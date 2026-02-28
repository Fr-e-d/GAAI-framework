// E02S12 AC7: GET /api/experts/internal/:slug
// Internal Worker-to-Worker endpoint — called by Landing Worker to render /book/:slug.
// Authorization: Bearer {INTERNAL_API_KEY}
// Returns full expert data (non-anonymized) + attribution ('direct' | 'callibrate').
// Attribution is determined by verifying the ?t= HMAC token in the request.

import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { deriveQualityTier } from '../../lib/qualityTier';
import { signDirectLinkToken, verifyDirectLinkToken } from '../../lib/directLinkToken';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

export async function handleGetInternalExpertBySlug(
  request: Request,
  env: Env,
  slug: string,
): Promise<Response> {
  // Authorization: Bearer {INTERNAL_API_KEY}
  const authHeader = request.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ') || authHeader.slice(7) !== env.INTERNAL_API_KEY) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: JSON_HEADERS,
    });
  }

  // Validate slug format
  if (!slug.startsWith('exp-') || slug.length < 12) {
    return new Response(JSON.stringify({ error: 'Expert not found' }), {
      status: 404,
      headers: JSON_HEADERS,
    });
  }

  const shortHash = slug.substring(4);
  const sql = createSql(env);

  const [row] = await sql<{
    id: string;
    display_name: string | null;
    headline: string | null;
    bio: string | null;
    profile: unknown;
    rate_min: number | null;
    rate_max: number | null;
    composite_score: number | null;
    availability: string | null;
    direct_link_nonce: string;
    direct_submissions_this_month: number;
  }[]>`
    SELECT
      id, display_name, headline, bio, profile,
      rate_min, rate_max, composite_score, availability,
      direct_link_nonce, direct_submissions_this_month
    FROM experts
    WHERE LEFT(id::text, 8) = ${shortHash}
  `;

  if (!row) {
    return new Response(JSON.stringify({ error: 'Expert not found' }), {
      status: 404,
      headers: JSON_HEADERS,
    });
  }

  const profile = (row.profile ?? {}) as {
    skills?: string[];
    languages?: string[];
    portfolio_links?: string[];
    industries?: string[];
    completed_projects?: number;
  };

  // Compute current direct_link_token (for displaying in dashboard / passing back)
  let directLinkToken: string | null = null;
  try {
    directLinkToken = await signDirectLinkToken(row.id, row.direct_link_nonce, env.DIRECT_LINK_SECRET);
  } catch {
    directLinkToken = null;
  }

  // Determine attribution by validating the ?t= query parameter
  const url = new URL(request.url);
  const tParam = url.searchParams.get('t') ?? '';
  let attribution: 'direct' | 'callibrate' = 'callibrate';
  if (tParam && env.DIRECT_LINK_SECRET) {
    try {
      const valid = await verifyDirectLinkToken(tParam, row.id, row.direct_link_nonce, env.DIRECT_LINK_SECRET);
      if (valid) {
        attribution = 'direct';
      }
    } catch {
      attribution = 'callibrate';
    }
  }

  const result = {
    id: row.id,
    slug,
    display_name: row.display_name,
    headline: row.headline,
    bio: row.bio,
    skills: profile.skills ?? [],
    languages: profile.languages ?? [],
    portfolio_links: profile.portfolio_links ?? [],
    rate_min: row.rate_min,
    rate_max: row.rate_max,
    quality_tier: deriveQualityTier(row.composite_score),
    availability: row.availability,
    direct_link_token: directLinkToken,
    direct_submissions_this_month: row.direct_submissions_this_month,
    attribution,
  };

  return new Response(JSON.stringify(result), { status: 200, headers: JSON_HEADERS });
}
