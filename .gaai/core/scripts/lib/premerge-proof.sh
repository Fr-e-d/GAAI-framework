#!/usr/bin/env bash
# lib/premerge-proof.sh — base-held pre-merge proof contract verifier
#
# Sourceable library. NEVER calls the GitHub API, curl, or any network
# primitive (grep-verifiable) — it is a pure function over (a) the trust
# manifest read from the resolved base commit B, (b) Git objects resolved
# from local refs, and (c) a caller-supplied evidence JSON blob describing
# the CI run. Evidence is untrusted input: every identity/commit/tree claim
# it carries is independently recomputed from Git and cross-checked, never
# taken at face value — this is what makes a forged or replayed evidence
# blob rejectable without ever calling out to GitHub.
#
# jq is a hard dependency. A security verifier fails closed if its own
# tooling is absent rather than silently degrading (mirrors test-gate.sh's
# "never treat an unobservable result as a pass" doctrine) — see
# reason=environment_error.
#
# Public entry points:
#   _premerge_canonical_json <file>
#     Prints canonical form (jq -S -c) of the JSON at <file>. Single shared
#     serialization path — every digest below goes through it, so a
#     key-reordered-but-semantically-identical document always hashes the
#     same and a changed value always hashes differently.
#   _premerge_load_manifest <path>
#     Structurally validates a trust_manifest instance — required fields
#     read live from premerge-policy.schema.json's own `required` array,
#     never hand-duplicated — and prints "<canonical_json>\t<sha256_digest>".
#   _premerge_resolve_tuple <mode> <base_ref> <head_ref> <merge_ref>
#     Resolves B, H, T from local Git refs (git rev-parse — never trusts a
#     caller-supplied SHA) and tree(T). For pull_request mode also asserts
#     parents(T) == (B, H) in that order. Prints "B H T TREE_T".
#   _premerge_check_trust_surface <B> <T> <path...>
#     git diff-tree --raw restricted to the given paths; any output (add,
#     delete, rename, mode/symlink flip, content change) means the surface
#     changed — returns 1 in that case.
#   _premerge_verify_jobs <required_jobs_json> <evidence_jobs_json>
#     Exact-once-per-required-job, strict conclusion=="success" (no
#     continue_on_error/skipped/neutral/cancelled/...). Extra non-required
#     jobs are ignored — never substitute, never poison.
#   _premerge_verify <manifest_repo_path> <evidence_json_path>
#     Top-level orchestrator. Emits the full verdict JSON (schema:
#     premerge-policy.schema.json#/$defs/verdict) to stdout. Returns 0 when
#     result.status=="success", 1 otherwise (result.reason set).
#
# Reason enum (stable, closed — see premerge-policy.schema.json reason_enum),
# checked in this order so a verdict never reports two simultaneous causes:
#   environment_error         jq/schema file unavailable (precondition).
#   schema_invalid             evidence unparsable/missing fields, or the
#                              manifest read from B fails structural checks.
#   identity_mode_conflict    evidence.identity shape doesn't match mode.
#   commit_unresolvable        B, H, or T doesn't resolve via git rev-parse.
#   parent_mismatch            pull_request: parents(T) != (B, H) in order.
#   tuple_forged                claimed base/head/merge sha != independently
#                              resolved B/H/T.
#   tree_mismatch               claimed tree_sha != independently resolved
#                              tree(T).
#   manifest_digest_mismatch   claimed digest != digest of the manifest
#                              actually read from B.
#   trust_surface_changed      a covered path differs between B and T.
#   run_attempt_mismatch       a job's own run_attempt disagrees with the
#                              evidence's top-level run.run_attempt (rejects
#                              evidence spliced from two CI attempts).
#   job_missing / job_duplicate / job_not_success — required-job semantics.
# Evidence JSON contract (caller-supplied, untrusted): repository, mode
# ("pull_request"|"merge_group"), identity (pull_request:
# {pr_number,base_ref,head_ref}; merge_group: {merge_group_ref,base_ref}),
# merge_ref (git ref resolving to T), base_sha/head_sha/merge_sha/tree_sha
# (claims, cross-checked against independent resolution), run
# {workflow_path,run_id,run_attempt,event}, manifest_digest (claim),
# jobs: [{name, conclusion, continue_on_error?, run_attempt?}].
#
# Env vars:
#   GAAI_PREMERGE_SCHEMA_PATH — override the schema path (default: resolved
#                               relative to this file's own location, so the
#                               framework schema is used regardless of the
#                               target repo's current working directory).

set -uo pipefail

_PREMERGE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PREMERGE_SCHEMA_PATH="${GAAI_PREMERGE_SCHEMA_PATH:-${_PREMERGE_LIB_DIR}/../../ci/premerge-policy.schema.json}"
_PREMERGE_REASON=""

_premerge_digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
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

_premerge_load_manifest() {
  local path="$1"
  command -v jq >/dev/null 2>&1 || { _premerge_fail environment_error; return 1; }
  [[ -f "$_PREMERGE_SCHEMA_PATH" ]] || { _premerge_fail environment_error; return 1; }
  [[ -s "$path" ]] || { _premerge_fail schema_invalid; return 1; }
  jq empty "$path" >/dev/null 2>&1 || { _premerge_fail schema_invalid; return 1; }

  local required_fields f
  required_fields="$(jq -r '.["$defs"].trust_manifest.required[]' "$_PREMERGE_SCHEMA_PATH" 2>/dev/null)" \
    || { _premerge_fail environment_error; return 1; }
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    jq -e --arg f "$f" 'has($f)' "$path" >/dev/null 2>&1 || { _premerge_fail schema_invalid; return 1; }
  done <<<"$required_fields"

  jq -e '.digest_algorithm == "sha256"
    and (.covered_paths | type == "array" and length >= 1)
    and (.required_jobs | type == "array" and length >= 1)
    and (.workflow | type == "object" and has("path") and has("name"))' \
    "$path" >/dev/null 2>&1 || { _premerge_fail schema_invalid; return 1; }

  local canon digest
  canon="$(_premerge_canonical_json "$path")" || { _premerge_fail schema_invalid; return 1; }
  digest="$(printf '%s' "$canon" | _premerge_digest)"
  printf '%s\t%s\n' "$canon" "$digest"
}

_premerge_resolve_tuple() {
  local mode="$1" base_ref="$2" head_ref="$3" merge_ref="$4"
  local b h t tree_t parents

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
  local out
  out="$(git diff-tree -r --raw "$b" "$t" -- "$@" 2>/dev/null)"
  [[ -z "$out" ]]
}

_premerge_verify_jobs() {
  local required_json="$1" evidence_jobs_json="$2" job count concl coe
  while IFS= read -r job; do
    [[ -z "$job" ]] && continue
    count="$(jq --arg j "$job" '[.[] | select(.name==$j)] | length' <<<"$evidence_jobs_json")"
    if [[ "$count" -eq 0 ]]; then
      _PREMERGE_REASON=job_missing; return 1
    elif [[ "$count" -gt 1 ]]; then
      _PREMERGE_REASON=job_duplicate; return 1
    fi
    concl="$(jq -r --arg j "$job" '.[] | select(.name==$j) | .conclusion' <<<"$evidence_jobs_json")"
    coe="$(jq -r --arg j "$job" '.[] | select(.name==$j) | (.continue_on_error // false)' <<<"$evidence_jobs_json")"
    [[ "$concl" == "success" && "$coe" != "true" ]] || { _PREMERGE_REASON=job_not_success; return 1; }
  done < <(jq -r '.[]' <<<"$required_json")
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
      repository: ($ev.repository // "unknown"),
      mode: ($ev.mode // "unknown"),
      identity: ($ev.identity // {}),
      base_sha: (if $b == "null" then ($ev.base_sha // null) else $b end),
      head_sha: (if $h == "null" then ($ev.head_sha // null) else $h end),
      merge_sha: (if $t == "null" then ($ev.merge_sha // null) else $t end),
      tree_sha: (if $tree == "null" then ($ev.tree_sha // null) else $tree end),
      run: ($ev.run // {}),
      manifest_digest: (if $digest == "" then null else $digest end),
      validation_profile: ($mf.validation_profile // ($ev.validation_profile // null)),
      jobs: ($ev.jobs // []),
      result: (if $reason == "" then {status:"success"} else {status:"rejected", reason:$reason} end)
    }'
}

_premerge_verify() {
  local manifest_repo_path="$1" evidence_path="$2"

  if ! command -v jq >/dev/null 2>&1; then
    printf '{"schema_version":"1.0.0","repository":null,"mode":null,"identity":null,"base_sha":null,"head_sha":null,"merge_sha":null,"tree_sha":null,"run":null,"manifest_digest":null,"validation_profile":null,"jobs":null,"result":{"status":"rejected","reason":"environment_error"}}\n'
    return 1
  fi

  [[ -f "$evidence_path" ]] && jq empty "$evidence_path" >/dev/null 2>&1 \
    || { _premerge_emit_verdict '{}' '{}' '' schema_invalid; return 1; }
  local evidence
  evidence="$(jq -c . "$evidence_path")"

  local f
  for f in repository mode identity merge_ref base_sha head_sha merge_sha tree_sha run manifest_digest jobs; do
    jq -e --arg f "$f" 'has($f)' <<<"$evidence" >/dev/null 2>&1 \
      || { _premerge_emit_verdict "$evidence" '{}' '' schema_invalid; return 1; }
  done
  jq -e '(.jobs|type=="array") and (.run|type=="object" and has("workflow_path") and has("run_id") and has("run_attempt") and has("event")) and (.identity|type=="object")' \
    <<<"$evidence" >/dev/null 2>&1 || { _premerge_emit_verdict "$evidence" '{}' '' schema_invalid; return 1; }

  local mode base_ref head_ref merge_ref
  mode="$(jq -r '.mode' <<<"$evidence")"
  merge_ref="$(jq -r '.merge_ref' <<<"$evidence")"
  if [[ "$mode" == "pull_request" ]]; then
    jq -e '.identity | has("pr_number") and has("base_ref") and has("head_ref") and (has("merge_group_ref")|not)' \
      <<<"$evidence" >/dev/null 2>&1 || { _premerge_emit_verdict "$evidence" '{}' '' identity_mode_conflict; return 1; }
    base_ref="$(jq -r '.identity.base_ref' <<<"$evidence")"
    head_ref="$(jq -r '.identity.head_ref' <<<"$evidence")"
  elif [[ "$mode" == "merge_group" ]]; then
    jq -e '.identity | has("merge_group_ref") and has("base_ref") and (has("pr_number")|not) and (has("head_ref")|not)' \
      <<<"$evidence" >/dev/null 2>&1 || { _premerge_emit_verdict "$evidence" '{}' '' identity_mode_conflict; return 1; }
    base_ref="$(jq -r '.identity.base_ref' <<<"$evidence")"
    head_ref=""
  else
    _premerge_emit_verdict "$evidence" '{}' '' schema_invalid; return 1
  fi

  local tuple tuple_rc
  tuple="$(_premerge_resolve_tuple "$mode" "$base_ref" "$head_ref" "$merge_ref")"; tuple_rc=$?
  if [[ $tuple_rc -ne 0 ]]; then
    _premerge_emit_verdict "$evidence" '{}' '' "${tuple#REASON }"; return 1
  fi
  local b h t tree_t
  read -r b h t tree_t <<<"$tuple"

  local claim_b claim_h claim_t
  claim_b="$(jq -r '.base_sha' <<<"$evidence")"; claim_h="$(jq -r '.head_sha' <<<"$evidence")"; claim_t="$(jq -r '.merge_sha' <<<"$evidence")"
  if [[ "$claim_b" != "$b" || "$claim_h" != "$h" || "$claim_t" != "$t" ]]; then
    _premerge_emit_verdict "$evidence" '{}' '' tuple_forged "$b" "$h" "$t" "$tree_t"; return 1
  fi

  local claim_tree
  claim_tree="$(jq -r '.tree_sha' <<<"$evidence")"
  if [[ "$claim_tree" != "$tree_t" ]]; then
    _premerge_emit_verdict "$evidence" '{}' '' tree_mismatch "$b" "$h" "$t" "$tree_t"; return 1
  fi

  local manifest_tmp manifest_out manifest_rc
  manifest_tmp="$(mktemp)"
  git show "${b}:${manifest_repo_path}" >"$manifest_tmp" 2>/dev/null
  manifest_out="$(_premerge_load_manifest "$manifest_tmp")"; manifest_rc=$?
  rm -f "$manifest_tmp"
  if [[ $manifest_rc -ne 0 ]]; then
    _premerge_emit_verdict "$evidence" '{}' '' "${manifest_out#REASON }" "$b" "$h" "$t" "$tree_t"; return 1
  fi
  local manifest_canon="${manifest_out%%$'\t'*}" manifest_digest="${manifest_out##*$'\t'}"

  local claim_digest
  claim_digest="$(jq -r '.manifest_digest' <<<"$evidence")"
  if [[ "$claim_digest" != "$manifest_digest" ]]; then
    _premerge_emit_verdict "$evidence" "$manifest_canon" "$manifest_digest" manifest_digest_mismatch "$b" "$h" "$t" "$tree_t"; return 1
  fi

  local covered_paths
  mapfile -t covered_paths < <(jq -r '.covered_paths[]' <<<"$manifest_canon")
  if ! _premerge_check_trust_surface "$b" "$t" "${covered_paths[@]}"; then
    _premerge_emit_verdict "$evidence" "$manifest_canon" "$manifest_digest" trust_surface_changed "$b" "$h" "$t" "$tree_t"; return 1
  fi

  local top_attempt mismatched
  top_attempt="$(jq -r '.run.run_attempt' <<<"$evidence")"
  mismatched="$(jq -r --argjson a "$top_attempt" '[.jobs[] | select(has("run_attempt") and .run_attempt != $a)] | length' <<<"$evidence")"
  if [[ "$mismatched" -gt 0 ]]; then
    _premerge_emit_verdict "$evidence" "$manifest_canon" "$manifest_digest" run_attempt_mismatch "$b" "$h" "$t" "$tree_t"; return 1
  fi

  local required_jobs_json evidence_jobs_json
  required_jobs_json="$(jq -c '.required_jobs' <<<"$manifest_canon")"
  evidence_jobs_json="$(jq -c '.jobs' <<<"$evidence")"
  if ! _premerge_verify_jobs "$required_jobs_json" "$evidence_jobs_json"; then
    _premerge_emit_verdict "$evidence" "$manifest_canon" "$manifest_digest" "$_PREMERGE_REASON" "$b" "$h" "$t" "$tree_t"; return 1
  fi

  _premerge_emit_verdict "$evidence" "$manifest_canon" "$manifest_digest" "" "$b" "$h" "$t" "$tree_t"
}
