import { Hono } from 'hono';
import { cors } from 'hono/cors';

export interface Env {}

// PostHog EU endpoints
const POSTHOG_INGEST = 'https://eu.i.posthog.com';
const POSTHOG_ASSETS = 'https://eu-assets.i.posthog.com';

const app = new Hono<{ Bindings: Env }>();

// ── CORS: allow *.callibrate.io origins ───────────────────────────────────────
app.use(
  '*',
  cors({
    origin: (origin) => {
      if (!origin) return null;
      try {
        const { hostname } = new URL(origin);
        if (hostname === 'callibrate.io' || hostname.endsWith('.callibrate.io')) {
          return origin;
        }
      } catch {
        // ignore malformed origin
      }
      return null;
    },
    allowMethods: ['GET', 'POST', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization'],
    maxAge: 86400,
    credentials: false,
  })
);

// ── Proxy helper ──────────────────────────────────────────────────────────────
// Rewrites the Host header and forwards the request to the target PostHog host.
// The path (including query string) is preserved unchanged.
// No API keys are stored here — the proxy is transparent pass-through.
async function proxyTo(targetBase: string, request: Request): Promise<Response> {
  const requestUrl = new URL(request.url);
  const targetUrl = new URL(requestUrl.pathname + requestUrl.search, targetBase);
  const targetHostname = new URL(targetBase).hostname;

  const headers = new Headers(request.headers);
  headers.set('Host', targetHostname);

  // Buffer body to avoid ReadableStream duplex issues across fetch calls
  const body =
    request.method !== 'GET' && request.method !== 'HEAD' ? await request.arrayBuffer() : null;

  return fetch(targetUrl.toString(), {
    method: request.method,
    headers,
    body: body ?? null,
    redirect: 'follow',
  });
}

// ── Routes ────────────────────────────────────────────────────────────────────

// POST /ingest/* → eu.i.posthog.com/ingest/* (raw event ingestion)
app.post('/ingest/*', (c) => proxyTo(POSTHOG_INGEST, c.req.raw));

// GET /static/* → eu-assets.i.posthog.com/static/* (PostHog JS SDK)
app.get('/static/*', (c) => proxyTo(POSTHOG_ASSETS, c.req.raw));

// POST /decide/* → eu.i.posthog.com/decide/* (feature flags)
app.post('/decide/*', (c) => proxyTo(POSTHOG_INGEST, c.req.raw));

export default app;
