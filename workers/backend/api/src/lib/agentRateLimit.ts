// E06S43: Per-API-key rate limiting for agent endpoints

export type AgentEndpoint = 'extract' | 'match' | 'reveal' | 'booking';

const LIMITS: Record<AgentEndpoint, { count: number; windowSecs: number }> = {
  extract: { count: 10, windowSecs: 60 },
  match:   { count: 5,  windowSecs: 60 },
  reveal:  { count: 3,  windowSecs: 3600 },
  booking: { count: 3,  windowSecs: 3600 },
};

/**
 * Check and increment the rate limit for an agent API key + endpoint.
 * Returns { allowed: true } if within limit, { allowed: false, retryAfter: N } if exceeded.
 * Fails open on KV errors.
 */
export async function checkAgentRateLimit(
  sessions: KVNamespace,
  keyHash: string,
  endpoint: AgentEndpoint,
): Promise<{ allowed: boolean; retryAfter?: number }> {
  const { count: limit, windowSecs } = LIMITS[endpoint];
  const windowIndex = Math.floor(Date.now() / (windowSecs * 1000));
  const kvKey = `agent-rate:${keyHash}:${endpoint}:${windowIndex}`;

  try {
    const current = await sessions.get(kvKey);
    const count = current ? parseInt(current, 10) : 0;

    if (count >= limit) {
      const windowRemainingMs = (windowIndex + 1) * windowSecs * 1000 - Date.now();
      const retryAfter = Math.ceil(windowRemainingMs / 1000);
      return { allowed: false, retryAfter };
    }

    await sessions.put(kvKey, String(count + 1), { expirationTtl: windowSecs * 2 });
    return { allowed: true };
  } catch {
    // Fail open on KV errors — do not block requests due to rate limit infrastructure issues
    return { allowed: true };
  }
}
