import { z } from 'zod';
import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createSql } from '../../lib/db';
import { checkRateLimit } from '../../lib/rateLimit';
import type { ExpertRow } from '../../types/db';

const RegisterSchema = z.object({
  display_name: z.string().min(1, 'display_name is required').max(100),
  headline: z.string().max(200).optional(),
  bio: z.string().max(2000).optional(),
  rate_min: z.number().int().positive().optional(),
  rate_max: z.number().int().positive().optional(),
});

export async function handleRegister(
  request: Request,
  env: Env,
  user: AuthUser
): Promise<Response> {
  // AC6: Rate limiting
  const rateCheck = await checkRateLimit(request, env);
  if (!rateCheck.allowed) {
    return new Response(JSON.stringify({ error: 'Too Many Requests' }), {
      status: 429,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Parse body
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // AC3: Zod validation
  const parsed = RegisterSchema.safeParse(body);
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

  const { display_name, headline, bio, rate_min, rate_max } = parsed.data;
  const sql = createSql(env);

  // Insert expert row (Google Calendar OAuth layer wired in E06S10 — DEC-41)
  let expert: Pick<ExpertRow, 'id' | 'display_name'>;
  try {
    const [row] = await sql<Pick<ExpertRow, 'id' | 'display_name'>[]>`
      INSERT INTO experts (id, display_name, headline, bio, rate_min, rate_max)
      VALUES (${user.id}, ${display_name}, ${headline ?? null}, ${bio ?? null}, ${rate_min ?? null}, ${rate_max ?? null})
      RETURNING id, display_name`;
    if (!row) throw new Error('Insert failed');
    expert = row;
  } catch (err) {
    // AC4: Duplicate detection — Postgres unique violation
    if ((err as { code?: string }).code === '23505') {
      return new Response(
        JSON.stringify({ error: 'Expert already registered' }),
        {
          status: 409,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }
    return new Response(
      JSON.stringify({ error: 'Registration failed', details: { message: String(err) } }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  // AC5: Push queue message to email-notifications (email sourced from JWT)
  await env.EMAIL_NOTIFICATIONS.send({
    type: 'expert.registered',
    expert_id: user.id,
    email: user.email ?? '',
  });

  // Return 201
  return new Response(
    JSON.stringify({
      expert_id: expert.id,
      display_name: expert.display_name,
    }),
    {
      status: 201,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}
