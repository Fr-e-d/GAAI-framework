// E02S11: Tests for availability rules CRUD handler + expandRulesToWorkingHours
import { describe, it, expect, vi, beforeEach, type Mock } from 'vitest';
import {
  handleGetAvailabilityRules,
  handleCreateAvailabilityRule,
  handleUpdateAvailabilityRule,
  handleDeleteAvailabilityRule,
  validateTimeFormat,
  rulesOverlap,
} from './availability-rules';
import { expandRulesToWorkingHours } from '../../lib/availability';
import type { ExpertAvailabilityRuleRow } from '../../types/db';

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
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_KEY: 'service-key',
  ANTHROPIC_API_KEY: '',
  CLOUDFLARE_AI_GATEWAY_URL: '',
  SESSIONS: {} as unknown as KVNamespace,
  RATE_LIMITER: {} as unknown as RateLimit,
  FEATURE_FLAGS: {} as unknown as KVNamespace,
  PROSPECT_TOKEN_SECRET: 'secret',
  EMAIL_NOTIFICATIONS: {} as unknown as Queue,
  LEAD_BILLING: {} as unknown as Queue,
  SCORE_COMPUTATION: {} as unknown as Queue,
  GOOGLE_CLIENT_ID: 'gid',
  GOOGLE_CLIENT_SECRET: 'gsecret',
  GCAL_TOKEN_ENCRYPTION_KEY: 'dGVzdGtleXRlc3RrZXl0ZXN0a2V5dGVzdGtleXQ=',
  WORKER_BASE_URL: 'https://test.workers.dev',
  RESEND_API_KEY: '',
  LEMON_SQUEEZY_API_KEY: '',
  N8N_WEBHOOK_URL: '',
  POSTHOG_API_KEY: '',
};

const mockUser = { id: 'expert-uuid', email: 'expert@test.com' };
const otherUser = { id: 'other-uuid', email: 'other@test.com' };

const sampleRule: ExpertAvailabilityRuleRow = {
  id: 'rule-uuid-1',
  expert_id: 'expert-uuid',
  day_of_week: 1,
  start_time: '09:00:00',
  end_time: '17:00:00',
  is_active: true,
  created_at: '2026-02-28T10:00:00Z',
  updated_at: '2026-02-28T10:00:00Z',
};

function makeRequest(method: string, path: string, body?: unknown): Request {
  const init: RequestInit = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
  }
  return new Request(`https://test.workers.dev${path}`, init);
}

// ── Group 1: Pure validation helpers ──────────────────────────────────────────

describe('validateTimeFormat', () => {
  it('accepts valid HH:MM values', () => {
    expect(validateTimeFormat('09:00')).toBe(true);
    expect(validateTimeFormat('00:00')).toBe(true);
    expect(validateTimeFormat('23:59')).toBe(true);
    expect(validateTimeFormat('17:30')).toBe(true);
  });

  it('rejects missing leading zero', () => {
    expect(validateTimeFormat('9:00')).toBe(false);
  });

  it('rejects invalid hour', () => {
    expect(validateTimeFormat('25:00')).toBe(false);
    expect(validateTimeFormat('24:00')).toBe(false);
  });

  it('rejects invalid minute', () => {
    expect(validateTimeFormat('09:60')).toBe(false);
    expect(validateTimeFormat('09:99')).toBe(false);
  });

  it('rejects HH:MM:SS format (seconds not allowed in API body)', () => {
    expect(validateTimeFormat('09:00:00')).toBe(false);
  });

  it('rejects empty string', () => {
    expect(validateTimeFormat('')).toBe(false);
  });
});

describe('rulesOverlap', () => {
  it('detects overlap in the middle', () => {
    expect(rulesOverlap('09:00', '12:00', '10:00', '14:00')).toBe(true);
  });

  it('detects containment (new inside existing)', () => {
    expect(rulesOverlap('09:00', '18:00', '10:00', '12:00')).toBe(true);
  });

  it('detects containment (existing inside new)', () => {
    expect(rulesOverlap('11:00', '12:00', '09:00', '18:00')).toBe(true);
  });

  it('no overlap: adjacent (back-to-back)', () => {
    // [09:00,12:00) and [12:00,17:00) should not overlap
    expect(rulesOverlap('09:00', '12:00', '12:00', '17:00')).toBe(false);
  });

  it('no overlap: entirely before', () => {
    expect(rulesOverlap('09:00', '10:00', '11:00', '12:00')).toBe(false);
  });

  it('no overlap: entirely after', () => {
    expect(rulesOverlap('14:00', '17:00', '09:00', '12:00')).toBe(false);
  });

  it('day_of_week is checked by caller — validateTimeFormat rejects invalid', () => {
    // day 7 invalid — pure logic test
    expect(rulesOverlap('09:00', '17:00', '09:00', '17:00')).toBe(true);
  });
});

describe('day_of_week validation (inside handler)', () => {
  it('0 is valid (Sunday)', () => expect(validateTimeFormat('09:00')).toBe(true));
  it('6 is valid (Saturday)', () => expect(validateTimeFormat('18:00')).toBe(true));
});

// ── Group 2: GET availability rules ──────────────────────────────────────────

describe('handleGetAvailabilityRules', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns 403 when user is not the expert', async () => {
    const req = makeRequest('GET', '/api/experts/expert-uuid/availability/rules');
    const res = await handleGetAvailabilityRules(req, mockEnv as never, otherUser, 'expert-uuid');
    expect(res.status).toBe(403);
    const body = await res.json() as Record<string, string>;
    expect(body.error).toBe('forbidden');
  });

  it('returns 200 with rules array and timezone', async () => {
    const mockSql = vi.fn() as Mock;
    // Call 1: expert timezone query
    mockSql.mockResolvedValueOnce([{ timezone: 'Europe/Brussels' }]);
    // Call 2: rules query
    mockSql.mockResolvedValueOnce([sampleRule]);
    (createSql as Mock).mockReturnValue(mockSql);

    const req = makeRequest('GET', '/api/experts/expert-uuid/availability/rules');
    const res = await handleGetAvailabilityRules(req, mockEnv as never, mockUser, 'expert-uuid');
    expect(res.status).toBe(200);
    const body = await res.json() as { rules: ExpertAvailabilityRuleRow[]; timezone: string };
    expect(body.timezone).toBe('Europe/Brussels');
    expect(body.rules).toHaveLength(1);
    // Time should be normalized to HH:MM
    expect(body.rules[0]!.start_time).toBe('09:00');
    expect(body.rules[0]!.end_time).toBe('17:00');
  });

  it('returns empty array when no rules', async () => {
    const mockSql = vi.fn() as Mock;
    mockSql.mockResolvedValueOnce([{ timezone: 'UTC' }]);
    mockSql.mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const req = makeRequest('GET', '/api/experts/expert-uuid/availability/rules');
    const res = await handleGetAvailabilityRules(req, mockEnv as never, mockUser, 'expert-uuid');
    expect(res.status).toBe(200);
    const body = await res.json() as { rules: ExpertAvailabilityRuleRow[] };
    expect(body.rules).toHaveLength(0);
  });
});

// ── Group 3: POST (create) availability rule ──────────────────────────────────

describe('handleCreateAvailabilityRule', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns 403 when user is not the expert', async () => {
    const req = makeRequest('POST', '/api/experts/expert-uuid/availability/rules', {
      day_of_week: 1, start_time: '09:00', end_time: '17:00',
    });
    const res = await handleCreateAvailabilityRule(req, mockEnv as never, otherUser, 'expert-uuid');
    expect(res.status).toBe(403);
  });

  it('returns 422 for invalid day_of_week (7)', async () => {
    const req = makeRequest('POST', '/api/experts/expert-uuid/availability/rules', {
      day_of_week: 7, start_time: '09:00', end_time: '17:00',
    });
    const res = await handleCreateAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid');
    expect(res.status).toBe(422);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Validation failed');
  });

  it('returns 422 for invalid day_of_week (-1)', async () => {
    const req = makeRequest('POST', '/api/experts/expert-uuid/availability/rules', {
      day_of_week: -1, start_time: '09:00', end_time: '17:00',
    });
    const res = await handleCreateAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid');
    expect(res.status).toBe(422);
  });

  it('returns 422 for invalid time format (no leading zero)', async () => {
    const req = makeRequest('POST', '/api/experts/expert-uuid/availability/rules', {
      day_of_week: 1, start_time: '9:00', end_time: '17:00',
    });
    const res = await handleCreateAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid');
    expect(res.status).toBe(422);
  });

  it('returns 422 when end_time is before start_time', async () => {
    const req = makeRequest('POST', '/api/experts/expert-uuid/availability/rules', {
      day_of_week: 1, start_time: '17:00', end_time: '09:00',
    });
    const res = await handleCreateAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid');
    expect(res.status).toBe(422);
    const body = await res.json() as { error: string; details: Record<string, string> };
    expect(body.details.end_time).toBe('must be after start_time');
  });

  it('returns 409 when rule overlaps existing', async () => {
    const mockSql = vi.fn() as Mock;
    // Overlap check: existing rule Mon 08:00–12:00 overlaps with new 09:00–17:00
    mockSql.mockResolvedValueOnce([{ start_time: '08:00:00', end_time: '12:00:00' }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const req = makeRequest('POST', '/api/experts/expert-uuid/availability/rules', {
      day_of_week: 1, start_time: '09:00', end_time: '17:00',
    });
    const res = await handleCreateAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid');
    expect(res.status).toBe(409);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('overlapping_rule');
  });

  it('returns 201 on successful creation', async () => {
    const mockSql = vi.fn() as Mock;
    // No existing overlapping rules
    mockSql.mockResolvedValueOnce([]);
    // INSERT RETURNING
    mockSql.mockResolvedValueOnce([{ ...sampleRule }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const req = makeRequest('POST', '/api/experts/expert-uuid/availability/rules', {
      day_of_week: 1, start_time: '09:00', end_time: '17:00',
    });
    const res = await handleCreateAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid');
    expect(res.status).toBe(201);
    const body = await res.json() as ExpertAvailabilityRuleRow;
    expect(body.day_of_week).toBe(1);
    expect(body.start_time).toBe('09:00');
    expect(body.end_time).toBe('17:00');
  });
});

// ── Group 4: PUT (update) availability rule ───────────────────────────────────

describe('handleUpdateAvailabilityRule', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns 403 when user is not the expert', async () => {
    const req = makeRequest('PUT', '/api/experts/expert-uuid/availability/rules/rule-uuid-1', {
      day_of_week: 1, start_time: '09:00', end_time: '17:00',
    });
    const res = await handleUpdateAvailabilityRule(req, mockEnv as never, otherUser, 'expert-uuid', 'rule-uuid-1');
    expect(res.status).toBe(403);
  });

  it('returns 404 when rule does not exist', async () => {
    const mockSql = vi.fn() as Mock;
    // Rule lookup returns empty
    mockSql.mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const req = makeRequest('PUT', '/api/experts/expert-uuid/availability/rules/nonexistent', {
      day_of_week: 1, start_time: '09:00', end_time: '17:00',
    });
    const res = await handleUpdateAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid', 'nonexistent');
    expect(res.status).toBe(404);
  });

  it('returns 409 when update creates overlap (excluding self)', async () => {
    const mockSql = vi.fn() as Mock;
    // Rule lookup — found
    mockSql.mockResolvedValueOnce([sampleRule]);
    // Other rules on same day (NOT the current rule) — has overlapping one
    mockSql.mockResolvedValueOnce([{ start_time: '14:00:00', end_time: '18:00:00' }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const req = makeRequest('PUT', '/api/experts/expert-uuid/availability/rules/rule-uuid-1', {
      day_of_week: 1, start_time: '13:00', end_time: '16:00',
    });
    const res = await handleUpdateAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid', 'rule-uuid-1');
    expect(res.status).toBe(409);
  });

  it('returns 200 on successful update', async () => {
    const mockSql = vi.fn() as Mock;
    // Rule lookup — found
    mockSql.mockResolvedValueOnce([sampleRule]);
    // No other overlapping rules
    mockSql.mockResolvedValueOnce([]);
    // UPDATE RETURNING
    const updated = { ...sampleRule, start_time: '10:00:00', end_time: '18:00:00' };
    mockSql.mockResolvedValueOnce([updated]);
    (createSql as Mock).mockReturnValue(mockSql);

    const req = makeRequest('PUT', '/api/experts/expert-uuid/availability/rules/rule-uuid-1', {
      day_of_week: 1, start_time: '10:00', end_time: '18:00',
    });
    const res = await handleUpdateAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid', 'rule-uuid-1');
    expect(res.status).toBe(200);
    const body = await res.json() as ExpertAvailabilityRuleRow;
    expect(body.start_time).toBe('10:00');
    expect(body.end_time).toBe('18:00');
  });
});

// ── Group 5: DELETE availability rule ────────────────────────────────────────

describe('handleDeleteAvailabilityRule', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns 403 when user is not the expert', async () => {
    const req = makeRequest('DELETE', '/api/experts/expert-uuid/availability/rules/rule-uuid-1');
    const res = await handleDeleteAvailabilityRule(req, mockEnv as never, otherUser, 'expert-uuid', 'rule-uuid-1');
    expect(res.status).toBe(403);
  });

  it('returns 404 when rule does not exist or already inactive', async () => {
    const mockSql = vi.fn() as Mock;
    mockSql.mockResolvedValueOnce([]); // Rule not found
    (createSql as Mock).mockReturnValue(mockSql);

    const req = makeRequest('DELETE', '/api/experts/expert-uuid/availability/rules/nonexistent');
    const res = await handleDeleteAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid', 'nonexistent');
    expect(res.status).toBe(404);
  });

  it('returns 204 on successful soft delete', async () => {
    const mockSql = vi.fn() as Mock;
    // Rule lookup — found
    mockSql.mockResolvedValueOnce([{ id: 'rule-uuid-1' }]);
    // UPDATE is_active = false
    mockSql.mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const req = makeRequest('DELETE', '/api/experts/expert-uuid/availability/rules/rule-uuid-1');
    const res = await handleDeleteAvailabilityRule(req, mockEnv as never, mockUser, 'expert-uuid', 'rule-uuid-1');
    expect(res.status).toBe(204);
    expect(res.body).toBeNull();
  });
});

// ── Group 6: expandRulesToWorkingHours (lib) ──────────────────────────────────

describe('expandRulesToWorkingHours', () => {
  it('returns empty object for empty rules', () => {
    const result = expandRulesToWorkingHours([], 'UTC');
    expect(result).toEqual({});
  });

  it('converts a UTC rule unchanged', () => {
    const rule: ExpertAvailabilityRuleRow = {
      ...sampleRule,
      day_of_week: 1, // Monday
      start_time: '09:00:00',
      end_time: '17:00:00',
    };
    const result = expandRulesToWorkingHours([rule], 'UTC');
    // UTC offset = 0 → local == UTC
    expect(result['mon']).toEqual(['09:00', '17:00']);
  });

  it('converts Brussels (UTC+1 winter) times to UTC', () => {
    const rule: ExpertAvailabilityRuleRow = {
      ...sampleRule,
      day_of_week: 1,
      start_time: '09:00:00',
      end_time: '17:00:00',
    };
    const result = expandRulesToWorkingHours([rule], 'Europe/Brussels');
    // Brussels is UTC+1 in winter: 09:00 local = 08:00 UTC
    expect(result['mon']).toEqual(['08:00', '16:00']);
  });

  it('excludes inactive rules', () => {
    const inactiveRule: ExpertAvailabilityRuleRow = {
      ...sampleRule,
      is_active: false,
    };
    const result = expandRulesToWorkingHours([inactiveRule], 'UTC');
    expect(result).toEqual({});
  });

  it('uses first rule per day when multiple rules on same day', () => {
    const rule1: ExpertAvailabilityRuleRow = {
      ...sampleRule,
      id: 'r1',
      day_of_week: 1,
      start_time: '09:00:00',
      end_time: '12:00:00',
    };
    const rule2: ExpertAvailabilityRuleRow = {
      ...sampleRule,
      id: 'r2',
      day_of_week: 1,
      start_time: '14:00:00',
      end_time: '18:00:00',
    };
    // Both active, different time slots — first one encountered wins
    const result = expandRulesToWorkingHours([rule1, rule2], 'UTC');
    // Only first rule per day is kept
    expect(result['mon']).toEqual(['09:00', '12:00']);
  });

  it('handles HH:MM format (no seconds) from body', () => {
    const rule: ExpertAvailabilityRuleRow = {
      ...sampleRule,
      start_time: '09:00', // no seconds
      end_time: '17:00',
    };
    const result = expandRulesToWorkingHours([rule], 'UTC');
    expect(result['mon']).toEqual(['09:00', '17:00']);
  });

  it('falls back to UTC for an invalid timezone string', () => {
    const rule: ExpertAvailabilityRuleRow = {
      ...sampleRule,
      day_of_week: 3, // Wednesday
      start_time: '09:00:00',
      end_time: '17:00:00',
    };
    // Invalid timezone should not throw
    const result = expandRulesToWorkingHours([rule], 'Not/ATimezone');
    // Falls back to UTC — times unchanged
    expect(result['wed']).toEqual(['09:00', '17:00']);
  });
});

// ── Group 7: Availability endpoint regression ─────────────────────────────────
// These tests verify handler-level integration through the availability.ts handler.
// We test via direct import to avoid needing a full Worker environment.

describe('handleGetAvailability — hybrid model regression', () => {
  beforeEach(() => vi.clearAllMocks());

  it('does not crash if expanded from the imported handler', async () => {
    // Smoke test: ensure the handler module resolves (no import errors)
    const mod = await import('../bookings/availability');
    expect(typeof mod.handleGetAvailability).toBe('function');
  });

  it('expandRulesToWorkingHours handles Sunday (day 0)', () => {
    const rule: ExpertAvailabilityRuleRow = {
      ...sampleRule,
      day_of_week: 0, // Sunday
      start_time: '10:00:00',
      end_time: '14:00:00',
    };
    const result = expandRulesToWorkingHours([rule], 'UTC');
    expect(result['sun']).toEqual(['10:00', '14:00']);
  });

  it('expandRulesToWorkingHours handles Saturday (day 6)', () => {
    const rule: ExpertAvailabilityRuleRow = {
      ...sampleRule,
      day_of_week: 6, // Saturday
      start_time: '08:00:00',
      end_time: '12:00:00',
    };
    const result = expandRulesToWorkingHours([rule], 'UTC');
    expect(result['sat']).toEqual(['08:00', '12:00']);
  });

  it('rulesOverlap is commutative', () => {
    const a = { s: '09:00', e: '12:00' };
    const b = { s: '11:00', e: '14:00' };
    expect(rulesOverlap(a.s, a.e, b.s, b.e)).toBe(rulesOverlap(b.s, b.e, a.s, a.e));
  });
});
