// D1 + Cache API L1 helpers for expert pool (ported from core src/lib/d1ExpertPool.ts)
// Handles: Cache API L1 (60s TTL, per-datacenter) + D1 read/write + sync_meta

import type { ExpertPoolEntry, Json } from './types';

// ── Constants ─────────────────────────────────────────────────────────────────

const CACHE_KEY_URL = 'https://cache.internal/expert-pool';
const CACHE_TTL_SECONDS = 60;
const SYNC_META_KEY = 'last_sync_at';

// ── D1 row type ───────────────────────────────────────────────────────────────

interface D1ExpertRow {
  id: string;
  profile: string;      // JSON string
  preferences: string;  // JSON string
  rate_min: number | null;
  rate_max: number | null;
  composite_score: number | null;
  total_leads: number;
}

// ── Cache API L1 ──────────────────────────────────────────────────────────────

export async function getCachedPool(): Promise<ExpertPoolEntry[] | null> {
  try {
    const cache = caches.default;
    const cached = await cache.match(new Request(CACHE_KEY_URL));
    if (!cached) return null;
    const data = await cached.json() as unknown;
    if (Array.isArray(data)) return data as ExpertPoolEntry[];
    return null;
  } catch {
    return null;
  }
}

export async function writeCachePool(pool: ExpertPoolEntry[]): Promise<void> {
  try {
    const cache = caches.default;
    const response = new Response(JSON.stringify(pool), {
      headers: { 'Cache-Control': `max-age=${CACHE_TTL_SECONDS}` },
    });
    await cache.put(new Request(CACHE_KEY_URL), response);
  } catch {
    // Cache write failure is non-blocking
  }
}

// ── D1 read ───────────────────────────────────────────────────────────────────

export async function loadFromD1(db: D1Database): Promise<ExpertPoolEntry[]> {
  const { results } = await db
    .prepare('SELECT id, profile, preferences, rate_min, rate_max, composite_score, total_leads FROM expert_pool')
    .all<D1ExpertRow>();
  return (results ?? []).map(rowToEntry);
}

// ── D1 write ─────────────────────────────────────────────────────────────────

export async function upsertToD1(db: D1Database, experts: ExpertPoolEntry[]): Promise<void> {
  if (experts.length === 0) return;
  const now = new Date().toISOString();
  const stmts = experts.map((e) =>
    db
      .prepare(
        `INSERT INTO expert_pool (id, profile, preferences, rate_min, rate_max, composite_score, total_leads, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
         ON CONFLICT (id) DO UPDATE SET
           profile = excluded.profile,
           preferences = excluded.preferences,
           rate_min = excluded.rate_min,
           rate_max = excluded.rate_max,
           composite_score = excluded.composite_score,
           total_leads = excluded.total_leads,
           updated_at = excluded.updated_at`,
      )
      .bind(
        e.id,
        JSON.stringify(e.profile ?? {}),
        JSON.stringify(e.preferences ?? {}),
        e.rate_min,
        e.rate_max,
        e.composite_score,
        e.total_leads,
        now,
      ),
  );
  await db.batch(stmts);
}

// ── Sync metadata ─────────────────────────────────────────────────────────────

export async function getLastSyncAt(db: D1Database): Promise<string | null> {
  try {
    const row = await db
      .prepare('SELECT value FROM _sync_meta WHERE key = ?1')
      .bind(SYNC_META_KEY)
      .first<{ value: string }>();
    return row?.value ?? null;
  } catch {
    return null;
  }
}

export async function setLastSyncAt(db: D1Database, ts: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO _sync_meta (key, value)
       VALUES (?1, ?2)
       ON CONFLICT (key) DO UPDATE SET value = excluded.value`,
    )
    .bind(SYNC_META_KEY, ts)
    .run();
}

// ── Outcome embeddings — separate table (E06S37 scalability fix) ──────────────

interface D1OutcomeEmbeddingRow {
  expert_id: string;
  embeddings: string; // JSON: Record<tag_string, number[]>
}

// Load pre-computed outcome tag embeddings for a set of candidate expert IDs.
// Batches in groups of 100 to respect D1 parameter limit.
export async function loadOutcomeEmbeddings(
  db: D1Database,
  expertIds: string[],
): Promise<Map<string, Record<string, number[]>>> {
  const map = new Map<string, Record<string, number[]>>();
  if (expertIds.length === 0) return map;

  const BATCH_SIZE = 100;
  for (let i = 0; i < expertIds.length; i += BATCH_SIZE) {
    const batch = expertIds.slice(i, i + BATCH_SIZE);
    const placeholders = batch.map((_, j) => `?${j + 1}`).join(',');
    const { results } = await db
      .prepare(`SELECT expert_id, embeddings FROM expert_outcome_embeddings WHERE expert_id IN (${placeholders})`)
      .bind(...batch)
      .all<D1OutcomeEmbeddingRow>();
    for (const row of results ?? []) {
      try {
        map.set(row.expert_id, JSON.parse(row.embeddings) as Record<string, number[]>);
      } catch { /* skip malformed row */ }
    }
  }
  return map;
}

// Upsert pre-computed outcome tag embeddings for one expert.
export async function upsertOutcomeEmbedding(
  db: D1Database,
  expertId: string,
  embeddings: Record<string, number[]>,
): Promise<void> {
  const now = new Date().toISOString();
  await db
    .prepare(
      `INSERT INTO expert_outcome_embeddings (expert_id, embeddings, updated_at)
       VALUES (?1, ?2, ?3)
       ON CONFLICT (expert_id) DO UPDATE SET
         embeddings = excluded.embeddings,
         updated_at = excluded.updated_at`,
    )
    .bind(expertId, JSON.stringify(embeddings), now)
    .run();
}

// ── Internal helpers ──────────────────────────────────────────────────────────

function rowToEntry(row: D1ExpertRow): ExpertPoolEntry {
  let profile: Json | null = null;
  let preferences: Json | null = null;
  try { profile = JSON.parse(row.profile) as Json; } catch { /* keep null */ }
  try { preferences = JSON.parse(row.preferences) as Json; } catch { /* keep null */ }
  return {
    id: row.id,
    profile,
    preferences,
    rate_min: row.rate_min,
    rate_max: row.rate_max,
    composite_score: row.composite_score,
    total_leads: row.total_leads,
  };
}
