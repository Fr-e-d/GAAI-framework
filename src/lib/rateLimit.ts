import { Env } from '../types/env';

const WINDOW_SECONDS = 60;
const MAX_REQUESTS = 10;

export async function checkRateLimit(
  request: Request,
  env: Env
): Promise<{ allowed: boolean }> {
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const key = `rate_limit:register:${ip}`;

  const current = await env.RATE_LIMITING.get(key);

  if (current !== null && parseInt(current, 10) >= MAX_REQUESTS) {
    return { allowed: false };
  }

  const next = current === null ? 1 : parseInt(current, 10) + 1;
  await env.RATE_LIMITING.put(key, String(next), {
    expirationTtl: WINDOW_SECONDS,
  });

  return { allowed: true };
}
