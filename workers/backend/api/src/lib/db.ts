import postgres from 'postgres';
import type { Env } from '../types/env';

// max: 1 — one connection per Worker isolate, prevents Hyperdrive pool exhaustion
// across concurrent invocations. Each handler must call ctx.waitUntil(sql.end()).
export function createSql(env: Env) {
  return postgres(env.HYPERDRIVE.connectionString, { max: 1, prepare: true });
}

export type SqlClient = ReturnType<typeof createSql>;
