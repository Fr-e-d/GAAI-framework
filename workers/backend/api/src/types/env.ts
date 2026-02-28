export interface Env {
  // Hyperdrive binding (AC2)
  HYPERDRIVE: Hyperdrive;

  // Supabase secrets (bound via wrangler secret put)
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_KEY: string;

  // OpenAI API (bound via wrangler secret put)
  OPENAI_API_KEY: string;

  // PostHog analytics (optional — silent no-op if absent)
  POSTHOG_API_KEY?: string;

  // KV namespaces
  SESSIONS: KVNamespace;
  RATE_LIMITER: RateLimit;
  FEATURE_FLAGS: KVNamespace;

  // D1 — expert pool edge cache (AC1, E06S23)
  // Optional: graceful degradation when not yet provisioned
  EXPERT_DB?: D1Database;

  // Vectorize + Workers AI bindings
  AI: Ai;
  VECTORIZE: VectorizeIndex;

  // Service Binding — callibrate-matching Worker (AC2, E06S24)
  // Optional: falls back to local deterministic scoring when not bound (dev/test, AC6)
  MATCHING_SERVICE?: Fetcher;

  // Durable Object — expert pool write coordinator (AC1–AC5, E06S25)
  // Optional: graceful degradation when not yet provisioned
  EXPERT_POOL_DO?: DurableObjectNamespace;

  // Worker secrets (bound via wrangler secret put)
  PROSPECT_TOKEN_SECRET: string;
  TURNSTILE_SECRET_KEY: string;
  SURVEY_TOKEN_SECRET: string;

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

  // CF Workflow bindings
  BOOKING_CONFIRMED_WORKFLOW: Workflow;
  BOOKING_COMPLETED_WORKFLOW: Workflow;

  // LemonSqueezy webhook secret (AC1, E06S33)
  LEMON_SQUEEZY_WEBHOOK_SECRET: string;

  // Flag window acceleration (staging only — absent in production → real 7d duration)
  FLAG_WINDOW_MS?: string;

  // Survey delay acceleration (staging only — absent in production → real durations)
  SURVEY_DELAY_7D_MS?: string;
  SURVEY_DELAY_38D_MS?: string;

  // Email deliverability (non-secret vars in wrangler.toml)
  EMAIL_FROM_DOMAIN: string;
  EMAIL_REPLY_TO: string;

  // Admin API key — dedicated secret for admin endpoints (E08S04, SEC-06)
  ADMIN_API_KEY: string;

  // Analytics Engine (optional — no-op if binding missing)
  MATCHING_ANALYTICS?: AnalyticsEngineDataset;
}
