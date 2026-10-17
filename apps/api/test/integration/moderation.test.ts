import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { databaseHarness } from './harness.ts';

test(
  'moderation permissions, concurrent decisions and withdrawal use real SQL',
  { timeout: 120_000 },
  async (t) => {
    const h = await databaseHarness();
    t.after(h.close);
    const owner = await h.user('Reporter'),
      moderator = await h.user('Reviewer'),
      second = await h.user('Second reviewer'),
      outsider = await h.user('Ordinary user');
    await h.admin.query('INSERT INTO awaaz_private.moderators(user_id) VALUES($1),($2)', [
      moderator.id,
      second.id,
    ]);
    const queue = '/v1/moderation/reports';
    const create = async (observedAt = new Date().toISOString(), actor = owner) => {
      const response = await h.request(actor.token, 'POST', '/v1/reports', {
        clientRequestId: randomUUID(),
        category: 'lighting',
        description: 'PRIVATE original narrative must not appear in any audit ledger.',
        latitude: 23.760123,
        longitude: 90.380456,
        observedAt,
      });
      assert.equal(response.statusCode, 201, response.body);
      return response.json().id as string;
    };
    const review = (id: string, input: object, actor = moderator) =>
      h.request(actor.token, 'POST', `${queue}/${id}/reviews`, input);
    const id = await create(),
      other = await create();
    assert.equal((await h.request(outsider.token, 'GET', queue)).statusCode, 403);
    // The fixture transport still says verified; SQL independently checks Auth.
    await h.admin.query('UPDATE auth.users SET phone_confirmed_at=null WHERE id=$1', [
      moderator.id,
    ]);
    assert.equal(
      (await h.request(moderator.token, 'GET', queue)).json().code,
      'verification_required',
    );
    await h.admin.query('UPDATE auth.users SET phone_confirmed_at=now() WHERE id=$1', [
      moderator.id,
    ]);
    assert.equal((await h.app.inject({ method: 'GET', url: queue })).statusCode, 401);
    await assert.rejects(h.asUser(moderator.id, 'SELECT * FROM awaaz_private.moderators'), {
      code: '42501',
    });
    await assert.rejects(
      h.api.query('INSERT INTO awaaz_private.moderators(user_id) VALUES($1)', [outsider.id]),
      { code: '42501' },
    );
    await assert.rejects(
      h.asAnon("SELECT awaaz_private.moderation_command(null,'list_pending','{}')"),
      { code: '42501' },
    );
    const first = await h.request(moderator.token, 'GET', queue + '?limit=1');
    assert.equal(first.statusCode, 200, first.body);
    assert.equal(first.headers['cache-control'], 'no-store');
    assert.equal(first.body.includes(owner.id), false);
    assert.equal(first.json().items.length, 1);
    const next = await h.request(
      moderator.token,
      'GET',
      queue + '?limit=1&cursor=' + first.json().nextCursor,
    );
    assert.equal(next.json().items.length, 1);
    assert.notEqual(first.json().items[0].id, next.json().items[0].id);
    assert.equal(next.json().nextCursor, null);
    assert.equal((await h.request(moderator.token, 'GET', queue + '?limit=51')).statusCode, 400);
    assert.equal(
      (await h.request(moderator.token, 'GET', queue + '?cursor=invalid')).statusCode,
      400,
    );
    const self = await create(undefined, moderator);
    assert.equal(
      (
        await review(self, {
          clientRequestId: randomUUID(),
          decision: 'approve',
          reason: 'reviewed',
        })
      ).statusCode,
      403,
    );
    assert.equal(
      (
        await review(id, {
          clientRequestId: randomUUID(),
          decision: 'approve',
          reason: 'duplicate',
        })
      ).statusCode,
      400,
    );
    const input = { clientRequestId: randomUUID(), decision: 'approve', reason: 'reviewed' };
    const created = await review(id, input);
    assert.equal(created.statusCode, 201, created.body);
    assert.equal(created.json().status, 'reviewed');
    assert.ok(Date.parse(created.json().expiresAt) > Date.now());
    const replay = await review(id, input);
    assert.equal(replay.statusCode, 200, replay.body);
    assert.equal(replay.json().replayed, true);
    assert.equal(replay.json().expiresAt, created.json().expiresAt);
    assert.equal((await review(other, input)).statusCode, 409);
    assert.equal(
      (await review(id, { ...input, reason: 'duplicate', decision: 'reject' })).statusCode,
      409,
    );
    assert.equal(
      (await h.admin.query('SELECT count(*)::integer AS count FROM public.road_events')).rows[0]
        .count,
      0,
    );
    assert.equal(
      (await h.admin.query('SELECT count(*)::integer AS count FROM public.edge_risk')).rows[0]
        .count,
      0,
    );
    const audit = await h.admin.query(
      'SELECT to_jsonb(r)::text AS value FROM awaaz_private.report_reviews r',
    );
    for (const row of audit.rows)
      for (const privateData of ['PRIVATE', 'latitude', 'longitude', '23.760123', owner.id])
        assert.equal(row.value.includes(privateData), false);
    assert.equal((await h.request(owner.token, 'DELETE', '/v1/reports/' + id)).statusCode, 200);
    const withdrawn = await review(id, input);
    assert.equal(withdrawn.statusCode, 200);
    assert.equal(withdrawn.json().status, 'withdrawn');
    assert.equal(
      (
        await h.admin.query(
          'SELECT count(*)::integer AS count FROM public.report_submissions WHERE id=$1',
          [id],
        )
      ).rows[0].count,
      0,
    );
    const race = await Promise.all([
      review(other, { clientRequestId: randomUUID(), decision: 'reject', reason: 'duplicate' }),
      review(
        other,
        { clientRequestId: randomUUID(), decision: 'approve', reason: 'reviewed' },
        second,
      ),
    ]);
    assert.deepEqual(race.map((r) => r.statusCode).sort(), [201, 409]);
    assert.equal(
      (
        await h.admin.query(
          'SELECT count(*)::integer AS count FROM awaaz_private.report_reviews WHERE report_id=$1',
          [other],
        )
      ).rows[0].count,
      1,
    );
    const stale = await create(new Date(Date.now() - 13 * 3_600_000).toISOString());
    assert.equal(
      (
        await review(stale, {
          clientRequestId: randomUUID(),
          decision: 'approve',
          reason: 'reviewed',
        })
      ).json().code,
      'stale_report',
    );
    assert.equal(
      (
        await review(stale, {
          clientRequestId: randomUUID(),
          decision: 'reject',
          reason: 'resolved',
        })
      ).statusCode,
      201,
    );
    await h.admin.query('UPDATE awaaz_private.moderators SET enabled=false WHERE user_id=$1', [
      moderator.id,
    ]);
    assert.equal((await h.request(moderator.token, 'GET', queue)).statusCode, 403);
    assert.equal((await review(id, input)).statusCode, 403);
    assert.equal(await h.stores.ready(), true);
  },
);
