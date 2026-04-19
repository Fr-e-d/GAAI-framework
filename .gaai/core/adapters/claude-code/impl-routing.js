/**
 * impl-routing.js
 *
 * Routing decision helper for the Implementation phase of the GAAI Delivery Loop.
 * Evaluates impl_model tag + env vars to determine which provider path to use.
 *
 * Called once per story at Implementation phase entry. Result is stable for the
 * entire phase — mid-phase re-evaluation is forbidden (E94S04 AC7).
 */

import { randomUUID } from 'node:crypto';

/**
 * @typedef {Object} RoutingDecision
 * @property {'primary'|'secondary'} provider   - Which provider path to use
 * @property {string}                traceId    - UUID for this story's observability chain
 * @property {string|null}           implModelTag - Raw value of impl_model field, or null if absent
 * @property {string[]|null}         envMissing - List of missing env var names (AC5), or null
 * @property {string|null}           reason     - 'secondary_but_env_missing' | null
 */

/**
 * Resolves the Implementation phase routing decision.
 *
 * @param {string|null|undefined} implModelTag - Value of the story's impl_model field
 * @returns {RoutingDecision}
 */
export function resolveImplRouting(implModelTag) {
  const traceId = randomUUID();
  const tag = implModelTag ?? null;

  if (tag !== 'secondary') {
    return { provider: 'primary', traceId, implModelTag: tag, envMissing: null, reason: null };
  }

  // Pre-flight env check — never attempt secondary if any required var is missing or empty
  const missing = [];
  if (!process.env.GAAI_IMPL_BASE_URL?.trim())    missing.push('GAAI_IMPL_BASE_URL');
  if (!process.env.GAAI_IMPL_AUTH_TOKEN?.trim())  missing.push('GAAI_IMPL_AUTH_TOKEN');
  if (!process.env.GAAI_IMPL_MODEL?.trim())       missing.push('GAAI_IMPL_MODEL');

  if (missing.length > 0) {
    console.warn(
      `IMPL_ROUTING_ENV_MISSING: expected GAAI_IMPL_BASE_URL|AUTH_TOKEN|MODEL, got: ${missing.join(', ')}`
    );
    return { provider: 'primary', traceId, implModelTag: tag, envMissing: missing, reason: 'secondary_but_env_missing' };
  }

  return { provider: 'secondary', traceId, implModelTag: tag, envMissing: null, reason: null };
}
