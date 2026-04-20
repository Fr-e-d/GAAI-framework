/**
 * impl-routing.test.js
 *
 * Integration tests for impl-routing.js decision matrix (E94S04 AC8, AC9, AC10).
 * Run with: node --test .gaai/core/adapters/claude-code/__tests__/impl-routing.test.js
 */

import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { resolveImplRouting } from '../impl-routing.js';

function setValidEnv() {
  process.env.GAAI_IMPL_BASE_URL   = 'https://test.example.com';
  process.env.GAAI_IMPL_AUTH_TOKEN = 'test-token';
  process.env.GAAI_IMPL_MODEL      = 'test-model';
}

function clearEnv() {
  delete process.env.GAAI_IMPL_BASE_URL;
  delete process.env.GAAI_IMPL_AUTH_TOKEN;
  delete process.env.GAAI_IMPL_MODEL;
}

describe('resolveImplRouting', () => {
  afterEach(clearEnv);

  // AC8: impl_model: secondary + env set → secondary provider
  test('AC8: secondary + env set → provider: secondary', () => {
    setValidEnv();
    const r = resolveImplRouting('secondary');
    assert.equal(r.provider, 'secondary');
    assert.equal(r.implModelTag, 'secondary');
    assert.equal(r.envMissing, null);
    assert.equal(r.reason, null);
    assert.match(r.traceId, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  });

  // AC9: impl_model: secondary + env missing → primary fallback, warning logged
  test('AC9: secondary + env missing → provider: primary (pre-flight gate, no spawn)', () => {
    clearEnv();
    const warnings = [];
    const orig = console.warn;
    console.warn = (...args) => warnings.push(args.join(' '));

    const r = resolveImplRouting('secondary');

    console.warn = orig;
    assert.equal(r.provider, 'primary');
    assert.equal(r.reason, 'secondary_but_env_missing');
    assert.ok(Array.isArray(r.envMissing) && r.envMissing.length > 0, 'envMissing must list missing vars');
    assert.ok(warnings.some(w => w.includes('IMPL_ROUTING_ENV_MISSING')), 'warning must include IMPL_ROUTING_ENV_MISSING');
    assert.ok(warnings.some(w => w.includes('GAAI_IMPL_BASE_URL')), 'warning must mention GAAI_IMPL_BASE_URL');
    assert.ok(warnings.some(w => w.includes('GAAI_IMPL_AUTH_TOKEN')), 'warning must mention GAAI_IMPL_AUTH_TOKEN');
    assert.ok(warnings.some(w => w.includes('GAAI_IMPL_MODEL')), 'warning must mention GAAI_IMPL_MODEL');
  });

  // AC10 (DEC-72): impl_model absent + env MISSING → primary, no routing warnings
  // Preserves OSS non-regression (E94 D-0 intent scoped to pre-configuration state).
  test('AC10: impl_model absent + env missing → provider: primary, no routing log (OSS non-regression)', () => {
    clearEnv();
    const warnings = [];
    const orig = console.warn;
    console.warn = (...args) => warnings.push(args.join(' '));

    const r = resolveImplRouting(undefined);

    console.warn = orig;
    assert.equal(r.provider, 'primary');
    assert.equal(r.implModelTag, null);
    assert.equal(r.reason, null);
    assert.equal(r.envMissing, null);
    assert.equal(warnings.filter(w => w.includes('IMPL_ROUTING')).length, 0, 'no IMPL_ROUTING warnings on primary path');
  });

  // DEC-72: impl_model absent + env CONFIGURED → secondary (NEW default post-E94 validation)
  test('DEC-72: impl_model absent + env configured → provider: secondary (env-driven default)', () => {
    setValidEnv();
    const r = resolveImplRouting(undefined);
    assert.equal(r.provider, 'secondary');
    assert.equal(r.implModelTag, null);
    assert.equal(r.envMissing, null);
    assert.equal(r.reason, null);
  });

  // DEC-72: impl_model null (explicit null) + env configured → secondary
  test('DEC-72: impl_model null + env configured → provider: secondary', () => {
    setValidEnv();
    const r = resolveImplRouting(null);
    assert.equal(r.provider, 'secondary');
    assert.equal(r.implModelTag, null);
  });

  // DEC-72: impl_model absent + partial env → primary (no warn because no explicit opt-in)
  test('DEC-72: impl_model absent + partial env → provider: primary, no warn (silent fallback)', () => {
    process.env.GAAI_IMPL_BASE_URL = 'https://test.example.com';
    // AUTH_TOKEN and MODEL not set
    const warnings = [];
    const orig = console.warn;
    console.warn = (...args) => warnings.push(args.join(' '));

    const r = resolveImplRouting(undefined);

    console.warn = orig;
    assert.equal(r.provider, 'primary');
    assert.equal(r.reason, null, 'no reason when tag is absent (silent fallback, not opt-in failure)');
    assert.equal(r.envMissing, null, 'envMissing is null when tag is absent (no explicit opt-in to report)');
    assert.equal(warnings.filter(w => w.includes('IMPL_ROUTING')).length, 0, 'no warn when tag absent');
  });

  // AC10b (DEC-72): impl_model: "primary" → always primary, regardless of env (explicit opt-out)
  test('AC10b: impl_model: primary + env missing → provider: primary (explicit opt-out)', () => {
    clearEnv();
    const r = resolveImplRouting('primary');
    assert.equal(r.provider, 'primary');
    assert.equal(r.implModelTag, 'primary');
    assert.equal(r.reason, null);
  });

  // DEC-72: impl_model: "primary" + env configured → STILL primary (explicit opt-out is absolute)
  test('DEC-72: impl_model: primary + env configured → provider: primary (explicit opt-out overrides env default)', () => {
    setValidEnv();
    const r = resolveImplRouting('primary');
    assert.equal(r.provider, 'primary');
    assert.equal(r.implModelTag, 'primary');
    assert.equal(r.reason, null);
    assert.equal(r.envMissing, null);
  });

  // AC7: decision is stable (called multiple times with same args → same provider)
  test('AC7: decision is deterministic (same input → same provider)', () => {
    setValidEnv();
    const r1 = resolveImplRouting('secondary');
    const r2 = resolveImplRouting('secondary');
    assert.equal(r1.provider, r2.provider);
    // trace_ids are unique per call (UUID), but provider is consistent
    assert.notEqual(r1.traceId, r2.traceId);
  });

  // AC5: partial env (only some vars set) → still primary fallback
  test('AC5: partial env (only BASE_URL set) → primary fallback', () => {
    process.env.GAAI_IMPL_BASE_URL = 'https://test.example.com';
    // GAAI_IMPL_AUTH_TOKEN and GAAI_IMPL_MODEL not set
    const r = resolveImplRouting('secondary');
    assert.equal(r.provider, 'primary');
    assert.ok(r.envMissing?.includes('GAAI_IMPL_AUTH_TOKEN'), 'AUTH_TOKEN must be in envMissing');
    assert.ok(r.envMissing?.includes('GAAI_IMPL_MODEL'), 'MODEL must be in envMissing');
  });

  // AC5: empty-string env vars → treat as missing
  test('AC5: empty-string env vars → treated as missing', () => {
    process.env.GAAI_IMPL_BASE_URL   = '';
    process.env.GAAI_IMPL_AUTH_TOKEN = 'token';
    process.env.GAAI_IMPL_MODEL      = 'model';
    const r = resolveImplRouting('secondary');
    assert.equal(r.provider, 'primary');
    assert.ok(r.envMissing?.includes('GAAI_IMPL_BASE_URL'), 'empty BASE_URL must be treated as missing');
  });
});
