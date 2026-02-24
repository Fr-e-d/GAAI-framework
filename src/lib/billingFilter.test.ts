import { describe, it, expect } from 'vitest';
import { applyBillingFilters } from './billingFilter';
import type { BillingRecord } from './billingFilter';

// Helper to build billing records
function record(overrides: Partial<BillingRecord> & { expert_id: string }): BillingRecord {
  return {
    credit_balance: 100000,
    max_lead_price: null,
    spending_limit: null,
    monthly_spend: 0,
    ...overrides,
  };
}

describe('applyBillingFilters — balance check (AC2, AC9)', () => {
  it('balance sufficient → included', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 10000 })]]);
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(1);
    expect(excluded).toHaveLength(0);
  });

  it('balance exactly equal → included', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 8900 })]]);
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(1);
    expect(excluded).toHaveLength(0);
  });

  it('balance insufficient → excluded', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 8899 })]]);
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(0);
    expect(excluded).toHaveLength(1);
    expect(excluded[0]).toMatchObject({ expert_id: 'e1', reason: 'insufficient_balance' });
  });

  it('balance zero → excluded (AC9 — no free pass)', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 0 })]]);
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 4900);
    expect(eligible).toHaveLength(0);
    expect(excluded[0]).toMatchObject({ expert_id: 'e1', reason: 'insufficient_balance' });
  });

  it('expert not in billing map → defaults to 0 balance → excluded (AC9)', () => {
    const experts = [{ id: 'unknown' }];
    const billingMap = new Map<string, BillingRecord>();
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 4900);
    expect(eligible).toHaveLength(0);
    expect(excluded[0]).toMatchObject({ expert_id: 'unknown', reason: 'insufficient_balance' });
  });
});

describe('applyBillingFilters — max_lead_price check (AC3)', () => {
  it('max_lead_price null → skip check → included', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 100000, max_lead_price: null })]]);
    const { eligible } = applyBillingFilters(experts, billingMap, 22900);
    expect(eligible).toHaveLength(1);
  });

  it('leadPrice equals max_lead_price → included', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 100000, max_lead_price: 8900 })]]);
    const { eligible } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(1);
  });

  it('leadPrice exceeds max_lead_price → excluded', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 100000, max_lead_price: 8899 })]]);
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(0);
    expect(excluded[0]).toMatchObject({ expert_id: 'e1', reason: 'max_lead_price_exceeded' });
  });
});

describe('applyBillingFilters — spending_limit check (AC4)', () => {
  it('spending_limit null → skip check → included', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 100000, spending_limit: null, monthly_spend: 90000 })]]);
    const { eligible } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(1);
  });

  it('monthly_spend + leadPrice exactly equals spending_limit → included', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 100000, spending_limit: 90900, monthly_spend: 82000 })]]);
    const { eligible } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(1);
  });

  it('monthly_spend + leadPrice exceeds spending_limit → excluded', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 100000, spending_limit: 90900, monthly_spend: 82001 })]]);
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(0);
    expect(excluded[0]).toMatchObject({ expert_id: 'e1', reason: 'spending_limit_reached' });
  });

  it('zero monthly_spend, spending_limit high → included', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 100000, spending_limit: 100000, monthly_spend: 0 })]]);
    const { eligible } = applyBillingFilters(experts, billingMap, 4900);
    expect(eligible).toHaveLength(1);
  });
});

describe('applyBillingFilters — check ordering (first-failing reason wins)', () => {
  it('balance fails first, also would fail max_lead_price → reason=insufficient_balance', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 5000, max_lead_price: 4000 })]]);
    const { excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(excluded[0]?.reason).toBe('insufficient_balance');
  });

  it('balance passes, max_lead_price fails → reason=max_lead_price_exceeded', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 100000, max_lead_price: 8000 })]]);
    const { excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(excluded[0]?.reason).toBe('max_lead_price_exceeded');
  });

  it('balance passes, max_lead_price passes, spending_limit fails → reason=spending_limit_reached', () => {
    const experts = [{ id: 'e1' }];
    const billingMap = new Map([['e1', record({ expert_id: 'e1', credit_balance: 100000, max_lead_price: 15000, spending_limit: 90000, monthly_spend: 85000 })]]);
    const { excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(excluded[0]?.reason).toBe('spending_limit_reached');
  });
});

describe('applyBillingFilters — mixed pool (AC7, AC11)', () => {
  it('all experts excluded → eligible=[], excluded has all (AC7)', () => {
    const experts = [{ id: 'e1' }, { id: 'e2' }, { id: 'e3' }];
    const billingMap = new Map([
      ['e1', record({ expert_id: 'e1', credit_balance: 0 })],
      ['e2', record({ expert_id: 'e2', credit_balance: 100000, max_lead_price: 5000 })],
      ['e3', record({ expert_id: 'e3', credit_balance: 100000, spending_limit: 10000, monthly_spend: 5200 })],
    ]);
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(0);
    expect(excluded).toHaveLength(3);
  });

  it('partial exclusion → correct split', () => {
    const experts = [{ id: 'e1' }, { id: 'e2' }];
    const billingMap = new Map([
      ['e1', record({ expert_id: 'e1', credit_balance: 100000 })],
      ['e2', record({ expert_id: 'e2', credit_balance: 0 })],
    ]);
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(1);
    expect(eligible[0]?.id).toBe('e1');
    expect(excluded).toHaveLength(1);
    expect(excluded[0]?.expert_id).toBe('e2');
  });

  it('multiple constraints simultaneously — each expert excluded for correct reason (AC11)', () => {
    const experts = [{ id: 'e1' }, { id: 'e2' }, { id: 'e3' }, { id: 'e4' }];
    const billingMap = new Map([
      ['e1', record({ expert_id: 'e1', credit_balance: 100000 })],  // eligible
      ['e2', record({ expert_id: 'e2', credit_balance: 0 })],  // insufficient_balance
      ['e3', record({ expert_id: 'e3', credit_balance: 100000, max_lead_price: 5000 })],  // max_lead_price_exceeded
      ['e4', record({ expert_id: 'e4', credit_balance: 100000, spending_limit: 50000, monthly_spend: 45000 })],  // spending_limit_reached
    ]);
    const { eligible, excluded } = applyBillingFilters(experts, billingMap, 8900);
    expect(eligible).toHaveLength(1);
    expect(eligible[0]?.id).toBe('e1');
    expect(excluded).toHaveLength(3);
    const reasons = excluded.map((e) => e.reason);
    expect(reasons).toContain('insufficient_balance');
    expect(reasons).toContain('max_lead_price_exceeded');
    expect(reasons).toContain('spending_limit_reached');
  });
});

describe('applyBillingFilters — edge cases', () => {
  it('empty pool → eligible=[], excluded=[]', () => {
    const { eligible, excluded } = applyBillingFilters([], new Map(), 8900);
    expect(eligible).toHaveLength(0);
    expect(excluded).toHaveLength(0);
  });
});
