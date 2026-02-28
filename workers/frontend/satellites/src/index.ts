import { Hono } from 'hono';
import type { Env } from './types/env';
import type { SatelliteConfig } from './types/config';
import { resolveConfig } from './middleware/config';
import { renderLandingPage } from './pages/landing';
import { renderMatchPage } from './pages/match';
import { renderConfirmPage } from './pages/confirm';
import { renderResultsPage } from './pages/results';
import { applySecurityHeaders } from './lib/securityHeaders';
import { renderPrivacyPolicy } from './pages/privacy';
import { renderTermsOfService } from './pages/terms';
import { renderRobotsTxt } from './pages/robots';
import { renderSitemapXml } from './pages/sitemap';
import { renderExpertsDirectoryPage } from './pages/experts-directory';
import { renderExpertProfilePage } from './pages/experts-profile';

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

app.get('/sitemap.xml', async (c) => {
  const config = c.get('config');
  const sitemapXml = await renderSitemapXml(config, c.env.CORE_API_URL);
  return new Response(sitemapXml, {
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

// ── Results page (/results) — merged page 2: extraction summary + confirmation + matches + email gate ──
// E03S10 AC2: Server-side session check — reads prospect_session cookie, validates via Core API
app.get('/results', async (c) => {
  const config = c.get('config');

  // Read prospect_session cookie from incoming request
  const cookieHeader = c.req.header('Cookie') ?? '';
  const cookieToken = cookieHeader
    .split(';')
    .find((s) => s.trim().startsWith('prospect_session='))
    ?.split('=')
    .slice(1)
    .join('=')
    .trim();

  let session: { sessionToken: string; prospectId: string } | undefined;
  const responseHeaders: HeadersInit = {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
  };

  if (cookieToken) {
    // Validate session via Core API
    try {
      const sessionRes = await fetch(`${c.env.CORE_API_URL}/api/auth/session`, {
        headers: { 'Authorization': `Bearer ${cookieToken}` },
      });
      if (sessionRes.ok) {
        const sessionData = await sessionRes.json() as { prospect_id: string; email: string };
        session = { sessionToken: cookieToken, prospectId: sessionData.prospect_id };
      } else {
        // Invalid/expired cookie — clear it
        (responseHeaders as Record<string, string>)['Set-Cookie'] =
          'prospect_session=; HttpOnly; Secure; SameSite=Lax; Max-Age=0; Path=/';
      }
    } catch {
      // Network error — proceed without session (don't clear cookie)
    }
  }

  return new Response(
    renderResultsPage(config, c.env.POSTHOG_API_KEY, c.env.CORE_API_URL, c.env.TURNSTILE_SITE_KEY, session),
    { status: 200, headers: responseHeaders },
  );
});

// ── Magic link handler (/results/:prospectId) — E03S10 AC5 ───────────────────
// Validates magic link token, sets session cookie, renders results page
app.get('/results/:prospectId', async (c) => {
  const config = c.get('config');
  const prospectId = c.req.param('prospectId');
  const magicToken = c.req.query('token');

  if (!magicToken) {
    // No token: redirect to fresh start
    return new Response(null, {
      status: 302,
      headers: { Location: '/match', 'Cache-Control': 'no-store' },
    });
  }

  // Exchange magic link token for session token via Core API
  try {
    const validateRes = await fetch(`${c.env.CORE_API_URL}/api/auth/magic-link/validate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prospect_id: prospectId, token: magicToken }),
    });

    if (!validateRes.ok) {
      // Invalid/expired token — redirect to /match with message
      const redirectUrl = '/match?error=link_expired';
      return new Response(null, {
        status: 302,
        headers: { Location: redirectUrl, 'Cache-Control': 'no-store' },
      });
    }

    const { session_token } = await validateRes.json() as { session_token: string };

    const session = { sessionToken: session_token, prospectId };

    // AC5: Fire-and-forget PostHog event — best effort
    void fetch(`${c.env.CORE_API_URL}/api/auth/session`, {
      headers: { 'Authorization': `Bearer ${session_token}` },
    }).catch(() => {});

    const html = renderResultsPage(
      config, c.env.POSTHOG_API_KEY, c.env.CORE_API_URL, c.env.TURNSTILE_SITE_KEY, session,
    );

    return new Response(html, {
      status: 200,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
        // AC5: Set HttpOnly cookie on satellite domain for future return visits
        'Set-Cookie': `prospect_session=${session_token}; HttpOnly; Secure; SameSite=Lax; Max-Age=604800; Path=/`,
      },
    });
  } catch {
    // Network error — redirect to fresh start
    return new Response(null, {
      status: 302,
      headers: { Location: '/match', 'Cache-Control': 'no-store' },
    });
  }
});

// ── Expert directory (/experts) — AC1, AC2, AC3, AC6, AC7, AC8, AC9 ──────────

app.get('/experts', async (c) => {
  const config = c.get('config');
  const html = await renderExpertsDirectoryPage(config, c.env.POSTHOG_API_KEY, c.env.CORE_API_URL);
  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300, stale-while-revalidate=3600',
    },
  });
});

// ── Expert profile page (/experts/:slug) — AC4, AC7, AC8, AC11 ───────────────

app.get('/experts/:slug', async (c) => {
  const config = c.get('config');
  const slug = c.req.param('slug');
  const { html, status } = await renderExpertProfilePage(
    config,
    c.env.POSTHOG_API_KEY,
    c.env.CORE_API_URL,
    slug,
  );
  if (status === 404) {
    const notFoundHtml = `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>Expert introuvable</title><meta name="robots" content="noindex"></head><body><p>Expert introuvable. <a href="/experts">Retour au répertoire</a></p></body></html>`;
    return new Response(notFoundHtml, {
      status: 404,
      headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
    });
  }
  return new Response(html, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': status === 200 ? 'public, max-age=300, stale-while-revalidate=3600' : 'no-store',
    },
  });
});

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const response = await app.fetch(request, env, ctx);
    // Inject core API origin into CSP connect-src (covers staging *.workers.dev URLs)
    let coreOrigin: string | undefined;
    try {
      coreOrigin = new URL(env.CORE_API_URL).origin;
    } catch {
      // invalid URL — skip extra connect-src
    }
    return applySecurityHeaders(response, coreOrigin);
  },
};
