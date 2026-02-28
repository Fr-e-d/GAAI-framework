// E06S38: GET /api/experts/:id/dashboard — aggregate stats for expert dashboard

import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createSql } from '../../lib/db';
import { deriveQualityTier } from '../../lib/qualityTier';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function forbidden(): Response {
  return new Response(JSON.stringify({ error: 'Forbidden' }), {
    status: 403,
    headers: JSON_HEADERS,
  });
}

// ── Monthly history padding ────────────────────────────────────────────────────

interface MonthlyStats {
  month: string;
  leads_received: number;
  leads_confirmed: number;
  leads_flagged: number;
  bookings_total: number;
  bookings_completed: number;
  conversions_declared: number;
}

function padMonthlyHistory(
  leadsRows: { month: string; leads_received: string; leads_confirmed: string; leads_flagged: string; conversions_declared: string }[],
  bookingsRows: { month: string; bookings_total: string; bookings_completed: string }[],
): MonthlyStats[] {
  const months: string[] = [];
  const now = new Date();
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    months.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`);
  }
  const leadsMap = new Map(leadsRows.map((r) => [r.month, r]));
  const bookingsMap = new Map(bookingsRows.map((r) => [r.month, r]));
  return months.map((month) => {
    const l = leadsMap.get(month);
    const b = bookingsMap.get(month);
    return {
      month,
      leads_received: l ? parseInt(l.leads_received, 10) : 0,
      leads_confirmed: l ? parseInt(l.leads_confirmed, 10) : 0,
      leads_flagged: l ? parseInt(l.leads_flagged, 10) : 0,
      bookings_total: b ? parseInt(b.bookings_total, 10) : 0,
      bookings_completed: b ? parseInt(b.bookings_completed, 10) : 0,
      conversions_declared: l ? parseInt(l.conversions_declared, 10) : 0,
    };
  });
}

// ── GET /api/experts/:id/dashboard ────────────────────────────────────────────

export async function handleGetDashboard(
  _request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
): Promise<Response> {
  // Ownership check
  if (user.id !== expertId) {
    return forbidden();
  }

  const sql = createSql(env);

  // Query 1 — expert base data + milestone timestamps (E02S10)
  const [expert] = await sql<{
    credit_balance: number;
    composite_score: number | null;
    milestone_matchable_at: string | null;
    milestone_bookable_at: string | null;
    milestone_trust_at: string | null;
  }[]>`
    SELECT credit_balance, composite_score,
           milestone_matchable_at, milestone_bookable_at, milestone_trust_at
    FROM experts WHERE id = ${expertId}
  `;

  if (!expert) {
    return new Response(JSON.stringify({ error: 'Expert not found' }), {
      status: 404,
      headers: JSON_HEADERS,
    });
  }

  // Query 2 — unread leads count
  const [unreadRow] = await sql<{ count: string }[]>`
    SELECT COUNT(*) AS count FROM leads WHERE expert_id = ${expertId} AND status = 'new'
  `;

  // Query 3 — upcoming bookings count
  const [upcomingRow] = await sql<{ count: string }[]>`
    SELECT COUNT(*) AS count
    FROM bookings
    WHERE expert_id = ${expertId}
      AND start_at > NOW()
      AND status NOT IN ('cancelled')
  `;

  // Query 4 — current month leads stats
  const [monthLeads] = await sql<{
    leads_received: string;
    leads_confirmed: string;
    leads_flagged: string;
    conversions_declared: string;
  }[]>`
    SELECT
      COUNT(*) AS leads_received,
      COUNT(*) FILTER (WHERE status = 'confirmed') AS leads_confirmed,
      COUNT(*) FILTER (WHERE status = 'flagged') AS leads_flagged,
      COUNT(*) FILTER (WHERE conversion_declared = true) AS conversions_declared
    FROM leads
    WHERE expert_id = ${expertId}
      AND created_at >= date_trunc('month', NOW())
  `;

  // Query 5 — current month bookings stats
  const [monthBookings] = await sql<{
    bookings_total: string;
    bookings_completed: string;
  }[]>`
    SELECT
      COUNT(*) AS bookings_total,
      COUNT(*) FILTER (WHERE status = 'completed') AS bookings_completed
    FROM bookings
    WHERE expert_id = ${expertId}
      AND start_at >= date_trunc('month', NOW())
  `;

  // Query 6 — monthly history: leads (last 6 months)
  const historyLeadsRows = await sql<{
    month: string;
    leads_received: string;
    leads_confirmed: string;
    leads_flagged: string;
    conversions_declared: string;
  }[]>`
    SELECT
      TO_CHAR(date_trunc('month', created_at), 'YYYY-MM') AS month,
      COUNT(*) AS leads_received,
      COUNT(*) FILTER (WHERE status = 'confirmed') AS leads_confirmed,
      COUNT(*) FILTER (WHERE status = 'flagged') AS leads_flagged,
      COUNT(*) FILTER (WHERE conversion_declared = true) AS conversions_declared
    FROM leads
    WHERE expert_id = ${expertId}
      AND created_at >= date_trunc('month', NOW()) - interval '5 months'
    GROUP BY 1
    ORDER BY 1
  `;

  // Query 7 — monthly history: bookings (last 6 months)
  const historyBookingsRows = await sql<{
    month: string;
    bookings_total: string;
    bookings_completed: string;
  }[]>`
    SELECT
      TO_CHAR(date_trunc('month', start_at), 'YYYY-MM') AS month,
      COUNT(*) AS bookings_total,
      COUNT(*) FILTER (WHERE status = 'completed') AS bookings_completed
    FROM bookings
    WHERE expert_id = ${expertId}
      AND start_at >= date_trunc('month', NOW()) - interval '5 months'
    GROUP BY 1
    ORDER BY 1
  `;

  const monthlyHistory = padMonthlyHistory(historyLeadsRows, historyBookingsRows);

  // E02S10: Compute milestone available_at (milestone timestamp + 72h — the credit release date)
  const milestoneAvailableAt = (ts: string | null) =>
    ts ? new Date(new Date(ts).getTime() + 72 * 3600 * 1000).toISOString() : null;

  return new Response(
    JSON.stringify({
      unread_leads: parseInt(unreadRow?.count ?? '0', 10),
      upcoming_bookings: parseInt(upcomingRow?.count ?? '0', 10),
      credit_balance: expert.credit_balance,
      composite_score: expert.composite_score,
      quality_tier: deriveQualityTier(expert.composite_score),
      month_stats: {
        leads_received: parseInt(monthLeads?.leads_received ?? '0', 10),
        leads_confirmed: parseInt(monthLeads?.leads_confirmed ?? '0', 10),
        leads_flagged: parseInt(monthLeads?.leads_flagged ?? '0', 10),
        bookings_total: parseInt(monthBookings?.bookings_total ?? '0', 10),
        bookings_completed: parseInt(monthBookings?.bookings_completed ?? '0', 10),
        conversions_declared: parseInt(monthLeads?.conversions_declared ?? '0', 10),
      },
      monthly_history: monthlyHistory,
      // E02S10/AC7: Milestone completion data for dashboard profile completion section
      milestones: {
        matchable: {
          unlocked: !!expert.milestone_matchable_at,
          unlocked_at: expert.milestone_matchable_at ?? null,
          available_at: milestoneAvailableAt(expert.milestone_matchable_at),
          credits: 4000,
        },
        bookable: {
          unlocked: !!expert.milestone_bookable_at,
          unlocked_at: expert.milestone_bookable_at ?? null,
          available_at: milestoneAvailableAt(expert.milestone_bookable_at),
          credits: 4000,
        },
        trust: {
          unlocked: !!expert.milestone_trust_at,
          unlocked_at: expert.milestone_trust_at ?? null,
          available_at: milestoneAvailableAt(expert.milestone_trust_at),
          credits: 2000,
        },
      },
    }),
    { status: 200, headers: JSON_HEADERS },
  );
}
