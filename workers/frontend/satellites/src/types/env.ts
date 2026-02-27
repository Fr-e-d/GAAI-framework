export interface Env {
  // KV namespace for satellite config cache
  CONFIG_CACHE: KVNamespace;

  // Supabase (read-only, anon key — for satellite_configs lookup on KV miss)
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;

  // Admin secret for cache purge endpoint
  ADMIN_SECRET: string;

  // PostHog Project API Key — injected via wrangler secret put
  POSTHOG_API_KEY: string;

  // Core API base URL — injected via wrangler.toml [vars] per environment
  // Staging: https://callibrate-core-staging.frederic-geens-consulting.workers.dev
  // Production: https://api.callibrate.io
  CORE_API_URL: string;
}
