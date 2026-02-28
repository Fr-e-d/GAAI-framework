// DEC-133: RPC Service Binding interface for callibrate-core Worker (SatelliteRPC entrypoint)
export interface CoreApiRPC {
  fetch(input: RequestInfo, init?: RequestInit): Promise<Response>;
  getPublicExperts(options: {
    vertical?: string | null;
    page?: number;
    per_page?: number;
    skills?: string;
  }): Promise<{ experts: unknown[]; total: number; page: number; per_page: number }>;
  getPublicExpertBySlug(slug: string): Promise<unknown | null>;
  validateSession(token: string): Promise<{ prospect_id: string; email: string } | null>;
  validateMagicLink(prospectId: string, token: string): Promise<{ session_token: string; prospect_id: string; email: string } | null>;
}

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
  CORE_API_URL: string;

  // Cloudflare Turnstile site key — public, injected via wrangler.toml [vars] per environment
  TURNSTILE_SITE_KEY: string;

  // RPC Service Binding to Core API Worker (DEC-133: zero-network-hop, avoids Worker-to-Worker routing issues)
  // Exposes RPC methods: getPublicExperts(), getPublicExpertBySlug(), validateSession(), validateMagicLink()
  CORE_API?: CoreApiRPC;
}
