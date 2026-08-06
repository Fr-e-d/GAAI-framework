#!/usr/bin/env bash
# lib/premerge-proof.sh — base-held pre-merge proof contract verifier
#
# Sourceable library. NEVER calls the GitHub API, curl, or any network
# primitive (grep-verifiable) and never mutates the repository — it is a
# pure function over (a) the trust manifest and the contract schema, both
# read from the resolved base commit B, (b) Git objects resolved from local
# refs, and (c) a caller-supplied evidence JSON blob describing the CI run.
# Evidence is untrusted input: claimed object SHAs and trees are recomputed
# from locally resolved refs and cross-checked, never taken at face value. The
# ref fields themselves — especially base_ref, which selects the trust root —
# are not authorization facts at this layer. A controller must bind them to the
# repository's base and current candidate before this proof can authorize a
# merge. This pure verifier never calls out to GitHub to make that binding.
#
# Trust-root rule: the contract schema is resolved ONLY from B, at
# .gaai/core/ci/premerge-policy.schema.json. A working-tree or merge-commit
# copy is never consulted, so a candidate cannot weaken the contract that
# judges it once the authorization layer has bound B to the repository base.
#
# Portability contract: Bash 3.2 — no mapfile/readarray, associative arrays,
# namerefs, case-conversion expansions, coproc, globstar, `wait -n`, `;;&`
# or `&>>`. jq, git, awk, mktemp, rm and one of sha256sum/shasum are hard
# dependencies. A security verifier fails closed when its own tooling, or
# its own trusted contract, is unavailable rather than silently degrading
# (mirrors test-gate.sh's "never treat an unobservable result as a pass"
# doctrine) — see reason=environment_error.
#
# Public entry points:
#   _premerge_canonical_json <file>
#     Prints canonical form (jq -S -c) of the JSON at <file>. Single shared
#     serialization path — every digest below goes through it, so a
#     key-reordered-but-semantically-identical document always hashes the
#     same and a changed value always hashes differently.
#   _premerge_load_manifest <path> [schema_path]
#     Structurally validates a trust_manifest instance — required and
#     allowed key sets read live from the published schema's own `required`
#     array and `properties` map, never hand-duplicated — and prints
#     "<canonical_json>\t<sha256_digest>". <schema_path> defaults to the
#     test-only GAAI_PREMERGE_SCHEMA_PATH resolution below; _premerge_verify
#     always passes the schema it extracted from B instead.
#   _premerge_resolve_tuple <mode> <base_ref> <head_ref> <merge_ref>
#     Resolves B, H, T from local Git refs (git rev-parse — never trusts a
#     caller-supplied SHA) and tree(T). For pull_request mode also asserts
#     parents(T) == (B, H) in that order. Prints "B H T TREE_T".
#   _premerge_check_trust_surface <B> <T> <path...>
#     git diff-tree --raw restricted to the given paths. Returns 0 when the
#     surface is unchanged, 1 when any output (add, delete, rename,
#     mode/symlink flip, content change) means it changed, and 2 when Git
#     itself failed — a Git error is never reported as unchanged.
#   _premerge_verify_jobs <required_jobs_json> <evidence_jobs_json>
#     Exact-once-per-required-job, strict conclusion=="success" (no
#     continue_on_error/skipped/neutral/cancelled/...). Extra non-required
#     jobs are ignored — never substitute, never poison. Asserts the
#     observed iteration count equals the declared list length.
#   _premerge_verify <manifest_repo_path> <evidence_json_path>
#     Top-level orchestrator. Emits the full verdict JSON (schema:
#     premerge-policy.schema.json#/$defs/verdict) to stdout. Returns 0 when
#     result.status=="success", 1 otherwise (result.reason set).
#
# Reason enum (stable, closed — see premerge-policy.schema.json reason_enum).
# The list below is the implemented check order, first match wins, so a
# verdict never reports two simultaneous causes. It is restated behind the
# same marker in that schema's reason_enum description; the two must stay
# equal.
#
# PRIORITY_ORDER: environment_error, schema_invalid, identity_mode_conflict, commit_unresolvable, parent_mismatch, tuple_forged, tree_mismatch, manifest_digest_mismatch, provenance_mismatch, policy_missing, trust_surface_changed, run_attempt_mismatch, job_missing, job_duplicate, job_not_success
#
#   environment_error          a precondition of the verifier itself is unmet:
#                              missing tool, unusable temporary directory,
#                              truncated iteration over a manifest-derived
#                              list, Git failure during the trust-surface
#                              comparison, or a trusted contract that cannot
#                              be acquired from the base commit (base ref
#                              unresolvable in this clone, schema absent or
#                              unparsable at B). Acquiring the contract
#                              necessarily precedes every data-level
#                              judgement, so classifying it at the top of the
#                              order keeps that order exact — it can never
#                              displace a lower-priority reason.
#   schema_invalid             evidence, or the manifest read from B, violates
#                              the published contract: unknown or missing key,
#                              wrong type, empty string, non-positive run
#                              attempt, duplicate array entry, unsafe covered
#                              path, identity matching neither shape.
#   identity_mode_conflict     identity is a valid published shape but not the
#                              one mode requires (after structural checks).
#   commit_unresolvable        H or T — and B, for a direct
#                              _premerge_resolve_tuple call — doesn't resolve.
#   parent_mismatch            pull_request: parents(T) != (B, H) in order.
#   tuple_forged                claimed base/head/merge sha != independently
#                              resolved B/H/T.
#   tree_mismatch               claimed tree_sha != resolved tree(T).
#   manifest_digest_mismatch   claimed digest != digest of the manifest
#                              actually read from B.
#   provenance_mismatch        run workflow path/name or validation_profile
#                              disagrees with the base-held manifest, or event
#                              disagrees with mode.
#   policy_missing             a covered path matches no object at B.
#   trust_surface_changed      a covered path differs between B and T.
#   run_attempt_mismatch       a job's own run_attempt disagrees with the
#                              evidence's top-level run.run_attempt (rejects
#                              evidence spliced from two CI attempts).
#   job_missing / job_duplicate / job_not_success — required-job semantics.
#
# Evidence JSON contract (caller-supplied, untrusted):
# premerge-policy.schema.json#/$defs/evidence. Required keys are repository,
# mode, identity, merge_ref, base_sha, head_sha, merge_sha, tree_sha, run,
# manifest_digest, validation_profile and jobs; x_extensions is the sole
# optional top-level extension and any other unrecognized key is
# schema_invalid (never silently ignored — malformed or incomplete evidence
# must never reach success). evidence.repository and its ref selectors are
# carried into the verdict but are NOT authorized here: binding repository,
# base_ref, head/current candidate and merge-group identity to controller-
# resolved state belongs to the merge-authorization layer, as does reading the
# manifest's rollover_approval_ref.
#
# Env vars:
#   GAAI_PREMERGE_SCHEMA_PATH — test-only default schema path for a direct
#                               _premerge_load_manifest call (default:
#                               resolved relative to this file's own
#                               location). It cannot redirect
#                               _premerge_verify, which always validates
#                               against the schema it extracted from B.

set -uo pipefail

_PREMERGE_LIB_SOURCE="${BASH_SOURCE[0]}"
case "$_PREMERGE_LIB_SOURCE" in
  */*) _PREMERGE_LIB_PARENT="${_PREMERGE_LIB_SOURCE%/*}" ;;
  *) _PREMERGE_LIB_PARENT="." ;;
esac
_PREMERGE_LIB_DIR="$(CDPATH= cd -- "$_PREMERGE_LIB_PARENT" 2>/dev/null && pwd)" \
  || _PREMERGE_LIB_DIR="$_PREMERGE_LIB_PARENT"
_PREMERGE_SCHEMA_PATH="${GAAI_PREMERGE_SCHEMA_PATH:-${_PREMERGE_LIB_DIR}/../../ci/premerge-policy.schema.json}"
# The one repository-relative location the trusted contract is read from at B.
_PREMERGE_SCHEMA_REPO_PATH=".gaai/core/ci/premerge-policy.schema.json"
_PREMERGE_REASON=""
_PREMERGE_TMPDIR=""

# Every hard dependency, checked once. A missing tool must produce a stable
# fail-closed reason, never a raw shell failure part-way through a check.
_premerge_have_tools() {
  local tool
  for tool in jq git awk mktemp rm; do
    command -v "$tool" >/dev/null 2>&1 || return 1
  done
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || return 1
  return 0
}

_premerge_digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    # Fail closed: an absent digest tool must never yield an empty digest that
    # compares equal to another empty digest.
    return 1
  fi
}

_premerge_canonical_json() {
  jq -S -c . "$1" 2>/dev/null
}

# Sets _PREMERGE_REASON (direct callers) AND echoes "REASON <code>" on
# stdout (callers captured via command substitution — a subshell, where a
# plain global write never reaches the parent once it completes).
_premerge_fail() {
  _PREMERGE_REASON="$1"
  printf 'REASON %s\n' "$1"
  return 1
}

# Reads the published key contract once: for each named document, the schema's
# own `required` array plus the key set of its `properties` map. Every
# predicate below is driven by this object, so the runtime never carries a
# second, hand-maintained copy of what the schema declares. A document whose
# key sets come back empty means the schema at hand is not the published
# contract, so nothing is emitted and the caller fails closed.
_premerge_schema_keysets() {
  jq -c '
    def ks($d): { required: (.["$defs"][$d].required // []),
                  allowed: ((.["$defs"][$d].properties // {}) | keys) };
    { manifest: ks("trust_manifest"), workflow: ks("workflow_identity"),
      evidence: ks("evidence"), run: ks("run_identity"), job: ks("job_result"),
      pr: ks("pull_request_identity"), mg: ks("merge_group_identity") }
    | select(all(.[]; (.required | length) > 0 and (.allowed | length) > 0))
  ' "$1" 2>/dev/null
}

# One predicate program per document: key sets come from the schema and every
# published type / enum / minimum / uniqueItems / nested-shape constraint is
# checked in a single jq invocation, not one subprocess per field.
_premerge_validate_manifest() {
  jq -e --argjson k "$1" '
    def str: type == "string" and length > 0;
    def keyset($s): (($s.required - keys) == []) and ((keys - $s.allowed) == []);
    def uniq_list: (type == "array") and (length >= 1) and ((unique | length) == length);
    # A covered path must denote exactly one auditable object at B: relative,
    # canonical and literal, with no empty/dot/parent component, control byte,
    # trailing separator, or Git pathspec magic.
    def safe_path: str
      and (startswith("/") | not) and (startswith(":") | not)
      and (index("\u0000") == null) and (index("\n") == null) and (index("\r") == null)
      and (test("(^|/)\\.{1,2}(/|$)") | not) and (contains("//") | not)
      and (endswith("/") | not) and (test("[*?\\[\\]]") | not);
    (type == "object") and keyset($k.manifest)
    and (.schema_version | str) and (.policy_version | str) and (.validation_profile | str)
    and (.digest_algorithm == "sha256")
    and (.workflow | (type == "object") and keyset($k.workflow) and (.path | str) and (.name | str))
    and (.covered_paths | uniq_list and all(safe_path))
    and (.required_jobs | uniq_list and all(str))
    and ((has("rollover_approval_ref") | not) or (.rollover_approval_ref | str))
  ' <<<"$2" >/dev/null 2>&1
}

_premerge_validate_evidence() {
  jq -e --argjson k "$1" '
    def str: type == "string" and length > 0;
    def posint: type == "number" and . == floor and . >= 1;
    def keyset($s): (($s.required - keys) == []) and ((keys - $s.allowed) == []);
    (type == "object") and keyset($k.evidence)
    and (.repository | str) and (.merge_ref | str) and (.manifest_digest | str)
    and (.validation_profile | str)
    and ([.base_sha, .head_sha, .merge_sha, .tree_sha] | all(str))
    and (.mode == "pull_request" or .mode == "merge_group")
    # Structure only: identity must be one of the two published shapes. Which
    # shape mode requires is identity_mode_conflict, checked after this.
    and (.identity | (type == "object")
          and ((keyset($k.pr) and (.pr_number | posint) and (.base_ref | str) and (.head_ref | str))
               or (keyset($k.mg) and (.merge_group_ref | str) and (.base_ref | str))))
    and (.run | (type == "object") and keyset($k.run)
          and ([.workflow_path, .workflow_name, .run_id, .event] | all(str))
          and (.run_attempt | posint))
    and ((.jobs | type) == "array")
    and (.jobs | all((type == "object") and keyset($k.job)
          and (.name | str) and (.conclusion | str)
          and ((has("continue_on_error") | not) or (.continue_on_error | type == "boolean"))
          and ((has("run_attempt") | not) or (.run_attempt | posint))))
    and ((has("x_extensions") | not) or (.x_extensions | type == "object"))
  ' <<<"$2" >/dev/null 2>&1
}

_premerge_load_manifest() {
  local path="$1" schema="${2:-$_PREMERGE_SCHEMA_PATH}"
  local keysets canon digest
  _PREMERGE_REASON=""
  _premerge_have_tools || { _premerge_fail environment_error; return 1; }
  [[ -s "$schema" ]] || { _premerge_fail environment_error; return 1; }
  keysets="$(_premerge_schema_keysets "$schema")"
  [[ -n "$keysets" ]] || { _premerge_fail environment_error; return 1; }

  [[ -s "$path" ]] || { _premerge_fail schema_invalid; return 1; }
  canon="$(_premerge_canonical_json "$path")"
  [[ -n "$canon" ]] || { _premerge_fail schema_invalid; return 1; }
  _premerge_validate_manifest "$keysets" "$canon" || { _premerge_fail schema_invalid; return 1; }

  digest="$(printf '%s' "$canon" | _premerge_digest)"
  [[ -n "$digest" ]] || { _premerge_fail environment_error; return 1; }
  printf '%s\t%s\n' "$canon" "$digest"
}

_premerge_resolve_tuple() {
  local mode="$1" base_ref="$2" head_ref="$3" merge_ref="$4"
  local b h t tree_t parents
  _PREMERGE_REASON=""

  b="$(git rev-parse --verify -q "${base_ref}^{commit}" 2>/dev/null)" || { _premerge_fail commit_unresolvable; return 1; }
  t="$(git rev-parse --verify -q "${merge_ref}^{commit}" 2>/dev/null)" || { _premerge_fail commit_unresolvable; return 1; }

  if [[ "$mode" == "pull_request" ]]; then
    h="$(git rev-parse --verify -q "${head_ref}^{commit}" 2>/dev/null)" || { _premerge_fail commit_unresolvable; return 1; }
    parents="$(git show -s --format=%P "$t" 2>/dev/null)" || { _premerge_fail commit_unresolvable; return 1; }
    [[ "$parents" == "$b $h" ]] || { _premerge_fail parent_mismatch; return 1; }
  else
    h="$t"
  fi

  tree_t="$(git rev-parse --verify -q "${t}^{tree}" 2>/dev/null)" || { _premerge_fail commit_unresolvable; return 1; }
  printf '%s %s %s %s\n' "$b" "$h" "$t" "$tree_t"
}

_premerge_check_trust_surface() {
  local b="$1" t="$2"; shift 2
  local out rc path top_paths
  top_paths=()
  for path in "$@"; do
    top_paths[${#top_paths[@]}]=":(top,literal)${path}"
  done
  [[ ${#top_paths[@]} -gt 0 ]] || return 2
  # git diff-tree exits 0 whether or not it found differences, so a non-zero
  # status is a real Git failure. Reporting that as "unchanged" would fail
  # open on the single most security-relevant comparison here. Manifest paths
  # are repository-root-relative, so top+literal magic prevents the caller's
  # current directory from changing which object each path denotes.
  out="$(git diff-tree -r --raw "$b" "$t" -- "${top_paths[@]}" 2>/dev/null)"; rc=$?
  [[ $rc -eq 0 ]] || return 2
  [[ -z "$out" ]]
}

_premerge_verify_jobs() {
  local required_json="$1" evidence_jobs_json="$2" job count concl coe
  local declared observed=0 required_names
  _PREMERGE_REASON=""
  required_names=()
  declared="$(jq -r 'length' <<<"$required_json" 2>/dev/null)"
  while IFS= read -r job; do
    [[ -z "$job" ]] && continue
    required_names[${#required_names[@]}]="$job"
    observed=$((observed + 1))
  done < <(jq -r '.[]' <<<"$required_json")
  # An empty or truncated expansion would otherwise verify nothing and return
  # success, which is exactly the shape of a silent authorization bypass. The
  # assertion runs before any job is judged, so a mis-expanded list can never
  # be reported as an ordinary required-job finding either.
  [[ "$observed" == "$declared" && $observed -gt 0 ]] \
    || { _PREMERGE_REASON=environment_error; return 1; }

  # Sweep by reason class, not required-job order, so simultaneous defects obey
  # the published job_missing -> job_duplicate -> job_not_success priority.
  for job in "${required_names[@]}"; do
    count="$(jq --arg j "$job" '[.[] | select(.name==$j)] | length' <<<"$evidence_jobs_json")"
    [[ "$count" -gt 0 ]] || { _PREMERGE_REASON=job_missing; return 1; }
  done
  for job in "${required_names[@]}"; do
    count="$(jq --arg j "$job" '[.[] | select(.name==$j)] | length' <<<"$evidence_jobs_json")"
    [[ "$count" -le 1 ]] || { _PREMERGE_REASON=job_duplicate; return 1; }
  done
  for job in "${required_names[@]}"; do
    concl="$(jq -r --arg j "$job" '.[] | select(.name==$j) | .conclusion' <<<"$evidence_jobs_json")"
    coe="$(jq -r --arg j "$job" '.[] | select(.name==$j) | (.continue_on_error // false)' <<<"$evidence_jobs_json")"
    [[ "$concl" == "success" && "$coe" != "true" ]] || { _PREMERGE_REASON=job_not_success; return 1; }
  done
  return 0
}

_premerge_emit_verdict() {
  # NOTE: default-value expansion (${1:-{}}) is deliberately NOT used here —
  # bash's ${VAR:-WORD} closes at the first unescaped '}' inside WORD, so a
  # literal "{}" default leaks a stray '}' into the value. Plain empty-string
  # checks avoid the trap.
  local evidence_json="$1" manifest_canon="$2" manifest_digest="${3:-}" reason="${4:-}"
  local b="${5:-null}" h="${6:-null}" t="${7:-null}" tree_t="${8:-null}"
  [[ -z "$evidence_json" ]] && evidence_json='{}'
  [[ -z "$manifest_canon" ]] && manifest_canon='{}'
  jq -n \
    --argjson ev "$evidence_json" --argjson mf "$manifest_canon" \
    --arg digest "$manifest_digest" --arg reason "$reason" \
    --arg b "$b" --arg h "$h" --arg t "$t" --arg tree "$tree_t" \
    '{
      schema_version: "1.0.0",
      repository: ($ev.repository // null),
      mode: ($ev.mode // null),
      identity: ($ev.identity // null),
      base_sha: (if $b == "null" then ($ev.base_sha // null) else $b end),
      head_sha: (if $h == "null" then ($ev.head_sha // null) else $h end),
      merge_sha: (if $t == "null" then ($ev.merge_sha // null) else $t end),
      tree_sha: (if $tree == "null" then ($ev.tree_sha // null) else $tree end),
      run: ($ev.run // null),
      manifest_digest: (if $digest == "" then null else $digest end),
      validation_profile: ($mf.validation_profile // ($ev.validation_profile // null)),
      jobs: ($ev.jobs // null),
      result: (if $reason == "" then {status:"success"} else {status:"rejected", reason:$reason} end)
    }'
}

# Emits a rejection verdict and releases the temporary trust-root directory.
# Callers pass empty evidence for any rejection raised before the evidence has
# been structurally validated, so a verdict never echoes unvalidated input and
# every verdict this library can emit conforms to $defs/verdict.
_premerge_reject() {
  local evidence_json="${1:-}" manifest_canon="${2:-}" manifest_digest="${3:-}"
  local reason="${4:-environment_error}"
  local b="${5:-null}" h="${6:-null}" t="${7:-null}" tree_t="${8:-null}"
  [[ -n "$reason" ]] || reason=environment_error
  [[ -n "$_PREMERGE_TMPDIR" ]] && rm -rf "$_PREMERGE_TMPDIR"
  _PREMERGE_TMPDIR=""
  _premerge_emit_verdict "$evidence_json" "$manifest_canon" "$manifest_digest" "$reason" "$b" "$h" "$t" "$tree_t"
  return 1
}

_premerge_verify() {
  local manifest_repo_path="$1" evidence_path="$2"
  _PREMERGE_REASON=""

  if ! command -v jq >/dev/null 2>&1; then
    printf '{"schema_version":"1.0.0","repository":null,"mode":null,"identity":null,"base_sha":null,"head_sha":null,"merge_sha":null,"tree_sha":null,"run":null,"manifest_digest":null,"validation_profile":null,"jobs":null,"result":{"status":"rejected","reason":"environment_error"}}\n'
    return 1
  fi

  _PREMERGE_TMPDIR=""
  _premerge_have_tools || { _premerge_reject '' '' '' environment_error; return 1; }

  # ── schema_invalid (1/2): the evidence document must parse and must name a
  # base ref, which is the minimum needed to reach the trust root at all.
  [[ -s "$evidence_path" ]] && jq empty "$evidence_path" >/dev/null 2>&1 \
    || { _premerge_reject '' '' '' schema_invalid; return 1; }
  local evidence
  evidence="$(jq -c . "$evidence_path")"
  jq -e 'type == "object" and (.identity | type == "object")
    and (.identity.base_ref | type == "string" and length > 0)' \
    <<<"$evidence" >/dev/null 2>&1 || { _premerge_reject '' '' '' schema_invalid; return 1; }

  # ── environment_error: acquire the trust root. The contract schema is taken
  # from B and never from the working tree or T, so a candidate cannot weaken
  # the rules that judge it, and GAAI_PREMERGE_SCHEMA_PATH cannot redirect it.
  # Acquisition necessarily precedes every data-level judgement, so each of its
  # failure modes is an environment_error — the top of the priority order —
  # and can never displace a lower-priority reason.
  local base_ref b keysets
  base_ref="$(jq -r '.identity.base_ref' <<<"$evidence")"
  b="$(git rev-parse --verify -q "${base_ref}^{commit}" 2>/dev/null)" \
    || { _premerge_reject '' '' '' environment_error; return 1; }
  _PREMERGE_TMPDIR="$(mktemp -d 2>/dev/null)" \
    || { _premerge_reject '' '' '' environment_error; return 1; }
  local schema_file="${_PREMERGE_TMPDIR}/schema.json"
  git show "${b}:${_PREMERGE_SCHEMA_REPO_PATH}" >"$schema_file" 2>/dev/null
  keysets="$(_premerge_schema_keysets "$schema_file")"
  [[ -n "$keysets" ]] || { _premerge_reject '' '' '' environment_error; return 1; }

  # ── schema_invalid (2/2): the full published contract, evidence first, then
  # the manifest read from B. Both are checked before any Git-state judgement
  # so that a malformed document can never be reported as a later reason.
  _premerge_validate_evidence "$keysets" "$evidence" \
    || { _premerge_reject '' '' '' schema_invalid; return 1; }

  local manifest_file="${_PREMERGE_TMPDIR}/manifest.json" manifest_out manifest_rc
  git show "${b}:${manifest_repo_path}" >"$manifest_file" 2>/dev/null
  manifest_out="$(_premerge_load_manifest "$manifest_file" "$schema_file")"; manifest_rc=$?
  if [[ $manifest_rc -ne 0 ]]; then
    _premerge_reject "$evidence" '' '' "${manifest_out#REASON }"; return 1
  fi
  local manifest_canon="${manifest_out%%$'\t'*}" manifest_digest="${manifest_out##*$'\t'}"

  # ── identity_mode_conflict: the identity is already known to be one of the
  # two published shapes; here it must be the shape this mode requires.
  jq -e 'if .mode == "pull_request" then (.identity | has("pr_number"))
         else (.identity | has("merge_group_ref")) end' \
    <<<"$evidence" >/dev/null 2>&1 \
    || { _premerge_reject "$evidence" '' '' identity_mode_conflict; return 1; }

  local mode merge_ref head_ref
  IFS=$'\t' read -r mode merge_ref head_ref \
    <<<"$(jq -r '[.mode, .merge_ref, (.identity.head_ref // "")] | @tsv' <<<"$evidence")"

  # ── commit_unresolvable / parent_mismatch
  local tuple tuple_rc
  tuple="$(_premerge_resolve_tuple "$mode" "$base_ref" "$head_ref" "$merge_ref")"; tuple_rc=$?
  if [[ $tuple_rc -ne 0 ]]; then
    _premerge_reject "$evidence" '' '' "${tuple#REASON }"; return 1
  fi
  local h t tree_t
  read -r b h t tree_t <<<"$tuple"

  # ── tuple_forged / tree_mismatch / manifest_digest_mismatch
  local claim_b claim_h claim_t claim_tree claim_digest
  IFS=$'\t' read -r claim_b claim_h claim_t claim_tree claim_digest \
    <<<"$(jq -r '[.base_sha, .head_sha, .merge_sha, .tree_sha, .manifest_digest] | @tsv' <<<"$evidence")"
  if [[ "$claim_b" != "$b" || "$claim_h" != "$h" || "$claim_t" != "$t" ]]; then
    _premerge_reject "$evidence" '' '' tuple_forged "$b" "$h" "$t" "$tree_t"; return 1
  fi
  if [[ "$claim_tree" != "$tree_t" ]]; then
    _premerge_reject "$evidence" '' '' tree_mismatch "$b" "$h" "$t" "$tree_t"; return 1
  fi
  if [[ "$claim_digest" != "$manifest_digest" ]]; then
    _premerge_reject "$evidence" "$manifest_canon" "$manifest_digest" manifest_digest_mismatch "$b" "$h" "$t" "$tree_t"; return 1
  fi

  # ── provenance_mismatch: the run must be the workflow and the profile the
  # base-held manifest names, under the trigger this mode requires. Otherwise a
  # successful run of some other workflow could be presented as this proof.
  jq -e --argjson mf "$manifest_canon" '
      (.run.workflow_path == $mf.workflow.path)
      and (.run.workflow_name == $mf.workflow.name)
      and (.validation_profile == $mf.validation_profile)
      and (.run.event == .mode)' \
    <<<"$evidence" >/dev/null 2>&1 \
    || { _premerge_reject "$evidence" "$manifest_canon" "$manifest_digest" provenance_mismatch "$b" "$h" "$t" "$tree_t"; return 1; }

  # ── policy_missing: every covered path must name a real object at B, or the
  # comparison below would compare nothing and report an unchanged surface.
  # The observed-vs-declared count assertion makes a truncated expansion an
  # environment_error instead of a silently empty verification.
  local covered_paths declared observed=0 path
  covered_paths=()
  declared="$(jq -r '.covered_paths | length' <<<"$manifest_canon")"
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    covered_paths[${#covered_paths[@]}]="$path"
    observed=$((observed + 1))
  done <<<"$(jq -r '.covered_paths[]' <<<"$manifest_canon")"
  if [[ "$observed" != "$declared" || $observed -eq 0 ]]; then
    _premerge_reject "$evidence" "$manifest_canon" "$manifest_digest" environment_error "$b" "$h" "$t" "$tree_t"; return 1
  fi
  for path in "${covered_paths[@]}"; do
    git cat-file -e "${b}:${path}" 2>/dev/null \
      || { _premerge_reject "$evidence" "$manifest_canon" "$manifest_digest" policy_missing "$b" "$h" "$t" "$tree_t"; return 1; }
  done

  # ── trust_surface_changed (a Git failure here is an environment_error)
  local surface_rc
  _premerge_check_trust_surface "$b" "$t" "${covered_paths[@]}"; surface_rc=$?
  if [[ $surface_rc -eq 2 ]]; then
    _premerge_reject "$evidence" "$manifest_canon" "$manifest_digest" environment_error "$b" "$h" "$t" "$tree_t"; return 1
  elif [[ $surface_rc -ne 0 ]]; then
    _premerge_reject "$evidence" "$manifest_canon" "$manifest_digest" trust_surface_changed "$b" "$h" "$t" "$tree_t"; return 1
  fi

  # ── run_attempt_mismatch
  local top_attempt mismatched
  top_attempt="$(jq -r '.run.run_attempt' <<<"$evidence")"
  mismatched="$(jq -r --argjson a "$top_attempt" '[.jobs[] | select(has("run_attempt") and .run_attempt != $a)] | length' <<<"$evidence")"
  if [[ "$mismatched" -gt 0 ]]; then
    _premerge_reject "$evidence" "$manifest_canon" "$manifest_digest" run_attempt_mismatch "$b" "$h" "$t" "$tree_t"; return 1
  fi

  # ── job_missing / job_duplicate / job_not_success
  local required_jobs_json evidence_jobs_json
  required_jobs_json="$(jq -c '.required_jobs' <<<"$manifest_canon")"
  evidence_jobs_json="$(jq -c '.jobs' <<<"$evidence")"
  if ! _premerge_verify_jobs "$required_jobs_json" "$evidence_jobs_json"; then
    _premerge_reject "$evidence" "$manifest_canon" "$manifest_digest" "$_PREMERGE_REASON" "$b" "$h" "$t" "$tree_t"; return 1
  fi

  rm -rf "$_PREMERGE_TMPDIR"; _PREMERGE_TMPDIR=""
  _premerge_emit_verdict "$evidence" "$manifest_canon" "$manifest_digest" "" "$b" "$h" "$t" "$tree_t"
}
