// E06S38: Tests for handleGetBookings, handleGetBilling, handleGetDashboard, public endpoints

import { describe, it, expect, vi, beforeEach, type Mock } from 'vitest';
import { handleGetBookings } from './bookings';
import { handleGetBilling } from './billing';
import { handleGetDashboard } from './dashboard';
import { handleGetPublicExperts, handleGetPublicExpertBySlug } from './public';

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

// ── Fixtures ───────────────────────────────────────────────────────────────────

const mockEnv = {
  HYPERDRIVE: { connectionString: 'postgresql://test' } as unknown as Hyperdrive,
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_KEY: 'service-key',
  POSTHOG_API_KEY: 'test-ph-key',
  RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: true }) } as unknown as RateLimit,
} as unknown as Parameters<typeof handleGetBookings>[1];

const mockUser = { id: 'expert-1', email: 'expert@test.com' };

function buildSqlMock(...responses: unknown[][]) {
  const sql = vi.fn() as Mock;
  for (const resp of responses) {
    sql.mockResolvedValueOnce(resp);
  }
  sql.mockResolvedValue([]);
  return sql;
}

// ── handleGetBookings tests ────────────────────────────────────────────────────

describe('handleGetBookings', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns 403 when user is not the expert', async () => {
    const request = new Request('https://test.workers.dev/api/experts/expert-1/bookings');
    const user = { id: 'other-user', email: 'other@test.com' };
    const response = await handleGetBookings(request, mockEnv, user, 'expert-1');
    expect(response.status).toBe(403);
  });

  it('returns 422 on invalid period param', async () => {
    const request = new Request('https://test.workers.dev/api/experts/expert-1/bookings?period=invalid');
    const response = await handleGetBookings(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(422);
  });

  it('returns 200 with empty bookings for upcoming period', async () => {
    const mockSql = buildSqlMock([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/bookings?period=upcoming');
    const response = await handleGetBookings(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as { bookings: unknown[]; total: number };
    expect(body.bookings).toEqual([]);
    expect(body.total).toBe(0);
  });

  it('returns bookings with correct shape (starts_at, ends_at mapped)', async () => {
    const mockBooking = {
      id: 'booking-1',
      start_at: '2026-03-01T09:00:00Z',
      end_at: '2026-03-01T09:20:00Z',
      status: 'confirmed',
      meeting_url: 'https://meet.google.com/abc',
      cancel_reason: null,
      prospect_id: 'prospect-1',
      prospect_email: 'prospect@test.com',
      prospect_name: 'John Prospect',
      created_at: '2026-02-20T00:00:00Z',
      total_count: '1',
    };
    const mockSql = buildSqlMock([mockBooking]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/bookings');
    const response = await handleGetBookings(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as { bookings: Record<string, unknown>[] };
    const booking = body.bookings[0]!;
    expect(booking.starts_at).toBe('2026-03-01T09:00:00Z');
    expect(booking.ends_at).toBe('2026-03-01T09:20:00Z');
    expect((booking.prospect as Record<string, unknown>).name).toBe('John Prospect');
    expect(booking.cancel_reason).toBeNull();
  });

  it('returns 200 for past period', async () => {
    const mockSql = buildSqlMock([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/bookings?period=past');
    const response = await handleGetBookings(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as { bookings: unknown[] };
    expect(body.bookings).toEqual([]);
  });

  it('returns 200 for all period', async () => {
    const mockSql = buildSqlMock([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/bookings?period=all');
    const response = await handleGetBookings(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
  });
});

// ── handleGetBilling tests ─────────────────────────────────────────────────────

describe('handleGetBilling', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns 403 when user is not the expert', async () => {
    const request = new Request('https://test.workers.dev/api/experts/expert-1/billing');
    const user = { id: 'other-user', email: 'other@test.com' };
    const response = await handleGetBilling(request, mockEnv, user, 'expert-1');
    expect(response.status).toBe(403);
  });

  it('returns 404 when expert not found', async () => {
    const mockSql = buildSqlMock([]); // expert query returns empty
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/billing');
    const response = await handleGetBilling(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(404);
  });

  it('returns 200 with correct billing shape', async () => {
    const mockSql = buildSqlMock(
      // Q1: expert billing data
      [{ credit_balance: 5000, ls_subscription_status: 'active', ls_subscription_id: 'sub-123', spending_limit: 10000, max_lead_price: 500 }],
      // Q2: monthly spend
      [{ monthly_spend: '1500' }],
      // Q3: transaction count
      [{ count: '3' }],
      // Q4: transactions
      [
        { id: 'tx-1', type: 'debit', amount: 500, description: 'Lead purchase', lead_id: 'lead-1', created_at: '2026-02-01T00:00:00Z' },
        { id: 'tx-2', type: 'credit', amount: 2000, description: 'Top-up', lead_id: null, created_at: '2026-01-15T00:00:00Z' },
      ],
    );
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/billing');
    const response = await handleGetBilling(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body.credit_balance).toBe(5000);
    expect(body.monthly_spend).toBe(1500);
    expect(body.total_transactions).toBe(3);
    expect(body.ls_subscription_status).toBe('active');
    const transactions = body.transactions as Record<string, unknown>[];
    expect(transactions[0]!.amount_cents).toBe(500); // mapped from amount
    expect(transactions[0]!.type).toBe('debit');
  });

  it('returns paginated transactions', async () => {
    const mockSql = buildSqlMock(
      [{ credit_balance: 1000, ls_subscription_status: null, ls_subscription_id: null, spending_limit: null, max_lead_price: null }],
      [{ monthly_spend: '0' }],
      [{ count: '50' }],
      [], // page 2 empty
    );
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/billing?page=2&per_page=10');
    const response = await handleGetBilling(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as { page: number; per_page: number; total_transactions: number };
    expect(body.page).toBe(2);
    expect(body.per_page).toBe(10);
    expect(body.total_transactions).toBe(50);
  });
});

// ── handleGetDashboard tests ───────────────────────────────────────────────────

describe('handleGetDashboard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns 403 when user is not the expert', async () => {
    const request = new Request('https://test.workers.dev/api/experts/expert-1/dashboard');
    const user = { id: 'other-user', email: 'other@test.com' };
    const response = await handleGetDashboard(request, mockEnv, user, 'expert-1');
    expect(response.status).toBe(403);
  });

  it('returns 404 when expert not found', async () => {
    const mockSql = buildSqlMock([]); // expert query empty
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/dashboard');
    const response = await handleGetDashboard(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(404);
  });

  it('returns 200 with correct dashboard shape including monthly_history', async () => {
    const mockSql = buildSqlMock(
      // Q1: expert data
      [{ credit_balance: 5000, composite_score: 75 }],
      // Q2: unread leads
      [{ count: '3' }],
      // Q3: upcoming bookings
      [{ count: '2' }],
      // Q4: month leads
      [{ leads_received: '10', leads_confirmed: '7', leads_flagged: '1', conversions_declared: '3' }],
      // Q5: month bookings
      [{ bookings_total: '4', bookings_completed: '2' }],
      // Q6: history leads (returns 3 months)
      [
        { month: '2025-12', leads_received: '5', leads_confirmed: '3', leads_flagged: '0', conversions_declared: '1' },
        { month: '2026-01', leads_received: '8', leads_confirmed: '5', leads_flagged: '1', conversions_declared: '2' },
        { month: '2026-02', leads_received: '10', leads_confirmed: '7', leads_flagged: '1', conversions_declared: '3' },
      ],
      // Q7: history bookings
      [
        { month: '2026-02', bookings_total: '4', bookings_completed: '2' },
      ],
    );
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/expert-1/dashboard');
    const response = await handleGetDashboard(request, mockEnv, mockUser, 'expert-1');
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body.unread_leads).toBe(3);
    expect(body.upcoming_bookings).toBe(2);
    expect(body.credit_balance).toBe(5000);
    expect(body.quality_tier).toBe('top'); // compositeScore=75 → 'top'
    expect(body.composite_score).toBe(75);
    const monthStats = body.month_stats as Record<string, number>;
    expect(monthStats.leads_received).toBe(10);
    expect(monthStats.conversions_declared).toBe(3);
    const history = body.monthly_history as unknown[];
    expect(history).toHaveLength(6); // always 6 months
  });

  it('derives quality_tier correctly for different composite scores', async () => {
    const scores = [
      { score: null, expected: 'new' },
      { score: 0, expected: 'new' },
      { score: 15, expected: 'rising' },
      { score: 45, expected: 'established' },
      { score: 80, expected: 'top' },
    ];

    for (const { score, expected } of scores) {
      const mockSql = buildSqlMock(
        [{ credit_balance: 0, composite_score: score }],
        [{ count: '0' }],
        [{ count: '0' }],
        [{ leads_received: '0', leads_confirmed: '0', leads_flagged: '0', conversions_declared: '0' }],
        [{ bookings_total: '0', bookings_completed: '0' }],
        [],
        [],
      );
      (createSql as Mock).mockReturnValue(mockSql);

      const request = new Request('https://test.workers.dev/api/experts/expert-1/dashboard');
      const response = await handleGetDashboard(request, mockEnv, mockUser, 'expert-1');
      expect(response.status).toBe(200);
      const body = await response.json() as { quality_tier: string };
      expect(body.quality_tier).toBe(expected);
    }
  });
});

// ── handleGetPublicExperts tests ───────────────────────────────────────────────

describe('handleGetPublicExperts', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns 429 when rate limited', async () => {
    (mockEnv as unknown as { RATE_LIMITER: { limit: Mock } }).RATE_LIMITER.limit = vi.fn().mockResolvedValue({ success: false });

    const request = new Request('https://test.workers.dev/api/experts/public');
    const response = await handleGetPublicExperts(request, mockEnv);
    expect(response.status).toBe(429);

    // Restore
    (mockEnv as unknown as { RATE_LIMITER: { limit: Mock } }).RATE_LIMITER.limit = vi.fn().mockResolvedValue({ success: true });
  });

  it('returns 200 with anonymized expert list', async () => {
    const mockExpert = {
      id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      headline: 'n8n + AI Automation Expert',
      profile: { skills: ['n8n', 'python'], industries: ['saas'], languages: ['en'], completed_projects: 12 },
      rate_min: 80,
      rate_max: 150,
      composite_score: 75,
      availability: 'available',
      outcome_tags: ['lead_gen', 'crm_automation'],
      bio: 'Experienced automation engineer.',
      total_count: '1',
    };
    const mockSql = buildSqlMock([mockExpert]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/public');
    const response = await handleGetPublicExperts(request, mockEnv);
    expect(response.status).toBe(200);
    const body = await response.json() as { experts: Record<string, unknown>[] };
    expect(body.experts).toHaveLength(1);
    const expert = body.experts[0]!;
    // Anonymized — no display_name, email, bio
    expect(expert.slug).toMatch(/^exp-/);
    expect(expert.skills).toEqual(['n8n', 'python']);
    expect(expert.quality_tier).toBe('top');
    expect(expert.completed_projects).toBe(12);
    expect(expert).not.toHaveProperty('bio');
    expect(expert).not.toHaveProperty('email');
    expect(expert).not.toHaveProperty('display_name');
  });

  it('returns empty list when no experts found', async () => {
    const mockSql = buildSqlMock([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/public');
    const response = await handleGetPublicExperts(request, mockEnv);
    expect(response.status).toBe(200);
    const body = await response.json() as { experts: unknown[]; total: number };
    expect(body.experts).toEqual([]);
    expect(body.total).toBe(0);
  });

  it('filters by skills param in TypeScript layer', async () => {
    const mockExperts = [
      {
        id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        headline: 'Python Expert',
        profile: { skills: ['python', 'langchain'], industries: [], languages: [], completed_projects: 5 },
        rate_min: 60, rate_max: 100, composite_score: 40, availability: 'available',
        outcome_tags: [], bio: null, total_count: '2',
      },
      {
        id: 'b2c3d4e5-f6a7-8901-bcde-f12345678901',
        headline: 'n8n Specialist',
        profile: { skills: ['n8n', 'make'], industries: [], languages: [], completed_projects: 8 },
        rate_min: 70, rate_max: 120, composite_score: 55, availability: 'available',
        outcome_tags: [], bio: null, total_count: '2',
      },
    ];
    const mockSql = buildSqlMock(mockExperts);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/public?skills=python');
    const response = await handleGetPublicExperts(request, mockEnv);
    expect(response.status).toBe(200);
    const body = await response.json() as { experts: Record<string, unknown>[] };
    // Only python expert should pass the filter
    expect(body.experts).toHaveLength(1);
    expect((body.experts[0]!.skills as string[])).toContain('python');
  });
});

// ── handleGetPublicExpertBySlug tests ─────────────────────────────────────────

describe('handleGetPublicExpertBySlug', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns 429 when rate limited', async () => {
    (mockEnv as unknown as { RATE_LIMITER: { limit: Mock } }).RATE_LIMITER.limit = vi.fn().mockResolvedValue({ success: false });

    const request = new Request('https://test.workers.dev/api/experts/public/exp-a1b2c3d4');
    const response = await handleGetPublicExpertBySlug(request, mockEnv, 'exp-a1b2c3d4');
    expect(response.status).toBe(429);

    // Restore
    (mockEnv as unknown as { RATE_LIMITER: { limit: Mock } }).RATE_LIMITER.limit = vi.fn().mockResolvedValue({ success: true });
  });

  it('returns 404 for invalid slug format', async () => {
    const request = new Request('https://test.workers.dev/api/experts/public/invalid-slug');
    const response = await handleGetPublicExpertBySlug(request, mockEnv, 'invalid-slug');
    expect(response.status).toBe(404);
  });

  it('returns 404 when expert not found', async () => {
    const mockSql = buildSqlMock([]); // no result
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/public/exp-a1b2c3d4');
    const response = await handleGetPublicExpertBySlug(request, mockEnv, 'exp-a1b2c3d4');
    expect(response.status).toBe(404);
  });

  it('returns 200 with anonymized expert detail', async () => {
    const mockExpert = {
      id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      headline: 'n8n + AI Automation Expert',
      profile: { skills: ['n8n', 'python'], industries: ['saas'], languages: ['en', 'fr'], completed_projects: 12 },
      rate_min: 80,
      rate_max: 150,
      composite_score: 75,
      availability: 'available',
      outcome_tags: ['lead_gen'],
      bio: 'This is a bio that is longer than 200 characters. '.repeat(5),
    };
    const mockSql = buildSqlMock([mockExpert]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request('https://test.workers.dev/api/experts/public/exp-a1b2c3d4');
    const response = await handleGetPublicExpertBySlug(request, mockEnv, 'exp-a1b2c3d4');
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body.slug).toBe('exp-a1b2c3d4');
    expect(body.headline).toBe('n8n + AI Automation Expert');
    expect(body.quality_tier).toBe('top');
    expect(body.availability_status).toBe('available');
    expect(body.outcome_tags).toEqual(['lead_gen']);
    // bio_excerpt max 200 chars
    expect(typeof body.bio_excerpt).toBe('string');
    expect((body.bio_excerpt as string).length).toBeLessThanOrEqual(200);
    // Anonymized — no full bio, no email
    expect(body).not.toHaveProperty('bio');
    expect(body).not.toHaveProperty('email');
  });
});
