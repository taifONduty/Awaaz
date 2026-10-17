import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { buildServer } from '../src/server.ts';
import { SharingCleanup } from '../src/sharing.ts';
import type { SharingStore, ShareControl } from '../src/sharing.ts';
import { payloadHash } from '../src/security.ts';

test('sharing routes authenticate before SQL, canonicalize consent and enforce schemas, serialization and account limits', async (t) => {
  const owner = randomUUID(),
    recipient = randomUUID(),
    another = randomUUID(),
    circleId = randomUUID(),
    id = randomUUID();
  const timestamp = new Date().toISOString();
  const control: ShareControl = {
    id,
    circleId,
    startedAt: timestamp,
    expiresAt: timestamp,
    status: 'active',
    sequence: 0,
    recipients: [{ userId: recipient, active: true }],
  };
  const calls: { op: string; args: unknown[] }[] = [];
  const store = new Proxy({} as SharingStore, {
    get:
      (_target, op: string) =>
      async (...args: unknown[]) => {
        if (op === 'cleanupExpired') return { positionsDeleted: 0, grantsDeleted: 0 };
        calls.push({ op, args });
        if (op === 'create')
          return { ...control, replayed: false, privateValue: 'PRIVATE', latitude: 23.76 };
        if (op === 'current') return { share: control };
        if (op === 'incoming') return { items: [], nextCursor: null };
        if (op === 'position')
          return {
            shareId: id,
            sequence: 1,
            acceptedAt: timestamp,
            expiresAt: timestamp,
            replayed: false,
            privateValue: 'PRIVATE',
          };
        return control;
      },
  });
  const app = await buildServer({
    sharing: store,
    verifyToken: async (token) => (token === 'valid' ? { id: owner, phoneVerified: false } : null),
    reports: {
      create: async () => {
        throw Error('unused');
      },
    },
  });
  t.after(() => app.close());
  const body = {
    clientRequestId: randomUUID(),
    circleId,
    recipientIds: [recipient],
    durationSeconds: 600,
  };
  const position = {
    sequence: 1,
    latitude: 23.76,
    longitude: 90.38,
    accuracyMetres: 12,
    capturedAt: timestamp,
  };
  const paths = [
    ['POST', '/v1/shares', body],
    ['GET', '/v1/me/share'],
    ['GET', `/v1/share-requests/${randomUUID()}`],
    ['GET', '/v1/shared-trips'],
    ['GET', `/v1/shares/${id}`],
    ['PUT', `/v1/shares/${id}/position`, position],
    ['DELETE', `/v1/shares/${id}`],
    ['DELETE', `/v1/shares/${id}/recipients/${recipient}`],
  ] as const;
  for (const [method, url, payload] of paths) {
    const denied = await app.inject({ method, url, ...(payload ? { payload } : {}) });
    assert.equal(denied.statusCode, 401, denied.body);
  }
  assert.equal(calls.length, 0);
  const headers = { authorization: 'Bearer valid' };
  const created = await app.inject({
    method: 'POST',
    url: '/v1/shares',
    headers,
    payload: {
      ...body,
      circleId: circleId.toUpperCase(),
      recipientIds: [another.toUpperCase(), recipient.toUpperCase()],
    },
  });
  assert.equal(created.statusCode, 201, created.body);
  assert.equal(created.headers['cache-control'], 'no-store');
  assert.ok(!created.body.includes('PRIVATE'));
  assert.ok(!created.body.includes('latitude'));
  assert.equal(calls[0]?.args[0], owner);
  assert.deepEqual(
    (calls[0]?.args[1] as { recipientIds: string[] }).recipientIds,
    [recipient, another].sort(),
  );
  assert.equal(
    calls[0]?.args[2],
    payloadHash(['trip-share.create.v1', circleId, [recipient, another].sort(), 600]),
  );
  const before = calls.length;
  for (const invalid of [
    { ...body, recipientIds: [recipient, recipient.toUpperCase()] },
    { ...body, recipientIds: [owner] },
    { ...body, ownerId: another },
    { ...body, durationSeconds: 299 },
    { ...body, durationSeconds: '600' },
    { ...body, recipientIds: Array.from({ length: 11 }, () => randomUUID()) },
  ]) {
    assert.equal(
      (await app.inject({ method: 'POST', url: '/v1/shares', headers, payload: invalid }))
        .statusCode,
      400,
    );
  }
  for (const suffix of [
    '?limit=51',
    '?limit=0',
    '?limit=1.5',
    '?after=broken',
    '?ownerId=' + owner,
  ]) {
    assert.equal(
      (await app.inject({ method: 'GET', url: '/v1/shared-trips' + suffix, headers })).statusCode,
      400,
    );
  }
  assert.equal(calls.length, before);
  const updated = await app.inject({
    method: 'PUT',
    url: `/v1/shares/${id}/position`,
    headers,
    payload: { ...position, capturedAt: timestamp.replace('Z', '+00:00') },
  });
  assert.equal(updated.statusCode, 200, updated.body);
  assert.ok(!updated.body.includes('PRIVATE'));
  assert.equal(
    calls.at(-1)?.args[3],
    payloadHash(['trip-share.position.v1', 1, 23.76, 90.38, 12, timestamp]),
  );
  let throttled = false;
  for (let i = 0; i < 121; i++) {
    const r = await app.inject({ method: 'GET', url: '/v1/me/share', headers });
    if (r.statusCode === 429) {
      throttled = true;
      break;
    }
    assert.equal(r.statusCode, 200, r.body);
  }
  assert.ok(throttled, 'sharing reads must run the common authenticated-account limiter');
});

test('sharing retention coalesces work, readiness ages on failure, and shutdown waits for the owned request', async () => {
  let calls = 0,
    now = 0,
    fail = false;
  let release: () => void = () => {};
  let held: Promise<void> | undefined = new Promise((resolve) => {
    release = resolve;
  });
  const store = {
    cleanupExpired: async () => {
      calls++;
      await held;
      if (fail) throw Error('PRIVATE');
      return { positionsDeleted: 0, grantsDeleted: 0 };
    },
  } as SharingStore;
  const cleanup = new SharingCleanup(store, () => now);
  const starting = cleanup.start();
  const same = cleanup.run();
  assert.equal(calls, 1);
  assert.equal(cleanup.ready(), false);
  release();
  await starting;
  await same;
  held = undefined;
  assert.equal(cleanup.ready(), true);
  now = 90_001;
  fail = true;
  await cleanup.run();
  assert.equal(cleanup.ready(), false);
  fail = false;
  await cleanup.run();
  assert.equal(cleanup.ready(), true);
  held = new Promise((resolve) => {
    release = resolve;
  });
  const running = cleanup.run();
  let closed = false;
  const closing = cleanup.close().then(() => {
    closed = true;
  });
  await Promise.resolve();
  assert.equal(closed, false);
  release();
  await running;
  await closing;
  assert.equal(cleanup.ready(), false);
  const endedCalls = calls;
  await cleanup.run();
  assert.equal(calls, endedCalls);
});
