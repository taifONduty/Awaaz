import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import { routingFromEnvironment } from '../src/routing.ts';

const router = await routingFromEnvironment(process.env);
assert(router, 'Configure a confirmed local routing service');
const url = new URL(process.env.AWAAZ_GRAPHHOPPER_URL!);
assert.equal(url.hostname, '127.0.0.1', 'This diagnostic is only for the owned local router');
const pairs = [
  [
    [23.7577, 90.389],
    [23.7461, 90.3743],
  ],
  [
    [23.7461, 90.3743],
    [23.7577, 90.389],
  ],
  [
    [23.7577, 90.389],
    [23.7335, 90.3956],
  ],
] as const;
const checks = [];
for (const mode of ['car', 'walk'] as const)
  for (const [origin, destination] of pairs) {
    const input = {
      origin: { latitude: origin[0], longitude: origin[1] },
      destination: { latitude: destination[0], longitude: destination[1] },
      mode,
    };
    const plan = await router.plan(input);
    assert.equal(plan.riskLevel, 'unknown');
    assert.equal(plan.evidenceCoverage, null);
    assert.equal(plan.trafficAware, false);
    const costs: Record<string, number> = {};
    for (const algorithm of ['astarbi', 'dijkstrabi']) {
      const response = await fetch(new URL('/route', url), {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        signal: AbortSignal.timeout(8000),
        body: JSON.stringify({
          points: [
            [origin[1], origin[0]],
            [destination[1], destination[0]],
          ],
          profile: mode === 'car' ? 'car' : 'foot',
          algorithm,
          'ch.disable': true,
          'lm.disable': true,
          instructions: false,
          points_encoded: false,
        }),
      });
      assert.equal(response.status, 200);
      const value = (await response.json()) as { paths: { weight: number }[] };
      costs[algorithm] = value.paths[0]!.weight;
    }
    assert(
      Math.abs(costs.astarbi! - costs.dijkstrabi!) <= Math.max(0.01, costs.dijkstrabi! * 0.000001),
      'A* disagrees with the Dijkstra oracle',
    );
    checks.push({
      mode,
      distanceMetres: plan.routes[0]!.distanceMetres,
      seconds: plan.routes[0]!.durationSeconds,
      points: plan.routes[0]!.points.length,
      astarCost: costs.astarbi,
      dijkstraCost: costs.dijkstrabi,
    });
  }
await writeFile(
  new URL('../../../.local/routing/verification.json', import.meta.url),
  JSON.stringify({ checkedAt: new Date().toISOString(), checks }, null, 2) + '\n',
);
console.log(JSON.stringify({ verified: checks.length, checks }));
