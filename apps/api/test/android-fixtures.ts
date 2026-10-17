// Test-only transport. This file is never imported by the production entry point.
// databaseHarness refuses any cluster without the disposable localhost marker.
import { randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { isAbsolute, join } from 'node:path';
import { databaseHarness } from './integration/harness.ts';
import { routingFromEnvironment } from '../src/routing.ts';
import { registerRoadGraph } from '../src/road_graph.ts';
import { EvidenceRefreshWorker } from '../src/evidence_refresh.ts';
import type { EvidenceWorkerPool } from '../src/evidence_refresh.ts';
import type { PoolClient } from 'pg';
import { workerRoutingFromEnvironment, WorkerRouting } from '../src/worker_routing.ts';
import type { RouteInput } from '../src/routing.ts';
import { routeInput } from '../src/schemas.ts';
import { distanceMetres } from '../src/routing.ts';
import { placesFromEnvironment } from '../src/places.ts';
import { parseGraphManifest } from '../src/routing.ts';
import { readFile } from 'node:fs/promises';
import { registerAndroidSharingFixtures } from './android-sharing-fixtures.ts';

const places = await placesFromEnvironment(
  process.env,
  process.env.AWAAZ_ROUTING_MANIFEST
    ? parseGraphManifest(JSON.parse(await readFile(process.env.AWAAZ_ROUTING_MANIFEST, 'utf8')))
        .graphVersion
    : undefined,
);
const harness = await databaseHarness({
  ...(places ? { places } : {}),
  routingFactory: async (evidence) =>
    (await workerRoutingFromEnvironment(process.env, evidence, true)) ??
    (await routingFromEnvironment(process.env)),
});
let fixtures: Record<string, unknown> = {};
registerAndroidSharingFixtures(
  harness.app,
  harness.admin,
  () => (fixtures.alice as { id?: string } | undefined)?.id,
);
let closing = false;
let refreshWorker: EvidenceRefreshWorker | undefined;
let refreshLoop: Promise<void> | undefined;
const refreshController = new AbortController();
let seedCorridor: (input: RouteInput) => Promise<object>;
async function withWorker<T>(operation: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await harness.admin.connect();
  let discard = false;
  try {
    await client.query('SET ROLE awaaz_evidence');
    return await operation(client);
  } finally {
    try {
      await client.query('RESET ROLE');
    } catch {
      discard = true;
    }
    client.release(discard);
  }
}
const close = async () => {
  if (closing) return;
  closing = true;
  refreshController.abort();
  await refreshLoop;
  await refreshWorker?.close();
  await harness.close();
};
process.once('SIGINT', () => void close());
process.once('SIGTERM', () => void close());

try {
  const artifact = process.env.AWAAZ_ROAD_EDGES_FILE;
  if (!artifact)
    throw new Error(
      'Export the real Dhaka graph and set AWAAZ_ROAD_EDGES_FILE for the fixture publication pipeline',
    );
  const graph = await withWorker((client) => registerRoadGraph(client, artifact));
  const execute = promisify(execFile);
  harness.app.post<{ Body: RouteInput }>(
    '/__fixtures/reported-corridor',
    { schema: { body: routeInput } },
    async (request) => seedCorridor(request.body),
  );
  harness.app.post(
    '/__fixtures/location-dialog',
    { schema: { body: { type: 'object', properties: {}, additionalProperties: false } } },
    async (request, reply) => {
      // Native UI observations can exceed the production API's short idle
      // socket limit. This extension is confined to the disposable fixture.
      request.raw.socket.setTimeout(60_000);
      const cancellation = new AbortController();
      const abandoned = () => {
        if (!reply.raw.writableEnded) cancellation.abort();
      };
      reply.raw.once('close', abandoned);
      try {
        const adb =
          process.env.AWAAZ_TEST_ADB_PATH ??
          join(process.env.LOCALAPPDATA ?? '', 'Android', 'Sdk', 'platform-tools', 'adb.exe');
        const options = {
          timeout: 15_000,
          windowsHide: true,
          maxBuffer: 1024 * 1024,
          signal: cancellation.signal,
        };
        if (!isAbsolute(adb)) throw new Error('Supply an absolute test ADB path');
        const identity = await execute(adb, ['-s', 'emulator-5554', 'emu', 'avd', 'name'], options);
        if (
          !identity.stdout
            .split(/\r?\n/)
            .map((line) => line.trim())
            .includes('awaaz_dhaka_api36')
        )
          throw new Error('Unexpected test device');
        let clicked = false;
        for (let attempt = 0; attempt < 8; attempt++) {
          const windows = await execute(
            adb,
            ['-s', 'emulator-5554', 'shell', 'dumpsys', 'window'],
            options,
          );
          if (
            /mCurrentFocus=.*com\.google\.android\.gms\/com\.google\.android\.location\.settings\.LocationSettingsCheckerActivity/.test(
              windows.stdout,
            )
          ) {
            const hierarchyPath = '/sdcard/awaaz-location-' + randomUUID() + '.xml';
            const dumped = await execute(
              adb,
              ['-s', 'emulator-5554', 'shell', 'uiautomator', 'dump', hierarchyPath],
              options,
            );
            if (!dumped.stdout.includes('dumped to'))
              throw new Error('No fresh location dialog hierarchy');
            const hierarchy = await execute(
              adb,
              ['-s', 'emulator-5554', 'shell', 'cat', hierarchyPath],
              options,
            );
            const buttons = [...hierarchy.stdout.matchAll(/<node\b[^>]*>/g)]
              .map((node) => node[0])
              .filter(
                (node) =>
                  node.includes('resource-id="android:id/button1"') &&
                  node.includes('text="Turn on"') &&
                  node.includes('package="com.google.android.gms"') &&
                  node.includes('clickable="true"') &&
                  node.includes('enabled="true"'),
              );
            if (buttons.length !== 1)
              throw new Error('Expected the observed English location opt-in button');
            const bounds = /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(buttons[0]!);
            if (!bounds) throw new Error('Missing native location button bounds');
            await execute(
              adb,
              [
                '-s',
                'emulator-5554',
                'shell',
                'input',
                'tap',
                String(Math.floor((Number(bounds[1]) + Number(bounds[3])) / 2)),
                String(Math.floor((Number(bounds[2]) + Number(bounds[4])) / 2)),
              ],
              options,
            );
            clicked = true;
            break;
          }
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
        // Provide a fresh sample after the user's settings decision/provider startup.
        await execute(adb, ['-s', 'emulator-5554', 'emu', 'geo', 'fix', '90.38', '23.76'], options);
        return { synthetic: true, clicked };
      } finally {
        reply.raw.removeListener('close', abandoned);
      }
    },
  );
  harness.app.post(
    '/__fixtures/location',
    { schema: { body: { type: 'object', properties: {}, additionalProperties: false } } },
    async () => {
      const adb =
        process.env.AWAAZ_TEST_ADB_PATH ??
        join(process.env.LOCALAPPDATA ?? '', 'Android', 'Sdk', 'platform-tools', 'adb.exe');
      if (!isAbsolute(adb)) throw new Error('Supply an absolute test ADB path');
      const options = { timeout: 15_000, windowsHide: true, maxBuffer: 1024 * 1024 };
      const identity = await execute(adb, ['-s', 'emulator-5554', 'emu', 'avd', 'name'], options);
      if (
        !identity.stdout
          .split(/\r?\n/)
          .map((line) => line.trim())
          .includes('awaaz_dhaka_api36')
      )
        throw new Error('Unexpected test device');
      await execute(
        adb,
        ['-s', 'emulator-5554', 'shell', 'cmd', 'location', 'set-location-enabled', 'true'],
        options,
      );
      for (const permission of [
        'android.permission.ACCESS_COARSE_LOCATION',
        'android.permission.ACCESS_FINE_LOCATION',
      ]) {
        await execute(
          adb,
          ['-s', 'emulator-5554', 'shell', 'pm', 'grant', 'app.awaaz.awaaz', permission],
          options,
        );
      }
      await execute(adb, ['-s', 'emulator-5554', 'emu', 'geo', 'fix', '90.38', '23.76'], options);
      return { synthetic: true };
    },
  );
  harness.app.post<{ Body: { action: 'prepare' | 'onroute' | 'trace' | 'notification-stop' } }>(
    '/__fixtures/trip',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['action'],
          properties: {
            action: { type: 'string', enum: ['prepare', 'onroute', 'trace', 'notification-stop'] },
          },
        },
      },
    },
    async (request) => {
      // This controlled trace intentionally lasts longer than the production
      // API's ten-second connection idle limit. Extend only this fixture socket.
      request.raw.socket.setTimeout(90_000);
      const adb =
        process.env.AWAAZ_TEST_ADB_PATH ??
        join(process.env.LOCALAPPDATA ?? '', 'Android', 'Sdk', 'platform-tools', 'adb.exe');
      if (!isAbsolute(adb)) throw new Error('Supply an absolute test ADB path');
      const options = { timeout: 15_000, windowsHide: true, maxBuffer: 2 * 1024 * 1024 };
      const identity = await execute(adb, ['-s', 'emulator-5554', 'emu', 'avd', 'name'], options);
      if (
        !identity.stdout
          .split(/\r?\n/)
          .map((line) => line.trim())
          .includes('awaaz_dhaka_api36')
      )
        throw new Error('Unexpected test device');
      const shell = async (...args: string[]) =>
        execute(adb, ['-s', 'emulator-5554', 'shell', ...args], options);
      const geo = async (longitude: number, latitude: number) =>
        execute(
          adb,
          [
            '-s',
            'emulator-5554',
            'emu',
            'geo',
            'fix',
            String(longitude),
            String(latitude),
            '0',
            '8',
            '16',
          ],
          options,
        );
      if (request.body.action === 'prepare') {
        await shell('pm', 'grant', 'app.awaaz.awaaz', 'android.permission.POST_NOTIFICATIONS');
        await shell('cmd', 'location', 'set-location-enabled', 'true');
        for (const permission of ['ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION'])
          await shell('pm', 'grant', 'app.awaaz.awaaz', 'android.permission.' + permission);
        await geo(90.38, 23.76);
        return { synthetic: true };
      }
      const service = await shell('dumpsys', 'activity', 'services', 'app.awaaz.awaaz');
      if (
        !service.stdout.includes('TripMonitorService') ||
        !service.stdout.includes('isForeground=true')
      )
        throw new Error('Expected the real native foreground monitor');
      if (request.body.action === 'onroute') {
        for (let step = 0; step < 3; step++) {
          await geo(90.38 + step * 0.0001, 23.76);
          await new Promise((resolve) => setTimeout(resolve, 3000));
        }
        return { synthetic: true };
      }
      if (request.body.action === 'notification-stop') {
        type UiNode = { attributes: string; children: UiNode[] };
        const attribute = (node: UiNode, name: string) =>
          new RegExp('(?:^|\\s)' + name + '="([^"]*)"').exec(node.attributes)?.[1];
        const flatten = (node: UiNode): UiNode[] => [node, ...node.children.flatMap(flatten)];
        const hierarchy = async () => {
          await shell('uiautomator', 'dump', '/sdcard/awaaz-notification-hierarchy.xml');
          const xml = await shell('cat', '/sdcard/awaaz-notification-hierarchy.xml');
          const root: UiNode = { attributes: '', children: [] },
            stack = [root];
          for (const match of xml.stdout.matchAll(/<node\b[^>]*\/?>|<\/node>/g)) {
            const tag = match[0];
            if (tag === '</node>') {
              if (stack.length > 1) stack.pop();
              continue;
            }
            const node: UiNode = { attributes: tag, children: [] };
            stack[stack.length - 1]!.children.push(node);
            if (!tag.endsWith('/>')) stack.push(node);
          }
          const rows = flatten(root).filter(
            (node) =>
              ((attribute(node, 'class') ?? '').endsWith('ExpandableNotificationRow') ||
                (attribute(node, 'resource-id') ?? '').endsWith('/expandableNotificationRow')) &&
              flatten(node).some(
                (child) => attribute(child, 'text') === 'Awaaz · Test journey monitor',
              ),
          );
          if (rows.length !== 1) throw new Error('Expected one observed Awaaz notification row');
          return flatten(rows[0]!);
        };
        const tapNode = async (node: UiNode) => {
          if (
            attribute(node, 'package') !== 'com.android.systemui' ||
            attribute(node, 'enabled') !== 'true'
          )
            throw new Error('Unexpected notification action');
          const bounds = /^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/.exec(attribute(node, 'bounds') ?? '');
          if (
            !bounds ||
            Number(bounds[3]) <= Number(bounds[1]) ||
            Number(bounds[4]) <= Number(bounds[2])
          )
            throw new Error('Notification action is not visible');
          await shell(
            'input',
            'tap',
            String(Math.floor((Number(bounds[1]) + Number(bounds[3])) / 2)),
            String(Math.floor((Number(bounds[2]) + Number(bounds[4])) / 2)),
          );
        };
        await shell('cmd', 'statusbar', 'expand-notifications');
        try {
          let shadeFocused = false;
          const shadeDeadline = Date.now() + 8000;
          do {
            const focus = await shell('dumpsys', 'window');
            shadeFocused = /mCurrentFocus=Window\{[^\r\n]*(NotificationShade|StatusBar)/.test(
              focus.stdout,
            );
            if (shadeFocused) break;
            await new Promise((resolve) => setTimeout(resolve, 500));
          } while (Date.now() < shadeDeadline);
          if (!shadeFocused) throw new Error('Notification shade is not focused');
          let nodes = await hierarchy();
          let stops = nodes.filter((node) => attribute(node, 'text') === 'Stop monitoring');
          if (stops.length === 0) {
            const expand = nodes.filter(
              (node) =>
                /expand/i.test(attribute(node, 'content-desc') ?? '') &&
                attribute(node, 'clickable') === 'true',
            );
            if (expand.length !== 1)
              throw new Error('Expected one observed Awaaz expansion control');
            await tapNode(expand[0]!);
            nodes = await hierarchy();
            stops = nodes.filter((node) => attribute(node, 'text') === 'Stop monitoring');
          }
          if (stops.length !== 1) throw new Error('Expected one observed Awaaz Stop action');
          await tapNode(stops[0]!);
          return { synthetic: true, notificationStop: true };
        } catch (error) {
          // Fixed fixture UI diagnostics only; never log reports, identities or raw hierarchy.
          console.error(
            'Native notification fixture failed:',
            error instanceof Error ? error.message.slice(0, 160) : 'unknown',
          );
          throw error;
        } finally {
          await shell('cmd', 'statusbar', 'collapse');
          await shell('am', 'start', '-n', 'app.awaaz.awaaz/.MainActivity');
        }
      }
      const foreground = await shell('dumpsys', 'window');
      if (
        !/mCurrentFocus=Window\{[^\r\n]*app\.awaaz\.awaaz\/app\.awaaz\.awaaz\.MainActivity/.test(
          foreground.stdout,
        )
      )
        throw new Error('Awaaz must be visible before this controlled background test');
      let checkInNotification = false,
        screenOff = false;
      try {
        await shell('input', 'keyevent', '3');
        await shell('input', 'keyevent', '223');
        const asleepDeadline = Date.now() + 8000;
        do {
          const power = await shell('dumpsys', 'power');
          screenOff =
            /mWakefulness=Asleep/.test(power.stdout) &&
            /mWakefulnessChanging=false/.test(power.stdout) &&
            /mHalInteractiveModeEnabled=false/.test(power.stdout);
          if (screenOff) break;
          await new Promise((resolve) => setTimeout(resolve, 500));
        } while (Date.now() < asleepDeadline);
        if (!screenOff) throw new Error('Could not verify that the test device is asleep');
        for (let step = 0; step < 7; step++) {
          await geo(90.3802 + step * 0.0004, 23.7625);
          await new Promise((resolve) => setTimeout(resolve, 5000));
        }
        const notices = await shell('dumpsys', 'notification');
        checkInNotification =
          /NotificationRecord\([^\r\n]*pkg=app\.awaaz\.awaaz[^\r\n]*id=7102\b/.test(notices.stdout);
      } finally {
        await shell('input', 'keyevent', '224');
        await shell('wm', 'dismiss-keyguard');
        await shell('am', 'start', '-n', 'app.awaaz.awaaz/.MainActivity');
      }
      return { synthetic: true, screenOff, checkInNotification };
    },
  );
  harness.app.post<{ Body: { reportRequestId: string } }>(
    '/__fixtures/restart',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['reportRequestId'],
          properties: {
            reportRequestId: {
              type: 'string',
              pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            },
          },
        },
      },
    },
    async (request) => {
      // Test phase metadata only; fixture identities and DB remain unchanged
      // while the Android application process is stopped and restarted.
      fixtures.restartRequestId = request.body.reportRequestId;
      return { ready: true };
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
          properties: { name: { type: 'string', pattern: '^[a-z0-9-]{1,64}$' } },
        },
      },
    },
    async (request) => {
      const adb =
        process.env.AWAAZ_TEST_ADB_PATH ??
        join(process.env.LOCALAPPDATA ?? '', 'Android', 'Sdk', 'platform-tools', 'adb.exe');
      if (!isAbsolute(adb)) throw new Error('Supply an absolute test ADB path');
      const options = { timeout: 15_000, windowsHide: true, maxBuffer: 1024 * 1024 };
      const identity = await execute(adb, ['-s', 'emulator-5554', 'emu', 'avd', 'name'], options);
      if (
        !identity.stdout
          .split(/\r?\n/)
          .map((line) => line.trim())
          .includes('awaaz_dhaka_api36')
      )
        throw new Error('Unexpected test device');
      const activities = await execute(
        adb,
        ['-s', 'emulator-5554', 'shell', 'dumpsys', 'activity', 'activities'],
        options,
      );
      if (
        !/mResumedActivity:.*app\.awaaz\.awaaz|topResumedActivity=.*app\.awaaz\.awaaz/.test(
          activities.stdout,
        )
      )
        throw new Error('Awaaz must be in the foreground for a test screenshot');
      const windows = await execute(
        adb,
        ['-s', 'emulator-5554', 'shell', 'dumpsys', 'window'],
        options,
      );
      if (
        !/mCurrentFocus=Window\{[^\r\n]*app\.awaaz\.awaaz\/app\.awaaz\.awaaz\.MainActivity/.test(
          windows.stdout,
        )
      )
        throw new Error('A native window is covering Awaaz; screenshot evidence is invalid');
      const output = fileURLToPath(new URL('../../../.local/android-evidence/', import.meta.url));
      await mkdir(output, { recursive: true });
      await execute(
        adb,
        ['-s', 'emulator-5554', 'shell', 'screencap', '-p', '/sdcard/awaaz-checkpoint.png'],
        options,
      );
      await execute(
        adb,
        [
          '-s',
          'emulator-5554',
          'pull',
          '/sdcard/awaaz-checkpoint.png',
          join(output, request.body.name + '.png'),
        ],
        options,
      );
      return { captured: true };
    },
  );
  harness.app.get('/__fixtures', async (_request, reply) => {
    reply.header('Cache-Control', 'no-store');
    return fixtures;
  });
  const alice = await harness.user('Fixture Alice');
  const bob = await harness.user('Fixture Bob');
  const outsider = await harness.user('Fixture Outsider');
  // Test-only moderator, provisioned solely in the owned disposable database.
  const reviewer = await harness.user('Fixture Reviewer');
  await harness.admin.query('INSERT INTO awaaz_private.moderators(user_id) VALUES($1)', [
    reviewer.id,
  ]);
  const result = await harness.request(alice.token, 'POST', '/v1/reports', {
    clientRequestId: randomUUID(),
    category: 'lighting',
    description: 'SYNTHETIC TEST: lighting fixture, not a real road incident.',
    latitude: 23.7577,
    longitude: 90.389,
    observedAt: new Date().toISOString(),
  });
  if (result.statusCode !== 201 && result.statusCode !== 200)
    throw new Error('Report fixture setup failed: ' + result.statusCode + ' ' + result.body);
  const reportId = result.json().id as string;
  const approval = await harness.request(
    reviewer.token,
    'POST',
    `/v1/moderation/reports/${reportId}/reviews`,
    { clientRequestId: randomUUID(), decision: 'approve', reason: 'reviewed' },
  );
  if (approval.statusCode !== 201) throw new Error('Fixture approval failed');
  const candidates = await harness.request(
    reviewer.token,
    'GET',
    `/v1/moderation/reports/${reportId}/road-candidates?graphVersion=${graph.graphVersion}`,
  );
  if (candidates.statusCode !== 200 || !candidates.json().items.length)
    throw new Error('Fixture real graph association failed');
  // Explicit synthetic test selection; production never automatically chooses
  // the nearest candidate or treats this fixture as real incident evidence.
  const selected = candidates.json().items[0];
  const publication = await harness.request(
    reviewer.token,
    'POST',
    `/v1/moderation/reports/${reportId}/publications`,
    { clientRequestId: randomUUID(), graphVersion: graph.graphVersion, edgeId: selected.edgeId },
  );
  if (publication.statusCode !== 201) throw new Error('Fixture publication failed');
  const scopedPool: EvidenceWorkerPool = {
    connect: async () => {
      const client = await harness.admin.connect();
      try {
        await client.query('SET ROLE awaaz_evidence');
      } catch (error) {
        client.release(true);
        throw error;
      }
      return {
        query: (sql, values) => client.query(sql, values),
        release: async (discard) => {
          try {
            if (!discard) await client.query('RESET ROLE');
          } catch {
            discard = true;
          } finally {
            client.release(discard);
          }
        },
      };
    },
  };
  const output =
    harness.routing instanceof WorkerRouting
      ? harness.routing.artifacts
      : process.env.AWAAZ_EVIDENCE_OUTPUT_DIR ||
        join(fileURLToPath(new URL('../../../', import.meta.url)), '.local/evidence');
  const worker = (refreshWorker = new EvidenceRefreshWorker(
    scopedPool,
    graph.graphVersion,
    output,
    join(output, 'awaaz-evidence-fixture.health.json'),
  ));
  const refreshSnapshot = async () => {
    if (closing) throw new Error('Fixture is closing');
    // A background cycle may have captured the graph before the final fixture
    // publication. Validate live state, then retry once with a fresh cycle.
    for (let attempt = 0; attempt < 2; attempt++) {
      await worker.cycle();
      if (worker.health.status !== 'ready' || !worker.health.snapshotId) continue;
      try {
        await harness.stores.evidence.read(worker.health.snapshotId, 10000000);
        return;
      } catch {
        /* concurrent fixture publication invalidated the captured epoch */
      }
    }
    throw new Error('Synthetic evidence refresh unavailable; safety remains unknown');
  };
  await refreshSnapshot();
  const corridorWitness = await harness.user('Fixture corridor witness');
  const seededRequests = new Set<string>();
  seedCorridor = async (input) => {
    const router = harness.routing;
    if (!(router instanceof WorkerRouting))
      throw new Error('Private evidence worker is required for corridor fixtures');
    const signature = JSON.stringify([input.origin, input.destination, input.mode]);
    if (seededRequests.has(signature)) return { seeded: true, replayed: true };
    if (seededRequests.size >= 1)
      throw new Error('Restart fixtures before seeding another corridor');
    const worker = await router.startup;
    const path = await worker.route(input.origin, input.destination, input.mode);
    const length = (edge: (typeof path.edges)[number]) =>
      path.points
        .slice(edge.first, edge.last + 1)
        .reduce(
          (total, p, i, a) =>
            i
              ? total +
                distanceMetres(
                  { latitude: a[i - 1]![0], longitude: a[i - 1]![1] },
                  { latitude: p[0], longitude: p[1] },
                )
              : total,
          0,
        );
    const edges = path.edges
      .slice(5, -5)
      .sort((a, b) => length(b) - length(a))
      .slice(0, 10);
    for (const edge of edges) {
      const mid = Math.floor((edge.first + edge.last) / 2),
        a = path.points[mid]!,
        b = path.points[Math.min(mid + 1, edge.last)]!;
      const submitted = await harness.request(corridorWitness.token, 'POST', '/v1/reports', {
        clientRequestId: randomUUID(),
        category: 'lighting',
        description: 'SYNTHETIC corridor observation for Android route-choice verification only.',
        latitude: (a[0] + b[0]) / 2,
        longitude: (a[1] + b[1]) / 2,
        observedAt: new Date().toISOString(),
      });
      if (submitted.statusCode !== 201) throw new Error('Synthetic corridor submission failed');
      const rid = submitted.json().id;
      const reviewed = await harness.request(
        reviewer.token,
        'POST',
        `/v1/moderation/reports/${rid}/reviews`,
        { clientRequestId: randomUUID(), decision: 'approve', reason: 'reviewed' },
      );
      if (reviewed.statusCode !== 201) throw new Error('Synthetic corridor review failed');
      const published = await harness.request(
        reviewer.token,
        'POST',
        `/v1/moderation/reports/${rid}/publications`,
        { clientRequestId: randomUUID(), graphVersion: graph.graphVersion, edgeId: edge.edgeId },
      );
      if (published.statusCode !== 201) throw new Error('Synthetic corridor publication failed');
    }
    seededRequests.add(signature);
    await refreshSnapshot();
    return { seeded: true, synthetic: true, edges: edges.length };
  };
  refreshLoop = worker.run(refreshController.signal).catch(() => {
    console.log('Synthetic evidence worker stopped unexpectedly; safety remains unknown.');
  });
  fixtures = {
    alice,
    bob,
    outsider,
    reviewer,
    reportId,
    graphVersion: graph.graphVersion,
    edgeId: selected.edgeId,
    publicSummary: 'Reviewed report of poor lighting nearby.',
    synthetic: true,
    realGraphAssociation: true,
  };
  await harness.app.listen({ host: '127.0.0.1', port: 3031 });
  console.log('Disposable Android fixture API ready on 127.0.0.1:3031 (synthetic data only).');
} catch (error) {
  await close();
  throw error;
}
