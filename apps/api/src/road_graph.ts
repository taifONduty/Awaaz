import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { dirname, isAbsolute, join } from 'node:path';
import type { PoolClient } from 'pg';
import { evidenceWorkerAllowed } from './database_roles.ts';

const digest = /^[0-9a-f]{64}$/;
type Metadata = {
  graphVersion: string;
  importDate: string;
  sourceTimestamp: string;
  engineSha256: string;
  configSha256: string;
  extractSha256: string;
  edgesSha256: string;
  edgeCount: number;
  format: 'awaaz-gh-edges-v1';
  sourceGraphFiles: { name: string; sha256: string }[];
};
export async function fileDigest(path: string) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}
function edge(value: unknown): object {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('Invalid edge artifact');
  const x = value as Record<string, unknown>;
  if (
    Object.keys(x).sort().join(',') !==
      'carForward,carReverse,edgeId,footForward,footReverse,forwardKey,geometry,lengthMetres,reverseKey' ||
    !Number.isInteger(x.edgeId) ||
    (x.edgeId as number) < 0 ||
    (x.edgeId as number) > 10_000_000 ||
    x.forwardKey !== (x.edgeId as number) * 2 ||
    x.reverseKey !== (x.edgeId as number) * 2 + 1 ||
    !['carForward', 'carReverse', 'footForward', 'footReverse'].every(
      (key) => typeof x[key] === 'boolean',
    ) ||
    !(x.carForward || x.carReverse || x.footForward || x.footReverse) ||
    typeof x.lengthMetres !== 'number' ||
    !Number.isFinite(x.lengthMetres) ||
    x.lengthMetres <= 0 ||
    x.lengthMetres > 100_000
  )
    throw new Error('Invalid edge artifact');
  const geometry = x.geometry as Record<string, unknown> | null;
  if (
    !geometry ||
    geometry.type !== 'LineString' ||
    Object.keys(geometry).sort().join(',') !== 'coordinates,type' ||
    !Array.isArray(geometry.coordinates) ||
    geometry.coordinates.length < 2 ||
    geometry.coordinates.length > 10_000 ||
    !geometry.coordinates.every(
      (point: unknown) =>
        Array.isArray(point) &&
        point.length === 2 &&
        point.every((n) => typeof n === 'number' && Number.isFinite(n)) &&
        point[0] >= 90 &&
        point[0] <= 90.7 &&
        point[1] >= 23.5 &&
        point[1] <= 24.3,
    )
  )
    throw new Error('Invalid edge geometry');
  const points = geometry.coordinates as [number, number][];
  if (!points.some((point) => point[0] !== points[0]![0] || point[1] !== points[0]![1]))
    throw new Error('Degenerate edge geometry');
  return x;
}

/** Caller supplies a dedicated connected client, never Pool.query, so import
 * RPCs and rollback stay on the same transaction/session. */
export async function registerRoadGraph(
  client: PoolClient,
  path: string,
  progress?: (count: number) => void,
) {
  if (!isAbsolute(path) || !path.endsWith('.edges.jsonl'))
    throw new Error('Use an absolute edges artifact path');
  const info = await stat(path),
    manifestInfo = await stat(path + '.manifest.json');
  if (info.size < 10_000 || info.size > 256 * 1024 * 1024 || manifestInfo.size > 16_384)
    throw new Error('Invalid artifact size');
  const metadata = JSON.parse(await readFile(path + '.manifest.json', 'utf8')) as Metadata;
  if (
    !/^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$/.test(metadata.graphVersion ?? '') ||
    metadata.format !== 'awaaz-gh-edges-v1' ||
    !Number.isInteger(metadata.edgeCount) ||
    metadata.edgeCount < 1000 ||
    metadata.edgeCount > 1_000_000 ||
    ![
      metadata.engineSha256,
      metadata.configSha256,
      metadata.extractSha256,
      metadata.edgesSha256,
    ].every((v) => typeof v === 'string' && digest.test(v)) ||
    metadata.engineSha256 !== '8462f758d9ea49edaded557cec5c687a0a24f004ec371cd4daaeb0534824ea33' ||
    metadata.graphVersion !==
      `dhaka-gh11.1-${metadata.extractSha256.slice(0, 20)}-${metadata.configSha256.slice(0, 12)}` ||
    !Array.isArray(metadata.sourceGraphFiles) ||
    metadata.sourceGraphFiles.length < 8 ||
    metadata.sourceGraphFiles.length > 20 ||
    new Set(metadata.sourceGraphFiles.map((f) => f.name)).size !==
      metadata.sourceGraphFiles.length ||
    !['edges', 'nodes', 'geometry', 'properties'].every((name) =>
      metadata.sourceGraphFiles.some((f) => f.name === name),
    ) ||
    !Number.isFinite(Date.parse(metadata.importDate)) ||
    !Number.isFinite(Date.parse(metadata.sourceTimestamp)) ||
    Date.parse(metadata.sourceTimestamp) > Date.parse(metadata.importDate)
  )
    throw new Error('Invalid artifact provenance');
  const directory = dirname(path);
  const routing = JSON.parse(await readFile(join(directory, 'manifest.json'), 'utf8'));
  if (
    routing.graphVersion !== metadata.graphVersion ||
    routing.importDate !== metadata.importDate ||
    routing.osmBase !== metadata.sourceTimestamp ||
    routing.engineSha256 !== metadata.engineSha256 ||
    routing.configSha256 !== metadata.configSha256 ||
    routing.extractSha256 !== metadata.extractSha256
  )
    throw new Error('Routing manifest does not match edge export');
  for (const [file, expected] of [
    [join(directory, 'graphhopper-web-11.1.jar'), metadata.engineSha256],
    [join(directory, 'dhaka.osm'), metadata.extractSha256],
    [join(directory, '..', '..', 'backend', 'routing', 'graphhopper.yml'), metadata.configSha256],
  ] as const)
    if ((await fileDigest(file)) !== expected) throw new Error('Routing source digest mismatch');
  for (const file of metadata.sourceGraphFiles) {
    if (
      !/^[a-z_]+(?:\.txt)?$/.test(file.name) ||
      !digest.test(file.sha256) ||
      (await fileDigest(join(directory, metadata.graphVersion, file.name))) !== file.sha256
    )
      throw new Error('Graph cache digest mismatch');
  }
  if ((await fileDigest(path)) !== metadata.edgesSha256)
    throw new Error('Edge artifact digest mismatch');
  if (!(await evidenceWorkerAllowed(client)))
    throw new Error('Use the restricted evidence worker role');
  await client.query('BEGIN');
  try {
    const rpc = async (operation: string, data: object) => {
      const response = await client.query(
        'SELECT awaaz_private.graph_import($1::text,$2::jsonb) AS result',
        [operation, { graphVersion: metadata.graphVersion, ...data }],
      );
      return response.rows[0].result;
    };
    const begun = await rpc('begin', { metadata });
    if (begun.ready === true) {
      await client.query('COMMIT');
      return { graphVersion: metadata.graphVersion, edges: metadata.edgeCount, replayed: true };
    }
    let batch: object[] = [],
      count = 0,
      pending = '';
    const streamHash = createHash('sha256');
    const accept = async (line: string) => {
      if (!line || line.length > 512 * 1024) throw new Error('Invalid edge line');
      batch.push(edge(JSON.parse(line)));
      count++;
      if (count > metadata.edgeCount) throw new Error('Edge count mismatch');
      if (batch.length === 500) {
        const response = await rpc('append', { edges: batch });
        if (response.appended !== batch.length) throw new Error('Edge import incomplete');
        batch = [];
        if (count % 20_000 === 0) progress?.(count);
      }
    };
    // Async chunk iteration provides backpressure while each DB batch commits
    // into the open transaction. No complete-city JSON array is held in memory.
    for await (const chunk of createReadStream(path, { highWaterMark: 64 * 1024 })) {
      streamHash.update(chunk);
      pending += chunk.toString('utf8');
      let split: number;
      while ((split = pending.indexOf('\n')) >= 0) {
        const line = pending.slice(0, split).replace(/\r$/, '');
        pending = pending.slice(split + 1);
        await accept(line);
      }
      if (pending.length > 512 * 1024) throw new Error('Invalid edge line');
    }
    if (pending) await accept(pending);
    if (count !== metadata.edgeCount || streamHash.digest('hex') !== metadata.edgesSha256)
      throw new Error('Artifact changed during import');
    if (batch.length) await rpc('append', { edges: batch });
    const completed = await rpc('finalize', {});
    if (completed.ready !== true || completed.edges !== count)
      throw new Error('Edge import incomplete');
    await client.query('COMMIT');
    return { graphVersion: metadata.graphVersion, edges: count, replayed: false };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}
