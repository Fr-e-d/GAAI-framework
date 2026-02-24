// Expert pool read chain (E06S23)
// AC8: Cache API L1 (60s TTL) → D1 → Hyperdrive fallback
// AC14: EXPERT_POOL KV removed from read path (KV binding retained for other uses)

import { createSql } from './db';
import { getCachedPool, writeCachePool, loadFromD1, upsertToD1 } from './d1ExpertPool';
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

// AC8: three-tier read chain
export async function loadExpertPool(env: Env): Promise<ExpertPoolEntry[]> {
  // 1. Cache API L1 — AC8, AC9 (60s TTL, per-datacenter)
  const fromCache = await getCachedPool();
  if (fromCache !== null && fromCache.length > 0) {
    return fromCache;
  }

  // 2. D1 edge — AC8, AC10
  if (env.EXPERT_DB) {
    try {
      const fromD1 = await loadFromD1(env.EXPERT_DB);
      if (fromD1.length > 0) {
        // AC10: write-back to Cache API on D1 hit
        await writeCachePool(fromD1);
        return fromD1;
      }
    } catch {
      // D1 failure — fall through to Hyperdrive (AC12)
    }
  }

  // 3. Hyperdrive fallback — AC11, AC12
  return loadFromHyperdrive(env);
}

// Hyperdrive path: reads from Supabase via postgres.js + Hyperdrive connection pooling
async function loadFromHyperdrive(env: Env): Promise<ExpertPoolEntry[]> {
  const sql = createSql(env);

  const expertRows = await sql<
    Pick<ExpertRow, 'id' | 'profile' | 'preferences' | 'rate_min' | 'rate_max' | 'composite_score'>[]
  >`SELECT id, profile, preferences, rate_min, rate_max, composite_score
    FROM experts WHERE availability != 'unavailable'`;

  if (expertRows.length === 0) return [];

  const expertIds = expertRows.map((e) => e.id);
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

  // AC11: write-back to Cache API and D1 on both-miss path
  await writeCachePool(pool);
  if (env.EXPERT_DB) {
    try {
      await upsertToD1(env.EXPERT_DB, pool);
    } catch {
      // D1 write failure is non-blocking
    }
  }

  return pool;
}
