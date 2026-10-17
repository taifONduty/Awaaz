import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { fork } from 'node:child_process';
import type { ChildProcess } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { Pool } from 'pg';
import { databaseHarness } from '../test/integration/harness.ts';
import { registerRoadGraph } from '../src/road_graph.ts';
import { parseGraphManifest } from '../src/routing.ts';
import { createDatabasePool } from '../src/postgres.ts';
import { EvidenceRefreshWorker, evidenceHealthReady } from '../src/evidence_refresh.ts';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const manifestPath = join(root, '.local/routing/manifest.json');
const manifest = parseGraphManifest(JSON.parse(await readFile(manifestPath, 'utf8')));
const source = process.env.AWAAZ_ROAD_EDGES_FILE;
if (!source) throw new Error('Export the actual graph first');
const h = await databaseHarness();
const control = new Pool({
  connectionString: process.env.AWAAZ_TEST_ADMIN_URL!,
  ssl: false,
  max: 1,
});
let roleChanged = false,
  locked = false;
let pool: ReturnType<typeof createDatabasePool> | undefined;
let first: EvidenceRefreshWorker | undefined, second: EvidenceRefreshWorker | undefined;
let child: ChildProcess | undefined;
let childExit: Promise<number | null> | undefined;
const directory = join(root, '.local/evidence-worker-check-' + randomUUID());
const lockKey = 'awaaz:evidence-worker:v1:' + manifest.graphVersion;
try {
  // The harness already verifies localhost and the integration-only cluster.
  // Serialize the temporary LOGIN credential with other role setup operations.
  await control.query(
    "SELECT pg_catalog.pg_advisory_lock(pg_catalog.hashtextextended('awaaz:test:role-setup:v1',0))",
  );
  locked = true;
  const previous = await h.admin.query(
    "SELECT NOT rolcanlogin AND rolpassword IS NULL AS untouched FROM pg_catalog.pg_authid WHERE rolname='awaaz_evidence'",
  );
  assert.equal(
    previous.rows[0]?.untouched,
    true,
    'Refusing to replace an existing worker credential',
  );
  const password = randomBytes(32).toString('hex');
  await h.admin.query("ALTER ROLE awaaz_evidence LOGIN PASSWORD '" + password + "'");
  roleChanged = true;
  const imported = await h.admin.connect();
  try {
    await imported.query('SET ROLE awaaz_evidence');
    await registerRoadGraph(imported, source);
  } finally {
    await imported.query('RESET ROLE');
    imported.release();
  }
  const databaseName = (await h.admin.query('SELECT current_database() AS name')).rows[0]?.name;
  assert.match(databaseName, /^awaaz_test_[0-9a-f]{32}$/);
  const url = new URL(process.env.AWAAZ_TEST_ADMIN_URL!);
  url.pathname = '/' + databaseName;
  url.username = 'awaaz_evidence';
  url.password = password;
  pool = createDatabasePool(url.toString(), undefined, 'awaaz_evidence');
  assert.equal((await pool.query('SELECT current_user AS name')).rows[0]?.name, 'awaaz_evidence');
  await assert.rejects(pool.query('SELECT * FROM auth.users'));
  await mkdir(directory, { recursive: true });
  first = new EvidenceRefreshWorker(
    pool,
    manifest.graphVersion,
    directory,
    join(directory, 'awaaz-evidence-first.health.json'),
  );
  const a = first.cycle(),
    b = first.cycle();
  assert.equal(a, b);
  await a;
  assert.equal(evidenceHealthReady(first.health), true);
  assert.equal(
    evidenceHealthReady(first.health, Date.parse(first.health.snapshotExpiresAt!) + 1),
    false,
  );
  assert.equal(
    evidenceHealthReady({ ...first.health, updatedAt: new Date(Date.now() - 90000).toISOString() }),
    false,
  );
  const exported = JSON.parse(
    (await readFile(join(directory, first.health.snapshotId + '.jsonl'), 'utf8')).split('\n')[0]!,
  );
  assert.equal(exported.metadata.graphVersion, manifest.graphVersion);
  assert.equal(exported.metadata.evidencedEdgeCount, 0);
  assert.equal(exported.metadata.safetyCoverage, null);
  const held = await h.admin.connect();
  second = new EvidenceRefreshWorker(
    pool,
    manifest.graphVersion,
    directory,
    join(directory, 'awaaz-evidence-second.health.json'),
  );
  try {
    await held.query('SELECT pg_catalog.pg_advisory_lock(pg_catalog.hashtextextended($1,0))', [
      lockKey,
    ]);
    await second.cycle();
    assert.equal(second.health.status, 'standby');
  } finally {
    await held.query('SELECT pg_catalog.pg_advisory_unlock(pg_catalog.hashtextextended($1,0))', [
      lockKey,
    ]);
    held.release();
  }
  await second.cycle();
  assert.equal(evidenceHealthReady(second.health), true);
  await h.admin.query(
    'REVOKE EXECUTE ON FUNCTION awaaz_private.build_evidence_snapshot(text) FROM awaaz_evidence',
  );
  await first.cycle();
  assert.equal(first.health.status, 'unavailable');
  assert.equal(first.health.consecutiveFailures, 1);
  await h.admin.query(
    'GRANT EXECUTE ON FUNCTION awaaz_private.build_evidence_snapshot(text) TO awaaz_evidence',
  );
  await first.cycle();
  assert.equal(evidenceHealthReady(first.health), true);
  const healthFile = join(directory, 'awaaz-evidence-child.health.json');
  const env: Record<string, string> = {
    AWAAZ_EVIDENCE_DATABASE_URL: url.toString(),
    AWAAZ_ROUTING_MANIFEST: manifestPath,
    AWAAZ_EVIDENCE_OUTPUT_DIR: directory,
    AWAAZ_EVIDENCE_HEALTH_FILE: healthFile,
  };
  for (const key of ['PATH', 'SystemRoot', 'TEMP', 'TMP'])
    if (process.env[key]) env[key] = process.env[key]!;
  child = fork(fileURLToPath(new URL('./run-evidence-worker.ts', import.meta.url)), [], {
    cwd: fileURLToPath(new URL('../', import.meta.url)),
    env,
    silent: true,
    execArgv: [],
    windowsHide: true,
  });
  child.stdout?.resume();
  child.stderr?.resume();
  childExit = new Promise((resolve, reject) => {
    child!.once('exit', (code) => resolve(code));
    child!.once('error', reject);
  });
  const deadline = Date.now() + 60000;
  let ready = false;
  while (!ready && Date.now() < deadline) {
    assert.equal(child.exitCode, null);
    try {
      ready = evidenceHealthReady(JSON.parse(await readFile(healthFile, 'utf8')));
    } catch {
      /* startup file pending */
    }
    if (!ready) await delay(200);
  }
  assert.equal(ready, true, 'Standalone restricted worker did not become ready');
  child.send('awaaz.evidence.stop');
  assert.equal(await Promise.race([childExit, delay(15000).then(() => 'timeout')]), 0);
  assert.equal(JSON.parse(await readFile(healthFile, 'utf8')).status, 'stopped');
  const probeClient = await pool.connect();
  try {
    const probe = await probeClient.query(
      'SELECT pg_catalog.pg_try_advisory_lock(pg_catalog.hashtextextended($1,0)) AS free',
      [lockKey],
    );
    assert.equal(probe.rows[0]?.free, true);
    await probeClient.query(
      'SELECT pg_catalog.pg_advisory_unlock(pg_catalog.hashtextextended($1,0))',
      [lockKey],
    );
  } finally {
    probeClient.release();
  }
  const result = {
    graphVersion: manifest.graphVersion,
    restrictedLoginVerified: true,
    overlappingCyclesCoalesced: true,
    standbyVerified: true,
    permissionFailureRecoveryVerified: true,
    expiredHealthRefused: true,
    gracefulOwnedIpcStopVerified: true,
    graphRegisteredEdges: exported.metadata.registeredEdgeCount,
    observedEdges: 0,
    safetyAssessment: 'unknown',
    productionDeploymentVerified: false,
  };
  await writeFile(
    join(root, '.local/routing/evidence-worker-verification.json'),
    JSON.stringify(result, null, 2) + '\n',
  );
  console.log(JSON.stringify(result));
} finally {
  if (child && child.exitCode === null) {
    if (child.connected) child.send('awaaz.evidence.stop');
    const exited = await Promise.race([childExit, delay(10000).then(() => 'timeout')]);
    if (exited === 'timeout') {
      child.kill('SIGKILL');
      await childExit;
    }
  }
  const failures: unknown[] = [];
  for (const cleanup of [
    async () => first?.close(),
    async () => second?.close(),
    async () => pool?.end(),
    async () => {
      if (roleChanged) await h.admin.query('ALTER ROLE awaaz_evidence NOLOGIN PASSWORD NULL');
    },
    async () => {
      if (locked)
        await control.query(
          "SELECT pg_catalog.pg_advisory_unlock(pg_catalog.hashtextextended('awaaz:test:role-setup:v1',0))",
        );
    },
    async () => control.end(),
    async () => h.close(),
  ]) {
    try {
      await cleanup();
    } catch (error) {
      failures.push(error);
    }
  }
  if (failures.length) throw new Error('Worker diagnostic cleanup incomplete');
}
