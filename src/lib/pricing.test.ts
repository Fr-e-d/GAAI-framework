import { describe, it, expect } from 'vitest';
import { calculateLeadPrice } from './pricing';

// ── Standard qualification (budget or timeline or skills missing) ─────────────

describe('calculateLeadPrice — standard qualification', () => {
  it('tier micro: null budget → 4900', () => {
    const result = calculateLeadPrice(null, { budget_max: null });
    expect(result.amount).toBe(4900);
    expect(result.tier).toBe('micro');
    expect(result.qualification).toBe('standard');
  });

  it('tier micro: undefined budget → 4900', () => {
    const result = calculateLeadPrice(undefined, {});
    expect(result.amount).toBe(4900);
    expect(result.tier).toBe('micro');
    expect(result.qualification).toBe('standard');
  });

  it('tier micro: budget 0 → 4900', () => {
    const result = calculateLeadPrice(0, { budget_max: 0 });
    expect(result.amount).toBe(4900);
    expect(result.tier).toBe('micro');
    expect(result.qualification).toBe('standard');
  });

  it('tier micro: budget 4999 → 4900', () => {
    const result = calculateLeadPrice(4999, { budget_max: 4999 });
    expect(result.amount).toBe(4900);
    expect(result.tier).toBe('micro');
    expect(result.qualification).toBe('standard');
  });

  it('tier small: budget 5000 → 8900', () => {
    const result = calculateLeadPrice(5000, { budget_max: 5000 });
    expect(result.amount).toBe(8900);
    expect(result.tier).toBe('small');
    expect(result.qualification).toBe('standard');
  });

  it('tier small: budget 19999 → 8900', () => {
    const result = calculateLeadPrice(19999, { budget_max: 19999 });
    expect(result.amount).toBe(8900);
    expect(result.tier).toBe('small');
    expect(result.qualification).toBe('standard');
  });

  it('tier medium: budget 20000 → 14900', () => {
    const result = calculateLeadPrice(20000, { budget_max: 20000 });
    expect(result.amount).toBe(14900);
    expect(result.tier).toBe('medium');
    expect(result.qualification).toBe('standard');
  });

  it('tier medium: budget 49999 → 14900', () => {
    const result = calculateLeadPrice(49999, { budget_max: 49999 });
    expect(result.amount).toBe(14900);
    expect(result.tier).toBe('medium');
    expect(result.qualification).toBe('standard');
  });

  it('tier large: budget 50000 → 22900', () => {
    const result = calculateLeadPrice(50000, { budget_max: 50000 });
    expect(result.amount).toBe(22900);
    expect(result.tier).toBe('large');
    expect(result.qualification).toBe('standard');
  });

  it('tier large: budget 100000 → 22900', () => {
    const result = calculateLeadPrice(100000, { budget_max: 100000 });
    expect(result.amount).toBe(22900);
    expect(result.tier).toBe('large');
    expect(result.qualification).toBe('standard');
  });
});

// ── Premium qualification (budget + timeline + skills all present) ────────────

describe('calculateLeadPrice — premium qualification', () => {
  it('tier micro: null budget, premium otherwise impossible → standard fallback', () => {
    // budget_max is null → not premium (budget missing)
    const result = calculateLeadPrice(null, {
      budget_max: null,
      timeline_days: 30,
      skills: ['n8n'],
    });
    expect(result.amount).toBe(4900);
    expect(result.qualification).toBe('standard');
  });

  it('tier micro: budget 1000 + timeline + skills → premium 5600', () => {
    const result = calculateLeadPrice(1000, {
      budget_max: 1000,
      timeline_days: 14,
      skills: ['python'],
    });
    expect(result.amount).toBe(5600);
    expect(result.tier).toBe('micro');
    expect(result.qualification).toBe('premium');
  });

  it('tier small: budget 10000 + timeline + skills → premium 10200', () => {
    const result = calculateLeadPrice(10000, {
      budget_max: 10000,
      timeline_days: 30,
      skills: ['n8n', 'zapier'],
    });
    expect(result.amount).toBe(10200);
    expect(result.tier).toBe('small');
    expect(result.qualification).toBe('premium');
  });

  it('tier medium: budget 30000 + timeline + skills → premium 17100', () => {
    const result = calculateLeadPrice(30000, {
      budget_max: 30000,
      timeline_days: 60,
      skills: ['python', 'airflow'],
    });
    expect(result.amount).toBe(17100);
    expect(result.tier).toBe('medium');
    expect(result.qualification).toBe('premium');
  });

  it('tier large: budget 75000 + timeline + skills → premium 26300', () => {
    const result = calculateLeadPrice(75000, {
      budget_max: 75000,
      timeline_days: 90,
      skills: ['python', 'airflow', 'dbt'],
    });
    expect(result.amount).toBe(26300);
    expect(result.tier).toBe('large');
    expect(result.qualification).toBe('premium');
  });
});

// ── Edge cases: missing timeline or skills → standard ─────────────────────────

describe('calculateLeadPrice — premium missing required fields', () => {
  it('missing timeline_days → standard', () => {
    const result = calculateLeadPrice(10000, {
      budget_max: 10000,
      timeline_days: null,
      skills: ['n8n'],
    });
    expect(result.qualification).toBe('standard');
    expect(result.amount).toBe(8900);
  });

  it('missing skills → standard', () => {
    const result = calculateLeadPrice(10000, {
      budget_max: 10000,
      timeline_days: 30,
      skills: [],
    });
    expect(result.qualification).toBe('standard');
    expect(result.amount).toBe(8900);
  });

  it('undefined skills → standard', () => {
    const result = calculateLeadPrice(10000, {
      budget_max: 10000,
      timeline_days: 30,
    });
    expect(result.qualification).toBe('standard');
    expect(result.amount).toBe(8900);
  });

  it('undefined timeline_days → standard', () => {
    const result = calculateLeadPrice(10000, {
      budget_max: 10000,
      skills: ['n8n'],
    });
    expect(result.qualification).toBe('standard');
    expect(result.amount).toBe(8900);
  });
});

// ── Boundary values ───────────────────────────────────────────────────────────

describe('calculateLeadPrice — boundary values', () => {
  it('budget exactly 5000 → small tier', () => {
    const result = calculateLeadPrice(5000, { budget_max: 5000 });
    expect(result.tier).toBe('small');
  });

  it('budget exactly 20000 → medium tier', () => {
    const result = calculateLeadPrice(20000, { budget_max: 20000 });
    expect(result.tier).toBe('medium');
  });

  it('budget exactly 50000 → large tier', () => {
    const result = calculateLeadPrice(50000, { budget_max: 50000 });
    expect(result.tier).toBe('large');
  });

  it('budget 4999 → micro tier', () => {
    const result = calculateLeadPrice(4999, { budget_max: 4999 });
    expect(result.tier).toBe('micro');
  });

  it('budget 19999 → small tier', () => {
    const result = calculateLeadPrice(19999, { budget_max: 19999 });
    expect(result.tier).toBe('small');
  });

  it('budget 49999 → medium tier', () => {
    const result = calculateLeadPrice(49999, { budget_max: 49999 });
    expect(result.tier).toBe('medium');
  });
});
