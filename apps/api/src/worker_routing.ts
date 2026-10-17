import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join, dirname, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DomainError } from './contracts.ts';
import { inPilot, distanceMetres, parseGraphManifest } from './routing.ts';
import type { RouteInput, RoutePlan, RoutingService, GraphManifest } from './routing.ts';
import type { EvidenceStore, EvidenceMetadata } from './evidence.ts';
import { EvidenceRouterWorker, EvidenceRoutingCoordinator } from './evidence_router.ts';
import type { EnginePath } from './evidence_router.ts';

export class WorkerRouting implements RoutingService {
  readonly manifest: GraphManifest;
  readonly artifacts: string;
  readonly startup: Promise<EvidenceRouterWorker>;
  readonly evidence: EvidenceStore;
  readonly experimental: boolean;
  readonly synthetic: boolean;
  #worker?: EvidenceRouterWorker;
  #closed = false;
  #running = 0;
  get graphVersion() {
    return this.manifest.graphVersion;
  }
  constructor(
    startup: Promise<EvidenceRouterWorker>,
    manifest: GraphManifest,
    evidence: EvidenceStore,
    artifacts: string,
    experimental: boolean,
    synthetic = false,
  ) {
    this.startup = startup;
    this.manifest = manifest;
    this.evidence = evidence;
    this.artifacts = artifacts;
    this.experimental = experimental;
    this.synthetic = synthetic;
    void startup
      .then((worker) => {
        this.#worker = worker;
        if (this.#closed) void worker.close();
      })
      .catch(() => {});
  }
  async ready() {
    return !this.#closed && !!this.#worker && (await this.#worker.ready());
  }
  async close() {
    this.#closed = true;
    await this.#worker?.close();
  }
  async #capturedEvidence(metadata: EvidenceMetadata, paths: EnginePath[]) {
    const known = new Set<number>();
    let after = -1;
    for (;;) {
      const page = await this.evidence.read(metadata.id, after);
      if (JSON.stringify(page.metadata) !== JSON.stringify(metadata))
        throw new DomainError('evidence_unavailable', 503);
      for (const edge of page.items) known.add(edge.edgeId);
      if (page.nextEdgeId === null) break;
      after = page.nextEdgeId;
    }
    const fractions = paths.map((path) => {
      let all = 0,
        covered = 0;
      for (const edge of path.edges) {
        let length = 0;
        for (let i = edge.first + 1; i <= edge.last; i++)
          length += distanceMetres(
            { latitude: path.points[i - 1]![0], longitude: path.points[i - 1]![1] },
            { latitude: path.points[i]![0], longitude: path.points[i]![1] },
          );
        all += length;
        if (known.has(edge.edgeId)) covered += length;
      }
      return all > 0 ? Math.min(1, covered / all) : 0;
    });
    await this.evidence.read(metadata.id, 10000000);
    return fractions;
  }
  async plan(input: RouteInput, cancellation?: AbortSignal): Promise<RoutePlan> {
    input = {
      origin: { ...input.origin },
      destination: { ...input.destination },
      mode: input.mode,
      includeReports: input.includeReports === true,
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
    if (!(await this.ready())) throw new DomainError('routing_unavailable', 503);
    if (this.#running >= 2) throw new DomainError('routing_busy', 503);
    this.#running++;
    const signal = cancellation
      ? AbortSignal.any([AbortSignal.timeout(10000), cancellation])
      : AbortSignal.timeout(10000);
    try {
      const worker = this.#worker!,
        base = await worker.route(
          input.origin,
          input.destination,
          input.mode,
          'astarbi',
          undefined,
          signal,
        );
      const paths = [base];
      let metadata: EvidenceMetadata | undefined, fractions: number[] | undefined;
      let status: NonNullable<RoutePlan['reportRouting']>['status'] = this.experimental
        ? 'no_evidence'
        : 'disabled';
      if (input.includeReports && this.experimental) {
        try {
          const current = await this.evidence.current(this.manifest.graphVersion);
          if (current) {
            const initial = await this.evidence.read(current.id);
            if (initial.metadata.evidencedEdgeCount > 0) {
              const weighted = await new EvidenceRoutingCoordinator(
                worker,
                this.evidence,
                this.artifacts,
              ).route(input, signal);
              metadata = weighted.metadata;
              const same =
                JSON.stringify(base.edges.map((e) => [e.edgeId, e.first, e.last])) ===
                  JSON.stringify(weighted.path.edges.map((e) => [e.edgeId, e.first, e.last])) &&
                JSON.stringify(base.points) === JSON.stringify(weighted.path.points);
              if (!same) paths.push(weighted.path);
              fractions = await this.#capturedEvidence(metadata, paths);
              status = same ? 'same_route' : 'available';
            }
          }
        } catch {
          if (signal.aborted) throw new DomainError('routing_unavailable', 503);
          paths.splice(1);
          metadata = undefined;
          fractions = undefined;
          status = 'unavailable';
        }
      }
      if (signal.aborted) throw new DomainError('routing_unavailable', 503);
      const now = new Date(),
        expiry = metadata ? new Date(metadata.expiresAt) : new Date(now.getTime() + 300000);
      if (expiry.getTime() <= now.getTime() + 1000)
        throw new DomainError('routing_unavailable', 503);
      return {
        trafficAware: false,
        durationModel: 'osm_static_speed',
        graphVersion: this.manifest.graphVersion,
        riskVersion: metadata ? `reviewed-decay-v1:${metadata.id}` : 'unknown-v1',
        riskLevel: 'unknown',
        evidenceCoverage: null,
        source: 'openstreetmap',
        sourceTimestamp: this.manifest.osmBase,
        attribution: '© OpenStreetMap contributors',
        license: 'ODbL-1.0',
        generatedAt: now.toISOString(),
        expiresAt: expiry.toISOString(),
        origin: input.origin,
        destination: input.destination,
        mode: input.mode,
        reportRouting: { status, synthetic: this.synthetic },
        routes: paths.map((path, index) => ({
          id: randomUUID(),
          preference: index === 0 ? 'fastest' : 'reported',
          durationSeconds: path.durationSeconds,
          distanceMetres: path.distanceMetres,
          points: path.points,
          ...(fractions ? { reportedEvidenceFraction: fractions[index] } : {}),
        })),
      };
    } finally {
      this.#running--;
    }
  }
}
export async function workerRoutingFromEnvironment(
  env: Record<string, string | undefined>,
  evidence: EvidenceStore,
  synthetic = false,
) {
  const java = env.AWAAZ_ROUTING_JAVA?.trim();
  if (!java) return undefined;
  const path = env.AWAAZ_ROUTING_MANIFEST?.trim();
  if (!isAbsolute(java) || !path || !isAbsolute(path))
    throw new Error('Supply absolute Java and confirmed graph manifest paths');
  const manifest = parseGraphManifest(
    JSON.parse((await readFile(path, 'utf8')).replace(/^\uFEFF/, '')),
  );
  const directory = dirname(path),
    root = fileURLToPath(new URL('../../../', import.meta.url)),
    artifacts = env.AWAAZ_EVIDENCE_OUTPUT_DIR?.trim() || join(root, '.local/evidence');
  if (!isAbsolute(artifacts)) throw new Error('Supply an absolute evidence output directory');
  const startup = EvidenceRouterWorker.create(
    java,
    join(directory, 'graphhopper-web-11.1.jar'),
    join(root, 'backend/routing/EvidenceRouter.java'),
    join(root, 'backend/routing/graphhopper.yml'),
    join(directory, manifest.graphVersion),
    artifacts,
    manifest,
  );
  return new WorkerRouting(
    startup,
    manifest,
    evidence,
    artifacts,
    env.AWAAZ_EXPERIMENTAL_EVIDENCE_ROUTING === 'true',
    synthetic,
  );
}
