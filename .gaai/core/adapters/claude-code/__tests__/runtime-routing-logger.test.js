/**
 * runtime-routing-logger.test.js
 *
 * Unit tests for runtime-routing-logger.js (E94S06).
 * Run with: node --test .gaai/core/adapters/claude-code/__tests__/runtime-routing-logger.test.js
 */

import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { logPhase, _setLogPath, _resetLogPath } from '../runtime-routing-logger.js';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeTmpLog() {
  const dir = mkdtempSync(join(tmpdir(), 'rrlog-'));
  return join(dir, 'runtime-routing.jsonl');
}

function readLines(path) {
  return readFileSync(path, 'utf8')
    .split('\n')
    .filter(l => l.trim() !== '')
    .map(l => JSON.parse(l));
}

function baseParams(overrides = {}) {
  return {
    trace_id:        'aaaaaaaa-0000-0000-0000-000000000001',
    story_id:        'E94S06',
    phase:           'plan',
    provider:        'primary',
    model:           'claude-sonnet-4-6',
    duration_ms:     1234,
    fallback_reason: null,
    impl_model_tag:  'absent',
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('runtime-routing-logger', () => {
  let tmpLog;

  beforeEach(() => {
    tmpLog = makeTmpLog();
    _setLogPath(tmpLog);
  });

  afterEach(() => {
    _resetLogPath();
  });

  // AC1 + AC3 + AC4 + AC9: write one line → file exists, parses as JSON, 9 fields present
  test('write one line → file exists, line parses as JSON, all 9 fields present', () => {
    logPhase(baseParams());

    assert.ok(existsSync(tmpLog), 'log file must exist after write');

    const lines = readLines(tmpLog);
    assert.equal(lines.length, 1, 'must have exactly one line');

    const entry = lines[0];
    const expectedFields = [
      'trace_id', 'story_id', 'phase', 'provider',
      'model', 'duration_ms', 'fallback_reason', 'impl_model_tag', 'timestamp',
    ];
    for (const field of expectedFields) {
      assert.ok(field in entry, `field "${field}" must be present`);
    }
    assert.equal(Object.keys(entry).length, 9, 'entry must have exactly 9 fields');
    assert.equal(entry.trace_id, 'aaaaaaaa-0000-0000-0000-000000000001');
    assert.ok(typeof entry.timestamp === 'string' && entry.timestamp.length > 0, 'timestamp must be a non-empty string');
  });

  // AC5: write three lines for same trace_id → all three parse, trace_id matches
  test('write three lines for same trace_id → all parse, trace_id consistent', () => {
    const sharedTraceId = 'bbbbbbbb-0000-0000-0000-000000000002';

    logPhase(baseParams({ trace_id: sharedTraceId, phase: 'plan' }));
    logPhase(baseParams({ trace_id: sharedTraceId, phase: 'impl' }));
    logPhase(baseParams({ trace_id: sharedTraceId, phase: 'qa' }));

    const lines = readLines(tmpLog);
    assert.equal(lines.length, 3, 'must have exactly three lines');

    for (const entry of lines) {
      assert.equal(entry.trace_id, sharedTraceId, 'trace_id must match for all three lines');
    }
    assert.equal(lines[0].phase, 'plan');
    assert.equal(lines[1].phase, 'impl');
    assert.equal(lines[2].phase, 'qa');
  });

  // AC11 fallback case: two impl lines for same trace_id, fallback_reason populated on first
  test('fallback case → two impl lines, fallback_reason populated on first', () => {
    const sharedTraceId = 'cccccccc-0000-0000-0000-000000000003';

    logPhase(baseParams({
      trace_id:        sharedTraceId,
      phase:           'impl',
      provider:        'secondary',
      fallback_reason: 'TIMEOUT',
    }));
    logPhase(baseParams({
      trace_id:        sharedTraceId,
      phase:           'impl',
      provider:        'primary',
      fallback_reason: null,
    }));

    const lines = readLines(tmpLog);
    assert.equal(lines.length, 2);
    assert.equal(lines[0].fallback_reason, 'TIMEOUT');
    assert.equal(lines[1].fallback_reason, null);
    assert.equal(lines[0].trace_id, sharedTraceId);
    assert.equal(lines[1].trace_id, sharedTraceId);
  });

  // AC11: missing required field → logger throws, no partial line written
  test('missing required field → throws, file not modified', () => {
    const params = baseParams();
    delete params.phase;

    assert.throws(
      () => logPhase(params),
      /missing required field "phase"/,
    );

    assert.ok(!existsSync(tmpLog), 'file must not exist after throw on missing field');
  });

  // AC11: token-like value in any field → logger throws before writing, file NOT modified
  test('Bearer token in model field → throws before write, file not modified', () => {
    assert.throws(
      () => logPhase(baseParams({ model: 'Bearer sk-abc123abc123abc123abc123' })),
      /token-like value detected/,
    );
    assert.ok(!existsSync(tmpLog), 'file must not exist after throw on token detection');
  });

  test('sk- token in trace_id field → throws before write', () => {
    assert.throws(
      () => logPhase(baseParams({ trace_id: 'sk-' + 'a'.repeat(25) })),
      /token-like value detected/,
    );
    assert.ok(!existsSync(tmpLog), 'file must not exist after throw');
  });

  test('Authorization: header pattern in story_id → throws before write', () => {
    assert.throws(
      () => logPhase(baseParams({ story_id: 'Authorization: Bearer token' })),
      /token-like value detected/,
    );
    assert.ok(!existsSync(tmpLog), 'file must not exist after throw');
  });

  // AC7: appendFileSync — second write appends, does not overwrite
  test('second write appends — does not overwrite first line', () => {
    logPhase(baseParams({ phase: 'plan' }));
    logPhase(baseParams({ phase: 'qa' }));

    const lines = readLines(tmpLog);
    assert.equal(lines.length, 2, 'must have two lines after two writes');
    assert.equal(lines[0].phase, 'plan');
    assert.equal(lines[1].phase, 'qa');
  });

  // AC1: directory created automatically if absent
  test('creates missing log directory automatically', () => {
    const base = mkdtempSync(join(tmpdir(), 'rrlog-nested-'));
    const nestedLog = join(base, 'deep', 'nested', 'runtime-routing.jsonl');
    _setLogPath(nestedLog);

    logPhase(baseParams());
    assert.ok(existsSync(nestedLog), 'file must exist in newly created nested directory');
  });
});
