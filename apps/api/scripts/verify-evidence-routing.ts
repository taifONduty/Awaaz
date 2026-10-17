import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { databaseHarness } from '../test/integration/harness.ts';
import { registerRoadGraph } from '../src/road_graph.ts';
import { buildEvidenceSnapshot, postgresEvidence, exportEvidence } from '../src/evidence.ts';
import { EvidenceRouterWorker, EvidenceRoutingCoordinator } from '../src/evidence_router.ts';
import { parseGraphManifest, distanceMetres } from '../src/routing.ts';
import { WorkerRouting } from '../src/worker_routing.ts';
import { buildServer } from '../src/server.ts';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const manifest = parseGraphManifest(
  JSON.parse(await readFile(join(root, '.local/routing/manifest.json'), 'utf8')),
);
const artifact = process.env.AWAAZ_ROAD_EDGES_FILE;
if (!artifact) throw new Error('Export/register the local Dhaka graph first');
const h = await databaseHarness();
let worker: EvidenceRouterWorker | undefined;
let api: Awaited<ReturnType<typeof buildServer>> | undefined;
try {
  const client = await h.admin.connect();
  try {
    await client.query('SET ROLE awaaz_evidence');
    await registerRoadGraph(client, artifact);
  } finally {
    try {
      await client.query('RESET ROLE');
    } finally {
      client.release();
    }
  }
  worker = await EvidenceRouterWorker.create(
    'C:/Users/User/.codex/toolchains/jdk-21.0.12.1/jdk-21.0.12.1+1/bin/java.exe',
    join(root, '.local/routing/graphhopper-web-11.1.jar'),
    join(root, 'backend/routing/EvidenceRouter.java'),
    join(root, 'backend/routing/graphhopper.yml'),
    join(root, '.local/routing', manifest.graphVersion),
    join(root, '.local/evidence'),
    manifest,
  );
  const origin = { latitude: 23.7577, longitude: 90.389 },
    destination = { latitude: 23.7461, longitude: 90.3743 };
  const base = await worker.route(origin, destination, 'car');
  const length = (edge: (typeof base.edges)[number]) =>
    base.points
      .slice(edge.first, edge.last + 1)
      .reduce(
        (total, p, i, array) =>
          i
            ? total +
              distanceMetres(
                { latitude: array[i - 1]![0], longitude: array[i - 1]![1] },
                { latitude: p[0], longitude: p[1] },
              )
            : total,
        0,
      );
  const target = base.edges.slice(5, -5).sort((a, b) => length(b) - length(a))[0]!;
  const offset = Math.floor((target.first + target.last) / 2),
    p = base.points[offset]!,
    q = base.points[Math.min(offset + 1, target.last)]!;
  const owner = await h.user('Synthetic witness'),
    reviewer = await h.user('Synthetic reviewer');
  await h.admin.query('INSERT INTO awaaz_private.moderators(user_id) VALUES($1)', [reviewer.id]);
  const submitted = await h.request(owner.token, 'POST', '/v1/reports', {
    clientRequestId: randomUUID(),
    category: 'lighting',
    description: 'SYNTHETIC route weighting fixture, not an actual lighting observation.',
    latitude: (p[0] + q[0]) / 2,
    longitude: (p[1] + q[1]) / 2,
    observedAt: new Date().toISOString(),
  });
  assert.equal(submitted.statusCode, 201, submitted.body);
  const id = submitted.json().id;
  const approved = await h.request(reviewer.token, 'POST', `/v1/moderation/reports/${id}/reviews`, {
    clientRequestId: randomUUID(),
    decision: 'approve',
    reason: 'reviewed',
  });
  assert.equal(approved.statusCode, 201, approved.body);
  const published = await h.request(
    reviewer.token,
    'POST',
    `/v1/moderation/reports/${id}/publications`,
    { clientRequestId: randomUUID(), graphVersion: manifest.graphVersion, edgeId: target.edgeId },
  );
  assert.equal(published.statusCode, 201, published.body);
  // A continuous observed condition can cover a corridor. Use separately
  // reviewed synthetic submissions on several actual edges, rather than
  // changing the algorithm's penalty just to force a demonstration detour.
  const corridor = base.edges
    .slice(5, -5)
    .sort((a, b) => length(b) - length(a))
    .filter((e) => e.edgeId !== target.edgeId)
    .slice(0, 9);
  for (const edge of corridor) {
    const mid = Math.floor((edge.first + edge.last) / 2),
      a = base.points[mid]!,
      b = base.points[Math.min(mid + 1, edge.last)]!;
    const report = await h.request(owner.token, 'POST', '/v1/reports', {
      clientRequestId: randomUUID(),
      category: 'lighting',
      description: 'SYNTHETIC corridor lighting observation for algorithm verification only.',
      latitude: (a[0] + b[0]) / 2,
      longitude: (a[1] + b[1]) / 2,
      observedAt: new Date().toISOString(),
    });
    assert.equal(report.statusCode, 201, report.body);
    const rid = report.json().id;
    assert.equal(
      (
        await h.request(reviewer.token, 'POST', `/v1/moderation/reports/${rid}/reviews`, {
          clientRequestId: randomUUID(),
          decision: 'approve',
          reason: 'reviewed',
        })
      ).statusCode,
      201,
    );
    assert.equal(
      (
        await h.request(reviewer.token, 'POST', `/v1/moderation/reports/${rid}/publications`, {
          clientRequestId: randomUUID(),
          graphVersion: manifest.graphVersion,
          edgeId: edge.edgeId,
        })
      ).statusCode,
      201,
    );
  }
  const scoring = await h.admin.connect();
  let built;
  try {
    await scoring.query('SET ROLE awaaz_evidence');
    built = await buildEvidenceSnapshot(scoring, manifest.graphVersion);
  } finally {
    try {
      await scoring.query('RESET ROLE');
    } finally {
      scoring.release();
    }
  }
  const evidence = postgresEvidence(h.api),
    exported = await exportEvidence(evidence, built.id, join(root, '.local/evidence'));
  const cases = [];
  for (const [a, b] of [
    [origin, destination],
    [destination, origin],
    [origin, { latitude: 23.7335, longitude: 90.3956 }],
  ] as const) {
    for (const mode of ['car', 'walk'] as const) {
      const astar = await worker.route(a, b, mode, 'astarbi', exported),
        dijkstra = await worker.route(a, b, mode, 'dijkstrabi', exported);
      assert.ok(
        Math.abs(astar.cost - dijkstra.cost) <= Math.max(0.01, astar.cost * 1e-6),
        `${mode}: A* must match Dijkstra`,
      );
      assert.equal(astar.snapshotId, built.id);
      assert.equal(astar.safetyAssessment, 'unknown');
      cases.push({
        mode,
        cost: astar.cost,
        distanceMetres: astar.distanceMetres,
        durationSeconds: astar.durationSeconds,
        pointCount: astar.points.length,
      });
    }
  }
  const weighted = await worker.route(origin, destination, 'car', 'astarbi', exported);
  const provider = new WorkerRouting(
    Promise.resolve(worker),
    manifest,
    evidence,
    join(root, '.local/evidence'),
    true,
    true,
  );
  api = await buildServer({
    ...h.stores,
    routing: provider,
    verifyToken: async () => null,
    inviteToken: () => '',
  });
  const httpPlan = await api.inject({
    method: 'POST',
    url: '/v1/routes',
    payload: { origin, destination, mode: 'car', includeReports: true },
  });
  assert.equal(httpPlan.statusCode, 200, httpPlan.body);
  assert.equal(httpPlan.headers['cache-control'], 'no-store');
  assert.equal(httpPlan.json().routes.length, 2);
  assert.equal(httpPlan.json().reportRouting.synthetic, true);
  assert.equal(httpPlan.json().reportRouting.status, 'available');
  assert.equal(httpPlan.json().riskLevel, 'unknown');
  assert.equal(httpPlan.json().evidenceCoverage, null);
  assert.equal(httpPlan.json().routes[1].preference, 'reported');
  assert.ok(
    httpPlan.json().routes[0].reportedEvidenceFraction >
      httpPlan.json().routes[1].reportedEvidenceFraction,
  );
  assert.ok(
    Date.parse(httpPlan.json().expiresAt) - Date.parse(httpPlan.json().generatedAt) <= 120000,
  );
  console.log(
    JSON.stringify({
      penalizedEdge: target.edgeId,
      baseCost: base.cost,
      weightedCost: weighted.cost,
    }),
  );
  assert.ok(
    weighted.cost > base.cost + 0.01,
    'The evidence weighting must change cost, independent of whether an alternative exists',
  );
  assert.notDeepEqual(
    weighted.edges.map((e) => e.edgeId),
    base.edges.map((e) => e.edgeId),
    'Actual evidence must alter the selected route in this fixture',
  );
  const virtual = base.edges[0]!;
  assert.equal(virtual.edgeId, 102008); // Actual origin snaps part-way through this stored edge.
  const next = base.points[virtual.first + 1]!,
    following = base.points[virtual.first + 2]!;
  const inside = {
    latitude: (next[0] + following[0]) / 2,
    longitude: (next[1] + following[1]) / 2,
  };
  const virtualBase = await worker.route(origin, inside, 'car');
  const virtualReport = await h.request(owner.token, 'POST', '/v1/reports', {
    clientRequestId: randomUUID(),
    category: 'lighting',
    description: 'SYNTHETIC virtual snap edge weighting fixture, not an actual incident.',
    latitude: origin.latitude,
    longitude: origin.longitude,
    observedAt: new Date().toISOString(),
  });
  assert.equal(virtualReport.statusCode, 201, virtualReport.body);
  const vid = virtualReport.json().id;
  assert.equal(
    (
      await h.request(reviewer.token, 'POST', `/v1/moderation/reports/${vid}/reviews`, {
        clientRequestId: randomUUID(),
        decision: 'approve',
        reason: 'reviewed',
      })
    ).statusCode,
    201,
  );
  assert.equal(
    (
      await h.request(reviewer.token, 'POST', `/v1/moderation/reports/${vid}/publications`, {
        clientRequestId: randomUUID(),
        graphVersion: manifest.graphVersion,
        edgeId: virtual.edgeId,
      })
    ).statusCode,
    201,
  );
  const virtualClient = await h.admin.connect();
  let virtualSnapshot;
  try {
    await virtualClient.query('SET ROLE awaaz_evidence');
    virtualSnapshot = await buildEvidenceSnapshot(virtualClient, manifest.graphVersion);
  } finally {
    try {
      await virtualClient.query('RESET ROLE');
    } finally {
      virtualClient.release();
    }
  }
  const virtualArtifact = await exportEvidence(
    evidence,
    virtualSnapshot.id,
    join(root, '.local/evidence'),
  );
  const originIndex = (await evidence.edge(virtualSnapshot.id, virtual.edgeId)).edge.evidenceIndex!;
  const virtualWeighted = await worker.route(origin, inside, 'car', 'astarbi', virtualArtifact);
  assert.deepEqual(
    virtualBase.edges.map((e) => e.edgeId),
    [virtual.edgeId],
  );
  assert.deepEqual(
    virtualWeighted.edges.map((e) => e.edgeId),
    [virtual.edgeId],
  );
  assert.equal(virtualWeighted.durationSeconds, virtualBase.durationSeconds);
  console.log(
    JSON.stringify({
      virtualBaseCost: virtualBase.cost,
      virtualWeightedCost: virtualWeighted.cost,
      originIndex,
      expectedFactor: 1 + 2 * originIndex,
      actualFactor: virtualWeighted.cost / virtualBase.cost,
    }),
  );
  assert.ok(
    Math.abs(virtualWeighted.cost / virtualBase.cost - (1 + 2 * originIndex)) < 1e-6,
    'Virtual snap fragments must inherit their original edge penalty',
  );
  const bad = { ...exported, sha256: '0'.repeat(64) };
  await assert.rejects(worker.route(origin, destination, 'car', 'astarbi', bad), {
    code: 'invalid_snapshot',
  });
  const coordinated = await new EvidenceRoutingCoordinator(
    worker,
    evidence,
    join(root, '.local/evidence'),
  ).route({ origin, destination, mode: 'car' });
  assert.equal(coordinated.path.snapshotId, virtualSnapshot.id);
  const activeWorker = worker;
  const mutating = {
    manifest: worker.manifest,
    route: async (...args: Parameters<typeof activeWorker.route>) => {
      const path = await activeWorker.route(...args);
      const removed = await h.request(owner.token, 'DELETE', '/v1/reports/' + vid);
      assert.equal(removed.statusCode, 200);
      return path;
    },
  };
  await assert.rejects(
    new EvidenceRoutingCoordinator(mutating, evidence, join(root, '.local/evidence')).route({
      origin,
      destination,
      mode: 'car',
    }),
    { code: 'evidence_unavailable' },
  );
  await h.request(owner.token, 'DELETE', '/v1/reports/' + id);
  await assert.rejects(evidence.read(virtualSnapshot.id), { code: 'evidence_unavailable' });
  const result = {
    graphVersion: manifest.graphVersion,
    weightingVersion: weighted.weightingVersion,
    sourceSnapshot: built.id,
    penalizedEdge: target.edgeId,
    baseCost: base.cost,
    weightedCost: weighted.cost,
    routeChanged: true,
    astarDijkstraPairs: cases,
    snapshotDigestChecked: true,
    virtualOriginEdge: virtual.edgeId,
    virtualPenaltyFactor: virtualWeighted.cost / virtualBase.cost,
    liveEpochCheckedAfterSearch: true,
    httpRouteChoicesVerified: true,
    syntheticReportsOnly: true,
    safetyAssessment: 'unknown',
    productionSafetyValidated: false,
  };
  await writeFile(
    join(root, '.local/routing/evidence-routing-verification.json'),
    JSON.stringify(result, null, 2) + '\n',
  );
  console.log(JSON.stringify(result));
} finally {
  await api?.close();
  await worker?.close();
  await h.close();
}
