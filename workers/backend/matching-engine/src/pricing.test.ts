import { describe, expect, it } from 'vitest';
import { calculateLeadPrice } from './pricing';
import type { QualificationData } from './pricing';

// ── Helpers ───────────────────────────────────────────────────────────────────

const premiumData: QualificationData = {
  budget_max: 10000,
  timeline_days: 30,
  skills: ['n8n', 'python'],
};

const standardData: QualificationData = {
  budget_max: 10000,
};

// ── Rate calculation — budget tier selection ──────────────────────────────────

describe('calculateLeadPrice — budget tier selection', () => {
  it('micro tier: null budget_max → standard 4900', () => {
    const result = calculateLeadPrice(null, standardData);
    expect(result.tier).toBe('micro');
    expect(result.amount).toBe(4900);
    expect(result.qualification).toBe('standard');
  });

  it('micro tier: budget_max undefined → standard 4900', () => {
    const result = calculateLeadPrice(undefined, standardData);
    expect(result.tier).toBe('micro');
    expect(result.amount).toBe(4900);
  });

  it('micro tier: budget_max < 5000 → standard 4900', () => {
    const result = calculateLeadPrice(4999, standardData);
    expect(result.tier).toBe('micro');
    expect(result.amount).toBe(4900);
  });

  it('small tier: budget_max 5000 → standard 8900', () => {
    const result = calculateLeadPrice(5000, standardData);
    expect(result.tier).toBe('small');
    expect(result.amount).toBe(8900);
  });

  it('small tier: budget_max 19999 → standard 8900', () => {
    const result = calculateLeadPrice(19999, standardData);
    expect(result.tier).toBe('small');
    expect(result.amount).toBe(8900);
  });

  it('medium tier: budget_max 20000 → standard 14900', () => {
    const result = calculateLeadPrice(20000, standardData);
    expect(result.tier).toBe('medium');
    expect(result.amount).toBe(14900);
  });

  it('medium tier: budget_max 49999 → standard 14900', () => {
    const result = calculateLeadPrice(49999, standardData);
    expect(result.tier).toBe('medium');
    expect(result.amount).toBe(14900);
  });

  it('large tier: budget_max 50000 → standard 22900', () => {
    const result = calculateLeadPrice(50000, standardData);
    expect(result.tier).toBe('large');
    expect(result.amount).toBe(22900);
  });

  it('large tier: budget_max 200000 → standard 22900', () => {
    const result = calculateLeadPrice(200000, standardData);
    expect(result.tier).toBe('large');
    expect(result.amount).toBe(22900);
  });
});

// ── Premium vs standard qualification ────────────────────────────────────────

describe('calculateLeadPrice — premium qualification', () => {
  it('premium: all fields present → premium amount (+15%)', () => {
    const result = calculateLeadPrice(10000, premiumData);
    expect(result.qualification).toBe('premium');
    expect(result.amount).toBe(10200); // small tier premium
  });

  it('premium micro tier: null budget in qualification data still premium with explicit budget_max', () => {
    const data: QualificationData = {
      budget_max: 1000,
      timeline_days: 14,
      skills: ['n8n'],
    };
    const result = calculateLeadPrice(null, data);
    // budget_max in qualificationData is 1000 (not null), but budgetMax arg is null → micro tier
    // isPremium: budget_max=1000 (not null), timeline=14 (not null), skills=['n8n'] → premium
    expect(result.tier).toBe('micro');
    expect(result.qualification).toBe('premium');
    expect(result.amount).toBe(5600);
  });

  it('standard: missing timeline_days → standard amount', () => {
    const data: QualificationData = { budget_max: 10000, skills: ['n8n'] };
    const result = calculateLeadPrice(10000, data);
    expect(result.qualification).toBe('standard');
    expect(result.amount).toBe(8900);
  });

  it('standard: missing skills → standard amount', () => {
    const data: QualificationData = { budget_max: 10000, timeline_days: 30 };
    const result = calculateLeadPrice(10000, data);
    expect(result.qualification).toBe('standard');
    expect(result.amount).toBe(8900);
  });

  it('standard: empty skills array → standard amount', () => {
    const data: QualificationData = { budget_max: 10000, timeline_days: 30, skills: [] };
    const result = calculateLeadPrice(10000, data);
    expect(result.qualification).toBe('standard');
    expect(result.amount).toBe(8900);
  });

  it('standard: null budget_max in qualification data → standard', () => {
    const data: QualificationData = { budget_max: null, timeline_days: 30, skills: ['n8n'] };
    const result = calculateLeadPrice(10000, data);
    expect(result.qualification).toBe('standard');
  });

  it('standard: null timeline_days in qualification data → standard', () => {
    const data: QualificationData = { budget_max: 10000, timeline_days: null, skills: ['n8n'] };
    const result = calculateLeadPrice(10000, data);
    expect(result.qualification).toBe('standard');
  });
});

// ── Boundary values ───────────────────────────────────────────────────────────

describe('calculateLeadPrice — boundary values', () => {
  it('returns amounts in centimes (integers, no floating point)', () => {
    const result = calculateLeadPrice(50000, premiumData);
    expect(Number.isInteger(result.amount)).toBe(true);
  });

  it('budget_max 0 → micro tier', () => {
    const result = calculateLeadPrice(0, standardData);
    expect(result.tier).toBe('micro');
  });

  it('large tier premium → 26300 centimes', () => {
    const result = calculateLeadPrice(100000, premiumData);
    expect(result.tier).toBe('large');
    expect(result.amount).toBe(26300);
  });

  it('result structure always contains amount, tier, and qualification', () => {
    const result = calculateLeadPrice(null, {});
    expect(result).toHaveProperty('amount');
    expect(result).toHaveProperty('tier');
    expect(result).toHaveProperty('qualification');
  });
});

// ── Premium grid cross-validation ────────────────────────────────────────────

describe('calculateLeadPrice — premium grid (all tiers)', () => {
  const fullPremiumData: QualificationData = {
    budget_max: 99999,
    timeline_days: 30,
    skills: ['n8n'],
  };

  it.each([
    [null, 'micro', 5600],
    [5000, 'small', 10200],
    [20000, 'medium', 17100],
    [50000, 'large', 26300],
  ] as const)('budget_max=%s → %s tier premium=%s', (budgetMax, tier, expectedAmount) => {
    const result = calculateLeadPrice(budgetMax, fullPremiumData);
    expect(result.tier).toBe(tier);
    expect(result.qualification).toBe('premium');
    expect(result.amount).toBe(expectedAmount);
  });
});
