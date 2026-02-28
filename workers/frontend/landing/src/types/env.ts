export interface Env {
  POSTHOG_API_KEY: string;

  // E02S12 AC1: Backend API base URL (set in wrangler.toml [vars] per env)
  API_BASE_URL: string;

  // E02S12 AC1: Internal API key for Worker-to-Worker calls to /api/experts/internal/:slug
  INTERNAL_API_KEY: string;

  // E02S12 AC8: Turnstile site key (public, embedded in HTML — not a secret)
  TURNSTILE_SITE_KEY: string;
}
