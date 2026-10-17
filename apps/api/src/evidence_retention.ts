import { lstat, open, opendir, realpath, unlink } from 'node:fs/promises';
import type { Dir } from 'node:fs';
import { isAbsolute, join, resolve } from 'node:path';

const id = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const complete = new RegExp(`^(${id})\\.jsonl$`, 'i');
const partial = new RegExp(`^(${id})\\.jsonl\\.(${id})\\.(?:manifest\\.)?partial$`, 'i');
const manifestName = new RegExp(`^(${id})\\.jsonl\\.manifest\\.json$`, 'i');
const canonical = (path: string) => (process.platform === 'win32' ? path.toLowerCase() : path);
const object = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === 'object' && !Array.isArray(v);

async function readPrefix(path: string, maximum: number) {
  const before = await lstat(path);
  if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1) return null;
  const file = await open(path, 'r');
  try {
    const actual = await file.stat();
    if (actual.dev !== before.dev || actual.ino !== before.ino || actual.nlink !== 1) return null;
    const bytes = Buffer.alloc(maximum);
    const { bytesRead } = await file.read(bytes, 0, maximum, 0);
    return bytes.subarray(0, bytesRead).toString('utf8');
  } finally {
    await file.close();
  }
}

/** Shallow, bounded retention for the worker's private export directory.
 * Crash partials require exact reserved names and a fifteen-minute quiet period.
 * No recursive removal and no deletion of malformed completed artifacts. */
export class EvidenceRetention {
  #directory: Dir | undefined;
  readonly directory: string;
  readonly graphVersion: string;
  constructor(directory: string, graphVersion: string) {
    this.directory = directory;
    this.graphVersion = graphVersion;
    if (!isAbsolute(directory) || !/^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$/.test(graphVersion))
      throw new Error('Invalid evidence retention configuration');
  }
  async close() {
    const dir = this.#directory;
    this.#directory = undefined;
    if (dir) await dir.close();
  }
  async prune(now = Date.now()) {
    if (!Number.isFinite(now)) throw new Error('Invalid retention clock');
    if (canonical(await realpath(this.directory)) !== canonical(resolve(this.directory)))
      throw new Error('Evidence directory must not be a symlink or junction');
    this.#directory ??= await opendir(this.directory);
    let scanned = 0,
      removed = 0,
      partials = 0,
      more = true;
    const remove = async (path: string) => {
      // Recheck immediately before unlink; links and multiply-linked files stay.
      const stat = await lstat(path);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) return false;
      await unlink(path);
      return true;
    };
    while (scanned < 1000 && removed < 50) {
      const entry = await this.#directory.read();
      if (!entry) {
        await this.close();
        more = false;
        break;
      }
      scanned++;
      if (!entry.isFile() || entry.isSymbolicLink()) continue;
      const matched =
        complete.exec(entry.name) ?? partial.exec(entry.name) ?? manifestName.exec(entry.name);
      if (!matched) continue;
      const path = join(this.directory, entry.name);
      try {
        if (partial.test(entry.name)) {
          if ((await lstat(path)).mtimeMs <= now - 900000 && (await remove(path))) {
            removed++;
            partials++;
          }
          continue;
        }
        const raw = await readPrefix(path, 16384);
        if (raw === null) continue;
        const isManifest = manifestName.test(entry.name);
        const newline = raw.indexOf('\n');
        if (!isManifest && newline < 0) continue;
        const value: unknown = JSON.parse(isManifest ? raw : raw.slice(0, newline));
        if (!object(value)) continue;
        const metadata = isManifest ? value : value.metadata;
        if (
          !object(metadata) ||
          (!isManifest && value.format !== 'awaaz-evidence-v1') ||
          metadata.id !== matched[1] ||
          metadata.graphVersion !== this.graphVersion ||
          typeof metadata.expiresAt !== 'string' ||
          !Number.isFinite(Date.parse(metadata.expiresAt))
        )
          continue;
        const expiry = Date.parse(metadata.expiresAt);
        // Completed artifacts outlive all request leases by five minutes.
        // Orphan manifests use a longer crash-recovery grace period.
        if (expiry > now - (isManifest ? 900000 : 300000)) continue;
        if (!isManifest) {
          if (
            typeof metadata.createdAt !== 'string' ||
            !Number.isFinite(Date.parse(metadata.createdAt)) ||
            expiry <= Date.parse(metadata.createdAt) ||
            expiry - Date.parse(metadata.createdAt) > 120000
          )
            continue;
        }
        if (isManifest) {
          // Leave a pair for its JSONL entry; only this branch removes orphans.
          try {
            await lstat(join(this.directory, matched[1] + '.jsonl'));
            continue;
          } catch (error) {
            if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
          }
        }
        if (await remove(path)) {
          removed++;
        }
        if (!isManifest) {
          const paired = path + '.manifest.json';
          try {
            const companion = await readPrefix(paired, 4096);
            const parsed: unknown = companion === null ? null : JSON.parse(companion);
            if (
              object(parsed) &&
              parsed.id === matched[1] &&
              parsed.graphVersion === this.graphVersion &&
              parsed.expiresAt === metadata.expiresAt
            )
              await remove(paired);
          } catch (error) {
            if (
              (error as NodeJS.ErrnoException).code !== 'ENOENT' &&
              !(error instanceof SyntaxError)
            )
              throw error;
          }
        }
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT' && !(error instanceof SyntaxError))
          throw error;
      }
    }
    return { scanned, removed, partials, more };
  }
}
