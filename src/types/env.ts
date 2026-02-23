export interface Env {
  // Hyperdrive binding (AC2)
  HYPERDRIVE: Hyperdrive;

  // Supabase secrets (bound via wrangler secret put)
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_KEY: string;

  // OpenAI API (bound via wrangler secret put)
  OPENAI_API_KEY: string;

  // KV namespaces
  SESSIONS: KVNamespace;
  RATE_LIMITING: KVNamespace;
  FEATURE_FLAGS: KVNamespace;
  EXPERT_POOL: KVNamespace;

  // D1 — expert pool edge cache type retained for expertPool.ts / syncExpertPool.ts
  // Not declared in wrangler.toml for Core (moved to Matching Worker, AC7) → undefined at runtime
  EXPERT_DB?: D1Database;

  // Vectorize + Workers AI bindings
  AI: Ai;
  VECTORIZE: VectorizeIndex;

  // Service Binding — callibrate-matching Worker (AC2, E06S24)
  // Optional: falls back to local deterministic scoring when not bound (dev/test, AC6)
  MATCHING_SERVICE?: Fetcher;

  // Worker secrets (bound via wrangler secret put)
  PROSPECT_TOKEN_SECRET: string;

  // Queue producers
  EMAIL_NOTIFICATIONS: Queue;
  LEAD_BILLING: Queue;
  SCORE_COMPUTATION: Queue;

  // Google Calendar OAuth (bound via wrangler secret put)
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  GCAL_TOKEN_ENCRYPTION_KEY: string;
  WORKER_BASE_URL: string;

  // Queue worker secrets
  RESEND_API_KEY: string;
  LEMON_SQUEEZY_API_KEY: string;
  N8N_WEBHOOK_URL: string;

  // Email deliverability (non-secret vars in wrangler.toml)
  EMAIL_FROM_DOMAIN: string;
  EMAIL_REPLY_TO: string;

  // Analytics Engine (optional — no-op if binding missing)
  MATCHING_ANALYTICS?: AnalyticsEngineDataset;
}
