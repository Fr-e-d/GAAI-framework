import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from 'vitest';
import { handleGcalAuthUrl, handleGcalStatus, handleGcalCallback, handleGcalDisconnect } from './gcal';

// ── Mock db ────────────────────────────────────────────────────────────────────

vi.mock('../../lib/db', () => ({
  createSql: vi.fn(),
}));

import { createSql } from '../../lib/db';

vi.mock('posthog-node', () => ({
  PostHog: vi.fn().mockImplementation(() => ({
    captureImmediate: vi.fn().mockResolvedValue(undefined),
  })),
}));

const mockCtx = {
  waitUntil: vi.fn(),
  passThroughOnException: vi.fn(),
} as unknown as ExecutionContext;

// ── Minimal mock Env ──────────────────────────────────────────────────────────

const mockEnv = {
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_KEY: 'service-key',
  GOOGLE_CLIENT_ID: 'test-client-id',
  GOOGLE_CLIENT_SECRET: 'test-client-secret',
  // Valid AES-256 key: 32 bytes base64-encoded
  GCAL_TOKEN_ENCRYPTION_KEY: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  WORKER_BASE_URL: 'https://callibrate-core-staging.test.workers.dev',
  ANTHROPIC_API_KEY: '',
  CLOUDFLARE_AI_GATEWAY_URL: '',
  PROSPECT_TOKEN_SECRET: '',
  SESSIONS: {} as KVNamespace,
  RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: true }) } as unknown as RateLimit,
  FEATURE_FLAGS: {} as KVNamespace,
  EXPERT_POOL: {} as KVNamespace,
  EMAIL_NOTIFICATIONS: {} as Queue,
  LEAD_BILLING: {} as Queue,
};

const mockUser = { id: 'expert-uuid-123', email: 'expert@example.com' };
const expertId = 'expert-uuid-123';

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn());
  vi.clearAllMocks();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

// ── Test 1: Auth URL generation (AC1) ──────────────────────────────────────

describe('handleGcalAuthUrl', () => {
  it('returns 200 with correct auth URL params', async () => {
    const mockSql = vi.fn() as Mock;
    // SELECT id FROM experts WHERE id = ... → expert found
    mockSql.mockResolvedValueOnce([{ id: expertId }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/auth-url`);
    const response = await handleGcalAuthUrl(request, mockEnv as any, mockUser, expertId);

    expect(response.status).toBe(200);
    const body = await response.json() as { auth_url: string };
    expect(body.auth_url).toContain('accounts.google.com/o/oauth2/v2/auth');
    expect(body.auth_url).toContain('calendar.events');
    expect(body.auth_url).toContain('calendar.readonly');
    expect(body.auth_url).toContain('access_type=offline');
    expect(body.auth_url).toContain('prompt=consent');
    expect(body.auth_url).toContain(`state=${expertId}`);
  });

  it('returns 403 when caller is not the expert', async () => {
    const differentUser = { id: 'different-user-uuid', email: 'other@example.com' };
    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/auth-url`);
    // 403 short-circuits before any DB call
    const response = await handleGcalAuthUrl(request, mockEnv as any, differentUser, expertId);
    expect(response.status).toBe(403);
  });
});

// ── Test 2: Callback token storage (AC2, AC3) ─────────────────────────────

describe('handleGcalCallback', () => {
  it('stores encrypted tokens and redirects to gcal-connected on success', async () => {
    const mockSql = vi.fn() as Mock;
    // SELECT id FROM experts WHERE id = ... → expert found
    mockSql.mockResolvedValueOnce([{ id: expertId }]);
    // UPDATE experts SET ... → success
    mockSql.mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    // Google token exchange
    vi.mocked(fetch).mockResolvedValueOnce(new Response(
      JSON.stringify({ access_token: 'at_plain', refresh_token: 'rt_plain', expires_in: 3600 }),
      { status: 200 }
    ));
    // Google userinfo
    vi.mocked(fetch).mockResolvedValueOnce(new Response(
      JSON.stringify({ email: 'expert@gmail.com' }),
      { status: 200 }
    ));

    const request = new Request(
      `https://example.com/api/gcal/callback?code=authcode&state=${expertId}`
    );
    const response = await handleGcalCallback(request, mockEnv as any, mockCtx);

    expect(response.status).toBe(302);
    expect(response.headers.get('Location')).toBe('/onboarding/gcal-connected');
  });

  it('does NOT include gcal_refresh_token in update when absent from token exchange (AC3)', async () => {
    const mockSql = vi.fn() as Mock;
    // SELECT id FROM experts
    mockSql.mockResolvedValueOnce([{ id: expertId }]);
    // UPDATE experts (capture call args to inspect)
    mockSql.mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    // Token exchange WITHOUT refresh_token
    vi.mocked(fetch).mockResolvedValueOnce(new Response(
      JSON.stringify({ access_token: 'at_plain' }), // no refresh_token
      { status: 200 }
    ));
    // userinfo
    vi.mocked(fetch).mockResolvedValueOnce(new Response(
      JSON.stringify({ email: 'expert@gmail.com' }),
      { status: 200 }
    ));

    const request = new Request(
      `https://example.com/api/gcal/callback?code=authcode&state=${expertId}`
    );
    await handleGcalCallback(request, mockEnv as any, mockCtx);

    // The UPDATE call (second sql call) should not contain 'gcal_refresh_token' as a literal
    // Since postgres.js uses tagged templates, we inspect the raw template strings array
    // The second call is the UPDATE — check it was called (the template doesn't include refresh_token column)
    expect(mockSql).toHaveBeenCalledTimes(2);

    // Inspect template strings of the UPDATE call: raw strings array is the first argument
    const updateCallArgs = mockSql.mock.calls[1]!;
    const templateStrings = updateCallArgs[0] as TemplateStringsArray;
    // Join all template string parts and verify gcal_refresh_token is absent
    const sqlText = Array.from(templateStrings).join('');
    expect(sqlText).not.toContain('gcal_refresh_token');
  });

  it('redirects to gcal-error when state is missing', async () => {
    const request = new Request('https://example.com/api/gcal/callback?code=authcode');
    const response = await handleGcalCallback(request, mockEnv as any, mockCtx);
    expect(response.status).toBe(302);
    expect(response.headers.get('Location')).toContain('/onboarding/gcal-error');
  });
});

// ── Test 3: Status endpoint (AC4) ────────────────────────────────────────────

describe('handleGcalStatus', () => {
  it('returns connected: true when gcal_refresh_token is non-null (AC4)', async () => {
    const mockSql = vi.fn() as Mock;
    mockSql.mockResolvedValueOnce([{
      gcal_refresh_token: 'encrypted-refresh-token',
      gcal_email: 'expert@gmail.com',
      gcal_connected_at: '2026-02-20T10:00:00Z',
    }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/status`);
    const response = await handleGcalStatus(request, mockEnv as any, mockUser, expertId);

    expect(response.status).toBe(200);
    const body = await response.json() as any;
    expect(body.connected).toBe(true);
    expect(body.google_email).toBe('expert@gmail.com');
    expect(body.connected_at).toBe('2026-02-20T10:00:00Z');
  });

  it('returns connected: false when gcal_refresh_token is null (AC4)', async () => {
    const mockSql = vi.fn() as Mock;
    mockSql.mockResolvedValueOnce([{
      gcal_refresh_token: null,
      gcal_email: null,
      gcal_connected_at: null,
    }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/status`);
    const response = await handleGcalStatus(request, mockEnv as any, mockUser, expertId);

    expect(response.status).toBe(200);
    const body = await response.json() as any;
    expect(body.connected).toBe(false);
    expect(body.google_email).toBeNull();
    expect(body.connected_at).toBeNull();
  });

  it('returns 403 when user.id !== expertId', async () => {
    const differentUser = { id: 'other-user', email: 'other@example.com' };
    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/status`);
    const response = await handleGcalStatus(request, mockEnv as any, differentUser, expertId);
    expect(response.status).toBe(403);
  });
});
