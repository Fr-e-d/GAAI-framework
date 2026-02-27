// E06S38: GET /api/experts/public — anonymized public expert listing
// E06S38: GET /api/experts/public/:slug — anonymized expert detail

import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { deriveQualityTier } from '../../lib/qualityTier';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

// ── GET /api/experts/public ───────────────────────────────────────────────────

export async function handleGetPublicExperts(
  request: Request,
  env: Env,
): Promise<Response> {
  // Rate limiting (AC16)
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const { success } = await env.RATE_LIMITER.limit({ key: `public:${ip}` });
  if (!success) {
    return new Response(JSON.stringify({ error: 'Too Many Requests' }), {
      status: 429,
      headers: JSON_HEADERS,
    });
  }

  const url = new URL(request.url);
  const page = Math.max(1, parseInt(url.searchParams.get('page') ?? '1', 10) || 1);
  const perPage = Math.min(Math.max(1, parseInt(url.searchParams.get('per_page') ?? '12', 10) || 12), 50);
  const vertical = url.searchParams.get('vertical') ?? null;
  const skillsParam = url.searchParams.get('skills') ?? null;
  const offset = (page - 1) * perPage;

  const sql = createSql(env);

  const rows = await sql<{
    id: string;
    headline: string | null;
    profile: unknown;
    rate_min: number | null;
    rate_max: number | null;
    composite_score: number | null;
    availability: string | null;
    outcome_tags: string[] | null;
    bio: string | null;
    total_count: string;
  }[]>`
    SELECT
      id,
      headline,
      profile,
      rate_min,
      rate_max,
      composite_score,
      availability,
      outcome_tags,
      bio,
      COUNT(*) OVER() AS total_count
    FROM experts
    WHERE availability != 'unavailable'
      AND (${vertical} IS NULL OR profile->>'vertical' = ${vertical})
    ORDER BY composite_score DESC NULLS LAST
    LIMIT ${perPage} OFFSET ${offset}
  `;

  const total = rows.length > 0 ? parseInt(rows[0]!.total_count, 10) : 0;

  // Optional: filter by skills in TypeScript after fetch (profile JSONB, MVP approach)
  type ExpertQueryRow = { id: string; headline: string | null; profile: unknown; rate_min: number | null; rate_max: number | null; composite_score: number | null; availability: string | null; outcome_tags: string[] | null; bio: string | null; total_count: string };
  let filtered: ExpertQueryRow[] = Array.from(rows);
  if (skillsParam) {
    const requestedSkills = skillsParam.split(',').map((s) => s.trim().toLowerCase());
    filtered = filtered.filter((r) => {
      const profile = (r.profile ?? {}) as { skills?: string[] };
      const expertSkills = (profile.skills ?? []).map((s) => s.toLowerCase());
      return requestedSkills.some((rs) => expertSkills.includes(rs));
    });
  }

  const experts = filtered.map((r) => {
    const profile = (r.profile ?? {}) as {
      skills?: string[];
      industries?: string[];
      languages?: string[];
      completed_projects?: number;
    };
    return {
      slug: `exp-${r.id.substring(0, 8)}`,
      headline: r.headline,
      skills: profile.skills ?? [],
      industries: profile.industries ?? [],
      rate_min: r.rate_min,
      rate_max: r.rate_max,
      composite_score: r.composite_score,
      quality_tier: deriveQualityTier(r.composite_score),
      completed_projects: profile.completed_projects ?? 0,
      languages: profile.languages ?? [],
    };
  });

  return new Response(
    JSON.stringify({ experts, total, page, per_page: perPage }),
    { status: 200, headers: JSON_HEADERS },
  );
}

// ── GET /api/experts/public/:slug ─────────────────────────────────────────────

export async function handleGetPublicExpertBySlug(
  request: Request,
  env: Env,
  slug: string,
): Promise<Response> {
  // Rate limiting (AC16)
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const { success } = await env.RATE_LIMITER.limit({ key: `public:${ip}` });
  if (!success) {
    return new Response(JSON.stringify({ error: 'Too Many Requests' }), {
      status: 429,
      headers: JSON_HEADERS,
    });
  }

  // Validate slug format: must start with 'exp-' followed by 8+ hex chars
  if (!slug.startsWith('exp-') || slug.length < 12) {
    return new Response(JSON.stringify({ error: 'Expert not found' }), {
      status: 404,
      headers: JSON_HEADERS,
    });
  }

  const shortHash = slug.substring(4); // first 8 chars of UUID
  const sql = createSql(env);

  const [row] = await sql<{
    id: string;
    headline: string | null;
    profile: unknown;
    rate_min: number | null;
    rate_max: number | null;
    composite_score: number | null;
    availability: string | null;
    outcome_tags: string[] | null;
    bio: string | null;
  }[]>`
    SELECT id, headline, profile, rate_min, rate_max, composite_score, availability, outcome_tags, bio
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
    industries?: string[];
    languages?: string[];
    completed_projects?: number;
  };

  const bioExcerpt = row.bio ? row.bio.substring(0, 200) : null;

  const detail = {
    slug: `exp-${row.id.substring(0, 8)}`,
    headline: row.headline,
    skills: profile.skills ?? [],
    industries: profile.industries ?? [],
    rate_min: row.rate_min,
    rate_max: row.rate_max,
    composite_score: row.composite_score,
    quality_tier: deriveQualityTier(row.composite_score),
    completed_projects: profile.completed_projects ?? 0,
    languages: profile.languages ?? [],
    bio_excerpt: bioExcerpt,
    availability_status: row.availability,
    outcome_tags: row.outcome_tags ?? [],
  };

  return new Response(JSON.stringify(detail), { status: 200, headers: JSON_HEADERS });
}
