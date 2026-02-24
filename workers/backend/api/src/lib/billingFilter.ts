// ── Billing filter — pre-scoring exclusion (E06S34, DEC-67/68) ──────────────
// Applied BEFORE scoring in the matching pipeline.
// Pure function applyBillingFilters + Hyperdrive query helper loadBillingData.

import { createSql } from './db';
import type { Env } from '../types/env';

export interface BillingRecord {
  expert_id: string;
  credit_balance: number;
  max_lead_price: number | null;
  spending_limit: number | null;
  monthly_spend: number;
}

export interface BillingExclusion {
  expert_id: string;
  reason: 'insufficient_balance' | 'max_lead_price_exceeded' | 'spending_limit_reached';
}

// ── Pure filter function ──────────────────────────────────────────────────────

export function applyBillingFilters<T extends { id: string }>(
  experts: T[],
  billingMap: Map<string, BillingRecord>,
  leadPrice: number,
): { eligible: T[]; excluded: BillingExclusion[] } {
  const eligible: T[] = [];
  const excluded: BillingExclusion[] = [];

  for (const expert of experts) {
    const billing = billingMap.get(expert.id) ?? {
      expert_id: expert.id,
      credit_balance: 0,
      max_lead_price: null,
      spending_limit: null,
      monthly_spend: 0,
    };

    // AC2 + AC9: balance check — credit_balance=0 still excluded (no free pass)
    if (billing.credit_balance < leadPrice) {
      excluded.push({ expert_id: expert.id, reason: 'insufficient_balance' });
      continue;
    }

    // AC3: max_lead_price deal-breaker (null = no cap)
    if (billing.max_lead_price !== null && leadPrice > billing.max_lead_price) {
      excluded.push({ expert_id: expert.id, reason: 'max_lead_price_exceeded' });
      continue;
    }

    // AC4: spending_limit monthly cap (null = unlimited)
    if (billing.spending_limit !== null && billing.monthly_spend + leadPrice > billing.spending_limit) {
      excluded.push({ expert_id: expert.id, reason: 'spending_limit_reached' });
      continue;
    }

    eligible.push(expert);
  }

  return { eligible, excluded };
}

// ── Hyperdrive query helper ───────────────────────────────────────────────────

export async function loadBillingData(
  env: Env,
  expertIds: string[],
): Promise<Map<string, BillingRecord>> {
  if (expertIds.length === 0) return new Map();

  const sql = createSql(env);

  // Query 1: billing columns from experts table
  const billingRows = await sql<
    { id: string; credit_balance: number; max_lead_price: number | null; spending_limit: number | null }[]
  >`SELECT id, credit_balance, max_lead_price, spending_limit FROM experts WHERE id = ANY(${expertIds})`;

  // Query 2: monthly spend from credit_transactions (AC4, AC5 — uses index on expert_id, created_at)
  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);

  const spendRows = await sql<{ expert_id: string; monthly_spend: number }[]>`
    SELECT expert_id, COALESCE(SUM(ABS(amount)), 0)::integer AS monthly_spend
    FROM credit_transactions
    WHERE type = 'lead_debit'
      AND expert_id = ANY(${expertIds})
      AND created_at >= ${monthStart.toISOString()}
    GROUP BY expert_id`;

  // Build spend map
  const spendMap = new Map<string, number>();
  for (const row of spendRows) {
    spendMap.set(row.expert_id, row.monthly_spend);
  }

  // Build result map
  const result = new Map<string, BillingRecord>();
  for (const row of billingRows) {
    result.set(row.id, {
      expert_id: row.id,
      credit_balance: row.credit_balance,
      max_lead_price: row.max_lead_price,
      spending_limit: row.spending_limit,
      monthly_spend: spendMap.get(row.id) ?? 0,
    });
  }

  return result;
}
