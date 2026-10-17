import { createHash, randomUUID } from 'node:crypto';
import { mkdir, open, rename, unlink, writeFile } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { DomainError } from './contracts.ts';
import type { SqlExecutor } from './postgres.ts';
import { evidenceWorkerAllowed } from './database_roles.ts';

export type EvidenceMetadata = {
  id: string;
  graphVersion: string;
  scoringVersion: 'reviewed-decay-v1';
  createdAt: string;
  expiresAt: string;
  evidenceEpoch: string;
  graphMetadataDigest: string;
  registeredEdgeCount: number;
  evidencedEdgeCount: number;
  safetyCoverage: null;
  source: 'openstreetmap';
  license: 'ODbL-1.0';
  attribution: '© OpenStreetMap contributors';
  sourceGraphFiles: { name: string; sha256: string }[];
  unknownDefault: { evidenceIndex: null; confidence: 0; uncertainty: 1; eventClusterCount: 0 };
};
export type EvidenceEdge = {
  edgeId: number;
  forwardKey: number;
  reverseKey: number;
  carForward: boolean;
  carReverse: boolean;
  footForward: boolean;
  footReverse: boolean;
  evidenceIndex: number;
  incidentIndex: number | null;
  environmentIndex: number | null;
  confidence: 0;
  uncertainty: 1;
  eventClusterCount: number;
  categories: Record<string, { clusters: number; lastObservedAt: string }>;
  lastObservedAt: string;
};
export type EvidencePage = {
  metadata: EvidenceMetadata;
  items: EvidenceEdge[];
  nextEdgeId: number | null;
};
export type UnknownEvidenceEdge = Omit<
  EvidenceEdge,
  'evidenceIndex' | 'incidentIndex' | 'environmentIndex' | 'lastObservedAt' | 'eventClusterCount'
> & {
  evidenceIndex: null;
  incidentIndex: null;
  environmentIndex: null;
  lastObservedAt: null;
  eventClusterCount: 0;
};
export interface EvidenceStore {
  current(graphVersion: string): Promise<{ id: string } | null>;
  read(id: string, after?: number): Promise<EvidencePage>;
  edge(
    id: string,
    edgeId: number,
  ): Promise<{ metadata: EvidenceMetadata; edge: EvidenceEdge | UnknownEvidenceEdge }>;
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const graph = /^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$/;
const hex = /^[0-9a-f]{64}$/;
const categories = new Set(['lighting', 'obstruction', 'other', 'theft', 'harassment', 'accident']);
function fail(): never {
  throw new DomainError('evidence_unavailable', 503);
}
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fail();
  return value as Record<string, unknown>;
}
function keys(value: Record<string, unknown>, expected: string[]) {
  if (Object.keys(value).sort().join(',') !== expected.sort().join(',')) fail();
}
function integer(v: unknown, min: number, max: number): v is number {
  return Number.isInteger(v) && (v as number) >= min && (v as number) <= max;
}
function date(v: unknown): v is string {
  return typeof v === 'string' && v.length <= 40 && Number.isFinite(Date.parse(v));
}
function index(v: unknown, nullable = false): boolean {
  return (
    (nullable && v === null) || (typeof v === 'number' && Number.isFinite(v) && v > 0 && v <= 0.8)
  );
}
export function parseEvidencePage(value: unknown, id: string, after: number): EvidencePage {
  const page = record(value);
  keys(page, ['metadata', 'items', 'nextEdgeId']);
  const m = record(page.metadata);
  keys(m, [
    'id',
    'graphVersion',
    'scoringVersion',
    'createdAt',
    'expiresAt',
    'evidenceEpoch',
    'graphMetadataDigest',
    'registeredEdgeCount',
    'evidencedEdgeCount',
    'safetyCoverage',
    'source',
    'license',
    'attribution',
    'sourceGraphFiles',
    'unknownDefault',
  ]);
  if (
    m.id !== id ||
    !uuid.test(id) ||
    typeof m.graphVersion !== 'string' ||
    !graph.test(m.graphVersion) ||
    m.scoringVersion !== 'reviewed-decay-v1' ||
    !date(m.createdAt) ||
    !date(m.expiresAt) ||
    Date.parse(m.createdAt) > Date.now() + 5000 ||
    Date.parse(m.expiresAt) <= Date.now() ||
    Date.parse(m.expiresAt) <= Date.parse(m.createdAt) ||
    Date.parse(m.expiresAt) - Date.parse(m.createdAt) > 120_001 ||
    typeof m.evidenceEpoch !== 'string' ||
    !/^(?:0|[1-9][0-9]{0,18})$/.test(m.evidenceEpoch) ||
    BigInt(m.evidenceEpoch) > 9223372036854775807n ||
    typeof m.graphMetadataDigest !== 'string' ||
    !hex.test(m.graphMetadataDigest) ||
    !integer(m.registeredEdgeCount, 1000, 1000000) ||
    !integer(m.evidencedEdgeCount, 0, m.registeredEdgeCount) ||
    m.safetyCoverage !== null ||
    m.source !== 'openstreetmap' ||
    m.license !== 'ODbL-1.0' ||
    m.attribution !== '© OpenStreetMap contributors'
  )
    fail();
  const unknown = record(m.unknownDefault);
  keys(unknown, ['evidenceIndex', 'confidence', 'uncertainty', 'eventClusterCount']);
  if (
    unknown.evidenceIndex !== null ||
    unknown.confidence !== 0 ||
    unknown.uncertainty !== 1 ||
    unknown.eventClusterCount !== 0
  )
    fail();
  if (
    !Array.isArray(m.sourceGraphFiles) ||
    m.sourceGraphFiles.length < 8 ||
    m.sourceGraphFiles.length > 20
  )
    fail();
  const names = new Set<string>();
  for (const file of m.sourceGraphFiles) {
    const f = record(file);
    keys(f, ['name', 'sha256']);
    if (
      typeof f.name !== 'string' ||
      !/^[a-z_]+(?:\.txt)?$/.test(f.name) ||
      names.has(f.name) ||
      typeof f.sha256 !== 'string' ||
      !hex.test(f.sha256)
    )
      fail();
    names.add(f.name);
  }
  if (!['nodes', 'edges', 'geometry', 'properties'].every((name) => names.has(name))) fail();
  if (!Array.isArray(page.items) || page.items.length > 500) fail();
  let previous = after;
  for (const item of page.items) {
    const e = record(item);
    keys(e, [
      'edgeId',
      'forwardKey',
      'reverseKey',
      'carForward',
      'carReverse',
      'footForward',
      'footReverse',
      'evidenceIndex',
      'incidentIndex',
      'environmentIndex',
      'confidence',
      'uncertainty',
      'eventClusterCount',
      'categories',
      'lastObservedAt',
    ]);
    if (
      !integer(e.edgeId, 0, 10000000) ||
      e.edgeId <= previous ||
      e.forwardKey !== e.edgeId * 2 ||
      e.reverseKey !== e.edgeId * 2 + 1 ||
      !['carForward', 'carReverse', 'footForward', 'footReverse'].every(
        (key) => typeof e[key] === 'boolean',
      ) ||
      !(e.carForward || e.carReverse || e.footForward || e.footReverse) ||
      !index(e.evidenceIndex) ||
      !index(e.incidentIndex, true) ||
      !index(e.environmentIndex, true) ||
      (e.incidentIndex === null && e.environmentIndex === null) ||
      e.confidence !== 0 ||
      e.uncertainty !== 1 ||
      !integer(e.eventClusterCount, 1, 1000000) ||
      !date(e.lastObservedAt) ||
      Date.parse(e.lastObservedAt) > Date.parse(m.createdAt) + 300000
    )
      fail();
    const c = record(e.categories);
    if (!Object.keys(c).length || !Object.keys(c).every((name) => categories.has(name))) fail();
    let total = 0,
      latest = -Infinity;
    for (const value of Object.values(c)) {
      const category = record(value);
      keys(category, ['clusters', 'lastObservedAt']);
      if (!integer(category.clusters, 1, 1000000) || !date(category.lastObservedAt)) fail();
      total += category.clusters;
      latest = Math.max(latest, Date.parse(category.lastObservedAt));
    }
    if (total !== e.eventClusterCount || latest !== Date.parse(e.lastObservedAt)) fail();
    previous = e.edgeId;
  }
  if (
    page.nextEdgeId !== null &&
    (!integer(page.nextEdgeId, 0, 10000000) ||
      page.items.length !== 500 ||
      page.nextEdgeId !== previous)
  )
    fail();
  if (page.items.length > m.evidencedEdgeCount) fail();
  return page as unknown as EvidencePage;
}
async function query(db: SqlExecutor, sql: string, values: unknown[]) {
  try {
    const result = await db.query(sql, values);
    if (!result.rows[0] || !Object.hasOwn(result.rows[0], 'result')) return fail();
    return result.rows[0].result;
  } catch {
    return fail();
  }
}
export function postgresEvidence(db: SqlExecutor): EvidenceStore {
  return {
    edge: async (id, edgeId) => {
      if (!uuid.test(id) || !integer(edgeId, 0, 10000000)) return fail();
      const v = record(
        await query(db, 'SELECT awaaz_private.read_evidence_edge($1::uuid,$2::integer) AS result', [
          id,
          edgeId,
        ]),
      );
      keys(v, ['metadata', 'edge']);
      const metadata = parseEvidencePage(
        { metadata: v.metadata, items: [], nextEdgeId: null },
        id,
        -1,
      ).metadata;
      const e = record(v.edge);
      if (e.edgeId !== edgeId) return fail();
      if (e.eventClusterCount !== 0) {
        const parsed = parseEvidencePage({ metadata, items: [e], nextEdgeId: null }, id, -1);
        return { metadata, edge: parsed.items[0]! };
      }
      keys(e, [
        'edgeId',
        'forwardKey',
        'reverseKey',
        'carForward',
        'carReverse',
        'footForward',
        'footReverse',
        'evidenceIndex',
        'incidentIndex',
        'environmentIndex',
        'confidence',
        'uncertainty',
        'eventClusterCount',
        'categories',
        'lastObservedAt',
      ]);
      if (
        e.forwardKey !== edgeId * 2 ||
        e.reverseKey !== edgeId * 2 + 1 ||
        !['carForward', 'carReverse', 'footForward', 'footReverse'].every(
          (key) => typeof e[key] === 'boolean',
        ) ||
        !(e.carForward || e.carReverse || e.footForward || e.footReverse) ||
        e.evidenceIndex !== null ||
        e.incidentIndex !== null ||
        e.environmentIndex !== null ||
        e.confidence !== 0 ||
        e.uncertainty !== 1 ||
        e.lastObservedAt !== null ||
        Object.keys(record(e.categories)).length
      )
        return fail();
      return { metadata, edge: e as unknown as UnknownEvidenceEdge };
    },
    current: async (version) => {
      if (!graph.test(version)) return fail();
      const value = await query(
        db,
        'SELECT awaaz_private.current_evidence_snapshot($1::text) AS result',
        [version],
      );
      if (value === null) return null;
      const v = record(value);
      keys(v, ['id']);
      if (typeof v.id !== 'string' || !uuid.test(v.id)) return fail();
      return { id: v.id };
    },
    read: async (id, after = -1) => {
      if (!uuid.test(id) || !integer(after, -1, 10000000)) return fail();
      return parseEvidencePage(
        await query(
          db,
          'SELECT awaaz_private.read_evidence_snapshot($1::uuid,$2::integer) AS result',
          [id, after],
        ),
        id,
        after,
      );
    },
  };
}
export async function buildEvidenceSnapshot(db: SqlExecutor, version: string) {
  if (!graph.test(version) || !(await evidenceWorkerAllowed(db))) return fail();
  await query(db, 'SELECT awaaz_private.prune_evidence_snapshots() AS result', []);
  const value = record(
    await query(db, 'SELECT awaaz_private.build_evidence_snapshot($1::text) AS result', [version]),
  );
  keys(value, ['id', 'replayed']);
  if (typeof value.id !== 'string' || !uuid.test(value.id) || typeof value.replayed !== 'boolean')
    return fail();
  return { id: value.id, replayed: value.replayed };
}

/** Artifacts are immutable but not a revocation oracle: routing must recheck
 * live epoch/expiry before and after use. Exports contain no reporter identity. */
export async function exportEvidence(store: EvidenceStore, id: string, directory: string) {
  if (!isAbsolute(directory) || !uuid.test(id)) return fail();
  await mkdir(directory, { recursive: true, mode: 0o770 });
  const target = join(directory, id + '.jsonl'),
    partial = target + '.' + randomUUID() + '.partial';
  const handle = await open(partial, 'wx', 0o640);
  const hash = createHash('sha256');
  let closed = false;
  try {
    let page = await store.read(id),
      after = -1,
      count = 0;
    const metadata = JSON.stringify(page.metadata);
    const write = async (text: string) => {
      hash.update(text, 'utf8');
      await handle.writeFile(text, 'utf8');
    };
    await write(JSON.stringify({ format: 'awaaz-evidence-v1', metadata: page.metadata }) + '\n');
    for (;;) {
      if (JSON.stringify(page.metadata) !== metadata) return fail();
      count += page.items.length;
      if (count > page.metadata.evidencedEdgeCount) return fail();
      if (page.items.length)
        await write(page.items.map((item) => JSON.stringify(item)).join('\n') + '\n');
      if (page.nextEdgeId === null) break;
      after = page.nextEdgeId;
      page = await store.read(id, after);
    }
    if (count !== page.metadata.evidencedEdgeCount) return fail();
    const final = await store.read(id, 10000000);
    if (
      JSON.stringify(final.metadata) !== metadata ||
      final.items.length ||
      Date.parse(final.metadata.expiresAt) <= Date.now() + 1000
    )
      return fail();
    await handle.sync();
    await handle.close();
    closed = true;
    await rename(partial, target);
    const sha256 = hash.digest('hex');
    const manifestPartial = target + '.' + randomUUID() + '.manifest.partial';
    try {
      await writeFile(
        manifestPartial,
        JSON.stringify(
          {
            id,
            graphVersion: page.metadata.graphVersion,
            evidenceEpoch: page.metadata.evidenceEpoch,
            graphMetadataDigest: page.metadata.graphMetadataDigest,
            expiresAt: page.metadata.expiresAt,
            edges: count,
            sha256,
          },
          null,
          2,
        ) + '\n',
        { mode: 0o640, flag: 'wx' },
      );
      await rename(manifestPartial, target + '.manifest.json');
    } catch (error) {
      await unlink(manifestPartial).catch(() => {});
      throw error;
    }
    return { path: target, sha256, metadata: page.metadata };
  } catch (error) {
    if (!closed) await handle.close();
    await unlink(partial).catch(() => {});
    throw error;
  }
}
