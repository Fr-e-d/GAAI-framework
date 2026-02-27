// Security headers added to every response from the Landing worker.

const BASE_SECURITY_HEADERS: Record<string, string> = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
};

// unsafe-inline required for PostHog snippet (inline script). No Turnstile on landing.
const HTML_CSP =
  "default-src 'self'; script-src 'self' 'unsafe-inline' https://ph.callibrate.io; connect-src 'self' https://ph.callibrate.io; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'";

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
