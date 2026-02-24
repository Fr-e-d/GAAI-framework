import type { Env } from '../types/env';

// ── writeMatchingDataPoint ─────────────────────────────────────────────────
// AC2: blobs[0]=satellite_id, blobs[1]=endpoint
//      doubles[0]=latency_ms, doubles[1]=pool_size,
//      doubles[2]=top_score, doubles[3]=mean_score
// AC3: fire-and-forget — NOT awaited, wrapped in try/catch
// AC4: env.MATCHING_ANALYTICS is optional — ?. makes this a no-op when binding missing

export function writeMatchingDataPoint(
  env: Env,
  params: {
    endpoint: string;
    satelliteId: string;
    latencyMs: number;
    poolSize: number;
    topScore: number;
    meanScore: number;
  },
): void {
  try {
    env.MATCHING_ANALYTICS?.writeDataPoint({
      blobs: [params.satelliteId, params.endpoint],
      doubles: [params.latencyMs, params.poolSize, params.topScore, params.meanScore],
    });
  } catch {
    // no-op — analytics must never impact request path
  }
}
