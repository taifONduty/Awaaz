// Native sharing has no routing dependency. Keep the real API/SQL boundary,
// while leaving the large routing graph/Java worker out of this AVD cycle.
import { databaseHarness } from './integration/harness.ts';
import { registerAndroidSharingFixtures } from './android-sharing-fixtures.ts';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { join, isAbsolute } from 'node:path';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const harness = await databaseHarness();
let traceSequence = 0;
const traceIds = new WeakMap<object, number>();
const traced = (route?: string) =>
  route?.startsWith('/v1/shares') ||
  route?.startsWith('/v1/share-devices') ||
  route?.startsWith('/v1/incidents') ||
  route?.startsWith('/v1/incident-requests') ||
  route?.startsWith('/v1/me');
harness.app.addHook('onRequest', async (request) => {
  if (traced(request.routeOptions.url)) {
    traceIds.set(request, ++traceSequence);
    console.log(
      `Fixture HTTP start ${traceSequence} ${request.method} ${request.routeOptions.url}`,
    );
  }
});
// Fixture-only timing observation. Never log headers, bodies or actual paths.
harness.app.addHook('onResponse', async (request, reply) => {
  const route = request.routeOptions.url;
  if (traced(route)) {
    console.log(
      `Fixture HTTP end ${traceIds.get(request)} ${request.method} ${route} ${reply.statusCode} ${Math.round(reply.elapsedTime)}ms`,
    );
  }
});
let fixtures: {
  synthetic: boolean;
  mode: string;
  alice?: { id: string; token: string };
  bob?: { id: string; token: string };
} = { synthetic: true, mode: 'native-sharing' };
registerAndroidSharingFixtures(harness.app, harness.admin, () => fixtures.alice?.id);
const execute = promisify(execFile);
async function device() {
  const adb =
    process.env.AWAAZ_TEST_ADB_PATH ??
    join(process.env.LOCALAPPDATA ?? '', 'Android', 'Sdk', 'platform-tools', 'adb.exe');
  if (!isAbsolute(adb)) throw new Error('Expected absolute ADB path');
  const options = { timeout: 15_000, windowsHide: true, maxBuffer: 2 * 1024 * 1024 };
  const identity = await execute(adb, ['-s', 'emulator-5554', 'emu', 'avd', 'name'], options);
  if (!identity.stdout.split(/\r?\n/).some((line) => line.trim() === 'awaaz_dhaka_api36'))
    throw new Error('Unexpected AVD');
  return {
    adb,
    options,
    shell: (...args: string[]) => execute(adb, ['-s', 'emulator-5554', 'shell', ...args], options),
  };
}
let pulseTimer: NodeJS.Timeout | undefined;
let pulseWork: Promise<void> | undefined;
async function stopPulse() {
  if (pulseTimer) clearInterval(pulseTimer);
  pulseTimer = undefined;
  await pulseWork;
}
function startPulse() {
  const until = Date.now() + 180_000;
  // Simulate a stationary GPS receiver producing fresh fixes. A single setup
  // fix can expire before the debug UI starts on a memory-constrained host.
  pulseTimer = setInterval(() => {
    if (Date.now() >= until) {
      if (pulseTimer) clearInterval(pulseTimer);
      pulseTimer = undefined;
      return;
    }
    if (pulseWork) return;
    pulseWork = (async () => {
      const { adb, options } = await device();
      await execute(
        adb,
        ['-s', 'emulator-5554', 'emu', 'geo', 'fix', '90.38', '23.76', '0', '8', '16'],
        options,
      );
    })()
      .catch(() => {
        if (pulseTimer) clearInterval(pulseTimer);
        pulseTimer = undefined;
        console.log('Fixture setup GPS pulse stopped after device observation failed.');
      })
      .finally(() => {
        pulseWork = undefined;
      });
  }, 3000);
  pulseTimer.unref();
}
harness.app.addHook('preHandler', async (request) => {
  // Wait for any final setup fix BEFORE the background observer records its
  // marker and distinct HAL fix. Setup input must not overwrite that proof.
  if (request.routeOptions.url === '/__fixtures/share-trip') await stopPulse();
});
harness.app.get('/__fixtures', async () => fixtures);
harness.app.post<{ Body: { action: 'prepare' } }>(
  '/__fixtures/trip',
  {
    schema: {
      body: {
        type: 'object',
        additionalProperties: false,
        required: ['action'],
        properties: { action: { type: 'string', const: 'prepare' } },
      },
    },
  },
  async () => {
    await stopPulse();
    const { adb, shell, options } = await device();
    await shell('pm', 'grant', 'app.awaaz.awaaz', 'android.permission.POST_NOTIFICATIONS');
    await shell('cmd', 'location', 'set-location-enabled', 'true');
    for (const permission of ['ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION'])
      await shell('pm', 'grant', 'app.awaaz.awaaz', 'android.permission.' + permission);
    await execute(
      adb,
      ['-s', 'emulator-5554', 'emu', 'geo', 'fix', '90.38', '23.76', '0', '8', '16'],
      options,
    );
    startPulse();
    return { synthetic: true };
  },
);
harness.app.post<{ Body: { name: string } }>(
  '/__fixtures/checkpoint',
  {
    schema: {
      body: {
        type: 'object',
        additionalProperties: false,
        required: ['name'],
        properties: {
          name: {
            type: 'string',
            pattern: '^(native-sharing-(active|stopped)|sos-(saved|received|closed|bangla))$',
          },
        },
      },
    },
  },
  async (request) => {
    const { adb, shell, options } = await device();
    const windows = (await shell('dumpsys', 'window')).stdout;
    if (
      !/mCurrentFocus=Window\{[^\r\n]*app\.awaaz\.awaaz\/app\.awaaz\.awaaz\.MainActivity/.test(
        windows,
      )
    )
      throw new Error('Awaaz must be visible without a covering dialog');
    const output = fileURLToPath(new URL('../../../.local/android-evidence/', import.meta.url));
    await mkdir(output, { recursive: true });
    await shell('screencap', '-p', '/sdcard/awaaz-native-sharing-checkpoint.png');
    await execute(
      adb,
      [
        '-s',
        'emulator-5554',
        'pull',
        '/sdcard/awaaz-native-sharing-checkpoint.png',
        join(output, request.body.name + '.png'),
      ],
      options,
    );
    return { captured: true };
  },
);
let closing = false;
const close = async () => {
  if (closing) return;
  closing = true;
  await stopPulse();
  await harness.close();
};
process.once('SIGINT', () => void close());
process.once('SIGTERM', () => void close());
try {
  fixtures = {
    synthetic: true,
    mode: 'native-sharing',
    alice: await harness.user('Native fixture Alice'),
    bob: await harness.user('Native fixture Bob'),
  };
  await harness.app.listen({ host: '127.0.0.1', port: 3031 });
  console.log(
    'Disposable native-sharing fixture API ready on 127.0.0.1:3031; real SQL/API, no routing worker.',
  );
} catch (error) {
  await close();
  throw error;
}
