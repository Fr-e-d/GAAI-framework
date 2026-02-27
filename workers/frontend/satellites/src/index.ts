import { Hono } from 'hono';
import type { Env } from './types/env';
import type { SatelliteConfig } from './types/config';
import { resolveConfig } from './middleware/config';
import { renderLandingPage } from './pages/landing';
import { renderMatchPage } from './pages/match';
import { renderConfirmPage } from './pages/confirm';
import { applySecurityHeaders } from './lib/securityHeaders';
import { renderPrivacyPolicy } from './pages/privacy';
import { renderTermsOfService } from './pages/terms';
import { renderRobotsTxt } from './pages/robots';
import { renderSitemapXml } from './pages/sitemap';

type AppEnv = {
  Bindings: Env;
  Variables: { config: SatelliteConfig };
};

const app = new Hono<AppEnv>();

// ── Admin: cache purge (no config middleware) ─────────────────────────────────

app.post('/admin/cache/purge', async (c) => {
  const adminSecret = c.req.header('x-admin-secret');
  if (!adminSecret || adminSecret !== c.env.ADMIN_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  let body: { domain?: string };
  try {
    body = await c.req.json<{ domain?: string }>();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  if (!body.domain) {
    return c.json({ error: 'Missing required field: domain' }, 400);
  }

  await c.env.CONFIG_CACHE.delete(`satellite:config:${body.domain}`);
  return c.json({ purged: true, domain: body.domain });
});

// ── Legal pages (static — no satellite config required, served on any hostname) ──

app.get('/privacy', (c) => {
  return new Response(renderPrivacyPolicy(), {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=86400',
    },
  });
});

app.get('/terms', (c) => {
  return new Response(renderTermsOfService(), {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=86400',
    },
  });
});

// ── Config resolution middleware (all routes below require valid config) ──────

app.use('*', async (c, next) => {
  // Skip for admin routes (already handled above)
  if (c.req.path.startsWith('/admin/')) {
    return next();
  }

  const hostname = new URL(c.req.url).hostname;
  const config = await resolveConfig(hostname, c.env);

  if (!config) {
    return new Response(null, {
      status: 302,
      headers: {
        Location: 'https://callibrate.io',
        'Cache-Control': 'no-store',
      },
    });
  }

  c.set('config', config);
  return next();
});

// ── Health ────────────────────────────────────────────────────────────────────

app.get('/health', (c) => {
  const config = c.get('config');
  return c.json(
    { ok: true, domain: new URL(c.req.url).hostname, satellite_id: config.id },
    200,
    { 'Cache-Control': 'no-store' }
  );
});

// ── robots.txt ───────────────────────────────────────────────────────────────

app.get('/robots.txt', (c) => {
  const config = c.get('config');
  return new Response(renderRobotsTxt(config), {
    status: 200,
    headers: {
      'Content-Type': 'text/plain',
      'Cache-Control': 'public, max-age=86400',
    },
  });
});

// ── sitemap.xml ──────────────────────────────────────────────────────────────

app.get('/sitemap.xml', (c) => {
  const config = c.get('config');
  return new Response(renderSitemapXml(config), {
    status: 200,
    headers: {
      'Content-Type': 'application/xml',
      'Cache-Control': 'public, max-age=86400',
    },
  });
});

// ── Landing page ─────────────────────────────────────────────────────────────

app.get('/', (c) => {
  const config = c.get('config');
  return new Response(renderLandingPage(config, c.env.POSTHOG_API_KEY), {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300, stale-while-revalidate=3600',
    },
  });
});

// ── Match page (/match) — prospect freetext input ────────────────────────────

app.get('/match', (c) => {
  const config = c.get('config');
  return new Response(renderMatchPage(config, c.env.POSTHOG_API_KEY, c.env.CORE_API_URL), {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
});

// ── Confirm page (/confirm) — AI-extracted requirements confirmation ──────────
app.get('/confirm', (c) => {
  const config = c.get('config');
  return new Response(
    renderConfirmPage(
      config,
      c.env.POSTHOG_API_KEY,
      c.env.CORE_API_URL,
      c.env.TURNSTILE_SITE_KEY
    ),
    {
      status: 200,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    }
  );
});

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const response = await app.fetch(request, env, ctx);
    return applySecurityHeaders(response);
  },
};
