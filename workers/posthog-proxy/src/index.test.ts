import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import app from './index';

describe('PostHog Proxy Worker', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  // ── Routing ────────────────────────────────────────────────────────────────

  describe('POST /ingest/*', () => {
    it('proxies to eu.i.posthog.com/ingest/*', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('{}', { status: 200 }));

      const req = new Request('https://ph.callibrate.io/ingest/batch', {
        method: 'POST',
        body: JSON.stringify({ distinct_id: 'user-1', event: 'page_view' }),
        headers: { 'Content-Type': 'application/json' },
      });

      await app.request(req);

      expect(vi.mocked(fetch)).toHaveBeenCalledOnce();
      const [proxyUrl, proxyInit] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
      expect(proxyUrl).toBe('https://eu.i.posthog.com/ingest/batch');
      expect((proxyInit.headers as Headers).get('host')).toBe('eu.i.posthog.com');
    });

    it('preserves query string', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('{}', { status: 200 }));

      const req = new Request(
        'https://ph.callibrate.io/ingest/batch?ver=1.0&compress=gzip',
        { method: 'POST', body: '{}', headers: { 'Content-Type': 'application/json' } }
      );

      await app.request(req);

      const [proxyUrl] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
      expect(proxyUrl).toBe('https://eu.i.posthog.com/ingest/batch?ver=1.0&compress=gzip');
    });

    it('preserves nested path segments', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('{}', { status: 200 }));

      const req = new Request('https://ph.callibrate.io/ingest/capture/', {
        method: 'POST',
        body: '{}',
        headers: { 'Content-Type': 'application/json' },
      });

      await app.request(req);

      const [proxyUrl] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
      expect(proxyUrl).toBe('https://eu.i.posthog.com/ingest/capture/');
    });
  });

  describe('GET /static/*', () => {
    it('proxies to eu-assets.i.posthog.com/static/*', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(
        new Response('// posthog sdk', { status: 200 })
      );

      const req = new Request('https://ph.callibrate.io/static/array.js');

      await app.request(req);

      expect(vi.mocked(fetch)).toHaveBeenCalledOnce();
      const [proxyUrl, proxyInit] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
      expect(proxyUrl).toBe('https://eu-assets.i.posthog.com/static/array.js');
      expect((proxyInit.headers as Headers).get('host')).toBe('eu-assets.i.posthog.com');
    });

    it('proxies minified SDK variant', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('// minified', { status: 200 }));

      const req = new Request('https://ph.callibrate.io/static/array.min.js');

      await app.request(req);

      const [proxyUrl] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
      expect(proxyUrl).toBe('https://eu-assets.i.posthog.com/static/array.min.js');
    });
  });

  describe('POST /decide/*', () => {
    it('proxies to eu.i.posthog.com/decide/*', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(
        new Response(JSON.stringify({ featureFlags: {} }), { status: 200 })
      );

      const req = new Request('https://ph.callibrate.io/decide/', {
        method: 'POST',
        body: JSON.stringify({ api_key: 'phc_test', distinct_id: 'user-1' }),
        headers: { 'Content-Type': 'application/json' },
      });

      await app.request(req);

      expect(vi.mocked(fetch)).toHaveBeenCalledOnce();
      const [proxyUrl, proxyInit] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
      expect(proxyUrl).toBe('https://eu.i.posthog.com/decide/');
      expect((proxyInit.headers as Headers).get('host')).toBe('eu.i.posthog.com');
    });
  });

  // ── Host header ────────────────────────────────────────────────────────────

  describe('Host header rewrite', () => {
    it('overwrites original host with PostHog ingest hostname', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('{}'));

      const req = new Request('https://ph.callibrate.io/ingest/batch', {
        method: 'POST',
        body: '{}',
        headers: { 'Content-Type': 'application/json', Host: 'ph.callibrate.io' },
      });

      await app.request(req);

      const [, proxyInit] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
      expect((proxyInit.headers as Headers).get('host')).toBe('eu.i.posthog.com');
    });

    it('overwrites original host with PostHog assets hostname for /static/*', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('// sdk'));

      const req = new Request('https://ph.callibrate.io/static/array.js', {
        headers: { Host: 'ph.callibrate.io' },
      });

      await app.request(req);

      const [, proxyInit] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
      expect((proxyInit.headers as Headers).get('host')).toBe('eu-assets.i.posthog.com');
    });
  });

  // ── Transparency ───────────────────────────────────────────────────────────

  describe('proxy transparency', () => {
    it('no PostHog API keys are added by the Worker', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('{}'));

      const req = new Request('https://ph.callibrate.io/ingest/batch', {
        method: 'POST',
        body: '{}',
        headers: { 'Content-Type': 'application/json' },
      });

      await app.request(req);

      const [, proxyInit] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
      const headers = proxyInit.headers as Headers;
      // No PostHog-specific auth headers injected by the proxy
      expect(headers.get('authorization')).toBeNull();
      expect(headers.get('x-posthog-api-key')).toBeNull();
    });

    it('returns PostHog response status unchanged', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('too many requests', { status: 429 }));

      const req = new Request('https://ph.callibrate.io/ingest/batch', {
        method: 'POST',
        body: '{}',
        headers: { 'Content-Type': 'application/json' },
      });

      const res = await app.request(req);
      expect(res.status).toBe(429);
    });
  });

  // ── CORS ───────────────────────────────────────────────────────────────────

  describe('CORS', () => {
    it('allows callibrate.io origin', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('{}'));

      const req = new Request('https://ph.callibrate.io/ingest/batch', {
        method: 'POST',
        body: '{}',
        headers: { 'Origin': 'https://callibrate.io', 'Content-Type': 'application/json' },
      });

      const res = await app.request(req);
      expect(res.headers.get('access-control-allow-origin')).toBe('https://callibrate.io');
    });

    it('allows *.callibrate.io subdomain origins', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('{}'));

      const req = new Request('https://ph.callibrate.io/ingest/batch', {
        method: 'POST',
        body: '{}',
        headers: {
          'Origin': 'https://automation-experts.callibrate.io',
          'Content-Type': 'application/json',
        },
      });

      const res = await app.request(req);
      expect(res.headers.get('access-control-allow-origin')).toBe(
        'https://automation-experts.callibrate.io'
      );
    });

    it('does not set ACAO for disallowed origins', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('{}'));

      const req = new Request('https://ph.callibrate.io/ingest/batch', {
        method: 'POST',
        body: '{}',
        headers: { 'Origin': 'https://evil.example.com', 'Content-Type': 'application/json' },
      });

      const res = await app.request(req);
      expect(res.headers.get('access-control-allow-origin')).toBeNull();
    });

    it('handles OPTIONS preflight for allowed origin', async () => {
      const req = new Request('https://ph.callibrate.io/ingest/batch', {
        method: 'OPTIONS',
        headers: {
          'Origin': 'https://some.callibrate.io',
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Request-Headers': 'Content-Type',
        },
      });

      const res = await app.request(req);
      expect(res.status).toBe(204);
      expect(res.headers.get('access-control-allow-origin')).toBe('https://some.callibrate.io');
      expect(res.headers.get('access-control-allow-methods')).toContain('POST');
      // fetch should NOT be called for OPTIONS (preflight handled by CORS middleware)
      expect(vi.mocked(fetch)).not.toHaveBeenCalled();
    });

    it('does not set ACAO when no Origin header present (server-to-server)', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(new Response('{}'));

      // No Origin header
      const req = new Request('https://ph.callibrate.io/ingest/batch', {
        method: 'POST',
        body: '{}',
        headers: { 'Content-Type': 'application/json' },
      });

      const res = await app.request(req);
      expect(res.headers.get('access-control-allow-origin')).toBeNull();
      // But proxy still works
      expect(vi.mocked(fetch)).toHaveBeenCalledOnce();
    });
  });

  // ── Edge cases ─────────────────────────────────────────────────────────────

  describe('unknown routes', () => {
    it('returns 404 for unmatched paths', async () => {
      const req = new Request('https://ph.callibrate.io/unknown/path');
      const res = await app.request(req);
      expect(res.status).toBe(404);
      // fetch should not be called for unmatched routes
      expect(vi.mocked(fetch)).not.toHaveBeenCalled();
    });
  });
});
