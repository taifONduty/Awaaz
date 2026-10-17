import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { test } from 'node:test';
import { GraphHopperRouting, distanceMetres } from '../src/routing.ts';
import { DomainError } from '../src/contracts.ts';
import { buildServer } from '../src/server.ts';

const manifest = {
  graphVersion: `dhaka-gh11.1-${'a'.repeat(20)}-${'b'.repeat(12)}`,
  engineVersion: '11.1' as const,
  importDate: '2026-10-13T00:00:00Z',
  osmBase: '2026-10-12T23:00:00Z',
};
const input = {
  origin: { latitude: 23.76, longitude: 90.38 },
  destination: { latitude: 23.765, longitude: 90.385 },
  mode: 'car' as const,
};

test('geographic API returns a versioned route with unknown safety and never creates a report', async () => {
  let searches = 0;
  const provider = createServer(async (req, res) => {
    res.setHeader('content-type', 'application/json');
    if (req.url === '/info') {
      res.end(
        JSON.stringify({
          version: '11.1',
          import_date: manifest.importDate,
          profiles: [{ name: 'car' }, { name: 'foot' }],
        }),
      );
      return;
    }
    let body = '';
    for await (const chunk of req) body += String(chunk);
    const request = JSON.parse(body) as Record<string, unknown>;
    assert.equal(request.algorithm, 'astarbi');
    assert.equal(request.profile, 'car');
    assert.equal(request.instructions, false);
    assert.equal(request.points_encoded, false);
    assert.deepEqual(request.points, [
      [90.38, 23.76],
      [90.385, 23.765],
    ]);
    searches++;
    res.end(
      JSON.stringify({
        paths: [
          {
            time: 120000,
            distance: distanceMetres(input.origin, input.destination),
            points: {
              type: 'LineString',
              coordinates: [
                [90.38, 23.76],
                [90.385, 23.765],
              ],
            },
          },
        ],
      }),
    );
  });
  provider.listen(0, '127.0.0.1');
  await once(provider, 'listening');
  const address = provider.address();
  assert(address && typeof address !== 'string');
  const routing = new GraphHopperRouting(`http://127.0.0.1:${address.port}`, manifest);
  const app = await buildServer({
    routing,
    verifyToken: async () => {
      assert.fail('Public routing must not invoke account Auth');
    },
    reports: {
      create: async () => {
        assert.fail('Planning must not persist a report');
      },
    },
  });
  try {
    const response = await app.inject({ method: 'POST', url: '/v1/routes', payload: input });
    assert.equal(response.statusCode, 200, response.body);
    const plan = response.json() as {
      graphVersion: string;
      riskLevel: string;
      evidenceCoverage: null;
      routes: { points: number[][] }[];
    };
    assert.equal(plan.graphVersion, manifest.graphVersion);
    assert.equal(plan.riskLevel, 'unknown');
    assert.equal(plan.evidenceCoverage, null);
    assert.deepEqual(plan.routes[0]!.points, [
      [23.76, 90.38],
      [23.765, 90.385],
    ]);
    assert.equal(response.headers['cache-control'], 'no-store');
    const rejected = await app.inject({
      method: 'POST',
      url: '/v1/routes',
      payload: { ...input, mode: 'motorcycle' },
    });
    assert.equal(rejected.statusCode, 400);
    assert.equal(searches, 1);
  } finally {
    await app.close();
    provider.close();
    await once(provider, 'close');
  }
});

test('graph replacement and remote redirects cannot yield an approved old-version route', async () => {
  let changed = false,
    redirect = false,
    queries = 0;
  const provider = createServer((req, res) => {
    if (redirect) {
      res.writeHead(302, { location: 'https://example.com/private' });
      res.end();
      return;
    }
    res.setHeader('content-type', 'application/json');
    if (req.url === '/info') {
      res.end(
        JSON.stringify({
          version: '11.1',
          import_date: changed ? '2026-10-13T00:01:00Z' : manifest.importDate,
          profiles: [{ name: 'car' }, { name: 'foot' }],
        }),
      );
      return;
    }
    queries++;
    changed = true;
    res.end(
      JSON.stringify({
        paths: [
          {
            time: 120000,
            distance: distanceMetres(input.origin, input.destination),
            points: {
              type: 'LineString',
              coordinates: [
                [90.38, 23.76],
                [90.385, 23.765],
              ],
            },
          },
        ],
      }),
    );
  });
  provider.listen(0, '127.0.0.1');
  await once(provider, 'listening');
  const address = provider.address();
  assert(address && typeof address !== 'string');
  const routing = new GraphHopperRouting(`http://127.0.0.1:${address.port}`, manifest);
  try {
    await assert.rejects(
      routing.plan(input),
      (e: unknown) => e instanceof DomainError && e.code === 'routing_version_changed',
    );
    assert.equal(queries, 1);
    assert.equal(await routing.ready(), false);
    redirect = true;
    await assert.rejects(
      routing.plan(input),
      (e: unknown) => e instanceof DomainError && e.code === 'routing_unavailable',
    );
    assert.equal(queries, 1);
  } finally {
    provider.close();
    await once(provider, 'close');
  }
});

test('unconfigured routing fails explicitly and invalid coordinates never reach a provider', async () => {
  const app = await buildServer({
    verifyToken: async () => null,
    reports: {
      create: async () => {
        throw new Error('unused');
      },
    },
  });
  try {
    const response = await app.inject({ method: 'POST', url: '/v1/routes', payload: input });
    assert.equal(response.statusCode, 503);
    assert.equal(response.json().code, 'routing_not_configured');
    const invalid = await app.inject({
      method: 'POST',
      url: '/v1/routes',
      payload: { ...input, origin: { latitude: 0, longitude: 0 } },
    });
    assert.equal(invalid.statusCode, 400);
    const router = new GraphHopperRouting('http://127.0.0.1:1', manifest);
    await assert.rejects(
      router.plan({ ...input, destination: input.origin }),
      (e: unknown) => e instanceof DomainError && e.code === 'already_at_destination',
    );
  } finally {
    await app.close();
  }
});
