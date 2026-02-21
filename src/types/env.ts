export interface Env {
  // Supabase secrets (bound via wrangler secret put)
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_KEY: string;

  // TODO(E06S12): migrate to OPENAI_API_KEY (DEC-48)
  ANTHROPIC_API_KEY: string;
  CLOUDFLARE_AI_GATEWAY_URL: string;

  // KV namespaces
  SESSIONS: KVNamespace;
  RATE_LIMITING: KVNamespace;
  FEATURE_FLAGS: KVNamespace;
  EXPERT_POOL: KVNamespace;

  // Worker secrets (bound via wrangler secret put)
  PROSPECT_TOKEN_SECRET: string;

  // Queue producers
  EMAIL_NOTIFICATIONS: Queue;
  LEAD_BILLING: Queue;

  // Google Calendar OAuth (bound via wrangler secret put)
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  GCAL_TOKEN_ENCRYPTION_KEY: string;
  WORKER_BASE_URL: string;

  // Queue worker secrets
  RESEND_API_KEY: string;
  LEMON_SQUEEZY_API_KEY: string;
  N8N_WEBHOOK_URL: string;
}
