import { createClient } from '@supabase/supabase-js';
import type { Dependencies } from './contracts.ts';

export function supabaseVerifier(url: string, publishableKey: string): Dependencies['verifyToken'] {
  const auth = createClient(url, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: (input: RequestInfo | URL, init?: RequestInit) => {
        const timeout = AbortSignal.timeout(10_000);
        const signal = init?.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
        return fetch(input, { ...init, signal });
      },
    },
  });
  return async (token) => {
    const { data, error } = await auth.auth.getUser(token);
    if (error) {
      if ([400, 401, 403, 404].includes(error.status ?? 0)) return null;
      throw new Error('Auth unavailable');
    }
    return data.user
      ? { id: data.user.id, phoneVerified: Boolean(data.user.phone_confirmed_at) }
      : null;
  };
}
