/**
 * delivery-provenance.mjs — contributor ledger for Delivery artefacts.
 *
 * Every artefact a Delivery step produces records which models materially
 * contributed to it. The router reads this ledger to decide whether a
 * candidate is allowed to EVALUATE a given artefact: a model may never
 * evaluate work it contributed to.
 *
 * Identity rule (deliberate, and the reason this module exists at all):
 * a different context window, run, session, harness invocation or reasoning
 * effort is NOT a different author. Two entries are the same contributor when
 * they name the same registry alias OR the same concrete model. Matching on
 * the concrete model as well as the alias is what keeps the invariant intact
 * when two aliases are pointed at one underlying model by a config edit, or
 * when the same model is reachable through two harnesses.
 *
 * Node stdlib only — no dependencies (this file ships in the OSS substrate).
 */

import { readFileSync, writeFileSync, mkdirSync, renameSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

export const SCHEMA_VERSION = 1;

/**
 * Artefact kinds a contribution can attach to. Closed set — an unknown kind is
 * a programming error, not a value to store, because a typo'd kind would
 * silently widen eligibility (nobody is a contributor to "COOD").
 *
 *  PLAN         the governed execution plan, including the approved plan
 *  PLAN_REVIEW  review feedback on a plan (an influence on the next plan version)
 *  CODE         the implementation / diff, including remediations
 *  QA           QA findings
 */
export const ARTIFACT_KINDS = Object.freeze(['PLAN', 'PLAN_REVIEW', 'CODE', 'QA']);

/**
 * Resolves the ledger path for a story.
 * @param {string} storyId
 * @param {{ledgerDir?: string, explicitPath?: string}} [opts]
 * @returns {string}
 */
export function resolveLedgerPath(storyId, opts = {}) {
  if (opts.explicitPath) return opts.explicitPath;
  if (process.env.GAAI_PROVENANCE_PATH) return process.env.GAAI_PROVENANCE_PATH;
  const dir = opts.ledgerDir
    || process.env.GAAI_PROVENANCE_DIR
    || join(process.cwd(), '.delivery-locks', 'provenance');
  return join(dir, `${storyId}.provenance.json`);
}

/**
 * Reads a ledger. A missing or unreadable ledger reads as empty — a story that
 * has produced nothing yet has no contributors, which is the correct starting
 * state and never relaxes an exclusion.
 *
 * A CORRUPT ledger is different and must not read as empty: losing the
 * contributor list silently would let a model evaluate its own work. Callers
 * get `corrupt: true` and are expected to fail closed on evaluation roles.
 *
 * @param {string} path
 * @param {string} storyId
 * @returns {{schema_version: number, story_id: string, contributions: Array, corrupt: boolean}}
 */
export function readLedger(path, storyId = '') {
  const empty = { schema_version: SCHEMA_VERSION, story_id: storyId, contributions: [], blocked: [], corrupt: false };
  if (!existsSync(path)) return empty;
  let raw;
  try {
    raw = readFileSync(path, 'utf8');
  } catch {
    return { ...empty, corrupt: true };
  }
  if (raw.trim() === '') return empty;
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { ...empty, corrupt: true };
  }
  if (!parsed || typeof parsed !== 'object' || !Array.isArray(parsed.contributions)) {
    return { ...empty, corrupt: true };
  }
  return {
    schema_version: parsed.schema_version ?? SCHEMA_VERSION,
    story_id: parsed.story_id || storyId,
    contributions: parsed.contributions,
    blocked: Array.isArray(parsed.blocked) ? parsed.blocked : [],
    corrupt: false,
  };
}

function writeLedgerAtomic(path, ledger) {
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.tmp-${process.pid}`;
  writeFileSync(tmp, `${JSON.stringify(ledger, null, 2)}\n`, 'utf8');
  renameSync(tmp, path);
}

/**
 * Records one contribution. Re-recording the same (artifact, alias, concrete
 * model) triple is a no-op, so a phase that retries does not inflate the
 * ledger — but it also never removes anyone: contributions only accumulate.
 *
 * @param {string} path
 * @param {{storyId: string, artifact: string, modelId: string, concreteModel: string,
 *          harness?: string, role?: string, note?: string, at?: string}} entry
 * @returns {{recorded: boolean, ledger: object}}
 */
export function recordContribution(path, entry) {
  const { storyId, artifact, modelId, concreteModel } = entry;
  if (!ARTIFACT_KINDS.includes(artifact)) {
    throw new Error(`unknown artifact kind: ${artifact} (expected one of ${ARTIFACT_KINDS.join(', ')})`);
  }
  if (!modelId || !concreteModel) {
    throw new Error('recordContribution requires both modelId (registry alias) and concreteModel');
  }
  const ledger = readLedger(path, storyId);
  if (ledger.corrupt) {
    // Rebuilding a corrupt ledger from scratch would silently drop
    // contributors. Refuse; the operator repairs or deletes the file.
    throw new Error(`provenance ledger is corrupt: ${path}`);
  }
  // De-duplication is per ATTEMPT, not per model. Collapsing attempts made the
  // ledger unable to answer "who produced the verdict that is on disk now":
  // a model recorded on an earlier failed attempt makes its own later, successful
  // run a no-op, so a membership check can accept a stale evaluator. Attempts are
  // distinct executions and are recorded as such; the exclusion set still unions
  // them, because anyone who ever contributed stays barred from judging.
  const attempt = entry.attempt || '';
  const dup = ledger.contributions.some(
    (c) => c.artifact === artifact && c.model_id === modelId
      && c.concrete_model === concreteModel && (c.attempt || '') === attempt,
  );
  if (!dup) {
    ledger.contributions.push({
      artifact,
      model_id: modelId,
      concrete_model: concreteModel,
      harness: entry.harness || '',
      role: entry.role || '',
      attempt: attempt,
      effort: entry.effort || '',
      // Recorded now because they cannot be reconstructed later. A question
      // deferred is answerable from history; a field never written is not.
      capability_waived: entry.capabilityWaived || '',
      duration_ms: Number(entry.durationMs) || 0,
      fallback_trace: entry.fallbackTrace || '',
      note: entry.note || '',
      recorded_at: entry.at || new Date().toISOString(),
    });
    ledger.schema_version = SCHEMA_VERSION;
    ledger.story_id = storyId || ledger.story_id;
    // `corrupt` is a read-time signal, not ledger content — never persist it.
    writeLedgerAtomic(path, {
      schema_version: ledger.schema_version,
      story_id: ledger.story_id,
      contributions: ledger.contributions,
      blocked: ledger.blocked || [],
    });
  }
  return { recorded: !dup, ledger };
}

/**
 * Records a step that could NOT be routed.
 *
 * A blocked step leaves no contributor, so without this it leaves no trace at
 * all — and "how often does routing block, and why" becomes unanswerable from
 * history. Blocks are the rarest and most interesting routing events; losing
 * them is losing the signal.
 *
 * @param {string} path
 * @param {{storyId: string, role: string, blockedClass: string, reason?: string,
 *          trace?: string, at?: string}} entry
 */
export function recordBlocked(path, entry) {
  const ledger = readLedger(path, entry.storyId);
  if (ledger.corrupt) throw new Error(`provenance ledger is corrupt: ${path}`);
  const blocked = ledger.blocked || [];
  blocked.push({
    role: entry.role,
    blocked_class: entry.blockedClass || '',
    reason: entry.reason || '',
    trace: entry.trace || '',
    recorded_at: entry.at || new Date().toISOString(),
  });
  writeLedgerAtomic(path, {
    schema_version: SCHEMA_VERSION,
    story_id: ledger.story_id || entry.storyId,
    contributions: ledger.contributions,
    blocked,
  });
  return { recorded: true };
}

/**
 * Identity tokens of every model that contributed to any of `kinds`.
 * Both the registry alias and the concrete model are emitted, so a candidate
 * matching on either one is excluded.
 *
 * @param {{contributions: Array}} ledger
 * @param {string[]} kinds
 * @returns {Set<string>}
 */
export function contributorTokens(ledger, kinds) {
  const wanted = new Set(kinds);
  const tokens = new Set();
  for (const c of ledger.contributions || []) {
    if (!wanted.has(c.artifact)) continue;
    if (c.model_id) tokens.add(`alias:${c.model_id}`);
    if (c.concrete_model) tokens.add(`model:${c.concrete_model}`);
  }
  return tokens;
}

/**
 * The most recent contributor recorded for a kind — the one that produced what
 * is on disk now, as opposed to everyone who ever produced a version of it.
 * Exclusion uses the union; "who wrote this verdict" needs the latest.
 * @param {{contributions: Array}} ledger
 * @param {string} kind
 * @returns {object|null}
 */
export function latestContributor(ledger, kind) {
  const rows = (ledger.contributions || []).filter((c) => c.artifact === kind);
  return rows.length ? rows[rows.length - 1] : null;
}

/**
 * Human-readable contributor list for a kind (alias names, de-duplicated,
 * in first-contribution order).
 * @param {{contributions: Array}} ledger
 * @param {string} kind
 * @returns {string[]}
 */
export function contributorsOf(ledger, kind) {
  const seen = new Set();
  const out = [];
  for (const c of ledger.contributions || []) {
    if (c.artifact !== kind) continue;
    if (seen.has(c.model_id)) continue;
    seen.add(c.model_id);
    out.push(c.model_id);
  }
  return out;
}

/**
 * True when the candidate is barred from evaluating `kinds`.
 * @param {{id: string, concrete_model: string}} candidate
 * @param {Set<string>} tokens
 * @returns {boolean}
 */
export function isContributor(candidate, tokens) {
  return tokens.has(`alias:${candidate.id}`) || tokens.has(`model:${candidate.concrete_model}`);
}
