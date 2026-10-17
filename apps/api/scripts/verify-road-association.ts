// Actual pinned Dhaka graph + synthetic reports in a newly owned disposable DB.
// No fixture incident is retained or presented as real city evidence.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import { databaseHarness } from '../test/integration/harness.ts';
import { registerRoadGraph } from '../src/road_graph.ts';
import { buildEvidenceSnapshot, postgresEvidence, exportEvidence } from '../src/evidence.ts';
import { routingFromEnvironment } from '../src/routing.ts';
import { fileURLToPath } from 'node:url';

const artifact = process.env.AWAAZ_ROAD_EDGES_FILE;
if (!artifact) throw new Error('Set AWAAZ_ROAD_EDGES_FILE to the verified local export');
const routing = await routingFromEnvironment(process.env);
const h = await databaseHarness(routing ? { routing } : {});
try {
  const client = await h.admin.connect();
  let registered;
  try {
    await client.query('SET ROLE awaaz_evidence');
    registered = await registerRoadGraph(client, artifact, (count) =>
      console.log(`Imported ${count} real graph edges into the disposable database.`),
    );
    const replay = await registerRoadGraph(client, artifact);
    assert.equal(replay.replayed, true);
    await assert.rejects(client.query('SELECT * FROM public.report_submissions'), {
      code: '42501',
    });
    await assert.rejects(
      client.query("SELECT awaaz_private.graph_import('append',$1::jsonb)", [
        { graphVersion: registered.graphVersion, edges: [] },
      ]),
      { message: 'graph_immutable' },
    );
  } finally {
    await client.query('RESET ROLE');
    client.release();
  }
  await assert.rejects(h.api.query("SELECT awaaz_private.graph_import('begin','{}')"), {
    code: '42501',
  });
  assert.equal(
    (await h.admin.query('SELECT count(*)::integer AS n FROM awaaz_private.road_edges')).rows[0].n,
    registered.edges,
  );
  const owner = await h.user('Synthetic reporter'),
    reviewer = await h.user('Synthetic moderator'),
    outsider = await h.user('Synthetic outsider');
  await h.admin.query('INSERT INTO awaaz_private.moderators(user_id) VALUES($1)', [reviewer.id]);
  const submitted = await h.request(owner.token, 'POST', '/v1/reports', {
    clientRequestId: randomUUID(),
    category: 'lighting',
    description: 'SYNTHETIC PRIVATE GRAPH ASSOCIATION TEST, not an actual incident.',
    latitude: 23.7577,
    longitude: 90.389,
    observedAt: new Date().toISOString(),
  });
  assert.equal(submitted.statusCode, 201, submitted.body);
  const id = submitted.json().id,
    base = `/v1/moderation/reports/${id}`;
  const path = base + '/road-candidates?graphVersion=' + registered.graphVersion;
  assert.equal((await h.request(outsider.token, 'GET', path)).statusCode, 403);
  assert.equal((await h.request(owner.token, 'GET', path)).statusCode, 403);
  const candidates = await h.request(reviewer.token, 'GET', path);
  assert.equal(candidates.statusCode, 200, candidates.body);
  assert.equal(candidates.json().requiresHumanSelection, true);
  assert.ok(candidates.json().items.length > 0 && candidates.json().items.length <= 5);
  const selected = candidates.json().items[0];
  assert.ok(selected.distanceMetres <= 35);
  const input = {
    clientRequestId: randomUUID(),
    graphVersion: registered.graphVersion,
    edgeId: selected.edgeId,
  };
  const publish = (payload = input) =>
    h.request(reviewer.token, 'POST', base + '/publications', payload);
  assert.equal((await publish()).json().code, 'report_not_approved');
  const approval = await h.request(reviewer.token, 'POST', base + '/reviews', {
    clientRequestId: randomUUID(),
    decision: 'approve',
    reason: 'reviewed',
  });
  assert.equal(approval.statusCode, 201, approval.body);
  assert.equal(
    (await publish({ ...input, clientRequestId: randomUUID(), edgeId: 0 })).json().code,
    'edge_not_near_report',
  );
  const created = await publish();
  assert.equal(created.statusCode, 201, created.body);
  assert.equal(created.json().status, 'published');
  assert.equal(created.json().expiresAt, approval.json().expiresAt);
  const replayed = await publish();
  assert.equal(replayed.statusCode, 200, replayed.body);
  assert.equal(replayed.json().eventId, created.json().eventId);
  assert.equal(replayed.json().replayed, true);
  assert.equal((await publish({ ...input, edgeId: 0 })).statusCode, 409);
  const epoch = await h.admin.query(
    'SELECT evidence_epoch FROM awaaz_private.road_graphs WHERE graph_version=$1',
    [registered.graphVersion],
  );
  assert.equal(epoch.rows[0].evidence_epoch, '1');
  const publicRow = await h.admin.query(
    'SELECT road_segment_id,public_summary FROM public.road_events WHERE id=$1',
    [created.json().eventId],
  );
  assert.equal(publicRow.rows[0].road_segment_id, registered.graphVersion + ':' + selected.edgeId);
  assert.equal(publicRow.rows[0].public_summary.includes('PRIVATE'), false);
  assert.equal(publicRow.rows[0].public_summary.includes(owner.id), false);
  const feed = await h.request(outsider.token, 'GET', '/v1/road-events?limit=20');
  assert.equal(feed.statusCode, 200, feed.body);
  assert.equal(feed.json().items.length, 1);
  assert.equal(feed.json().items[0].roadSegmentId, publicRow.rows[0].road_segment_id);
  assert.equal(feed.json().items[0].summary, 'Reviewed report of poor lighting nearby.');
  for (const secret of ['PRIVATE', 'SYNTHETIC', owner.id, '23.7577'])
    assert.equal(feed.body.includes(secret), false);
  const publicPoint = await h.admin.query(
    'SELECT extensions.st_x(centroid::extensions.geometry) AS longitude,extensions.st_y(centroid::extensions.geometry) AS latitude FROM public.road_events WHERE id=$1',
    [created.json().eventId],
  );
  assert.equal(publicPoint.rows[0].longitude, Number(publicPoint.rows[0].longitude.toFixed(3)));
  assert.equal(publicPoint.rows[0].latitude, Number(publicPoint.rows[0].latitude.toFixed(3)));
  await assert.rejects(h.asUser(outsider.id, 'SELECT centroid FROM public.road_events'), {
    code: '42501',
  });
  await assert.rejects(
    h.api.query('SELECT awaaz_private.build_evidence_snapshot($1)', [registered.graphVersion]),
    { code: '42501' },
  );
  const worker = await h.admin.connect();
  let snapshot;
  try {
    await worker.query('SET ROLE awaaz_evidence');
    snapshot = await buildEvidenceSnapshot(worker, registered.graphVersion);
  } finally {
    await worker.query('RESET ROLE');
    worker.release();
  }
  const evidence = postgresEvidence(h.api),
    page = await evidence.read(snapshot.id);
  assert.equal(page.metadata.registeredEdgeCount, registered.edges);
  assert.equal(page.metadata.evidencedEdgeCount, 1);
  assert.equal(page.metadata.safetyCoverage, null);
  assert.equal(page.items.length, 1);
  assert.equal(page.items[0]!.edgeId, selected.edgeId);
  assert.equal(page.items[0]!.incidentIndex, null);
  assert.ok(page.items[0]!.environmentIndex! > 0);
  assert.equal(page.items[0]!.confidence, 0);
  assert.equal(page.items[0]!.uncertainty, 1);
  assert.equal(page.items[0]!.eventClusterCount, 1);
  const unobserved = await evidence.edge(snapshot.id, 0);
  assert.equal(unobserved.edge.evidenceIndex, null);
  assert.equal(unobserved.edge.confidence, 0);
  assert.equal(unobserved.edge.uncertainty, 1);
  assert.equal(unobserved.edge.eventClusterCount, 0);
  assert.equal(
    (
      await h.admin.query(
        'SELECT count(*)::integer AS n FROM public.edge_risk WHERE snapshot_id=$1',
        [snapshot.id],
      )
    ).rows[0].n,
    1,
  );
  assert.equal(
    (await h.asUser(outsider.id, 'SELECT id FROM public.risk_snapshots WHERE id=$1', [snapshot.id]))
      .rows.length,
    1,
  );
  const exported = await exportEvidence(
    evidence,
    snapshot.id,
    fileURLToPath(new URL('../../../.local/evidence/', import.meta.url)),
  );
  assert.equal(exported.metadata.id, snapshot.id);
  if (routing) {
    const status = await h.app.inject({ method: 'GET', url: '/v1/routing/evidence/status' });
    assert.equal(status.statusCode, 200, status.body);
    assert.equal(status.json().available, true);
    assert.equal(status.json().safetyAssessment, 'unknown');
  }
  const withdrawn = await h.request(owner.token, 'DELETE', '/v1/reports/' + id);
  assert.equal(withdrawn.statusCode, 200, withdrawn.body);
  assert.equal((await publish()).json().status, 'withdrawn');
  await assert.rejects(evidence.read(snapshot.id), { code: 'evidence_unavailable' });
  assert.equal(await evidence.current(registered.graphVersion), null);
  assert.equal(
    (await h.asUser(outsider.id, 'SELECT id FROM public.risk_snapshots WHERE id=$1', [snapshot.id]))
      .rows.length,
    0,
  );
  assert.equal(
    (
      await h.asUser(
        outsider.id,
        'SELECT edge_id FROM public.edge_risk WHERE snapshot_id=$1 AND edge_id=$2',
        [snapshot.id, String(selected.edgeId)],
      )
    ).rows.length,
    0,
  );
  const emptyWorker = await h.admin.connect();
  let empty;
  try {
    await emptyWorker.query('SET ROLE awaaz_evidence');
    empty = await buildEvidenceSnapshot(emptyWorker, registered.graphVersion);
  } finally {
    await emptyWorker.query('RESET ROLE');
    emptyWorker.release();
  }
  const emptyPage = await evidence.read(empty.id);
  assert.equal(emptyPage.metadata.evidencedEdgeCount, 0);
  assert.equal(emptyPage.items.length, 0);
  assert.deepEqual(emptyPage.metadata.unknownDefault, {
    confidence: 0,
    evidenceIndex: null,
    eventClusterCount: 0,
    uncertainty: 1,
  });
  await h.admin.query(
    "UPDATE public.risk_snapshots SET created_at=clock_timestamp()-interval '5 minutes',expires_at=clock_timestamp()-interval '1 second' WHERE id=$1",
    [empty.id],
  );
  await assert.rejects(evidence.read(empty.id), { code: 'evidence_unavailable' });
  assert.equal(
    (await h.request(outsider.token, 'GET', '/v1/road-events?limit=20')).json().items.length,
    0,
  );
  assert.equal(
    (await h.admin.query('SELECT count(*)::integer AS n FROM public.road_events')).rows[0].n,
    0,
  );
  assert.equal(
    (await h.admin.query('SELECT evidence_epoch FROM awaaz_private.road_graphs')).rows[0]
      .evidence_epoch,
    '2',
  );
  assert.equal(
    (await h.admin.query('SELECT count(*)::integer AS n FROM public.edge_risk')).rows[0].n,
    1,
  );
  assert.equal(await h.stores.ready(), true);
  const result = {
    ...registered,
    candidates: candidates.json().items.length,
    selectedEdgeId: selected.edgeId,
    distanceMetres: selected.distanceMetres,
    verified: [
      'immutable_real_graph',
      'restricted_import',
      'moderator_only_candidates',
      'approval_required',
      'nearby_edge_required',
      'fixed_public_summary',
      'idempotent_publication',
      'withdrawal_removal',
      'evidence_epoch_invalidation',
      'coarse_database_coordinates',
      'direct_coordinate_read_denied',
      'snapshot_worker_isolation',
      'unknown_unobserved_edges',
      'separate_evidence_dimensions',
      'snapshot_export',
      'withdrawal_revokes_snapshot_and_rls',
      'empty_is_unknown',
      'expired_snapshot_refused',
    ],
    syntheticReportsOnly: true,
    safetyScoringEnabled: false,
  };
  await writeFile(
    new URL('../../../.local/routing/association-verification.json', import.meta.url),
    JSON.stringify(result, null, 2) + '\n',
  );
  console.log(JSON.stringify(result));
} finally {
  await h.close();
}
