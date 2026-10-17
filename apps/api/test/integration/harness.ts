import { Pool } from 'pg';
import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { buildServer } from '../../src/server.ts';
import { postgresStores } from '../../src/postgres.ts';
import { inviteTokenFactory } from '../../src/security.ts';
import type { RoutingService } from '../../src/routing.ts';
import type { EvidenceStore } from '../../src/evidence.ts';
import type { PlaceCatalogue } from '../../src/places.ts';

export async function databaseHarness(
  options: {
    routing?: RoutingService;
    places?: PlaceCatalogue;
    routingFactory?: (evidence: EvidenceStore) => Promise<RoutingService | undefined>;
  } = {},
) {
  const adminUrl = process.env.AWAAZ_TEST_ADMIN_URL;
  const apiPassword = process.env.AWAAZ_TEST_API_PASSWORD;
  if (!adminUrl || !apiPassword)
    throw new Error(
      'Start scripts/start-test-postgres.ps1 or configure a disposable integration-only cluster',
    );
  const source = new URL(adminUrl);
  if (
    !['127.0.0.1', 'localhost', '[::1]'].includes(source.hostname) ||
    !/^[0-9a-f]{64}$/.test(apiPassword)
  ) {
    throw new Error('Integration tests require localhost and a generated test password');
  }
  const root = new Pool({ connectionString: adminUrl, ssl: false, max: 2 });
  const marker = await root.query("SELECT current_setting('cluster_name') AS name");
  if (marker.rows[0]?.name !== 'awaaz-integration-only') {
    await root.end();
    throw new Error('Refusing to change a non-test cluster');
  }
  const name = 'awaaz_test_' + randomUUID().replaceAll('-', '');
  if (!/^awaaz_test_[0-9a-f]{32}$/.test(name)) throw new Error('Unsafe test database name');
  await root.query('CREATE DATABASE ' + name);
  const dbUrl = new URL(source);
  dbUrl.pathname = '/' + name;
  const admin = new Pool({ connectionString: dbUrl.toString(), ssl: false, max: 4 });
  let api: Pool | undefined;
  let app: Awaited<ReturnType<typeof buildServer>> | undefined;
  const close = async () => {
    if (app) await app.close();
    if (api) await api.end();
    await admin.end();
    await root.query('DROP DATABASE ' + name);
    await root.end();
  };
  try {
    // Roles are cluster-wide even though each harness owns a separate database.
    // Lock on a dedicated root session so fixture startup and test processes
    // cannot concurrently ALTER the same role's catalog tuple.
    const setup = await root.connect();
    try {
      await setup.query(
        "SELECT pg_catalog.pg_advisory_lock(pg_catalog.hashtextextended('awaaz:test:role-setup:v1',0))",
      );
      await admin.query(
        await readFile(new URL('../../../../backend/test/bootstrap.sql', import.meta.url), 'utf8'),
      );
      const directory = new URL('../../../../backend/supabase/migrations/', import.meta.url);
      for (const file of (await readdir(directory))
        .filter((file) => file.endsWith('.sql'))
        .sort()) {
        await admin.query(await readFile(new URL(file, directory), 'utf8'));
      }
      // Generated hex only, in a cluster whose marker was checked above.
      await admin.query("ALTER ROLE awaaz_api LOGIN PASSWORD '" + apiPassword + "'");
    } finally {
      try {
        await setup.query(
          "SELECT pg_catalog.pg_advisory_unlock(pg_catalog.hashtextextended('awaaz:test:role-setup:v1',0))",
        );
      } finally {
        setup.release();
      }
    }
    const apiUrl = new URL(dbUrl);
    apiUrl.username = 'awaaz_api';
    apiUrl.password = apiPassword;
    api = new Pool({ connectionString: apiUrl.toString(), ssl: false, max: 6 });
    const stores = postgresStores(api);
    const routing = options.routing ?? (await options.routingFactory?.(stores.evidence));
    const identities = new Map<string, { id: string; phoneVerified: boolean }>();
    app = await buildServer({
      ...stores,
      ...(routing ? { routing } : {}),
      ...(options.places ? { places: options.places } : {}),
      inviteToken: inviteTokenFactory('a1'.repeat(32)),
      verifyToken: async (token) => identities.get(token) ?? null,
    });
    let address = 1;
    const request = (
      token: string,
      method: 'GET' | 'POST' | 'PUT' | 'DELETE',
      url: string,
      payload?: object,
    ) =>
      app!.inject({
        method,
        url,
        headers: { authorization: 'Bearer ' + token },
        remoteAddress: '127.0.0.' + ((address++ % 200) + 1),
        ...(payload ? { payload } : {}),
      });
    const user = async (displayName: string, verified = true, transportVerified = verified) => {
      const id = randomUUID(),
        token = 'test-' + randomUUID();
      await admin.query('INSERT INTO auth.users(id,phone_confirmed_at) VALUES($1,$2)', [
        id,
        verified ? new Date() : null,
      ]);
      identities.set(token, { id, phoneVerified: transportVerified });
      const result = await request(token, 'PUT', '/v1/me', {
        displayName,
        locale: 'en',
        adultAttested: true,
      });
      if (result.statusCode !== 200) throw new Error('Profile setup failed: ' + result.body);
      return { id, token };
    };
    const asUser = async (id: string, sql: string, values: unknown[] = []) => {
      const connection = await admin.connect();
      try {
        await connection.query('BEGIN');
        await connection.query("SELECT set_config('request.jwt.claim.sub',$1,true)", [id]);
        await connection.query('SET LOCAL ROLE authenticated');
        return await connection.query(sql, values);
      } finally {
        await connection.query('ROLLBACK');
        connection.release();
      }
    };
    const asAnon = async (sql: string) => {
      const connection = await admin.connect();
      try {
        await connection.query('BEGIN');
        await connection.query('SET LOCAL ROLE anon');
        return await connection.query(sql);
      } finally {
        await connection.query('ROLLBACK');
        connection.release();
      }
    };
    return { admin, api, app, stores, routing, user, request, asUser, asAnon, close, name };
  } catch (error) {
    // Roll back any failed migration before closing/dropping only this new DB.
    try {
      await admin.query('ROLLBACK');
    } catch {}
    await close();
    throw error;
  }
}
