// Security headers added to every response from the Landing worker.

const BASE_SECURITY_HEADERS: Record<string, string> = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
};

// E02S12 AC3/AC8: CSP updated for expert profile + direct booking pages.
// Added:
//   script-src: challenges.cloudflare.com (Turnstile)
//   connect-src: api.callibrate.io (direct booking form POST)
//   frame-src: challenges.cloudflare.com (Turnstile iframe)
// unsafe-inline required for PostHog snippet + inline page scripts.
const HTML_CSP =
  "default-src 'self'; " +
  "script-src 'self' 'unsafe-inline' https://ph.callibrate.io https://challenges.cloudflare.com; " +
  "connect-src 'self' https://ph.callibrate.io https://api.callibrate.io; " +
  "img-src 'self' data: https:; " +
  "style-src 'self' 'unsafe-inline'; " +
  "frame-src https://challenges.cloudflare.com";

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
