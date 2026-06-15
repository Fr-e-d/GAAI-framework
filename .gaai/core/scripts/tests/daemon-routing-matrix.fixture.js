/**
 * daemon-routing-matrix.fixture.js
 *
 * Matrix regression test for the the proxy/direct compatibility contract proxy/direct compatibility contract.
 * Covers all five rows of the compatibility matrix × {Plan-equivalent primary,
 * Impl secondary, Impl primary, QA-equivalent primary} env checks.
 *
 * AC4: deterministic test verifying env seen by Plan, Impl, and QA for all
 *      supported combinations including proxy failure/fallback semantics.
 * AC5: named regression assertion that proxy mode must not let
 *      GAAI_IMPL_BASE_URL overwrite ANTHROPIC_BASE_URL.
 *
 * Run with:
 *   node --test .gaai/core/scripts/tests/daemon-routing-matrix.fixture.js
 */

import { describe, test, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const __dirname = dirname(fileURLToPath(import.meta.url));

import {
  _setSpawnFn,
  _resetSpawnFn,
  runImpl,
} from '../../adapters/claude-code/nested-claude-spawn.js';

import { _setLogPath, _resetLogPath } from '../../adapters/claude-code/runtime-routing-logger.js';

// ---------------------------------------------------------------------------
// Constants matching the proxy/direct compatibility contract compatibility contract
// ---------------------------------------------------------------------------

const PROXY_URL  = 'http://127.0.0.1:8787'; // illustrative gateway address
const IMPL_URL   = 'https://api.z.ai/coding/paas/v4';
const IMPL_AUTH  = 'test-impl-token';
const IMPL_MODEL = 'glm-4.6';

// All env vars touched by this test — saved and restored around the suite.
const ROUTING_VARS = [
  'GAAI_IMPL_BASE_URL',
  'GAAI_IMPL_AUTH_TOKEN',
  'GAAI_IMPL_MODEL',
  'GAAI_IMPL_MODEL_FALLBACK',
  'GAAI_CLAUDE_PROXY_BASE_URL',
  'ANTHROPIC_BASE_URL',
  'GAAI_NESTED_KEEP_MCP',
];

// ---------------------------------------------------------------------------
// Mock child process helper
// ---------------------------------------------------------------------------

function createMockChild({ exitCode = 0, stdoutData = '', delay = 10 } = {}) {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.exitCode = null;
  child.kill = () => {
    setImmediate(() => { child.exitCode = null; child.emit('close', null); });
  };
  process.nextTick(() => {
    if (stdoutData) child.stdout.emit('data', Buffer.from(stdoutData));
    setTimeout(() => { child.exitCode = exitCode; child.emit('close', exitCode); }, delay);
  });
  return child;
}

// ---------------------------------------------------------------------------
// Spawn-capture helper
// Returns a calls array. Each entry: { binPath, args, env }.
// ---------------------------------------------------------------------------

function setupSpawnCapture({ perCallFn } = {}) {
  const calls = [];
  _setSpawnFn((binPath, spawnArgs, spawnOpts) => {
    const entry = { binPath, args: spawnArgs, env: spawnOpts.env };
    calls.push(entry);
    if (perCallFn) return perCallFn(calls.length - 1, entry);
    return createMockChild({ exitCode: 0, stdoutData: '## QA\nall good.' });
  });
  return calls;
}

// ---------------------------------------------------------------------------
// Env helpers
// ---------------------------------------------------------------------------

function setProxyEnv() { process.env.GAAI_CLAUDE_PROXY_BASE_URL = PROXY_URL; }

function setImplEnv() {
  process.env.GAAI_IMPL_BASE_URL   = IMPL_URL;
  process.env.GAAI_IMPL_AUTH_TOKEN = IMPL_AUTH;
  process.env.GAAI_IMPL_MODEL      = IMPL_MODEL;
}

function clearRoutingEnv() {
  for (const k of ROUTING_VARS) delete process.env[k];
}

// ---------------------------------------------------------------------------
// runImpl wrappers mirroring real daemon phase usage
//
// Plan and QA use the primary subprocess path (buildPrimaryChildEnv).
// runImpl({ implModelTag: 'primary' }) exercises that path.
// runImpl({ implModelTag: null })      exercises secondary when env is set,
//                                      primary (via buildPrimaryChildEnv) when env is absent.
// ---------------------------------------------------------------------------

const BASE_OPTS = { prompt: 'matrix-test', reportPath: '', storyId: 'matrix-test' };

async function runPlanOrQA() {
  // Plan and QA always use the primary subprocess path.
  return runImpl({ ...BASE_OPTS, implModelTag: 'primary' });
}

async function runImplSecondary() {
  // Secondary path: resolveMode routes to secondary when GAAI_IMPL_* env is set.
  return runImpl({ ...BASE_OPTS, implModelTag: null });
}

async function runImplPrimary() {
  // Explicit primary opt-out (also the path when env is absent).
  return runImpl({ ...BASE_OPTS, implModelTag: 'primary' });
}

// ---------------------------------------------------------------------------
// Suite state
// ---------------------------------------------------------------------------

let savedRoutingVars = {};
let savedPath;
let fakeBinDir;
let tmpLog;

// ---------------------------------------------------------------------------
// Suite setup: isolate env + inject fake claude binary for findCLI()
// ---------------------------------------------------------------------------

before(() => {
  for (const k of ROUTING_VARS) {
    savedRoutingVars[k] = process.env[k];
    delete process.env[k];
  }

  // Inject a fake `claude` binary — _setSpawnFn intercepts before it runs.
  fakeBinDir = mkdtempSync(join(tmpdir(), 'gaai-matrix-test-'));
  const fakeClaude = join(fakeBinDir, 'claude');
  writeFileSync(fakeClaude, '#!/bin/sh\nexec true\n', { mode: 0o755 });
  savedPath = process.env.PATH;
  process.env.PATH = fakeBinDir + (savedPath ? ':' + savedPath : '');

  // Redirect routing log to tmp location.
  tmpLog = join(fakeBinDir, 'runtime-routing.jsonl');
  _setLogPath(tmpLog);
});

after(() => {
  process.env.PATH = savedPath;
  _resetLogPath();
  for (const k of ROUTING_VARS) {
    if (savedRoutingVars[k] !== undefined) {
      process.env[k] = savedRoutingVars[k];
    } else {
      delete process.env[k];
    }
  }
});

beforeEach(() => clearRoutingEnv());

afterEach(() => {
  _resetSpawnFn();
  clearRoutingEnv();
});

// ===========================================================================
// Matrix Row 1 — No proxy, no GAAI_IMPL_*
// Expected: primary Claude behavior unchanged.
// ===========================================================================

describe('Row 1 — no proxy, no GAAI_IMPL_* (primary direct, unchanged)', () => {

  test('Plan/QA env: ANTHROPIC_BASE_URL not injected', async () => {
    const calls = setupSpawnCapture();
    await runPlanOrQA();
    assert.equal(calls.length, 1, 'single spawn');
    assert.equal(calls[0].env.ANTHROPIC_BASE_URL, undefined,
      'ANTHROPIC_BASE_URL must not be set when no proxy and no GAAI_IMPL_* configured');
  });

  test('Impl primary env: ANTHROPIC_BASE_URL not injected', async () => {
    const calls = setupSpawnCapture();
    await runImplPrimary();
    assert.equal(calls[0].env.ANTHROPIC_BASE_URL, undefined,
      'ANTHROPIC_BASE_URL must not be set in primary Impl env (no proxy, no GAAI_IMPL_*)');
  });

  test('Plan/QA env: CLAUDECODE blanked for nested detection bypass', async () => {
    const calls = setupSpawnCapture();
    await runPlanOrQA();
    assert.equal(calls[0].env.CLAUDECODE, '', 'CLAUDECODE must be empty string');
  });

});

// ===========================================================================
// Matrix Row 2 — No proxy, GAAI_IMPL_* configured
// Expected: existing direct secondary Impl routing unchanged.
// ===========================================================================

describe('Row 2 — no proxy, GAAI_IMPL_* configured (direct secondary Impl, unchanged)', () => {

  test('Plan/QA env: ANTHROPIC_BASE_URL NOT set (proxy absent, primary path)', async () => {
    setImplEnv();
    const calls = setupSpawnCapture();
    await runPlanOrQA();
    assert.equal(calls[0].env.ANTHROPIC_BASE_URL, undefined,
      'Plan/QA primary path must not pick up GAAI_IMPL_BASE_URL as ANTHROPIC_BASE_URL');
  });

  test('Impl secondary env: ANTHROPIC_BASE_URL = GAAI_IMPL_BASE_URL (direct routing)', async () => {
    setImplEnv();
    const calls = setupSpawnCapture();
    await runImplSecondary();
    assert.ok(calls.length >= 1);
    assert.equal(calls[0].env.ANTHROPIC_BASE_URL, IMPL_URL,
      'Direct secondary Impl must map GAAI_IMPL_BASE_URL to ANTHROPIC_BASE_URL');
  });

  test('Impl secondary env: GAAI_IMPL_AUTH_TOKEN → ANTHROPIC_AUTH_TOKEN', async () => {
    setImplEnv();
    const calls = setupSpawnCapture();
    await runImplSecondary();
    assert.equal(calls[0].env.ANTHROPIC_AUTH_TOKEN, IMPL_AUTH);
  });

  test('Impl secondary env: GAAI_IMPL_MODEL → ANTHROPIC_DEFAULT_OPUS_MODEL', async () => {
    setImplEnv();
    const calls = setupSpawnCapture();
    await runImplSecondary();
    assert.equal(calls[0].env.ANTHROPIC_DEFAULT_OPUS_MODEL, IMPL_MODEL);
  });

});

// ===========================================================================
// Matrix Row 3 — GAAI_CLAUDE_PROXY_BASE_URL only, no GAAI_IMPL_*
// Expected: Plan, Impl, and QA claude -p use the proxy; provider stays primary/default.
// ===========================================================================

describe('Row 3 — proxy only, no GAAI_IMPL_* (all phases use proxy, primary provider)', () => {

  test('Plan/QA env: ANTHROPIC_BASE_URL = proxy URL', async () => {
    setProxyEnv();
    const calls = setupSpawnCapture();
    await runPlanOrQA();
    assert.equal(calls.length, 1);
    assert.equal(calls[0].env.ANTHROPIC_BASE_URL, PROXY_URL,
      'Plan/QA subprocess must route through proxy when GAAI_CLAUDE_PROXY_BASE_URL is set');
  });

  test('Impl env (no GAAI_IMPL_* → primary): ANTHROPIC_BASE_URL = proxy URL', async () => {
    setProxyEnv();
    // No GAAI_IMPL_* → resolveMode Row 5 → primary → buildPrimaryChildEnv
    const calls = setupSpawnCapture();
    await runImplSecondary();
    assert.equal(calls.length, 1, 'single spawn (no secondary path without GAAI_IMPL_*)');
    assert.equal(calls[0].env.ANTHROPIC_BASE_URL, PROXY_URL,
      'Impl primary subprocess must also use proxy transport');
  });

  test('Plan/QA env: --strict-mcp-config injected for non-Anthropic proxy host', async () => {
    setProxyEnv();
    const calls = setupSpawnCapture();
    await runPlanOrQA();
    assert.ok(calls[0].args.includes('--strict-mcp-config'),
      '--strict-mcp-config must be injected when proxy points to a non-Anthropic host');
  });

});

// ===========================================================================
// Matrix Row 4 — GAAI_CLAUDE_PROXY_BASE_URL + GAAI_IMPL_*
// Expected: Plan/QA use proxy+primary; Impl uses proxy transport + secondary
// provider intent forwarded. Gateway routes upstream.
// AC5: proxy must NOT be bypassed by GAAI_IMPL_BASE_URL overwriting ANTHROPIC_BASE_URL.
// ===========================================================================

describe('Row 4 — proxy + GAAI_IMPL_* (Plan/QA: proxy+primary; Impl: proxy transport + secondary intent)', () => {

  test('Plan/QA env: ANTHROPIC_BASE_URL = proxy URL (not GAAI_IMPL_BASE_URL)', async () => {
    setImplEnv();
    setProxyEnv();
    const calls = setupSpawnCapture();
    await runPlanOrQA();
    assert.equal(calls[0].env.ANTHROPIC_BASE_URL, PROXY_URL,
      'Plan/QA must use proxy transport; must not pick up GAAI_IMPL_BASE_URL');
    assert.notEqual(calls[0].env.ANTHROPIC_BASE_URL, IMPL_URL,
      'Plan/QA ANTHROPIC_BASE_URL must not be the secondary Impl URL');
  });

  test('[AC5] Impl secondary env: ANTHROPIC_BASE_URL = proxy URL, NOT GAAI_IMPL_BASE_URL', async () => {
    setImplEnv();
    setProxyEnv();
    const calls = setupSpawnCapture();
    await runImplSecondary();
    assert.ok(calls.length >= 1);
    assert.equal(calls[0].env.ANTHROPIC_BASE_URL, PROXY_URL,
      '[AC5] ANTHROPIC_BASE_URL must equal PROXY_URL in proxy+secondary mode');
    assert.notEqual(calls[0].env.ANTHROPIC_BASE_URL, IMPL_URL,
      '[AC5 regression guard] GAAI_IMPL_BASE_URL must NOT overwrite ANTHROPIC_BASE_URL when proxy is configured');
  });

  test('Impl secondary env: GAAI_IMPL_AUTH_TOKEN still forwarded to ANTHROPIC_AUTH_TOKEN', async () => {
    setImplEnv();
    setProxyEnv();
    const calls = setupSpawnCapture();
    await runImplSecondary();
    assert.equal(calls[0].env.ANTHROPIC_AUTH_TOKEN, IMPL_AUTH,
      'Secondary provider auth token must still reach the subprocess for gateway upstream routing');
  });

  test('Impl secondary env: GAAI_IMPL_MODEL still forwarded to ANTHROPIC_DEFAULT_OPUS_MODEL', async () => {
    setImplEnv();
    setProxyEnv();
    const calls = setupSpawnCapture();
    await runImplSecondary();
    assert.equal(calls[0].env.ANTHROPIC_DEFAULT_OPUS_MODEL, IMPL_MODEL,
      'Secondary provider model intent must reach the subprocess for gateway upstream routing');
  });

  test('Impl secondary env: GAAI_IMPL_MODEL present in child env for gateway observability', async () => {
    setImplEnv();
    setProxyEnv();
    const calls = setupSpawnCapture();
    await runImplSecondary();
    assert.equal(calls[0].env.GAAI_IMPL_MODEL, IMPL_MODEL,
      'GAAI_IMPL_MODEL must be present in child env so the gateway can read provider intent directly');
  });

});

// ===========================================================================
// Matrix Row 5 — Proxy failure / fallback semantics
// Expected: failure/fallback semantics remain explicit; no silent bypass to
// an unintended provider.
// ===========================================================================

describe('Row 5 — proxy failure: fallback must not silently bypass to wrong upstream', () => {

  test('secondary failure in proxy mode → primary fallback still uses proxy URL', async () => {
    setImplEnv();
    setProxyEnv();

    const calls = setupSpawnCapture({
      perCallFn: (idx) => {
        // First spawn (secondary) fails → triggers primary fallback
        if (idx === 0) return createMockChild({ exitCode: 1 });
        // Primary fallback succeeds
        return createMockChild({ exitCode: 0, stdoutData: '## QA\nPASSED.' });
      },
    });

    await runImplSecondary();

    assert.ok(calls.length >= 2, 'must have at least 2 spawns (secondary + primary fallback)');
    assert.equal(calls[0].env.ANTHROPIC_BASE_URL, PROXY_URL,
      'secondary spawn must use proxy URL');
    assert.equal(calls[1].env.ANTHROPIC_BASE_URL, PROXY_URL,
      'primary fallback must also use proxy URL — no silent bypass to direct Anthropic');
  });

  test('primary fallback must not switch to GAAI_IMPL_BASE_URL (would bypass gateway)', async () => {
    setImplEnv();
    setProxyEnv();

    const calls = setupSpawnCapture({
      perCallFn: (idx) => {
        if (idx === 0) return createMockChild({ exitCode: 1 });
        return createMockChild({ exitCode: 0, stdoutData: '## QA\nPASSED.' });
      },
    });

    await runImplSecondary();

    assert.ok(calls.length >= 2, 'fallback must occur');
    assert.notEqual(calls[1].env.ANTHROPIC_BASE_URL, IMPL_URL,
      'primary fallback must not route through GAAI_IMPL_BASE_URL — that would bypass the gateway');
  });

});
