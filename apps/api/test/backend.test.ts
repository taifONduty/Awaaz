import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { buildServer } from '../src/server.ts';
import { postgresStores, createDatabasePool } from '../src/postgres.ts';
import { inviteTokenFactory, tokenHash, encodeCursor, decodeCursor } from '../src/security.ts';
import { configuration } from '../src/config.ts';
import type { SqlExecutor } from '../src/postgres.ts';
import type { ReportInput } from '../src/contracts.ts';

const actor = randomUUID(),
  circleId = randomUUID(),
  recipient = randomUUID(),
  inviteId = randomUUID();
const timestamp = new Date().toISOString();
const profile = {
  id: actor,
  displayName: 'PRIVATE_NAME',
  locale: 'en',
  adultAttested: true,
  createdAt: timestamp,
};
const circle = { id: circleId, name: 'PRIVATE_CIRCLE', ownerId: actor, createdAt: timestamp };
const report: ReportInput = {
  clientRequestId: randomUUID(),
  category: 'lighting',
  description: 'PRIVATE_REPORT_TEXT_NOT_FOR_LOGGING',
  latitude: 23.76,
  longitude: 90.38,
  observedAt: timestamp,
};
async function setup(logger?: { stream: { write: (message: string) => void }; level: string }) {
  const calls: { sql: string; values: unknown[] }[] = [];
  const db: SqlExecutor = {
    query: async (sql, values = []) => {
      calls.push({ sql, values });
      if (sql.includes('cleanup_trip_sharing() AS result'))
        return { rows: [{ result: { positionsDeleted: 0, grantsDeleted: 0 } }] };
      const op = values[1];
      const result =
        op === 'get_block'
          ? {
              userId: recipient,
              blocked: false,
              version: 0,
              changedAt: null,
              privateInfo: 'PRIVATE_INTERNAL',
            }
          : op === 'set_block'
            ? {
                userId: recipient,
                blocked: true,
                version: 1,
                changedAt: timestamp,
                replayed: false,
                privateInfo: 'PRIVATE_INTERNAL',
              }
            : op === 'list_blocks'
              ? {
                  items: [
                    {
                      userId: recipient,
                      displayName: 'Known contact',
                      version: 1,
                      blockedAt: timestamp,
                    },
                  ],
                  nextCursor: null,
                }
              : op === 'get_profile' || op === 'put_profile'
                ? { ...profile, tokenHash: 'PRIVATE_HASH', phone: 'PRIVATE_PHONE' }
                : op === 'get_circle'
                  ? { ...circle, members: [], privateInfo: 'PRIVATE_INTERNAL' }
                  : op === 'create_invite'
                    ? {
                        id: inviteId,
                        circleId,
                        recipientId: recipient,
                        expiresAt: timestamp,
                        status: 'pending',
                        replayed: false,
                        tokenHash: 'PRIVATE_HASH',
                      }
                    : op === 'create_report'
                      ? { id: randomUUID(), status: 'pending', replayed: false }
                      : op === 'list_published_events'
                        ? { items: [] }
                        : op === 'list_own_reports'
                          ? { items: [], next: null }
                          : { items: [] };
      return { rows: [{ result }] };
    },
  };
  const stores = postgresStores(db);
  const app = await buildServer(
    {
      ...stores,
      inviteToken: inviteTokenFactory('12'.repeat(32)),
      verifyToken: async (token) =>
        token === 'valid' || token === 'PRIVATE_BEARER_TOKEN'
          ? { id: actor, phoneVerified: true }
          : null,
    },
    { allowedOrigins: ['http://127.0.0.1:8765'], ...(logger ? { logger } : {}) },
  );
  await app.ready();
  calls.length = 0;
  return { app, calls };
}
const headers = { authorization: 'Bearer valid' };

test('shared IPs do not merge report/account quotas and both authenticated limits run', async (t) => {
  const second = randomUUID();
  const app = await buildServer({
    verifyToken: async (token) => ({
      id: token === 'second' ? second : actor,
      phoneVerified: true,
    }),
    reports: { create: async () => ({ id: randomUUID(), status: 'pending', replayed: false }) },
    people: postgresStores({ query: async () => ({ rows: [{ result: profile }] }) }).people,
    inviteToken: inviteTokenFactory('12'.repeat(32)),
  });
  t.after(() => app.close());
  const send = (token: string) =>
    app.inject({
      method: 'POST',
      url: '/v1/reports',
      headers: { authorization: 'Bearer ' + token },
      payload: { ...report, clientRequestId: randomUUID() },
    });
  for (let i = 0; i < 20; i++) assert.equal((await send('first')).statusCode, 201);
  const blocked = await send('first');
  assert.equal(blocked.statusCode, 429);
  assert.ok(Number(blocked.headers['retry-after']) > 0);
  for (let i = 0; i < 20; i++) assert.equal((await send('second')).statusCode, 201);
  // 21 report attempts plus 99 reads exhaust the first account's 120/minute.
  for (let i = 0; i < 99; i++)
    assert.equal(
      (
        await app.inject({
          method: 'GET',
          url: '/v1/me',
          headers: { authorization: 'Bearer first' },
        })
      ).statusCode,
      200,
    );
  assert.equal(
    (await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: 'Bearer first' } }))
      .statusCode,
    429,
  );
  assert.equal(
    (
      await app.inject({
        method: 'GET',
        url: '/v1/me',
        headers: { authorization: 'Bearer second' },
      })
    ).statusCode,
    200,
  );
  assert.equal((await app.inject('/health')).statusCode, 200);
});

test('every account/circle/community route requires a verified Auth session', async (t) => {
  const { app, calls } = await setup();
  t.after(() => app.close());
  for (const [method, url, payload] of [
    ['GET', '/v1/me', undefined],
    ['PUT', '/v1/me', { displayName: 'Name', locale: 'en', adultAttested: true }],
    ['GET', '/v1/circles', undefined],
    ['POST', '/v1/circles', { name: 'Circle', clientRequestId: randomUUID() }],
    ['GET', '/v1/circles/' + circleId, undefined],
    [
      'POST',
      '/v1/circles/' + circleId + '/invites',
      { recipientId: recipient, clientRequestId: randomUUID() },
    ],
    ['GET', '/v1/circle-invites', undefined],
    ['GET', '/v1/me/blocks', undefined],
    ['GET', '/v1/me/blocks/' + recipient, undefined],
    ['PUT', '/v1/me/blocks/' + recipient, { blocked: true, expectedVersion: 0 }],
    ['POST', '/v1/circle-invites/' + inviteId + '/accept', { token: 'x'.repeat(43) }],
    ['DELETE', '/v1/circle-invites/' + inviteId, undefined],
    ['DELETE', '/v1/circles/' + circleId + '/members/' + recipient, undefined],
    ['DELETE', '/v1/circles/' + circleId, undefined],
    ['GET', '/v1/reports', undefined],
    ['DELETE', '/v1/reports/' + randomUUID(), undefined],
    ['GET', '/v1/road-events', undefined],
  ] as const) {
    const response = await app.inject({ method, url, ...(payload ? { payload } : {}) });
    assert.equal(response.statusCode, 401, url);
    assert.equal(response.headers['cache-control'], 'no-store');
  }
  assert.equal(calls.length, 0);
});

test('block endpoints bind actor, bound pagination/version and serialize only private outgoing state', async (t) => {
  const { app, calls } = await setup();
  t.after(() => app.close());
  const path = '/v1/me/blocks/' + recipient.toUpperCase();
  const state = await app.inject({ method: 'GET', url: path, headers });
  assert.equal(state.statusCode, 200);
  assert.deepEqual(state.json(), {
    userId: recipient,
    blocked: false,
    version: 0,
    changedAt: null,
  });
  const changed = await app.inject({
    method: 'PUT',
    url: path,
    headers,
    payload: { blocked: true, expectedVersion: 0 },
  });
  assert.equal(changed.statusCode, 200);
  assert.equal(changed.json().version, 1);
  assert.equal(changed.body.includes('PRIVATE_INTERNAL'), false);
  assert.equal(changed.headers['cache-control'], 'no-store');
  assert.deepEqual(calls.at(-1)?.values, [
    actor,
    'set_block',
    { userId: recipient, blocked: true, expectedVersion: 0 },
  ]);
  const page = await app.inject({
    method: 'GET',
    url: '/v1/me/blocks?limit=1&after=' + recipient,
    headers,
  });
  assert.equal(page.statusCode, 200);
  assert.deepEqual(calls.at(-1)?.values, [actor, 'list_blocks', { limit: 1, after: recipient }]);
  const before = calls.length;
  for (const payload of [
    { blocked: 'true', expectedVersion: 0 },
    { blocked: true, expectedVersion: '0' },
    { blocked: true, expectedVersion: -1 },
    { blocked: true, expectedVersion: 2147483647 },
    { blocked: true, expectedVersion: 0, actorId: recipient },
  ])
    assert.equal(
      (await app.inject({ method: 'PUT', url: path, headers, payload })).statusCode,
      400,
    );
  for (const query of [
    'limit=0',
    'limit=51',
    'limit=01',
    'after=not-an-id',
    'actorId=' + recipient,
  ])
    assert.equal(
      (await app.inject({ method: 'GET', url: '/v1/me/blocks?' + query, headers })).statusCode,
      400,
    );
  assert.equal(calls.length, before);
});

test('strict schemas reject ownership spoofing, type coercion, bad TTLs and malformed IDs before SQL', async (t) => {
  const { app, calls } = await setup();
  t.after(() => app.close());
  const bad = [
    {
      method: 'PUT' as const,
      url: '/v1/me',
      payload: { displayName: 'Name', locale: 'en', adultAttested: 'true' },
    },
    {
      method: 'POST' as const,
      url: '/v1/circles',
      payload: { name: 'Circle', clientRequestId: randomUUID(), ownerId: recipient },
    },
    {
      method: 'POST' as const,
      url: '/v1/circles/' + circleId + '/invites',
      payload: { clientRequestId: randomUUID(), recipientId: recipient, expiresInSeconds: 604801 },
    },
    { method: 'POST' as const, url: '/v1/reports', payload: { ...report, latitude: '23.76' } },
    { method: 'POST' as const, url: '/v1/reports', payload: { ...report, status: 'reviewed' } },
  ];
  for (const request of bad)
    assert.equal((await app.inject({ ...request, headers })).statusCode, 400);
  assert.equal(
    (await app.inject({ method: 'GET', url: '/v1/circles/not-an-id', headers })).statusCode,
    400,
  );
  assert.equal(calls.length, 0);
});

test('response allowlists remove hashes, phone values and internal fields', async (t) => {
  const { app } = await setup();
  t.after(() => app.close());
  const me = await app.inject({ method: 'GET', url: '/v1/me', headers });
  assert.equal(me.statusCode, 200);
  assert.equal(me.json().profile.id, actor);
  assert.equal(me.body.includes('PRIVATE_HASH'), false);
  assert.equal(me.body.includes('PRIVATE_PHONE'), false);
  const detail = await app.inject({ method: 'GET', url: '/v1/circles/' + circleId, headers });
  assert.equal(detail.body.includes('PRIVATE_INTERNAL'), false);
  const invite = await app.inject({
    method: 'POST',
    url: '/v1/circles/' + circleId + '/invites',
    headers,
    payload: { clientRequestId: randomUUID(), recipientId: recipient },
  });
  assert.equal(invite.statusCode, 201);
  assert.match(invite.json().token, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(invite.body.includes('PRIVATE_HASH'), false);
});

test('write operations use bound Auth actor and parameterized SQL; raw tokens never reach storage', async (t) => {
  const { app, calls } = await setup();
  t.after(() => app.close());
  const result = await app.inject({ method: 'POST', url: '/v1/reports', headers, payload: report });
  assert.equal(result.statusCode, 201);
  assert.equal(calls[0]?.values[0], actor);
  assert.equal(calls[0]?.sql.includes(report.description), false);
  const invite = await app.inject({
    method: 'POST',
    url: '/v1/circles/' + circleId + '/invites',
    headers,
    payload: { clientRequestId: randomUUID(), recipientId: recipient },
  });
  const data = calls[1]?.values[2] as { tokenHash: string };
  assert.equal(data.tokenHash, tokenHash(invite.json().token));
  assert.equal(JSON.stringify(calls[1]).includes(invite.json().token), false);
});

test('bounded queries reject invalid cursors, incomplete/oversized bounds and unbounded limits', async (t) => {
  const { app, calls } = await setup();
  t.after(() => app.close());
  for (const url of [
    '/v1/reports?limit=101',
    '/v1/reports?cursor=bad',
    '/v1/road-events?south=23.7',
    '/v1/road-events?south=20&north=30&west=90&east=91',
    '/v1/road-events?limit=0',
  ]) {
    assert.equal((await app.inject({ method: 'GET', url, headers })).statusCode, 400, url);
  }
  assert.equal(calls.length, 0);
  const valid = await app.inject({
    method: 'GET',
    url: '/v1/road-events?south=23.7&north=23.9&west=90.3&east=90.5',
    headers,
  });
  assert.equal(valid.statusCode, 200, valid.body);
  assert.equal((calls[0]?.values[2] as { limit: number }).limit, 50);
});

test('readiness distinguishes a live process from a usable database and exposes no infrastructure details', async (t) => {
  const app = await buildServer({
    verifyToken: async () => null,
    reports: {
      create: async () => {
        throw Error('unused');
      },
    },
    ready: async () => {
      throw Error('PRIVATE_DB_CONNECTION');
    },
  });
  t.after(() => app.close());
  assert.equal((await app.inject('/health')).statusCode, 200);
  const ready = await app.inject('/ready');
  assert.equal(ready.statusCode, 503);
  assert.deepEqual(ready.json(), { status: 'not_ready' });
  assert.equal(ready.body.includes('PRIVATE'), false);
});

test('CORS allows only configured origins and the OpenAPI describes full authenticated contracts', async (t) => {
  const { app } = await setup();
  t.after(() => app.close());
  const allowed = await app.inject({
    method: 'OPTIONS',
    url: '/v1/me',
    headers: { origin: 'http://127.0.0.1:8765', 'access-control-request-method': 'GET' },
  });
  assert.equal(allowed.headers['access-control-allow-origin'], 'http://127.0.0.1:8765');
  const denied = await app.inject({
    method: 'GET',
    url: '/health',
    headers: { origin: 'https://untrusted.example' },
  });
  assert.equal(denied.headers['access-control-allow-origin'], undefined);
  const spec = (await app.inject('/openapi.json')).json();
  assert.equal(spec.openapi, '3.1.0');
  assert.ok(spec.paths['/v1/me']);
  assert.ok(spec.paths['/v1/circle-invites/{inviteId}/accept']);
  assert.deepEqual(spec.paths['/v1/me'].get.security, [{ bearerAuth: [] }]);
});

test('logs contain route templates/status only, not IDs, queries, tokens, profile names or report bodies', async (t) => {
  const logs: string[] = [];
  const { app } = await setup({
    level: 'info',
    stream: { write: (message) => logs.push(message) },
  });
  t.after(() => app.close());
  const privateHeaders = { authorization: 'Bearer PRIVATE_BEARER_TOKEN' };
  await app.inject({
    method: 'POST',
    url: '/v1/reports',
    headers: privateHeaders,
    payload: report,
  });
  await app.inject({ method: 'GET', url: '/v1/circles/' + circleId, headers: privateHeaders });
  await app.inject({ method: 'GET', url: '/v1/me', headers: privateHeaders });
  const output = logs.join('');
  assert.ok(output.includes('/v1/circles/:circleId'));
  for (const sensitive of ['PRIVATE_', circleId, actor, report.clientRequestId])
    assert.equal(output.includes(sensitive), false, sensitive);
});

test('persistence failures are sanitized and documented domain errors map to HTTP codes', async () => {
  for (const [source, code, status] of [
    [{ code: 'P0001', message: 'not_found' }, 'not_found', 404],
    [{ code: 'P0001', message: 'idempotency_conflict' }, 'idempotency_conflict', 409],
    [{ code: 'P0001', message: 'rate_limited' }, 'rate_limited', 429],
    [{ code: 'P0001', message: 'PRIVATE_SQL_VALUE' }, 'storage_unavailable', 503],
    [{ code: '42P01', message: 'PRIVATE_DB_CONNECTION' }, 'storage_unavailable', 503],
  ] as const) {
    const stores = postgresStores({
      query: async () => {
        throw source;
      },
    });
    const app = await buildServer({
      ...stores,
      verifyToken: async () => ({ id: actor, phoneVerified: true }),
      inviteToken: inviteTokenFactory('12'.repeat(32)),
    });
    try {
      const result = await app.inject({ method: 'GET', url: '/v1/me', headers });
      assert.equal(result.statusCode, status);
      assert.equal(result.json().code, code);
      assert.equal(result.body.includes('PRIVATE'), false);
    } finally {
      await app.close();
    }
  }
});

test('invite derivation is stable, canonical and isolated by actor/circle/command; cursor round trips are bounded', () => {
  const factory = inviteTokenFactory('12'.repeat(32)),
    requestId = randomUUID();
  const token = factory(actor, circleId, requestId);
  assert.equal(
    token,
    factory(actor.toUpperCase(), circleId.toUpperCase(), requestId.toUpperCase()),
  );
  assert.notEqual(token, factory(actor, circleId, randomUUID()));
  assert.notEqual(token, factory(recipient, circleId, requestId));
  assert.notEqual(token, factory(actor, randomUUID(), requestId));
  assert.throws(() => inviteTokenFactory('short'));
  const cursor = { createdAt: timestamp, id: randomUUID() };
  assert.deepEqual(decodeCursor(encodeCursor(cursor)!), cursor);
  for (const value of [
    'x'.repeat(513),
    Buffer.from(JSON.stringify([1, 'not-a-date', actor])).toString('base64url'),
  ])
    assert.throws(() => decodeCursor(value));
});

test('configuration rejects unsafe CORS, plaintext remote Auth and unverified remote database TLS options', async () => {
  const env = {
    SUPABASE_URL: 'https://fresh.example.test',
    SUPABASE_PUBLISHABLE_KEY: 'test-key',
    DATABASE_URL: 'postgresql://awaaz_api:test@db.example/test',
    INVITE_TOKEN_SECRET: '12'.repeat(32),
  };
  assert.equal(configuration(env).host, '127.0.0.1');
  assert.equal(configuration(env).port, 3030);
  assert.throws(() => configuration({ ...env, CORS_ORIGINS: '*' }));
  assert.throws(() => configuration({ ...env, SUPABASE_URL: 'http://remote.example' }));
  assert.throws(() => configuration({ ...env, PORT: '-1' }));
  assert.throws(() => createDatabasePool('postgresql://postgres:test@localhost/test'));
  for (const parameter of [
    'sslmode=no-verify',
    'ssl=false',
    'SSLMode=disable',
    'uselibpqcompat=true',
  ]) {
    assert.throws(() => createDatabasePool(env.DATABASE_URL + '?' + parameter));
  }
  const pool = createDatabasePool(env.DATABASE_URL);
  assert.deepEqual(pool.options.ssl, { rejectUnauthorized: true });
  await pool.end();
});
