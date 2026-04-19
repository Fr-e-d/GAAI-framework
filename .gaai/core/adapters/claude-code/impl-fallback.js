/**
 * impl-fallback.js
 *
 * Fallback orchestration for Epic E94 — universal nested-subprocess fallback.
 *
 * Called by the Delivery Orchestrator after resolveImplRouting() returns provider='secondary'.
 * When the nested subprocess fails for ANY reason, this module re-invokes Implementation
 * via the Task tool on primary with identical story context.
 *
 * Production callers MUST inject primaryFn. secondaryFn defaults to spawnNestedClaude.
 *
 * Obsolescence: Retire when spawnNestedClaude is retired (issue #38698).
 */

import { spawnNestedClaude } from './nested-claude-spawn.js';

// ---------------------------------------------------------------------------
// JSDoc typedefs
// ---------------------------------------------------------------------------

/**
 * @typedef {Object} FallbackResult
 * @property {boolean}              success           - true if Implementation (either path) succeeded
 * @property {string}               trace_id          - The shared trace_id across both attempt log lines
 * @property {boolean}              fallback_triggered - true if secondary failed and primary was invoked
 * @property {string|null}          fallback_reason   - exact error_reason string if fallback was triggered,
 *                                                      else null. NOTE: may be null if spawnResult.error_reason
 *                                                      was null on a failure result (contract violation in wrapper;
 *                                                      E94S06 must handle null fallback_reason).
 * @property {'primary'|'secondary'} provider_used   - which provider ultimately ran
 * @property {string|null}          error_reason      - final failure reason if success===false, else null
 */

/**
 * @typedef {Object} FallbackOptions
 * @property {'primary'|'secondary'} provider   - Routing decision from resolveImplRouting()
 * @property {string}  traceId                  - Provisional UUID from resolveImplRouting()
 * @property {string}  implPrompt               - The prompt for the Implementation Sub-Agent
 * @property {string}  implReportPath           - Expected path of the impl-report artefact
 * @property {string[]} [extraArgs]             - Extra argv forwarded to nested spawn (default: [])
 * @property {Function} [secondaryFn]           - Injected secondary fn (default: spawnNestedClaude)
 * @property {Function} primaryFn               - REQUIRED: invokes Implementation Sub-Agent on primary.
 *                                                No default — the production caller always injects this.
 *                                                Signature: async (implPrompt, implReportPath) => {success, error_reason}
 */

// ---------------------------------------------------------------------------
// Exported function
// ---------------------------------------------------------------------------

/**
 * Executes the Implementation phase with universal nested-subprocess fallback.
 *
 * If provider === 'primary': calls primaryFn directly, no secondary involved.
 * If provider === 'secondary': calls secondaryFn (nested subprocess). On success,
 * returns immediately. On any failure, universally falls back to primaryFn.
 *
 * Never throws on normal operation — all failure cases are returned as {success: false, ...}.
 * Only throws if primaryFn is not provided (programming error, fast-fail at call time).
 *
 * @param {FallbackOptions} opts
 * @returns {Promise<FallbackResult>}
 */
export async function executeImplWithFallback(opts) {
  const {
    provider,
    traceId,
    implPrompt,
    implReportPath,
    extraArgs = [],
    secondaryFn = spawnNestedClaude,
    primaryFn,
  } = opts;

  // Guard: primaryFn is required — fast-fail at call time (Risk Register item)
  if (typeof primaryFn !== 'function') {
    throw new Error('primaryFn is required');
  }

  // ---------------------------------------------------------------------------
  // Path 1: provider === 'primary'
  // Covers: untagged stories, impl_model: primary, ENV_MISSING pre-flight (E94S04 AC5)
  // secondaryFn is never called on this path (AC17 / AC2)
  // ---------------------------------------------------------------------------
  if (provider === 'primary') {
    const result = await primaryFn(implPrompt, implReportPath);
    return {
      success: result.success,
      trace_id: traceId,
      fallback_triggered: false,
      fallback_reason: null,
      provider_used: 'primary',
      error_reason: result.success ? null : (result.error_reason ?? 'PRIMARY_FAILED'),
    };
  }

  // ---------------------------------------------------------------------------
  // Path 2: provider === 'secondary'
  // Attempt nested subprocess once — no retry (AC3)
  // ---------------------------------------------------------------------------
  const spawnResult = await secondaryFn(implPrompt, implReportPath, extraArgs);

  // Replace provisional trace_id with wrapper's trace_id (AC5)
  // Both the secondary attempt log line and the primary fallback log line share this ID
  const sharedTraceId = spawnResult.trace_id ?? traceId;

  if (spawnResult.success) {
    // Secondary succeeded — no fallback (AC16)
    return {
      success: true,
      trace_id: sharedTraceId,
      fallback_triggered: false,
      fallback_reason: null,
      provider_used: 'secondary',
      error_reason: null,
    };
  }

  // ---------------------------------------------------------------------------
  // Secondary failed — universal fallback to primary (AC1, AC2, AC3, AC4)
  // Any error_reason class falls through here — no class-specific exemptions
  // ---------------------------------------------------------------------------
  const fallbackReason = spawnResult.error_reason; // exact class name verbatim (AC4)

  const primaryResult = await primaryFn(implPrompt, implReportPath);

  return {
    success: primaryResult.success,
    trace_id: sharedTraceId,         // same trace_id on both attempt log lines (AC5)
    fallback_triggered: true,
    fallback_reason: fallbackReason, // exact error class string (AC4); null if wrapper omitted it
    provider_used: 'primary',
    error_reason: primaryResult.success ? null : (primaryResult.error_reason ?? 'PRIMARY_FAILED'),
  };
  // Note: if primaryResult.success === false, we return {success: false} here.
  // The Delivery Orchestrator sees this and triggers the existing escalation path (AC6).
  // This function does NOT escalate internally — it is a pure async function returning a result.
  // No process.exit(), no backlog updates, no artefact writes (AC18, AC19).
}
