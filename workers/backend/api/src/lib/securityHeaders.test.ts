import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// Must be hoisted before index.ts imports to avoid 'cloudflare:workers' resolution error.
// Provides stubs for DurableObject, WorkflowEntrypoint, WorkflowStep, WorkflowEvent.
vi.mock('cloudflare:workers', () => {
  class DurableObject {
    ctx: unknown;
    env: unknown;
    constructor(ctx: unknown, env: unknown) {
      this.ctx = ctx;
      this.env = env;
    }
  }
  class WorkflowEntrypoint {
    ctx: unknown;
    env: unknown;
    constructor(ctx: unknown, env: unknown) {
      this.ctx = ctx;
      this.env = env;
    }
  }
  return { DurableObject, WorkflowEntrypoint, WorkflowStep: class {}, WorkflowEvent: class {} };
});

import { applySecurityHeaders } from './securityHeaders';
import worker from '../index';

// ── Unit tests: applySecurityHeaders ──────────────────────────────────────────

describe('applySecurityHeaders', () => {
  it('adds all required security headers', () => {
    const original = new Response('{}', {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
    const secured = applySecurityHeaders(original);

    expect(secured.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(secured.headers.get('X-Frame-Options')).toBe('DENY');
    expect(secured.headers.get('Strict-Transport-Security')).toBe(
      'max-age=31536000; includeSubDomains'
    );
    expect(secured.headers.get('Referrer-Policy')).toBe('strict-origin-when-cross-origin');
    expect(secured.headers.get('Permissions-Policy')).toBe(
      'camera=(), microphone=(), geolocation=()'
    );
  });

  it('preserves original headers', () => {
    const original = new Response('{}', {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
    const secured = applySecurityHeaders(original);
    expect(secured.headers.get('Content-Type')).toBe('application/json');
  });

  it('preserves status code', () => {
    const original = new Response('Not Found', { status: 404 });
    const secured = applySecurityHeaders(original);
    expect(secured.status).toBe(404);
  });
});

// ── Integration tests via worker.fetch ────────────────────────────────────────

const mockEnv = {
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_KEY: 'service-key',
  ANTHROPIC_API_KEY: '',
  CLOUDFLARE_AI_GATEWAY_URL: '',
  SESSIONS: {} as KVNamespace,
  RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: true }) } as unknown as RateLimit,
  FEATURE_FLAGS: {} as KVNamespace,
  PROSPECT_TOKEN_SECRET: 'secret',
  EMAIL_NOTIFICATIONS: { send: vi.fn() } as unknown as Queue,
  LEAD_BILLING: { send: vi.fn() } as unknown as Queue,
  SCORE_COMPUTATION: {} as unknown as Queue,
  GOOGLE_CLIENT_ID: 'gid',
  GOOGLE_CLIENT_SECRET: 'gsecret',
  GCAL_TOKEN_ENCRYPTION_KEY: 'dGVzdGtleXRlc3RrZXl0ZXN0a2V5dGVzdGtleXQ=',
  WORKER_BASE_URL: 'https://test.workers.dev',
  RESEND_API_KEY: '',
  LEMON_SQUEEZY_API_KEY: '',
  N8N_WEBHOOK_URL: '',
};

const mockCtx = {
  waitUntil: vi.fn(),
  passThroughOnException: vi.fn(),
} as unknown as ExecutionContext;

// AC7a: security headers present on an API response
describe('worker.fetch — security headers (AC7a)', () => {
  beforeEach(() => {
    // Mock global fetch so health check doesn't make real network calls
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response('{}', { status: 200 }))
    );
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('includes all security headers on a GET /api/health response', async () => {
    const request = new Request('https://api.callibrate.io/api/health');
    const response = await worker.fetch(request, mockEnv as never, mockCtx);

    expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(response.headers.get('X-Frame-Options')).toBe('DENY');
    expect(response.headers.get('Strict-Transport-Security')).toBe(
      'max-age=31536000; includeSubDomains'
    );
    expect(response.headers.get('Referrer-Policy')).toBe('strict-origin-when-cross-origin');
    expect(response.headers.get('Permissions-Policy')).toBe(
      'camera=(), microphone=(), geolocation=()'
    );
  });
});

// AC7c: POST without Content-Type: application/json returns 415
describe('worker.fetch — Content-Type guard (AC7c)', () => {
  it('returns 415 for POST /api/matches/compute without Content-Type: application/json', async () => {
    const request = new Request('https://api.callibrate.io/api/matches/compute', {
      method: 'POST',
      body: '{"test":true}',
      headers: { 'Content-Type': 'text/plain' },
    });
    const response = await worker.fetch(request, mockEnv as never, mockCtx);
    expect(response.status).toBe(415);
  });

  it('returns 415 for POST without any Content-Type header', async () => {
    const request = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      body: '{"test":true}',
    });
    const response = await worker.fetch(request, mockEnv as never, mockCtx);
    expect(response.status).toBe(415);
  });

  it('does NOT return 415 for webhook POST (Content-Type exception)', async () => {
    const request = new Request('https://api.callibrate.io/api/webhooks/lemonsqueezy', {
      method: 'POST',
      body: '{}',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    });
    // The webhook handler will run; it may return non-415 (e.g. 400 for missing sig)
    const response = await worker.fetch(request, mockEnv as never, mockCtx);
    expect(response.status).not.toBe(415);
  });
});
