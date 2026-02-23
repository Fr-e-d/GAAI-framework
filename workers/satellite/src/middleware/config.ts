import type { Env } from '../types/env';
import type { SatelliteConfig } from '../types/config';

const KV_KEY_PREFIX = 'satellite:config:';
const KV_TTL_SECONDS = 3600;

export async function resolveConfig(
  hostname: string,
  env: Env
): Promise<SatelliteConfig | null> {
  // Step 1: KV cache lookup
  const kvKey = `${KV_KEY_PREFIX}${hostname}`;
  const cached = await env.CONFIG_CACHE.get<SatelliteConfig>(kvKey, 'json');
  if (cached) {
    return cached;
  }

  // Step 2: Supabase fallback on KV miss
  let config: SatelliteConfig | null = null;
  try {
    const url = `${env.SUPABASE_URL}/rest/v1/satellite_configs?domain=eq.${encodeURIComponent(hostname)}&active=eq.true&limit=1`;
    const response = await fetch(url, {
      headers: {
        apikey: env.SUPABASE_ANON_KEY,
        Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      },
    });

    if (response.ok) {
      const rows = (await response.json()) as SatelliteConfig[];
      if (rows.length > 0) {
        config = rows[0]!;
      }
    }
  } catch {
    // Supabase unreachable — fail-safe to null (302 redirect)
    return null;
  }

  // Step 3: Write back to KV on DB hit (non-blocking)
  if (config) {
    try {
      await env.CONFIG_CACHE.put(kvKey, JSON.stringify(config), {
        expirationTtl: KV_TTL_SECONDS,
      });
    } catch {
      // KV write failure is non-fatal — config already resolved from DB
    }
  }

  return config;
}

