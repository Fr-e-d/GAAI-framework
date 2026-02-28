// ── Circuit breaker — E06S40 (AC8) ────────────────────────────────────────────
// KV-based cost accumulator with hourly window.
// Tracks extraction cost per hour. If the hourly total exceeds $10 (1000 cents),
// new extraction requests are rejected with 503 until the next hour.
//
// KV key: extract-cost:{ISO-hour}  (e.g. extract-cost:2026-02-28T14)
// KV TTL: 7200s (2 hours — ensures cleanup even if clock drifts)
// Auto-resume: next hour's counter starts at 0 (new key).

import type { Env } from '../types/env';

const CIRCUIT_BREAKER_THRESHOLD_CENTS = 1000; // $10.00

function hourKey(): string {
  // e.g. "extract-cost:2026-02-28T14"
  return `extract-cost:${new Date().toISOString().slice(0, 13)}`;
}

// ── isCircuitOpen ─────────────────────────────────────────────────────────────
// Returns true if accumulated cost this hour has exceeded the threshold.
// Returns false if KV is unavailable (fail open — prefer availability over strict cost control).

export async function isCircuitOpen(env: Env): Promise<boolean> {
  try {
    const raw = await env.SESSIONS.get(hourKey());
    if (!raw) return false;
    return parseFloat(raw) >= CIRCUIT_BREAKER_THRESHOLD_CENTS;
  } catch {
    return false; // fail open — circuit breaker must not block legitimate users on KV error
  }
}

// ── recordExtractionCost ──────────────────────────────────────────────────────
// Increments the hourly cost counter after a successful extraction.
// Uses EXTRACT_COST_CENTS env var (default 0.4 = $0.004 per extraction).
// Fire-and-forget safe: errors are swallowed so they never block the response.

export async function recordExtractionCost(env: Env): Promise<void> {
  try {
    const key = hourKey();
    const raw = await env.SESSIONS.get(key);
    const current = raw ? parseFloat(raw) : 0;
    const costCents = env.EXTRACT_COST_CENTS !== undefined ? parseFloat(env.EXTRACT_COST_CENTS) : 0.4;
    const next = current + costCents;
    await env.SESSIONS.put(key, next.toFixed(4), { expirationTtl: 7200 });
  } catch {
    // Never block the response for circuit breaker bookkeeping failures
  }
}
