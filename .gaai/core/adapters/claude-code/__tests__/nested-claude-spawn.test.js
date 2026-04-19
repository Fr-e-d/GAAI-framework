/**
 * nested-claude-spawn.test.js
 *
 * Unit tests for nested-claude-spawn.js using node:test and node:assert (built-in).
 * Run with: node --test .gaai/core/adapters/claude-code/__tests__/nested-claude-spawn.test.js
 */

import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';

import {
  spawnNestedClaude,
  _spawnWithTimerOverride,
  _setSpawnFn,
  _resetSpawnFn,
} from '../nested-claude-spawn.js';

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
// Tests
// ---------------------------------------------------------------------------

describe('nested-claude-spawn', () => {

  afterEach(() => {
    _resetSpawnFn();
    clearEnv();
  });

  // -------------------------------------------------------------------------
  // T1: ENV_MISSING
  // -------------------------------------------------------------------------
  test('T1: ENV_MISSING - returns ENV_MISSING without spawning', async () => {
    clearEnv();

    const r = await spawnNestedClaude('test-prompt', '/tmp/test-report.md');

    assert.equal(r.error_reason, 'ENV_MISSING');
    assert.equal(r.success, false);
    assert.equal(r.exit_code, null);
    assert.equal(r.impl_report_path, null);
    // UUID must be present (non-empty string matching UUID pattern)
    assert.ok(r.trace_id, 'trace_id must be non-empty');
    assert.match(r.trace_id, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
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

});
