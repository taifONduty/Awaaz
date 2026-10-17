import { createHash } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { DomainError } from './contracts.ts';
import { inPilot, distanceMetres } from './routing.ts';
import type { GeoPoint } from './routing.ts';

export const placeKinds = [
  'road',
  'education',
  'health',
  'transit',
  'shop',
  'area',
  'place',
] as const;
export type Place = {
  id: string;
  name: string;
  nameEn: string;
  nameBn: string;
  kind: (typeof placeKinds)[number];
  point: GeoPoint;
};
export type PlaceSearchResult = {
  graphVersion: string;
  datasetVersion: string;
  sourceTimestamp: string;
  source: 'openstreetmap';
  license: 'ODbL-1.0';
  attribution: '© OpenStreetMap contributors';
  coverage: 'imported_places_only';
  items: Place[];
};
const normalized = (value: string) =>
  value
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\p{N}]+/gu, ' ')
    .trim();
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === 'object' && !Array.isArray(v);
const name = (v: unknown): v is string =>
  typeof v === 'string' && [...v].length > 0 && [...v].length <= 160 && !/[\p{Cc}]/u.test(v);
const bad = () => new Error('Invalid or mismatched place catalogue');

export class PlaceCatalogue {
  readonly graphVersion: string;
  readonly datasetVersion: string;
  readonly sourceTimestamp: string;
  readonly #entries: { value: Place; aliases: string[] }[];
  constructor(data: unknown, sha256: string, expectedGraph: string) {
    if (
      !record(data) ||
      data.format !== 'awaaz-place-catalog-v1' ||
      data.graphVersion !== expectedGraph ||
      !/^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$/.test(expectedGraph) ||
      !/^[0-9a-f]{64}$/.test(sha256) ||
      typeof data.sourceTimestamp !== 'string' ||
      data.sourceTimestamp.length > 40 ||
      !Number.isFinite(Date.parse(data.sourceTimestamp)) ||
      Date.parse(data.sourceTimestamp) > Date.now() + 300000 ||
      !Array.isArray(data.items) ||
      data.items.length > 50000 ||
      !data.items.length
    )
      throw bad();
    this.graphVersion = expectedGraph;
    this.datasetVersion = 'dhaka-places-v1-' + sha256.slice(0, 20);
    this.sourceTimestamp = data.sourceTimestamp;
    const ids = new Set<string>();
    this.#entries = data.items.map((raw: unknown) => {
      if (
        !record(raw) ||
        typeof raw.id !== 'string' ||
        !/^osm:(node|way|relation):[1-9][0-9]{0,19}$/.test(raw.id) ||
        ids.has(raw.id) ||
        !name(raw.name) ||
        !name(raw.nameEn) ||
        !name(raw.nameBn) ||
        !placeKinds.includes(raw.kind as Place['kind']) ||
        !record(raw.point) ||
        typeof raw.point.latitude !== 'number' ||
        typeof raw.point.longitude !== 'number' ||
        !inPilot(raw.point as GeoPoint) ||
        !Array.isArray(raw.aliases) ||
        raw.aliases.length > 8 ||
        !raw.aliases.every(name)
      )
        throw bad();
      ids.add(raw.id);
      const value: Place = {
        id: raw.id,
        name: raw.name,
        nameEn: raw.nameEn,
        nameBn: raw.nameBn,
        kind: raw.kind as Place['kind'],
        point: { latitude: raw.point.latitude, longitude: raw.point.longitude },
      };
      return {
        value,
        aliases: [
          ...new Set(
            [value.name, value.nameEn, value.nameBn, ...(raw.aliases as string[])].map(normalized),
          ),
        ],
      };
    });
  }
  search(query: string): PlaceSearchResult {
    if (
      typeof query !== 'string' ||
      [...query.trim()].length < 2 ||
      [...query].length > 80 ||
      /[\p{Cc}]/u.test(query)
    )
      throw new DomainError('place_query_invalid', 400);
    const q = normalized(query),
      tokens = q.split(' ');
    if ([...q].length < 2 || tokens.length > 12) throw new DomainError('place_query_invalid', 400);
    const best: { value: Place; score: number }[] = [];
    for (const entry of this.#entries) {
      let score = Infinity;
      for (const alias of entry.aliases) {
        if (alias === q) score = Math.min(score, 0);
        else if (alias.startsWith(q)) score = Math.min(score, 1);
        else if (tokens.every((t) => alias.includes(t))) score = Math.min(score, 2);
      }
      if (!Number.isFinite(score)) continue;
      if (
        best.some(
          (v) =>
            v.value.kind === entry.value.kind &&
            normalized(v.value.nameEn) === normalized(entry.value.nameEn) &&
            distanceMetres(v.value.point, entry.value.point) < 200,
        )
      )
        continue;
      best.push({ value: entry.value, score: score * 10 + (entry.value.kind === 'road' ? 2 : 0) });
      best.sort(
        (a, b) =>
          a.score - b.score ||
          a.value.name.localeCompare(b.value.name, 'en') ||
          a.value.id.localeCompare(b.value.id),
      );
      if (best.length > 8) best.pop();
    }
    return {
      graphVersion: this.graphVersion,
      datasetVersion: this.datasetVersion,
      sourceTimestamp: this.sourceTimestamp,
      source: 'openstreetmap',
      license: 'ODbL-1.0',
      attribution: '© OpenStreetMap contributors',
      coverage: 'imported_places_only',
      items: best.map((v) => ({ ...v.value, point: { ...v.value.point } })),
    };
  }
}

export async function placesFromEnvironment(
  env: Record<string, string | undefined>,
  graphVersion?: string,
) {
  const file = env.AWAAZ_PLACE_CATALOG_FILE?.trim();
  if (!file) return undefined;
  if (!isAbsolute(file) || !graphVersion || (await stat(file)).size > 12000000) throw bad();
  const bytes = await readFile(file);
  const manifest: unknown = JSON.parse(await readFile(file + '.manifest.json', 'utf8'));
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  if (
    !record(manifest) ||
    manifest.sha256 !== sha256 ||
    manifest.graphVersion !== graphVersion ||
    manifest.format !== 'awaaz-place-catalog-v1'
  )
    throw bad();
  return new PlaceCatalogue(JSON.parse(bytes.toString('utf8')), sha256, graphVersion);
}
