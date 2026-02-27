// E06S38: Tests for handleGetLeads and handleEvaluateLead

import { describe, it, expect, vi, beforeEach, type Mock } from 'vitest';
import { handleGetLeads, handleEvaluateLead } from './leads';

// ── Mock db ────────────────────────────────────────────────────────────────────

vi.mock('../../lib/db', () => ({
  createSql: vi.fn(),
}));

import { createSql } from '../../lib/db';

vi.mock('posthog-node', () => {
  const PostHog = vi.fn().mockImplementation(() => ({
    captureImmediate: vi.fn().mockResolvedValue(undefined),
  }));
  return { PostHog };
});

// ── Fixtures ───────────────────────────────────────────────────────────────────

const mockEnv = {
  HYPERDRIVE: { connectionString: 'postgresql://test' } as unknown as Hyperdrive,
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_KEY: 'service-key',
  // POSTHOG_API_KEY deliberately omitted so captureEvent returns early (no-op) — avoids constructor mock issues
  RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: true }) } as unknown as RateLimit,
} as unknown as Parameters<typeof handleGetLeads>[1];

const mockCtx = {
  waitUntil: vi.fn(),
  passThroughOnException: vi.fn(),
} as unknown as ExecutionContext;

const mockUser = { id: 'expert-1', email: 'expert@test.com' };

function buildSqlMock(...responses: unknown[][]) {
  const sql = vi.fn() as Mock;
  for (const resp of responses) {
    sql.mockResolvedValueOnce(resp);
  }
  sql.mockResolvedValue([]);
  return sql;
}

// ── handleGetLeads tests ───────────────────────────────────────────────────────

describe('handleGetLeads', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns 403 when user is not the expert', async () => {
    const request = new Request('https://test.workers.dev/api/experts/other-expert/leads');
    const user = { id: 'different-user', email: 'other@test.com' };
    const response = await handleGetLeads(request, mockEnv, user, 'other-expert');
    expect(response.status).toBe(403);
    const body = await response.json() as Record<string, string>;
    expect(body.error).toBe('Forbidden');
  });

  it('returns 403 when expertId does not match user.id', async () => {
    const request = new Request('https://test.workers.dev/api/experts/expert-1/leads');
    const user = { id: 'expert-2', email: 'other@test.com' };
    const response = await handleGetLeads(request, mockEnv, user, 'expert-1');
    expect(response.status).toBe(403);
  });

  it('returns 422 on invalid status param', async () => {
    const request = new Request('https://test.workers.dev/api/experts/expert-1/leads?status=invalid');
    const response = await handleGetLeads(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body.error).toBe('Validation failed');
  });

  it('returns 200 with empty leads when no results', async () => {
    const mockSql = buildSqlMock(
      [{ count: '0' }], // count query
      [],               // leads query
    );
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/leads');
    const response = await handleGetLeads(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body.leads).toEqual([]);
    expect(body.total).toBe(0);
    expect(body.page).toBe(1);
    expect(body.per_page).toBe(20);
  });

  it('returns paginated leads with correct shape', async () => {
    const mockLead = {
      id: 'lead-1',
      status: 'confirmed',
      price_cents: 8900,
      created_at: '2026-02-01T10:00:00Z',
      confirmed_at: '2026-02-02T10:00:00Z',
      flagged_at: null,
      flag_reason: null,
      flag_window_expires_at: '2026-02-08T10:00:00Z',
      evaluation_score: null,
      evaluation_notes: null,
      conversion_declared: false,
      evaluated_at: null,
      prospect_id: 'prospect-1',
      prospect_email: 'prospect@test.com',
      prospect_requirements: { budget_range: { max: 5000 } },
      match_score: 0.85,
      booking_id: 'booking-1',
      booking_starts_at: '2026-02-10T09:00:00Z',
      booking_status: 'confirmed',
    };
    const mockSql = buildSqlMock(
      [{ count: '1' }],
      [mockLead],
    );
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/leads');
    const response = await handleGetLeads(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as {
      leads: unknown[];
      total: number;
      page: number;
      per_page: number;
    };
    expect(body.total).toBe(1);
    expect(body.leads).toHaveLength(1);
    const lead = body.leads[0] as Record<string, unknown>;
    expect(lead.id).toBe('lead-1');
    expect(lead.price_cents).toBe(8900);
    expect((lead.prospect as Record<string, unknown>).id).toBe('prospect-1');
    expect((lead.booking as Record<string, unknown>).id).toBe('booking-1');
  });

  it('filters by status=confirmed', async () => {
    const mockSql = buildSqlMock(
      [{ count: '2' }],
      [{ id: 'lead-2', status: 'confirmed', price_cents: 5000, created_at: '2026-02-01T00:00:00Z', confirmed_at: null, flagged_at: null, flag_reason: null, flag_window_expires_at: null, evaluation_score: null, evaluation_notes: null, conversion_declared: false, evaluated_at: null, prospect_id: null, prospect_email: null, prospect_requirements: null, match_score: null, booking_id: null, booking_starts_at: null, booking_status: null }],
    );
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/leads?status=confirmed');
    const response = await handleGetLeads(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as { leads: unknown[] };
    expect(body.leads).toHaveLength(1);
  });

  it('respects pagination params (page + per_page)', async () => {
    const mockSql = buildSqlMock(
      [{ count: '100' }],
      [],
    );
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/leads?page=3&per_page=10');
    const response = await handleGetLeads(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as { page: number; per_page: number };
    expect(body.page).toBe(3);
    expect(body.per_page).toBe(10);
  });

  it('clamps per_page to max 50', async () => {
    const mockSql = buildSqlMock([{ count: '0' }], []);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/leads?per_page=200');
    const response = await handleGetLeads(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as { per_page: number };
    expect(body.per_page).toBe(50);
  });
});

// ── handleEvaluateLead tests ──────────────────────────────────────────────────

describe('handleEvaluateLead', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns 404 when lead not found', async () => {
    const mockSql = buildSqlMock([]); // no lead returned
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/leads/lead-404/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ score: 8 }),
    });
    const response = await handleEvaluateLead(request, mockEnv, mockUser, 'lead-404', mockCtx);
    expect(response.status).toBe(404);
  });

  it('returns 403 when lead belongs to different expert', async () => {
    const mockSql = buildSqlMock([
      { id: 'lead-1', expert_id: 'other-expert', status: 'confirmed', evaluation_score: null },
    ]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/leads/lead-1/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ score: 8 }),
    });
    const response = await handleEvaluateLead(request, mockEnv, mockUser, 'lead-1', mockCtx);
    expect(response.status).toBe(403);
    const body = await response.json() as Record<string, string>;
    expect(body.error).toBe('Forbidden');
  });

  it('returns 400 when lead status is not confirmed', async () => {
    const mockSql = buildSqlMock([
      { id: 'lead-1', expert_id: 'expert-1', status: 'new', evaluation_score: null },
    ]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/leads/lead-1/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ score: 8 }),
    });
    const response = await handleEvaluateLead(request, mockEnv, mockUser, 'lead-1', mockCtx);
    expect(response.status).toBe(400);
  });

  it('returns 409 when lead already evaluated', async () => {
    const mockSql = buildSqlMock([
      { id: 'lead-1', expert_id: 'expert-1', status: 'confirmed', evaluation_score: 7 },
    ]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/leads/lead-1/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ score: 8 }),
    });
    const response = await handleEvaluateLead(request, mockEnv, mockUser, 'lead-1', mockCtx);
    expect(response.status).toBe(409);
    const body = await response.json() as Record<string, string>;
    expect(body.error).toBe('Lead already evaluated');
  });

  it('returns 422 on invalid score (out of range)', async () => {
    const mockSql = buildSqlMock([
      { id: 'lead-1', expert_id: 'expert-1', status: 'confirmed', evaluation_score: null },
    ]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/leads/lead-1/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ score: 15 }), // max is 10
    });
    const response = await handleEvaluateLead(request, mockEnv, mockUser, 'lead-1', mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body.error).toBe('Validation failed');
  });

  it('returns 422 on missing score field', async () => {
    const mockSql = buildSqlMock([
      { id: 'lead-1', expert_id: 'expert-1', status: 'confirmed', evaluation_score: null },
    ]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/leads/lead-1/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ notes: 'Good lead' }), // missing score
    });
    const response = await handleEvaluateLead(request, mockEnv, mockUser, 'lead-1', mockCtx);
    expect(response.status).toBe(422);
  });

  it('returns 200 with updated lead on success', async () => {
    const updatedLead = {
      id: 'lead-1',
      status: 'confirmed',
      evaluation_score: 8,
      evaluation_notes: 'Good quality lead',
      conversion_declared: true,
      evaluated_at: '2026-02-27T10:00:00Z',
    };
    const mockSql = buildSqlMock(
      [{ id: 'lead-1', expert_id: 'expert-1', status: 'confirmed', evaluation_score: null }],
      [updatedLead],
    );
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/leads/lead-1/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ score: 8, notes: 'Good quality lead', conversion_declared: true }),
    });
    const response = await handleEvaluateLead(request, mockEnv, mockUser, 'lead-1', mockCtx);
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body.evaluation_score).toBe(8);
    expect(body.conversion_declared).toBe(true);
  });
});
