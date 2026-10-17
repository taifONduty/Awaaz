import { readFile } from 'node:fs/promises';
import { createDatabasePool } from '../src/postgres.ts';
import { buildEvidenceSnapshot, postgresEvidence, exportEvidence } from '../src/evidence.ts';

const database = process.env.AWAAZ_EVIDENCE_DATABASE_URL,
  graph = process.env.AWAAZ_EVIDENCE_GRAPH_VERSION,
  output = process.env.AWAAZ_EVIDENCE_OUTPUT_DIR;
if (!database || !graph || !output)
  throw new Error(
    'Set the evidence worker connection, graph version and absolute output directory',
  );
const ca = process.env.DATABASE_CA_CERT_PATH
  ? await readFile(process.env.DATABASE_CA_CERT_PATH, 'utf8')
  : undefined;
const pool = createDatabasePool(database, ca, 'awaaz_evidence');
try {
  const built = await buildEvidenceSnapshot(pool, graph);
  const artifact = await exportEvidence(postgresEvidence(pool), built.id, output);
  console.log(
    JSON.stringify({
      ...built,
      path: artifact.path,
      sha256: artifact.sha256,
      expiresAt: artifact.metadata.expiresAt,
      evidencedEdges: artifact.metadata.evidencedEdgeCount,
      safetyCoverage: null,
    }),
  );
} catch {
  console.error('Evidence snapshot unavailable; no route safety assessment was created.');
  process.exitCode = 1;
} finally {
  await pool.end();
}
