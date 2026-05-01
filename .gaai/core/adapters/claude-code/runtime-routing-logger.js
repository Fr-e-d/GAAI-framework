/**
 * runtime-routing-logger.js
 *
 * Structured append-only JSONL logger for per-phase provider + duration + fallback reason.
 *
 * // Example: jq 'select(.fallback_reason != null)' runtime-routing.jsonl
 *
 * Privacy review: schema contains only operational telemetry, no PII.
 *
 * V1 is info-only; log rotation deferred to V2 once size signal justifies.
 */

import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// ---------------------------------------------------------------------------
// Default log path — resolved from this file's dir up to repo root.
// File lives at <repo>/.gaai/core/adapters/claude-code/, so REPO_ROOT is 4 levels up.
// ---------------------------------------------------------------------------

const __filename = fileURLToPath(import.meta.url);
const __dirname  = dirname(__filename);
const REPO_ROOT  = join(__dirname, '..', '..', '..', '..');

const DEFAULT_LOG_PATH = join(
  REPO_ROOT,
  '.gaai', 'project', 'contexts', 'logs', 'runtime-routing.jsonl'
);

// ---------------------------------------------------------------------------
// Log path injection seam (for tests only)
// ---------------------------------------------------------------------------

let _logPath = DEFAULT_LOG_PATH;

/** @internal — for tests only */
export function _setLogPath(path) { _logPath = path; }

/** @internal — for tests only */
export function _resetLogPath() { _logPath = DEFAULT_LOG_PATH; }

// ---------------------------------------------------------------------------
// Token-like value detection heuristic (AC11, AC6)
// ---------------------------------------------------------------------------

const TOKEN_RE = /Bearer\s+|sk-[a-zA-Z0-9]{20,}|Authorization:/i;

const REQUIRED_FIELDS = [
  'trace_id', 'story_id', 'phase', 'provider',
  'model', 'duration_ms', 'fallback_reason', 'impl_model_tag',
];

// ---------------------------------------------------------------------------
// Public export: logPhase
// ---------------------------------------------------------------------------

/**
 * Appends one JSONL line to the routing log.
 *
 * Optional secondary-mode telemetry fields (E131S08 / AC1 / DEC-65):
 *   context_size_at_spawn   — cumulative input_tokens from the last assistant event (integer)
 *   compact_events_count    — count of compact_boundary system events (integer)
 *   retry_429_count         — count of api_retry events with error_status=429 (integer)
 *   nested_session_completed — true iff stop_reason ∈ {end_turn, stop_sequence} (boolean)
 * These fields are integers/boolean only — the token-detection guard cannot trigger on them.
 * When absent, the field is omitted from the log record (not null, not zero — absent per AC2).
 *
 * @param {{ trace_id: string, story_id: string, phase: string, provider: string,
 *           model: string, duration_ms: number, fallback_reason: string|null,
 *           impl_model_tag: string,
 *           context_size_at_spawn?: number, compact_events_count?: number,
 *           retry_429_count?: number, nested_session_completed?: boolean }} params
 * @throws {Error} if a required field is missing or a token-like value is detected
 */
export function logPhase(params) {
  // Validate required fields
  for (const field of REQUIRED_FIELDS) {
    if (!(field in params)) {
      throw new Error(`logPhase: missing required field "${field}"`);
    }
  }

  // Token-like value guard — check all string fields
  for (const [key, value] of Object.entries(params)) {
    if (typeof value === 'string' && TOKEN_RE.test(value)) {
      throw new Error(`logPhase: token-like value detected in field "${key}"`);
    }
  }

  const entry = {
    trace_id:        params.trace_id,
    story_id:        params.story_id,
    phase:           params.phase,
    provider:        params.provider,
    model:           params.model,
    duration_ms:     params.duration_ms,
    fallback_reason: params.fallback_reason,
    impl_model_tag:  params.impl_model_tag,
  };

  // Append optional secondary-mode telemetry fields when present (integers/boolean, DEC-65)
  const TELEMETRY_FIELDS = ['context_size_at_spawn', 'compact_events_count', 'retry_429_count', 'nested_session_completed', 'pipeline', 'pr_url', 'auto_merge_applied'];
  for (const f of TELEMETRY_FIELDS) {
    if (f in params) entry[f] = params[f];
  }

  entry.timestamp = new Date().toISOString();

  const line = JSON.stringify(entry) + '\n';

  mkdirSync(dirname(_logPath), { recursive: true });
  appendFileSync(_logPath, line, 'utf8');
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);

  function argValue(flag) {
    const idx = args.indexOf(flag);
    if (idx === -1 || idx + 1 >= args.length) return undefined;
    return args[idx + 1];
  }

  const traceId       = argValue('--trace-id');
  const storyId       = argValue('--story-id');
  const phase         = argValue('--phase');
  const provider      = argValue('--provider');
  const model         = argValue('--model');
  const durationRaw   = argValue('--duration-ms');
  const fallbackRaw   = argValue('--fallback-reason');
  const implModelTag  = argValue('--impl-model-tag');
  const pipelineArg   = argValue('--pipeline');
  const logPathArg    = argValue('--log-path');
  const prUrlArg         = argValue('--pr-url');
  const autoMergeApplied = argValue('--auto-merge-applied');

  // --log-path overrides default log path (useful for testing without internal _setLogPath)
  if (logPathArg) _setLogPath(logPathArg);

  // Normalize fallback_reason: empty string or literal "null" → null
  const fallbackReason = (fallbackRaw === '' || fallbackRaw === 'null') ? null : fallbackRaw;

  try {
    const phaseParams = {
      trace_id:       traceId,
      story_id:       storyId,
      phase,
      provider,
      model,
      duration_ms:    Number(durationRaw),
      fallback_reason: fallbackReason,
      impl_model_tag:  implModelTag,
    };
    if (pipelineArg !== undefined) phaseParams.pipeline = pipelineArg;
    if (prUrlArg !== undefined && prUrlArg !== '') phaseParams.pr_url = prUrlArg;
    if (autoMergeApplied !== undefined) phaseParams.auto_merge_applied = autoMergeApplied === 'true';
    logPhase(phaseParams);
    process.stdout.write(formatPhaseStdout(phase, provider, model, fallbackReason));
  } catch (err) {
    process.stderr.write(`runtime-routing-logger: ${err.message}\n`);
    process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// Stdout feedback formatter (E94S07)
// ---------------------------------------------------------------------------

/**
 * Returns a single-line human-readable phase feedback string for stdout.
 * No secrets: only provider label, model ID, and error class (no tokens, no base URLs).
 *
 * @param {string}      phase          - 'plan' | 'impl' | 'qa'
 * @param {string}      provider       - 'primary' | 'secondary'
 * @param {string}      model          - model ID string (e.g. 'claude-sonnet-4-6')
 * @param {string|null} fallbackReason - error class if fallback was triggered, else null
 * @returns {string}
 */
export function formatPhaseStdout(phase, provider, model, fallbackReason) {
  const phaseName = phase === 'qa' ? 'QA'
    : phase.charAt(0).toUpperCase() + phase.slice(1);
  const suffix = fallbackReason != null
    ? `... ⚠ Falling back to primary (reason: ${fallbackReason})`
    : '... done';
  return `▸ Phase ${phaseName} (${provider} / ${model}) ${suffix}\n`;
}
