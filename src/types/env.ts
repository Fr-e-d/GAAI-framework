export interface Env {
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
  EXPERT_POOL: KVNamespace;

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

  // Survey delay acceleration (staging only — absent in production → real durations)
  SURVEY_DELAY_7D_MS?: string;
  SURVEY_DELAY_38D_MS?: string;

  // Email deliverability (non-secret vars in wrangler.toml)
  EMAIL_FROM_DOMAIN: string;
  EMAIL_REPLY_TO: string;

  // Analytics Engine (optional — no-op if binding missing)
  MATCHING_ANALYTICS?: AnalyticsEngineDataset;
}
