import test from 'node:test';
import assert from 'node:assert/strict';
import { PlaceCatalogue } from '../src/places.ts';
import { buildServer } from '../src/server.ts';

test('public place lookup matches bilingual names, deduplicates and rejects private request fields', async () => {
  const graph = 'dhaka-gh11.1-' + 'a'.repeat(20) + '-' + 'b'.repeat(12);
  const value = {
    format: 'awaaz-place-catalog-v1',
    graphVersion: graph,
    sourceTimestamp: new Date().toISOString(),
    items: [1, 2].map((id) => ({
      id: 'osm:node:' + id,
      name: 'ফার্মগেট',
      nameEn: 'Farmgate',
      nameBn: 'ফার্মগেট',
      aliases: ['Farmgate', 'ফার্মগেট'],
      kind: 'transit',
      point: { latitude: 23.758, longitude: 90.387 + id * 0.00001 },
    })),
  };
  const places = new PlaceCatalogue(value, 'a'.repeat(64), graph);
  const app = await buildServer({
    places,
    reports: {
      create: async () => {
        throw new Error('Unexpected report');
      },
    },
    verifyToken: async () => null,
  });
  try {
    for (const query of ['Farmgate', 'ফার্মগেট']) {
      const r = await app.inject({ method: 'POST', url: '/v1/places/search', payload: { query } });
      assert.equal(r.statusCode, 200);
      assert.equal(r.headers['cache-control'], 'no-store');
      assert.equal(r.json().items.length, 1);
      assert.equal(r.json().coverage, 'imported_places_only');
      assert.equal(Object.hasOwn(r.json().items[0], 'aliases'), false);
    }
    const missing = await app.inject({
      method: 'POST',
      url: '/v1/places/search',
      payload: { query: 'does-not-exist' },
    });
    assert.deepEqual(missing.json().items, []);
    for (const payload of [
      { query: 'f' },
      { query: 'Farmgate', latitude: 23.76 },
      { query: ' '.repeat(4) },
    ])
      assert.equal(
        (await app.inject({ method: 'POST', url: '/v1/places/search', payload })).statusCode,
        400,
      );
    assert.throws(
      () =>
        new PlaceCatalogue(value, 'a'.repeat(64), graph.replace('a'.repeat(20), 'c'.repeat(20))),
    );
  } finally {
    await app.close();
  }
});
