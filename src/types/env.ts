export interface Env {
  // Supabase secrets (bound via wrangler secret put)
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_KEY: string;

  // Prospect token signing secret (bound via wrangler secret put)
  PROSPECT_TOKEN_SECRET: string;

  // Cal.com secrets (bound via wrangler secret put)
  CAL_API_KEY: string;           // Platform OAuth client secret (x-cal-secret-key)
  CAL_OAUTH_CLIENT_ID: string;   // Platform OAuth client ID
  CAL_WEBHOOK_SECRET: string;    // Secret for HMAC-SHA256 webhook signature validation

  // Anthropic AI (bound via wrangler secret put)
  ANTHROPIC_API_KEY: string;
  CLOUDFLARE_AI_GATEWAY_URL: string;

  // KV namespaces
  SESSIONS: KVNamespace;
  RATE_LIMITING: KVNamespace;
  FEATURE_FLAGS: KVNamespace;

  // Queue producers
  EMAIL_NOTIFICATIONS: Queue;
  LEAD_BILLING: Queue;
}
