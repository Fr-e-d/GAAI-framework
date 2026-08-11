#!/usr/bin/env node
// qa-verdict.mjs — DEC-200 two-axis QA handoff validator (Node-stdlib, no
// JSON-Schema engine dependency). Enforces closed shape, conditional
// materiality/evidence rules, exact surface coverage, authority freshness
// and the machine-derived aggregate/remediation invariants independently of
// whatever the QA agent narrated. Exports a pure function for hermetic
// tests and a thin CLI wrapper for daemon-dispatch.sh.

import { readFileSync } from 'node:fs';

const AXIS = new Set(['PASS', 'FAIL', 'ESCALATE']);
const CLASSIFICATION = new Set(['blocking', 'non_blocking', 'not_applicable']);
const MATERIALITY = new Set([
  'deprecated', 'unsupported', 'materially_obsolete',
  'unsafe', 'officially_discouraged', 'demonstrably_fragile',
]);
const REVIEW_DOMAIN = new Set([
  'security', 'dependency', 'runtime_api', 'data',
  'operations', 'interoperability', 'reliability', 'other',
]);
const OUTCOME = new Set(['supports', 'contradicts']);
const SOURCE_KIND = new Set(['live', 'governed_record']);
const AUTHORITY_DOMAIN = new Set(['security', 'fast_moving', 'stable', 'unknown']);
const ROOT_CAUSE = new Set(['plan', 'implementation']);
const REMEDIATION_ROUTE = new Set(['human', 'plan', 'impl', null]);
const FRESH_DAYS = { security: 30, fast_moving: 30, stable: 90 };
const SECRET_QUERY_KEYS = ['token', 'key', 'secret', 'password', 'apikey'];
const TOP_FIELDS = new Set([
  'schema_version', 'story_id', 'evaluated_as_of', 'plan_conformance', 'state_of_the_art_conformance',
  'changed_surface_inventory', 'findings', 'evidence', 'verdict', 'remediation_route', 'replan_required', 'report_path',
]);
const INVENTORY_FIELDS = new Set(['surface', 'classification', 'review_domain', 'materiality', 'eligibility_reason']);
const FINDING_FIELDS = new Set(['finding_id', 'surface', 'classification', 'description', 'root_cause']);
const EVIDENCE_FIELDS = new Set([
  'surface', 'finding_id', 'outcome', 'source_kind', 'authority_uri', 'authority_title',
  'published_at', 'accessed_at', 'claim', 'content_digest', 'excerpt', 'materiality', 'governed_record',
]);
const GOVERNED_RECORD_FIELDS = new Set(['authority_record_version', 'official_authority_url', 'verified_at', 'authority_domain', 'claim_scope']);

const isPlainObject = (v) => typeof v === 'object' && v !== null && !Array.isArray(v);
const isNonEmptyString = (v) => typeof v === 'string' && v.length > 0;

function rejectUnknownFields(obj, allowed, path, errors) {
  for (const k of Object.keys(obj)) {
    if (!allowed.has(k)) errors.push(`${path}.${k} is not a recognized field`);
  }
}

function isSafeRepoRelative(p) {
  if (!isNonEmptyString(p)) return false;
  if (p.startsWith('/')) return false;
  return !p.split('/').some((seg) => seg === '..');
}

function isSafeLiveUri(uri) {
  if (!isNonEmptyString(uri)) return false;
  let url;
  try { url = new URL(uri); } catch { return false; }
  if (url.protocol !== 'https:') return false;
  if (url.username || url.password) return false;
  const keys = [...url.searchParams.keys()].map((k) => k.toLowerCase());
  return !keys.some((k) => SECRET_QUERY_KEYS.some((s) => k.includes(s)));
}

function ageDays(fromISO, toISO) {
  const from = Date.parse(fromISO);
  const to = Date.parse(toISO);
  if (Number.isNaN(from) || Number.isNaN(to)) return Infinity;
  return (to - from) / 86400000;
}

function deriveAggregate(plan, sota) {
  if (plan === 'ESCALATE' || sota === 'ESCALATE') return 'ESCALATE';
  if (plan === 'FAIL' || sota === 'FAIL') return 'FAIL';
  return 'PASS';
}

function deriveRemediation(aggregate, findings) {
  if (aggregate === 'ESCALATE') return { route: 'human', replan: null };
  if (aggregate === 'PASS') return { route: null, replan: null };
  const planRooted = findings.some((f) => f.classification === 'blocking' && f.root_cause === 'plan');
  return planRooted ? { route: 'plan', replan: true } : { route: 'impl', replan: false };
}

function checkInventoryEntry(entry, idx, errors) {
  const path = `changed_surface_inventory[${idx}]`;
  if (!isPlainObject(entry)) { errors.push(`${path} is not an object`); return; }
  rejectUnknownFields(entry, INVENTORY_FIELDS, path, errors);
  if (!isNonEmptyString(entry.surface)) errors.push(`${path}.surface missing/invalid`);
  if (!CLASSIFICATION.has(entry.classification)) errors.push(`${path}.classification invalid: ${entry.classification}`);
  if (!REVIEW_DOMAIN.has(entry.review_domain)) errors.push(`${path}.review_domain invalid: ${entry.review_domain}`);
  if (entry.classification === 'blocking') {
    if (!MATERIALITY.has(entry.materiality)) errors.push(`${path}.materiality required (blocking, closed 6-value set)`);
    if ('eligibility_reason' in entry) errors.push(`${path}.eligibility_reason forbidden for blocking`);
  } else if (entry.classification === 'non_blocking') {
    if ('materiality' in entry) errors.push(`${path}.materiality forbidden for non_blocking`);
    if ('eligibility_reason' in entry) errors.push(`${path}.eligibility_reason forbidden for non_blocking`);
  } else if (entry.classification === 'not_applicable') {
    if ('materiality' in entry) errors.push(`${path}.materiality forbidden for not_applicable`);
    if (!isNonEmptyString(entry.eligibility_reason)) errors.push(`${path}.eligibility_reason required for not_applicable`);
  }
}

function checkFindingEntry(entry, idx, errors) {
  const path = `findings[${idx}]`;
  if (!isPlainObject(entry)) { errors.push(`${path} is not an object`); return; }
  rejectUnknownFields(entry, FINDING_FIELDS, path, errors);
  if (!isNonEmptyString(entry.finding_id)) errors.push(`${path}.finding_id missing`);
  if (!isNonEmptyString(entry.surface)) errors.push(`${path}.surface missing`);
  if (!CLASSIFICATION.has(entry.classification)) errors.push(`${path}.classification invalid: ${entry.classification}`);
  if (!isNonEmptyString(entry.description)) errors.push(`${path}.description missing`);
  if (entry.classification === 'blocking' && !ROOT_CAUSE.has(entry.root_cause)) {
    errors.push(`${path}.root_cause required (plan|implementation) for a blocking finding`);
  }
}

// Returns true when the record is a quality-insufficient (not structurally broken)
// authority: stale, or a domain mismatch on a security/unsafe claim. Per DEC-200
// D3/D4 this does NOT unconditionally invalidate the handoff — it requires the
// caller's state_of_the_art_conformance to be ESCALATE. Structural defects (unknown
// fields, missing required fields, an unrecognized domain value) are unconditional
// and go straight to `errors`. A missing/literal-`unknown` domain is a normal,
// valid fallback (DEC-200 D3) — it defaults to `fast_moving` and pushes the
// evidence's surface onto `domainDefaulted` so the default is observable to the
// caller, never silently absorbed.
function checkGovernedRecord(gr, path, errors, evidence, surfaceEntry, nowISO, domainDefaulted) {
  rejectUnknownFields(gr, GOVERNED_RECORD_FIELDS, `${path}.governed_record`, errors);
  if (gr.authority_record_version !== 1) errors.push(`${path}.governed_record.authority_record_version must be 1`);
  if (!isNonEmptyString(gr.official_authority_url)) errors.push(`${path}.governed_record.official_authority_url missing`);
  if (!isNonEmptyString(gr.verified_at)) errors.push(`${path}.governed_record.verified_at missing`);
  if (!isNonEmptyString(gr.claim_scope)) errors.push(`${path}.governed_record.claim_scope missing`);

  let domain = gr.authority_domain;
  if (domain === undefined || domain === 'unknown') {
    domain = 'fast_moving';
    domainDefaulted.push(evidence.surface); // DEC-200 D3: "emits authority_domain_defaulted"
  } else if (!AUTHORITY_DOMAIN.has(domain)) {
    errors.push(`${path}.governed_record.authority_domain unrecognized: ${gr.authority_domain}`);
    return false;
  }
  if (!isNonEmptyString(gr.verified_at)) return false; // already flagged above as structural

  const needsSecurity = evidence.materiality === 'unsafe' || surfaceEntry?.review_domain === 'security';
  if (needsSecurity && domain !== 'security') return true; // mismatch — insufficient, not structurally broken

  const freshDays = FRESH_DAYS[domain];
  const age = ageDays(gr.verified_at, nowISO);
  return !(age <= freshDays); // stale — insufficient
}

// Returns true when this evidence entry is authority-insufficient (see above).
function checkEvidenceEntry(entry, idx, errors, surfaceMap, nowISO, domainDefaulted) {
  const path = `evidence[${idx}]`;
  if (!isPlainObject(entry)) { errors.push(`${path} is not an object`); return false; }
  rejectUnknownFields(entry, EVIDENCE_FIELDS, path, errors);
  for (const f of ['surface', 'finding_id', 'authority_uri', 'authority_title', 'accessed_at', 'claim']) {
    if (!isNonEmptyString(entry[f])) errors.push(`${path}.${f} missing`);
  }
  if (!OUTCOME.has(entry.outcome)) errors.push(`${path}.outcome invalid: ${entry.outcome}`);
  if (!SOURCE_KIND.has(entry.source_kind)) errors.push(`${path}.source_kind invalid: ${entry.source_kind}`);

  const hasDigest = 'content_digest' in entry;
  const hasExcerpt = 'excerpt' in entry;
  if (hasDigest === hasExcerpt) errors.push(`${path} must carry exactly one of content_digest / excerpt`);

  const surfaceEntry = surfaceMap.get(entry.surface);
  if (surfaceEntry?.classification === 'blocking') {
    if (!MATERIALITY.has(entry.materiality)) errors.push(`${path}.materiality required for evidence on a blocking surface`);
  } else if ('materiality' in entry) {
    errors.push(`${path}.materiality forbidden for evidence on a non-blocking surface`);
  }

  if (entry.source_kind === 'live') {
    if ('governed_record' in entry) errors.push(`${path}.governed_record forbidden for source_kind=live`);
    if (!isSafeLiveUri(entry.authority_uri)) {
      errors.push(`${path}.authority_uri unsafe (must be absolute HTTPS, no user-info, no secret-shaped query key)`);
    }
    return false;
  }
  if (entry.source_kind === 'governed_record') {
    if (!isSafeRepoRelative(entry.authority_uri)) errors.push(`${path}.authority_uri unsafe (must be safe repo-relative)`);
    if (!isPlainObject(entry.governed_record)) {
      errors.push(`${path}.governed_record required for source_kind=governed_record`);
      return false;
    }
    return checkGovernedRecord(entry.governed_record, path, errors, entry, surfaceEntry, nowISO, domainDefaulted);
  }
  return false;
}

/**
 * Pure validator — no I/O. sidecar/expectedSurfaces are already-parsed JS values.
 * sidecarPath (optional) is the sidecar JSON file's own repo-relative locator,
 * supplied by the caller (the validator has no I/O of its own to derive it) —
 * echoed into summary.sidecar_path on success so observability records both
 * the sidecar and the report locator (AC5), never just the report.
 * @returns {{valid:boolean, errors:string[], derivedAggregate:?string,
 *   derivedRemediationRoute:?string, derivedReplanRequired:?boolean,
 *   authorityDomainDefaulted:boolean, authorityDomainDefaultedSurfaces:string[],
 *   summary:?object}}
 */
export function validateQaVerdict({ sidecar, storyId, expectedSurfaces, sidecarPath }) {
  const errors = [];

  if (!isPlainObject(sidecar)) {
    return { valid: false, errors: ['sidecar is not a JSON object'], derivedAggregate: null, derivedRemediationRoute: null, derivedReplanRequired: null, summary: null };
  }

  rejectUnknownFields(sidecar, TOP_FIELDS, 'sidecar', errors);
  if (sidecar.schema_version !== 1) errors.push(`schema_version must be 1, got ${JSON.stringify(sidecar.schema_version)}`);
  if (sidecar.story_id !== storyId) errors.push(`story_id mismatch: expected ${storyId}, got ${sidecar.story_id}`);
  if (!isNonEmptyString(sidecar.evaluated_as_of)) errors.push('evaluated_as_of missing');
  if (!AXIS.has(sidecar.plan_conformance)) errors.push(`plan_conformance invalid: ${sidecar.plan_conformance}`);
  if (!AXIS.has(sidecar.state_of_the_art_conformance)) errors.push(`state_of_the_art_conformance invalid: ${sidecar.state_of_the_art_conformance}`);
  if (!AXIS.has(sidecar.verdict)) errors.push(`verdict invalid: ${sidecar.verdict}`);
  if (!REMEDIATION_ROUTE.has(sidecar.remediation_route ?? null)) errors.push(`remediation_route invalid: ${sidecar.remediation_route}`);
  if (sidecar.replan_required !== null && sidecar.replan_required !== undefined && typeof sidecar.replan_required !== 'boolean') {
    errors.push('replan_required must be boolean or null');
  }
  if (!isSafeRepoRelative(sidecar.report_path)) errors.push('report_path unsafe or missing');
  if (sidecarPath !== undefined && sidecarPath !== null && !isSafeRepoRelative(sidecarPath)) {
    errors.push('sidecarPath unsafe (must be safe repo-relative)');
  }

  const keys = Object.keys(sidecar);
  const sotaIdx = keys.indexOf('state_of_the_art_conformance');
  const planIdx = keys.indexOf('plan_conformance');
  if (sotaIdx !== -1 && planIdx !== -1 && sotaIdx > planIdx) {
    errors.push('state_of_the_art_conformance must be recorded before plan_conformance (DEC-200 D1)');
  }

  const inventory = Array.isArray(sidecar.changed_surface_inventory) ? sidecar.changed_surface_inventory : [];
  if (!Array.isArray(sidecar.changed_surface_inventory)) errors.push('changed_surface_inventory must be an array');
  const findings = Array.isArray(sidecar.findings) ? sidecar.findings : [];
  if (!Array.isArray(sidecar.findings)) errors.push('findings must be an array');
  const evidence = Array.isArray(sidecar.evidence) ? sidecar.evidence : [];
  if (!Array.isArray(sidecar.evidence)) errors.push('evidence must be an array');

  inventory.forEach((e, i) => checkInventoryEntry(e, i, errors));

  const invSurfaces = inventory.map((e) => e.surface).filter((s) => typeof s === 'string');
  const invCounts = new Map();
  for (const s of invSurfaces) invCounts.set(s, (invCounts.get(s) || 0) + 1);
  for (const [s, n] of invCounts) if (n > 1) errors.push(`changed_surface_inventory duplicate surface: ${s}`);
  const expectedSet = new Set(expectedSurfaces || []);
  const invSet = new Set(invSurfaces);
  for (const s of expectedSet) if (!invSet.has(s)) errors.push(`changed_surface_inventory missing expected surface: ${s}`);
  for (const s of invSet) if (!expectedSet.has(s)) errors.push(`changed_surface_inventory unexpected surface: ${s}`);
  // An empty inventory is only wrong when surfaces were actually expected — that
  // case is already caught by the "missing expected surface" loop above. When
  // expectedSurfaces is itself empty, an empty inventory is the correct match.

  const surfaceMap = new Map(inventory.filter((e) => typeof e?.surface === 'string').map((e) => [e.surface, e]));

  findings.forEach((f, i) => checkFindingEntry(f, i, errors));
  const findingIds = new Set(findings.map((f) => f?.finding_id).filter(Boolean));

  // Authority-insufficiency (stale / domain-mismatch) does not by itself invalidate
  // the handoff — DEC-200 D3/D4 require it to *produce* ESCALATE, which is a valid,
  // correctly fail-closed outcome. It only becomes QA_HANDOFF_INVALID when the axis
  // disagrees (claims PASS/FAIL despite insufficient authority).
  let authorityInsufficient = false;
  const domainDefaulted = [];
  evidence.forEach((e, i) => {
    if (checkEvidenceEntry(e, i, errors, surfaceMap, sidecar.evaluated_as_of, domainDefaulted)) authorityInsufficient = true;
    if (isNonEmptyString(e?.finding_id) && !findingIds.has(e.finding_id)) {
      errors.push(`evidence[${i}].finding_id references unknown finding: ${e.finding_id}`);
    }
  });
  if (authorityInsufficient && sidecar.state_of_the_art_conformance !== 'ESCALATE') {
    errors.push('state_of_the_art_conformance must be ESCALATE — stale or domain-mismatched authority evidence present (DEC-200 D3/D4)');
  }

  // not_applicable surfaces must never carry evidence (unconditional).
  const evidenceBySurface = new Map();
  for (const e of evidence) {
    if (typeof e?.surface !== 'string') continue;
    if (!evidenceBySurface.has(e.surface)) evidenceBySurface.set(e.surface, []);
    evidenceBySurface.get(e.surface).push(e);
  }
  for (const entry of inventory) {
    if (entry?.classification === 'not_applicable' && isNonEmptyString(entry.surface) && evidenceBySurface.has(entry.surface)) {
      errors.push(`evidence present for not_applicable surface: ${entry.surface}`);
    }
  }

  // A `blocking` classification unconditionally obligates a backing blocking finding
  // with supporting evidence, regardless of the eventual axis value (D2/D4).
  for (const entry of inventory) {
    if (entry?.classification !== 'blocking' || !isNonEmptyString(entry.surface)) continue;
    const backing = findings.filter((f) => f?.surface === entry.surface && f?.classification === 'blocking');
    if (backing.length === 0) {
      errors.push(`blocking surface '${entry.surface}' has no backing finding`);
      continue;
    }
    for (const f of backing) {
      if (!evidence.some((e) => e?.finding_id === f.finding_id)) {
        errors.push(`blocking finding '${f.finding_id}' (surface '${entry.surface}') has no supporting evidence`);
      }
    }
  }

  // D4: "a PASS without exact surface-by-surface evidence/N-A coverage is an invalid
  // handoff" — enforced when the currentness axis itself claims PASS.
  if (sidecar.state_of_the_art_conformance === 'PASS') {
    for (const entry of inventory) {
      if (entry?.classification === 'not_applicable' || !isNonEmptyString(entry.surface)) continue;
      if (!evidenceBySurface.has(entry.surface)) {
        errors.push(`surface '${entry.surface}' (${entry.classification}) has no evidence coverage required for a PASS currentness axis`);
      }
    }
  }

  let derivedAggregate = null;
  if (AXIS.has(sidecar.plan_conformance) && AXIS.has(sidecar.state_of_the_art_conformance)) {
    derivedAggregate = deriveAggregate(sidecar.plan_conformance, sidecar.state_of_the_art_conformance);
    if (sidecar.verdict !== derivedAggregate) {
      errors.push(`verdict '${sidecar.verdict}' disagrees with derived aggregate '${derivedAggregate}' (plan=${sidecar.plan_conformance}, sota=${sidecar.state_of_the_art_conformance})`);
    }
  }

  let derivedRoute = null;
  let derivedReplan = null;
  if (derivedAggregate) {
    const r = deriveRemediation(derivedAggregate, findings);
    derivedRoute = r.route;
    derivedReplan = r.replan;
    if ((sidecar.remediation_route ?? null) !== derivedRoute) {
      errors.push(`remediation_route '${sidecar.remediation_route}' disagrees with derived '${derivedRoute}'`);
    }
    if ((sidecar.replan_required ?? null) !== derivedReplan) {
      errors.push(`replan_required '${sidecar.replan_required}' disagrees with derived '${derivedReplan}'`);
    }
  }

  const valid = errors.length === 0;
  const authorityDomainDefaulted = domainDefaulted.length > 0;
  return {
    valid,
    errors,
    derivedAggregate,
    derivedRemediationRoute: derivedRoute,
    derivedReplanRequired: derivedReplan,
    authorityDomainDefaulted,
    authorityDomainDefaultedSurfaces: domainDefaulted,
    summary: valid ? {
      story_id: sidecar.story_id,
      schema_version: sidecar.schema_version,
      plan_conformance: sidecar.plan_conformance,
      state_of_the_art_conformance: sidecar.state_of_the_art_conformance,
      verdict: sidecar.verdict,
      remediation_route: sidecar.remediation_route,
      evaluated_as_of: sidecar.evaluated_as_of,
      surface_count: inventory.length,
      evidence_count: evidence.length,
      report_path: sidecar.report_path,
      // AC5: sidecar's own locator, distinct from report_path above — both
      // must be recorded on success, not just the Markdown report's path.
      sidecar_path: sidecarPath ?? null,
      // DEC-200 D3: observable signal — never silently absorbed (AC2/AC6).
      authority_domain_defaulted: authorityDomainDefaulted,
    } : null,
  };
}

// ── CLI wrapper ────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a.startsWith('--')) { out[a.slice(2)] = argv[i + 1]; i += 1; }
  }
  return out;
}

function readJson(path, label) {
  let raw;
  try {
    raw = readFileSync(path, 'utf8');
  } catch (err) {
    throw new Error(`${label} unreadable at ${path}: ${err.message}`);
  }
  try {
    return JSON.parse(raw);
  } catch (err) {
    throw new Error(`${label} is not valid JSON (${path}): ${err.message}`);
  }
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  if (cmd !== 'validate') {
    process.stderr.write('usage: qa-verdict.mjs validate --sidecar <path> --schema <path> --story-id <id> --expected-surfaces <path> [--sidecar-locator <repo-relative-path>]\n');
    process.exit(1);
  }
  const args = parseArgs(rest);
  let sidecar;
  let expectedSurfaces;
  try {
    sidecar = readJson(args.sidecar, 'sidecar');
    expectedSurfaces = readJson(args['expected-surfaces'], 'expected-surfaces');
    // schema file is read for existence/well-formedness only — enforcement is hand-rolled above.
    readJson(args.schema, 'schema');
  } catch (err) {
    process.stderr.write(`QA_HANDOFF_INVALID: ${err.message}\n`);
    process.exit(1);
  }
  if (!Array.isArray(expectedSurfaces)) {
    process.stderr.write('QA_HANDOFF_INVALID: expected-surfaces must be a JSON array\n');
    process.exit(1);
  }

  const result = validateQaVerdict({
    sidecar,
    storyId: args['story-id'],
    expectedSurfaces,
    sidecarPath: args['sidecar-locator'] ?? null,
  });
  if (!result.valid) {
    process.stderr.write(`QA_HANDOFF_INVALID: ${result.errors.join(' | ')}\n`);
    process.exit(1);
  }
  process.stdout.write(`${JSON.stringify(result.summary)}\n`);
  process.exit(0);
}

const isMain = process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  main();
}
