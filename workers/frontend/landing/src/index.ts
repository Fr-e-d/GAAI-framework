import { Hono } from 'hono';
import type { Env } from './types/env';
import { renderLandingPage } from './pages/landing';
import { renderRobotsTxt } from './pages/robots';
import { renderSitemapXml } from './pages/sitemap';
import { applySecurityHeaders } from './lib/securityHeaders';

type AppEnv = { Bindings: Env };

const app = new Hono<AppEnv>();

app.get('/health', (c) => c.json({ ok: true }, 200, { 'Cache-Control': 'no-store' }));

app.get('/robots.txt', () =>
  new Response(renderRobotsTxt(), {
    status: 200,
    headers: { 'Content-Type': 'text/plain', 'Cache-Control': 'public, max-age=86400' },
  })
);

app.get('/sitemap.xml', () =>
  new Response(renderSitemapXml(), {
    status: 200,
    headers: { 'Content-Type': 'application/xml', 'Cache-Control': 'public, max-age=86400' },
  })
);

app.get('/', (c) =>
  new Response(renderLandingPage(c.env.POSTHOG_API_KEY), {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300, stale-while-revalidate=3600',
    },
  })
);

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const response = await app.fetch(request, env, ctx);
    return applySecurityHeaders(response);
  },
};
