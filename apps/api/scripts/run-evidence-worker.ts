import { readFile } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { createDatabasePool } from '../src/postgres.ts';
import { parseGraphManifest } from '../src/routing.ts';
import { EvidenceRefreshWorker } from '../src/evidence_refresh.ts';

// Standalone restricted worker. No consumer Auth or Maps credentials are needed.
const controller = new AbortController();
const stop = () => controller.abort();
process.once('SIGINT', stop);
process.once('SIGTERM', stop);
// Windows supervisors can request graceful shutdown through their owned IPC
// channel. No network command endpoint is opened.
const parentMessage = (message: unknown) => {
  if (message === 'awaaz.evidence.stop') stop();
};
if (process.connected) {
  process.on('message', parentMessage);
  process.once('disconnect', stop);
}
let pool: ReturnType<typeof createDatabasePool> | undefined;
let worker: EvidenceRefreshWorker | undefined;
try {
  if (process.argv.slice(2).some((v) => v !== '--once')) throw new Error('Invalid argument');
  const database = process.env.AWAAZ_EVIDENCE_DATABASE_URL;
  const manifestPath = process.env.AWAAZ_ROUTING_MANIFEST;
  const directory = process.env.AWAAZ_EVIDENCE_OUTPUT_DIR;
  if (
    !database ||
    !manifestPath ||
    !directory ||
    !isAbsolute(manifestPath) ||
    !isAbsolute(directory)
  )
    throw new Error('Worker configuration missing');
  const manifest = parseGraphManifest(
    JSON.parse((await readFile(manifestPath, 'utf8')).replace(/^\uFEFF/, '')),
  );
  if (
    process.env.AWAAZ_EVIDENCE_GRAPH_VERSION &&
    process.env.AWAAZ_EVIDENCE_GRAPH_VERSION !== manifest.graphVersion
  )
    throw new Error('Worker graph mismatch');
  const caPath = process.env.DATABASE_CA_CERT_PATH;
  if (caPath && !isAbsolute(caPath)) throw new Error('Invalid CA configuration');
  const ca = caPath ? await readFile(caPath, 'utf8') : undefined;
  pool = createDatabasePool(database, ca, 'awaaz_evidence');
  worker = new EvidenceRefreshWorker(
    pool,
    manifest.graphVersion,
    directory,
    process.env.AWAAZ_EVIDENCE_HEALTH_FILE || join(directory, 'awaaz-evidence.health.json'),
  );
  console.log('Evidence refresh worker started; safety assessment remains unknown.');
  if (process.argv.includes('--once')) {
    await worker.cycle();
    if (worker.health.status !== 'ready') process.exitCode = 1;
  } else await worker.run(controller.signal);
} catch {
  console.error('Evidence worker unavailable. Check its configuration and private health file.');
  process.exitCode = 1;
} finally {
  try {
    await worker?.close();
  } catch {
    console.error('Evidence worker health shutdown failed.');
    process.exitCode = 1;
  }
  try {
    await pool?.end();
  } catch {
    console.error('Evidence worker database shutdown failed.');
    process.exitCode = 1;
  }
  process.removeListener('SIGINT', stop);
  process.removeListener('SIGTERM', stop);
  process.removeListener('message', parentMessage);
  process.removeListener('disconnect', stop);
  if (process.connected) process.disconnect();
}
