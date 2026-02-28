import postgres from 'postgres';
import type { Env } from '../types/env';

// max: 1 — one connection per Worker isolate, prevents Hyperdrive pool exhaustion
// across concurrent invocations. Each handler must call ctx.waitUntil(sql.end()).
// prepare: false — required for Supabase PgBouncer pooler (port 6543, transaction mode).
// PgBouncer transaction mode does not support named prepared statements.
export function createSql(env: Env) {
  return postgres(env.HYPERDRIVE.connectionString, { max: 1, prepare: false, connect_timeout: 10, idle_timeout: 5 });
}

export type SqlClient = ReturnType<typeof createSql>;
