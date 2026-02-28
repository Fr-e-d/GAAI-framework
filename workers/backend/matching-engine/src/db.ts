import postgres from 'postgres';
import type { MatchingEnv } from './env';

// max: 1 — one connection per Worker isolate, prevents Hyperdrive pool exhaustion.
// prepare: false — required for Supabase PgBouncer pooler (port 6543, transaction mode).
export function createSql(env: MatchingEnv) {
  return postgres(env.HYPERDRIVE.connectionString, { max: 1, prepare: false });
}

export type SqlClient = ReturnType<typeof createSql>;
