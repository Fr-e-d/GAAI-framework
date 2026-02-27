// Security headers added to every response from the Satellite worker.
// AC1: X-Content-Type-Options, X-Frame-Options, HSTS, Referrer-Policy, Permissions-Policy.
// AC3: HTML responses additionally receive Content-Security-Policy.

const BASE_SECURITY_HEADERS: Record<string, string> = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
};

// unsafe-inline required for PostHog snippet (inline script). Tighten post-MVP with nonce-based CSP.
// connect-src includes https://*.callibrate.io to allow client-side fetch() to Core API from /match.
// E03S02: Added Cloudflare Turnstile domains to script-src and frame-src for /confirm Turnstile widget.
const HTML_CSP =
  "default-src 'self'; script-src 'self' 'unsafe-inline' https://ph.callibrate.io https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; connect-src 'self' https://ph.callibrate.io https://*.callibrate.io; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'";

export function applySecurityHeaders(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(BASE_SECURITY_HEADERS)) {
    headers.set(key, value);
  }
  const ct = headers.get('Content-Type') ?? '';
  if (ct.includes('text/html')) {
    headers.set('Content-Security-Policy', HTML_CSP);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
