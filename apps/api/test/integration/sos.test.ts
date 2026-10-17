import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { databaseHarness } from './harness.ts';

test('SOS consent, durable fan-out, response and revocation boundaries', async (t) => {
  const h = await databaseHarness();
  type User = Awaited<ReturnType<typeof h.user>>;
  const call = async (
    user: User,
    method: 'GET' | 'POST' | 'PUT' | 'DELETE',
    path: string,
    body?: object,
    expected = 200,
  ) => {
    const result = await h.request(user.token, method, path, body);
    assert.equal(result.statusCode, expected, `${method} ${path}: ${result.body}`);
    return result.json();
  };
  const circle = async (owner: User, members: User[]) => {
    const created = await call(
      owner,
      'POST',
      '/v1/circles',
      { clientRequestId: randomUUID(), name: 'Consenting help contacts' },
      201,
    );
    for (const member of members) {
      const invite = await call(
        owner,
        'POST',
        `/v1/circles/${created.circle.id}/invites`,
        { clientRequestId: randomUUID(), recipientId: member.id },
        201,
      );
      await call(member, 'POST', `/v1/circle-invites/${invite.id}/accept`, { token: invite.token });
    }
    return created.circle.id as string;
  };
  const optIn = async (user: User) =>
    call(user, 'PUT', '/v1/me/sos-preference', { allowed: true, expectedVersion: 0 });
  const input = (circleId: string, recipients: User[], shareLocation = true) => ({
    clientRequestId: randomUUID(),
    circleId,
    recipientIds: recipients.map((u) => u.id),
    mode: 'silent',
    shareLocation,
  });
  try {
    await t.test(
      'all recipients opt in; retries cannot change consent or claim delivery',
      async () => {
        const alice = await h.user('Help Alice'),
          bob = await h.user('Help Bob'),
          cara = await h.user('Help Cara'),
          outsider = await h.user('Help outsider');
        const group = await circle(alice, [bob, cara]);
        assert.deepEqual(await call(bob, 'GET', '/v1/me/sos-preference'), {
          allowed: false,
          version: 0,
        });
        assert.deepEqual(
          (await call(alice, 'GET', `/v1/circles/${group}/sos-recipients`)).items,
          [],
        );
        const command = input(group, [bob, cara]);
        await call(
          alice,
          'POST',
          '/v1/incidents',
          { ...command, status: 'provider_accepted' },
          400,
        );
        await call(alice, 'POST', '/v1/incidents', { ...command, shareLocation: 'true' }, 400);
        await call(alice, 'POST', '/v1/incidents', command, 409);
        assert.equal(
          (await h.admin.query('select count(*)::int as n from public.incidents')).rows[0].n,
          0,
        );
        await optIn(bob);
        await call(alice, 'POST', '/v1/incidents', command, 409);
        await optIn(cara);
        const first = await call(alice, 'POST', '/v1/incidents', command, 201);
        assert.equal(first.replayed, false);
        assert.equal(first.status, 'active');
        assert.equal(first.recipients.length, 2);
        assert.ok(
          first.recipients.every(
            (r: { delivery: { status: string }[] }) =>
              r.delivery.length === 1 && r.delivery[0]!.status === 'queued',
          ),
        );
        assert.equal(
          (await h.admin.query('select count(*)::int as n from public.notification_outbox')).rows[0]
            .n,
          2,
        );
        const replay = await call(alice, 'POST', '/v1/incidents', {
          ...command,
          recipientIds: [...command.recipientIds].reverse(),
        });
        assert.equal(replay.id, first.id);
        assert.equal(replay.expiresAt, first.expiresAt);
        assert.equal(replay.replayed, true);
        await call(alice, 'POST', '/v1/incidents', { ...command, shareLocation: false }, 409);
        await call(alice, 'POST', '/v1/incidents', input(group, [bob]), 409);
        const gate = await h.app.inject('/v1/sos/status');
        assert.deepEqual(gate.json(), {
          requestStorage: true,
          pushDelivery: false,
          smsDelivery: false,
        });
        const view = await call(bob, 'GET', `/v1/incidents/${first.id}`);
        assert.equal(view.location, null); // No GPS dependency on creating the incident.
        assert.equal(view.response, null); // Reading never acknowledges a request.
        await call(outsider, 'GET', `/v1/incidents/${first.id}`, undefined, 404);
        await call(alice, 'GET', `/v1/incidents/${first.id}`, undefined, 404);
        assert.equal((await call(bob, 'GET', '/v1/me/incidents?limit=1')).items[0].id, first.id);
        const point = {
          sequence: 1,
          latitude: 23.76,
          longitude: 90.38,
          accuracyMetres: 8,
          capturedAt: new Date().toISOString(),
        };
        const accepted = await call(alice, 'PUT', `/v1/incidents/${first.id}/position`, point);
        const retried = await call(alice, 'PUT', `/v1/incidents/${first.id}/position`, point);
        assert.equal(retried.replayed, true);
        assert.equal(retried.expiresAt, accepted.expiresAt);
        assert.equal(
          (await call(bob, 'GET', `/v1/incidents/${first.id}`)).location.latitude,
          point.latitude,
        );
        await call(bob, 'PUT', `/v1/incidents/${first.id}/position`, point, 404);
        const seen = await call(bob, 'PUT', `/v1/incidents/${first.id}/response`, {
          response: 'seen',
          expectedVersion: 0,
        });
        assert.equal(seen.version, 1);
        const afterSeen = (
          await h.admin.query(
            'select recipient_id,status from public.notification_outbox where incident_id=$1',
            [first.id],
          )
        ).rows;
        assert.equal(afterSeen.find((j) => j.recipient_id === bob.id)!.status, 'cancelled');
        assert.equal(afterSeen.find((j) => j.recipient_id === cara.id)!.status, 'queued');
        assert.equal(
          (
            await call(bob, 'PUT', `/v1/incidents/${first.id}/response`, {
              response: 'seen',
              expectedVersion: 0,
            })
          ).replayed,
          true,
        );
        const kept = await call(bob, 'PUT', `/v1/incidents/${first.id}/response`, {
          response: 'seen',
          expectedVersion: 1,
        });
        assert.equal(kept.version, 2);
        await call(
          bob,
          'PUT',
          `/v1/incidents/${first.id}/response`,
          { response: 'helping', expectedVersion: 1 },
          409,
        );
        await call(bob, 'PUT', `/v1/incidents/${first.id}/response`, {
          response: 'helping',
          expectedVersion: 2,
        });
        await call(
          bob,
          'PUT',
          `/v1/incidents/${first.id}/response`,
          { response: 'seen', expectedVersion: 0 },
          409,
        );
        const ended = await call(alice, 'POST', `/v1/incidents/${first.id}/end`, {
          outcome: 'resolved',
        });
        assert.equal(ended.status, 'ended');
        assert.equal(ended.version, 2);
        assert.equal(
          ended.recipients.find((r: { userId: string }) => r.userId === bob.id).response,
          'helping',
        );
        assert.equal((await call(bob, 'GET', `/v1/incidents/${first.id}`)).location, null);
        assert.equal((await call(bob, 'GET', `/v1/incidents/${first.id}`)).status, 'ended');
        assert.equal(
          (await h.admin.query('select count(*)::int as n from awaaz_private.sos_positions'))
            .rows[0].n,
          0,
        );
        const jobs = (
          await h.admin.query(
            'select kind,status from public.notification_outbox where incident_id=$1',
            [first.id],
          )
        ).rows;
        assert.equal(
          jobs.filter((j) => j.kind === 'request' && j.status === 'cancelled').length,
          2,
        );
        assert.equal(jobs.filter((j) => j.kind === 'resolved' && j.status === 'queued').length, 1);
        const again = await call(alice, 'POST', `/v1/incidents/${first.id}/end`, {
          outcome: 'cancelled',
        });
        assert.equal(again.status, 'ended');
        assert.equal(again.version, 2);
        assert.equal((await call(alice, 'POST', '/v1/incidents', command)).status, 'ended');
        assert.equal(
          (
            await h.admin.query(
              'select count(*)::int as n from public.notification_outbox where incident_id=$1',
              [first.id],
            )
          ).rows[0].n,
          3,
        );
        await call(
          alice,
          'PUT',
          `/v1/incidents/${first.id}/position`,
          { ...point, sequence: 2 },
          410,
        );
        await call(outsider, 'POST', `/v1/incidents/${first.id}/end`, { outcome: 'resolved' }, 404);
      },
    );

    await t.test(
      'preference ABA, decline, and blocking permanently revoke old grants',
      async () => {
        const alice = await h.user('Revocation Alice'),
          bob = await h.user('Revocation Bob');
        const group = await circle(alice, [bob]);
        await optIn(bob);
        const withdrawn = input(group, [bob]);
        const closed = await call(
          alice,
          'DELETE',
          `/v1/incident-requests/${withdrawn.clientRequestId}`,
        );
        assert.equal(closed.incidentId, null);
        assert.equal(closed.incidentStatus, null);
        assert.deepEqual(
          await call(alice, 'DELETE', `/v1/incident-requests/${withdrawn.clientRequestId}`),
          closed,
        );
        await call(alice, 'POST', '/v1/incidents', withdrawn, 410);
        const incident = await call(
          alice,
          'POST',
          '/v1/incidents',
          input(group, [bob], false),
          201,
        );
        await call(
          alice,
          'PUT',
          `/v1/incidents/${incident.id}/position`,
          {
            sequence: 1,
            latitude: 23.76,
            longitude: 90.38,
            accuracyMetres: 8,
            capturedAt: new Date().toISOString(),
          },
          410,
        );
        await call(bob, 'PUT', '/v1/me/sos-preference', { allowed: false, expectedVersion: 1 });
        await call(bob, 'PUT', '/v1/me/sos-preference', { allowed: true, expectedVersion: 2 });
        await call(bob, 'PUT', '/v1/me/sos-preference', { allowed: true, expectedVersion: 0 }, 409);
        await call(bob, 'GET', `/v1/incidents/${incident.id}`, undefined, 404);
        assert.equal(
          (
            await h.admin.query(
              'select status from public.notification_outbox where incident_id=$1',
              [incident.id],
            )
          ).rows[0].status,
          'cancelled',
        );
        await call(alice, 'POST', `/v1/incidents/${incident.id}/end`, { outcome: 'cancelled' });
        const next = await call(alice, 'POST', '/v1/incidents', input(group, [bob]), 201);
        await call(bob, 'DELETE', `/v1/incidents/${next.id}/access`);
        await call(bob, 'DELETE', `/v1/incidents/${next.id}/access`);
        await call(bob, 'GET', `/v1/incidents/${next.id}`, undefined, 404);
        await call(alice, 'POST', `/v1/incidents/${next.id}/end`, { outcome: 'cancelled' });
        const third = await call(alice, 'POST', '/v1/incidents', input(group, [bob]), 201);
        const keptPreference = await call(bob, 'PUT', '/v1/me/sos-preference', {
          allowed: true,
          expectedVersion: 3,
        });
        assert.equal(keptPreference.version, 4);
        await call(
          bob,
          'PUT',
          '/v1/me/sos-preference',
          { allowed: false, expectedVersion: 3 },
          409,
        );
        await call(bob, 'GET', `/v1/incidents/${third.id}`);
        await call(bob, 'PUT', `/v1/me/blocks/${alice.id}`, { blocked: true, expectedVersion: 0 });
        await call(bob, 'PUT', `/v1/me/blocks/${alice.id}`, { blocked: false, expectedVersion: 1 });
        await call(bob, 'GET', `/v1/incidents/${third.id}`, undefined, 404);
        await call(alice, 'POST', `/v1/incidents/${third.id}/end`, { outcome: 'cancelled' });
        const newGroup = await circle(alice, [bob]);
        const fourth = await call(alice, 'POST', '/v1/incidents', input(newGroup, [bob]), 201);
        await h.stores.people.removeMember(alice.id, newGroup, bob.id);
        const rejoin = await call(
          alice,
          'POST',
          `/v1/circles/${newGroup}/invites`,
          { clientRequestId: randomUUID(), recipientId: bob.id },
          201,
        );
        await call(bob, 'POST', `/v1/circle-invites/${rejoin.id}/accept`, { token: rejoin.token });
        await call(bob, 'GET', `/v1/incidents/${fourth.id}`, undefined, 404);
        await call(alice, 'POST', `/v1/incidents/${fourth.id}/end`, { outcome: 'cancelled' });
        const fifth = await call(alice, 'POST', '/v1/incidents', input(newGroup, [bob]), 201);
        await h.stores.people.closeCircle(alice.id, newGroup);
        await call(bob, 'GET', `/v1/incidents/${fifth.id}`, undefined, 404);
        await call(alice, 'POST', `/v1/incidents/${fifth.id}/end`, { outcome: 'cancelled' });
      },
    );

    await t.test(
      'expiry, ambiguous in-flight cancellation, direct-role denial and account erasure',
      async () => {
        const alice = await h.user('Expiry Alice'),
          bob = await h.user('Expiry Bob');
        const group = await circle(alice, [bob]);
        await optIn(bob);
        const command = input(group, [bob]);
        const incident = await call(alice, 'POST', '/v1/incidents', command, 201);
        await call(alice, 'PUT', `/v1/incidents/${incident.id}/position`, {
          sequence: 1,
          latitude: 23.76,
          longitude: 90.38,
          accuracyMetres: 8,
          capturedAt: new Date().toISOString(),
        });
        await h.admin.query(
          "update awaaz_private.sos_positions set purge_at=clock_timestamp()-interval '1 second' where incident_id=$1",
          [incident.id],
        );
        assert.equal((await call(bob, 'GET', `/v1/incidents/${incident.id}`)).location, null);
        await h.stores.sos.cleanupExpired();
        assert.equal(
          (
            await h.admin.query(
              'select count(*)::int as n from awaaz_private.sos_positions where incident_id=$1',
              [incident.id],
            )
          ).rows[0].n,
          0,
        );
        // A network attempt may have reached a provider; cancellation cannot invent non-delivery.
        await h.admin.query(
          "update public.notification_outbox set status='sending',attempts=1 where incident_id=$1",
          [incident.id],
        );
        await call(alice, 'POST', `/v1/incidents/${incident.id}/end`, { outcome: 'cancelled' });
        const rows = (
          await h.admin.query(
            'select kind,status,cancelled_at from public.notification_outbox where incident_id=$1',
            [incident.id],
          )
        ).rows;
        assert.ok(
          rows.some((j) => j.kind === 'request' && j.status === 'unknown' && j.cancelled_at),
        );
        assert.ok(rows.some((j) => j.kind === 'cancelled' && j.status === 'queued'));
        await h.admin.query(
          "update public.notification_outbox set expires_at=clock_timestamp()-interval '1 second' where incident_id=$1",
          [incident.id],
        );
        const beforeCleanup = await call(
          alice,
          'GET',
          `/v1/incident-requests/${command.clientRequestId}`,
        );
        assert.equal(
          beforeCleanup.recipients[0].delivery.find((j: { kind: string }) => j.kind === 'cancelled')
            .status,
          'expired',
        );
        await h.stores.sos.cleanupExpired();
        assert.equal(
          (
            await h.admin.query(
              "select status from public.notification_outbox where incident_id=$1 and kind='cancelled'",
              [incident.id],
            )
          ).rows[0].status,
          'expired',
        );
        for (const relation of [
          'public.incidents',
          'public.notification_outbox',
          'awaaz_private.sos_preferences',
          'awaaz_private.sos_grants',
          'awaaz_private.sos_positions',
          'awaaz_private.sos_request_cancellations',
        ]) {
          await assert.rejects(h.api.query('select * from ' + relation), { code: '42501' });
          await assert.rejects(h.asUser(bob.id, 'select * from ' + relation), { code: '42501' });
        }
        await assert.rejects(
          h.api.query('select awaaz_private.sos_view($1,$2)', [bob.id, incident.id]),
          { code: '42501' },
        );
        assert.equal((await h.app.inject('/ready')).statusCode, 200);
        await h.admin.query('grant select(latitude) on awaaz_private.sos_positions to awaaz_api');
        try {
          assert.equal((await h.app.inject('/ready')).statusCode, 503);
        } finally {
          await h.admin.query(
            'revoke select(latitude) on awaaz_private.sos_positions from awaaz_api',
          );
        }
        assert.equal((await h.app.inject('/ready')).statusCode, 200);
        await h.admin.query(
          "update public.incidents set expires_at=clock_timestamp()-interval '25 hours' where id=$1",
          [incident.id],
        );
        assert.deepEqual(
          (await call(alice, 'GET', `/v1/incident-requests/${command.clientRequestId}`)).recipients,
          [],
        );
        await call(bob, 'GET', `/v1/incidents/${incident.id}`, undefined, 404);
        await h.stores.sos.cleanupExpired();
        assert.equal(
          (
            await h.admin.query(
              'select count(*)::int as n from awaaz_private.sos_grants where incident_id=$1',
              [incident.id],
            )
          ).rows[0].n,
          0,
        );
        await h.admin.query('delete from auth.users where id=$1', [alice.id]);
        assert.equal(
          (
            await h.admin.query('select count(*)::int as n from public.incidents where id=$1', [
              incident.id,
            ])
          ).rows[0].n,
          0,
        );
        assert.equal(
          (
            await h.admin.query(
              'select count(*)::int as n from public.notification_outbox where incident_id=$1',
              [incident.id],
            )
          ).rows[0].n,
          0,
        );
      },
    );

    await t.test(
      'a real simultaneous block cannot leave an authorized request or queued alert',
      async () => {
        const alice = await h.user('Race Alice'),
          bob = await h.user('Race Bob');
        const group = await circle(alice, [bob]);
        await optIn(bob);
        const uncertain = input(group, [bob]);
        const [start, stop] = await Promise.all([
          h.request(alice.token, 'POST', '/v1/incidents', uncertain),
          h.request(alice.token, 'DELETE', `/v1/incident-requests/${uncertain.clientRequestId}`),
        ]);
        assert.equal(stop.statusCode, 200, stop.body);
        assert.ok([201, 410].includes(start.statusCode), start.body);
        assert.equal((await call(alice, 'GET', '/v1/me/incident')).incident, null);
        if (start.statusCode === 201) {
          await call(bob, 'GET', `/v1/incidents/${start.json().id}`, undefined, 404);
        }
        const [created, blocked] = await Promise.all([
          h.request(alice.token, 'POST', '/v1/incidents', input(group, [bob])),
          h.request(bob.token, 'PUT', `/v1/me/blocks/${alice.id}`, {
            blocked: true,
            expectedVersion: 0,
          }),
        ]);
        assert.equal(blocked.statusCode, 200, blocked.body);
        assert.ok([201, 409].includes(created.statusCode), created.body);
        if (created.statusCode === 201) {
          const id = created.json().id;
          await call(bob, 'GET', `/v1/incidents/${id}`, undefined, 404);
          assert.equal(
            (
              await h.admin.query(
                'select status from public.notification_outbox where incident_id=$1',
                [id],
              )
            ).rows[0].status,
            'cancelled',
          );
        }
      },
    );
  } finally {
    await h.close();
  }
});
