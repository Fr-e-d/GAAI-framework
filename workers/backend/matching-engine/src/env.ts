// ── MatchingEnv — bindings for the callibrate-matching Worker ─────────────────
// All compute-heavy resources (D1, Vectorize, Workers AI) live here.
// Core Worker connects via Service Binding (MATCHING_SERVICE) with zero network hop.

export interface MatchingEnv {
  // Hyperdrive — Supabase PostgreSQL access via postgres.js
  HYPERDRIVE: Hyperdrive;

  // D1 — expert pool edge cache (optional: graceful degradation when not provisioned)
  EXPERT_DB?: D1Database;

  // Workers AI — embedding generation
  AI: Ai;

  // Vectorize — expert profile similarity index
  VECTORIZE: VectorizeIndex;

  // Analytics Engine — matching metrics (optional — no-op if binding missing)
  MATCHING_ANALYTICS?: AnalyticsEngineDataset;

  // Supabase service key — used for admin reindex auth check
  SUPABASE_SERVICE_KEY: string;
}
