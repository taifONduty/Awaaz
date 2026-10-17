import { readFile } from 'node:fs/promises';
import { createDatabasePool } from '../src/postgres.ts';
import { registerRoadGraph } from '../src/road_graph.ts';

const source = process.env.AWAAZ_EVIDENCE_DATABASE_URL;
const artifact = process.env.AWAAZ_ROAD_EDGES_FILE;
if (!source || !artifact)
  throw new Error('Set AWAAZ_EVIDENCE_DATABASE_URL and AWAAZ_ROAD_EDGES_FILE');
const ca = process.env.DATABASE_CA_CERT_PATH
  ? await readFile(process.env.DATABASE_CA_CERT_PATH, 'utf8')
  : undefined;
const pool = createDatabasePool(source, ca, 'awaaz_evidence');
try {
  const client = await pool.connect();
  try {
    const result = await registerRoadGraph(client, artifact, (count) =>
      console.log(`Imported ${count} edges into the pending transaction.`),
    );
    console.log(JSON.stringify(result));
  } finally {
    client.release();
  }
} catch {
  console.error(
    'Graph registration failed; transaction rolled back. Check the restricted role and pinned local artifacts.',
  );
  process.exitCode = 1;
} finally {
  await pool.end();
}
