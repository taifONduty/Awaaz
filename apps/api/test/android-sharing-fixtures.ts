// Isolated AVD/SQL observations only; never imported by the production server.
import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';
import { isAbsolute, join } from 'node:path';

export function registerAndroidSharingFixtures(
  app: FastifyInstance,
  admin: Pool,
  owner: () => string | undefined,
) {
  const execute = promisify(execFile);
  app.addHook('onRequest', async (request) => {
    if (request.routeOptions.url?.startsWith('/__fixtures')) request.raw.socket.setTimeout(90_000);
  });
  let dropStopFor: string | null = null;
  const stopRequests = new Map<string, number>();
  // Observe the actual HTTP exchange, independent of when Fastify compiled a
  // route's lifecycle hooks. Drop only after its SQL-backed 200 reaches end().
  app.server.prependListener('request', (request, response) => {
    if (request.method !== 'DELETE') return;
    const id = /^\/v1\/share-devices\/([0-9a-f-]{36})$/.exec(request.url ?? '')?.[1];
    if (!id || !stopRequests.has(id)) return;
    stopRequests.set(id, (stopRequests.get(id) ?? 0) + 1);
    const end = response.end;
    response.end = ((...args: unknown[]) => {
      if (dropStopFor === id && response.statusCode === 200) {
        dropStopFor = null;
        response.destroy();
        console.log('Native sharing fixture discarded one committed stop acknowledgement.');
        return response;
      }
      return Reflect.apply(end, response, args);
    }) as typeof response.end;
  });
  app.addHook('onError', async (request, _reply, error) => {
    if (request.routeOptions.url?.startsWith('/__fixtures'))
      console.log('Native sharing fixture failed: ' + error.message);
  });
  app.addHook('onSend', async (request, reply, payload) => {
    // Fixture calls can surround a long first-frame/JIT or screen-off action.
    // Do not leave a pooled idle fixture socket for the next startup command.
    // Production /v1 connection lifetimes remain unchanged.
    if (request.routeOptions.url?.startsWith('/__fixtures/')) reply.header('connection', 'close');
    if (request.routeOptions.url === '/__fixtures') reply.header('connection', 'close');
    return payload;
  });
  app.post<{ Body: { action: 'background-fix' | 'notification-stop' | 'wake'; shareId?: string } }>(
    '/__fixtures/share-trip',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['action'],
          properties: {
            action: { type: 'string', enum: ['background-fix', 'notification-stop', 'wake'] },
            shareId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (request, reply) => {
      request.raw.socket.setTimeout(90_000);
      const cancellation = new AbortController();
      reply.raw.once('close', () => {
        if (!reply.raw.writableEnded) cancellation.abort();
      });
      const adb =
        process.env.AWAAZ_TEST_ADB_PATH ??
        join(process.env.LOCALAPPDATA ?? '', 'Android', 'Sdk', 'platform-tools', 'adb.exe');
      if (!isAbsolute(adb)) throw new Error('Expected an absolute ADB path');
      const options = {
        timeout: 15_000,
        windowsHide: true,
        maxBuffer: 2 * 1024 * 1024,
        signal: cancellation.signal,
      };
      const identity = await execute(adb, ['-s', 'emulator-5554', 'emu', 'avd', 'name'], options);
      if (!identity.stdout.split(/\r?\n/).some((line) => line.trim() === 'awaaz_dhaka_api36'))
        throw new Error('Unexpected AVD');
      const shell = (...args: string[]) =>
        execute(adb, ['-s', 'emulator-5554', 'shell', ...args], options);
      const wake = async () => {
        await shell('input', 'keyevent', '224');
        await shell('wm', 'dismiss-keyguard');
        await shell('cmd', 'statusbar', 'collapse');
        await shell('am', 'start', '-n', 'app.awaaz.awaaz/.MainActivity');
      };
      if (request.body.action === 'wake') {
        await wake();
        return { synthetic: true };
      }
      const id = request.body.shareId;
      if (!id || !owner()) throw new Error('Expected the fixture owner and share');
      const owned = await admin.query(
        'SELECT id FROM awaaz_private.trip_shares WHERE id=$1 AND owner_id=$2',
        [id, owner()],
      );
      if (!owned.rows.length) throw new Error('Not a share owned by the synthetic account');
      const foregroundService = async () => {
        const services = (await shell('dumpsys', 'activity', 'services', 'app.awaaz.awaaz')).stdout;
        return services
          .split('* ServiceRecord{')
          .some(
            (block) =>
              block.split('\n')[0]?.includes('ShareLocationService') &&
              /\bisForeground=true\b/.test(block),
          );
      };
      if (!(await foregroundService()))
        throw new Error('Expected the actual native sharing foreground service');
      const pid = (await shell('pidof', 'app.awaaz.awaaz')).stdout.trim();
      if (!/^\d+$/.test(pid)) throw new Error('Expected one Awaaz process');
      if (request.body.action === 'background-fix') {
        let completed = false;
        try {
          const focus = (await shell('dumpsys', 'window')).stdout;
          if (
            !/mCurrentFocus=Window\{[^\r\n]*app\.awaaz\.awaaz\/app\.awaaz\.awaaz\.MainActivity/.test(
              focus,
            )
          )
            throw new Error('Awaaz must start visibly');
          await shell('input', 'keyevent', '3');
          await shell('input', 'keyevent', '223');
          let screenOff = false;
          const asleepUntil = Date.now() + 8000;
          do {
            const power = (await shell('dumpsys', 'power')).stdout;
            screenOff =
              /mWakefulness=Asleep/.test(power) &&
              /mWakefulnessChanging=false/.test(power) &&
              /mHalInteractiveModeEnabled=false/.test(power);
            if (screenOff) break;
            await new Promise((resolve) => setTimeout(resolve, 500));
          } while (Date.now() < asleepUntil && !cancellation.signal.aborted);
          if (!screenOff) throw new Error('Screen-off state was not verified');
          const marker = (await admin.query('SELECT clock_timestamp() AS marker')).rows[0].marker;
          const until = Date.now() + 45_000;
          do {
            await execute(
              adb,
              ['-s', 'emulator-5554', 'emu', 'geo', 'fix', '90.38123', '23.76234', '0', '8', '16'],
              options,
            );
            await new Promise((resolve) => setTimeout(resolve, 2500));
            const point = await admin.query(
              'SELECT sequence FROM awaaz_private.trip_share_positions WHERE share_id=$1 AND abs(latitude-23.76234)<0.00001 AND abs(longitude-90.38123)<0.00001 AND accepted_at>=$2',
              [id, marker],
            );
            if (point.rows.length) {
              const power = (await shell('dumpsys', 'power')).stdout;
              const stillAsleep =
                /mWakefulness=Asleep/.test(power) && /mHalInteractiveModeEnabled=false/.test(power);
              const sameProcess = (await shell('pidof', 'app.awaaz.awaaz')).stdout.trim() === pid;
              const nativeForeground = await foregroundService();
              if (!stillAsleep || !sameProcess || !nativeForeground)
                throw new Error('Native/screen-off observation changed');
              completed = true;
              console.log(
                'Native sharing fixture verified a new point while asleep in the same foreground-service process.',
              );
              return {
                synthetic: true,
                screenOff: true,
                serverPositionWhileAsleep: true,
                sameProcess,
                nativeForeground,
                sequence: point.rows[0].sequence,
              };
            }
          } while (Date.now() < until && !cancellation.signal.aborted);
          throw new Error('No new native position reached PostgreSQL while asleep');
        } finally {
          if (!completed) await wake();
        }
      }
      type Node = { tag: string; children: Node[] };
      const attribute = (node: Node, name: string) =>
        new RegExp('(?:^|\\s)' + name + '="([^"]*)"').exec(node.tag)?.[1];
      const flatten = (node: Node): Node[] => [node, ...node.children.flatMap(flatten)];
      const hierarchy = async () => {
        const file = '/sdcard/awaaz-share-notice-' + randomUUID() + '.xml';
        const dumped = await execute(
          adb,
          ['-s', 'emulator-5554', 'shell', 'uiautomator', 'dump', file],
          { ...options, timeout: 30_000 },
        );
        if (!dumped.stdout.includes('dumped to'))
          throw new Error('Fresh native hierarchy is unavailable');
        const xml = (await shell('cat', file)).stdout;
        const root: Node = { tag: '', children: [] },
          stack = [root];
        for (const match of xml.matchAll(/<node\b[^>]*\/?>|<\/node>/g)) {
          const tag = match[0];
          if (tag === '</node>') {
            if (stack.length > 1) stack.pop();
            continue;
          }
          const node: Node = { tag, children: [] };
          stack[stack.length - 1]!.children.push(node);
          if (!tag.endsWith('/>')) stack.push(node);
        }
        const rows = flatten(root).filter(
          (node) =>
            ((attribute(node, 'class') ?? '').endsWith('ExpandableNotificationRow') ||
              (attribute(node, 'resource-id') ?? '').endsWith('/expandableNotificationRow')) &&
            flatten(node).some((child) => attribute(child, 'text') === 'Location sharing is on'),
        );
        if (rows.length !== 1) throw new Error('Expected one observed Awaaz sharing notification');
        return flatten(rows[0]!);
      };
      const tap = async (node: Node) => {
        const bounds = /^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/.exec(attribute(node, 'bounds') ?? '');
        if (!bounds || attribute(node, 'enabled') !== 'true')
          throw new Error('Native control has no usable observed bounds');
        const [left, top, right, bottom] = bounds.slice(1).map(Number) as [
          number,
          number,
          number,
          number,
        ];
        if (right <= left || bottom <= top) throw new Error('Invalid observed native bounds');
        await shell(
          'input',
          'tap',
          String(Math.round((left + right) / 2)),
          String(Math.round((top + bottom) / 2)),
        );
      };
      try {
        await shell('input', 'keyevent', '224');
        await shell('wm', 'dismiss-keyguard');
        await shell('cmd', 'statusbar', 'expand-notifications');
        let nodes = await hierarchy();
        if (!nodes.some((node) => attribute(node, 'text') === 'Stop sharing')) {
          const expand = nodes.find((node) =>
            (attribute(node, 'resource-id') ?? '').endsWith('/expand_button'),
          );
          if (!expand) throw new Error('Sharing notification cannot be expanded');
          await tap(expand);
          nodes = await hierarchy();
        }
        const buttons = nodes.filter((node) => attribute(node, 'text') === 'Stop sharing');
        if (buttons.length !== 1) throw new Error('Expected one observed Stop sharing action');
        dropStopFor = id;
        stopRequests.set(id, 0);
        console.log('Native sharing fixture observed the notification Stop sharing control.');
        await tap(buttons[0]!);
        // Ordinary JobScheduler retry backoff starts at 30 seconds. This wait
        // observes delivery without forcing a job or changing its policy.
        const until = Date.now() + 45_000;
        do {
          const stopped = await admin.query(
            'SELECT ended_at IS NOT NULL AS stopped FROM awaaz_private.trip_shares WHERE id=$1',
            [id],
          );
          if (
            stopped.rows[0]?.stopped &&
            !(await foregroundService()) &&
            (stopRequests.get(id) ?? 0) >= 2
          )
            return {
              synthetic: true,
              notificationAction: true,
              remoteStopped: true,
              nativeInactive: true,
              lostStopAck: dropStopFor !== id,
              stopReplayed: (stopRequests.get(id) ?? 0) >= 2,
              sameProcess: (await shell('pidof', 'app.awaaz.awaaz')).stdout.trim() === pid,
            };
          await new Promise((resolve) => setTimeout(resolve, 500));
        } while (Date.now() < until && !cancellation.signal.aborted);
        throw new Error('Notification stop was not acknowledged by the server');
      } finally {
        if (dropStopFor === id) dropStopFor = null;
        stopRequests.delete(id);
        await wake();
      }
    },
  );
}
