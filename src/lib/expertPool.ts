// ── Expert pool KV cache ───────────────────────────────────────────────────────
// Loads the active expert pool from EXPERT_POOL KVNamespace (AC3, DEC-40).
// Cache-aside pattern: KV hit → return directly; miss → load from DB + write KV.
// TTL: 300s (5 minutes) — new experts appear within 5 minutes of registration.

import { createSql } from './db';
import type { Json } from '../types/database';
import type { Env } from '../types/env';
import type { ExpertRow } from '../types/db';

export interface ExpertPoolEntry {
  id: string;
  profile: Json | null;
  preferences: Json | null;
  rate_min: number | null;
  rate_max: number | null;
  composite_score: number | null;
  total_leads: number;
}

const KV_KEY = 'expert_pool';
const KV_TTL_SECONDS = 300;

export async function loadExpertPool(env: Env): Promise<ExpertPoolEntry[]> {
  // 1. Try KV cache
  let cached: ExpertPoolEntry[] | null = null;
  try {
    cached = await env.EXPERT_POOL.get<ExpertPoolEntry[]>(KV_KEY, { type: 'json' });
  } catch {
    // KV read failure — proceed to DB fallback
  }

  if (cached !== null && Array.isArray(cached)) {
    return cached;
  }

  // 2. Cache miss — load from DB
  const sql = createSql(env);

  const expertRows = await sql<Pick<ExpertRow, 'id' | 'profile' | 'preferences' | 'rate_min' | 'rate_max' | 'composite_score'>[]>`
    SELECT id, profile, preferences, rate_min, rate_max, composite_score
    FROM experts WHERE availability != 'unavailable'`;

  if (expertRows.length === 0) return [];

  const expertIds = expertRows.map(e => e.id);
  const leadRows = await sql<{ expert_id: string }[]>`
    SELECT expert_id FROM leads WHERE expert_id = ANY(${expertIds})`;

  const leadCountMap = new Map<string, number>();
  for (const row of leadRows) {
    if (row.expert_id) {
      leadCountMap.set(row.expert_id, (leadCountMap.get(row.expert_id) ?? 0) + 1);
    }
  }

  const pool: ExpertPoolEntry[] = expertRows.map((e) => ({
    id: e.id,
    profile: e.profile,
    preferences: e.preferences,
    rate_min: e.rate_min,
    rate_max: e.rate_max,
    composite_score: e.composite_score,
    total_leads: leadCountMap.get(e.id) ?? 0,
  }));

  // 3. Write back to KV (non-blocking on failure)
  try {
    await env.EXPERT_POOL.put(KV_KEY, JSON.stringify(pool), { expirationTtl: KV_TTL_SECONDS });
  } catch {
    // KV write failure — pool still usable for this request
  }

  return pool;
}
