import { z } from 'zod';
import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createServiceClient } from '../../lib/supabase';
import { Json } from '../../types/database';
import { upsertExpertEmbedding, ExpertProfile } from '../../lib/vectorize';

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

function forbidden(): Response {
  return new Response(JSON.stringify({ error: 'Forbidden' }), {
    status: 403,
    headers: { 'Content-Type': 'application/json' },
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

  const supabase = createServiceClient(env);
  const { data, error } = await supabase
    .from('experts')
    .select('*')
    .eq('id', expertId)
    .single();

  if (error || !data) {
    if (error?.code === 'PGRST116') {
      return new Response(JSON.stringify({ error: 'Expert not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    return new Response(
      JSON.stringify({ error: 'Failed to fetch profile', details: { message: error?.message } }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
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
      headers: { 'Content-Type': 'application/json' },
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
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  const { display_name, headline, bio, rate_min, rate_max, availability, profile, preferences } =
    parsed.data;

  const supabase = createServiceClient(env);

  // AC8: JSONB merge via RPC
  const { data, error } = await supabase.rpc('merge_expert_profile', {
    p_id: expertId,
    ...(display_name !== undefined && { p_display_name: display_name }),
    ...(headline !== undefined && { p_headline: headline }),
    ...(bio !== undefined && { p_bio: bio }),
    ...(rate_min !== undefined && { p_rate_min: rate_min }),
    ...(rate_max !== undefined && { p_rate_max: rate_max }),
    ...(availability !== undefined && { p_availability: availability }),
    ...(profile !== undefined && { p_profile: profile as Json }),
    ...(preferences !== undefined && { p_preferences: preferences as Json }),
  } as { p_id: string });

  if (error) {
    return new Response(
      JSON.stringify({ error: 'Failed to update profile', details: { message: error.message } }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  if (!data || data.length === 0) {
    return new Response(JSON.stringify({ error: 'Expert not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

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

  return new Response(JSON.stringify(data[0]), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
