import { readFile, lstat } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { evidenceHealthReady, evidenceHealthLive } from '../src/evidence_refresh.ts';

try {
  const file =
    process.env.AWAAZ_EVIDENCE_HEALTH_FILE ||
    (process.env.AWAAZ_EVIDENCE_OUTPUT_DIR
      ? join(process.env.AWAAZ_EVIDENCE_OUTPUT_DIR, 'awaaz-evidence.health.json')
      : '');
  if (process.argv.slice(2).some((v) => v !== '--live')) throw new Error('Invalid argument');
  if (!isAbsolute(file)) throw new Error('Invalid worker health');
  const stat = await lstat(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 4096)
    throw new Error('Invalid worker health');
  const check = process.argv.includes('--live') ? evidenceHealthLive : evidenceHealthReady;
  if (!check(JSON.parse(await readFile(file, 'utf8')))) throw new Error('Worker not ready');
  console.log(
    process.argv.includes('--live')
      ? 'Evidence worker heartbeat current; safety assessment remains unknown.'
      : 'Evidence worker ready; safety assessment remains unknown.',
  );
} catch {
  console.error('Evidence worker not ready or its snapshot/heartbeat has expired.');
  process.exitCode = 1;
}
