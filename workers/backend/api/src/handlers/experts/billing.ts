// E06S38: GET /api/experts/:id/billing — credit balance, subscription, and transactions

import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createSql } from '../../lib/db';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function forbidden(): Response {
  return new Response(JSON.stringify({ error: 'Forbidden' }), {
    status: 403,
    headers: JSON_HEADERS,
  });
}

// ── GET /api/experts/:id/billing ──────────────────────────────────────────────

export async function handleGetBilling(
  request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
): Promise<Response> {
  // Ownership check
  if (user.id !== expertId) {
    return forbidden();
  }

  const url = new URL(request.url);
  const page = Math.max(1, parseInt(url.searchParams.get('page') ?? '1', 10) || 1);
  const perPage = Math.min(Math.max(1, parseInt(url.searchParams.get('per_page') ?? '20', 10) || 20), 50);
  const offset = (page - 1) * perPage;

  const sql = createSql(env);

  // Query 1 — expert billing data
  const [expert] = await sql<{
    credit_balance: number;
    ls_subscription_status: string | null;
    ls_subscription_id: string | null;
    spending_limit: number | null;
    max_lead_price: number | null;
  }[]>`
    SELECT credit_balance, ls_subscription_status, ls_subscription_id, spending_limit, max_lead_price
    FROM experts
    WHERE id = ${expertId}
  `;

  if (!expert) {
    return new Response(JSON.stringify({ error: 'Expert not found' }), {
      status: 404,
      headers: JSON_HEADERS,
    });
  }

  // Query 2 — monthly spend (debit transactions since start of month)
  const [monthlyRow] = await sql<{ monthly_spend: string }[]>`
    SELECT COALESCE(SUM(amount), 0) AS monthly_spend
    FROM credit_transactions
    WHERE expert_id = ${expertId}
      AND type = 'debit'
      AND created_at >= date_trunc('month', NOW())
  `;
  const monthlySpend = parseInt(monthlyRow?.monthly_spend ?? '0', 10);

  // Query 3 — transaction count
  const [countRow] = await sql<{ count: string }[]>`
    SELECT COUNT(*) AS count FROM credit_transactions WHERE expert_id = ${expertId}
  `;
  const totalTransactions = parseInt(countRow?.count ?? '0', 10);

  // Query 4 — paginated transactions
  const transactionRows = await sql<{
    id: string;
    type: string;
    amount: number;
    description: string | null;
    lead_id: string | null;
    created_at: string | null;
  }[]>`
    SELECT id, type, amount, description, lead_id, created_at
    FROM credit_transactions
    WHERE expert_id = ${expertId}
    ORDER BY created_at DESC
    LIMIT ${perPage} OFFSET ${offset}
  `;

  const transactions = transactionRows.map((t) => ({
    id: t.id,
    type: t.type,
    amount_cents: t.amount,
    description: t.description,
    lead_id: t.lead_id,
    created_at: t.created_at,
  }));

  return new Response(
    JSON.stringify({
      credit_balance: expert.credit_balance,
      ls_subscription_status: expert.ls_subscription_status,
      ls_subscription_id: expert.ls_subscription_id,
      spending_limit: expert.spending_limit,
      max_lead_price: expert.max_lead_price,
      monthly_spend: monthlySpend,
      transactions,
      total_transactions: totalTransactions,
      page,
      per_page: perPage,
    }),
    { status: 200, headers: JSON_HEADERS },
  );
}
