// ── calculateLeadPrice — DEC-67 pricing grid ─────────────────────────────────
// Pure function, no side effects. Returns amount in centimes.
//
// Grid (centimes):
// Budget max         | Standard | Premium (+15%)
// -------------------|----------|---------------
// NULL or < 5000     |   4 900  |   5 600
// 5 000 – 19 999     |   8 900  |  10 200
// 20 000 – 49 999    |  14 900  |  17 100
// 50 000+            |  22 900  |  26 300
//
// Premium = explicit budget provided AND explicit timeline provided
//           AND all required fields present (budget_max, timeline_days, skills)

export interface QualificationData {
  budget_max?: number | null;
  timeline_days?: number | null;
  skills?: string[];
}

export interface LeadPriceResult {
  amount: number;
  tier: string;
  qualification: 'standard' | 'premium';
}

function getBudgetTier(budgetMax: number | null | undefined): { tier: string; standard: number; premium: number } {
  if (budgetMax == null || budgetMax < 5000) {
    return { tier: 'micro', standard: 4900, premium: 5600 };
  }
  if (budgetMax < 20000) {
    return { tier: 'small', standard: 8900, premium: 10200 };
  }
  if (budgetMax < 50000) {
    return { tier: 'medium', standard: 14900, premium: 17100 };
  }
  return { tier: 'large', standard: 22900, premium: 26300 };
}

function isPremium(data: QualificationData): boolean {
  return (
    data.budget_max != null &&
    data.timeline_days != null &&
    Array.isArray(data.skills) &&
    data.skills.length > 0
  );
}

export function calculateLeadPrice(
  budgetMax: number | null | undefined,
  qualificationData: QualificationData,
): LeadPriceResult {
  const { tier, standard, premium } = getBudgetTier(budgetMax);
  const qualification = isPremium(qualificationData) ? 'premium' : 'standard';
  const amount = qualification === 'premium' ? premium : standard;
  return { amount, tier, qualification };
}
