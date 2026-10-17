import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { buildServer, IdempotencyConflict } from '../src/server.ts';
import type { ReportInput, ReportReceipt } from '../src/server.ts';

const now = new Date('2026-10-12T12:00:00Z');
const owner = randomUUID();
const report: ReportInput = {
  clientRequestId: randomUUID(),
  category: 'lighting',
  description: 'Demo lighting issue near the crossing.',
  latitude: 23.76,
  longitude: 90.38,
  observedAt: now.toISOString(),
};
async function setup() {
  const saved = new Map<string, { receipt: ReportReceipt; hash: string; owner: string }>();
  const app = await buildServer({
    now: () => now,
    verifyToken: async (token) =>
      token === 'verified'
        ? { id: owner, phoneVerified: true }
        : token === 'unverified'
          ? { id: owner, phoneVerified: false }
          : null,
    reports: {
      create: async (user, input, hash) => {
        const key = `${user}/${input.clientRequestId}`;
        const prior = saved.get(key);
        if (prior) {
          if (prior.hash !== hash) throw new IdempotencyConflict();
          return { ...prior.receipt, replayed: true };
        }
        const receipt: ReportReceipt = { id: randomUUID(), status: 'pending', replayed: false };
        saved.set(key, { receipt, hash, owner: user });
        return receipt;
      },
    },
  });
  return { app, saved };
}
test('health has no privileged dependencies in its response', async (t) => {
  const { app } = await setup();
  t.after(() => app.close());
  const result = await app.inject('/health');
  assert.equal(result.statusCode, 200);
  assert.equal(result.json().service, 'awaaz-api');
});
test('unauthenticated and unverified accounts cannot submit reports', async (t) => {
  const { app, saved } = await setup();
  t.after(() => app.close());
  for (const [token, status] of [
    ['invalid', 401],
    ['unverified', 403],
  ] as const) {
    const result = await app.inject({
      method: 'POST',
      url: '/v1/reports',
      headers: { authorization: `Bearer ${token}` },
      payload: report,
    });
    assert.equal(result.statusCode, status);
  }
  assert.equal(saved.size, 0);
});
test('validated reports bind ownership to the verified session and replay safely', async (t) => {
  const { app, saved } = await setup();
  t.after(() => app.close());
  const request = {
    method: 'POST' as const,
    url: '/v1/reports',
    headers: { authorization: 'Bearer verified' },
    payload: report,
  };
  const first = await app.inject(request),
    second = await app.inject(request);
  assert.equal(first.statusCode, 201);
  assert.equal(second.statusCode, 200);
  assert.equal(first.json().id, second.json().id);
  assert.equal(second.json().replayed, true);
  assert.equal([...saved.values()][0]?.owner, owner);
  assert.equal(first.json().status, 'pending');
  const conflict = await app.inject({
    ...request,
    payload: { ...report, description: 'A different demo description.' },
  });
  assert.equal(conflict.statusCode, 409);
});
test('spoofed ownership, bad categories, stale data and locations are rejected', async (t) => {
  const { app, saved } = await setup();
  t.after(() => app.close());
  for (const payload of [
    { ...report, ownerId: randomUUID() },
    { ...report, category: 'suspicious_person' },
    { ...report, observedAt: '2020-01-01T00:00:00Z' },
    { ...report, description: ' '.repeat(15) },
  ]) {
    const result = await app.inject({
      method: 'POST',
      url: '/v1/reports',
      headers: { authorization: 'Bearer verified' },
      payload,
    });
    assert.equal(result.statusCode, 400);
  }
  const outside = await app.inject({
    method: 'POST',
    url: '/v1/reports',
    headers: { authorization: 'Bearer verified' },
    payload: { ...report, latitude: 22.3 },
  });
  assert.equal(outside.statusCode, 422);
  assert.equal(saved.size, 0);
});
test('storage failure never returns a successful receipt', async (t) => {
  const app = await buildServer({
    now: () => now,
    verifyToken: async () => ({ id: owner, phoneVerified: true }),
    reports: {
      create: async () => {
        throw new Error('sensitive database detail');
      },
    },
  });
  t.after(() => app.close());
  const result = await app.inject({
    method: 'POST',
    url: '/v1/reports',
    headers: { authorization: 'Bearer verified' },
    payload: report,
  });
  assert.equal(result.statusCode, 503);
  assert.equal(result.json().code, 'storage_unavailable');
  assert.equal(result.body.includes('sensitive'), false);
});
