import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { supabaseVerifier } from '../src/auth.ts';

test('Auth verifier asks Supabase for the user rather than accepting decoded client claims', async (t) => {
  const id = randomUUID();
  const calls: { url: string; authorization: string | null }[] = [];
  t.mock.method(globalThis, 'fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({
      url: String(input),
      authorization: new Headers(init?.headers).get('authorization'),
    });
    return new Response(
      JSON.stringify({
        id,
        email_confirmed_at: new Date().toISOString(),
        phone_confirmed_at: new Date().toISOString(),
      }),
      { status: 200, headers: { 'content-type': 'application/json' } },
    );
  });
  const verify = supabaseVerifier('https://fresh.example.test', 'test-publishable-key');
  assert.deepEqual(await verify('test-access-token'), { id, phoneVerified: true });
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.url, 'https://fresh.example.test/auth/v1/user');
  assert.equal(calls[0]?.authorization, 'Bearer test-access-token');
});

test('email confirmation is not treated as phone confirmation, and invalid tokens are rejected', async (t) => {
  const id = randomUUID();
  let status = 200;
  t.mock.method(
    globalThis,
    'fetch',
    async () =>
      new Response(
        JSON.stringify(
          status === 200
            ? { id, email_confirmed_at: new Date().toISOString(), phone_confirmed_at: null }
            : { error_code: 'bad_jwt', msg: 'Invalid JWT' },
        ),
        { status, headers: { 'content-type': 'application/json' } },
      ),
  );
  const verify = supabaseVerifier('https://fresh.example.test', 'test-publishable-key');
  assert.deepEqual(await verify('test-token'), { id, phoneVerified: false });
  status = 401;
  assert.equal(await verify('invalid-token'), null);
});
