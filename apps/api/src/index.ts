import { readFile } from 'node:fs/promises';
import { buildServer } from './server.ts';
import { supabaseVerifier } from './auth.ts';
import { createDatabasePool, postgresStores } from './postgres.ts';
import { inviteTokenFactory } from './security.ts';
import { configuration } from './config.ts';
import { routingFromEnvironment, parseGraphManifest } from './routing.ts';
import { placesFromEnvironment } from './places.ts';
import { workerRoutingFromEnvironment } from './worker_routing.ts';

const config = configuration(process.env);
const makeInviteToken = inviteTokenFactory(config.inviteSecret);
const ca = config.caPath ? await readFile(config.caPath, 'utf8') : undefined;
const pool = createDatabasePool(config.databaseUrl, ca);
const stores = postgresStores(pool);
const places = await placesFromEnvironment(
  process.env,
  process.env.AWAAZ_ROUTING_MANIFEST
    ? parseGraphManifest(JSON.parse(await readFile(process.env.AWAAZ_ROUTING_MANIFEST, 'utf8')))
        .graphVersion
    : undefined,
);
const routing =
  (await workerRoutingFromEnvironment(process.env, stores.evidence)) ??
  (await routingFromEnvironment(process.env));
const app = await buildServer(
  {
    ...stores,
    ...(routing ? { routing } : {}),
    ...(places ? { places } : {}),
    verifyToken: supabaseVerifier(config.supabaseUrl, config.publishableKey),
    inviteToken: makeInviteToken,
    close: () => pool.end(),
  },
  {
    allowedOrigins: config.allowedOrigins,
    logger: {
      level: config.logLevel,
      redact: [
        'req.headers.authorization',
        'req.headers.cookie',
        'req.body',
        'res.headers.set-cookie',
      ],
    },
  },
);
if (!(await stores.ready())) {
  await app.close();
  throw new Error('Database not ready. Apply migrations and use the awaaz_api connection role.');
}
await app.listen({ port: config.port, host: config.host });
let closing = false;
for (const signal of ['SIGINT', 'SIGTERM'] as const)
  process.once(signal, () => {
    if (closing) return;
    closing = true;
    const timeout = setTimeout(() => process.exit(1), 30_000);
    timeout.unref();
    void app
      .close()
      .then(() => clearTimeout(timeout))
      .catch(() => {
        app.log.error({ code: 'shutdown_failed' }, 'shutdown failed');
        process.exitCode = 1;
      });
  });
