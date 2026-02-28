import { Hono } from 'hono';
import type { Env } from './types/env';
import { renderLandingPage } from './pages/landing';
import { renderRobotsTxt } from './pages/robots';
import { renderSitemapXml } from './pages/sitemap';
import { applySecurityHeaders } from './lib/securityHeaders';
// E02S12: new page modules
import { fetchPublicExpert, renderExpertProfilePage } from './pages/expert-profile';
import { fetchInternalExpert, renderDirectBookingPage } from './pages/direct-booking';

type AppEnv = { Bindings: Env };

const app = new Hono<AppEnv>();

app.get('/health', (c) => c.json({ ok: true }, 200, { 'Cache-Control': 'no-store' }));

app.get('/robots.txt', () =>
  new Response(renderRobotsTxt(), {
    status: 200,
    headers: { 'Content-Type': 'text/plain', 'Cache-Control': 'public, max-age=86400' },
  })
);

// E02S12 AC10: sitemap now async — fetches expert slugs from API
app.get('/sitemap.xml', async (c) => {
  const xml = await renderSitemapXml(c.env.API_BASE_URL);
  return new Response(xml, {
    status: 200,
    headers: { 'Content-Type': 'application/xml', 'Cache-Control': 'public, max-age=86400' },
  });
});

app.get('/', (c) =>
  new Response(renderLandingPage(c.env.POSTHOG_API_KEY), {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300, stale-while-revalidate=3600',
    },
  })
);

// E02S12 AC2: GET /experts/:slug — expert public profile page
// X-Robots-Tag: index,follow,max-snippet:150 (AC5)
app.get('/experts/:slug', async (c) => {
  const slug = c.req.param('slug');
  const expert = await fetchPublicExpert(c.env.API_BASE_URL, slug);

  if (!expert) {
    return new Response('Expert not found', {
      status: 404,
      headers: { 'Content-Type': 'text/plain' },
    });
  }

  const html = renderExpertProfilePage(expert, c.env.POSTHOG_API_KEY);
  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'X-Robots-Tag': 'index, follow, max-snippet:150',
      'Cache-Control': 'public, max-age=300, stale-while-revalidate=3600',
    },
  });
});

// E02S12 AC7: GET /book/:slug — direct booking page
// noindex, nofollow, no-store (AC9: never cached, no crawling)
app.get('/book/:slug', async (c) => {
  const slug = c.req.param('slug');
  const token = c.req.query('t') ?? undefined;

  const expert = await fetchInternalExpert(
    c.env.API_BASE_URL,
    c.env.INTERNAL_API_KEY,
    slug,
    token,
  );

  if (!expert) {
    return new Response('Expert not found', {
      status: 404,
      headers: { 'Content-Type': 'text/plain' },
    });
  }

  const html = renderDirectBookingPage(
    expert,
    expert.attribution,
    c.env.POSTHOG_API_KEY,
    c.env.TURNSTILE_SITE_KEY,
  );

  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'X-Robots-Tag': 'noindex, nofollow',
      'Cache-Control': 'no-store',
    },
  });
});

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const response = await app.fetch(request, env, ctx);
    return applySecurityHeaders(response);
  },
};
