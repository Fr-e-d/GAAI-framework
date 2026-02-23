import { z } from 'zod';
import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
<<<<<<< HEAD
import { createSql } from '../../lib/db';
import type { ExpertRow } from '../../types/db';
<<<<<<< HEAD
=======
import { createServiceClient } from '../../lib/supabase';
import { Json } from '../../types/database';
import { upsertExpertEmbedding, ExpertProfile } from '../../lib/vectorize';
>>>>>>> 902c0cd (feat(E06S21): Vectorize infrastructure + embedding pipeline)
=======
>>>>>>> 25fd870 (feat(E06S24): callibrate-matching Worker + Service Binding split)

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
  ctx: ExecutionContext
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

<<<<<<< HEAD
<<<<<<< HEAD
  return new Response(JSON.stringify(rows[0]), {
=======
  // AC4, AC7: Fire-and-forget re-embedding — failure must NOT block profile update
  const updatedExpert = data[0] as {
    profile?: ExpertProfile;
    rate_min?: number | null;
    rate_max?: number | null;
    availability?: string | null;
  };
  upsertExpertEmbedding(env, ctx, expertId, {
    profile: (updatedExpert.profile as ExpertProfile) ?? {},
    rate_min: updatedExpert.rate_min ?? null,
    rate_max: updatedExpert.rate_max ?? null,
    availability: updatedExpert.availability ?? null,
  });
=======
  // AC4 (E06S24): Fire-and-forget re-embedding via MATCHING_SERVICE — failure must NOT block profile update
  const updatedExpert = rows[0] as ExpertRow;
  if (env.MATCHING_SERVICE) {
    ctx.waitUntil(
      env.MATCHING_SERVICE.fetch(new Request('https://matching/embed', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          expert_id: expertId,
          profile: updatedExpert.profile ?? {},
          rate_min: updatedExpert.rate_min ?? null,
          rate_max: updatedExpert.rate_max ?? null,
          availability: updatedExpert.availability ?? null,
        }),
      })).catch((err) => console.error('profile: MATCHING_SERVICE embed failed', err))
    );
  }
>>>>>>> 25fd870 (feat(E06S24): callibrate-matching Worker + Service Binding split)

  return new Response(JSON.stringify(data[0]), {
>>>>>>> 902c0cd (feat(E06S21): Vectorize infrastructure + embedding pipeline)
    status: 200,
    headers: JSON_HEADERS,
  });
}
