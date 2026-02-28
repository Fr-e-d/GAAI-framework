// E02S12 AC18: Direct link dashboard endpoints (expert-authenticated)
// GET /api/experts/:id/direct-link — returns direct_link_url, quota stats, recent submissions
// PATCH /api/experts/:id/direct-link/rotate — rotates nonce, invalidates old links, returns new URL

import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { signDirectLinkToken } from '../../lib/directLinkToken';
import type { AuthUser } from '../../middleware/auth';
import type { BookingRow } from '../../types/db';

const JSON_HEADERS = { 'Content-Type': 'application/json' };
const DIRECT_BOOKING_QUOTA = 100;

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}

function buildDirectLinkUrl(slug: string, token: string): string {
  return `https://callibrate.io/book/${slug}?t=${token}`;
}

// GET /api/experts/:id/direct-link
export async function handleGetDirectLinkInfo(
  request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
): Promise<Response> {
  // Authorization: expert can only access their own data
  if (user.id !== expertId) {
    return json({ error: 'Forbidden' }, 403);
  }

  const sql = createSql(env);
  try {
    const [expert] = await sql<{
      id: string;
      direct_link_nonce: string;
      direct_submissions_this_month: number;
      direct_submissions_reset_at: string;
    }[]>`
      SELECT id, direct_link_nonce, direct_submissions_this_month, direct_submissions_reset_at
      FROM experts
      WHERE id = ${expertId}
    `;

    if (!expert) {
      return json({ error: 'Expert not found' }, 404);
    }

    const slug = `exp-${expert.id.substring(0, 8)}`;

    // Compute current direct link URL
    let directLinkUrl: string | null = null;
    try {
      const token = await signDirectLinkToken(expert.id, expert.direct_link_nonce, env.DIRECT_LINK_SECRET);
      directLinkUrl = buildDirectLinkUrl(slug, token);
    } catch {
      directLinkUrl = null;
    }

    // Fetch recent 3 direct submissions
    const recentSubmissions = await sql<
      Pick<BookingRow, 'id' | 'prospect_name' | 'prospect_email' | 'created_at' | 'status'>[]
    >`
      SELECT id, prospect_name, prospect_email, created_at, status
      FROM bookings
      WHERE expert_id = ${expertId}
        AND lead_source = 'direct'
      ORDER BY created_at DESC
      LIMIT 3
    `;

    const nextResetAt = new Date(expert.direct_submissions_reset_at);
    // Reset is on the 1st of the following month
    nextResetAt.setMonth(nextResetAt.getMonth() + 1);
    nextResetAt.setDate(1);
    nextResetAt.setHours(0, 0, 0, 0);

    return json({
      direct_link_url: directLinkUrl,
      quota: {
        used: expert.direct_submissions_this_month,
        limit: DIRECT_BOOKING_QUOTA,
        remaining: Math.max(0, DIRECT_BOOKING_QUOTA - expert.direct_submissions_this_month),
        resets_at: nextResetAt.toISOString(),
      },
      recent_submissions: recentSubmissions.map((b) => ({
        booking_id: b.id,
        prospect_name: b.prospect_name,
        prospect_email: b.prospect_email,
        submitted_at: b.created_at,
        status: b.status,
      })),
    });
  } finally {
    await sql.end();
  }
}

// PATCH /api/experts/:id/direct-link/rotate
export async function handleRotateDirectLinkToken(
  request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
): Promise<Response> {
  // Authorization: expert can only rotate their own link
  if (user.id !== expertId) {
    return json({ error: 'Forbidden' }, 403);
  }

  const sql = createSql(env);
  try {
    const newNonce = crypto.randomUUID();

    const [expert] = await sql<{ id: string }[]>`
      UPDATE experts
      SET direct_link_nonce = ${newNonce}
      WHERE id = ${expertId}
      RETURNING id
    `;

    if (!expert) {
      return json({ error: 'Expert not found' }, 404);
    }

    const slug = `exp-${expertId.substring(0, 8)}`;
    const token = await signDirectLinkToken(expertId, newNonce, env.DIRECT_LINK_SECRET);
    const newDirectLinkUrl = buildDirectLinkUrl(slug, token);

    return json({
      direct_link_url: newDirectLinkUrl,
      message: 'Direct link token rotated. All previous links are now invalid.',
    });
  } finally {
    await sql.end();
  }
}
