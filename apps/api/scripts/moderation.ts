// Operator tool: uses a normal verified access token and the same DB-authorized
// endpoints as a future console. Never accepts a service-role key or DB URL.
import { randomUUID } from 'node:crypto';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const rejectionReasons = [
  'duplicate',
  'unverifiable',
  'personal_information',
  'outside_scope',
  'resolved',
];
async function run() {
  const [command, first, second, third, fourth, ...extra] = process.argv.slice(2);
  if (extra.length) throw new Error('Too many arguments');
  const base = new URL(process.env.AWAAZ_MODERATION_API_URL ?? 'http://127.0.0.1:3030');
  if (
    (base.protocol !== 'https:' &&
      !(
        base.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(base.hostname)
      )) ||
    base.username ||
    base.password ||
    base.search ||
    base.hash ||
    base.pathname !== '/'
  )
    throw new Error('Use an HTTPS API origin or localhost HTTP');
  const token = process.env.AWAAZ_MODERATION_ACCESS_TOKEN;
  if (!token || token.length > 8192 || /\s/.test(token))
    throw new Error('Set AWAAZ_MODERATION_ACCESS_TOKEN to a verified moderator access token');
  let path: string, body: object | undefined;
  if (command === 'queue' && !second && !third && !fourth) {
    const query = new URLSearchParams({ limit: '20' });
    if (first) {
      if (!/^[A-Za-z0-9_-]{1,512}$/.test(first)) throw new Error('Invalid queue cursor');
      query.set('cursor', first);
    }
    path = '/v1/moderation/reports?' + query;
  } else if ((command === 'approve' || command === 'reject') && first && uuid.test(first)) {
    const reason = command === 'approve' ? 'reviewed' : second;
    const requestId = command === 'approve' ? second : third;
    if (
      fourth ||
      (command === 'approve' && third) ||
      !reason ||
      (command === 'reject' && !rejectionReasons.includes(reason)) ||
      (requestId !== undefined && !uuid.test(requestId))
    )
      throw new Error('Invalid review arguments');
    // Require a caller-supplied UUID so a failed response can be retried without
    // creating a different command. The request-id subcommand generates one.
    if (!requestId)
      throw new Error(
        'Supply a client request UUID; generate one with: node scripts/moderation.ts request-id',
      );
    path = `/v1/moderation/reports/${first.toLowerCase()}/reviews`;
    body = { clientRequestId: requestId.toLowerCase(), decision: command, reason };
  } else if (
    command === 'candidates' &&
    first &&
    uuid.test(first) &&
    second &&
    /^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$/.test(second) &&
    !third &&
    !fourth
  ) {
    path =
      `/v1/moderation/reports/${first.toLowerCase()}/road-candidates?` +
      new URLSearchParams({ graphVersion: second });
  } else if (
    command === 'publish' &&
    first &&
    uuid.test(first) &&
    second &&
    /^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$/.test(second) &&
    third &&
    /^(?:0|[1-9][0-9]{0,7})$/.test(third) &&
    Number(third) <= 10_000_000 &&
    fourth &&
    uuid.test(fourth)
  ) {
    path = `/v1/moderation/reports/${first.toLowerCase()}/publications`;
    body = { clientRequestId: fourth.toLowerCase(), graphVersion: second, edgeId: Number(third) };
  } else
    throw new Error(
      'Usage: queue [cursor] | approve <report UUID> <request UUID> | reject <report UUID> <reason> <request UUID> | candidates <report UUID> <graph version> | publish <report UUID> <graph version> <edge ID> <request UUID>',
    );
  const response = await fetch(new URL(path, base), {
    method: body ? 'POST' : 'GET',
    redirect: 'error',
    signal: AbortSignal.timeout(15_000),
    headers: {
      authorization: 'Bearer ' + token,
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) {
    // Print only the status, never an untrusted upstream response or token.
    throw new Error(`Moderation API returned HTTP ${response.status}`);
  }
  const reader = response.body?.getReader();
  if (!reader) throw new Error('Moderation API returned an empty response');
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > 256 * 1024) throw new Error('Moderation response exceeded its size limit');
      chunks.push(chunk.value);
    }
  } finally {
    await reader.cancel();
  }
  console.log(JSON.stringify(JSON.parse(Buffer.concat(chunks).toString('utf8')), null, 2));
}

if (process.argv.length === 3 && process.argv[2] === 'request-id') console.log(randomUUID());
else {
  try {
    await run();
  } catch (error) {
    // Network errors may include URL information; operational errors above are
    // safe fixed strings, whereas driver/fetch/parser failures stay generic.
    const message = error instanceof Error ? error.message : '';
    const safe = [
      'Too many arguments',
      'Use an HTTPS API origin or localhost HTTP',
      'Set AWAAZ_MODERATION_ACCESS_TOKEN',
      'Invalid queue cursor',
      'Invalid review arguments',
      'Supply a client request UUID',
      'Usage:',
      'Moderation API returned HTTP',
      'Moderation API returned an empty response',
      'Moderation response exceeded its size limit',
    ];
    console.error(
      safe.some((prefix) => message.startsWith(prefix)) ? message : 'Moderation request failed',
    );
    process.exitCode = 1;
  }
}
