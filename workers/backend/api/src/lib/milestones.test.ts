// Tests for E02S10: lib/milestones.ts (AC12)
// checkMilestones, checkBookable, processMilestoneCredits
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { checkMilestones, checkBookable, processMilestoneCredits } from './milestones';
import type { ExpertRow } from '../types/db';

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeExpert(overrides: Partial<ExpertRow> = {}): ExpertRow {
  return {
    id: 'expert-1',
    display_name: null,
    bio: null,
    avatar_url: null,
    profile: null,
    outcome_tags: null,
    admissibility_criteria: null,
    availability: null,
    availability_rules: null,
    cal_username: null,
    composite_score: null,
    created_at: null,
    credit_balance: 0,
    gcal_access_token: null,
    gcal_connected: null,
    gcal_connected_at: null,
    gcal_email: null,
    gcal_refresh_token: null,
    gcal_token_expiry_at: null,
    headline: null,
    ls_subscription_id: null,
    ls_subscription_item_id: null,
    ls_subscription_status: null,
    max_lead_price: null,
    milestone_matchable_at: null,
    milestone_bookable_at: null,
    milestone_trust_at: null,
    normalized_email: null,
    preferences: null,
    rate_max: null,
    rate_min: null,
    reminder_settings: null,
    score_updated_at: null,
    spending_limit: null,
    verified_at: null,
    ...overrides,
  };
}

// ── checkMilestones — Matchable ────────────────────────────────────────────────

describe('checkMilestones — matchable', () => {
  it('all conditions met → matchable=true', () => {
    const expert = makeExpert({
      display_name: 'John Doe',
      bio: 'A'.repeat(50),
      outcome_tags: ['a', 'b', 'c'],
    });
    const result = checkMilestones(expert);
    expect(result.matchable).toBe(true);
  });

  it('display_name missing → matchable=false', () => {
    const expert = makeExpert({ bio: 'A'.repeat(50), outcome_tags: ['a', 'b', 'c'] });
    expect(checkMilestones(expert).matchable).toBe(false);
  });

  it('display_name too short (< 2 chars) → matchable=false', () => {
    const expert = makeExpert({
      display_name: 'A',
      bio: 'A'.repeat(50),
      outcome_tags: ['a', 'b', 'c'],
    });
    expect(checkMilestones(expert).matchable).toBe(false);
  });

  it('bio too short (< 50 chars) → matchable=false', () => {
    const expert = makeExpert({
      display_name: 'John',
      bio: 'Short bio',
      outcome_tags: ['a', 'b', 'c'],
    });
    expect(checkMilestones(expert).matchable).toBe(false);
  });

  it('bio exactly 50 chars → matchable=true (boundary)', () => {
    const expert = makeExpert({
      display_name: 'John',
      bio: 'A'.repeat(50),
      outcome_tags: ['a', 'b', 'c'],
    });
    expect(checkMilestones(expert).matchable).toBe(true);
  });

  it('less than 3 skill tags → matchable=false', () => {
    const expert = makeExpert({
      display_name: 'John',
      bio: 'A'.repeat(50),
      outcome_tags: ['a', 'b'],
    });
    expect(checkMilestones(expert).matchable).toBe(false);
  });

  it('exactly 3 skill tags → matchable=true (boundary)', () => {
    const expert = makeExpert({
      display_name: 'John',
      bio: 'A'.repeat(50),
      outcome_tags: ['a', 'b', 'c'],
    });
    expect(checkMilestones(expert).matchable).toBe(true);
  });

  it('no outcome_tags → matchable=false', () => {
    const expert = makeExpert({
      display_name: 'John',
      bio: 'A'.repeat(50),
      outcome_tags: null,
    });
    expect(checkMilestones(expert).matchable).toBe(false);
  });
});

// ── checkMilestones — Trust ────────────────────────────────────────────────────

describe('checkMilestones — trust', () => {
  it('avatar_url set → trust=true', () => {
    const expert = makeExpert({ avatar_url: 'https://example.com/photo.jpg' });
    expect(checkMilestones(expert).trust).toBe(true);
  });

  it('portfolio_url in profile → trust=true', () => {
    const expert = makeExpert({ profile: { portfolio_url: 'https://portfolio.com' } });
    expect(checkMilestones(expert).trust).toBe(true);
  });

  it('linkedin_url in profile → trust=true', () => {
    const expert = makeExpert({ profile: { linkedin_url: 'https://linkedin.com/in/test' } });
    expect(checkMilestones(expert).trust).toBe(true);
  });

  it('github_url in profile → trust=true', () => {
    const expert = makeExpert({ profile: { github_url: 'https://github.com/test' } });
    expect(checkMilestones(expert).trust).toBe(true);
  });

  it('website_url in profile → trust=true', () => {
    const expert = makeExpert({ profile: { website_url: 'https://mysite.com' } });
    expect(checkMilestones(expert).trust).toBe(true);
  });

  it('no photo or links → trust=false', () => {
    const expert = makeExpert({ avatar_url: null, profile: null });
    expect(checkMilestones(expert).trust).toBe(false);
  });

  it('empty profile object → trust=false', () => {
    const expert = makeExpert({ avatar_url: null, profile: {} });
    expect(checkMilestones(expert).trust).toBe(false);
  });
});

// ── checkBookable ─────────────────────────────────────────────────────────────

describe('checkBookable', () => {
  it('returns false when table does not exist (E02S11 not delivered)', async () => {
    const sql = vi.fn().mockImplementation(async () => {
      throw new Error('relation "expert_availability_rules" does not exist');
    });
    const result = await checkBookable('expert-1', sql as any);
    expect(result).toBe(false);
  });

  it('returns true when availability rule exists', async () => {
    const sql = vi.fn().mockResolvedValue([{ exists: true }]);
    const result = await checkBookable('expert-1', sql as any);
    expect(result).toBe(true);
  });

  it('returns false when no availability rules', async () => {
    const sql = vi.fn().mockResolvedValue([{ exists: false }]);
    const result = await checkBookable('expert-1', sql as any);
    expect(result).toBe(false);
  });
});

// ── processMilestoneCredits — idempotency ─────────────────────────────────────

describe('processMilestoneCredits', () => {
  it('matchable newly unlocked → returns ["matchable"]', async () => {
    // Simulate: UPDATE sets timestamp, credit INSERT succeeds → unlocked=true
    const sql = vi.fn().mockResolvedValue([{ balance_after: 4000, unlocked: true }]);
    const result = await processMilestoneCredits(
      'expert-1',
      { matchable: true, bookable: false, trust: false },
      sql as any,
    );
    expect(result).toEqual(['matchable']);
  });

  it('trust condition met → returns ["trust"]', async () => {
    const sql = vi.fn().mockResolvedValue([{ balance_after: 2000, unlocked: true }]);
    const result = await processMilestoneCredits(
      'expert-1',
      { matchable: false, bookable: false, trust: true },
      sql as any,
    );
    expect(result).toEqual(['trust']);
  });

  it('idempotency: milestone already set → unlocked=false → returns []', async () => {
    // Simulate: UPDATE WHERE milestone IS NULL matches 0 rows → CTE returns no row → unlocked=false
    const sql = vi.fn().mockResolvedValue([{ balance_after: 0, unlocked: false }]);
    const result = await processMilestoneCredits(
      'expert-1',
      { matchable: true, bookable: false, trust: false },
      sql as any,
    );
    expect(result).toEqual([]);
  });

  it('no conditions met → sql not called, returns []', async () => {
    const sql = vi.fn();
    const result = await processMilestoneCredits(
      'expert-1',
      { matchable: false, bookable: false, trust: false },
      sql as any,
    );
    expect(result).toEqual([]);
    expect(sql).not.toHaveBeenCalled();
  });

  it('all 3 milestones newly unlocked → returns all 3', async () => {
    // Each milestone calls sql 3 times: sql(column) SET, sql(column) WHERE IS NULL, template tag.
    // mockResolvedValue (not Once) ensures all 9 calls return the same value.
    const sql = vi.fn().mockResolvedValue([{ balance_after: 10000, unlocked: true }]);
    const result = await processMilestoneCredits(
      'expert-1',
      { matchable: true, bookable: true, trust: true },
      sql as any,
    );
    expect(result).toHaveLength(3);
    expect(result).toContain('matchable');
    expect(result).toContain('bookable');
    expect(result).toContain('trust');
    // 3 milestones × 3 sql calls each (2 sql(column) + 1 template tag) = 9
    expect(sql).toHaveBeenCalledTimes(9);
  });

  it('double-call: second call returns [] (idempotent)', async () => {
    // Each processMilestoneCredits call (1 condition) calls sql 3 times:
    //   #1 sql(column) for SET clause, #2 sql(column) for WHERE IS NULL, #3 template tag (result)
    // Two calls total = 6 mock invocations. Positions 3 and 6 carry the meaningful return values.
    const sql = vi.fn()
      .mockResolvedValueOnce(null)                              // #1 sql(column) SET
      .mockResolvedValueOnce(null)                              // #2 sql(column) WHERE IS NULL
      .mockResolvedValueOnce([{ balance_after: 4000, unlocked: true }])  // #3 template tag → first result
      .mockResolvedValueOnce(null)                              // #4 sql(column) SET
      .mockResolvedValueOnce(null)                              // #5 sql(column) WHERE IS NULL
      .mockResolvedValueOnce([{ balance_after: 0, unlocked: false }]);   // #6 template tag → second result

    const first = await processMilestoneCredits(
      'expert-1',
      { matchable: true, bookable: false, trust: false },
      sql as any,
    );
    const second = await processMilestoneCredits(
      'expert-1',
      { matchable: true, bookable: false, trust: false },
      sql as any,
    );
    expect(first).toEqual(['matchable']);
    expect(second).toEqual([]);
  });
});
