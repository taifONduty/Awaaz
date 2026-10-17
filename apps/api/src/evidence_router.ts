import { spawn } from 'node:child_process';
import type { ChildProcessWithoutNullStreams } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { isAbsolute, join, dirname } from 'node:path';
import { fileDigest } from './road_graph.ts';
import { DomainError } from './contracts.ts';
import type { GeoPoint, GraphManifest } from './routing.ts';
import type { EvidenceMetadata } from './evidence.ts';
import { distanceMetres } from './routing.ts';
import type { RouteInput } from './routing.ts';
import { exportEvidence } from './evidence.ts';
import type { EvidenceStore } from './evidence.ts';

export type EnginePath = {
  graphVersion: string;
  importDate: string;
  weightingVersion: string;
  snapshotId?: string;
  evidenceEpoch?: string;
  graphMetadataDigest?: string;
  safetyAssessment: 'unknown';
  distanceMetres: number;
  durationSeconds: number;
  cost: number;
  points: [number, number][];
  edges: { edgeId: number; first: number; last: number }[];
};
type Pending = {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
  cleanup: () => void;
};
const unavailable = () => new DomainError('routing_unavailable', 503);

export class EvidenceRouterWorker {
  readonly manifest: GraphManifest;
  readonly child: ChildProcessWithoutNullStreams;
  readonly startup: Promise<void>;
  #pending = new Map<string, Pending>();
  #buffer = '';
  #ready = false;
  #closed = false;
  #startupResolve!: () => void;
  #startupReject!: (error: Error) => void;
  #startupTimer: ReturnType<typeof setTimeout>;
  private constructor(
    java: string,
    jar: string,
    source: string,
    config: string,
    cache: string,
    artifacts: string,
    manifest: GraphManifest,
  ) {
    if (![java, jar, source, config, cache, artifacts].every(isAbsolute)) throw unavailable();
    this.manifest = manifest;
    this.startup = new Promise((resolve, reject) => {
      this.#startupResolve = resolve;
      this.#startupReject = reject;
    });
    // No database, Auth, signing or Maps credentials enter the Java environment.
    const env: Record<string, string> = {};
    for (const name of [
      'PATH',
      'SystemRoot',
      'WINDIR',
      'TEMP',
      'TMP',
      'USERPROFILE',
      'HOME',
      'LANG',
    ])
      if (process.env[name]) env[name] = process.env[name]!;
    this.child = spawn(
      java,
      [
        '-Xmx512m',
        '-XX:ActiveProcessorCount=2',
        `-Dlogback.configurationFile=${join(dirname(source), 'worker-logback.xml')}`,
        '--class-path',
        jar,
        source,
        cache,
        config,
        manifest.graphVersion,
        manifest.importDate,
        artifacts,
      ],
      { windowsHide: true, env, stdio: 'pipe' },
    );
    this.#startupTimer = setTimeout(() => this.#failure(), 45000);
    this.#startupTimer.unref();
    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', (chunk: string) => {
      this.#buffer += chunk;
      if (this.#buffer.length > 512 * 1024) return this.#failure();
      let split: number;
      while ((split = this.#buffer.indexOf('\n')) >= 0) {
        const line = this.#buffer.slice(0, split).replace(/\r$/, '');
        this.#buffer = this.#buffer.slice(split + 1);
        try {
          this.#message(JSON.parse(line));
        } catch {
          this.#failure();
        }
      }
    });
    // Drain, but never forward library stderr, paths or coordinates into logs.
    this.child.stderr.resume();
    this.child.on('error', () => this.#failure());
    this.child.on('exit', () => this.#failure());
  }
  #failure() {
    this.#ready = false;
    this.#closed = true;
    clearTimeout(this.#startupTimer);
    this.#startupReject(unavailable());
    for (const pending of this.#pending.values()) {
      clearTimeout(pending.timer);
      pending.cleanup();
      pending.reject(unavailable());
    }
    this.#pending.clear();
    if (this.child.exitCode === null && !this.child.killed) this.child.kill();
  }
  #message(value: Record<string, unknown>) {
    if (!this.#ready && value.ready === true) {
      if (
        value.graphVersion !== this.manifest.graphVersion ||
        value.importDate !== this.manifest.importDate ||
        value.engineVersion !== '11.1'
      )
        return this.#failure();
      this.#ready = true;
      clearTimeout(this.#startupTimer);
      this.#startupResolve();
      return;
    }
    const pending = this.#pending.get(String(value.id));
    if (!pending) return; // A canceled search may finish; it cannot satisfy another request.
    this.#pending.delete(String(value.id));
    clearTimeout(pending.timer);
    pending.cleanup();
    if (value.error)
      pending.reject(
        typeof value.error === 'string' &&
          [
            'route_unavailable',
            'outside_pilot',
            'snapshot_expired',
            'graph_mismatch',
            'invalid_snapshot',
          ].includes(value.error)
          ? new DomainError(
              value.error,
              value.error === 'route_unavailable' || value.error === 'outside_pilot' ? 422 : 503,
            )
          : unavailable(),
      );
    else pending.resolve(value.result);
  }
  async ready() {
    try {
      await this.startup;
      return this.#ready && !this.#closed;
    } catch {
      return false;
    }
  }
  async route(
    origin: GeoPoint,
    destination: GeoPoint,
    mode: 'car' | 'walk',
    algorithm: 'astarbi' | 'dijkstrabi' = 'astarbi',
    artifact?: { sha256: string; metadata: EvidenceMetadata },
    signal?: AbortSignal,
  ): Promise<EnginePath> {
    await this.startup;
    if (!this.#ready || this.#closed || signal?.aborted || this.#pending.size >= 2)
      throw unavailable();
    const id = randomUUID();
    const result = await new Promise<unknown>((resolve, reject) => {
      const abort = () => {
        const p = this.#pending.get(id);
        if (!p) return;
        this.#pending.delete(id);
        clearTimeout(p.timer);
        p.cleanup();
        reject(unavailable());
      };
      const timer = setTimeout(abort, 10000);
      timer.unref();
      this.#pending.set(id, {
        resolve,
        reject,
        timer,
        cleanup: () => signal?.removeEventListener('abort', abort),
      });
      signal?.addEventListener('abort', abort, { once: true });
      this.child.stdin.write(
        JSON.stringify({
          id,
          origin,
          destination,
          mode,
          algorithm,
          ...(artifact ? { snapshot: { id: artifact.metadata.id, sha256: artifact.sha256 } } : {}),
        }) + '\n',
        (error) => {
          if (error) abort();
        },
      );
    });
    if (!result || typeof result !== 'object') throw unavailable();
    const r = result as EnginePath;
    if (
      r.graphVersion !== this.manifest.graphVersion ||
      r.importDate !== this.manifest.importDate ||
      r.safetyAssessment !== 'unknown' ||
      !Number.isFinite(r.cost) ||
      r.cost <= 0 ||
      !Number.isFinite(r.distanceMetres) ||
      r.distanceMetres <= 0 ||
      r.distanceMetres > 100000 ||
      !Number.isInteger(r.durationSeconds) ||
      r.durationSeconds < 1 ||
      r.durationSeconds > 21600 ||
      !Array.isArray(r.points) ||
      r.points.length < 2 ||
      r.points.length > 2000 ||
      !r.points.every(
        (p) =>
          Array.isArray(p) &&
          p.length === 2 &&
          p.every(Number.isFinite) &&
          p[0] >= 23.62 &&
          p[0] <= 24.02 &&
          p[1] >= 90.2 &&
          p[1] <= 90.58,
      ) ||
      !Array.isArray(r.edges) ||
      !r.edges.length ||
      r.edges.length > 2000
    )
      throw unavailable();
    let previous = 0;
    for (const edge of r.edges) {
      if (
        !Number.isInteger(edge.edgeId) ||
        edge.edgeId < 0 ||
        edge.edgeId > 10000000 ||
        !Number.isInteger(edge.first) ||
        !Number.isInteger(edge.last) ||
        edge.first !== previous ||
        edge.last < edge.first ||
        edge.last >= r.points.length
      )
        throw unavailable();
      previous = edge.last;
    }
    if (
      previous !== r.points.length - 1 ||
      r.weightingVersion !== (artifact ? 'reviewed-time-v1-alpha2' : 'osm-static-time-v1')
    )
      throw unavailable();
    if (
      artifact &&
      (r.snapshotId !== artifact.metadata.id ||
        r.evidenceEpoch !== artifact.metadata.evidenceEpoch ||
        r.graphMetadataDigest !== artifact.metadata.graphMetadataDigest)
    )
      throw unavailable();
    if (!artifact && (r.snapshotId || r.evidenceEpoch || r.graphMetadataDigest))
      throw unavailable();
    const first = r.points[0]!,
      last = r.points.at(-1)!;
    if (
      distanceMetres(origin, { latitude: first[0], longitude: first[1] }) > 50 ||
      distanceMetres(destination, { latitude: last[0], longitude: last[1] }) > 75
    )
      throw new DomainError('snap_too_far', 422);
    let length = 0;
    for (let i = 1; i < r.points.length; i++)
      length += distanceMetres(
        { latitude: r.points[i - 1]![0], longitude: r.points[i - 1]![1] },
        { latitude: r.points[i]![0], longitude: r.points[i]![1] },
      );
    if (Math.abs(length - r.distanceMetres) > Math.max(100, r.distanceMetres * 0.05))
      throw unavailable();
    return r;
  }
  async close() {
    this.#failure();
  }
  static async create(
    java: string,
    jar: string,
    source: string,
    config: string,
    cache: string,
    artifacts: string,
    manifest: GraphManifest,
  ) {
    if (
      (await fileDigest(jar)) !== '8462f758d9ea49edaded557cec5c687a0a24f004ec371cd4daaeb0534824ea33'
    )
      throw unavailable();
    const worker = new EvidenceRouterWorker(java, jar, source, config, cache, artifacts, manifest);
    await worker.startup;
    return worker;
  }
}

/** Database epoch checks belong at the caller boundary, not in an offline
 * artifact. An update while search runs invalidates this result before return.
 */
export class EvidenceRoutingCoordinator {
  readonly worker: Pick<EvidenceRouterWorker, 'route' | 'manifest'>;
  readonly store: EvidenceStore;
  readonly directory: string;
  constructor(
    worker: Pick<EvidenceRouterWorker, 'route' | 'manifest'>,
    store: EvidenceStore,
    directory: string,
  ) {
    this.worker = worker;
    this.store = store;
    this.directory = directory;
  }
  async route(input: RouteInput, signal?: AbortSignal) {
    const captured = {
      origin: { ...input.origin },
      destination: { ...input.destination },
      mode: input.mode,
    };
    const selected = await this.store.current(this.worker.manifest.graphVersion);
    if (!selected) throw new DomainError('evidence_unavailable', 503);
    const artifact = await exportEvidence(this.store, selected.id, this.directory);
    if (artifact.metadata.graphVersion !== this.worker.manifest.graphVersion || signal?.aborted)
      throw unavailable();
    const result = await this.worker.route(
      captured.origin,
      captured.destination,
      captured.mode,
      'astarbi',
      artifact,
      signal,
    );
    const final = await this.store.read(selected.id, 10000000);
    if (JSON.stringify(final.metadata) !== JSON.stringify(artifact.metadata) || signal?.aborted)
      throw new DomainError('evidence_unavailable', 503);
    return { path: result, metadata: final.metadata };
  }
}
