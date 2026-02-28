import postgres from 'postgres';
import type { MatchingEnv } from './env';

// max: 5 — per Cloudflare Workers docs (6-connection limit per isolate).
// prepare: false — required for Supabase PgBouncer pooler (port 6543, transaction mode).
export function createSql(env: MatchingEnv) {
  return postgres(env.HYPERDRIVE.connectionString, { max: 5, prepare: false, connect_timeout: 10, idle_timeout: 5, max_lifetime: 60 });
}

export type SqlClient = ReturnType<typeof createSql>;
