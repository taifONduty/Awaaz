import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { databaseHarness } from './harness.ts';

test('private contact blocks on real PostgreSQL', { timeout: 120000 }, async (t) => {
  const h = await databaseHarness();
  t.after(h.close);
  type User = Awaited<ReturnType<typeof h.user>>;
  const circle = async (owner: User) => {
    const response = await h.request(owner.token, 'POST', '/v1/circles', {
      clientRequestId: randomUUID(),
      name: 'Fixture circle',
    });
    assert.equal(response.statusCode, 201, response.body);
    return response.json().circle.id as string;
  };
  const invite = async (owner: User, circleId: string, recipient: User) =>
    h.request(owner.token, 'POST', `/v1/circles/${circleId}/invites`, {
      clientRequestId: randomUUID(),
      recipientId: recipient.id,
    });
  const join = async (owner: User, circleId: string, recipient: User) => {
    const response = await invite(owner, circleId, recipient);
    assert.equal(response.statusCode, 201, response.body);
    const link = response.json();
    assert.equal(
      (
        await h.request(recipient.token, 'POST', `/v1/circle-invites/${link.id}/accept`, {
          token: link.token,
        })
      ).statusCode,
      200,
    );
    return link;
  };
  const block = (actor: User, target: User, blocked: boolean, expectedVersion: number) =>
    h.request(actor.token, 'PUT', `/v1/me/blocks/${target.id}`, { blocked, expectedVersion });

  await t.test(
    'block disconnects owned/third-party circles and invalidates old tokens; unblock never restores membership',
    async () => {
      const a = await h.user('Blocker'),
        b = await h.user('Known contact'),
        d = await h.user('Third-party owner');
      const own = await circle(a),
        theirs = await circle(b),
        shared = await circle(d);
      const old = await join(a, own, b);
      await join(b, theirs, a);
      await join(d, shared, a);
      await join(d, shared, b);
      const changed = await block(a, b, true, 0);
      assert.equal(changed.statusCode, 200, changed.body);
      assert.equal(changed.json().version, 1);
      assert.equal((await h.request(b.token, 'GET', `/v1/circles/${own}`)).statusCode, 404);
      assert.equal((await h.request(a.token, 'GET', `/v1/circles/${theirs}`)).statusCode, 404);
      assert.equal((await h.request(a.token, 'GET', `/v1/circles/${shared}`)).statusCode, 404);
      assert.equal((await h.request(b.token, 'GET', `/v1/circles/${shared}`)).statusCode, 200);
      const rls = await h.asUser(a.id, 'SELECT id FROM public.circles WHERE id=$1', [shared]);
      assert.equal(rls.rows.length, 0);
      assert.equal((await invite(a, own, b)).statusCode, 404);
      assert.equal((await invite(b, theirs, a)).statusCode, 404);
      assert.equal((await invite(d, shared, a)).statusCode, 404);
      const reverse = await h.request(b.token, 'GET', `/v1/me/blocks/${a.id}`);
      assert.deepEqual(reverse.json(), {
        userId: a.id,
        blocked: false,
        version: 0,
        changedAt: null,
      });
      const unblocked = await block(a, b, false, 1);
      assert.equal(unblocked.statusCode, 200, unblocked.body);
      assert.equal(unblocked.json().version, 2);
      assert.equal((await h.request(b.token, 'GET', `/v1/circles/${own}`)).statusCode, 404);
      assert.equal(
        (
          await h.request(b.token, 'POST', `/v1/circle-invites/${old.id}/accept`, {
            token: old.token,
          })
        ).statusCode,
        410,
      );
      assert.equal((await invite(a, own, b)).statusCode, 201);
      const retained = await h.admin.query(
        'SELECT blocked,version,label_snapshot FROM awaaz_private.user_block_settings WHERE blocker_id=$1 AND target_id=$2',
        [a.id, b.id],
      );
      assert.deepEqual(retained.rows[0], { blocked: false, version: 2, label_snapshot: null });
    },
  );

  await t.test(
    'versions reject delayed decisions, block lists paginate privately and legacy RPC cannot bypass guards',
    async () => {
      const a = await h.user('State owner'),
        b = await h.user('Saved label'),
        c = await h.user('Another contact'),
        stranger = await h.user('Unrelated');
      const owned = await circle(a);
      await join(a, owned, b);
      await join(a, owned, c);
      assert.equal((await block(a, stranger, true, 0)).statusCode, 404);
      assert.equal((await block(a, b, true, 0)).json().replayed, false);
      assert.equal((await block(a, b, true, 0)).json().replayed, true);
      await h.request(b.token, 'PUT', '/v1/me', {
        displayName: 'Changed private name',
        locale: 'en',
        adultAttested: true,
      });
      const snapshot = await h.request(a.token, 'GET', '/v1/me/blocks');
      assert.ok(snapshot.body.includes('Saved label'));
      assert.equal(snapshot.body.includes('Changed private name'), false);
      assert.equal((await block(a, b, false, 1)).json().version, 2);
      assert.equal((await block(a, b, true, 0)).statusCode, 409);
      assert.equal((await block(a, b, true, 2)).json().version, 3);
      assert.equal((await block(a, b, false, 1)).statusCode, 409);
      assert.equal((await block(a, c, true, 0)).statusCode, 200);
      const first = await h.request(a.token, 'GET', '/v1/me/blocks?limit=1');
      assert.equal(first.statusCode, 200, first.body);
      assert.equal(first.json().items.length, 1);
      assert.ok(first.json().nextCursor);
      const second = await h.request(
        a.token,
        'GET',
        '/v1/me/blocks?limit=1&after=' + first.json().nextCursor,
      );
      assert.equal(second.json().items.length, 1);
      assert.equal(second.json().nextCursor, null);
      assert.notEqual(first.json().items[0].userId, second.json().items[0].userId);
      assert.deepEqual((await h.request(stranger.token, 'GET', '/v1/me/blocks')).json().items, []);
      const list = await h.request(a.token, 'GET', '/v1/me/blocks');
      assert.equal(list.body.includes('Changed private name'), false);
      assert.equal(
        list.json().items.find((entry: { userId: string }) => entry.userId === b.id).displayName,
        null,
        'reblocking a former contact must not discover their changed profile name',
      );
      await assert.rejects(h.api.query('SELECT * FROM awaaz_private.user_block_settings'), {
        code: '42501',
      });
      await assert.rejects(h.asUser(a.id, 'SELECT * FROM awaaz_private.user_block_settings'), {
        code: '42501',
      });
      await assert.rejects(
        h.api.query("SELECT awaaz_private.people_command_before_blocks($1,'list_circles','{}')", [
          a.id,
        ]),
        { code: '42501' },
      );
      await h.admin.query(
        'GRANT EXECUTE ON FUNCTION awaaz_private.people_command_before_blocks(uuid,text,jsonb) TO awaaz_api',
      );
      assert.equal(await h.stores.ready(), false);
      await h.admin.query(
        'REVOKE EXECUTE ON FUNCTION awaaz_private.people_command_before_blocks(uuid,text,jsonb) FROM awaaz_api',
      );
      assert.equal(await h.stores.ready(), true);
      await h.admin.query('DELETE FROM auth.users WHERE id=$1', [b.id]);
      assert.equal(
        (
          await h.admin.query(
            'SELECT count(*)::int AS n FROM awaaz_private.user_block_settings WHERE target_id=$1',
            [b.id],
          )
        ).rows[0].n,
        0,
      );
    },
  );

  await t.test(
    'concurrent block versus acceptance or invitation creation cannot reconnect the pair',
    async () => {
      const a = await h.user('Concurrent blocker'),
        b = await h.user('Concurrent recipient'),
        d = await h.user('Concurrent third party');
      const owned = await circle(a);
      const pending = await invite(a, owned, b),
        link = pending.json();
      assert.equal(pending.statusCode, 201);
      const race = async (lockId: string, operations: () => Promise<unknown[]>) => {
        const gate = await h.admin.connect();
        let running: Promise<unknown[]> | undefined;
        try {
          await gate.query('BEGIN');
          await gate.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [lockId]);
          running = operations();
          const deadline = Date.now() + 3000;
          let waiting = false;
          do {
            const result = await h.admin.query(
              "SELECT count(*)::int AS n FROM pg_stat_activity WHERE datname=$1 AND wait_event='advisory'",
              [h.name],
            );
            if (result.rows[0].n > 0) {
              waiting = true;
              break;
            }
            await new Promise((resolve) => setTimeout(resolve, 20));
          } while (Date.now() < deadline);
          assert.ok(waiting, 'a live database operation must be waiting on the held account lock');
        } finally {
          await gate.query('COMMIT');
          gate.release();
        }
        return await running!;
      };
      const first = await race(a.id, () =>
        Promise.all([
          block(a, b, true, 0),
          h.request(b.token, 'POST', `/v1/circle-invites/${link.id}/accept`, { token: link.token }),
        ]),
      );
      const firstStatuses = first.map(
        (response) => (response as { statusCode: number }).statusCode,
      );
      assert.equal(firstStatuses[0], 200);
      assert.ok([200, 410].includes(firstStatuses[1]!));
      assert.equal((await h.request(b.token, 'GET', `/v1/circles/${owned}`)).statusCode, 404);
      assert.equal(
        (await h.admin.query('SELECT status FROM public.circle_invites WHERE id=$1', [link.id]))
          .rows[0].status,
        'revoked',
      );
      assert.equal((await block(a, b, false, 1)).statusCode, 200);
      const shared = await circle(d);
      await join(d, shared, a);
      const second = await race(b.id, () =>
        Promise.all([block(a, b, true, 2), invite(d, shared, b)]),
      );
      const responses = second as { statusCode: number; body: string }[];
      assert.equal(responses[0]!.statusCode, 200, responses[0]!.body);
      assert.ok([201, 404].includes(responses[1]!.statusCode));
      const conflicting = await h.admin.query(
        "SELECT count(*)::int AS n FROM public.circle_invites WHERE circle_id=$1 AND recipient_id=$2 AND status='pending' AND expires_at>now()",
        [shared, b.id],
      );
      assert.equal(conflicting.rows[0].n, 0);
    },
  );
});
