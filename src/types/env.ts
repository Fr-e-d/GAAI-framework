export interface Env {
  // Supabase secrets (bound via wrangler secret put)
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_KEY: string;

  // KV namespaces
  SESSIONS: KVNamespace;
  RATE_LIMITING: KVNamespace;
  FEATURE_FLAGS: KVNamespace;

  // Queue producers
  EMAIL_NOTIFICATIONS: Queue;
  LEAD_BILLING: Queue;
}
