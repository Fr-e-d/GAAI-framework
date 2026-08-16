/**
 * nested-claude-spawn.test.js
 *
 * Unit tests for nested-claude-spawn.js using node:test and node:assert (built-in).
 * Run with: node --test .gaai/core/adapters/claude-code/__tests__/nested-claude-spawn.test.js
 *
 * Updated for E131S03: covers resolveMode() DEC-72 matrix (AC1), runImpl() routing log
 * record counts (AC2), universal fallback (AC4), and the rewritten T1 — ENV_MISSING no
 * longer applies to the new runImpl() API; silent primary routing is the correct contract.
 */

import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { writeFileSync, mkdirSync, existsSync, readFileSync, readdirSync, mkdtempSync, statSync, chmodSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';

import {
  spawnNestedClaude,
  _spawnWithTimerOverride,
  _setSpawnFn,
  _resetSpawnFn,
  resolveMode,
  runImpl,
  reconcileHandles,
} from '../nested-claude-spawn.js';

import { _setLogPath, _resetLogPath } from '../runtime-routing-logger.js';

// ---------------------------------------------------------------------------
// Mock child factory helpers
// ---------------------------------------------------------------------------

/**
 * Creates a mock child process EventEmitter that behaves like a spawned process.
 * @param {Object} opts
 * @param {number}  [opts.exitCode=0]     - Exit code to emit on close
 * @param {string}  [opts.stdoutData='']  - Data to emit on stdout
 * @param {string}  [opts.stderrData='']  - Data to emit on stderr
 * @param {number}  [opts.delay=10]       - Milliseconds before emitting close
 * @param {Function} [opts.onKill]        - Called when child.kill() is invoked
 */
function createMockChild({ exitCode = 0, stdoutData = '', stderrData = '', delay = 10, onKill } = {}) {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  child.kill = (signal) => {
    if (onKill) onKill(signal);
    // Emit close after a tiny tick to simulate OS behaviour
    setImmediate(() => {
      child.exitCode = null;
      child.emit('close', null);
    });
  };

  process.nextTick(() => {
    if (stderrData) child.stderr.emit('data', Buffer.from(stderrData));
    if (stdoutData) child.stdout.emit('data', Buffer.from(stdoutData));
    setTimeout(() => {
      child.exitCode = exitCode;
      child.emit('close', exitCode);
    }, delay);
  });

  return child;
}

/**
 * Creates a mock child that hangs forever (never emits 'close').
 * Used for timeout tests.
 * @param {Function} [onKill]
 */
function createHangingChild(onKill) {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  let killCount = 0;
  child.kill = (signal) => {
    killCount++;
    if (onKill) onKill(signal);
    // First kill (SIGTERM) → do nothing; second kill (SIGKILL) → emit close
    if (killCount >= 2) {
      setImmediate(() => child.emit('close', null));
    }
  };
  return child;
}

// ---------------------------------------------------------------------------
// Environment helpers
// ---------------------------------------------------------------------------

function setValidEnv() {
  process.env.GAAI_IMPL_BASE_URL   = 'https://test.example.com';
  process.env.GAAI_IMPL_AUTH_TOKEN = 'test-token-do-not-log';
  process.env.GAAI_IMPL_MODEL      = 'test-model';
}

function clearEnv() {
  delete process.env.GAAI_IMPL_BASE_URL;
  delete process.env.GAAI_IMPL_AUTH_TOKEN;
  delete process.env.GAAI_IMPL_MODEL;
  delete process.env.GAAI_IMPL_MODEL_FALLBACK;
  delete process.env.GAAI_CLAUDE_PROXY_BASE_URL;
  delete process.env.GAAI_RUNNER_POLL_BUDGET_MS;
  delete process.env.GAAI_RUNNER_HANDLE_DIR;
}

/**
 * Pins the post-expiry poll budget so timeout tests stay fast. Without this the
 * budget defaults to one further heartbeat window, which is minutes in production
 * and would make these tests wait for it.
 */
function setPollBudget(ms) {
  process.env.GAAI_RUNNER_POLL_BUDGET_MS = String(ms);
}

/** Isolates handle records in a throwaway directory. Returns the directory path. */
function useTmpHandleDir() {
  const dir = mkdtempSync(join(tmpdir(), 'gaai-test-handles-'));
  process.env.GAAI_RUNNER_HANDLE_DIR = dir;
  return dir;
}

// ---------------------------------------------------------------------------
// Routing log fixture helpers (AC2, AC6)
// ---------------------------------------------------------------------------

function makeTmpLog() {
  const dir = mkdtempSync(join(tmpdir(), 'gaai-test-E131S03-log-'));
  return join(dir, 'runtime-routing.jsonl');
}

function readLogLines(logPath) {
  if (!existsSync(logPath)) return [];
  return readFileSync(logPath, 'utf8')
    .split('\n')
    .filter(l => l.trim() !== '')
    .map(l => JSON.parse(l));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('nested-claude-spawn', () => {

  afterEach(() => {
    _resetSpawnFn();
    _resetLogPath();
    clearEnv();
  });

  // -------------------------------------------------------------------------
  // T1 (rewritten — AC3): runImpl with no env + no tag routes silently to primary
  //
  // Previously asserted ENV_MISSING via spawnNestedClaude(). That contract is
  // gone from the new runImpl() API: absent env + absent tag → silent primary
  // routing (DEC-72 Row 5 / OSS non-regression). No ENV_MISSING, no warning.
  // -------------------------------------------------------------------------
  test('T1: no-env + no-tag routes to primary silently — error_reason is not ENV_MISSING', async () => {
    clearEnv();
    const tmpLog = makeTmpLog();
    _setLogPath(tmpLog);

    const reportPath = join(tmpdir(), `gaai-test-E131S03-T1-${Date.now()}.md`);
    writeFileSync(reportPath, '## QA\nAll good.\n');

    // Capture stdout to verify no ⚠ warning is emitted (no explicit secondary tag)
    const stdoutLines = [];
    const origWrite = process.stdout.write.bind(process.stdout);
    process.stdout.write = (msg, ...rest) => {
      stdoutLines.push(typeof msg === 'string' ? msg : msg.toString());
      return origWrite(msg, ...rest);
    };

    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: '## QA\nAll good.\n' }));

    let r;
    try {
      r = await runImpl({
        implModelTag: null,
        prompt: 'test-prompt',
        reportPath,
        storyId: 'E131S03-T1',
      });
    } finally {
      process.stdout.write = origWrite;
    }

    // Core assertion: ENV_MISSING must never appear in the new routing API
    assert.notEqual(r.error_reason, 'ENV_MISSING', 'ENV_MISSING must not be returned by runImpl');
    // The mock succeeds → primary spawn succeeds
    assert.equal(r.success, true, 'primary spawn must succeed with mock');
    // No ⚠ warning when tag is absent (warning only for explicit secondary tag per AC3)
    const hasWarning = stdoutLines.some(l => l.includes('⚠ impl_model=secondary'));
    assert.equal(hasWarning, false, 'no warning must be emitted for absent tag');
  });

  // -------------------------------------------------------------------------
  // T2: TIMEOUT - global timer kills hanging child
  // -------------------------------------------------------------------------
  test('T2: TIMEOUT - global timer kills hanging child', async () => {
    setValidEnv();
    // Expiry now demotes to poll mode first; the kill lands when that budget runs out.
    setPollBudget(50);

    const killSignals = [];
    _setSpawnFn(() => createHangingChild((sig) => killSignals.push(sig)));

    const r = await _spawnWithTimerOverride(
      'test-prompt', '/tmp/test-timeout.md', [],
      { globalTimeoutMs: 200, heartbeatTimeoutMs: 60_000 }
    );

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'TIMEOUT');
    assert.ok(r.duration_ms >= 200, `duration_ms ${r.duration_ms} should be >= 200`);
    assert.ok(killSignals.includes('SIGTERM'), 'SIGTERM must have been sent');
  });

  // -------------------------------------------------------------------------
  // T3: HEARTBEAT_TIMEOUT - heartbeat timer fires when stdout goes silent
  // -------------------------------------------------------------------------
  test('T3: HEARTBEAT_TIMEOUT - heartbeat timer fires on silent child', async () => {
    setValidEnv();
    setPollBudget(50);

    _setSpawnFn(() => createHangingChild());

    const r = await _spawnWithTimerOverride(
      'test-prompt', '/tmp/test-heartbeat.md', [],
      { globalTimeoutMs: 60_000, heartbeatTimeoutMs: 200 }
    );

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'HEARTBEAT_TIMEOUT');
    assert.equal(r.observation_window_expired, true,
      'a silent child must be polled against its handle before being killed');
  });

  // -------------------------------------------------------------------------
  // T4: AUTH_FAILED - 401 in stderr
  // -------------------------------------------------------------------------
  test('T4: AUTH_FAILED - 401 in stderr triggers AUTH_FAILED', async () => {
    setValidEnv();

    _setSpawnFn(() => createMockChild({
      exitCode: 1,
      stderrData: 'Error: 401 Unauthorized — invalid_api_key',
    }));

    const r = await spawnNestedClaude('test-prompt', '/tmp/test-auth.md');

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'AUTH_FAILED');
    assert.equal(r.exit_code, 1);
  });

  // -------------------------------------------------------------------------
  // T5: ENDPOINT_UNREACHABLE - ECONNREFUSED in stderr
  // -------------------------------------------------------------------------
  test('T5: ENDPOINT_UNREACHABLE - ECONNREFUSED in stderr', async () => {
    setValidEnv();

    _setSpawnFn(() => createMockChild({
      exitCode: 1,
      stderrData: 'Error: connect ECONNREFUSED 127.0.0.1:443',
    }));

    const r = await spawnNestedClaude('test-prompt', '/tmp/test-econnrefused.md');

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'ENDPOINT_UNREACHABLE');
  });

  // -------------------------------------------------------------------------
  // T6: CLAUDECODE_BUG - nested spawn detection message in stderr
  // -------------------------------------------------------------------------
  test('T6: CLAUDECODE_BUG - nested spawn detection message in stderr', async () => {
    setValidEnv();

    _setSpawnFn(() => createMockChild({
      exitCode: 1,
      stderrData: 'Error: cannot be launched inside another Claude Code session',
    }));

    const r = await spawnNestedClaude('test-prompt', '/tmp/test-nested.md');

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'CLAUDECODE_BUG');
  });

  // -------------------------------------------------------------------------
  // T7: PARSE_ERROR - exit 0 but no completion marker
  // -------------------------------------------------------------------------
  test('T7: PARSE_ERROR - exit code 0 but no completion marker in stdout', async () => {
    setValidEnv();

    _setSpawnFn(() => createMockChild({
      exitCode: 0,
      stdoutData: 'Some output without the expected marker',
    }));

    const r = await spawnNestedClaude('test-prompt', '/tmp/test-parse.md');

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'PARSE_ERROR');
    assert.equal(r.exit_code, 0);
  });

  // -------------------------------------------------------------------------
  // T8: NO_ARTEFACT_PRODUCED - exit 0 + completion marker but report file absent
  // -------------------------------------------------------------------------
  test('T8: NO_ARTEFACT_PRODUCED - exit 0 with marker but impl_report_path absent', async () => {
    setValidEnv();

    // Path that does NOT exist on disk
    const missingPath = '/tmp/gaai-test-E94S03-DOES-NOT-EXIST-' + Date.now() + '.md';

    _setSpawnFn(() => createMockChild({
      exitCode: 0,
      stdoutData: '## QA\nAll steps complete.\n',
    }));

    const r = await spawnNestedClaude('test-prompt', missingPath);

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'NO_ARTEFACT_PRODUCED');
    assert.equal(r.exit_code, 0);
  });

  // -------------------------------------------------------------------------
  // T9: EXIT_CODE_NON_ZERO - non-zero exit with non-classified stderr
  // -------------------------------------------------------------------------
  test('T9: EXIT_CODE_NON_ZERO - non-zero exit code with unclassified stderr', async () => {
    setValidEnv();

    _setSpawnFn(() => createMockChild({
      exitCode: 7,
      stderrData: 'Some unrecognized error message',
    }));

    const r = await spawnNestedClaude('test-prompt', '/tmp/test-exitcode.md');

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'EXIT_CODE_NON_ZERO');
    assert.equal(r.exit_code, 7);
  });

  // -------------------------------------------------------------------------
  // T10: env propagation — CLAUDECODE is empty string, auth vars deleted
  // -------------------------------------------------------------------------
  test('T10: env propagation - CLAUDECODE="" set, parent auth vars deleted, GAAI_IMPL_* mapped', async () => {
    setValidEnv();
    process.env.GAAI_IMPL_MODEL_FALLBACK = 'fallback-model';
    // Plant parent auth vars that must be stripped
    process.env.CLAUDE_CODE_OAUTH_TOKEN = 'oauth-secret';
    process.env.ANTHROPIC_API_KEY       = 'api-key-secret';
    process.env.CLAUDE_API_KEY          = 'claude-key-secret';

    let capturedEnv = null;
    const reportPath = '/tmp/gaai-test-E94S03-env-report.md';
    writeFileSync(reportPath, '# Env test report\n');

    _setSpawnFn((cmd, args, options) => {
      capturedEnv = options.env;
      return createMockChild({
        exitCode: 0,
        stdoutData: '## QA\nAll good.\n',
      });
    });

    const r = await spawnNestedClaude('test-prompt', reportPath);

    assert.ok(capturedEnv, 'env must have been captured by mock spawn');

    // CLAUDECODE must be '' (empty string, not undefined)
    assert.equal(capturedEnv.CLAUDECODE, '', 'CLAUDECODE must be empty string');

    // GAAI_IMPL_* must be mapped to Anthropic SDK vars
    assert.equal(capturedEnv.ANTHROPIC_BASE_URL,           'https://test.example.com', 'ANTHROPIC_BASE_URL must be mapped');
    assert.equal(capturedEnv.ANTHROPIC_AUTH_TOKEN,         'test-token-do-not-log',    'ANTHROPIC_AUTH_TOKEN must be mapped');
    assert.equal(capturedEnv.ANTHROPIC_DEFAULT_OPUS_MODEL, 'test-model',               'ANTHROPIC_DEFAULT_OPUS_MODEL must be mapped');
    assert.equal(capturedEnv.ANTHROPIC_DEFAULT_SONNET_MODEL, 'fallback-model',         'ANTHROPIC_DEFAULT_SONNET_MODEL must be mapped');

    // Parent auth vars must be deleted
    assert.equal(capturedEnv.CLAUDE_CODE_OAUTH_TOKEN, undefined, 'CLAUDE_CODE_OAUTH_TOKEN must be deleted');
    assert.equal(capturedEnv.ANTHROPIC_API_KEY,       undefined, 'ANTHROPIC_API_KEY must be deleted');
    assert.equal(capturedEnv.CLAUDE_API_KEY,          undefined, 'CLAUDE_API_KEY must be deleted');

    // Verify success shape too
    assert.equal(r.provider_base_url,       'https://test.example.com');
    assert.equal(r.model_requested,          'test-model');
    // model_fallback_triggered is false here (model_actual is null since mock emits no JSON model line)
    assert.equal(typeof r.model_fallback_triggered, 'boolean');
  });

  test('T10b: daemon Claude proxy wins over Impl base URL for ANTHROPIC_BASE_URL', async () => {
    setValidEnv();
    process.env.GAAI_CLAUDE_PROXY_BASE_URL = 'https://proxy.example.test';

    let capturedEnv = null;
    const reportPath = '/tmp/gaai-test-claude-proxy-env-report.md';
    writeFileSync(reportPath, '# Proxy env test report\n');

    _setSpawnFn((_cmd, _args, options) => {
      capturedEnv = options.env;
      return createMockChild({
        exitCode: 0,
        stdoutData: '## QA\nAll good.\n',
      });
    });

    await spawnNestedClaude('test-prompt', reportPath);

    assert.ok(capturedEnv, 'env must have been captured by mock spawn');
    assert.equal(capturedEnv.ANTHROPIC_BASE_URL, 'https://proxy.example.test');
    assert.equal(capturedEnv.ANTHROPIC_AUTH_TOKEN, 'test-token-do-not-log');
    assert.equal(capturedEnv.ANTHROPIC_DEFAULT_OPUS_MODEL, 'test-model');
  });

  // -------------------------------------------------------------------------
  // T11: logFile absent → no file I/O
  // -------------------------------------------------------------------------
  test('T11: logFile absent — no file I/O occurs', async () => {
    setValidEnv();
    const reportPath = join(tmpdir(), `gaai-test-E94S12-T11-report-${Date.now()}.md`);
    writeFileSync(reportPath, '## QA\nAll good.\n');
    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: '## QA\nAll good.\n' }));
    const r = await spawnNestedClaude('test-prompt', reportPath);
    assert.equal(r.success, true);
    assert.equal(r.error_reason, null);
    assert.ok(r.trace_id);
    try { await import('node:fs').then(m => m.unlinkSync(reportPath)); } catch { /* ok */ }
  });

  // -------------------------------------------------------------------------
  // T12: logFile set + writable → chunks appended, file grows
  // -------------------------------------------------------------------------
  test('T12: logFile set and writable — chunks appended, existing content preserved', async () => {
    setValidEnv();
    const tmpDir = mkdtempSync(join(tmpdir(), 'gaai-test-E94S12-T12-'));
    const logFile = join(tmpDir, 'delivery.log');
    const reportPath = join(tmpDir, 'impl-report.md');
    writeFileSync(logFile, '{"type":"system","content":"outer-event"}\n', { encoding: 'utf8', flag: 'w' });
    const initialSize = statSync(logFile).size;
    writeFileSync(reportPath, '## QA\nAll good.\n');
    const stdoutPayload = '{"type":"assistant","model":"test-model"}\n{"type":"result","subtype":"success"}\n';
    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: stdoutPayload }));
    const r = await spawnNestedClaude('test-prompt', reportPath, [], logFile);
    assert.equal(r.success, true);
    const finalSize = statSync(logFile).size;
    assert.ok(finalSize > initialSize, `log file must grow: was ${initialSize}, now ${finalSize}`);
    const logContent = readFileSync(logFile, 'utf8');
    assert.ok(logContent.includes('outer-event'), 'existing content must be preserved');
    assert.ok(logContent.includes('"type":"assistant"'), 'child stdout must appear in log');
  });

  // -------------------------------------------------------------------------
  // T13: logFile set + unwritable → completes normally, single warning on stderr, no throw
  // -------------------------------------------------------------------------
  test('T13: logFile unwritable — completes normally, single warning on stderr', async () => {
    setValidEnv();
    const tmpDir = mkdtempSync(join(tmpdir(), 'gaai-test-E94S12-T13-'));
    const logFile = join(tmpDir, 'readonly.log');
    const reportPath = join(tmpDir, 'impl-report.md');
    writeFileSync(logFile, '', { encoding: 'utf8' });
    chmodSync(logFile, 0o444);
    writeFileSync(reportPath, '## QA\nAll good.\n');
    const stderrLines = [];
    const originalStderrWrite = process.stderr.write.bind(process.stderr);
    process.stderr.write = (msg, ...rest) => {
      stderrLines.push(typeof msg === 'string' ? msg : msg.toString());
      return originalStderrWrite(msg, ...rest);
    };
    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: '{"type":"assistant"}\n{"type":"result"}\n' }));
    let threw = false;
    let r;
    try {
      r = await spawnNestedClaude('test-prompt', reportPath, [], logFile);
    } catch (e) {
      threw = true;
    } finally {
      process.stderr.write = originalStderrWrite;
      try { chmodSync(logFile, 0o644); } catch { /* ok */ }
    }
    assert.equal(threw, false, 'must not throw');
    assert.equal(r.success, true);
    const warnings = stderrLines.filter(l => l.includes('[nested-claude-spawn] WARNING'));
    assert.ok(warnings.length >= 1, 'at least one WARNING must be emitted');
    assert.ok(warnings[0].includes(logFile), 'warning must contain log file path');
    assert.ok(!warnings[0].includes('test-token-do-not-log'), 'warning must not contain auth token');
  });

  // -------------------------------------------------------------------------
  // T14 (AC2): runImpl success → exactly one phase:impl record in routing log
  // -------------------------------------------------------------------------
  test('T14: runImpl success → exactly one phase:impl record in routing log', async () => {
    setValidEnv();
    const tmpLog = makeTmpLog();
    _setLogPath(tmpLog);

    const reportPath = join(tmpdir(), `gaai-test-E131S03-T14-${Date.now()}.md`);
    writeFileSync(reportPath, '## QA\nAll good.\n');

    // implModelTag 'secondary' + env configured → secondary
    // (post default flip — null tag now defaults to primary, must opt in explicitly)
    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: '## QA\nAll good.\n' }));

    const r = await runImpl({
      implModelTag: 'secondary',
      prompt: 'test-prompt',
      reportPath,
      storyId: 'E131S03-T14',
    });

    assert.equal(r.success, true);

    const records = readLogLines(tmpLog);
    assert.equal(records.length, 1, 'must have exactly one log record for a successful invocation');
    assert.equal(records[0].phase, 'impl');
    assert.equal(records[0].provider, 'secondary', 'explicit secondary tag + env configured → secondary');
    assert.equal(records[0].impl_model_tag, 'secondary', 'tag_recorded reflects explicit opt-in');
    assert.equal(records[0].fallback_reason, null, 'no fallback on success');
  });

  // -------------------------------------------------------------------------
  // T15 (AC2 + AC4): runImpl secondary→primary fallback → exactly two phase:impl records
  //
  // Verifies the universal fallback (AC4): secondary subprocess fails with a
  // classified error; module retries once on primary and returns primary's outcome.
  // Two routing log records are emitted — one per attempt.
  // -------------------------------------------------------------------------
  test('T15: runImpl fallback (secondary→primary) → exactly two phase:impl records in routing log', async () => {
    setValidEnv();
    const tmpLog = makeTmpLog();
    _setLogPath(tmpLog);

    const reportPath = join(tmpdir(), `gaai-test-E131S03-T15-${Date.now()}.md`);
    // Pre-create report so primary succeeds (secondary fails via non-zero exit + auth error before file check)
    writeFileSync(reportPath, '## QA\nAll good.\n');

    // Stateful mock: first call (secondary) → AUTH_FAILED; second call (primary) → success
    let spawnCallCount = 0;
    _setSpawnFn(() => {
      spawnCallCount++;
      if (spawnCallCount === 1) {
        return createMockChild({ exitCode: 1, stderrData: '401 Unauthorized — invalid_api_key' });
      }
      return createMockChild({ exitCode: 0, stdoutData: '## QA\nAll good.\n' });
    });

    const r = await runImpl({
      implModelTag: 'secondary',
      prompt: 'test-prompt',
      reportPath,
      storyId: 'E131S03-T15',
    });

    assert.equal(r.success, true, 'primary fallback must succeed');
    assert.equal(spawnCallCount, 2, 'exactly two spawn calls must occur (secondary + primary fallback)');

    const records = readLogLines(tmpLog);
    assert.equal(records.length, 2, 'must have exactly two log records (one per attempt)');

    // Record 1: secondary attempt (failed, but logged before triggering fallback)
    assert.equal(records[0].phase, 'impl');
    assert.equal(records[0].provider, 'secondary');
    assert.equal(records[0].impl_model_tag, 'secondary');
    assert.equal(records[0].fallback_reason, null, 'first record has no fallback_reason — it IS the attempt that triggered the fallback');

    // Record 2: primary fallback (carries the reason that triggered the switch)
    assert.equal(records[1].phase, 'impl');
    assert.equal(records[1].provider, 'primary');
    assert.equal(records[1].fallback_reason, 'AUTH_FAILED', 'second record carries the reason that triggered the fallback');

    // Both records share the same trace_id (per runImpl contract)
    assert.equal(records[0].trace_id, records[1].trace_id, 'both records must share the same trace_id');
  });

  // -------------------------------------------------------------------------
  // T16 (AC3): explicit secondary tag + missing env → ⚠ warning emitted, routes to primary
  //
  // Verifies the warning fires only when the operator explicitly tagged the
  // story as secondary — absent/null tags produce no warning (verified in T1).
  // -------------------------------------------------------------------------
  test('T16: explicit secondary tag + missing env → ⚠ warning emitted, routes to primary', async () => {
    clearEnv();
    const tmpLog = makeTmpLog();
    _setLogPath(tmpLog);

    const reportPath = join(tmpdir(), `gaai-test-E131S03-T16-${Date.now()}.md`);
    writeFileSync(reportPath, '## QA\nAll good.\n');

    // Capture stdout to detect the ⚠ warning line (runImpl writes it via process.stdout.write)
    const stdoutLines = [];
    const origWrite = process.stdout.write.bind(process.stdout);
    process.stdout.write = (msg, ...rest) => {
      stdoutLines.push(typeof msg === 'string' ? msg : msg.toString());
      return origWrite(msg, ...rest);
    };

    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: '## QA\nAll good.\n' }));

    let r;
    try {
      r = await runImpl({
        implModelTag: 'secondary',
        prompt: 'test-prompt',
        reportPath,
        storyId: 'E131S03-T16',
      });
    } finally {
      process.stdout.write = origWrite;
    }

    // Routes to primary (env missing) → mock succeeds
    assert.notEqual(r.error_reason, 'ENV_MISSING');
    assert.equal(r.success, true);

    // Warning must be emitted because operator explicitly tagged as secondary
    const hasWarning = stdoutLines.some(l => l.includes('⚠ impl_model=secondary'));
    assert.equal(hasWarning, true, '⚠ warning must be emitted when explicit secondary tag + missing env');
  });

  // -------------------------------------------------------------------------
  // T17 (E131S08 AC1): secondary mode + full stream-json → all 4 telemetry fields in log record
  // -------------------------------------------------------------------------
  test('T17: secondary mode + stream-json with all event types → 4 telemetry fields in log record', async () => {
    setValidEnv();
    const tmpLog = makeTmpLog();
    _setLogPath(tmpLog);

    const reportPath = join(tmpdir(), `gaai-test-E131S08-T17-${Date.now()}.md`);
    writeFileSync(reportPath, '# impl report\n');

    // stream-json with all 4 telemetry signals
    const streamJson = [
      JSON.stringify({ type: 'system', subtype: 'compact_boundary' }),
      JSON.stringify({ type: 'system', subtype: 'api_retry', error_status: 429 }),
      JSON.stringify({ type: 'system', subtype: 'api_retry', error_status: 429 }),
      JSON.stringify({ type: 'assistant', message: { stop_reason: 'end_turn', usage: { input_tokens: 5678, output_tokens: 100 } } }),
    ].join('\n') + '\n';

    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: streamJson }));

    const r = await runImpl({
      implModelTag: 'secondary',  // explicit opt-in (default flipped to primary)
      prompt: 'test-prompt',
      reportPath,
      storyId: 'E131S08-T17',
    });

    assert.equal(r.success, true);

    const records = readLogLines(tmpLog);
    assert.equal(records.length, 1);
    const rec = records[0];
    assert.equal(rec.provider, 'secondary');

    // AC1: all 4 telemetry fields present with correct values
    assert.equal(rec.context_size_at_spawn,   5678, 'context_size_at_spawn must equal last assistant input_tokens');
    assert.equal(rec.compact_events_count,    1,    'compact_events_count must equal number of compact_boundary events');
    assert.equal(rec.retry_429_count,         2,    'retry_429_count must equal number of api_retry 429 events');
    assert.equal(rec.nested_session_completed, true, 'nested_session_completed must be true when stop_reason=end_turn');
  });

  // -------------------------------------------------------------------------
  // T18 (E131S08 AC2): primary mode → no telemetry fields in log record
  // -------------------------------------------------------------------------
  test('T18: primary mode (explicit tag) → no telemetry fields in log record (AC2)', async () => {
    clearEnv();  // env missing → any tag routes to primary
    const tmpLog = makeTmpLog();
    _setLogPath(tmpLog);

    const reportPath = join(tmpdir(), `gaai-test-E131S08-T18-${Date.now()}.md`);
    writeFileSync(reportPath, '# impl report\n');

    const streamJson = JSON.stringify({ type: 'assistant', message: { stop_reason: 'end_turn', usage: { input_tokens: 999 } } }) + '\n';
    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: streamJson }));

    const r = await runImpl({
      implModelTag: 'primary',  // explicit opt-out → always primary
      prompt: 'test-prompt',
      reportPath,
      storyId: 'E131S08-T18',
    });

    assert.equal(r.success, true);

    const records = readLogLines(tmpLog);
    assert.equal(records.length, 1);
    const rec = records[0];
    assert.equal(rec.provider, 'primary');

    // AC2: telemetry fields must be absent (not null, not zero — absent)
    assert.ok(!('context_size_at_spawn'    in rec), 'context_size_at_spawn must be absent for primary');
    assert.ok(!('compact_events_count'     in rec), 'compact_events_count must be absent for primary');
    assert.ok(!('retry_429_count'          in rec), 'retry_429_count must be absent for primary');
    assert.ok(!('nested_session_completed' in rec), 'nested_session_completed must be absent for primary');
  });

  // -------------------------------------------------------------------------
  // T19 (E131S08 AC3): secondary mode + no assistant event → context_size_at_spawn absent + stderr warning
  // -------------------------------------------------------------------------
  test('T19: secondary mode + no assistant event → context_size_at_spawn absent, warning on stderr', async () => {
    setValidEnv();
    const tmpLog = makeTmpLog();
    _setLogPath(tmpLog);

    const reportPath = join(tmpdir(), `gaai-test-E131S08-T19-${Date.now()}.md`);
    writeFileSync(reportPath, '# impl report\n');

    // stdout has system events but no assistant event → no input_tokens
    const streamJson = [
      JSON.stringify({ type: 'system', subtype: 'compact_boundary' }),
      JSON.stringify({ type: 'system', subtype: 'api_retry', error_status: 429 }),
    ].join('\n') + '\n';

    // Capture stderr to detect the WARNING
    const stderrLines = [];
    const origStderr = process.stderr.write.bind(process.stderr);
    process.stderr.write = (msg, ...rest) => {
      stderrLines.push(typeof msg === 'string' ? msg : msg.toString());
      return origStderr(msg, ...rest);
    };

    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: streamJson }));

    let r;
    try {
      r = await runImpl({
        implModelTag: 'secondary',  // explicit opt-in (default flipped to primary)
        prompt: 'test-prompt',
        reportPath,
        storyId: 'E131S08-T19',
      });
    } finally {
      process.stderr.write = origStderr;
    }

    assert.equal(r.success, true);

    const records = readLogLines(tmpLog);
    assert.equal(records.length, 1);
    const rec = records[0];

    // context_size_at_spawn must be absent (no assistant event)
    assert.ok(!('context_size_at_spawn' in rec), 'context_size_at_spawn must be absent when no assistant event');

    // The other 3 fields must still be present
    assert.equal(rec.compact_events_count,    1,     'compact_events_count must still be computed');
    assert.equal(rec.retry_429_count,         1,     'retry_429_count must still be computed');
    assert.equal(rec.nested_session_completed, false, 'nested_session_completed must be false (no stop_reason)');

    // AC3: warning must be emitted for the missing field
    const warnings = stderrLines.filter(l => l.includes('[nested-claude-spawn] WARNING') && l.includes('context_size_at_spawn'));
    assert.ok(warnings.length >= 1, 'WARNING for context_size_at_spawn must be emitted on stderr');
  });

  // -------------------------------------------------------------------------
  // T20 (E131S08 AC5): primary path → no field collection overhead
  // -------------------------------------------------------------------------
  test('T20: primary path (env missing + absent tag) → SpawnResult.telemetry is null (AC5)', async () => {
    clearEnv();
    const tmpLog = makeTmpLog();
    _setLogPath(tmpLog);

    const reportPath = join(tmpdir(), `gaai-test-E131S08-T20-${Date.now()}.md`);
    writeFileSync(reportPath, '# impl report\n');

    const streamJson = JSON.stringify({ type: 'assistant', message: { stop_reason: 'end_turn', usage: { input_tokens: 42 } } }) + '\n';
    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: streamJson }));

    const r = await runImpl({
      implModelTag: null,  // absent + env missing → primary (DEC-72 Row 5)
      prompt: 'test-prompt',
      reportPath,
      storyId: 'E131S08-T20',
    });

    assert.equal(r.success, true);
    // Primary path: telemetry must be null (no collection runs, AC5)
    assert.equal(r.telemetry, null, 'SpawnResult.telemetry must be null for primary path');
  });

});

// ---------------------------------------------------------------------------
// resolveMode — DEC-72 five-row decision matrix (AC1)
//
// Pure function tests: no I/O, no env mutation, no subprocess. Each test
// verifies both the resolved routing mode and the tag_recorded value written
// to the audit log — covering all five rows of the DEC-72 matrix.
// ---------------------------------------------------------------------------

describe('resolveMode (DEC-72 five-row matrix)', () => {

  const fullEnv    = { hasBaseUrl: true,  hasAuthToken: true,  hasModel: true  };
  const emptyEnv   = { hasBaseUrl: false, hasAuthToken: false, hasModel: false };
  const partialEnv = { hasBaseUrl: true,  hasAuthToken: false, hasModel: true  };

  // Row 1: explicit primary opt-out — always primary regardless of env
  test('Row 1a: primary tag + env configured → mode=primary, tag_recorded=primary', () => {
    const r = resolveMode('primary', fullEnv);
    assert.equal(r.mode, 'primary');
    assert.equal(r.tag_recorded, 'primary');
  });

  test('Row 1b: primary tag + env missing → mode=primary, tag_recorded=primary', () => {
    const r = resolveMode('primary', emptyEnv);
    assert.equal(r.mode, 'primary');
    assert.equal(r.tag_recorded, 'primary');
  });

  // Row 2: explicit secondary + env configured → secondary
  test('Row 2: secondary tag + env configured → mode=secondary, tag_recorded=secondary', () => {
    const r = resolveMode('secondary', fullEnv);
    assert.equal(r.mode, 'secondary');
    assert.equal(r.tag_recorded, 'secondary');
  });

  // Row 3: explicit secondary + env missing → primary (warn path; tag still recorded as secondary)
  test('Row 3a: secondary tag + env fully missing → mode=primary, tag_recorded=secondary', () => {
    const r = resolveMode('secondary', emptyEnv);
    assert.equal(r.mode, 'primary');
    assert.equal(r.tag_recorded, 'secondary');
  });

  test('Row 3b: secondary tag + env partially configured → mode=primary, tag_recorded=secondary', () => {
    const r = resolveMode('secondary', partialEnv);
    assert.equal(r.mode, 'primary');
    assert.equal(r.tag_recorded, 'secondary');
  });

  // Row 4: absent/null tag + env configured → secondary (env-driven default)
  // Universal fallback absorbs the rare failure cases by cascading to primary.
  test('Row 4a: absent sentinel + env configured → mode=secondary, tag_recorded=absent', () => {
    const r = resolveMode('absent', fullEnv);
    assert.equal(r.mode, 'secondary');
    assert.equal(r.tag_recorded, 'absent');
  });

  test('Row 4b: null (no backlog tag) + env configured → mode=secondary, tag_recorded=absent', () => {
    const r = resolveMode(null, fullEnv);
    assert.equal(r.mode, 'secondary');
    assert.equal(r.tag_recorded, 'absent');
  });

  test('Row 4c: undefined (no backlog tag) + env configured → mode=secondary, tag_recorded=absent', () => {
    const r = resolveMode(undefined, fullEnv);
    assert.equal(r.mode, 'secondary');
    assert.equal(r.tag_recorded, 'absent');
  });

  // Row 5: absent/null tag + env missing → primary (OSS non-regression, E94 D-0 preserved)
  test('Row 5a: absent sentinel + env missing → mode=primary, tag_recorded=absent', () => {
    const r = resolveMode('absent', emptyEnv);
    assert.equal(r.mode, 'primary');
    assert.equal(r.tag_recorded, 'absent');
  });

  test('Row 5b: null + env missing → mode=primary, tag_recorded=absent', () => {
    const r = resolveMode(null, emptyEnv);
    assert.equal(r.mode, 'primary');
    assert.equal(r.tag_recorded, 'absent');
  });

  test('Row 5c: undefined + env missing → mode=primary, tag_recorded=absent', () => {
    const r = resolveMode(undefined, emptyEnv);
    assert.equal(r.mode, 'primary');
    assert.equal(r.tag_recorded, 'absent');
  });

});

// ---------------------------------------------------------------------------
// Terminal receipts for long-running runs
//
// An expiring observation window used to end the run: the wrapper killed the
// child, discarded the session_id it had already seen, and reported a failure
// built from partial output — while the child went on to finish correctly.
// These cover the retained handle, the poll-to-receipt path, and the outcome
// being decided on the receipt rather than on the exit code our own kill produced.
// ---------------------------------------------------------------------------

/**
 * Mock child driven by a script of timed stdout chunks, then a close.
 * @param {Array<{ at: number, data: string }>} chunks - emission schedule (ms from spawn)
 * @param {{ closeAt: number, exitCode: number|null, onKill?: Function }} end
 */
function createScriptedChild(chunks, { closeAt, exitCode = null, onKill }) {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  child.kill = (signal) => { if (onKill) onKill(signal); };

  for (const { at, data } of chunks) {
    setTimeout(() => child.stdout.emit('data', Buffer.from(data)), at);
  }
  setTimeout(() => {
    child.exitCode = exitCode;
    child.emit('close', exitCode);
  }, closeAt);

  return child;
}

const INIT_LINE   = (sid) => JSON.stringify({ type: 'system', subtype: 'init', session_id: sid }) + '\n';
const RESULT_LINE = (sid) => JSON.stringify({ type: 'result', subtype: 'success', is_error: false, session_id: sid }) + '\n';

describe('nested-claude-spawn — terminal receipts', () => {

  afterEach(() => {
    _resetSpawnFn();
    _resetLogPath();
    clearEnv();
  });

  test('a run that finishes after its window expired is a success, not a timeout', async () => {
    setValidEnv();
    useTmpHandleDir();
    setPollBudget(5_000);

    const reportPath = join(mkdtempSync(join(tmpdir(), 'gaai-test-receipt-')), 'impl-report.md');

    const killSignals = [];
    _setSpawnFn(() => createScriptedChild(
      [
        { at: 10,  data: INIT_LINE('sess-late-finish') },
        // Silence past the heartbeat window → wrapper demotes to poll mode.
        { at: 400, data: (writeFileSync(reportPath, '## Implementation\ndone\n'), RESULT_LINE('sess-late-finish')) },
      ],
      // Exit code is null: the child ended without a clean code, exactly as it
      // would after a signal. The receipt plus the artefact is what decides.
      { closeAt: 450, exitCode: null, onKill: (s) => killSignals.push(s) }
    ));

    const r = await _spawnWithTimerOverride(
      'test-prompt', reportPath, [],
      { globalTimeoutMs: 60_000, heartbeatTimeoutMs: 150 }
    );

    assert.equal(r.observation_window_expired, true, 'the heartbeat window must have expired');
    assert.equal(r.terminal_receipt, true, 'the terminal result event must have been observed');
    assert.equal(r.session_id, 'sess-late-finish', 'the session_id must be retained, not discarded');
    assert.equal(r.success, true, 'a completed run must not be graded as a failure');
    assert.equal(r.error_reason, null);
    assert.deepEqual(killSignals, [], 'a still-running child must not be killed at window expiry');
  });

  test('output resuming after a window expiry returns the run to normal watching', async () => {
    setValidEnv();
    useTmpHandleDir();
    setPollBudget(5_000);

    const reportPath = join(mkdtempSync(join(tmpdir(), 'gaai-test-resume-')), 'impl-report.md');

    _setSpawnFn(() => createScriptedChild(
      [
        { at: 10,  data: INIT_LINE('sess-resume') },
        { at: 300, data: JSON.stringify({ type: 'assistant', message: { content: 'still working' } }) + '\n' },
        { at: 400, data: (writeFileSync(reportPath, '## Implementation\ndone\n'), RESULT_LINE('sess-resume')) },
      ],
      { closeAt: 450, exitCode: 0 }
    ));

    const r = await _spawnWithTimerOverride(
      'test-prompt', reportPath, [],
      { globalTimeoutMs: 60_000, heartbeatTimeoutMs: 150 }
    );

    assert.equal(r.observation_window_expired, true);
    assert.equal(r.success, true);
    assert.equal(r.session_id, 'sess-resume');
  });

  test('session_id split across two stdout chunks is still captured', async () => {
    setValidEnv();
    useTmpHandleDir();

    const line  = INIT_LINE('sess-split');
    const cut   = Math.floor(line.length / 2);

    _setSpawnFn(() => createScriptedChild(
      [
        { at: 5,  data: line.slice(0, cut) },
        { at: 20, data: line.slice(cut) },
      ],
      { closeAt: 60, exitCode: 0 }
    ));

    const r = await _spawnWithTimerOverride(
      'test-prompt', '', [],
      { globalTimeoutMs: 60_000, heartbeatTimeoutMs: 60_000 }
    );

    assert.equal(r.session_id, 'sess-split',
      'a chunk boundary inside the init line must not lose the identifier');
  });

  test('the handle record is removed once the run reaches a terminal state', async () => {
    setValidEnv();
    const handleDir = useTmpHandleDir();

    _setSpawnFn(() => createScriptedChild(
      [{ at: 5, data: INIT_LINE('sess-handle') }],
      { closeAt: 40, exitCode: 0 }
    ));

    await _spawnWithTimerOverride(
      'test-prompt', '', [],
      { globalTimeoutMs: 60_000, heartbeatTimeoutMs: 60_000 }
    );

    const leftover = readdirSync(handleDir).filter(f => f.endsWith('.json'));
    assert.deepEqual(leftover, [], 'a concluded run must leave no handle behind');
  });

  test('reconcileHandles prunes dead handles and preserves live ones', () => {
    const handleDir = useTmpHandleDir();

    // A handle whose process is gone: pid 2^22 is above every configured pid_max.
    writeFileSync(join(handleDir, 'dead.json'),
      JSON.stringify({ trace_id: 'dead', pid: 4_194_304, state: 'polling' }), 'utf8');
    // A handle that is demonstrably alive: this very test process.
    writeFileSync(join(handleDir, 'live.json'),
      JSON.stringify({ trace_id: 'live', pid: process.pid, state: 'running' }), 'utf8');

    const report = reconcileHandles();

    assert.deepEqual(report.stale.map(r => r.trace_id), ['dead']);
    assert.deepEqual(report.live.map(r => r.trace_id), ['live']);
    assert.equal(existsSync(join(handleDir, 'dead.json')), false, 'a dead handle must be pruned');
    assert.equal(existsSync(join(handleDir, 'live.json')), true,
      'a live handle must survive — pruning it is what lets recovery spawn a duplicate');
  });

});

// ---------------------------------------------------------------------------
// Hard ceiling + handle ageing
//
// Regressions caught in review of the poll-mode change. Poll mode made the
// global window a one-shot entry point instead of a bound, and handle liveness
// trusted a bare pid forever. Both let a run escape its limits.
// ---------------------------------------------------------------------------

/** Mock child that emits a byte every `everyMs` and never finishes. */
function createChattyChild(everyMs, onKill) {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  let killCount = 0;
  const beat = setInterval(() => child.stdout.emit('data', Buffer.from('{"type":"assistant"}\n')), everyMs);
  child.kill = (signal) => {
    killCount++;
    if (onKill) onKill(signal);
    if (killCount >= 2) { clearInterval(beat); setImmediate(() => child.emit('close', null)); }
  };
  return child;
}

describe('nested-claude-spawn — hard ceiling', () => {

  afterEach(() => {
    _resetSpawnFn();
    _resetLogPath();
    clearEnv();
  });

  test('a child chatty enough to keep resetting the heartbeat is still stopped at the ceiling', async () => {
    setValidEnv();
    useTmpHandleDir();
    setPollBudget(100);

    const killSignals = [];
    // Beats every 60ms: comfortably under the 400ms heartbeat, so the heartbeat
    // alone would never fire and the run would never end.
    _setSpawnFn(() => createChattyChild(60, (sig) => killSignals.push(sig)));

    const started = Date.now();
    const r = await _spawnWithTimerOverride(
      'test-prompt', '/tmp/test-ceiling.md', [],
      { globalTimeoutMs: 300, heartbeatTimeoutMs: 400 }
    );

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'TIMEOUT', 'the ceiling must be the reason, not the heartbeat');
    assert.ok(killSignals.includes('SIGTERM'), 'the ceiling must actually kill');
    assert.ok(Date.now() - started < 10_000,
      'the run must end shortly after the ceiling, not stream on indefinitely');
  });

  test('output resuming past the ceiling does not buy the run more time', async () => {
    setValidEnv();
    useTmpHandleDir();
    setPollBudget(500);

    const killSignals = [];
    // Silent through the heartbeat (150ms) so poll mode opens, then chatty from
    // 500ms — past the 400ms ceiling. Before the fix that late output left poll
    // mode and re-armed only the heartbeat, so the chatter ran on unbounded.
    _setSpawnFn(() => {
      const child = new EventEmitter();
      child.stdout = new EventEmitter();
      child.stderr = new EventEmitter();
      child.exitCode = null;
      let killCount = 0;
      let beat = null;
      const start = setTimeout(() => {
        beat = setInterval(() => child.stdout.emit('data', Buffer.from('{"type":"assistant"}\n')), 60);
      }, 500);
      child.kill = (signal) => {
        killCount++;
        killSignals.push(signal);
        if (killCount >= 2) {
          clearTimeout(start); if (beat) clearInterval(beat);
          setImmediate(() => child.emit('close', null));
        }
      };
      return child;
    });

    const started = Date.now();
    const r = await _spawnWithTimerOverride(
      'test-prompt', '/tmp/test-ceiling-resume.md', [],
      { globalTimeoutMs: 400, heartbeatTimeoutMs: 150 }
    );

    assert.equal(r.success, false);
    assert.ok(killSignals.includes('SIGTERM'), 'the run must be killed despite resumed output');
    assert.ok(Date.now() - started < 10_000,
      'resumed output past the ceiling must not restart the heartbeat cycle');
  });

  test('an over-age handle is not believed, and its process is left alone', () => {
    const handleDir = useTmpHandleDir();
    process.env.GAAI_RUNNER_HANDLE_MAX_AGE_MS = '1000';

    // Alive pid (this process), but recorded long enough ago that the pid can no
    // longer be trusted to belong to the recorded run.
    writeFileSync(join(handleDir, 'aged.json'), JSON.stringify({
      trace_id: 'aged',
      pid: process.pid,
      cwd: '/tmp/example-aged-workspace',
      started_at: new Date(Date.now() - 60_000).toISOString(),
      state: 'polling',
    }), 'utf8');

    const report = reconcileHandles();

    assert.deepEqual(report.live, [], 'an over-age handle must not count as live');
    assert.deepEqual(report.expired.map(r => r.trace_id), ['aged']);
    assert.equal(existsSync(join(handleDir, 'aged.json')), false,
      'the record must be pruned, or recovery stays blocked forever');
    // The decisive part: we are still running. Signalling a recycled pid would be
    // the actual damage this branch exists to avoid.
    assert.equal(_isAliveSelfCheck(), true, 'reconcile must never signal an over-age pid');
  });

  test('a fresh handle with a live pid is still believed', () => {
    const handleDir = useTmpHandleDir();

    writeFileSync(join(handleDir, 'fresh.json'), JSON.stringify({
      trace_id: 'fresh',
      pid: process.pid,
      cwd: '/tmp/example-fresh-workspace',
      started_at: new Date().toISOString(),
      state: 'running',
    }), 'utf8');

    const report = reconcileHandles();

    assert.deepEqual(report.live.map(r => r.trace_id), ['fresh']);
    assert.deepEqual(report.expired, []);
    assert.equal(existsSync(join(handleDir, 'fresh.json')), true);
  });

});

/** Proves this process survived the call above. */
function _isAliveSelfCheck() {
  try { process.kill(process.pid, 0); return true; } catch { return false; }
}

// ---------------------------------------------------------------------------
// Handle identity
//
// A handle that cannot name its own story forces consumers to infer identity
// from the worktree path. These pin the recorded fields, and pin the one thing
// that must never appear in them.
// ---------------------------------------------------------------------------

describe('nested-claude-spawn — handle identity', () => {

  afterEach(() => {
    _resetSpawnFn();
    _resetLogPath();
    clearEnv();
    delete process.env.GAAI_STORY_ID;
    delete process.env.GAAI_WORKSPACE_ID;
  });

  test('the in-flight handle names its story, workspace, phase and command', async () => {
    setValidEnv();
    const handleDir = useTmpHandleDir();
    process.env.GAAI_STORY_ID     = 'EXAMPLE-STORY';
    process.env.GAAI_WORKSPACE_ID = 'ws-example';

    _setSpawnFn(() => createMockChild({ exitCode: 0, stdoutData: '## Implementation\n', delay: 400 }));

    // Deliberately not awaited: the record is written synchronously at spawn, and
    // it is removed once the run concludes — mid-flight is the only time to read it.
    const pending = _spawnWithTimerOverride(
      'a-prompt-that-must-not-be-recorded', '', [],
      { globalTimeoutMs: 60_000, heartbeatTimeoutMs: 60_000 }
    );

    const files = readdirSync(handleDir).filter(f => f.endsWith('.json'));
    assert.equal(files.length, 1, 'exactly one in-flight handle');
    const raw = readFileSync(join(handleDir, files[0]), 'utf8');
    const rec = JSON.parse(raw);

    assert.equal(rec.story_id, 'EXAMPLE-STORY');
    assert.equal(rec.workspace_id, 'ws-example');
    assert.equal(rec.phase, 'impl');
    assert.equal(typeof rec.command?.bin, 'string');
    assert.ok(rec.started_at, 'started_at recorded');
    assert.ok(rec.last_activity_at, 'last_activity_at recorded');

    // The argv carries the prompt. A handle file is not a place for prompt content.
    assert.equal(raw.includes('a-prompt-that-must-not-be-recorded'), false,
      'the prompt must never be persisted into the handle');

    await pending;
    assert.deepEqual(readdirSync(handleDir).filter(f => f.endsWith('.json')), [],
      'the handle is cleared once the run concludes');
  });

  test('reconcile reports the story so callers need not parse a path', () => {
    const handleDir = useTmpHandleDir();
    writeFileSync(join(handleDir, 'h.json'), JSON.stringify({
      trace_id: 'h',
      pid: process.pid,
      story_id: 'EXAMPLE-STORY',
      cwd: '/tmp/some-unrelated-path',
      started_at: new Date().toISOString(),
      state: 'running',
    }), 'utf8');

    const report = reconcileHandles();
    assert.equal(report.live.length, 1);
    assert.equal(report.live[0].story_id, 'EXAMPLE-STORY',
      'story identity survives reconciliation without path inference');
  });

});
