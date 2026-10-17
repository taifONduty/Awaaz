export function configuration(env: Record<string, string | undefined>) {
  const required = (name: string) => {
    const value = env[name]?.trim();
    if (!value) throw new Error(`Missing configuration: ${name}`);
    return value;
  };
  const supabaseUrl = required('SUPABASE_URL');
  let authUrl: URL;
  try {
    authUrl = new URL(supabaseUrl);
  } catch {
    throw new Error('Invalid SUPABASE_URL');
  }
  if (
    authUrl.protocol !== 'https:' &&
    !(
      authUrl.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(authUrl.hostname)
    )
  ) {
    throw new Error('SUPABASE_URL must use HTTPS outside localhost');
  }
  const port = Number(env.PORT ?? 3030);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
  const host = env.HOST ?? '127.0.0.1';
  if (!['127.0.0.1', 'localhost', '0.0.0.0', '::1', '::'].includes(host))
    throw new Error('Invalid HOST');
  const logLevel = env.LOG_LEVEL ?? 'info';
  if (!['trace', 'debug', 'info', 'warn', 'error', 'fatal', 'silent'].includes(logLevel))
    throw new Error('Invalid LOG_LEVEL');
  const allowedOrigins = (env.CORS_ORIGINS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)
    .map((value) => {
      let origin: URL;
      try {
        origin = new URL(value);
      } catch {
        throw new Error('Invalid CORS_ORIGINS');
      }
      if (
        !['http:', 'https:'].includes(origin.protocol) ||
        origin.username ||
        origin.password ||
        origin.pathname !== '/' ||
        origin.search ||
        origin.hash
      ) {
        throw new Error('CORS_ORIGINS must contain explicit HTTP origins');
      }
      return origin.origin;
    });
  return {
    supabaseUrl,
    publishableKey: required('SUPABASE_PUBLISHABLE_KEY'),
    databaseUrl: required('DATABASE_URL'),
    inviteSecret: required('INVITE_TOKEN_SECRET'),
    caPath: env.DATABASE_CA_CERT_PATH,
    host,
    port,
    logLevel,
    allowedOrigins,
  };
}
