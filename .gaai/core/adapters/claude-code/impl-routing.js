/**
 * impl-routing.js
 *
 * Routing decision helper for the Implementation phase of the GAAI Delivery Loop.
 * Evaluates impl_model tag + env vars to determine which provider path to use.
 *
 * Called once per story at Implementation phase entry. Result is stable for the
 * entire phase — mid-phase re-evaluation is forbidden (E94S04 AC7).
 *
 * Default routing (DEC-72, 2026-04-20, amends E94 D-0):
 *   - tag === 'primary'           → primary (explicit opt-out)
 *   - tag === 'secondary' + env   → secondary
 *   - tag === 'secondary' + !env  → primary (warn, reason='secondary_but_env_missing')
 *   - tag absent + env            → secondary (NEW default — was primary under E94 D-0)
 *   - tag absent + !env           → primary (preserves OSS non-regression)
 */

import { randomUUID } from 'node:crypto';

const REQUIRED_ENV = ['GAAI_IMPL_BASE_URL', 'GAAI_IMPL_AUTH_TOKEN', 'GAAI_IMPL_MODEL'];

/**
 * @typedef {Object} RoutingDecision
 * @property {'primary'|'secondary'} provider   - Which provider path to use
 * @property {string}                traceId    - UUID for this story's observability chain
 * @property {string|null}           implModelTag - Raw value of impl_model field, or null if absent
 * @property {string[]|null}         envMissing - List of missing env var names (AC5), or null
 * @property {string|null}           reason     - 'secondary_but_env_missing' | null
 */

function checkEnv() {
  return REQUIRED_ENV.filter(name => !process.env[name]?.trim());
}

/**
 * Resolves the Implementation phase routing decision.
 *
 * @param {string|null|undefined} implModelTag - Value of the story's impl_model field
 * @returns {RoutingDecision}
 */
export function resolveImplRouting(implModelTag) {
  const traceId = randomUUID();
  const tag = implModelTag ?? null;

  // Explicit opt-out — always routes primary, regardless of env (DEC-72)
  if (tag === 'primary') {
    return { provider: 'primary', traceId, implModelTag: tag, envMissing: null, reason: null };
  }

  // Env pre-flight gate — shared by explicit 'secondary' and env-driven default (DEC-72)
  const missing = checkEnv();

  if (missing.length > 0) {
    // Env missing: stories without env cannot route secondary.
    // - tag === 'secondary' → warn + fallback (existing E94 behavior)
    // - tag absent → silent primary (preserves OSS non-regression — DEC-72)
    if (tag === 'secondary') {
      console.warn(
        `IMPL_ROUTING_ENV_MISSING: expected ${REQUIRED_ENV.join('|')}, got: ${missing.join(', ')}`
      );
      return { provider: 'primary', traceId, implModelTag: tag, envMissing: missing, reason: 'secondary_but_env_missing' };
    }
    return { provider: 'primary', traceId, implModelTag: tag, envMissing: null, reason: null };
  }

  // Env configured: route secondary (tag === 'secondary' OR tag absent → new default per DEC-72)
  return { provider: 'secondary', traceId, implModelTag: tag, envMissing: null, reason: null };
}
