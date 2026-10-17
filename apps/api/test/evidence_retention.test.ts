import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { mkdir, writeFile, utimes, access, link, rm, realpath, symlink } from 'node:fs/promises';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { EvidenceRetention } from '../src/evidence_retention.ts';

test('retention bounds deletion and preserves current, foreign, malformed and linked files', async () => {
  const root = fileURLToPath(new URL('../../../.local/', import.meta.url));
  const directory = join(root, 'retention-check-' + randomUUID());
  await mkdir(directory, { recursive: true });
  const graph = 'dhaka-gh11.1-' + 'a'.repeat(20) + '-' + 'b'.repeat(12);
  const now = Date.now(),
    old = now - 20 * 60000;
  const header = (id: string, time: number, version = graph) =>
    JSON.stringify({
      format: 'awaaz-evidence-v1',
      metadata: {
        id,
        graphVersion: version,
        createdAt: new Date(time).toISOString(),
        expiresAt: new Date(time + 120000).toISOString(),
      },
    }) + '\n';
  const keep: string[] = [];
  const retention = new EvidenceRetention(directory, graph);
  try {
    const valid = randomUUID() + '.jsonl';
    await writeFile(join(directory, valid), header(valid.slice(0, 36), now));
    keep.push(valid);
    const foreign = randomUUID() + '.jsonl';
    await writeFile(
      join(directory, foreign),
      header(foreign.slice(0, 36), old, graph.replace('a'.repeat(20), 'c'.repeat(20))),
    );
    keep.push(foreign);
    const bad = randomUUID() + '.jsonl';
    await writeFile(join(directory, bad), 'unrecognized content\n');
    keep.push(bad);
    const freshPartial = randomUUID() + '.jsonl.' + randomUUID() + '.partial';
    await writeFile(join(directory, freshPartial), '');
    keep.push(freshPartial);
    const stalePartial = randomUUID() + '.jsonl.' + randomUUID() + '.manifest.partial';
    await writeFile(join(directory, stalePartial), '');
    await utimes(join(directory, stalePartial), new Date(old), new Date(old));
    const shared = randomUUID() + '.jsonl';
    await writeFile(join(directory, shared), header(shared.slice(0, 36), old));
    await link(join(directory, shared), join(directory, 'protected-hardlink'));
    keep.push(shared, 'protected-hardlink');
    await writeFile(join(directory, 'unrelated.txt'), 'keep');
    keep.push('unrelated.txt');
    for (let i = 0; i < 55; i++) {
      const id = randomUUID();
      await writeFile(join(directory, id + '.jsonl'), header(id, old));
      await writeFile(
        join(directory, id + '.jsonl.manifest.json'),
        JSON.stringify({
          id,
          graphVersion: graph,
          expiresAt: new Date(old + 120000).toISOString(),
        }),
      );
    }
    let removed = 0;
    for (let i = 0; i < 5; i++) {
      const result = await retention.prune(now);
      assert.ok(result.removed <= 50);
      assert.ok(result.scanned <= 1000);
      removed += result.removed;
      if (!result.more) break;
    }
    assert.equal(removed, 56);
    for (const file of keep) await access(join(directory, file));
    await assert.rejects(access(join(directory, stalePartial)));
    const protectedDir = join(directory, 'protected');
    const junction = join(directory, 'junction');
    await mkdir(protectedDir);
    await writeFile(join(protectedDir, 'keep'), 'protected');
    await symlink(protectedDir, junction, process.platform === 'win32' ? 'junction' : 'dir');
    const redirected = new EvidenceRetention(junction, graph);
    await assert.rejects(redirected.prune(now), /symlink or junction/);
    await redirected.close();
    await access(join(protectedDir, 'keep'));
  } finally {
    await retention.close();
    // Verify the final absolute deletion target remains an owned fixture.
    const resolved = await realpath(directory);
    assert.equal(dirname(resolved), await realpath(root));
    assert.ok(basename(resolved).startsWith('retention-check-'));
    await rm(resolved, { recursive: true, force: true });
  }
});
