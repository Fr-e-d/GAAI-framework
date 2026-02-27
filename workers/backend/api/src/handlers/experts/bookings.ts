// E06S38: GET /api/experts/:id/bookings — paginated booking list for expert dashboard

import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createSql } from '../../lib/db';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

const VALID_PERIODS = ['upcoming', 'past', 'all'] as const;
type BookingPeriod = (typeof VALID_PERIODS)[number];

function forbidden(): Response {
  return new Response(JSON.stringify({ error: 'Forbidden' }), {
    status: 403,
    headers: JSON_HEADERS,
  });
}

// ── GET /api/experts/:id/bookings ─────────────────────────────────────────────

export async function handleGetBookings(
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
  const periodParam = url.searchParams.get('period') ?? 'upcoming';

  if (!VALID_PERIODS.includes(periodParam as BookingPeriod)) {
    return new Response(
      JSON.stringify({ error: 'Validation failed', details: { period: 'must be one of: upcoming, past, all' } }),
      { status: 422, headers: JSON_HEADERS },
    );
  }

  const period = periodParam as BookingPeriod;
  const offset = (page - 1) * perPage;

  const sql = createSql(env);

  type BookingQueryRow = {
    id: string;
    start_at: string | null;
    end_at: string | null;
    status: string | null;
    meeting_url: string | null;
    cancel_reason: string | null;
    prospect_id: string | null;
    prospect_email: string | null;
    prospect_name: string | null;
    created_at: string | null;
    total_count: string;
  };

  let rows: BookingQueryRow[];

  if (period === 'upcoming') {
    rows = await sql<BookingQueryRow[]>`
      SELECT
        id, start_at, end_at, status, meeting_url, cancel_reason,
        prospect_id, prospect_email, prospect_name, created_at,
        COUNT(*) OVER() AS total_count
      FROM bookings
      WHERE expert_id = ${expertId}
        AND start_at > NOW()
        AND status NOT IN ('cancelled')
      ORDER BY start_at ASC
      LIMIT ${perPage} OFFSET ${offset}
    `;
  } else if (period === 'past') {
    rows = await sql<BookingQueryRow[]>`
      SELECT
        id, start_at, end_at, status, meeting_url, cancel_reason,
        prospect_id, prospect_email, prospect_name, created_at,
        COUNT(*) OVER() AS total_count
      FROM bookings
      WHERE expert_id = ${expertId}
        AND (start_at <= NOW() OR status = 'cancelled')
      ORDER BY start_at DESC
      LIMIT ${perPage} OFFSET ${offset}
    `;
  } else {
    // all
    rows = await sql<BookingQueryRow[]>`
      SELECT
        id, start_at, end_at, status, meeting_url, cancel_reason,
        prospect_id, prospect_email, prospect_name, created_at,
        COUNT(*) OVER() AS total_count
      FROM bookings
      WHERE expert_id = ${expertId}
      ORDER BY start_at ASC
      LIMIT ${perPage} OFFSET ${offset}
    `;
  }

  const total = rows.length > 0 ? parseInt(rows[0]!.total_count, 10) : 0;

  const bookings = rows.map((r) => ({
    id: r.id,
    starts_at: r.start_at,
    ends_at: r.end_at,
    status: r.status,
    meeting_url: r.meeting_url,
    cancel_reason: r.cancel_reason,
    prospect: r.prospect_id
      ? { id: r.prospect_id, email: r.prospect_email, name: r.prospect_name }
      : null,
    created_at: r.created_at,
  }));

  return new Response(
    JSON.stringify({ bookings, total, page, per_page: perPage }),
    { status: 200, headers: JSON_HEADERS },
  );
}
