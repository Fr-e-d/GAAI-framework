export interface Env {
  // Supabase secrets (bound via wrangler secret put)
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_KEY: string;

  // Anthropic AI (bound via wrangler secret put)
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
}
