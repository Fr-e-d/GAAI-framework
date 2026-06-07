/**
 * stdout-feedback.test.js
 *
 * Tests for E94S07: Delivery Agent stdout feedback lines.
 * Covers formatPhaseStdout (unit) and CLI stdout ↔ JSONL parity (integration / AC11).
 * Run with: node --test .gaai/core/adapters/claude-code/__tests__/stdout-feedback.test.js
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

import { formatPhaseStdout } from '../runtime-routing-logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname  = dirname(__filename);
const LOGGER_PATH = join(__dirname, '..', 'runtime-routing-logger.js');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeTmpLog() {
  const dir = mkdtempSync(join(tmpdir(), 'stdout-fb-'));
  return join(dir, 'runtime-routing.jsonl');
}

function runCLI(tmpLog, args) {
  return execFileSync(process.execPath, [LOGGER_PATH, ...args], {
    env: { ...process.env },
    encoding: 'utf8',
  });
}

function readFirstJsonlLine(path) {
  const line = readFileSync(path, 'utf8').split('\n').find(l => l.trim() !== '');
  return JSON.parse(line);
}

// ---------------------------------------------------------------------------
// Unit: formatPhaseStdout
// ---------------------------------------------------------------------------

describe('formatPhaseStdout (unit)', () => {

  // AC1 + AC5 + AC6: primary path, no fallback
  test('primary plan phase → correct marker, provider, model, done suffix', () => {
    const line = formatPhaseStdout('plan', 'primary', 'claude-sonnet-4-6', null);
    assert.equal(line, '▸ Phase Plan (primary / claude-sonnet-4-6) ... done\n');
  });

  test('primary impl phase → Impl capitalization', () => {
    const line = formatPhaseStdout('impl', 'primary', 'claude-sonnet-4-6', null);
    assert.equal(line, '▸ Phase Impl (primary / claude-sonnet-4-6) ... done\n');
  });

  // AC5: QA phase uses uppercase "QA" (not "Qa")
  test('qa phase → QA capitalization', () => {
    const line = formatPhaseStdout('qa', 'primary', 'claude-sonnet-4-6', null);
    assert.equal(line, '▸ Phase QA (primary / claude-sonnet-4-6) ... done\n');
  });

  // AC7: secondary success path
  test('secondary impl success → provider=secondary in line', () => {
    const line = formatPhaseStdout('impl', 'secondary', 'glm-4.6', null);
    assert.equal(line, '▸ Phase Impl (secondary / glm-4.6) ... done\n');
  });

  // AC8: secondary failure → fallback suffix instead of done
  test('secondary impl fallback → ⚠ suffix with error class', () => {
    const line = formatPhaseStdout('impl', 'secondary', 'glm-4.6', 'TIMEOUT');
    assert.equal(line, '▸ Phase Impl (secondary / glm-4.6) ... ⚠ Falling back to primary (reason: TIMEOUT)\n');
  });

  test('AUTH_FAILED class → correct suffix', () => {
    const line = formatPhaseStdout('impl', 'secondary', 'glm-4.6', 'AUTH_FAILED');
    assert.equal(line, '▸ Phase Impl (secondary / glm-4.6) ... ⚠ Falling back to primary (reason: AUTH_FAILED)\n');
  });

  // AC3: spawn-error provider (not 'secondary') — no "Falling back" label even with non-null reason
  test('provider=error with QA_SPAWN_FAILED → no "Falling back" label, error class shown', () => {
    const line = formatPhaseStdout('qa', 'error', 'claude-sonnet-4-6', 'QA_SPAWN_FAILED');
    assert.ok(!line.includes('Falling back'), 'must not show "Falling back to primary" on spawn-error');
    assert.ok(line.includes('QA_SPAWN_FAILED'), 'must include the error class for diagnostics');
  });

  // AC10: no secrets — format contains only provider label, model ID, error class
  test('no token-like content in formatted line', () => {
    const line = formatPhaseStdout('impl', 'secondary', 'glm-4.6', 'AUTH_FAILED');
    assert.ok(!line.includes('Bearer'), 'must not include Bearer');
    assert.ok(!line.includes('Authorization'), 'must not include Authorization header');
    assert.ok(!line.includes('sk-'), 'must not include sk- token prefix');
  });
});

// ---------------------------------------------------------------------------
// Integration: CLI stdout ↔ JSONL parity (AC11)
// ---------------------------------------------------------------------------

describe('CLI stdout ↔ JSONL parity (AC11)', () => {
  const traceId = 'dddddddd-0000-0000-0000-000000000011';

  // AC6: primary plan — stdout and JSONL must agree on provider, model, fallback_reason
  test('primary plan: stdout line and JSONL entry carry same provider/model/fallback_reason', () => {
    const tmpLog = makeTmpLog();
    const stdout = runCLI(tmpLog, [
      '--trace-id', traceId,
      '--story-id', 'E94S07',
      '--phase', 'plan',
      '--provider', 'primary',
      '--model', 'claude-sonnet-4-6',
      '--duration-ms', '0',
      '--fallback-reason', '',
      '--impl-model-tag', 'absent',
      '--log-path', tmpLog,
    ]).trimEnd();

    // stdout assertion (AC1)
    assert.equal(stdout, '▸ Phase Plan (primary / claude-sonnet-4-6) ... done');

    // JSONL assertion
    const entry = readFirstJsonlLine(tmpLog);
    assert.equal(entry.provider, 'primary');
    assert.equal(entry.model, 'claude-sonnet-4-6');
    assert.equal(entry.fallback_reason, null);

    // Parity: provider matches stdout
    assert.ok(stdout.includes(entry.provider), 'stdout must contain JSONL provider');
    assert.ok(stdout.includes(entry.model), 'stdout must contain JSONL model');
  });

  // AC8: secondary failure fallback — stdout shows fallback, JSONL has matching fallback_reason
  test('secondary fallback: stdout fallback suffix matches JSONL fallback_reason', () => {
    const tmpLog = makeTmpLog();
    const stdout = runCLI(tmpLog, [
      '--trace-id', traceId,
      '--story-id', 'E94S07',
      '--phase', 'impl',
      '--provider', 'secondary',
      '--model', 'glm-4.6',
      '--duration-ms', '500',
      '--fallback-reason', 'TIMEOUT',
      '--impl-model-tag', 'secondary',
      '--log-path', tmpLog,
    ]).trimEnd();

    assert.ok(stdout.includes('⚠ Falling back to primary (reason: TIMEOUT)'),
      'stdout must contain fallback marker and error class');

    const entry = readFirstJsonlLine(tmpLog);
    assert.equal(entry.fallback_reason, 'TIMEOUT', 'JSONL fallback_reason must be TIMEOUT');
    assert.ok(stdout.includes(entry.fallback_reason), 'stdout must contain JSONL fallback_reason');
    assert.ok(stdout.includes(entry.model), 'stdout must contain JSONL model');
    assert.ok(stdout.includes(entry.provider), 'stdout must contain JSONL provider');
  });

  // AC11: three phases for same trace_id → each stdout line matches corresponding JSONL entry
  test('three-phase delivery: each stdout line matches its JSONL entry', () => {
    const tmpLog = makeTmpLog();

    const phases = [
      { phase: 'plan',  provider: 'primary',   model: 'claude-sonnet-4-6', fallback: '', expectedDone: true },
      { phase: 'impl',  provider: 'secondary',  model: 'glm-4.6',           fallback: '', expectedDone: true },
      { phase: 'qa',    provider: 'primary',   model: 'claude-sonnet-4-6', fallback: '', expectedDone: true },
    ];

    const stdoutLines = [];
    for (const p of phases) {
      const out = runCLI(tmpLog, [
        '--trace-id', traceId,
        '--story-id', 'E94S07',
        '--phase', p.phase,
        '--provider', p.provider,
        '--model', p.model,
        '--duration-ms', '0',
        '--fallback-reason', p.fallback,
        '--impl-model-tag', 'absent',
        '--log-path', tmpLog,
      ]).trimEnd();
      stdoutLines.push(out);
    }

    const raw = readFileSync(tmpLog, 'utf8');
    const jsonlEntries = raw.split('\n').filter(l => l.trim()).map(l => JSON.parse(l));

    assert.equal(jsonlEntries.length, 3, 'must have 3 JSONL entries');
    assert.equal(stdoutLines.length, 3, 'must have 3 stdout lines');

    for (let i = 0; i < 3; i++) {
      const entry = jsonlEntries[i];
      const line  = stdoutLines[i];
      assert.ok(line.includes(entry.provider), `entry ${i}: stdout must include provider`);
      assert.ok(line.includes(entry.model),    `entry ${i}: stdout must include model`);
      // fallback_reason=null → stdout must NOT contain "Falling back"
      if (entry.fallback_reason === null) {
        assert.ok(line.endsWith('... done'), `entry ${i}: stdout must end with "... done"`);
      } else {
        assert.ok(line.includes(entry.fallback_reason), `entry ${i}: stdout must include fallback_reason`);
      }
    }
  });
});
