/**
 * nested-claude-spawn.js
 *
 * Purpose: Single-file isolation of multi-provider routing fragility per Epic E94 decision D-10.
 *
 * Obsolescence: Retire this file (and its callers in workflows + story fields) when Anthropic
 * ships native multi-provider routing — tracked in github.com/anthropics/claude-code issue #38698.
 *
 * Community workaround: `CLAUDECODE=""` required to bypass parent-process env inheritance that
 * blocks nested spawn — see anthropics/claude-code #28339, #25803, #28407.
 *
 * Non-regression: Callers MUST NOT invoke this wrapper for stories without `impl_model: secondary`
 * tag AND user env vars configured — Epic E94 D-0.
 *
 * ToS caveat: secondary provider account ToS must permit programmatic API; parent OAuth Max Plan
 * terms respected by process isolation.
 */

import { spawn as _childSpawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

// ---------------------------------------------------------------------------
// Spawn injection seam (for tests only)
// ---------------------------------------------------------------------------

let _spawnFn = _childSpawn;

/** @internal — for tests only */
export function _setSpawnFn(fn) { _spawnFn = fn; }

/** @internal — for tests only */
export function _resetSpawnFn() { _spawnFn = _childSpawn; }

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const GLOBAL_TIMEOUT_MS    = 14_400_000; // 4 hours
const HEARTBEAT_TIMEOUT_MS =  1_800_000; // 30 minutes
const SIGKILL_GRACE_MS     =      5_000; // 5 seconds
const MAX_TURNS            =        150;

// ---------------------------------------------------------------------------
// JSDoc typedef for SpawnResult
// ---------------------------------------------------------------------------

/**
 * @typedef {Object} SpawnResult
 * @property {string}       trace_id          - UUID identifying this spawn execution
 * @property {boolean}      success           - true if the child exited 0 and produced the artefact
 * @property {number|null}  exit_code         - raw process exit code, or null if killed/missing
 * @property {string|null}  error_reason      - one of the classified error codes, or null on success
 * @property {string|null}  impl_report_path  - path to impl report file if it exists, else null
 * @property {string|null}  model_actual      - model string extracted from child stdout JSON, or null
 * @property {number}       duration_ms       - wall-clock ms from spawn to close
 * @property {string}       model_requested   - value of GAAI_IMPL_MODEL at spawn time
 * @property {boolean}      model_fallback_triggered - true iff model_actual !== model_requested
 * @property {string}       provider_base_url     - value of GAAI_IMPL_BASE_URL at spawn time (no token)
 */

// ---------------------------------------------------------------------------
// Private helper: findCLI
// ---------------------------------------------------------------------------

/**
 * Resolves the `claude` binary path by scanning PATH entries.
 * @returns {string|null} Absolute path to the claude binary, or null if not found.
 */
function findCLI() {
  const pathEnv = process.env.PATH || '';
  const dirs = pathEnv.split(process.platform === 'win32' ? ';' : ':');
  const candidates = process.platform === 'win32'
    ? ['claude.cmd', 'claude.exe']
    : ['claude'];

  for (const dir of dirs) {
    for (const name of candidates) {
      const full = join(dir, name);
      try {
        if (existsSync(full)) {
          return full;
        }
      } catch {
        // skip unreadable dirs
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Private helper: buildChildEnv
// ---------------------------------------------------------------------------

/**
 * Constructs the child process environment for the nested claude spawn.
 * Maps GAAI_IMPL_* vars to Anthropic SDK vars, clears parent OAuth/key vars.
 * NEVER logs token values.
 * @returns {Record<string,string>} The environment object for the child.
 */
function buildChildEnv() {
  const env = { ...process.env };

  // Required: bypass nested Claude Code detection
  env.CLAUDECODE = '';

  // Map GAAI_IMPL_* -> Anthropic SDK env vars
  if (env.GAAI_IMPL_BASE_URL)      { env.ANTHROPIC_BASE_URL             = env.GAAI_IMPL_BASE_URL; }
  if (env.GAAI_IMPL_AUTH_TOKEN)    { env.ANTHROPIC_AUTH_TOKEN           = env.GAAI_IMPL_AUTH_TOKEN; }
  if (env.GAAI_IMPL_MODEL)         { env.ANTHROPIC_DEFAULT_OPUS_MODEL   = env.GAAI_IMPL_MODEL; }
  if (env.GAAI_IMPL_MODEL_FALLBACK){ env.ANTHROPIC_DEFAULT_SONNET_MODEL = env.GAAI_IMPL_MODEL_FALLBACK; }

  // API_TIMEOUT_MS inherited via spread — no extra code needed

  // Remove parent auth credentials to prevent credential leakage / conflict
  delete env.CLAUDE_CODE_OAUTH_TOKEN;
  delete env.ANTHROPIC_API_KEY;
  delete env.CLAUDE_API_KEY;

  return env;
}

// ---------------------------------------------------------------------------
// Private helper: buildSpawnArgs
// ---------------------------------------------------------------------------

/**
 * Builds the argv array for the claude child process.
 * Always uses `--model opus` regardless of GAAI_IMPL_MODEL (AC6).
 * @param {string} prompt
 * @param {string[]} extraArgs
 * @returns {string[]}
 */
function buildSpawnArgs(prompt, extraArgs) {
  return [
    '-p', prompt,
    '--no-session-persistence',
    '--dangerously-skip-permissions',  // nested child cannot answer permission prompts; would hang forever
    '--output-format', 'stream-json',
    '--verbose',
    '--model', 'opus',
    '--max-turns', String(MAX_TURNS),
    ...extraArgs,
    ...(process.env.GAAI_IMPL_MODEL_FALLBACK ? ['--fallback-model', 'sonnet'] : []),
  ];
}

// ---------------------------------------------------------------------------
// Private helper: classifyError
// ---------------------------------------------------------------------------

/**
 * Classifies the failure reason from exit code, stderr, stdout and an optional preset reason.
 * Priority order is documented inline.
 * @param {number|null}  exitCode
 * @param {string}       stderr
 * @param {string}       stdout
 * @param {string|null}  presetReason  - TIMEOUT or HEARTBEAT_TIMEOUT if already determined
 * @param {string|null}  implReportPath
 * @returns {string} One of the error reason codes.
 */
function classifyError(exitCode, stderr, stdout, presetReason, implReportPath) {
  // 1. Preset reason (timer-triggered kill)
  if (presetReason) return presetReason;

  // 2. Auth failures
  if (/401|403|invalid_api_key|authentication/i.test(stderr)) return 'AUTH_FAILED';

  // 3. Network / endpoint failures
  if (/ECONNREFUSED|ENOTFOUND|ETIMEDOUT|network|dns/i.test(stderr)) return 'ENDPOINT_UNREACHABLE';

  // 4. Nested Claude Code detection bug
  if (/running inside Claude Code|cannot be launched inside another Claude Code session/i.test(stderr)) {
    return 'CLAUDECODE_BUG';
  }

  // 5. Exited 0 — primary success signal is impl_report file presence (ground truth).
  //    Completion markers in stdout are a heuristic fallback for cases where no
  //    implReportPath is provided (e.g., unit tests). In real delivery, what matters
  //    is that the child WROTE the artefact file, regardless of what it said in stdout.
  //    (Fix 2026-04-19 after E63S03 PARSE_ERROR'd despite 7KB impl-report.md being written.)
  if (exitCode === 0 && implReportPath) {
    if (existsSync(implReportPath)) {
      // File written — treat as success regardless of stdout markers.
      // Caller's `success` field is `exit_code === 0 && implReportPath && existsSync(implReportPath)`,
      // which remains satisfied here; no error_reason needed.
      return null; // success path
    }
    // File NOT written — real failure. Distinguish marker-absent (parser issue?)
    // from marker-present (agent described but didn't write).
    const hasCompletionMarker = stdout.includes('## QA') || stdout.includes('## Implementation') || stdout.includes('impl_report');
    if (!hasCompletionMarker) return 'PARSE_ERROR';
    return 'NO_ARTEFACT_PRODUCED';
  }

  // 5b. Exited 0 but NO implReportPath given (e.g., unit tests) — fall back to markers.
  if (exitCode === 0 && !implReportPath) {
    const hasCompletionMarker = stdout.includes('## QA') || stdout.includes('## Implementation') || stdout.includes('impl_report');
    if (!hasCompletionMarker) return 'PARSE_ERROR';
  }

  // 7. Non-zero exit
  if (exitCode !== 0) return 'EXIT_CODE_NON_ZERO';

  // Should not reach here (success path is handled before classifyError is called)
  return 'UNKNOWN';
}

// ---------------------------------------------------------------------------
// Private helper: extractModelActual
// ---------------------------------------------------------------------------

/**
 * Scans stdout for a JSON line containing a `model` field.
 * Claude Code `-p` output may include JSONL assistant messages.
 * @param {string} stdout
 * @returns {string|null}
 */
function extractModelActual(stdout) {
  for (const line of stdout.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('{')) continue;
    try {
      const obj = JSON.parse(trimmed);
      if (typeof obj.model === 'string') return obj.model;
    } catch {
      // not valid JSON, skip
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Core spawn logic (shared between public and override export)
// ---------------------------------------------------------------------------

/**
 * Core implementation: spawns a nested claude process with configurable timeouts.
 * @param {string}   prompt
 * @param {string}   implReportPath
 * @param {string[]} extraArgs
 * @param {number}   globalTimeoutMs
 * @param {number}   heartbeatTimeoutMs
 * @returns {Promise<SpawnResult>}
 */
function spawnCore(prompt, implReportPath, extraArgs, globalTimeoutMs, heartbeatTimeoutMs) {
  const traceId   = randomUUID();
  const startMs   = Date.now();
  const modelReq  = process.env.GAAI_IMPL_MODEL   || '';
  const baseUrl   = process.env.GAAI_IMPL_BASE_URL || '';
  const fallback  = process.env.GAAI_IMPL_MODEL_FALLBACK || null;

  // Log spawn start — never log token values
  console.log(`[nested-claude-spawn] spawn trace_id=${traceId} model=${modelReq} url=${baseUrl}`);

  return new Promise((resolve) => {
    // Resolve claude binary
    const claudePath = findCLI();
    if (!claudePath) {
      const duration = Date.now() - startMs;
      console.log(`[nested-claude-spawn] CLAUDECODE_BUG: claude binary not found trace_id=${traceId}`);
      resolve({
        trace_id:         traceId,
        success:          false,
        exit_code:        null,
        error_reason:     'CLAUDECODE_BUG',
        impl_report_path: null,
        model_actual:     null,
        duration_ms:      duration,
        model_requested:  modelReq,
        model_fallback_triggered: false,
        provider_base_url:       baseUrl,
      });
      return;
    }

    const args  = buildSpawnArgs(prompt, extraArgs);
    const env   = buildChildEnv();
    const child = _spawnFn(claudePath, args, { env, shell: false, stdio: ['ignore', 'pipe', 'pipe'] });

    const stdoutChunks = [];
    const stderrChunks = [];
    let presetReason   = null;
    let killed         = false;

    let globalTimer    = null;
    let heartbeatTimer = null;

    function clearTimers() {
      if (globalTimer)    { clearTimeout(globalTimer);    globalTimer    = null; }
      if (heartbeatTimer) { clearTimeout(heartbeatTimer); heartbeatTimer = null; }
    }

    function killChild(reason) {
      if (killed) return;
      killed       = true;
      presetReason = reason;
      console.log(`[nested-claude-spawn] killing child reason=${reason} trace_id=${traceId}`);
      child.kill('SIGTERM');
      setTimeout(() => {
        try { child.kill('SIGKILL'); } catch { /* already dead */ }
      }, SIGKILL_GRACE_MS);
    }

    function resetHeartbeat() {
      if (heartbeatTimer) { clearTimeout(heartbeatTimer); }
      heartbeatTimer = setTimeout(() => killChild('HEARTBEAT_TIMEOUT'), heartbeatTimeoutMs);
    }

    // Start timers
    globalTimer    = setTimeout(() => killChild('TIMEOUT'), globalTimeoutMs);
    resetHeartbeat();

    child.stdout.on('data', (chunk) => {
      stdoutChunks.push(chunk);
      resetHeartbeat();
    });

    child.stderr.on('data', (chunk) => {
      stderrChunks.push(chunk);
    });

    child.on('close', (code) => {
      clearTimers();

      const stdout     = Buffer.concat(stdoutChunks).toString('utf8');
      const stderr     = Buffer.concat(stderrChunks).toString('utf8');
      const duration   = Date.now() - startMs;
      const modelActual = extractModelActual(stdout);

      // Determine completion marker presence
      const hasCompletionMarker = stdout.includes('## QA') || stdout.includes('## Implementation') || stdout.includes('impl_report');
      const reportExists = implReportPath ? existsSync(implReportPath) : false;

      // Success primary signal is artefact file existence (ground truth) when implReportPath
      // is given — the child's responsibility is to WRITE the file, not to emit stdout markers.
      // When no implReportPath is given (e.g., unit tests), fall back to completion markers.
      // (Updated 2026-04-19 after E63S03 PARSE_ERROR'd despite 7KB impl-report.md being written.)
      const success = (code === 0) && (implReportPath
        ? reportExists
        : hasCompletionMarker);

      let errorReason = null;
      if (!success) {
        errorReason = classifyError(code, stderr, stdout, presetReason, implReportPath);
      }

      const modelFallbackTriggered = !!(modelActual && modelActual !== modelReq);

      console.log(`[nested-claude-spawn] done trace_id=${traceId} success=${success} reason=${errorReason} duration_ms=${duration}`);

      resolve({
        trace_id:         traceId,
        success,
        exit_code:        code,
        error_reason:     errorReason,
        impl_report_path: (success && implReportPath) ? implReportPath : null,
        model_actual:     modelActual,
        duration_ms:      duration,
        model_requested:  modelReq,
        model_fallback_triggered: modelFallbackTriggered,
        provider_base_url:       baseUrl,
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Public export: spawnNestedClaude
// ---------------------------------------------------------------------------

/**
 * Spawns a nested `claude -p` process using the secondary provider env vars.
 * Returns a SpawnResult — never throws.
 *
 * @param {string}   prompt          - The prompt to pass to `claude -p`
 * @param {string}   implReportPath  - Expected path to the impl-report artefact
 * @param {string[]} [extraArgs=[]]  - Additional argv to append
 * @returns {Promise<SpawnResult>}
 */
export async function spawnNestedClaude(prompt, implReportPath, extraArgs = []) {
  // Guard: required env vars
  const missing = [];
  if (!process.env.GAAI_IMPL_BASE_URL)   missing.push('GAAI_IMPL_BASE_URL');
  if (!process.env.GAAI_IMPL_AUTH_TOKEN) missing.push('GAAI_IMPL_AUTH_TOKEN');
  if (!process.env.GAAI_IMPL_MODEL)      missing.push('GAAI_IMPL_MODEL');

  if (missing.length > 0) {
    const traceId = randomUUID();
    console.log(`[nested-claude-spawn] ENV_MISSING vars=${missing.join(',')} trace_id=${traceId}`);
    return {
      trace_id:         traceId,
      success:          false,
      exit_code:        null,
      error_reason:     'ENV_MISSING',
      impl_report_path: null,
      model_actual:     null,
      duration_ms:      0,
      model_requested:  process.env.GAAI_IMPL_MODEL   || '',
      model_fallback_triggered: false,
      provider_base_url:       process.env.GAAI_IMPL_BASE_URL || '',
    };
  }

  return spawnCore(prompt, implReportPath, extraArgs, GLOBAL_TIMEOUT_MS, HEARTBEAT_TIMEOUT_MS);
}

// ---------------------------------------------------------------------------
// Secondary export: _spawnWithTimerOverride (for tests only)
// ---------------------------------------------------------------------------

/**
 * Same as spawnNestedClaude but with overridable timeout values.
 * @internal — for tests only
 *
 * @param {string}   prompt
 * @param {string}   implReportPath
 * @param {string[]} extraArgs
 * @param {{ globalTimeoutMs?: number, heartbeatTimeoutMs?: number }} overrides
 * @returns {Promise<SpawnResult>}
 */
export async function _spawnWithTimerOverride(prompt, implReportPath, extraArgs, overrides = {}) {
  // Guard: required env vars (same as spawnNestedClaude)
  const missing = [];
  if (!process.env.GAAI_IMPL_BASE_URL)   missing.push('GAAI_IMPL_BASE_URL');
  if (!process.env.GAAI_IMPL_AUTH_TOKEN) missing.push('GAAI_IMPL_AUTH_TOKEN');
  if (!process.env.GAAI_IMPL_MODEL)      missing.push('GAAI_IMPL_MODEL');

  if (missing.length > 0) {
    const traceId = randomUUID();
    return {
      trace_id:         traceId,
      success:          false,
      exit_code:        null,
      error_reason:     'ENV_MISSING',
      impl_report_path: null,
      model_actual:     null,
      duration_ms:      0,
      model_requested:  process.env.GAAI_IMPL_MODEL   || '',
      model_fallback_triggered: false,
      provider_base_url:       process.env.GAAI_IMPL_BASE_URL || '',
    };
  }

  const gMs = overrides.globalTimeoutMs    ?? GLOBAL_TIMEOUT_MS;
  const hMs = overrides.heartbeatTimeoutMs ?? HEARTBEAT_TIMEOUT_MS;
  return spawnCore(prompt, implReportPath, extraArgs, gMs, hMs);
}

// ---------------------------------------------------------------------------
// CLI entry point — enables bash-native invocation by delivery agents
// ---------------------------------------------------------------------------
//
// Usage (from Bash tool in delivery workflow §6a):
//   node .gaai/core/adapters/claude-code/nested-claude-spawn.js \
//     --prompt-file /path/to/impl-prompt.md \
//     --report-path /path/to/impl-report.md
//
// Result: JSON SpawnResult printed to stdout on exit 0; exits 1 on invocation error.
// The SpawnResult.success field (true/false) indicates whether the nested claude -p
// produced a valid impl-report. Caller should parse stdout JSON and act on it.
//
// Rationale: ES module functions are not directly callable from bash. Without this
// CLI, delivery agents looking at the module couldn't invoke the wrapper and fell
// back to Task tool on primary (observed in E77S02, E77S03, E78S01, E64S01 deliveries).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

async function _cli() {
  const args = process.argv.slice(2);
  const opts = {};
  for (let i = 0; i < args.length; i++) {
    const k = args[i];
    if (k === '--prompt-file' || k === '--prompt') opts.promptFile = args[++i];
    else if (k === '--prompt-inline') opts.promptInline = args[++i];
    else if (k === '--report-path') opts.reportPath = args[++i];
    else if (k === '--extra-arg') { (opts.extraArgs ||= []).push(args[++i]); }
    else if (k === '--help' || k === '-h') {
      process.stdout.write(`Usage: node nested-claude-spawn.js [options]

Options:
  --prompt-file <path>   Read prompt text from file (preferred for large prompts)
  --prompt-inline <txt>  Pass prompt inline (for short prompts only)
  --report-path <path>   Path where the nested claude -p will write impl-report.md
  --extra-arg <arg>      Append extra argv to child (repeatable, e.g. --extra-arg --model)
  --help, -h             Show this help

Output: SpawnResult JSON on stdout on success. Exit 1 on invocation error.
`);
      process.exit(0);
    }
  }

  if (!opts.reportPath) {
    console.error('ERROR: --report-path is required');
    process.exit(1);
  }
  let prompt = '';
  if (opts.promptFile) {
    try { prompt = readFileSync(opts.promptFile, 'utf8'); }
    catch (e) { console.error(`ERROR: cannot read --prompt-file ${opts.promptFile}: ${e.message}`); process.exit(1); }
  } else if (opts.promptInline) {
    prompt = opts.promptInline;
  } else {
    console.error('ERROR: --prompt-file or --prompt-inline is required');
    process.exit(1);
  }

  const result = await spawnNestedClaude(prompt, opts.reportPath, opts.extraArgs || []);
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  // Exit 0 regardless of result.success — the caller reads success from the JSON.
  // This way the wrapper's business-logic failure (e.g. AUTH_FAILED) is not conflated
  // with invocation errors (missing args, unreadable file).
  process.exit(0);
}

// Detect direct invocation (not import) and run CLI
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  _cli().catch(e => {
    console.error(`FATAL: ${e.message}`);
    process.exit(1);
  });
}
