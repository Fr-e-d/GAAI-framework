import { z } from 'zod';
import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createSql } from '../../lib/db';
import { notifyExpertPoolDO } from '../../durable-objects/expertPoolDO';
import type { ExpertRow } from '../../types/db';
import { captureEvent } from '../../lib/posthog';

const VALID_AVAILABILITY = ['available', 'limited', 'unavailable'] as const;

const PatchProfileSchema = z.object({
  display_name: z.string().min(1).max(100).optional(),
  headline: z.string().max(200).optional(),
  bio: z.string().max(2000).optional(),
  rate_min: z.number().int().positive().optional(),
  rate_max: z.number().int().positive().optional(),
  availability: z.enum(VALID_AVAILABILITY).optional(),
  profile: z.record(z.string(), z.unknown()).optional(),
  preferences: z.record(z.string(), z.unknown()).optional(),
});

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function forbidden(): Response {
  return new Response(JSON.stringify({ error: 'Forbidden' }), {
    status: 403,
    headers: JSON_HEADERS,
  });
}

export async function handleGetProfile(
  _request: Request,
  env: Env,
  user: AuthUser,
  expertId: string
): Promise<Response> {
  // AC7: Own profile only
  if (user.id !== expertId) {
    return forbidden();
  }

  const sql = createSql(env);
  const [data] = await sql<ExpertRow[]>`SELECT * FROM experts WHERE id = ${expertId}`;

  if (!data) {
    return new Response(JSON.stringify({ error: 'Expert not found' }), {
      status: 404,
      headers: JSON_HEADERS,
    });
  }

  return new Response(JSON.stringify(data), {
    status: 200,
    headers: JSON_HEADERS,
  });
}

export async function handlePatchProfile(
  request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  // AC7 / AC8: Own profile only
  if (user.id !== expertId) {
    return forbidden();
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: JSON_HEADERS,
    });
  }

  // AC9: Validate availability enum + other fields
  const parsed = PatchProfileSchema.safeParse(body);
  if (!parsed.success) {
    return new Response(
      JSON.stringify({
        error: 'Validation failed',
        details: parsed.error.flatten().fieldErrors,
      }),
      {
        status: 422,
        headers: JSON_HEADERS,
      }
    );
  }

  const { display_name, headline, bio, rate_min, rate_max, availability, profile, preferences } =
    parsed.data;

  const sql = createSql(env);

  // AC8: JSONB merge via RPC (postgres.js named-param call)
  const rows = await sql<ExpertRow[]>`
    SELECT * FROM merge_expert_profile(
      p_id := ${expertId},
      p_display_name := ${display_name ?? null},
      p_headline := ${headline ?? null},
      p_bio := ${bio ?? null},
      p_rate_min := ${rate_min ?? null},
      p_rate_max := ${rate_max ?? null},
      p_availability := ${availability ?? null},
      p_profile := ${profile ? JSON.stringify(profile) : null}::jsonb,
      p_preferences := ${preferences ? JSON.stringify(preferences) : null}::jsonb
    )`;

  if (!rows || rows.length === 0) {
    return new Response(JSON.stringify({ error: 'Expert not found' }), {
      status: 404,
      headers: JSON_HEADERS,
    });
  }

  const updated = rows[0] as ExpertRow;

  // AC5 (E06S25): Notify ExpertPoolDO — fire-and-forget, must NOT block response
  notifyExpertPoolDO(env, ctx, {
    id: expertId,
    profile: (updated.profile as Record<string, unknown>) ?? {},
    preferences: (updated.preferences as Record<string, unknown>) ?? {},
    rate_min: updated.rate_min ?? null,
    rate_max: updated.rate_max ?? null,
    composite_score: updated.composite_score ?? null,
    total_leads: 0,
    availability: updated.availability ?? null,
  });

  // AC4 (E06S24): Fire-and-forget re-embedding via MATCHING_SERVICE — failure must NOT block profile update
  if (env.MATCHING_SERVICE) {
    ctx.waitUntil(
      env.MATCHING_SERVICE.fetch(new Request('https://matching/embed', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          expert_id: expertId,
          profile: updated.profile ?? {},
          rate_min: updated.rate_min ?? null,
          rate_max: updated.rate_max ?? null,
          availability: updated.availability ?? null,
        }),
      })).catch((err) => console.error('profile: MATCHING_SERVICE embed failed', err))
    );
  }

  const fieldsUpdated: string[] = [];
  if (display_name !== undefined) fieldsUpdated.push('display_name');
  if (headline !== undefined) fieldsUpdated.push('headline');
  if (bio !== undefined) fieldsUpdated.push('bio');
  if (rate_min !== undefined) fieldsUpdated.push('rate_min');
  if (rate_max !== undefined) fieldsUpdated.push('rate_max');
  if (availability !== undefined) fieldsUpdated.push('availability');
  if (profile !== undefined) fieldsUpdated.push('profile');
  if (preferences !== undefined) fieldsUpdated.push('preferences');

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `expert:${expertId}`,
    event: 'expert.profile_updated',
    properties: { fields_updated: fieldsUpdated },
  }));

  return new Response(JSON.stringify(updated), {
    status: 200,
    headers: JSON_HEADERS,
  });
}
