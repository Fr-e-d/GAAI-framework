#!/usr/bin/env bash
# premerge-proof.test.sh — hermetic regression suite for lib/premerge-proof.sh
#
# Scenario map (Tn -> Story E1108S01 AC):
#   T0  AC1        shipped template validates against the shipped schema
#   T1  AC1/2/4/5/6 valid pull_request fixture -> success
#   T2  AC2/6      valid merge_group fixture -> success
#   T3  AC2/6      swapped parents (H,B) -> parent_mismatch
#   T4  AC2/6      stale/forged base claim -> tuple_forged
#   T5  AC2/6      forged head claim (replayed) -> tuple_forged
#   T6  AC2/6      forged tree claim -> tree_mismatch
#   T7  AC1/6      manifest substitution (digest claim mismatch) -> manifest_digest_mismatch
#   T8  AC3/6      covered-path content change -> trust_surface_changed
#   T9  AC3        covered-path mode-only change -> trust_surface_changed
#   T10 AC3        covered-path symlink flip -> trust_surface_changed
#   T11 AC3        covered-path rename (delete+add) -> trust_surface_changed
#   T12 AC3        uncovered-path change is ignored -> success (boundary, folded into T1)
#   T13 AC6        changed run_attempt spliced across jobs -> run_attempt_mismatch
#   T14 AC5/6      duplicate required job -> job_duplicate
#   T15 AC5/6      missing required job -> job_missing
#   T16 AC5/6      every non-success conclusion -> job_not_success
#   T17 AC5        continue_on_error marker on a required job -> job_not_success
#   T18 AC5        extra non-required job (any conclusion) ignored -> success
#   T19 AC2        identity/mode shape conflict -> identity_mode_conflict
#   T20 AC2/4      unresolvable ref -> commit_unresolvable
#   T21 AC4        evidence missing a required field -> schema_invalid
#   T22 AC4        evidence is not valid JSON -> schema_invalid
#   T23 AC1/4      jq unavailable -> environment_error
#   T24 AC1        canonical digest: reorder-stable, value-sensitive
#   T25 AC1        manifest missing a required field -> schema_invalid (unit-level)
set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/premerge-proof.sh
source "${SCRIPT_DIR}/lib/premerge-proof.sh"
TEMPLATE_PATH="${SCRIPT_DIR}/../templates/ci/premerge-policy.json"

FIXTURE_BASE="/tmp/gaai-premerge-proof-test-$$"
trap 'rm -rf "$FIXTURE_BASE"' EXIT
mkdir -p "$FIXTURE_BASE"

check_reason() {
  local out="$1" expected="$2" label="$3" status reason
  status="$(jq -r '.result.status' <<<"$out" 2>/dev/null)"
  reason="$(jq -r '.result.reason // empty' <<<"$out" 2>/dev/null)"
  if [[ "$status" == "rejected" && "$reason" == "$expected" ]]; then
    pass "$label (reason=$expected)"
  else
    fail "$label (expected reason=$expected, got status=$status reason=$reason)"
  fi
}
check_success() {
  local out="$1" label="$2" status
  status="$(jq -r '.result.status' <<<"$out" 2>/dev/null)"
  [[ "$status" == "success" ]] && pass "$label" || fail "$label (expected success, got: $out)"
}

setup_repo() {
  rm -rf "$1"; mkdir -p "$1"
  git init -q "$1"
  git -C "$1" config user.email "test@gaai.local"
  git -C "$1" config user.name "GAAI Test"
  git -C "$1" config core.hooksPath /dev/null
}
gcommit() {
  git -C "$1" add -A
  GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" \
    git -C "$1" commit -q -m "$2"
}
make_manifest() {
  jq -n --argjson cp "$1" --argjson rj "$2" '{
    schema_version:"1.0.0", policy_version:"1", digest_algorithm:"sha256",
    workflow:{path:".github/workflows/test-gate.yml", name:"Test Gate"},
    covered_paths:$cp, required_jobs:$rj, validation_profile:"standard"
  }'
}
run_verify() { ( cd "$1" && _premerge_verify "$2" "$3" ); }
# Mirrors _premerge_load_manifest's own canon-then-digest path exactly (command
# substitution strips the trailing newline jq -S -c emits; a direct pipe would
# not, and would silently digest a different byte sequence than the library).
manifest_digest_of() {
  local canon
  canon="$(_premerge_canonical_json "$1")"
  printf '%s' "$canon" | _premerge_digest
}

build_pr_fixture() {
  local repo="$1"
  setup_repo "$repo"
  make_manifest '["policy.json","guarded.txt"]' '["job-a","job-b"]' > "$repo/policy.json"
  printf 'guarded-v1' > "$repo/guarded.txt"
  printf 'other-v1' > "$repo/other.txt"
  gcommit "$repo" "init"
  PR_B="$(git -C "$repo" rev-parse HEAD)"
  printf 'other-v2' > "$repo/other.txt"
  gcommit "$repo" "head change (uncovered path)"
  PR_H="$(git -C "$repo" rev-parse HEAD)"
  local tree_h
  tree_h="$(git -C "$repo" rev-parse "${PR_H}^{tree}")"
  PR_T="$(GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" \
    git -C "$repo" commit-tree "$tree_h" -p "$PR_B" -p "$PR_H" -m merge)"
  PR_TREE_T="$(git -C "$repo" rev-parse "${PR_T}^{tree}")"
  git -C "$repo" update-ref refs/heads/base "$PR_B"
  git -C "$repo" update-ref refs/heads/candidate "$PR_H"
  git -C "$repo" update-ref refs/heads/merge "$PR_T"
  PR_MANIFEST_DIGEST="$(manifest_digest_of "$repo/policy.json")"
}
build_evidence_pr() {
  local base="$1" head="$2" merge="$3" tree="$4" digest="$5" jobs="$6" attempt="$7" out="$8"
  jq -n --arg base "$base" --arg head "$head" --arg merge "$merge" --arg tree "$tree" \
        --arg digest "$digest" --argjson jobs "$jobs" --argjson attempt "$attempt" '{
    repository:"acme/example", mode:"pull_request",
    identity:{pr_number:42, base_ref:"base", head_ref:"candidate"},
    merge_ref:"merge",
    base_sha:$base, head_sha:$head, merge_sha:$merge, tree_sha:$tree,
    run:{workflow_path:".github/workflows/test-gate.yml", run_id:"1001", run_attempt:$attempt, event:"pull_request"},
    manifest_digest:$digest, jobs:$jobs
  }' > "$out"
}

build_mg_fixture() {
  local repo="$1"
  setup_repo "$repo"
  make_manifest '["policy.json"]' '["job-a"]' > "$repo/policy.json"
  gcommit "$repo" "init"
  MG_B="$(git -C "$repo" rev-parse HEAD)"
  printf 'candidate' > "$repo/other.txt"
  gcommit "$repo" "candidate"
  MG_T="$(git -C "$repo" rev-parse HEAD)"
  MG_TREE_T="$(git -C "$repo" rev-parse "${MG_T}^{tree}")"
  git -C "$repo" update-ref refs/heads/base "$MG_B"
  git -C "$repo" update-ref refs/heads/mg "$MG_T"
  MG_MANIFEST_DIGEST="$(manifest_digest_of "$repo/policy.json")"
}
build_evidence_mg() {
  local base="$1" merge="$2" tree="$3" digest="$4" jobs="$5" attempt="$6" out="$7"
  jq -n --arg base "$base" --arg merge "$merge" --arg tree "$tree" --arg digest "$digest" \
        --argjson jobs "$jobs" --argjson attempt "$attempt" '{
    repository:"acme/example", mode:"merge_group",
    identity:{merge_group_ref:"mg", base_ref:"base"},
    merge_ref:"mg",
    base_sha:$base, head_sha:$merge, merge_sha:$merge, tree_sha:$tree,
    run:{workflow_path:".github/workflows/test-gate.yml", run_id:"2001", run_attempt:$attempt, event:"merge_group"},
    manifest_digest:$digest, jobs:$jobs
  }' > "$out"
}

JOBS_OK='[{"name":"job-a","conclusion":"success"},{"name":"job-b","conclusion":"success"}]'
JOBS_OK_MG='[{"name":"job-a","conclusion":"success"}]'

# ── T0: shipped template validates against shipped schema ────────────────────
echo ""; echo "T0: template validates against schema"
out="$(_premerge_load_manifest "$TEMPLATE_PATH")"; rc=$?
[[ $rc -eq 0 && -n "$out" ]] && pass "T0: template loads + validates" || fail "T0: template failed to validate (reason=${_PREMERGE_REASON:-})"

# ── T1: valid pull_request fixture -> success (also covers T12 uncovered-path boundary) ──
echo ""; echo "T1: valid pull_request fixture"
R1="${FIXTURE_BASE}/t1"; build_pr_fixture "$R1"
E1="${FIXTURE_BASE}/t1-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E1"
out="$(run_verify "$R1" "policy.json" "$E1")"
check_success "$out" "T1: valid PR proof succeeds despite uncovered-path change (T12)"

# ── T2: valid merge_group fixture -> success ──────────────────────────────────
echo ""; echo "T2: valid merge_group fixture"
R2="${FIXTURE_BASE}/t2"; build_mg_fixture "$R2"
E2="${FIXTURE_BASE}/t2-evidence.json"
build_evidence_mg "$MG_B" "$MG_T" "$MG_TREE_T" "$MG_MANIFEST_DIGEST" "$JOBS_OK_MG" 1 "$E2"
out="$(run_verify "$R2" "policy.json" "$E2")"
check_success "$out" "T2: valid merge_group proof succeeds"

# ── T3: swapped parents -> parent_mismatch ────────────────────────────────────
echo ""; echo "T3: swapped parent order"
R3="${FIXTURE_BASE}/t3"; build_pr_fixture "$R3"
SWAPPED_T="$(GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" \
  git -C "$R3" commit-tree "$PR_TREE_T" -p "$PR_H" -p "$PR_B" -m "swapped merge")"
git -C "$R3" update-ref refs/heads/merge "$SWAPPED_T"
SWAPPED_TREE="$(git -C "$R3" rev-parse "${SWAPPED_T}^{tree}")"
E3="${FIXTURE_BASE}/t3-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$SWAPPED_T" "$SWAPPED_TREE" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E3"
out="$(run_verify "$R3" "policy.json" "$E3")"
check_reason "$out" "parent_mismatch" "T3: swapped parents rejected"

# ── T4: forged/stale base claim -> tuple_forged ───────────────────────────────
echo ""; echo "T4: forged base_sha claim"
R4="${FIXTURE_BASE}/t4"; build_pr_fixture "$R4"
E4="${FIXTURE_BASE}/t4-evidence.json"
build_evidence_pr "$PR_H" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E4"
out="$(run_verify "$R4" "policy.json" "$E4")"
check_reason "$out" "tuple_forged" "T4: forged base claim rejected"

# ── T5: forged/replayed head claim -> tuple_forged ────────────────────────────
echo ""; echo "T5: forged head_sha claim (replay)"
R5="${FIXTURE_BASE}/t5"; build_pr_fixture "$R5"
E5="${FIXTURE_BASE}/t5-evidence.json"
build_evidence_pr "$PR_B" "$PR_B" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E5"
out="$(run_verify "$R5" "policy.json" "$E5")"
check_reason "$out" "tuple_forged" "T5: forged/replayed head claim rejected"

# ── T6: forged tree claim -> tree_mismatch ────────────────────────────────────
echo ""; echo "T6: forged tree_sha claim"
R6="${FIXTURE_BASE}/t6"; build_pr_fixture "$R6"
E6="${FIXTURE_BASE}/t6-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_B" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E6"
out="$(run_verify "$R6" "policy.json" "$E6")"
check_reason "$out" "tree_mismatch" "T6: forged tree claim rejected"

# ── T7: manifest substitution -> manifest_digest_mismatch ────────────────────
echo ""; echo "T7: manifest substitution"
R7="${FIXTURE_BASE}/t7"; build_pr_fixture "$R7"
E7="${FIXTURE_BASE}/t7-evidence.json"
TAMPERED_DIGEST="$(make_manifest '["policy.json"]' '["job-x"]' | _premerge_digest)"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$TAMPERED_DIGEST" "$JOBS_OK" 1 "$E7"
out="$(run_verify "$R7" "policy.json" "$E7")"
check_reason "$out" "manifest_digest_mismatch" "T7: substituted manifest digest rejected"

# ── T8: covered-path content change -> trust_surface_changed ─────────────────
echo ""; echo "T8: covered-path content change"
R8="${FIXTURE_BASE}/t8"; build_pr_fixture "$R8"
printf 'guarded-TAMPERED' > "$R8/guarded.txt"
git -C "$R8" add guarded.txt
TAMPERED_TREE="$(git -C "$R8" write-tree)"
git -C "$R8" reset -q --mixed HEAD >/dev/null
T8_T="$(GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" \
  git -C "$R8" commit-tree "$TAMPERED_TREE" -p "$PR_B" -p "$PR_H" -m "tampered merge")"
T8_TREE="$(git -C "$R8" rev-parse "${T8_T}^{tree}")"
git -C "$R8" update-ref refs/heads/merge "$T8_T"
E8="${FIXTURE_BASE}/t8-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$T8_T" "$T8_TREE" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E8"
out="$(run_verify "$R8" "policy.json" "$E8")"
check_reason "$out" "trust_surface_changed" "T8: covered-path content change rejected"

# ── T9: covered-path mode-only change (byte-identical content) ───────────────
echo ""; echo "T9: covered-path mode-only change"
R9="${FIXTURE_BASE}/t9"; build_pr_fixture "$R9"
chmod +x "$R9/guarded.txt"
git -C "$R9" add guarded.txt
T9_TREE="$(git -C "$R9" write-tree)"
git -C "$R9" reset -q --mixed HEAD >/dev/null
T9_T="$(GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" \
  git -C "$R9" commit-tree "$T9_TREE" -p "$PR_B" -p "$PR_H" -m "mode-flip merge")"
git -C "$R9" update-ref refs/heads/merge "$T9_T"
E9="${FIXTURE_BASE}/t9-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$T9_T" "$(git -C "$R9" rev-parse "${T9_T}^{tree}")" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E9"
out="$(run_verify "$R9" "policy.json" "$E9")"
check_reason "$out" "trust_surface_changed" "T9: mode-only change on covered path rejected"

# ── T10: covered-path symlink flip ────────────────────────────────────────────
echo ""; echo "T10: covered-path symlink flip"
R10="${FIXTURE_BASE}/t10"; build_pr_fixture "$R10"
rm "$R10/guarded.txt"
ln -s other.txt "$R10/guarded.txt"
git -C "$R10" add guarded.txt
T10_TREE="$(git -C "$R10" write-tree)"
git -C "$R10" reset -q --mixed HEAD >/dev/null
T10_T="$(GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" \
  git -C "$R10" commit-tree "$T10_TREE" -p "$PR_B" -p "$PR_H" -m "symlink merge")"
git -C "$R10" update-ref refs/heads/merge "$T10_T"
E10="${FIXTURE_BASE}/t10-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$T10_T" "$(git -C "$R10" rev-parse "${T10_T}^{tree}")" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E10"
out="$(run_verify "$R10" "policy.json" "$E10")"
check_reason "$out" "trust_surface_changed" "T10: covered path replaced by symlink rejected"

# ── T11: covered-path rename away ─────────────────────────────────────────────
echo ""; echo "T11: covered-path renamed away"
R11="${FIXTURE_BASE}/t11"; build_pr_fixture "$R11"
git -C "$R11" rm -q guarded.txt
printf 'guarded-v1' > "$R11/guarded-renamed.txt"
git -C "$R11" add guarded-renamed.txt
T11_TREE="$(git -C "$R11" write-tree)"
git -C "$R11" reset -q --mixed HEAD >/dev/null
T11_T="$(GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" \
  git -C "$R11" commit-tree "$T11_TREE" -p "$PR_B" -p "$PR_H" -m "rename merge")"
git -C "$R11" update-ref refs/heads/merge "$T11_T"
E11="${FIXTURE_BASE}/t11-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$T11_T" "$(git -C "$R11" rev-parse "${T11_T}^{tree}")" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E11"
out="$(run_verify "$R11" "policy.json" "$E11")"
check_reason "$out" "trust_surface_changed" "T11: covered-path rename rejected"

# ── T13: run_attempt spliced across two CI attempts -> run_attempt_mismatch ──
echo ""; echo "T13: spliced run_attempt"
R13="${FIXTURE_BASE}/t13"; build_pr_fixture "$R13"
JOBS_SPLICED='[{"name":"job-a","conclusion":"success","run_attempt":1},{"name":"job-b","conclusion":"success"}]'
E13="${FIXTURE_BASE}/t13-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_SPLICED" 2 "$E13"
out="$(run_verify "$R13" "policy.json" "$E13")"
check_reason "$out" "run_attempt_mismatch" "T13: spliced-attempt evidence rejected"

# ── T14: duplicate required job -> job_duplicate ──────────────────────────────
echo ""; echo "T14: duplicate required job"
R14="${FIXTURE_BASE}/t14"; build_pr_fixture "$R14"
JOBS_DUP='[{"name":"job-a","conclusion":"success"},{"name":"job-a","conclusion":"success"},{"name":"job-b","conclusion":"success"}]'
E14="${FIXTURE_BASE}/t14-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_DUP" 1 "$E14"
out="$(run_verify "$R14" "policy.json" "$E14")"
check_reason "$out" "job_duplicate" "T14: duplicate required job rejected"

# ── T15: missing required job -> job_missing ──────────────────────────────────
echo ""; echo "T15: missing required job"
R15="${FIXTURE_BASE}/t15"; build_pr_fixture "$R15"
JOBS_MISSING='[{"name":"job-a","conclusion":"success"}]'
E15="${FIXTURE_BASE}/t15-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_MISSING" 1 "$E15"
out="$(run_verify "$R15" "policy.json" "$E15")"
check_reason "$out" "job_missing" "T15: missing required job rejected"

# ── T16: every non-success conclusion -> job_not_success ─────────────────────
echo ""; echo "T16: non-success conclusions"
for concl in skipped neutral cancelled timed_out action_required startup_failure stale failure; do
  R16="${FIXTURE_BASE}/t16-${concl}"; build_pr_fixture "$R16"
  jobs="$(jq -n --arg c "$concl" '[{name:"job-a",conclusion:$c},{name:"job-b",conclusion:"success"}]')"
  E16="${FIXTURE_BASE}/t16-${concl}-evidence.json"
  build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$jobs" 1 "$E16"
  out="$(run_verify "$R16" "policy.json" "$E16")"
  check_reason "$out" "job_not_success" "T16(${concl}): non-success conclusion rejected"
done

# ── T17: continue_on_error marker on a required job -> job_not_success ───────
echo ""; echo "T17: continue_on_error marker"
R17="${FIXTURE_BASE}/t17"; build_pr_fixture "$R17"
JOBS_COE='[{"name":"job-a","conclusion":"success","continue_on_error":true},{"name":"job-b","conclusion":"success"}]'
E17="${FIXTURE_BASE}/t17-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_COE" 1 "$E17"
out="$(run_verify "$R17" "policy.json" "$E17")"
check_reason "$out" "job_not_success" "T17: continue_on_error required job rejected"

# ── T18: extra non-required job (even failing) is ignored -> success ─────────
echo ""; echo "T18: extra non-required job ignored"
R18="${FIXTURE_BASE}/t18"; build_pr_fixture "$R18"
JOBS_EXTRA='[{"name":"job-a","conclusion":"success"},{"name":"job-b","conclusion":"success"},{"name":"lint","conclusion":"failure"}]'
E18="${FIXTURE_BASE}/t18-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_EXTRA" 1 "$E18"
out="$(run_verify "$R18" "policy.json" "$E18")"
check_success "$out" "T18: extra non-required failing job does not block"

# ── T19: identity/mode shape conflict -> identity_mode_conflict ──────────────
echo ""; echo "T19: identity/mode shape conflict"
R19="${FIXTURE_BASE}/t19"; build_pr_fixture "$R19"
E19="${FIXTURE_BASE}/t19-evidence.json"
jq -n --arg base "$PR_B" --arg head "$PR_H" --arg merge "$PR_T" --arg tree "$PR_TREE_T" \
      --arg digest "$PR_MANIFEST_DIGEST" --argjson jobs "$JOBS_OK" '{
  repository:"acme/example", mode:"merge_group",
  identity:{pr_number:42, base_ref:"base", head_ref:"candidate"},
  merge_ref:"merge",
  base_sha:$base, head_sha:$head, merge_sha:$merge, tree_sha:$tree,
  run:{workflow_path:".github/workflows/test-gate.yml", run_id:"1001", run_attempt:1, event:"merge_group"},
  manifest_digest:$digest, jobs:$jobs
}' > "$E19"
out="$(run_verify "$R19" "policy.json" "$E19")"
check_reason "$out" "identity_mode_conflict" "T19: mismatched identity shape for mode rejected"

# ── T20: unresolvable ref -> commit_unresolvable ──────────────────────────────
echo ""; echo "T20: unresolvable ref"
R20="${FIXTURE_BASE}/t20"; build_pr_fixture "$R20"
E20="${FIXTURE_BASE}/t20-evidence.json"
jq -n --arg base "$PR_B" --arg head "$PR_H" --arg tree "$PR_TREE_T" --arg digest "$PR_MANIFEST_DIGEST" --argjson jobs "$JOBS_OK" '{
  repository:"acme/example", mode:"pull_request",
  identity:{pr_number:42, base_ref:"base", head_ref:"candidate"},
  merge_ref:"does-not-exist-ref",
  base_sha:$base, head_sha:$head, merge_sha:"0000000000000000000000000000000000000000", tree_sha:$tree,
  run:{workflow_path:".github/workflows/test-gate.yml", run_id:"1001", run_attempt:1, event:"pull_request"},
  manifest_digest:$digest, jobs:$jobs
}' > "$E20"
out="$(run_verify "$R20" "policy.json" "$E20")"
check_reason "$out" "commit_unresolvable" "T20: unresolvable merge ref rejected"

# ── T21: evidence missing a required field -> schema_invalid ─────────────────
echo ""; echo "T21: evidence missing required field"
R21="${FIXTURE_BASE}/t21"; build_pr_fixture "$R21"
E21="${FIXTURE_BASE}/t21-evidence.json"
jq -n '{repository:"acme/example", mode:"pull_request"}' > "$E21"
out="$(run_verify "$R21" "policy.json" "$E21")"
check_reason "$out" "schema_invalid" "T21: evidence missing required fields rejected"

# ── T22: evidence is not valid JSON -> schema_invalid ─────────────────────────
echo ""; echo "T22: evidence is not valid JSON"
R22="${FIXTURE_BASE}/t22"; build_pr_fixture "$R22"
E22="${FIXTURE_BASE}/t22-evidence.json"
printf 'not { valid json' > "$E22"
out="$(run_verify "$R22" "policy.json" "$E22")"
check_reason "$out" "schema_invalid" "T22: malformed JSON evidence rejected"

# ── T23: jq unavailable -> environment_error ──────────────────────────────────
echo ""; echo "T23: jq unavailable"
R23="${FIXTURE_BASE}/t23"; build_pr_fixture "$R23"
E23="${FIXTURE_BASE}/t23-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E23"
NO_JQ_DIR="${FIXTURE_BASE}/no-jq-path"
mkdir -p "$NO_JQ_DIR"
for tool in git awk sha256sum shasum bash; do
  p="$(command -v "$tool" 2>/dev/null)" && ln -sf "$p" "$NO_JQ_DIR/$tool"
done
out="$(cd "$R23" && PATH="$NO_JQ_DIR" _premerge_verify "policy.json" "$E23")"
status="$(printf '%s' "$out" | grep -o '"status":"rejected"')"
reason="$(printf '%s' "$out" | grep -o '"reason":"environment_error"')"
if [[ -n "$status" && -n "$reason" ]]; then
  pass "T23: jq-unavailable environment_error"
else
  fail "T23: expected environment_error verdict, got: $out"
fi

# ── T24: canonical digest is reorder-stable and value-sensitive ──────────────
echo ""; echo "T24: canonical digest stability"
J1="${FIXTURE_BASE}/t24-a.json"; J2="${FIXTURE_BASE}/t24-b.json"; J3="${FIXTURE_BASE}/t24-c.json"
printf '{"b":2,"a":1}' > "$J1"
printf '{"a":1,"b":2}' > "$J2"
printf '{"a":1,"b":3}' > "$J3"
D1="$(_premerge_canonical_json "$J1" | _premerge_digest)"
D2="$(_premerge_canonical_json "$J2" | _premerge_digest)"
D3="$(_premerge_canonical_json "$J3" | _premerge_digest)"
[[ "$D1" == "$D2" ]] && pass "T24a: key-reordered identical JSON hashes identically" || fail "T24a: reordered JSON digest mismatch ($D1 vs $D2)"
[[ "$D1" != "$D3" ]] && pass "T24b: changed value hashes differently" || fail "T24b: changed-value JSON hashed identically"

# ── T25: manifest missing a required field -> schema_invalid (unit-level) ────
echo ""; echo "T25: manifest missing required field"
M25="${FIXTURE_BASE}/t25-manifest.json"
jq -n '{schema_version:"1.0.0", policy_version:"1", digest_algorithm:"sha256",
        workflow:{path:"x",name:"y"}, covered_paths:["a"], validation_profile:"standard"}' > "$M25"
_premerge_load_manifest "$M25" >/dev/null 2>&1
rc=$?
if [[ $rc -ne 0 && "$_PREMERGE_REASON" == "schema_invalid" ]]; then
  pass "T25: manifest missing required_jobs rejected as schema_invalid"
else
  fail "T25: expected schema_invalid, got rc=$rc reason=${_PREMERGE_REASON:-}"
fi

echo ""
echo "════════════════════════════════════════"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "════════════════════════════════════════"
[[ $FAIL_COUNT -eq 0 ]]
