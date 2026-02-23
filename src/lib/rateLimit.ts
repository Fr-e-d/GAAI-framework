import { Env } from '../types/env';

export async function checkRateLimit(
  request: Request,
  env: Env
): Promise<{ allowed: boolean }> {
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const { success } = await env.RATE_LIMITER.limit({ key: ip });
  return { allowed: success };
}
