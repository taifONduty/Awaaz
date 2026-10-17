import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { databaseHarness } from './harness.ts';

test('consented latest-position sharing on real PostgreSQL', { timeout: 120000 }, async (t) => {
  const h = await databaseHarness();
  t.after(h.close);
  type User = Awaited<ReturnType<typeof h.user>>;
  const circle = async (owner: User) => {
    const r = await h.request(owner.token, 'POST', '/v1/circles', {
      clientRequestId: randomUUID(),
      name: 'Private fixture Circle',
    });
    assert.equal(r.statusCode, 201, r.body);
    return r.json().circle.id as string;
  };
  const join = async (owner: User, id: string, person: User) => {
    const invite = await h.request(owner.token, 'POST', `/v1/circles/${id}/invites`, {
      clientRequestId: randomUUID(),
      recipientId: person.id,
    });
    assert.equal(invite.statusCode, 201, invite.body);
    const accepted = await h.request(
      person.token,
      'POST',
      `/v1/circle-invites/${invite.json().id}/accept`,
      { token: invite.json().token },
    );
    assert.equal(accepted.statusCode, 200, accepted.body);
  };
  const start = (owner: User, id: string, people: User[], requestId = randomUUID()) =>
    h.request(owner.token, 'POST', '/v1/shares', {
      clientRequestId: requestId,
      circleId: id,
      recipientIds: people.map((p) => p.id),
      durationSeconds: 600,
    });
  const fix = (sequence = 1) => ({
    sequence,
    latitude: 23.76,
    longitude: 90.38,
    accuracyMetres: 12,
    capturedAt: new Date().toISOString(),
  });

  await t.test(
    'only explicit recipients read a current point; replay, sequencing and stop never restore data',
    async () => {
      const a = await h.user('Sharer'),
        b = await h.user('Selected contact'),
        c = await h.user('Unselected Circle member');
      const id = await circle(a);
      await join(a, id, b);
      await join(a, id, c);
      const requestId = randomUUID();
      const [created, replayed] = await Promise.all([
        start(a, id, [b], requestId),
        start(a, id, [b], requestId),
      ]);
      assert.deepEqual([created.statusCode, replayed.statusCode].sort(), [200, 201]);
      const share = created.json();
      assert.equal(share.id, replayed.json().id);
      assert.equal((await start(a, id, [c], requestId)).statusCode, 409);
      assert.equal((await start(a, id, [b])).json().code, 'share_already_active');
      assert.equal((await h.request(c.token, 'GET', `/v1/shares/${share.id}`)).statusCode, 404);
      const waiting = await h.request(b.token, 'GET', `/v1/shares/${share.id}`);
      assert.equal(waiting.statusCode, 200, waiting.body);
      assert.equal(waiting.json().location, null);
      assert.equal(waiting.json().freshness, 'waiting');
      const incoming = await h.request(b.token, 'GET', '/v1/shared-trips');
      assert.equal(incoming.json().items.length, 1);
      assert.ok(!incoming.body.includes('latitude'));
      const position = fix();
      const first = await h.request(a.token, 'PUT', `/v1/shares/${share.id}/position`, position);
      assert.equal(first.statusCode, 200, first.body);
      const duplicate = await h.request(
        a.token,
        'PUT',
        `/v1/shares/${share.id}/position`,
        position,
      );
      assert.equal(duplicate.statusCode, 200, duplicate.body);
      assert.equal(duplicate.json().replayed, true);
      assert.equal(duplicate.json().expiresAt, first.json().expiresAt);
      assert.equal(
        (
          await h.request(a.token, 'PUT', `/v1/shares/${share.id}/position`, {
            ...position,
            latitude: 23.77,
          })
        ).json().code,
        'stale_position',
      );
      assert.equal(
        (await h.request(b.token, 'PUT', `/v1/shares/${share.id}/position`, fix(2))).statusCode,
        404,
      );
      const current = await h.request(b.token, 'GET', `/v1/shares/${share.id}`);
      assert.equal(current.json().freshness, 'fresh');
      assert.equal(current.json().location.latitude, position.latitude);
      assert.equal(current.headers['cache-control'], 'no-store');
      assert.equal(
        (
          await h.admin.query(
            'SELECT count(*)::int n FROM awaaz_private.trip_share_positions WHERE share_id=$1',
            [share.id],
          )
        ).rows[0].n,
        1,
      );
      const changed = { ...fix(2), capturedAt: new Date(Date.now() + 50).toISOString() };
      assert.equal(
        (await h.request(a.token, 'PUT', `/v1/shares/${share.id}/position`, changed)).statusCode,
        429,
      );
      await h.admin.query(
        "UPDATE awaaz_private.trip_shares SET last_accepted_at=last_accepted_at-interval '6 seconds' WHERE id=$1",
        [share.id],
      );
      const second = await h.request(a.token, 'PUT', `/v1/shares/${share.id}/position`, changed);
      assert.equal(second.statusCode, 200, second.body);
      assert.equal(
        (await h.request(a.token, 'DELETE', `/v1/shares/${share.id}`)).json().status,
        'stopped',
      );
      assert.equal(
        (await h.request(a.token, 'DELETE', `/v1/shares/${share.id}`)).json().status,
        'stopped',
      );
      assert.equal(
        (await h.request(a.token, 'PUT', `/v1/shares/${share.id}/position`, fix(3))).statusCode,
        410,
      );
      assert.equal((await h.request(b.token, 'GET', `/v1/shares/${share.id}`)).statusCode, 404);
      const old = await start(a, id, [b], requestId);
      assert.equal(old.statusCode, 200, old.body);
      assert.equal(old.json().status, 'stopped');
      assert.equal(
        (await h.request(a.token, 'GET', `/v1/share-requests/${requestId}`)).json().status,
        'stopped',
      );
      assert.equal(
        (await h.request(c.token, 'GET', `/v1/share-requests/${requestId}`)).statusCode,
        404,
      );
      assert.equal((await h.request(a.token, 'GET', '/v1/me/share')).json().share, null);
      assert.equal(
        (
          await h.admin.query(
            'SELECT count(*)::int n FROM awaaz_private.trip_share_positions WHERE share_id=$1',
            [share.id],
          )
        ).rows[0].n,
        0,
      );
      assert.equal(
        (
          await h.admin.query(
            'SELECT count(*)::int n FROM awaaz_private.trip_share_grants WHERE share_id=$1',
            [share.id],
          )
        ).rows[0].n,
        0,
      );
    },
  );

  await t.test(
    'leave/rejoin, block/unblock and recipient decline cannot revive old grants',
    async () => {
      const a = await h.user('Sharer'),
        b = await h.user('Recipient'),
        c = await h.user('Other recipient');
      const id = await circle(a);
      await join(a, id, b);
      await join(a, id, c);
      const created = await start(a, id, [b, c]);
      assert.equal(created.statusCode, 201, created.body);
      const shareId = created.json().id;
      assert.equal(
        (await h.request(b.token, 'DELETE', `/v1/circles/${id}/members/${b.id}`)).statusCode,
        200,
      );
      await join(a, id, b);
      assert.equal((await h.request(b.token, 'GET', `/v1/shares/${shareId}`)).statusCode, 404);
      assert.equal(
        (
          await h.request(a.token, 'PUT', `/v1/me/blocks/${c.id}`, {
            blocked: true,
            expectedVersion: 0,
          })
        ).statusCode,
        200,
      );
      assert.equal((await h.request(c.token, 'GET', `/v1/shares/${shareId}`)).statusCode, 404);
      assert.equal(
        (
          await h.request(a.token, 'PUT', `/v1/me/blocks/${c.id}`, {
            blocked: false,
            expectedVersion: 1,
          })
        ).statusCode,
        200,
      );
      await join(a, id, c);
      assert.equal((await h.request(c.token, 'GET', `/v1/shares/${shareId}`)).statusCode, 404);
      assert.equal(
        (await h.request(a.token, 'PUT', `/v1/shares/${shareId}/position`, fix())).statusCode,
        410,
      );
      await h.request(a.token, 'DELETE', `/v1/shares/${shareId}`);
      const next = await start(a, id, [b, c]);
      assert.equal(next.statusCode, 201, next.body);
      const nextId = next.json().id;
      assert.equal(
        (await h.request(b.token, 'DELETE', `/v1/shares/${nextId}/recipients/${c.id}`)).statusCode,
        404,
      );
      assert.equal(
        (await h.request(b.token, 'DELETE', `/v1/shares/${nextId}/recipients/${b.id}`)).statusCode,
        200,
      );
      assert.equal(
        (await h.request(b.token, 'DELETE', `/v1/shares/${nextId}/recipients/${b.id}`)).statusCode,
        200,
      );
      assert.equal((await h.request(b.token, 'GET', `/v1/shares/${nextId}`)).statusCode, 404);
      assert.equal((await h.request(c.token, 'GET', `/v1/shares/${nextId}`)).statusCode, 200);
      assert.equal((await h.request(a.token, 'DELETE', `/v1/circles/${id}`)).statusCode, 200);
      assert.equal((await h.request(c.token, 'GET', `/v1/shares/${nextId}`)).statusCode, 404);
    },
  );

  await t.test(
    'block-versus-consent and stop-versus-upload serialize without reviving access',
    async () => {
      const a = await h.user('Concurrent sharer'),
        b = await h.user('Concurrent reader');
      const id = await circle(a);
      await join(a, id, b);
      const race = async <T>(operations: () => Promise<T>): Promise<T> => {
        const gate = await h.admin.connect();
        let running: Promise<T> | undefined;
        try {
          await gate.query('BEGIN');
          await gate.query('SELECT pg_advisory_xact_lock(hashtextextended($1::text,0))', [a.id]);
          running = operations();
          const deadline = Date.now() + 3000;
          let waiting = false;
          do {
            const state = await h.admin.query(
              "SELECT count(*)::int n FROM pg_stat_activity WHERE datname=$1 AND wait_event='advisory'",
              [h.name],
            );
            if (state.rows[0].n >= 2) {
              waiting = true;
              break;
            }
            await new Promise((resolve) => setTimeout(resolve, 20));
          } while (Date.now() < deadline);
          assert.ok(waiting, 'both real operations must be waiting on account locks');
        } finally {
          await gate.query('COMMIT');
          gate.release();
        }
        return running!;
      };
      const [created, blocked] = await race(() =>
        Promise.all([
          start(a, id, [b]),
          h.request(b.token, 'PUT', `/v1/me/blocks/${a.id}`, { blocked: true, expectedVersion: 0 }),
        ]),
      );
      assert.equal(blocked.statusCode, 200, blocked.body);
      assert.ok([201, 409].includes(created.statusCode), created.body);
      if (created.statusCode === 201) {
        assert.equal(
          (await h.request(b.token, 'GET', `/v1/shares/${created.json().id}`)).statusCode,
          404,
        );
        await h.request(a.token, 'DELETE', `/v1/shares/${created.json().id}`);
      }
      assert.equal(
        (
          await h.request(b.token, 'PUT', `/v1/me/blocks/${a.id}`, {
            blocked: false,
            expectedVersion: 1,
          })
        ).statusCode,
        200,
      );
      await join(a, id, b);
      const next = await start(a, id, [b]);
      assert.equal(next.statusCode, 201, next.body);
      const shareId = next.json().id;
      const [position, stopped] = await race(() =>
        Promise.all([
          h.request(a.token, 'PUT', `/v1/shares/${shareId}/position`, fix()),
          h.request(a.token, 'DELETE', `/v1/shares/${shareId}`),
        ]),
      );
      assert.ok([200, 410].includes(position.statusCode), position.body);
      assert.equal(stopped.statusCode, 200, stopped.body);
      assert.equal((await h.request(b.token, 'GET', `/v1/shares/${shareId}`)).statusCode, 404);
      assert.equal(
        (
          await h.admin.query(
            'SELECT count(*)::int n FROM awaaz_private.trip_share_positions WHERE share_id=$1',
            [shareId],
          )
        ).rows[0].n,
        0,
      );
    },
  );

  await t.test(
    'expiry gates exact coordinates, cleanup skips locked sessions, and private roles stay isolated',
    async () => {
      const a = await h.user('Sharer'),
        b = await h.user('Reader');
      const id = await circle(a);
      await join(a, id, b);
      const created = await start(a, id, [b]);
      assert.equal(created.statusCode, 201, created.body);
      const shareId = created.json().id,
        original = fix();
      assert.equal(
        (await h.request(a.token, 'PUT', `/v1/shares/${shareId}/position`, original)).statusCode,
        200,
      );
      await h.admin.query(
        "UPDATE awaaz_private.trip_share_positions SET captured_at=captured_at-interval '2 minutes',accepted_at=accepted_at-interval '2 minutes',purge_at=purge_at-interval '2 minutes' WHERE share_id=$1",
        [shareId],
      );
      await h.admin.query(
        "UPDATE awaaz_private.trip_shares SET last_captured_at=last_captured_at-interval '2 minutes',last_accepted_at=last_accepted_at-interval '2 minutes' WHERE id=$1",
        [shareId],
      );
      const stale = await h.request(b.token, 'GET', `/v1/shares/${shareId}`);
      assert.equal(stale.json().freshness, 'stale');
      assert.equal(stale.json().location, null);
      const lock = await h.admin.connect();
      try {
        await lock.query('BEGIN');
        await lock.query('SELECT id FROM awaaz_private.trip_shares WHERE id=$1 FOR UPDATE', [
          shareId,
        ]);
        await h.stores.sharing.cleanupExpired();
        assert.equal(
          (
            await h.admin.query(
              'SELECT count(*)::int n FROM awaaz_private.trip_share_positions WHERE share_id=$1',
              [shareId],
            )
          ).rows[0].n,
          1,
        );
        await lock.query('COMMIT');
      } finally {
        await lock.query('ROLLBACK');
        lock.release();
      }
      await h.stores.sharing.cleanupExpired();
      assert.equal(
        (
          await h.admin.query(
            'SELECT count(*)::int n FROM awaaz_private.trip_share_positions WHERE share_id=$1',
            [shareId],
          )
        ).rows[0].n,
        0,
      );
      const cleaned = await h.request(b.token, 'GET', `/v1/shares/${shareId}`);
      assert.equal(cleaned.json().freshness, 'stale');
      assert.equal(cleaned.json().location, null);
      assert.equal(
        (await h.request(a.token, 'PUT', `/v1/shares/${shareId}/position`, original)).json().code,
        'stale_position',
      );
      await assert.rejects(h.api.query('SELECT * FROM awaaz_private.trip_share_positions'), {
        code: '42501',
      });
      await assert.rejects(h.asUser(b.id, 'SELECT * FROM awaaz_private.trip_share_positions'), {
        code: '42501',
      });
      await assert.rejects(
        h.asUser(b.id, "SELECT awaaz_private.sharing_command($1,'current')", [a.id]),
        { code: '42501' },
      );
      assert.equal(await h.stores.ready(), true);
      await h.admin.query('GRANT SELECT ON awaaz_private.trip_share_positions TO awaaz_api');
      assert.equal(await h.stores.ready(), false);
      await h.admin.query('REVOKE SELECT ON awaaz_private.trip_share_positions FROM awaaz_api');
      await h.admin.query(
        "UPDATE awaaz_private.trip_shares SET created_at=clock_timestamp()-interval '10 minutes',expires_at=clock_timestamp()-interval '1 second' WHERE id=$1",
        [shareId],
      );
      assert.equal((await h.request(b.token, 'GET', `/v1/shares/${shareId}`)).statusCode, 404);
      await h.stores.sharing.cleanupExpired();
      const expired = await h.admin.query(
        'SELECT circle_id,last_captured_at FROM awaaz_private.trip_shares WHERE id=$1',
        [shareId],
      );
      assert.equal(expired.rows[0].circle_id, null);
      assert.equal(expired.rows[0].last_captured_at, null);
      await h.admin.query('DELETE FROM auth.users WHERE id=$1', [a.id]);
      assert.equal(
        (
          await h.admin.query('SELECT count(*)::int n FROM awaaz_private.trip_shares WHERE id=$1', [
            shareId,
          ])
        ).rows[0].n,
        0,
      );
    },
  );
});
