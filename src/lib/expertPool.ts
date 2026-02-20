// ── Expert pool KV cache ───────────────────────────────────────────────────────
// Loads the active expert pool from EXPERT_POOL KVNamespace (AC3, DEC-40).
// Cache-aside pattern: KV hit → return directly; miss → load from DB + write KV.
// TTL: 300s (5 minutes) — new experts appear within 5 minutes of registration.

import { createClient } from '@supabase/supabase-js';
import type { Json, Database } from '../types/database';
import type { Env } from '../types/env';

export interface ExpertPoolEntry {
  id: string;
  profile: Json | null;
  preferences: Json | null;
  rate_min: number | null;
  rate_max: number | null;
  composite_score: number | null;
  total_leads: number; // TODO(E06S09): populate from leads table count
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
  const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });

  const { data: experts, error } = await supabase
    .from('experts')
    .select('id, profile, preferences, rate_min, rate_max, composite_score')
    .neq('availability', 'unavailable');

  if (error || !experts) {
    return [];
  }

  const pool: ExpertPoolEntry[] = experts.map((e) => ({
    id: e.id,
    profile: e.profile,
    preferences: e.preferences,
    rate_min: e.rate_min,
    rate_max: e.rate_max,
    composite_score: e.composite_score,
    total_leads: 0, // TODO(E06S09): populate from leads table count
  }));

  // 3. Write back to KV (non-blocking on failure)
  try {
    await env.EXPERT_POOL.put(KV_KEY, JSON.stringify(pool), { expirationTtl: KV_TTL_SECONDS });
  } catch {
    // KV write failure — pool still usable for this request
  }

  return pool;
}
