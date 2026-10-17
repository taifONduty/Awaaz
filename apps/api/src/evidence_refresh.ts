import { randomUUID } from 'node:crypto';
import { mkdir, open, rename, unlink } from 'node:fs/promises';
import { basename, dirname, isAbsolute } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import type { SqlExecutor } from './postgres.ts';
import { buildEvidenceSnapshot, exportEvidence, postgresEvidence } from './evidence.ts';
import { EvidenceRetention } from './evidence_retention.ts';

export type EvidenceWorkerHealth = {
  version: 1;
  status: 'starting' | 'ready' | 'standby' | 'unavailable' | 'stopped';
  graphVersion: string;
  updatedAt: string;
  lastSuccessAt: string | null;
  snapshotId: string | null;
  snapshotExpiresAt: string | null;
  consecutiveFailures: number;
  safetyAssessment: 'unknown';
  cleanup: { scanned: number; removed: number; partials: number; more: boolean } | null;
};

export interface EvidenceWorkerConnection extends SqlExecutor {
  release(discard: boolean): void | Promise<void>;
}
export interface EvidenceWorkerPool {
  connect(): Promise<EvidenceWorkerConnection>;
}

export class EvidenceRefreshWorker {
  readonly retention: EvidenceRetention;
  health: EvidenceWorkerHealth;
  #cycle: Promise<void> | undefined;
  #stopped = false;
  readonly #shutdown = new AbortController();
  readonly pool: EvidenceWorkerPool;
  readonly graphVersion: string;
  readonly directory: string;
  readonly healthFile: string;
  constructor(
    pool: EvidenceWorkerPool,
    graphVersion: string,
    directory: string,
    healthFile: string,
  ) {
    if (
      !isAbsolute(healthFile) ||
      !/^awaaz-evidence[\w.-]*\.health\.json$/.test(basename(healthFile))
    )
      throw new Error('Supply an absolute awaaz-evidence*.health.json path');
    this.pool = pool;
    this.graphVersion = graphVersion;
    this.directory = directory;
    this.healthFile = healthFile;
    this.retention = new EvidenceRetention(directory, graphVersion);
    this.health = {
      version: 1,
      status: 'starting',
      graphVersion,
      updatedAt: new Date().toISOString(),
      lastSuccessAt: null,
      snapshotId: null,
      snapshotExpiresAt: null,
      consecutiveFailures: 0,
      safetyAssessment: 'unknown',
      cleanup: null,
    };
  }
  async #publish() {
    this.health.updatedAt = new Date().toISOString();
    await mkdir(dirname(this.healthFile), { recursive: true });
    const partial = this.healthFile + '.' + randomUUID() + '.partial';
    const file = await open(partial, 'wx', 0o600);
    try {
      await file.writeFile(JSON.stringify(this.health) + '\n');
      await file.sync();
      await file.close();
      await rename(partial, this.healthFile);
    } catch (error) {
      await file.close().catch(() => {});
      await unlink(partial).catch(() => {});
      throw error;
    }
  }
  async #refresh() {
    const client = await this.pool.connect();
    let locked = false,
      discard = false;
    try {
      await client.query("SET statement_timeout='8s'");
      await client.query("SET lock_timeout='2s'");
      const lock = await client.query(
        'SELECT pg_catalog.pg_try_advisory_lock(pg_catalog.hashtextextended($1,0)) AS locked',
        ['awaaz:evidence-worker:v1:' + this.graphVersion],
      );
      locked = lock.rows[0]?.locked === true;
      if (!locked) {
        this.health.status = 'standby';
        return;
      }
      const built = await buildEvidenceSnapshot(client, this.graphVersion);
      const store = postgresEvidence(client);
      const exported = await exportEvidence(store, built.id, this.directory);
      this.health.cleanup = await this.retention.prune();
      const live = await store.read(built.id, 10000000);
      if (JSON.stringify(live.metadata) !== JSON.stringify(exported.metadata))
        throw new Error('Evidence changed during retention');
      this.health.status = 'ready';
      this.health.lastSuccessAt = new Date().toISOString();
      this.health.snapshotId = built.id;
      this.health.snapshotExpiresAt = exported.metadata.expiresAt;
      this.health.consecutiveFailures = 0;
    } catch (error) {
      discard = true;
      throw error;
    } finally {
      if (locked) {
        try {
          await client.query(
            'SELECT pg_catalog.pg_advisory_unlock(pg_catalog.hashtextextended($1,0))',
            ['awaaz:evidence-worker:v1:' + this.graphVersion],
          );
        } catch {
          discard = true;
        }
      }
      await client.release(discard);
    }
  }
  cycle() {
    if (this.#stopped) return Promise.reject(new Error('Evidence worker stopped'));
    return (this.#cycle ??= (async () => {
      try {
        await this.#refresh();
      } catch {
        this.health.status = 'unavailable';
        this.health.consecutiveFailures++;
      }
      await this.#publish();
    })().finally(() => {
      this.#cycle = undefined;
    }));
  }
  async run(signal: AbortSignal) {
    signal = AbortSignal.any([signal, this.#shutdown.signal]);
    await this.#publish();
    while (!signal.aborted && !this.#stopped) {
      await this.cycle();
      const milliseconds =
        this.health.status === 'unavailable'
          ? Math.min(30000, 1000 * 2 ** Math.min(this.health.consecutiveFailures, 5))
          : 30000;
      try {
        await delay(milliseconds, undefined, { signal });
      } catch (error) {
        if (!signal.aborted) throw error;
      }
    }
  }
  async close() {
    this.#stopped = true;
    this.#shutdown.abort();
    try {
      await this.#cycle;
    } finally {
      await this.retention.close();
      this.health.status = 'stopped';
      await this.#publish();
    }
  }
}

export function evidenceHealthLive(value: unknown, now = Date.now()): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const h = value as Record<string, unknown>;
  const updated = typeof h.updatedAt === 'string' ? Date.parse(h.updatedAt) : NaN;
  return (
    h.version === 1 &&
    ['starting', 'ready', 'standby', 'unavailable'].includes(String(h.status)) &&
    h.safetyAssessment === 'unknown' &&
    Number.isSafeInteger(h.consecutiveFailures) &&
    (h.consecutiveFailures as number) >= 0 &&
    typeof h.graphVersion === 'string' &&
    /^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$/.test(h.graphVersion) &&
    Number.isFinite(updated) &&
    updated <= now + 5000 &&
    now - updated <= 60000
  );
}

export function evidenceHealthReady(value: unknown, now = Date.now()): boolean {
  if (!evidenceHealthLive(value, now)) return false;
  const h = value as Record<string, unknown>;
  const updated = Date.parse(h.updatedAt as string);
  const expiry = typeof h.snapshotExpiresAt === 'string' ? Date.parse(h.snapshotExpiresAt) : NaN;
  return (
    h.version === 1 &&
    h.status === 'ready' &&
    h.safetyAssessment === 'unknown' &&
    h.consecutiveFailures === 0 &&
    typeof h.graphVersion === 'string' &&
    /^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$/.test(h.graphVersion) &&
    typeof h.snapshotId === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(h.snapshotId) &&
    Number.isFinite(updated) &&
    updated <= now + 5000 &&
    now - updated <= 60000 &&
    Number.isFinite(expiry) &&
    expiry > now + 1000 &&
    expiry - updated <= 120000
  );
}
