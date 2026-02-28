-- D1 schema for expert-pool-edge database (E06S23)
-- Run from workers/backend/api/:
-- Apply with: wrangler d1 execute expert-pool-edge --file=d1/expert-pool-edge.schema.sql --env staging
-- Apply with: wrangler d1 execute expert-pool-edge --file=d1/expert-pool-edge.schema.sql --env production

-- AC2: denormalized expert_pool table (read-only at query time — writes via cron sync)
CREATE TABLE IF NOT EXISTS expert_pool (
  id TEXT PRIMARY KEY,
  profile TEXT NOT NULL DEFAULT '{}',
  preferences TEXT NOT NULL DEFAULT '{}',
  rate_min INTEGER,
  rate_max INTEGER,
  composite_score REAL,
  total_leads INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- AC3: sync metadata — stores last_sync_at for incremental sync
CREATE TABLE IF NOT EXISTS _sync_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Index for incremental sync performance
CREATE INDEX IF NOT EXISTS idx_expert_pool_updated_at ON expert_pool (updated_at);

-- Pre-computed outcome_tags embeddings (E06S37 scalability fix)
-- Populated via POST /embed and POST /admin/reindex — never written at match time.
-- Allows match-time outcome alignment with 1 AI call (desired_outcomes only, max 5 strings)
-- instead of N AI calls (expert tags on-the-fly). Scales to 1000+ experts without code changes.
CREATE TABLE IF NOT EXISTS expert_outcome_embeddings (
  expert_id TEXT PRIMARY KEY,
  embeddings TEXT NOT NULL,  -- JSON: Record<tag_string, number[]> — one float32[768] per tag
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
