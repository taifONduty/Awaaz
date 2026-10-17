import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { databaseHarness } from './harness.ts';
import { payloadHash, inviteTokenFactory } from '../../src/security.ts';
import { buildServer } from '../../src/server.ts';
import { DomainError } from '../../src/contracts.ts';
import type { ReportInput } from '../../src/contracts.ts';

function report(): ReportInput {
  return {
    clientRequestId: randomUUID(),
    category: 'lighting',
    description: 'PRIVATE demo lighting report near a crossing.',
    latitude: 23.760123,
    longitude: 90.380456,
    observedAt: new Date().toISOString(),
  };
}
function hash(input: ReportInput) {
  return payloadHash([
    input.category,
    input.description,
    input.latitude,
    input.longitude,
    input.observedAt,
  ]);
}

test('real Postgres/PostGIS backend integration', { timeout: 120_000 }, async (t) => {
  const h = await databaseHarness();
  t.after(h.close);
  await t.test(
    'own report receipts reconcile old requests and withdrawal without write or payload access',
    async () => {
      const alice = await h.user('Receipt owner'),
        bob = await h.user('Receipt outsider');
      const input = report(),
        created = await h.request(alice.token, 'POST', '/v1/reports', input);
      assert.equal(created.statusCode, 201, created.body);
      const id = created.json().id;
      const path = '/v1/report-requests/' + input.clientRequestId;
      assert.equal((await h.request(bob.token, 'GET', path)).statusCode, 404);
      assert.equal(
        (await h.request(alice.token, 'GET', '/v1/report-requests/' + randomUUID())).statusCode,
        404,
      );
      assert.equal(
        (await h.request(alice.token, 'GET', '/v1/report-requests/not-a-uuid')).statusCode,
        400,
      );
      assert.equal((await h.app.inject({ method: 'GET', url: path })).statusCode, 401);
      const future = await buildServer({
        ...h.stores,
        inviteToken: inviteTokenFactory('a1'.repeat(32)),
        now: () => new Date(Date.now() + 96 * 3_600_000),
        verifyToken: async (token) =>
          token === alice.token ? { id: alice.id, phoneVerified: true } : null,
      });
      try {
        const headers = { authorization: 'Bearer ' + alice.token };
        assert.equal(
          (await future.inject({ method: 'POST', url: '/v1/reports', headers, payload: input }))
            .statusCode,
          400,
        );
        const received = await future.inject({ method: 'GET', url: path, headers });
        assert.equal(received.statusCode, 200, received.body);
        assert.deepEqual(received.json(), { id, status: 'pending', replayed: true });
        for (const sensitive of ['PRIVATE', 'latitude', 'longitude', 'payloadHash', alice.id])
          assert.equal(received.body.includes(sensitive), false);
        assert.equal((await h.request(alice.token, 'DELETE', '/v1/reports/' + id)).statusCode, 200);
        assert.deepEqual((await future.inject({ method: 'GET', url: path, headers })).json(), {
          id,
          status: 'withdrawn',
          replayed: true,
        });
        assert.equal((await h.request(alice.token, 'GET', '/v1/reports')).json().items.length, 0);
        await assert.rejects(
          h.api!.query(
            "SELECT awaaz_private.community_command_v1($1,'list_own_reports','{\"limit\":1}')",
            [alice.id],
          ),
          { code: '42501' },
        );
        await assert.rejects(
          h.asUser(alice.id, "SELECT awaaz_private.community_command($1,'report_receipt',$2)", [
            alice.id,
            { clientRequestId: input.clientRequestId },
          ]),
          { code: '42501' },
        );
      } finally {
        await future.close();
      }
    },
  );
  const circle = async (token: string) => {
    const response = await h.request(token, 'POST', '/v1/circles', {
      name: 'Demo trusted circle',
      clientRequestId: randomUUID(),
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json().circle.id as string;
  };
  const invite = async (owner: string, circleId: string, recipientId: string) => {
    const response = await h.request(owner, 'POST', '/v1/circles/' + circleId + '/invites', {
      clientRequestId: randomUUID(),
      recipientId,
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json() as { id: string; token: string };
  };

  await t.test(
    'owned-circle caps serialize concurrent creation and daily quotas survive closure',
    async () => {
      const alice = await h.user('Circle caps');
      const results = await Promise.all(
        Array.from({ length: 6 }, () =>
          h.request(alice.token, 'POST', '/v1/circles', {
            name: 'Bounded circle',
            clientRequestId: randomUUID(),
          }),
        ),
      );
      const created = results.filter((r) => r.statusCode === 201);
      assert.equal(created.length, 5);
      assert.equal(
        results.filter((r) => r.statusCode === 409 && r.json().code === 'circles_limit_reached')
          .length,
        1,
      );
      for (const item of created)
        assert.equal(
          (await h.request(alice.token, 'DELETE', '/v1/circles/' + item.json().circle.id))
            .statusCode,
          200,
        );
      for (let i = 0; i < 5; i++) {
        const id = await circle(alice.token);
        assert.equal((await h.request(alice.token, 'DELETE', '/v1/circles/' + id)).statusCode, 200);
      }
      const blocked = await h.request(alice.token, 'POST', '/v1/circles', {
        name: 'Over quota',
        clientRequestId: randomUUID(),
      });
      assert.equal(blocked.statusCode, 429);
      assert.equal(blocked.json().code, 'rate_limited');
      assert.equal((await h.request(alice.token, 'GET', '/v1/circles')).json().items.length, 0);
      assert.equal(
        (
          await h.admin.query(
            "SELECT used FROM awaaz_private.account_quotas WHERE actor_id=$1 AND kind='circle'",
            [alice.id],
          )
        ).rows[0]?.used,
        10,
      );
    },
  );

  await t.test(
    'circle member cap and durable invitation quota apply without partial joins',
    async () => {
      const alice = await h.user('Member caps'),
        id = await circle(alice.token);
      let pending: { id: string; token: string } | undefined;
      let target: Awaited<ReturnType<typeof h.user>> | undefined;
      let first: { id: string; token: string } | undefined;
      for (let i = 0; i < 20; i++) {
        const bob = await h.user('Member ' + i),
          link = await invite(alice.token, id, bob.id);
        if (i === 0) first = link;
        const joined = await h.request(
          bob.token,
          'POST',
          '/v1/circle-invites/' + link.id + '/accept',
          { token: link.token },
        );
        if (i < 19) assert.equal(joined.statusCode, 200, joined.body);
        else {
          assert.equal(joined.statusCode, 409);
          assert.equal(joined.json().code, 'members_limit_reached');
          pending = link;
          target = bob;
        }
      }
      assert.equal(
        (await h.request(alice.token, 'GET', '/v1/circles/' + id)).json().members.length,
        20,
      );
      const extra = await h.user('Over invite quota');
      const blocked = await h.request(alice.token, 'POST', '/v1/circles/' + id + '/invites', {
        clientRequestId: randomUUID(),
        recipientId: extra.id,
      });
      assert.equal(blocked.statusCode, 429);
      assert.equal(
        (
          await h.admin.query(
            "SELECT used FROM awaaz_private.account_quotas WHERE actor_id=$1 AND kind='invite'",
            [alice.id],
          )
        ).rows[0]?.used,
        20,
      );
      assert.equal(
        (await h.request(alice.token, 'DELETE', '/v1/circle-invites/' + first!.id)).statusCode,
        200,
      );
      const retry = await h.request(
        target!.token,
        'POST',
        '/v1/circle-invites/' + pending!.id + '/accept',
        { token: pending!.token },
      );
      assert.equal(retry.statusCode, 200, retry.body);
      assert.equal(retry.json().circle.members.length, 20);
    },
  );

  await t.test(
    'all migrations load with PostGIS; API role has only scoped function access',
    async () => {
      const version = await h.admin.query('SELECT extensions.postgis_full_version() AS version');
      assert.match(version.rows[0]?.version, /POSTGIS="3.6.2/);
      assert.equal(await h.stores.ready(), true);
      await h.admin.query(
        'REVOKE EXECUTE ON FUNCTION awaaz_private.people_command(uuid,text,jsonb) FROM awaaz_api',
      );
      assert.equal(await h.stores.ready(), false, 'missing command grants must fail readiness');
      await h.admin.query(
        'GRANT EXECUTE ON FUNCTION awaaz_private.people_command(uuid,text,jsonb) TO awaaz_api',
      );
      await h.admin.query('GRANT SELECT ON public.profiles TO awaaz_api');
      assert.equal(
        await h.stores.ready(),
        false,
        'accidental direct table access must fail readiness',
      );
      await h.admin.query('REVOKE SELECT ON public.profiles FROM awaaz_api');
      assert.equal(await h.stores.ready(), true);
      await assert.rejects(h.api.query('SELECT * FROM auth.users'), { code: '42501' });
      await assert.rejects(h.api.query('SELECT * FROM public.report_submissions'), {
        code: '42501',
      });
      await assert.rejects(
        h.api.query(
          'INSERT INTO public.circles(owner_id,client_request_id,payload_hash,name) VALUES($1,$2,$3,$4)',
          [randomUUID(), randomUUID(), 'a'.repeat(64), 'forged'],
        ),
        { code: '42501' },
      );
      const privileges = await h.admin.query(
        "SELECT has_function_privilege('authenticated','awaaz_private.people_command(uuid,text,jsonb)','EXECUTE') AS client, has_function_privilege('awaaz_api','awaaz_private.people_command(uuid,text,jsonb)','EXECUTE') AS api",
      );
      assert.deepEqual(privileges.rows[0], { client: false, api: true });
      const functions = await h.admin.query(
        "SELECT p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='awaaz_private' AND p.proname IN ('people_command','community_command','is_circle_member')",
      );
      assert.equal(functions.rows.length, 3);
      for (const fn of functions.rows) {
        assert.equal(fn.prosecdef, true);
        assert.ok(
          fn.proconfig.includes('search_path=\"\"') || fn.proconfig.includes('search_path='),
        );
      }
    },
  );

  await t.test(
    'own profiles are bound to Auth, adult attestation is strict and RLS rejects spoofing',
    async () => {
      const alice = await h.user('Alice'),
        bob = await h.user('Bob');
      const me = await h.request(alice.token, 'GET', '/v1/me');
      assert.equal(me.statusCode, 200);
      assert.equal(me.json().profile.id, alice.id);
      assert.equal(me.json().phoneVerified, true);
      for (const payload of [
        { displayName: 'Alice', locale: 'en', adultAttested: false },
        { displayName: 'Alice', locale: 'en', adultAttested: 'true' },
        { displayName: 'Alice', locale: 'en', adultAttested: true, id: bob.id },
      ])
        assert.equal((await h.request(alice.token, 'PUT', '/v1/me', payload)).statusCode, 400);
      const own = await h.asUser(alice.id, 'SELECT id FROM public.profiles');
      assert.deepEqual(
        own.rows.map((r) => r.id),
        [alice.id],
      );
      await assert.rejects(
        h.asUser(
          alice.id,
          'INSERT INTO public.profiles(id,display_name,adult_attested) VALUES($1,$2,true)',
          [randomUUID(), 'forged'],
        ),
        { code: '42501' },
      );
      await assert.rejects(
        h.asUser(alice.id, 'UPDATE public.profiles SET adult_attested=false WHERE id=$1', [
          alice.id,
        ]),
        { code: '42501' },
      );
      await assert.rejects(h.asAnon('SELECT id FROM public.profiles'), { code: '42501' });
    },
  );

  await t.test(
    'concurrent circle creation is idempotent, does not double-charge, and conflicts on changed payload',
    async () => {
      const alice = await h.user('Circle owner');
      const input = { name: 'My family', clientRequestId: randomUUID() };
      const responses = await Promise.all(
        Array.from({ length: 6 }, () => h.request(alice.token, 'POST', '/v1/circles', input)),
      );
      assert.equal(responses.filter((r) => r.statusCode === 201).length, 1);
      assert.equal(responses.filter((r) => r.statusCode === 200).length, 5);
      assert.equal(new Set(responses.map((r) => r.json().circle.id)).size, 1);
      const quota = await h.admin.query(
        "SELECT used FROM awaaz_private.account_quotas WHERE actor_id=$1 AND kind='circle'",
        [alice.id],
      );
      assert.equal(quota.rows[0]?.used, 1);
      assert.equal(
        (await h.request(alice.token, 'POST', '/v1/circles', { ...input, name: 'changed' }))
          .statusCode,
        409,
      );
    },
  );

  await t.test(
    'only intended account can accept; secret and idempotent retry are enforced',
    async () => {
      const alice = await h.user('Inviter'),
        bob = await h.user('Invitee'),
        stranger = await h.user('Stranger');
      const id = await circle(alice.token);
      const input = { clientRequestId: randomUUID(), recipientId: bob.id };
      const first = await h.request(alice.token, 'POST', '/v1/circles/' + id + '/invites', input);
      const again = await h.request(alice.token, 'POST', '/v1/circles/' + id + '/invites', input);
      assert.equal(first.statusCode, 201);
      assert.equal(again.statusCode, 200);
      assert.equal(first.json().token, again.json().token);
      const link = first.json();
      const inbox = await h.request(bob.token, 'GET', '/v1/circle-invites');
      assert.ok(inbox.json().items.some((i: { id: string }) => i.id === link.id));
      assert.equal(inbox.body.includes(link.token), false);
      assert.equal(inbox.body.includes('tokenHash'), false);
      assert.equal(
        (
          await h.request(stranger.token, 'POST', '/v1/circle-invites/' + link.id + '/accept', {
            token: link.token,
          })
        ).statusCode,
        404,
      );
      assert.equal(
        (
          await h.request(bob.token, 'POST', '/v1/circle-invites/' + link.id + '/accept', {
            token: 'x'.repeat(43),
          })
        ).statusCode,
        404,
      );
      const accepted = await h.request(
        bob.token,
        'POST',
        '/v1/circle-invites/' + link.id + '/accept',
        { token: link.token },
      );
      assert.equal(accepted.statusCode, 200, accepted.body);
      assert.equal(accepted.json().circle.members.length, 2);
      assert.equal(
        (
          await h.request(bob.token, 'POST', '/v1/circle-invites/' + link.id + '/accept', {
            token: link.token,
          })
        ).json().replayed,
        true,
      );
      assert.equal((await h.request(stranger.token, 'GET', '/v1/circles/' + id)).statusCode, 404);
      assert.equal((await h.asUser(stranger.id, 'SELECT id FROM public.circles')).rows.length, 0);
      await assert.rejects(h.asUser(bob.id, 'SELECT token_hash FROM public.circle_invites'), {
        code: '42501',
      });
    },
  );

  await t.test(
    'expired invitations cannot join; owner-only invitation rights and API-role quotas apply',
    async () => {
      const alice = await h.user('Expiry owner'),
        bob = await h.user('Expiry invitee'),
        stranger = await h.user('Cannot invite');
      const id = await circle(alice.token),
        link = await invite(alice.token, id, bob.id);
      await h.admin.query(
        "UPDATE public.circle_invites SET created_at=now()-interval '2 hours',expires_at=now()-interval '1 hour' WHERE id=$1",
        [link.id],
      );
      const expired = await h.request(
        bob.token,
        'POST',
        '/v1/circle-invites/' + link.id + '/accept',
        { token: link.token },
      );
      assert.equal(expired.statusCode, 410, expired.body);
      assert.equal(
        (
          await h.request(stranger.token, 'POST', '/v1/circles/' + id + '/invites', {
            clientRequestId: randomUUID(),
            recipientId: bob.id,
          })
        ).statusCode,
        404,
      );
      assert.equal(
        (
          await h.request(alice.token, 'POST', '/v1/circles/' + id + '/invites', {
            clientRequestId: randomUUID(),
            recipientId: randomUUID(),
          })
        ).statusCode,
        404,
      );
      assert.equal(
        (await h.request(bob.token, 'GET', '/v1/circle-invites')).json().items.length,
        0,
      );
    },
  );

  await t.test(
    'secret rotation requires new invitation delivery commands; issued tokens still need explicit revocation',
    async () => {
      const alice = await h.user('Rotation owner'),
        bob = await h.user('Rotation invitee');
      const id = await circle(alice.token),
        input = { clientRequestId: randomUUID(), recipientId: bob.id };
      const issued = await h.request(alice.token, 'POST', '/v1/circles/' + id + '/invites', input);
      assert.equal(issued.statusCode, 201);
      const rotated = await buildServer({
        ...h.stores,
        inviteToken: inviteTokenFactory('b2'.repeat(32)),
        verifyToken: async (token) =>
          token === alice.token
            ? { id: alice.id, phoneVerified: true }
            : token === bob.token
              ? { id: bob.id, phoneVerified: true }
              : null,
      });
      try {
        const replay = await rotated.inject({
          method: 'POST',
          url: '/v1/circles/' + id + '/invites',
          headers: { authorization: 'Bearer ' + alice.token },
          payload: input,
        });
        assert.equal(replay.statusCode, 409);
        assert.equal(replay.json().code, 'invite_reissue_required');
        const accepted = await rotated.inject({
          method: 'POST',
          url: '/v1/circle-invites/' + issued.json().id + '/accept',
          headers: { authorization: 'Bearer ' + bob.token },
          payload: { token: issued.json().token },
        });
        assert.equal(accepted.statusCode, 200);
        assert.equal(
          (await h.request(alice.token, 'DELETE', '/v1/circle-invites/' + issued.json().id))
            .statusCode,
          200,
        );
        const revoked = await rotated.inject({
          method: 'POST',
          url: '/v1/circle-invites/' + issued.json().id + '/accept',
          headers: { authorization: 'Bearer ' + bob.token },
          payload: { token: issued.json().token },
        });
        assert.equal(revoked.statusCode, 410);
      } finally {
        await rotated.close();
      }
    },
  );

  await t.test(
    'accept/revoke race ends revoked; copied or previously accepted token cannot rejoin',
    async () => {
      const alice = await h.user('Race owner'),
        bob = await h.user('Race invitee');
      const id = await circle(alice.token),
        link = await invite(alice.token, id, bob.id);
      const results = await Promise.all([
        h.request(bob.token, 'POST', '/v1/circle-invites/' + link.id + '/accept', {
          token: link.token,
        }),
        h.request(alice.token, 'DELETE', '/v1/circle-invites/' + link.id),
      ]);
      assert.equal(results[1]!.statusCode, 200);
      assert.ok([200, 410].includes(results[0]!.statusCode));
      assert.equal((await h.request(bob.token, 'GET', '/v1/circles/' + id)).statusCode, 404);
      assert.equal(
        (await h.asUser(bob.id, 'SELECT circle_id FROM public.circle_members')).rows.length,
        0,
      );
      assert.equal(
        (
          await h.request(bob.token, 'POST', '/v1/circle-invites/' + link.id + '/accept', {
            token: link.token,
          })
        ).statusCode,
        410,
      );
    },
  );

  await t.test(
    'leaving is idempotent, owner cannot silently leave, and closure revokes all access',
    async () => {
      const alice = await h.user('Leave owner'),
        bob = await h.user('Leaving member');
      const id = await circle(alice.token),
        link = await invite(alice.token, id, bob.id);
      assert.equal(
        (
          await h.request(bob.token, 'POST', '/v1/circle-invites/' + link.id + '/accept', {
            token: link.token,
          })
        ).statusCode,
        200,
      );
      const leave = '/v1/circles/' + id + '/members/' + bob.id;
      assert.equal((await h.request(bob.token, 'DELETE', leave)).statusCode, 200);
      assert.equal((await h.request(bob.token, 'DELETE', leave)).statusCode, 200);
      assert.equal(
        (await h.request(alice.token, 'DELETE', '/v1/circles/' + id + '/members/' + alice.id))
          .statusCode,
        409,
      );
      assert.equal((await h.request(alice.token, 'DELETE', '/v1/circles/' + id)).statusCode, 200);
      assert.equal((await h.request(alice.token, 'DELETE', '/v1/circles/' + id)).statusCode, 200);
      assert.equal((await h.request(alice.token, 'GET', '/v1/circles/' + id)).statusCode, 404);
      assert.equal(
        (
          await h.request(bob.token, 'POST', '/v1/circle-invites/' + link.id + '/accept', {
            token: link.token,
          })
        ).statusCode,
        410,
      );
    },
  );

  await t.test(
    'database rechecks phone verification and cannot be bypassed by a trusted transport claim',
    async () => {
      const unverified = await h.user('Unconfirmed phone', false, true);
      const result = await h.request(unverified.token, 'POST', '/v1/reports', report());
      assert.equal(result.statusCode, 403, result.body);
      assert.equal(result.json().code, 'verification_required');
      const count = await h.admin.query(
        'SELECT count(*)::integer n FROM public.report_submissions WHERE owner_id=$1',
        [unverified.id],
      );
      assert.equal(count.rows[0]?.n, 0);
    },
  );

  await t.test(
    'concurrent report retries create one row/one quota unit and changed payload conflicts',
    async () => {
      const alice = await h.user('Report retries');
      const input = report();
      const results = await Promise.all(
        Array.from({ length: 8 }, () => h.request(alice.token, 'POST', '/v1/reports', input)),
      );
      assert.equal(results.filter((r) => r.statusCode === 201).length, 1);
      assert.equal(new Set(results.map((r) => r.json().id)).size, 1);
      assert.ok(results.every((r) => [200, 201].includes(r.statusCode)));
      assert.equal(
        (
          await h.request(alice.token, 'POST', '/v1/reports', {
            ...input,
            description: 'Changed valid private description',
          })
        ).statusCode,
        409,
      );
      const quota = await h.admin.query(
        "SELECT used FROM awaaz_private.account_quotas WHERE actor_id=$1 AND kind='report'",
        [alice.id],
      );
      assert.equal(quota.rows[0]?.used, 1);
    },
  );

  await t.test(
    'private report pagination isolates users; public feed contains only unexpired sanitized events',
    async () => {
      const alice = await h.user('Private reports'),
        bob = await h.user('Cannot read reports');
      const ids: string[] = [];
      for (let i = 0; i < 3; i++) {
        const result = await h.request(alice.token, 'POST', '/v1/reports', report());
        assert.equal(result.statusCode, 201, result.body);
        ids.push(result.json().id);
      }
      const first = await h.request(alice.token, 'GET', '/v1/reports?limit=2');
      assert.equal(first.statusCode, 200);
      assert.equal(first.json().items.length, 2);
      assert.ok(first.json().nextCursor);
      const second = await h.request(
        alice.token,
        'GET',
        '/v1/reports?limit=2&cursor=' + first.json().nextCursor,
      );
      assert.equal(second.json().items.length, 1);
      assert.equal(second.json().nextCursor, null);
      assert.equal(
        new Set([...first.json().items, ...second.json().items].map((r: { id: string }) => r.id))
          .size,
        3,
      );
      assert.equal((await h.request(bob.token, 'GET', '/v1/reports')).json().items.length, 0);
      assert.equal((await h.request(bob.token, 'DELETE', '/v1/reports/' + ids[0])).statusCode, 404);
      await h.admin.query(
        "INSERT INTO public.road_events(submission_id,category,road_segment_id,centroid,public_summary,observed_at,expires_at) VALUES($1,'lighting','demo-road',extensions.st_setsrid(extensions.st_makepoint(90.380456,23.760123),4326)::extensions.geography,'Sanitized lighting condition',now(),now()+interval '1 hour')",
        [ids[0]],
      );
      await h.admin.query(
        "INSERT INTO public.road_events(submission_id,category,road_segment_id,centroid,public_summary,observed_at,expires_at) VALUES($1,'lighting','expired-road',extensions.st_setsrid(extensions.st_makepoint(90.38,23.76),4326)::extensions.geography,'Expired event',now()-interval '2 hours',now()-interval '1 hour')",
        [ids[1]],
      );
      const feed = await h.request(bob.token, 'GET', '/v1/road-events');
      assert.equal(feed.statusCode, 200, feed.body);
      assert.equal(feed.json().items.length, 1);
      assert.equal(feed.json().items[0].latitude, 23.76);
      assert.equal(feed.json().items[0].longitude, 90.38);
      for (const sensitive of [alice.id, ids[0]!, 'PRIVATE', 'submission_id', 'payload_hash'])
        assert.equal(feed.body.includes(sensitive), false);
      await assert.rejects(h.asUser(bob.id, 'SELECT submission_id FROM public.road_events'), {
        code: '42501',
      });
      assert.equal((await h.asUser(bob.id, 'SELECT id FROM public.road_events')).rows.length, 1);
    },
  );

  await t.test(
    'deleting removes private/public payloads and cannot be undone by replaying a command',
    async () => {
      const alice = await h.user('Withdrawal');
      const input = report(),
        created = await h.request(alice.token, 'POST', '/v1/reports', input),
        id = created.json().id;
      await h.admin.query(
        "INSERT INTO public.road_events(submission_id,category,road_segment_id,centroid,public_summary,observed_at,expires_at) VALUES($1,'lighting','withdrawal-road',extensions.st_setsrid(extensions.st_makepoint(90.38,23.76),4326)::extensions.geography,'Sanitized condition',now(),now()+interval '1 hour')",
        [id],
      );
      assert.equal((await h.request(alice.token, 'DELETE', '/v1/reports/' + id)).statusCode, 200);
      assert.equal((await h.request(alice.token, 'DELETE', '/v1/reports/' + id)).statusCode, 200);
      const replay = await h.request(alice.token, 'POST', '/v1/reports', input);
      assert.equal(replay.statusCode, 200);
      assert.deepEqual(replay.json(), { id, status: 'withdrawn', replayed: true });
      const raw = await h.admin.query(
        'SELECT count(*)::integer n FROM public.report_submissions WHERE id=$1',
        [id],
      );
      const published = await h.admin.query(
        'SELECT count(*)::integer n FROM public.road_events WHERE submission_id=$1',
        [id],
      );
      assert.equal(raw.rows[0]?.n, 0);
      assert.equal(published.rows[0]?.n, 0);
      const ledger = await h.admin.query(
        "SELECT column_name FROM information_schema.columns WHERE table_schema='awaaz_private' AND table_name='report_commands'",
      );
      assert.equal(
        ledger.rows.some((r) =>
          ['description', 'location', 'latitude', 'longitude'].includes(r.column_name),
        ),
        false,
      );
    },
  );

  await t.test(
    'durable report quota survives deletion and rejected attempts do not corrupt it',
    async () => {
      const alice = await h.user('Quota owner');
      for (let i = 0; i < 20; i++) {
        const input = report(),
          saved = await h.stores.reports.create(alice.id, input, hash(input));
        await h.stores.community.withdraw(alice.id, saved.id);
      }
      const input = report();
      await assert.rejects(
        h.stores.reports.create(alice.id, input, hash(input)),
        (error) => error instanceof DomainError && error.code === 'rate_limited',
      );
      const quota = await h.admin.query(
        "SELECT used FROM awaaz_private.account_quotas WHERE actor_id=$1 AND kind='report'",
        [alice.id],
      );
      assert.equal(quota.rows[0]?.used, 20);
      assert.equal(
        (
          await h.admin.query(
            'SELECT count(*)::integer n FROM public.report_submissions WHERE owner_id=$1',
            [alice.id],
          )
        ).rows[0]?.n,
        0,
      );
    },
  );

  await t.test(
    'outbox is isolated and unknown-risk constraints reject invented zero risk',
    async () => {
      const alice = await h.user('RLS safety');
      await assert.rejects(h.asUser(alice.id, 'SELECT * FROM public.notification_outbox'), {
        code: '42501',
      });
      await assert.rejects(h.api.query('SELECT * FROM public.notification_outbox'), {
        code: '42501',
      });
      const snapshot = await h.admin.query(
        "INSERT INTO public.risk_snapshots(graph_version,scoring_version,expires_at) VALUES('fixture','baseline',now()+interval '1 hour') RETURNING id",
      );
      await assert.rejects(
        h.admin.query(
          "INSERT INTO public.edge_risk(snapshot_id,edge_id,risk_signal,uncertainty,confidence,event_cluster_count) VALUES($1,'invented',0,1,0,0)",
          [snapshot.rows[0]?.id],
        ),
        { code: '23514' },
      );
      await h.admin.query(
        "INSERT INTO public.edge_risk(snapshot_id,edge_id,risk_signal,uncertainty,confidence,event_cluster_count) VALUES($1,'unknown',null,1,0,0)",
        [snapshot.rows[0]?.id],
      );
      await assert.rejects(h.asUser(alice.id, 'SELECT * FROM awaaz_private.report_commands'), {
        code: '42501',
      });
      await assert.rejects(h.asAnon('SELECT id FROM public.road_events'), { code: '42501' });
    },
  );

  await t.test(
    'Auth deletion cascades profiles/circles/reports/retry metadata and contact membership',
    async () => {
      const alice = await h.user('Deleted account'),
        bob = await h.user('Surviving owner');
      const ownCircle = await circle(alice.token),
        other = await circle(bob.token),
        link = await invite(bob.token, other, alice.id);
      await h.request(alice.token, 'POST', '/v1/circle-invites/' + link.id + '/accept', {
        token: link.token,
      });
      await h.request(alice.token, 'POST', '/v1/reports', report());
      await h.admin.query('DELETE FROM auth.users WHERE id=$1', [alice.id]);
      for (const [table, column] of [
        ['public.profiles', 'id'],
        ['public.circles', 'owner_id'],
        ['public.circle_members', 'user_id'],
        ['public.report_submissions', 'owner_id'],
        ['awaaz_private.report_commands', 'actor_id'],
        ['awaaz_private.account_quotas', 'actor_id'],
      ] as const) {
        const result = await h.admin.query(
          'SELECT count(*)::integer n FROM ' + table + ' WHERE ' + column + '=$1',
          [alice.id],
        );
        assert.equal(result.rows[0]?.n, 0, table);
      }
      const survived = await h.request(bob.token, 'GET', '/v1/circles/' + other);
      assert.equal(survived.statusCode, 200);
      assert.equal(survived.json().members.length, 1);
      assert.equal((await h.request(bob.token, 'GET', '/v1/circles/' + ownCircle)).statusCode, 404);
    },
  );
});
