#!/usr/bin/env node
/**
 * impl-spawn-stub.mjs — Test helper for handle_impl_phase real runImpl routing
 *
 * Invokes nested-claude-spawn.js runImpl() with a controlled _setSpawnFn stub
 * so that tests can exercise real routing logic without spawning an actual
 * claude subprocess.
 *
 * CLI args:
 *   --story-id <id>              story ID (required)
 *   --report-path <path>         where impl-report.md will be written (required)
 *   --prompt-file <path>         path to prompt file (required)
 *   --impl-model-tag <tag>       primary | secondary | absent (default: absent)
 *   --stub-success <true|false>  whether stub returns success=true (default: true)
 *   --stub-error-reason <str>    error_reason when stub-success=false (default: FALLBACK_EXHAUSTED)
 *
 * Output: SpawnResult JSON on stdout. Exits 0 (mirrors nested-claude-spawn.js exit-0 contract).
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Resolve nested-claude-spawn.js relative to this helper
// helpers/ → tests/ → scripts/ → core/ → adapters/
const SPAWN_MODULE_PATH = resolve(
  __dirname, '..', '..', '..', 'adapters', 'claude-code', 'nested-claude-spawn.js'
);

// Parse CLI args
const args = process.argv.slice(2);
const opts = {
  storyId: null,
  reportPath: null,
  promptFile: null,
  implModelTag: 'absent',
  stubSuccess: true,
  stubErrorReason: 'FALLBACK_EXHAUSTED',
};

for (let i = 0; i < args.length; i++) {
  const k = args[i];
  if      (k === '--story-id')          opts.storyId       = args[++i];
  else if (k === '--report-path')       opts.reportPath    = args[++i];
  else if (k === '--prompt-file')       opts.promptFile    = args[++i];
  else if (k === '--impl-model-tag')    opts.implModelTag  = args[++i];
  else if (k === '--stub-success')      opts.stubSuccess   = (args[++i] === 'true');
  else if (k === '--stub-error-reason') opts.stubErrorReason = args[++i];
}

if (!opts.storyId)    { console.error('ERROR: --story-id is required');    process.exit(1); }
if (!opts.reportPath) { console.error('ERROR: --report-path is required'); process.exit(1); }
if (!opts.promptFile) { console.error('ERROR: --prompt-file is required'); process.exit(1); }

// Read prompt from file
let prompt = '';
try {
  prompt = readFileSync(opts.promptFile, 'utf8');
} catch (e) {
  console.error(`ERROR: cannot read --prompt-file ${opts.promptFile}: ${e.message}`);
  process.exit(1);
}

// Import the spawn module
const spawnModule = await import(SPAWN_MODULE_PATH);
const { _setSpawnFn, _resetSpawnFn, runImpl } = spawnModule;

// Build the stub spawn function
// The stub mimics the contract of spawnCore's inner spawnFn:
// it receives (cmd, args, opts) and must return a ChildProcess-like object.
// _setSpawnFn replaces the low-level spawn used inside spawnCore.
// We need to produce the right result at the spawnCore level.
//
// Strategy: use _setSpawnFn to inject a fake process that:
//   - emits no stdout data (or a minimal result event)
//   - emits 'close' with exit code 0
//   - (if stub-success=true) writes the impl-report.md before closing
//
// This exercises the full runImpl() path including resolveMode() routing.

const stubTraceId = randomUUID();

_setSpawnFn((_cmd, _args, _spawnOpts) => {
  // Ensure report directory exists
  mkdirSync(dirname(opts.reportPath), { recursive: true });

  // Build a minimal fake EventEmitter-based child process
  const events = {};
  const fake = {
    stdout: {
      on: (ev, cb) => {
        if (ev === 'data') {
          // Emit a minimal claude -p stream-json result event on next tick
          if (opts.stubSuccess) {
            const resultEvent = JSON.stringify({
              type: 'result',
              subtype: 'success',
              session_id: stubTraceId,
              total_cost_usd: 0,
              num_turns: 1,
              result: `impl-report written to ${opts.reportPath}`,
              is_error: false,
            });
            process.nextTick(() => cb(Buffer.from(resultEvent + '\n')));
          }
        }
        return fake.stdout;
      },
    },
    stderr: {
      on: (_ev, _cb) => fake.stderr,
    },
    on: (ev, cb) => {
      events[ev] = cb;
      return fake;
    },
    kill: () => {},
  };

  // Schedule: write impl-report + fire 'close'
  process.nextTick(() => {
    if (opts.stubSuccess) {
      writeFileSync(
        opts.reportPath,
        `# Impl Report — ${opts.storyId}\n\nStub impl-report written by impl-spawn-stub.mjs.\n`
      );
    }
    // Fire 'close' with exit code 0 (nested-claude-spawn.js always exits 0)
    if (events['close']) events['close'](0, null);
  });

  return fake;
});

// Invoke runImpl() — this exercises the real routing logic
let result;
try {
  result = await runImpl({
    implModelTag: opts.implModelTag,
    prompt,
    reportPath: opts.reportPath,
    storyId: opts.storyId,
    extraArgs: [],
    logFile: '',
  });
} catch (e) {
  _resetSpawnFn();
  console.error(`FATAL: runImpl() threw: ${e.message}`);
  process.exit(1);
}

_resetSpawnFn();

// Override result.success based on stub configuration
// (The real runImpl checks if the report file exists — if stub-success=false,
// the file was not written, so result.success will naturally be false.
// But we also honour explicit --stub-success=false for error_reason control.)
if (!opts.stubSuccess) {
  result = {
    ...result,
    success: false,
    error_reason: opts.stubErrorReason,
  };
}

process.stdout.write(JSON.stringify(result, null, 2) + '\n');
// Always exit 0 — mirrors nested-claude-spawn.js contract
process.exit(0);
