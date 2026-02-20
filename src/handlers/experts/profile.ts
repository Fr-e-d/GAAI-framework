import { z } from 'zod';
import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createServiceClient } from '../../lib/supabase';
import { Json } from '../../types/database';

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
  expertId: string
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
    p_display_name: display_name ?? null,
    p_headline: headline ?? null,
    p_bio: bio ?? null,
    p_rate_min: rate_min ?? null,
    p_rate_max: rate_max ?? null,
    p_availability: availability ?? null,
    p_profile: (profile as Json) ?? null,
    p_preferences: (preferences as Json) ?? null,
  });

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

  return new Response(JSON.stringify(data[0]), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
