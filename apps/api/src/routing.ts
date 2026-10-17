import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { DomainError } from './contracts.ts';

export type GeoPoint = { latitude: number; longitude: number };
export type RouteInput = {
  origin: GeoPoint;
  destination: GeoPoint;
  mode: 'car' | 'walk';
  includeReports?: boolean;
};
export type GeographicRoute = {
  id: string;
  preference: 'fastest' | 'reported';
  reportedEvidenceFraction?: number;
  durationSeconds: number;
  distanceMetres: number;
  points: [number, number][]; // Latitude, longitude; provider GeoJSON is reversed.
};
export type RoutePlan = {
  trafficAware: false;
  durationModel: 'osm_static_speed';
  graphVersion: string;
  riskVersion: string;
  riskLevel: 'unknown';
  evidenceCoverage: null;
  source: 'openstreetmap';
  sourceTimestamp: string;
  attribution: '© OpenStreetMap contributors';
  license: 'ODbL-1.0';
  generatedAt: string;
  expiresAt: string;
  origin: GeoPoint;
  destination: GeoPoint;
  mode: 'car' | 'walk';
  routes: GeographicRoute[];
  reportRouting?: {
    status: 'available' | 'no_evidence' | 'unavailable' | 'disabled' | 'same_route';
    synthetic: boolean;
  };
};
export interface RoutingService {
  readonly graphVersion?: string;
  ready(): Promise<boolean>;
  plan(input: RouteInput, signal?: AbortSignal): Promise<RoutePlan>;
  close?(): Promise<void>;
}
export type GraphManifest = {
  graphVersion: string;
  engineVersion: '11.1';
  importDate: string;
  osmBase: string;
};

export function inPilot(point: GeoPoint) {
  return (
    Number.isFinite(point.latitude) &&
    Number.isFinite(point.longitude) &&
    point.latitude >= 23.62 &&
    point.latitude <= 24.02 &&
    point.longitude >= 90.2 &&
    point.longitude <= 90.58
  );
}
export function distanceMetres(a: GeoPoint, b: GeoPoint) {
  const rad = Math.PI / 180;
  const h =
    Math.sin(((b.latitude - a.latitude) * rad) / 2) ** 2 +
    Math.cos(a.latitude * rad) *
      Math.cos(b.latitude * rad) *
      Math.sin(((b.longitude - a.longitude) * rad) / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new DomainError('routing_unavailable', 503);
  return value as Record<string, unknown>;
}
function validDate(value: unknown): value is string {
  return typeof value === 'string' && value.length <= 40 && Number.isFinite(Date.parse(value));
}
export function parseGraphManifest(value: unknown): GraphManifest {
  const v = record(value);
  if (
    typeof v.graphVersion !== 'string' ||
    !/^dhaka-gh11\.1-[a-f0-9]{20}-[a-f0-9]{12}$/.test(v.graphVersion) ||
    v.engineVersion !== '11.1' ||
    !validDate(v.importDate) ||
    !validDate(v.osmBase)
  ) {
    throw new Error('Confirm a prepared GraphHopper 11.1 graph before enabling routing');
  }
  return Object.freeze({
    graphVersion: v.graphVersion,
    engineVersion: '11.1',
    importDate: v.importDate,
    osmBase: v.osmBase,
  });
}

export class GraphHopperRouting implements RoutingService {
  get graphVersion() {
    return this.manifest.graphVersion;
  }
  readonly url: URL;
  readonly manifest: GraphManifest;
  #running = 0;
  constructor(url: string, manifest: GraphManifest) {
    this.url = new URL(url);
    if (
      this.url.username ||
      this.url.password ||
      this.url.search ||
      this.url.hash ||
      this.url.pathname !== '/' ||
      (this.url.protocol !== 'https:' &&
        !(
          this.url.protocol === 'http:' &&
          ['127.0.0.1', 'localhost', '[::1]'].includes(this.url.hostname)
        ))
    ) {
      throw new Error('GraphHopper requires a dedicated HTTPS endpoint or loopback HTTP');
    }
    this.manifest = parseGraphManifest(manifest);
  }

  async #request(path: string, signal: AbortSignal, body?: object): Promise<unknown> {
    const response = await fetch(new URL(path, this.url), {
      method: body ? 'POST' : 'GET',
      redirect: 'error',
      signal,
      headers: {
        accept: 'application/json',
        ...(body ? { 'content-type': 'application/json' } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    const maximum = path === '/info' ? 65536 : 262144;
    const length = Number(response.headers.get('content-length') ?? 0);
    if (length > maximum || !response.body) {
      await response.body?.cancel();
      throw new DomainError('routing_unavailable', 503);
    }
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let bytes = 0;
    try {
      for (;;) {
        const next = await reader.read();
        if (next.done) break;
        bytes += next.value.byteLength;
        if (bytes > maximum) throw new DomainError('routing_unavailable', 503);
        chunks.push(next.value);
      }
    } finally {
      await reader.cancel();
    }
    if (!response.ok) {
      if (path === '/route' && response.status === 400)
        throw new DomainError('route_unavailable', 422);
      throw new DomainError('routing_unavailable', 503);
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
  }

  async #check(signal: AbortSignal) {
    const info = record(await this.#request('/info', signal));
    if (
      info.version !== this.manifest.engineVersion ||
      info.import_date !== this.manifest.importDate ||
      !Array.isArray(info.profiles) ||
      !['car', 'foot'].every((name) =>
        (info.profiles as unknown[]).some((profile) => record(profile).name === name),
      )
    ) {
      throw new DomainError('routing_version_changed', 503);
    }
  }
  async ready() {
    try {
      await this.#check(AbortSignal.timeout(2000));
      return true;
    } catch {
      return false;
    }
  }

  async plan(input: RouteInput, cancellation?: AbortSignal): Promise<RoutePlan> {
    input = {
      origin: { ...input.origin },
      destination: { ...input.destination },
      mode: input.mode,
    };
    if (
      !inPilot(input.origin) ||
      !inPilot(input.destination) ||
      !['car', 'walk'].includes(input.mode)
    )
      throw new DomainError('outside_pilot', 400);
    if (distanceMetres(input.origin, input.destination) < 25)
      throw new DomainError('already_at_destination', 422);
    if (this.#running >= 2) throw new DomainError('routing_busy', 503);
    this.#running++;
    const deadline = AbortSignal.timeout(8000);
    const signal = cancellation ? AbortSignal.any([deadline, cancellation]) : deadline;
    try {
      // Verify the pinned import both before and after search. A replaced graph
      // is rejected instead of being labelled with an old version.
      await this.#check(signal);
      const result = record(
        await this.#request('/route', signal, {
          points: [
            [input.origin.longitude, input.origin.latitude],
            [input.destination.longitude, input.destination.latitude],
          ],
          profile: input.mode === 'car' ? 'car' : 'foot',
          algorithm: 'astarbi',
          'ch.disable': true,
          'lm.disable': true,
          instructions: false,
          points_encoded: false,
          min_path_precision: 1,
        }),
      );
      const paths = result.paths;
      if (!Array.isArray(paths) || paths.length !== 1)
        throw new DomainError('routing_unavailable', 503);
      const path = record(paths[0]);
      const geometry = record(path.points);
      if (
        geometry.type !== 'LineString' ||
        !Array.isArray(geometry.coordinates) ||
        geometry.coordinates.length < 2 ||
        geometry.coordinates.length > 2000 ||
        typeof path.time !== 'number' ||
        !Number.isFinite(path.time) ||
        path.time <= 0 ||
        path.time > 21600000 ||
        typeof path.distance !== 'number' ||
        !Number.isFinite(path.distance) ||
        path.distance < 1 ||
        path.distance > 100000
      ) {
        throw new DomainError('routing_unavailable', 503);
      }
      const points: [number, number][] = geometry.coordinates.map((coordinate: unknown) => {
        if (
          !Array.isArray(coordinate) ||
          coordinate.length !== 2 ||
          typeof coordinate[0] !== 'number' ||
          typeof coordinate[1] !== 'number'
        )
          throw new DomainError('routing_unavailable', 503);
        const point = { latitude: coordinate[1], longitude: coordinate[0] };
        if (!inPilot(point)) throw new DomainError('route_outside_pilot', 422);
        return [point.latitude, point.longitude];
      });
      const first = points[0]!,
        last = points.at(-1)!;
      if (
        distanceMetres(input.origin, { latitude: first[0], longitude: first[1] }) > 50 ||
        distanceMetres(input.destination, { latitude: last[0], longitude: last[1] }) > 75
      ) {
        throw new DomainError('route_snap_too_far', 422);
      }
      let length = 0;
      for (let i = 1; i < points.length; i++) {
        const a = points[i - 1]!,
          b = points[i]!;
        length += distanceMetres(
          { latitude: a[0], longitude: a[1] },
          { latitude: b[0], longitude: b[1] },
        );
      }
      if (
        length < 1 ||
        length > 100000 ||
        Math.abs(length - path.distance) > Math.max(100, path.distance * 0.05)
      ) {
        throw new DomainError('routing_unavailable', 503);
      }
      await this.#check(signal);
      const now = new Date();
      return {
        trafficAware: false,
        durationModel: 'osm_static_speed',
        graphVersion: this.manifest.graphVersion,
        riskVersion: 'unknown-v1',
        riskLevel: 'unknown',
        evidenceCoverage: null,
        source: 'openstreetmap',
        sourceTimestamp: this.manifest.osmBase,
        attribution: '© OpenStreetMap contributors',
        license: 'ODbL-1.0',
        generatedAt: now.toISOString(),
        expiresAt: new Date(now.getTime() + 300000).toISOString(),
        origin: { ...input.origin },
        destination: { ...input.destination },
        mode: input.mode,
        routes: [
          {
            id: randomUUID(),
            preference: 'fastest',
            durationSeconds: Math.ceil(path.time / 1000),
            distanceMetres: path.distance,
            points,
          },
        ],
      };
    } catch (error) {
      if (error instanceof DomainError) throw error;
      throw new DomainError('routing_unavailable', 503);
    } finally {
      this.#running--;
    }
  }
}

export async function routingFromEnvironment(env: Record<string, string | undefined>) {
  const url = env.AWAAZ_GRAPHHOPPER_URL?.trim(),
    path = env.AWAAZ_ROUTING_MANIFEST?.trim();
  if (!url && !path) return undefined;
  if (!url || !path || !isAbsolute(path))
    throw new Error('Supply a router URL and absolute confirmed graph manifest path');
  const contents = await readFile(path, 'utf8');
  if (contents.length > 16384) throw new Error('Unexpected graph manifest size');
  const router = new GraphHopperRouting(
    url,
    parseGraphManifest(JSON.parse(contents.replace(/^\uFEFF/, '')) as unknown),
  );
  // Router availability is a separate capability. A stopped router must not
  // prevent the account/reporting API (or future help delivery) from starting.
  return router;
}
