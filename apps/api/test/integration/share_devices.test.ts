import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { databaseHarness } from './harness.ts';
import { deviceCredentialHash } from '../../src/share_devices.ts';

test(
  'native share capabilities use the real restricted PostgreSQL boundary',
  { timeout: 120000 },
  async (t) => {
    const h = await databaseHarness();
    t.after(h.close);
    const create = async () => {
      const owner = await h.user('Native sharing owner'),
        recipient = await h.user('Chosen recipient');
      const circle = await h.request(owner.token, 'POST', '/v1/circles', {
        clientRequestId: randomUUID(),
        name: 'Evening commute',
      });
      assert.equal(circle.statusCode, 201, circle.body);
      const circleId = circle.json().circle.id;
      const invite = await h.request(owner.token, 'POST', `/v1/circles/${circleId}/invites`, {
        clientRequestId: randomUUID(),
        recipientId: recipient.id,
      });
      assert.equal(invite.statusCode, 201, invite.body);
      assert.equal(
        (
          await h.request(
            recipient.token,
            'POST',
            `/v1/circle-invites/${invite.json().id}/accept`,
            { token: invite.json().token },
          )
        ).statusCode,
        200,
      );
      const consent = {
        clientRequestId: randomUUID(),
        circleId,
        recipientIds: [recipient.id],
        durationSeconds: 600,
      };
      const share = await h.request(owner.token, 'POST', '/v1/shares', consent);
      assert.equal(share.statusCode, 201, share.body);
      const id = share.json().id as string;
      const secret = 'awaaz-share-v1.' + randomBytes(32).toString('base64url');
      return {
        owner,
        recipient,
        id,
        secret,
        consent,
        expiresAt: share.json().expiresAt,
        hash: deviceCredentialHash(secret),
      };
    };
    const point = () => ({
      sequence: 1,
      latitude: 23.76,
      longitude: 90.38,
      accuracyMetres: 8,
      capturedAt: new Date().toISOString(),
    });

    await t.test(
      'an exact immutable binding has only position/status/stop scope and no account-token dependency',
      async () => {
        const s = await create();
        const path = `/v1/shares/${s.id}/device`,
          native = `/v1/share-devices/${s.id}`;
        assert.equal(
          (await h.request(s.recipient.token, 'POST', path, { credentialHash: s.hash })).statusCode,
          404,
        );
        assert.equal(
          (await h.request(s.owner.token, 'POST', path, { credentialHash: 'weak' })).statusCode,
          400,
        );
        const bound = await h.request(s.owner.token, 'POST', path, { credentialHash: s.hash });
        assert.equal(bound.statusCode, 200, bound.body);
        assert.equal(bound.json().status, 'active');
        assert.equal(bound.json().expiresAt, s.expiresAt);
        assert.ok(!bound.body.includes(s.hash) && !bound.body.includes(s.secret));
        const retry = await h.request(s.owner.token, 'POST', path, { credentialHash: s.hash });
        assert.equal(retry.json().expiresAt, s.expiresAt);
        assert.equal(
          (await h.request(s.owner.token, 'POST', path, { credentialHash: 'ab'.repeat(32) })).json()
            .code,
          'device_already_bound',
        );
        assert.equal((await h.request(s.secret, 'GET', '/v1/me')).statusCode, 401);
        assert.equal((await h.request(s.owner.token, 'GET', native)).statusCode, 401);
        assert.equal(
          (await h.request('awaaz-share-v1.' + 'a'.repeat(43), 'GET', native)).statusCode,
          401,
        );
        assert.equal(
          (await h.request(s.secret, 'GET', `/v1/share-devices/${randomUUID()}`)).statusCode,
          401,
        );
        const state = await h.request(s.secret, 'GET', native);
        assert.equal(state.statusCode, 200, state.body);
        assert.deepEqual(Object.keys(state.json()).sort(), [
          'expiresAt',
          'sequence',
          'serverTime',
          'shareId',
          'status',
        ]);
        assert.equal(state.json().sequence, 0);
        // Device requests don't call online Auth; a valid scoped credential is not
        // accidentally interpreted as a Supabase token by the transport.
        const fix = point();
        assert.equal(
          (await h.request(s.secret, 'PUT', native + '/position', { ...fix, ownerId: s.owner.id }))
            .statusCode,
          400,
        );
        const uploaded = await h.request(s.secret, 'PUT', native + '/position', fix);
        assert.equal(uploaded.statusCode, 200, uploaded.body);
        const replay = await h.request(s.owner.token, 'PUT', `/v1/shares/${s.id}/position`, fix);
        assert.equal(replay.statusCode, 200, replay.body);
        assert.equal(replay.json().replayed, true);
        assert.equal(replay.json().expiresAt, uploaded.json().expiresAt);
        const competing = await h.request(s.owner.token, 'PUT', `/v1/shares/${s.id}/position`, {
          ...point(),
          sequence: 2,
        });
        assert.equal(competing.json().code, 'native_publisher_active');
        assert.equal(
          (await h.request(s.recipient.token, 'GET', `/v1/shares/${s.id}`)).json().location
            .latitude,
          fix.latitude,
        );
        const stopped = await h.request(s.secret, 'DELETE', native);
        assert.equal(stopped.json().status, 'stopped', stopped.body);
        assert.equal((await h.request(s.secret, 'DELETE', native)).json().status, 'stopped');
        assert.equal(
          (await h.request(s.recipient.token, 'GET', `/v1/shares/${s.id}`)).statusCode,
          404,
        );
        assert.equal(
          (
            await h.request(s.secret, 'PUT', native + '/position', { ...point(), sequence: 2 })
          ).json().code,
          'share_unavailable',
        );
        assert.equal(
          (await h.request(s.owner.token, 'POST', path, { credentialHash: s.hash })).json().status,
          'stopped',
        );
        const consentReplay = await h.request(s.owner.token, 'POST', '/v1/shares', s.consent);
        assert.equal(consentReplay.json().status, 'stopped');
        assert.equal(
          (
            await h.admin.query(
              'SELECT count(*)::int AS n FROM awaaz_private.trip_share_positions WHERE share_id=$1',
              [s.id],
            )
          ).rows[0].n,
          0,
        );
      },
    );

    await t.test(
      'owner revocation and a revoke-before-bind tombstone cannot be undone by delayed consent',
      async () => {
        const s = await create();
        const path = `/v1/shares/${s.id}/device`,
          native = `/v1/share-devices/${s.id}`;
        await h.request(s.owner.token, 'POST', path, { credentialHash: s.hash });
        assert.equal((await h.request(s.owner.token, 'DELETE', path)).json().status, 'revoked');
        assert.equal((await h.request(s.secret, 'GET', native)).json().status, 'revoked');
        assert.equal(
          (await h.request(s.secret, 'PUT', native + '/position', point())).json().code,
          'device_revoked',
        );
        assert.equal((await h.request(s.secret, 'DELETE', native)).json().code, 'device_revoked');
        assert.equal(
          (await h.request(s.owner.token, 'POST', path, { credentialHash: s.hash })).json().status,
          'revoked',
        );
        // Foreground owner uploads stay authorized; the revoked credential cannot
        // stop them. A revoked device is not equivalent to a stopped whole share.
        assert.equal(
          (await h.request(s.owner.token, 'PUT', `/v1/shares/${s.id}/position`, point()))
            .statusCode,
          200,
        );
        const other = await create();
        const otherPath = `/v1/shares/${other.id}/device`;
        assert.equal(
          (await h.request(other.owner.token, 'DELETE', otherPath)).json().status,
          'revoked',
        );
        assert.equal(
          (
            await h.request(other.owner.token, 'POST', otherPath, { credentialHash: other.hash })
          ).json().code,
          'device_already_bound',
        );
        // A credential is globally unique, even across accounts/consents.
        const third = await create();
        assert.equal(
          (
            await h.request(third.owner.token, 'POST', `/v1/shares/${third.id}/device`, {
              credentialHash: s.hash,
            })
          ).json().code,
          'device_already_bound',
        );
      },
    );

    await t.test(
      'membership/block, deadline and account deletion still govern a native capability',
      async () => {
        const s = await create();
        await h.request(s.owner.token, 'POST', `/v1/shares/${s.id}/device`, {
          credentialHash: s.hash,
        });
        await h.request(s.recipient.token, 'PUT', `/v1/me/blocks/${s.owner.id}`, {
          blocked: true,
          expectedVersion: 0,
        });
        assert.equal(
          (await h.request(s.secret, 'GET', `/v1/share-devices/${s.id}`)).json().status,
          'revoked',
        );
        assert.equal(
          (await h.request(s.secret, 'PUT', `/v1/share-devices/${s.id}/position`, point())).json()
            .code,
          'share_unavailable',
        );
        const old = await create();
        await h.request(old.owner.token, 'POST', `/v1/shares/${old.id}/device`, {
          credentialHash: old.hash,
        });
        await h.admin.query(
          "UPDATE awaaz_private.trip_shares SET created_at=clock_timestamp()-interval '20 minutes',expires_at=clock_timestamp()-interval '10 minutes' WHERE id=$1",
          [old.id],
        );
        assert.equal(
          (await h.request(old.secret, 'GET', `/v1/share-devices/${old.id}`)).json().status,
          'expired',
        );
        assert.equal(
          (
            await h.request(old.secret, 'PUT', `/v1/share-devices/${old.id}/position`, point())
          ).json().code,
          'share_unavailable',
        );
        assert.equal(
          (await h.request(old.secret, 'DELETE', `/v1/share-devices/${old.id}`)).json().status,
          'expired',
        );
        await h.admin.query('DELETE FROM auth.users WHERE id=$1', [old.owner.id]);
        assert.equal(
          (await h.request(old.secret, 'GET', `/v1/share-devices/${old.id}`)).statusCode,
          401,
        );
        assert.equal(
          (
            await h.admin.query(
              'SELECT count(*)::int AS n FROM awaaz_private.trip_share_devices WHERE share_id=$1',
              [old.id],
            )
          ).rows[0].n,
          0,
        );
        await assert.rejects(
          h.api.query('SELECT * FROM awaaz_private.trip_share_devices'),
          /permission denied/i,
        );
        await assert.rejects(
          h.api.query('SELECT awaaz_private.share_device_control($1)', [s.id]),
          /permission denied/i,
        );
        assert.equal((await h.app.inject('/ready')).statusCode, 200);
        await h.admin.query('GRANT SELECT ON awaaz_private.trip_share_devices TO awaaz_api');
        try {
          assert.equal((await h.app.inject('/ready')).statusCode, 503);
        } finally {
          await h.admin.query('REVOKE SELECT ON awaaz_private.trip_share_devices FROM awaaz_api');
        }
      },
    );
  },
);
