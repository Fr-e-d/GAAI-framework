/**
 * impl-fallback.test.js
 *
 * Integration tests for impl-fallback.js (E94S05 AC7-AC17).
 * Run with: node --test .gaai/core/adapters/claude-code/__tests__/impl-fallback.test.js
 *
 * Tests cover all 8 error classes (T1-T8), double-failure path (T9),
 * secondary success path (T10), and primary-only non-regression (T11).
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

import { executeImplWithFallback } from '../impl-fallback.js';

// ---------------------------------------------------------------------------
// Mock factory helpers
// ---------------------------------------------------------------------------

/**
 * Returns a mock secondaryFn that resolves with a SpawnResult-shaped object.
 * Includes a getCallCount() helper to assert invocation count.
 *
 * @param {Object} opts
 * @param {boolean} opts.success
 * @param {string|null} [opts.error_reason]
 * @param {string} [opts.trace_id]
 */
function mockSecondary({ success, error_reason = null, trace_id = 'test-trace-id-001' }) {
  let callCount = 0;
  const fn = async () => {
    callCount++;
    return {
      success,
      error_reason,
      trace_id,
      exit_code: null,
      impl_report_path: null,
      model_actual: null,
      duration_ms: 0,
      model_requested: '',
      model_fallback_triggered: false,
      provider_base_url: '',
    };
  };
  fn.getCallCount = () => callCount;
  return fn;
}

/**
 * Returns a mock primaryFn that resolves with a simple {success, error_reason} result.
 * Includes a getCallCount() helper to assert invocation count.
 *
 * @param {Object} opts
 * @param {boolean} opts.success
 * @param {string|null} [opts.error_reason]
 */
function mockPrimary({ success, error_reason = null }) {
  let callCount = 0;
  const fn = async () => {
    callCount++;
    return { success, error_reason };
  };
  fn.getCallCount = () => callCount;
  return fn;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('executeImplWithFallback', () => {

  // -------------------------------------------------------------------------
  // T1 (AC7): AUTH_FAILED → fallback triggered, primary succeeds
  // -------------------------------------------------------------------------
  test('T1 (AC7): AUTH_FAILED — secondary fails, fallback to primary succeeds', async () => {
    const secondaryFn = mockSecondary({ success: false, error_reason: 'AUTH_FAILED', trace_id: 't1' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.fallback_triggered, true);
    assert.equal(r.fallback_reason, 'AUTH_FAILED');
    assert.equal(r.trace_id, 't1');
    assert.equal(primaryFn.getCallCount(), 1);
    assert.equal(r.success, true);
    assert.equal(r.provider_used, 'primary');
    assert.equal(r.error_reason, null);
  });

  // -------------------------------------------------------------------------
  // T2 (AC8): ENDPOINT_UNREACHABLE → fallback triggered
  // -------------------------------------------------------------------------
  test('T2 (AC8): ENDPOINT_UNREACHABLE — secondary fails, fallback to primary succeeds', async () => {
    const secondaryFn = mockSecondary({ success: false, error_reason: 'ENDPOINT_UNREACHABLE', trace_id: 't2' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.fallback_triggered, true);
    assert.equal(r.fallback_reason, 'ENDPOINT_UNREACHABLE');
    assert.equal(r.trace_id, 't2');
    assert.equal(primaryFn.getCallCount(), 1);
    assert.equal(r.success, true);
    assert.equal(r.provider_used, 'primary');
  });

  // -------------------------------------------------------------------------
  // T3 (AC9): CLAUDECODE_BUG → fallback triggered
  // -------------------------------------------------------------------------
  test('T3 (AC9): CLAUDECODE_BUG — secondary fails, fallback to primary succeeds', async () => {
    const secondaryFn = mockSecondary({ success: false, error_reason: 'CLAUDECODE_BUG', trace_id: 't3' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.fallback_triggered, true);
    assert.equal(r.fallback_reason, 'CLAUDECODE_BUG');
    assert.equal(r.trace_id, 't3');
    assert.equal(primaryFn.getCallCount(), 1);
    assert.equal(r.success, true);
    assert.equal(r.provider_used, 'primary');
  });

  // -------------------------------------------------------------------------
  // T4 (AC10): TIMEOUT → fallback triggered
  // -------------------------------------------------------------------------
  test('T4 (AC10): TIMEOUT — secondary fails, fallback to primary succeeds', async () => {
    const secondaryFn = mockSecondary({ success: false, error_reason: 'TIMEOUT', trace_id: 't4' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.fallback_triggered, true);
    assert.equal(r.fallback_reason, 'TIMEOUT');
    assert.equal(r.trace_id, 't4');
    assert.equal(primaryFn.getCallCount(), 1);
    assert.equal(r.success, true);
    assert.equal(r.provider_used, 'primary');
  });

  // -------------------------------------------------------------------------
  // T5 (AC11): HEARTBEAT_TIMEOUT → fallback triggered
  // -------------------------------------------------------------------------
  test('T5 (AC11): HEARTBEAT_TIMEOUT — secondary fails, fallback to primary succeeds', async () => {
    const secondaryFn = mockSecondary({ success: false, error_reason: 'HEARTBEAT_TIMEOUT', trace_id: 't5' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.fallback_triggered, true);
    assert.equal(r.fallback_reason, 'HEARTBEAT_TIMEOUT');
    assert.equal(r.trace_id, 't5');
    assert.equal(primaryFn.getCallCount(), 1);
    assert.equal(r.success, true);
    assert.equal(r.provider_used, 'primary');
  });

  // -------------------------------------------------------------------------
  // T6 (AC12): NO_ARTEFACT_PRODUCED → fallback triggered
  // -------------------------------------------------------------------------
  test('T6 (AC12): NO_ARTEFACT_PRODUCED — secondary fails, fallback to primary succeeds', async () => {
    const secondaryFn = mockSecondary({ success: false, error_reason: 'NO_ARTEFACT_PRODUCED', trace_id: 't6' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.fallback_triggered, true);
    assert.equal(r.fallback_reason, 'NO_ARTEFACT_PRODUCED');
    assert.equal(r.trace_id, 't6');
    assert.equal(primaryFn.getCallCount(), 1);
    assert.equal(r.success, true);
    assert.equal(r.provider_used, 'primary');
  });

  // -------------------------------------------------------------------------
  // T7 (AC13): PARSE_ERROR → fallback triggered
  // -------------------------------------------------------------------------
  test('T7 (AC13): PARSE_ERROR — secondary fails, fallback to primary succeeds', async () => {
    const secondaryFn = mockSecondary({ success: false, error_reason: 'PARSE_ERROR', trace_id: 't7' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.fallback_triggered, true);
    assert.equal(r.fallback_reason, 'PARSE_ERROR');
    assert.equal(r.trace_id, 't7');
    assert.equal(primaryFn.getCallCount(), 1);
    assert.equal(r.success, true);
    assert.equal(r.provider_used, 'primary');
  });

  // -------------------------------------------------------------------------
  // T8 (AC14): EXIT_CODE_NON_ZERO → fallback triggered
  // -------------------------------------------------------------------------
  test('T8 (AC14): EXIT_CODE_NON_ZERO — secondary fails, fallback to primary succeeds', async () => {
    const secondaryFn = mockSecondary({ success: false, error_reason: 'EXIT_CODE_NON_ZERO', trace_id: 't8' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.fallback_triggered, true);
    assert.equal(r.fallback_reason, 'EXIT_CODE_NON_ZERO');
    assert.equal(r.trace_id, 't8');
    assert.equal(primaryFn.getCallCount(), 1);
    assert.equal(r.success, true);
    assert.equal(r.provider_used, 'primary');
  });

  // -------------------------------------------------------------------------
  // T9 (AC15): secondary fail + primary fail → success===false (escalation path)
  // -------------------------------------------------------------------------
  test('T9 (AC15): secondary fail + primary fail — success===false, escalation to caller', async () => {
    const secondaryFn = mockSecondary({ success: false, error_reason: 'TIMEOUT', trace_id: 't9' });
    const primaryFn   = mockPrimary({ success: false, error_reason: 'PRIMARY_FAILED' });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.success, false);
    assert.equal(r.fallback_triggered, true);
    assert.equal(r.error_reason, 'PRIMARY_FAILED');
    assert.equal(r.provider_used, 'primary');
    assert.equal(r.trace_id, 't9');
    assert.equal(r.fallback_reason, 'TIMEOUT');
  });

  // -------------------------------------------------------------------------
  // T10 (AC16): secondary success → no fallback, primaryFn NOT called
  // -------------------------------------------------------------------------
  test('T10 (AC16): secondary success — no fallback, primaryFn not invoked', async () => {
    const secondaryFn = mockSecondary({ success: true, trace_id: 't10' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'secondary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(r.fallback_triggered, false);
    assert.equal(r.fallback_reason, null);
    assert.equal(primaryFn.getCallCount(), 0);
    assert.equal(r.success, true);
    assert.equal(r.provider_used, 'secondary');
    assert.equal(r.trace_id, 't10');
  });

  // -------------------------------------------------------------------------
  // T11 (AC17): provider==='primary' → secondaryFn NOT called (non-regression)
  // -------------------------------------------------------------------------
  test('T11 (AC17): provider===primary — secondaryFn never called, primary-only path', async () => {
    const secondaryFn = mockSecondary({ success: true, trace_id: 'should-not-be-used' });
    const primaryFn   = mockPrimary({ success: true });

    const r = await executeImplWithFallback({
      provider: 'primary',
      traceId: 'initial-trace',
      implPrompt: 'test-prompt',
      implReportPath: '/tmp/test.md',
      secondaryFn,
      primaryFn,
    });

    assert.equal(secondaryFn.getCallCount(), 0);
    assert.equal(r.fallback_triggered, false);
    assert.equal(r.fallback_reason, null);
    assert.equal(r.provider_used, 'primary');
    assert.equal(r.trace_id, 'initial-trace');
    assert.equal(r.success, true);
  });

});
