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
import { writeFileSync, mkdirSync, existsSync, readFileSync, mkdtempSync, statSync, chmodSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';

import {
  spawnNestedClaude,
  _spawnWithTimerOverride,
  _setSpawnFn,
  _resetSpawnFn,
  resolveMode,
  runImpl,
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

    _setSpawnFn(() => createHangingChild());

    const r = await _spawnWithTimerOverride(
      'test-prompt', '/tmp/test-heartbeat.md', [],
      { globalTimeoutMs: 60_000, heartbeatTimeoutMs: 200 }
    );

    assert.equal(r.success, false);
    assert.equal(r.error_reason, 'HEARTBEAT_TIMEOUT');
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
