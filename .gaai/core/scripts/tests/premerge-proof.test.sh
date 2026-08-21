#!/usr/bin/env bash
# premerge-proof.test.sh — hermetic regression suite for lib/premerge-proof.sh
#
# Scenario map. The "Generation" column records whether a scenario belongs to
# the initial contract or its corrective hardening, so the original coverage
# stays identifiable after provenance/schema/portability corrections.
#
#   Tn   Generation  AC          Scenario
#   T0   initial     AC1         shipped template validates against the shipped schema
#   T1   initial     AC1/2/4/5/6 valid pull_request fixture -> success
#   T2   initial     AC2/6       valid merge_group fixture -> success
#   T3   initial     AC2/6       swapped parents (H,B) -> parent_mismatch
#   T4   initial     AC2/6       stale/forged base claim -> tuple_forged
#   T5   initial     AC2/6       forged head claim (replayed) -> tuple_forged
#   T6   initial     AC2/6       forged tree claim -> tree_mismatch
#   T7   initial     AC1/6       manifest substitution -> manifest_digest_mismatch
#   T8   initial     AC3/6       covered-path content change -> trust_surface_changed
#   T9   initial     AC3         covered-path mode-only change -> trust_surface_changed
#   T10  initial     AC3         covered-path symlink flip -> trust_surface_changed
#   T11  initial     AC3         covered-path rename (delete+add) -> trust_surface_changed
#   T12  initial     AC3         uncovered-path change ignored -> success (folded into T1)
#   T13  initial     AC6         run_attempt spliced across jobs -> run_attempt_mismatch
#   T14  initial     AC5/6       duplicate required job -> job_duplicate
#   T15  initial     AC5/6       missing required job -> job_missing
#   T16  initial     AC5/6       every non-success conclusion -> job_not_success
#   T17  initial     AC5         continue_on_error on a required job -> job_not_success
#   T18  initial     AC5         extra non-required job ignored -> success
#   T19  initial     AC2         identity/mode shape conflict -> identity_mode_conflict
#   T20  initial     AC2/4       unresolvable merge ref -> commit_unresolvable
#   T21  initial     AC4         evidence missing a required field -> schema_invalid
#   T22  initial     AC4         evidence is not valid JSON -> schema_invalid
#   T23  initial     AC1/4       jq unavailable -> environment_error
#   T24  initial     AC1         canonical digest: reorder-stable, value-sensitive
#   T25  initial     AC1         manifest missing a required field -> schema_invalid
#   T26  initial     AC4         unrecognized top-level evidence field -> schema_invalid
#   T27  correction  AC1         evidence missing validation_profile -> schema_invalid
#   T28  correction  AC1         schema-to-runtime drift: every required evidence key
#   T29  correction  AC1         schema-to-runtime drift: every required manifest key
#   T30  correction  AC1         wrong-type / empty / zero-attempt values -> schema_invalid
#   T31  correction  AC1         published uniqueItems violation vs evidence job_duplicate
#   T32  correction  AC1/4       unsafe covered-path forms -> schema_invalid
#   T33  correction  AC1         GAAI_PREMERGE_SCHEMA_PATH cannot redirect verification
#   T34  correction  AC1/6       a T-held (candidate) schema never weakens verification
#   T35  correction  AC1/6       the working-tree manifest is never read
#   T36  correction  AC2         missing run.workflow_name -> schema_invalid
#   T37  correction  AC2         workflow path/name disagreement -> provenance_mismatch
#   T38  correction  AC2         validation_profile disagreement -> provenance_mismatch
#   T39  correction  AC2         event/mode disagreement -> provenance_mismatch
#   T40  correction  AC2         reason enum registration + priority-order agreement
#   T41  correction  AC2         repository is carried, not bound (assigned downstream)
#   T42  correction  AC3         every emitted verdict conforms to the verdict schema
#   T43  correction  AC3         success forbids reason; rejection requires one
#   T44  correction  AC3         declared dialect supports every keyword used
#   T45  correction  AC4         default policy covers exactly the existing surfaces
#   T46  correction  AC4/5       covered path matching nothing at B -> policy_missing
#   T47  correction  AC5         dependency matrix -> environment_error, never empty digest
#   T48  correction  AC5         schema or manifest unobtainable at B -> stable reason
#   T49  correction  AC5         Git failure and caller-cwd independence
#   T50  correction  AC5         truncated manifest-derived iteration -> environment_error
#   T51  correction  AC6         static Bash 3.2 construct assertion over production code
#   T52  correction  AC6         real Bash 3.2 execution when a 3.2 interpreter exists
#   T53  correction  AC6         no gh/curl/network primitive in production code
#   T54  correction  AC6         verification mutates nothing in the repository
#   T55  local-first AC6         resolver's hermetic Node matrix is part of the OSS corpus
set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
VERDICTS_CHECKED=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo "  SKIP: $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_PATH="${SCRIPT_DIR}/lib/premerge-proof.sh"
# shellcheck source=../lib/premerge-proof.sh
source "$LIB_PATH"
TEMPLATE_PATH="${SCRIPT_DIR}/../templates/ci/premerge-policy.json"
SCHEMA_PATH="${SCRIPT_DIR}/../ci/premerge-policy.schema.json"
SCHEMA_REPO_PATH=".gaai/core/ci/premerge-policy.schema.json"

FIXTURE_BASE="/tmp/gaai-premerge-proof-test-$$"
RESTRICTED_STDERR="${FIXTURE_BASE}/restricted-path.stderr"
trap 'rm -rf "$FIXTURE_BASE"' EXIT
mkdir -p "$FIXTURE_BASE"

# The canonical contract, restated here independently of the runtime so a
# silent narrowing of either the schema or the library is a test failure and
# not a coincidence of both drifting together.
CANONICAL_EVIDENCE_KEYS='["repository","mode","identity","merge_ref","base_sha","head_sha","merge_sha","tree_sha","run","manifest_digest","validation_profile","jobs"]'
CANONICAL_PRIORITY_ORDER='environment_error, schema_invalid, identity_mode_conflict, commit_unresolvable, parent_mismatch, tuple_forged, tree_mismatch, manifest_digest_mismatch, provenance_mismatch, policy_missing, trust_surface_changed, run_attempt_mismatch, job_missing, job_duplicate, job_not_success'
CANONICAL_TRUST_SURFACES='[".gaai/core/ci/premerge-policy.schema.json",".gaai/core/templates/ci/premerge-policy.json",".gaai/core/scripts/lib/premerge-proof.sh",".gaai/core/scripts/lib/local-admission-resolver.mjs"]'

# Key sets + closed reason list read from the shipped schema, used by the
# fail-closed verdict predicate below. Always available; a real JSON-Schema
# validator is used additionally when one is installed (T44).
VK="$(jq -c '
  def ks($d): { required: (.["$defs"][$d].required // []),
                allowed: ((.["$defs"][$d].properties // {}) | keys) };
  { verdict: ks("verdict"), run: ks("run_identity"), job: ks("job_result"),
    pr: ks("pull_request_identity"), mg: ks("merge_group_identity"),
    manifest: ks("trust_manifest"), evidence: ks("evidence"),
    reasons: (.["$defs"].reason_enum.enum) }' "$SCHEMA_PATH")"

# Fail-closed runtime implementation of premerge-policy.schema.json#/$defs/verdict.
verdict_conforms() {
  jq -e --argjson k "$VK" '
    def str: type == "string" and length > 0;
    def posint: type == "number" and . == floor and . >= 1;
    def keyset($s): (($s.required - keys) == []) and ((keys - $s.allowed) == []);
    def nullable_str: (. == null) or str;
    (type == "object") and keyset($k.verdict)
    and (.schema_version | str)
    and (.repository | nullable_str) and (.manifest_digest | nullable_str)
    and (.validation_profile | nullable_str)
    and ([.base_sha, .head_sha, .merge_sha, .tree_sha] | all(nullable_str))
    and ((.mode == null) or (.mode == "pull_request") or (.mode == "merge_group"))
    and ((.identity == null) or (.identity | (type == "object")
          and ((keyset($k.pr) and (.pr_number | posint) and (.base_ref | str) and (.head_ref | str))
               or (keyset($k.mg) and (.merge_group_ref | str) and (.base_ref | str)))))
    and ((.run == null) or (.run | (type == "object") and keyset($k.run)
          and ([.workflow_path, .workflow_name, .run_id, .event] | all(str))
          and (.run_attempt | posint)))
    and ((.jobs == null) or (((.jobs | type) == "array")
          and (.jobs | all((type == "object") and keyset($k.job)
                and (.name | str) and (.conclusion | str)
                and ((has("continue_on_error") | not) or (.continue_on_error | type == "boolean"))
                and ((has("run_attempt") | not) or (.run_attempt | posint))))))
    and (.result | (type == "object") and ((keys - ["status", "reason"]) == []) and has("status")
          and (((.status == "success") and (has("reason") | not))
               or ((.status == "rejected") and (.reason | str)
                   and (.reason as $r | ($k.reasons | index($r)) != null))))
  ' <<<"$1" >/dev/null 2>&1
}

# Every verdict any scenario produces is checked against the verdict schema
# (T42): conformance is a property of every path, not of the happy path.
assert_verdict() {
  local out="$1" label="$2"
  VERDICTS_CHECKED=$((VERDICTS_CHECKED + 1))
  verdict_conforms "$out" || fail "$label: emitted verdict violates \$defs/verdict — $out"
}

check_reason() {
  local out="$1" expected="$2" label="$3" status reason
  status="$(jq -r '.result.status' <<<"$out" 2>/dev/null)"
  reason="$(jq -r '.result.reason // empty' <<<"$out" 2>/dev/null)"
  if [[ "$status" == "rejected" && "$reason" == "$expected" ]]; then
    pass "$label (reason=$expected)"
  else
    fail "$label (expected reason=$expected, got status=$status reason=$reason)"
  fi
  assert_verdict "$out" "$label"
}
check_success() {
  local out="$1" label="$2" status
  status="$(jq -r '.result.status' <<<"$out" 2>/dev/null)"
  [[ "$status" == "success" ]] && pass "$label" || fail "$label (expected success, got: $out)"
  assert_verdict "$out" "$label"
}
manifest_rejects_as() {  # <manifest-path> <reason>
  local manifest_path="$1" expected="$2" rc
  _PREMERGE_REASON=""
  _premerge_load_manifest "$manifest_path" >/dev/null 2>&1; rc=$?
  [[ $rc -ne 0 && "$_PREMERGE_REASON" == "$expected" ]]
}

setup_repo() {
  rm -rf "$1"; mkdir -p "$1"
  git init -q "$1"
  git -C "$1" config user.email "test@gaai.local"
  git -C "$1" config user.name "GAAI Test"
  git -C "$1" config core.hooksPath /dev/null
  # The verifier resolves its contract from B at the canonical repository
  # path, so every fixture repository carries the real shipped schema there.
  mkdir -p "$1/$(dirname "$SCHEMA_REPO_PATH")"
  cp "$SCHEMA_PATH" "$1/$SCHEMA_REPO_PATH"
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
    run:{workflow_path:".github/workflows/test-gate.yml", workflow_name:"Test Gate",
         run_id:"1001", run_attempt:$attempt, event:"pull_request"},
    manifest_digest:$digest, validation_profile:"standard", jobs:$jobs
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
    run:{workflow_path:".github/workflows/test-gate.yml", workflow_name:"Test Gate",
         run_id:"2001", run_attempt:$attempt, event:"merge_group"},
    manifest_digest:$digest, validation_profile:"standard", jobs:$jobs
  }' > "$out"
}

# A restricted PATH containing exactly the named tools, for the fail-closed
# dependency scenarios.
make_path_dir() {
  local dir="$1"; shift
  local tool resolved
  rm -rf "$dir"; mkdir -p "$dir"
  for tool in "$@"; do
    resolved="$(command -v "$tool" 2>/dev/null)" && ln -sf "$resolved" "$dir/$tool"
  done
}
# Restricted-PATH scenarios must run in a fresh interpreter: Bash 3.2 does not
# invalidate its command hash when PATH changes, so a tool already run by an
# earlier scenario would still resolve inside this one and the scenario would
# silently test nothing.
TEST_SHELL="${BASH:-/bin/bash}"
verify_with_path() {  # <path-dir> <repo> <manifest-repo-path> <evidence-file>
  : > "$RESTRICTED_STDERR"
  ( cd "$2" && PATH="$1" "$TEST_SHELL" -c 'source "$1"; _premerge_verify "$2" "$3"' \
      _ "$LIB_PATH" "$3" "$4" ) 2>"$RESTRICTED_STDERR"
}

# Production code with whole-line and trailing comments stripped, so a
# construct named in prose is never mistaken for a construct that is used.
production_code() {
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#[[:space:]].*$//' "$LIB_PATH"
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
  run:{workflow_path:".github/workflows/test-gate.yml", workflow_name:"Test Gate",
       run_id:"1001", run_attempt:1, event:"merge_group"},
  manifest_digest:$digest, validation_profile:"standard", jobs:$jobs
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
  run:{workflow_path:".github/workflows/test-gate.yml", workflow_name:"Test Gate",
       run_id:"1001", run_attempt:1, event:"pull_request"},
  manifest_digest:$digest, validation_profile:"standard", jobs:$jobs
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
make_path_dir "$NO_JQ_DIR" git awk sha256sum shasum bash mktemp rm
out="$(verify_with_path "$NO_JQ_DIR" "$R23" "policy.json" "$E23")"
status="$(printf '%s' "$out" | grep -o '"status":"rejected"')"
reason="$(printf '%s' "$out" | grep -o '"reason":"environment_error"')"
if [[ -n "$status" && -n "$reason" ]]; then
  pass "T23: jq-unavailable environment_error"
else
  fail "T23: expected environment_error verdict, got: $out"
fi
assert_verdict "$out" "T23"
[[ ! -s "$RESTRICTED_STDERR" ]] && pass "T23b: missing jq emits no raw shell error" \
  || fail "T23b: missing jq leaked stderr: $(tr '\n' ' ' < "$RESTRICTED_STDERR")"

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
if manifest_rejects_as "$M25" schema_invalid; then
  pass "T25: manifest missing required_jobs rejected as schema_invalid"
else
  fail "T25: expected schema_invalid, got reason=${_PREMERGE_REASON:-}"
fi
_premerge_load_manifest "$TEMPLATE_PATH" >/dev/null 2>&1; rc=$?
[[ $rc -eq 0 && -z "$_PREMERGE_REASON" ]] \
  && pass "T25b: successful manifest validation clears an earlier reason" \
  || fail "T25b: success retained stale reason=${_PREMERGE_REASON:-none}"

# ── T26: evidence with an unrecognized top-level field -> schema_invalid ─────
echo ""; echo "T26: evidence carries an unrecognized top-level field"
R26="${FIXTURE_BASE}/t26"; build_pr_fixture "$R26"
E26_BASE="${FIXTURE_BASE}/t26-base-evidence.json"
E26="${FIXTURE_BASE}/t26-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E26_BASE"
jq '. + {"malicious_extra": {"inject":"whatever"}}' "$E26_BASE" > "$E26"
out="$(run_verify "$R26" "policy.json" "$E26")"
check_reason "$out" "schema_invalid" "T26: unrecognized evidence field rejected"
# Sanity: the identical evidence minus the extra field still succeeds, proving
# the rejection above is caused by the injected key, not by fixture drift.
out_baseline="$(run_verify "$R26" "policy.json" "$E26_BASE")"
check_success "$out_baseline" "T26 baseline: same evidence without the extra field succeeds"

# ═══ Corrective scenarios: provenance, exhaustive schema, portability ════════
# One shared valid fixture reused by the mutation-driven scenarios below.
RS="${FIXTURE_BASE}/correction"; build_pr_fixture "$RS"
ES_OK="${FIXTURE_BASE}/correction-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$ES_OK"
CORR_B="$PR_B"; CORR_H="$PR_H"; CORR_T="$PR_T"; CORR_TREE="$PR_TREE_T"; CORR_DIGEST="$PR_MANIFEST_DIGEST"

# Applies a jq mutation to the known-good evidence and verifies the result.
verify_mutated() {  # <jq-filter> -> prints verdict
  local mutated="${FIXTURE_BASE}/correction-mutated.json"
  jq "$1" "$ES_OK" > "$mutated"
  run_verify "$RS" "policy.json" "$mutated"
}

# ── T27: evidence missing validation_profile -> schema_invalid ───────────────
echo ""; echo "T27: evidence missing validation_profile"
out="$(verify_mutated 'del(.validation_profile)')"
check_reason "$out" "schema_invalid" "T27: validation_profile is a required evidence key"

# ── T28: schema-to-runtime drift, evidence ───────────────────────────────────
echo ""; echo "T28: every schema-required evidence key is enforced at runtime"
if [[ "$(jq -c '.["$defs"].evidence.required' "$SCHEMA_PATH")" == "$CANONICAL_EVIDENCE_KEYS" ]]; then
  pass "T28a: schema publishes exactly the canonical required evidence keys"
else
  fail "T28a: schema evidence.required drifted from the canonical set"
fi
t28_bad=0
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  out="$(verify_mutated "del(.\"${key}\")")"
  [[ "$(jq -r '.result.reason // empty' <<<"$out")" == "schema_invalid" ]] || {
    t28_bad=$((t28_bad + 1)); echo "    (removing ${key} did not yield schema_invalid)"; }
  assert_verdict "$out" "T28(${key})"
done < <(jq -r '.["$defs"].evidence.required[]' "$SCHEMA_PATH")
[[ $t28_bad -eq 0 ]] && pass "T28b: removing any schema-required evidence key -> schema_invalid" \
  || fail "T28b: ${t28_bad} schema-required evidence key(s) unenforced at runtime"

# ── T29: schema-to-runtime drift, manifest ───────────────────────────────────
echo ""; echo "T29: every schema-required manifest key is enforced at runtime"
M29_OK="${FIXTURE_BASE}/t29-manifest.json"
make_manifest '["a"]' '["j"]' > "$M29_OK"
t29_bad=0
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  jq "del(.\"${key}\")" "$M29_OK" > "${FIXTURE_BASE}/t29-mutated.json"
  manifest_rejects_as "${FIXTURE_BASE}/t29-mutated.json" schema_invalid || {
    t29_bad=$((t29_bad + 1)); echo "    (removing ${key} did not yield schema_invalid)"; }
done < <(jq -r '.["$defs"].trust_manifest.required[]' "$SCHEMA_PATH")
[[ $t29_bad -eq 0 ]] && pass "T29: removing any schema-required manifest key -> schema_invalid" \
  || fail "T29: ${t29_bad} schema-required manifest key(s) unenforced at runtime"

# ── T30: wrong-type / empty / zero-attempt values -> schema_invalid ──────────
echo ""; echo "T30: invalid, empty, wrong-type and zero-attempt values"
for mutation in \
  '.base_sha = ""' \
  '.repository = 7' \
  '.run.run_attempt = 0' \
  '.run.run_attempt = 1.5' \
  '.run.run_id = ""' \
  '.run.extra_field = "x"' \
  '.jobs = "not-an-array"' \
  '.jobs[0].name = ""' \
  '.jobs[0].continue_on_error = "true"' \
  '.jobs[0].unexpected = 1' \
  '.identity = {"unexpected":"shape"}' \
  '.identity.pr_number = 0' \
  '.mode = "push"' \
  '.x_extensions = "not-an-object"' \
; do
  out="$(verify_mutated "$mutation")"
  check_reason "$out" "schema_invalid" "T30 ($mutation)"
done

# ── T31: published uniqueItems violation vs evidence job duplication ─────────
echo ""; echo "T31: uniqueItems is schema_invalid, evidence job duplication is job_duplicate"
M31="${FIXTURE_BASE}/t31-manifest.json"
make_manifest '["a","a"]' '["j"]' > "$M31"
manifest_rejects_as "$M31" schema_invalid && pass "T31a: duplicate covered_paths -> schema_invalid" \
  || fail "T31a: duplicate covered_paths gave ${_PREMERGE_REASON:-none}"
make_manifest '["a"]' '["j","j"]' > "$M31"
manifest_rejects_as "$M31" schema_invalid && pass "T31b: duplicate required_jobs -> schema_invalid" \
  || fail "T31b: duplicate required_jobs gave ${_PREMERGE_REASON:-none}"
# The distinction the contract requires: duplication in untrusted run evidence
# stays job_duplicate and never collapses into the document-level reason (T14).

# ── T32: unsafe covered-path forms -> schema_invalid ─────────────────────────
echo ""; echo "T32: unsafe covered-path forms"
t32_bad=0
while IFS= read -r bad_path_json; do
  [[ -z "$bad_path_json" ]] && continue
  jq -n --argjson p "[$bad_path_json]" --argjson rj '["j"]' '{
    schema_version:"1.0.0", policy_version:"1", digest_algorithm:"sha256",
    workflow:{path:"w", name:"n"}, covered_paths:$p, required_jobs:$rj,
    validation_profile:"standard" }' > "${FIXTURE_BASE}/t32-manifest.json"
  manifest_rejects_as "${FIXTURE_BASE}/t32-manifest.json" schema_invalid || {
    t32_bad=$((t32_bad + 1)); echo "    (accepted unsafe covered path ${bad_path_json})"; }
done <<'UNSAFE'
"/etc/passwd"
"../outside"
"a/../../outside"
".."
"."
"./guarded"
".//guarded"
"a/./guarded"
"a//guarded"
"a/"
":(glob)**/x"
":!excluded"
"src/*.sh"
"weird?name"
"bracket[0]"
""
UNSAFE
jq -n '["a\nb"]' > "${FIXTURE_BASE}/t32-nl.json"
jq -n --argjson p "$(cat "${FIXTURE_BASE}/t32-nl.json")" '{
  schema_version:"1.0.0", policy_version:"1", digest_algorithm:"sha256",
  workflow:{path:"w", name:"n"}, covered_paths:$p, required_jobs:["j"],
  validation_profile:"standard" }' > "${FIXTURE_BASE}/t32-manifest.json"
manifest_rejects_as "${FIXTURE_BASE}/t32-manifest.json" schema_invalid || t32_bad=$((t32_bad + 1))
jq -n '["a\u0000b"]' > "${FIXTURE_BASE}/t32-nul.json"
jq -n --argjson p "$(cat "${FIXTURE_BASE}/t32-nul.json")" '{
  schema_version:"1.0.0", policy_version:"1", digest_algorithm:"sha256",
  workflow:{path:"w", name:"n"}, covered_paths:$p, required_jobs:["j"],
  validation_profile:"standard" }' > "${FIXTURE_BASE}/t32-manifest.json"
manifest_rejects_as "${FIXTURE_BASE}/t32-manifest.json" schema_invalid || t32_bad=$((t32_bad + 1))
[[ $t32_bad -eq 0 ]] && pass "T32: non-canonical, parent, magic, glob, empty, newline and NUL paths rejected" \
  || fail "T32: ${t32_bad} unsafe covered-path form(s) accepted"

# ── T33: GAAI_PREMERGE_SCHEMA_PATH cannot redirect production verification ───
echo ""; echo "T33: the schema override cannot redirect _premerge_verify"
PERMISSIVE_SCHEMA="${FIXTURE_BASE}/t33-permissive.json"
jq '.["$defs"].evidence.required = [] | .["$defs"].evidence.additionalProperties = true
    | .["$defs"].trust_manifest.required = []' "$SCHEMA_PATH" > "$PERMISSIVE_SCHEMA"
E33="${FIXTURE_BASE}/t33-evidence.json"
jq '. + {"malicious_extra":1}' "$ES_OK" > "$E33"
out="$(cd "$RS" && GAAI_PREMERGE_SCHEMA_PATH="$PERMISSIVE_SCHEMA" \
  bash -c 'source "$1"; _premerge_verify "$2" "$3"' _ "$LIB_PATH" "policy.json" "$E33")"
check_reason "$out" "schema_invalid" "T33a: override cannot loosen the contract"
out="$(cd "$RS" && GAAI_PREMERGE_SCHEMA_PATH=/nonexistent/schema.json \
  bash -c 'source "$1"; _premerge_verify "$2" "$3"' _ "$LIB_PATH" "policy.json" "$ES_OK")"
check_success "$out" "T33b: a broken override does not break verification"

# ── T34: a T-held (candidate) schema never weakens verification ──────────────
echo ""; echo "T34: the candidate's own schema copy is never consulted"
R34="${FIXTURE_BASE}/t34"; build_pr_fixture "$R34"
cp "$PERMISSIVE_SCHEMA" "$R34/$SCHEMA_REPO_PATH"
git -C "$R34" add "$SCHEMA_REPO_PATH"
T34_TREE="$(git -C "$R34" write-tree)"
git -C "$R34" reset -q --mixed HEAD >/dev/null
T34_T="$(GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" \
  git -C "$R34" commit-tree "$T34_TREE" -p "$PR_B" -p "$PR_H" -m "weakened-schema merge")"
git -C "$R34" update-ref refs/heads/merge "$T34_T"
E34="${FIXTURE_BASE}/t34-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$T34_T" "$(git -C "$R34" rev-parse "${T34_T}^{tree}")" \
  "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "${FIXTURE_BASE}/t34-base.json"
jq '. + {"malicious_extra":1}' "${FIXTURE_BASE}/t34-base.json" > "$E34"
out="$(run_verify "$R34" "policy.json" "$E34")"
check_reason "$out" "schema_invalid" "T34: B-held schema governs even when T ships a permissive one"

# ── T35: the working-tree manifest is never read ─────────────────────────────
echo ""; echo "T35: the working-tree manifest is never read"
R35="${FIXTURE_BASE}/t35"; build_pr_fixture "$R35"
E35="${FIXTURE_BASE}/t35-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E35"
make_manifest '["policy.json"]' '["job-nonexistent"]' > "$R35/policy.json"
out="$(run_verify "$R35" "policy.json" "$E35")"
check_success "$out" "T35: an uncommitted manifest rewrite cannot change the verdict"

# ── T36: missing run.workflow_name -> schema_invalid ─────────────────────────
echo ""; echo "T36: run provenance fields are required"
out="$(verify_mutated 'del(.run.workflow_name)')"
check_reason "$out" "schema_invalid" "T36a: workflow_name is required"
out="$(verify_mutated 'del(.run.event)')"
check_reason "$out" "schema_invalid" "T36b: event is required"
out="$(verify_mutated 'del(.run.run_attempt)')"
check_reason "$out" "schema_invalid" "T36c: run_attempt is required"
out="$(verify_mutated 'del(.run.run_id)')"
check_reason "$out" "schema_invalid" "T36d: run_id is required"

# ── T37/T38/T39: provenance disagreement -> provenance_mismatch ──────────────
echo ""; echo "T37-T39: run provenance is bound to the base-held manifest"
out="$(verify_mutated '.run.workflow_path = ".github/workflows/attacker.yml"')"
check_reason "$out" "provenance_mismatch" "T37a: workflow path disagreement"
out="$(verify_mutated '.run.workflow_name = "Some Other Workflow"')"
check_reason "$out" "provenance_mismatch" "T37b: workflow name disagreement"
out="$(verify_mutated '.validation_profile = "weak"')"
check_reason "$out" "provenance_mismatch" "T38: validation_profile disagreement"
out="$(verify_mutated '.run.event = "push"')"
check_reason "$out" "provenance_mismatch" "T39a: pull_request mode requires event pull_request"
R39="${FIXTURE_BASE}/t39"; build_mg_fixture "$R39"
E39="${FIXTURE_BASE}/t39-evidence.json"
build_evidence_mg "$MG_B" "$MG_T" "$MG_TREE_T" "$MG_MANIFEST_DIGEST" "$JOBS_OK_MG" 1 "${FIXTURE_BASE}/t39-base.json"
jq '.run.event = "pull_request"' "${FIXTURE_BASE}/t39-base.json" > "$E39"
out="$(run_verify "$R39" "policy.json" "$E39")"
check_reason "$out" "provenance_mismatch" "T39b: merge_group mode requires event merge_group"

# ── T40: reason registration + priority-order agreement ──────────────────────
echo ""; echo "T40: reason enum registration and priority-order agreement"
for reason in provenance_mismatch policy_missing; do
  jq -e --arg r "$reason" '.["$defs"].reason_enum.enum | index($r) != null' "$SCHEMA_PATH" >/dev/null 2>&1 \
    && pass "T40a: ${reason} registered in the closed enum" \
    || fail "T40a: ${reason} missing from the closed enum"
done
schema_order="$(jq -r '.["$defs"].reason_enum.description' "$SCHEMA_PATH" | sed -n 's/.*PRIORITY_ORDER: //p')"
lib_order="$(sed -n 's/^# PRIORITY_ORDER: //p' "$LIB_PATH")"
[[ -n "$schema_order" && "$schema_order" == "$lib_order" ]] \
  && pass "T40b: schema description and library header declare the same order" \
  || fail "T40b: priority-order marker mismatch (schema='$schema_order' lib='$lib_order')"
[[ "$lib_order" == "$CANONICAL_PRIORITY_ORDER" ]] \
  && pass "T40c: declared order equals the canonical order" \
  || fail "T40c: declared order drifted from the canonical order"
declared_set="$(printf '%s' "$lib_order" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort | tr '\n' ' ')"
enum_set="$(jq -r '.["$defs"].reason_enum.enum[]' "$SCHEMA_PATH" | sort | tr '\n' ' ')"
[[ "$declared_set" == "$enum_set" ]] \
  && pass "T40d: the declared order covers exactly the closed enum" \
  || fail "T40d: declared order and enum members differ"
out="$(verify_mutated '.jobs = [
  {name:"job-a",conclusion:"success"}, {name:"job-a",conclusion:"success"}
]')"
check_reason "$out" "job_missing" "T40e: job_missing outranks a simultaneous job_duplicate"
out="$(verify_mutated '.jobs = [{name:"job-a",conclusion:"failure"}]')"
check_reason "$out" "job_missing" "T40f: job_missing outranks a simultaneous job_not_success"
out="$(verify_mutated '.jobs = [
  {name:"job-a",conclusion:"success"}, {name:"job-a",conclusion:"success"},
  {name:"job-b",conclusion:"failure"}
]')"
check_reason "$out" "job_duplicate" "T40g: job_duplicate outranks a simultaneous job_not_success"

# ── T41: repository is carried, not bound here ───────────────────────────────
echo ""; echo "T41: repository binding is assigned downstream, not claimed here"
out="$(verify_mutated '.repository = "someone-else/another-repo"')"
check_success "$out" "T41: an unrelated repository value is carried, not verified (downstream gate owns it)"
[[ "$(jq -r '.repository' <<<"$out")" == "someone-else/another-repo" ]] \
  && pass "T41b: the verdict carries the claimed repository verbatim" \
  || fail "T41b: the verdict did not carry the claimed repository"
jq -e '
  .["$defs"].pull_request_identity.properties.base_ref.description
    | contains("merge-authorization layer")' "$SCHEMA_PATH" >/dev/null 2>&1 \
  && grep -q 'base_ref, which selects the trust root' "$LIB_PATH" \
  && pass "T41c: untrusted base_ref selection is explicitly handed to merge authorization" \
  || fail "T41c: base_ref trust-root hand-off is undocumented"

# ── T42/T43: verdict conformance on success and on every rejection path ──────
echo ""; echo "T42-T43: verdict schema conformance"
[[ $VERDICTS_CHECKED -gt 0 ]] \
  && pass "T42: ${VERDICTS_CHECKED} emitted verdicts checked against \$defs/verdict so far" \
  || fail "T42: no verdict was checked"
out="$(run_verify "$RS" "policy.json" "$ES_OK")"
jq -e '.result.status == "success" and (.result | has("reason") | not)' <<<"$out" >/dev/null 2>&1 \
  && pass "T43a: a success verdict carries no reason" || fail "T43a: success verdict carried a reason"
verdict_conforms "$(jq '.result.reason = "job_missing"' <<<"$out")" \
  && fail "T43b: a success verdict carrying a reason was accepted" \
  || pass "T43b: reason on success is rejected by the verdict contract"
verdict_conforms "$(jq '.result = {status:"rejected"}' <<<"$out")" \
  && fail "T43c: a rejected verdict without a reason was accepted" \
  || pass "T43c: rejection without a reason is rejected by the verdict contract"
verdict_conforms "$(jq '.jobs = [{name:"job-a",conclusion:"success",run_attempt:3}]' <<<"$out")" \
  && pass "T43d: jobs[].run_attempt is accepted by the verdict contract" \
  || fail "T43d: jobs[].run_attempt is not accepted by the verdict contract"
out="$(_premerge_reject '' '' '' '')"
check_reason "$out" "environment_error" "T43e: a rejection helper can never emit success from an empty reason"

# ── T44: declared dialect supports every keyword used ────────────────────────
echo ""; echo "T44: declared JSON-Schema dialect"
dialect="$(jq -r '.["$schema"]' "$SCHEMA_PATH")"
case "$dialect" in
  *json-schema.org/draft/2020-12/schema*) pass "T44a: declared dialect is 2020-12, which defines \$defs, if/then/else, const, uniqueItems, minLength" ;;
  *draft-07*) jq -e 'has("$defs") | not' "$SCHEMA_PATH" >/dev/null 2>&1 \
      && pass "T44a: draft-07 declared and \$defs unused" \
      || fail "T44a: draft-07 declared but \$defs (2019-09+) used" ;;
  *) fail "T44a: unrecognized declared dialect '$dialect'" ;;
esac
# In 2020-12 `items` is the single-schema form only; a tuple-form array here
# would silently mean something else than intended.
jq -e '[.. | objects | select(has("items")) | .items | arrays] | length == 0' "$SCHEMA_PATH" >/dev/null 2>&1 \
  && pass "T44b: no tuple-form items (single-schema form only)" \
  || fail "T44b: tuple-form items found, which 2020-12 spells prefixItems"
VALIDATOR=""
if command -v check-jsonschema >/dev/null 2>&1; then VALIDATOR="check-jsonschema"
elif command -v ajv >/dev/null 2>&1; then VALIDATOR="ajv"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1; then VALIDATOR="python-jsonschema"
fi
if [[ -n "$VALIDATOR" ]]; then
  V_OK=0
  case "$VALIDATOR" in
    check-jsonschema)
      check-jsonschema --schemafile "$SCHEMA_PATH" "$TEMPLATE_PATH" >/dev/null 2>&1 && V_OK=1 ;;
    ajv)
      ajv validate -s "$SCHEMA_PATH" -d "$TEMPLATE_PATH" >/dev/null 2>&1 && V_OK=1 ;;
    python-jsonschema)
      python3 - "$SCHEMA_PATH" "$TEMPLATE_PATH" >/dev/null 2>&1 <<'PY' && V_OK=1
import copy, json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
instance = json.load(open(sys.argv[2]))
manifest_schema = {"$schema": schema["$schema"], "$defs": schema["$defs"],
                   "$ref": "#/$defs/trust_manifest"}
jsonschema.validate(instance, manifest_schema)
validator = jsonschema.Draft202012Validator(manifest_schema)
for bad_path in ["./guarded", ".//guarded", "a/./guarded", "a//guarded", "a/", ".", ".."]:
    invalid = copy.deepcopy(instance)
    invalid["covered_paths"] = [bad_path]
    assert list(validator.iter_errors(invalid)), bad_path
PY
      ;;
  esac
  [[ $V_OK -eq 1 ]] && pass "T44c: shipped template validates under ${VALIDATOR}" \
    || fail "T44c: shipped template failed validation under ${VALIDATOR}"
else
  skip "T44c: no JSON-Schema validator installed; fail-closed runtime predicates still ran"
fi

# ── T45: default policy covers exactly the existing trust surfaces ───────────
echo ""; echo "T45: default policy trust surface and forward-declared workflow identity"
[[ "$(jq -c '.covered_paths' "$TEMPLATE_PATH")" == "$CANONICAL_TRUST_SURFACES" ]] \
  && pass "T45a: covered_paths is exactly the four existing trust surfaces" \
  || fail "T45a: covered_paths drifted: $(jq -c '.covered_paths' "$TEMPLATE_PATH")"
t45_bad=0
while IFS= read -r surface; do
  [[ -f "${SCRIPT_DIR}/../../../${surface}" ]] || { t45_bad=$((t45_bad + 1)); echo "    (missing $surface)"; }
done < <(jq -r '.covered_paths[]' "$TEMPLATE_PATH")
[[ $t45_bad -eq 0 ]] && pass "T45b: every covered path exists in this repository" \
  || fail "T45b: ${t45_bad} covered path(s) do not exist"
[[ "$(jq -r '.workflow.path' "$TEMPLATE_PATH")" == ".github/workflows/gaai-premerge.yml" \
   && "$(jq -r '.workflow.name' "$TEMPLATE_PATH")" == "GAAI Pre-Merge" \
   && "$(jq -c '.required_jobs' "$TEMPLATE_PATH")" == '["premerge-validate"]' ]] \
  && pass "T45c: the managed workflow identity and required job are forward-declared" \
  || fail "T45c: forward-declared workflow identity drifted"
jq -e --argjson cp "$(jq -c '.covered_paths' "$TEMPLATE_PATH")" \
  '.workflow.path as $w | ($cp | index($w)) == null' "$TEMPLATE_PATH" >/dev/null 2>&1 \
  && pass "T45d: the not-yet-existing workflow is declared, never covered" \
  || fail "T45d: a non-existent workflow path is listed as a covered path"

# ── T46: covered path matching nothing at B -> policy_missing ────────────────
echo ""; echo "T46: covered path matching nothing at B"
R46="${FIXTURE_BASE}/t46"
setup_repo "$R46"
make_manifest '["policy.json","never-committed.txt"]' '["job-a"]' > "$R46/policy.json"
printf 'x' > "$R46/other.txt"
gcommit "$R46" "init"
T46_B="$(git -C "$R46" rev-parse HEAD)"
printf 'y' > "$R46/other.txt"
gcommit "$R46" "candidate"
T46_H="$(git -C "$R46" rev-parse HEAD)"
T46_T="$(GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" \
  git -C "$R46" commit-tree "$(git -C "$R46" rev-parse "${T46_H}^{tree}")" -p "$T46_B" -p "$T46_H" -m merge)"
git -C "$R46" update-ref refs/heads/base "$T46_B"
git -C "$R46" update-ref refs/heads/candidate "$T46_H"
git -C "$R46" update-ref refs/heads/merge "$T46_T"
E46="${FIXTURE_BASE}/t46-evidence.json"
build_evidence_pr "$T46_B" "$T46_H" "$T46_T" "$(git -C "$R46" rev-parse "${T46_T}^{tree}")" \
  "$(manifest_digest_of "$R46/policy.json")" "$JOBS_OK_MG" 1 "$E46"
out="$(run_verify "$R46" "policy.json" "$E46")"
check_reason "$out" "policy_missing" "T46: an uncoverable path is policy_missing, not an unchanged surface"

# ── T47: dependency matrix -> environment_error, never an empty digest ───────
echo ""; echo "T47: fail-closed dependency matrix"
E47="${FIXTURE_BASE}/t47-evidence.json"
cp "$ES_OK" "$E47"
run_with_tools() {  # <dirname> <tool...> -> verdict
  local dir="${FIXTURE_BASE}/$1"; shift
  make_path_dir "$dir" "$@"
  verify_with_path "$dir" "$RS" "policy.json" "$E47"
}
out="$(run_with_tools no-git jq awk mktemp sha256sum shasum rm)"
check_reason "$out" "environment_error" "T47a: missing git"
[[ ! -s "$RESTRICTED_STDERR" ]] || fail "T47a: raw stderr leaked: $(tr '\n' ' ' < "$RESTRICTED_STDERR")"
out="$(run_with_tools no-awk jq git mktemp sha256sum shasum rm)"
check_reason "$out" "environment_error" "T47b: missing awk"
[[ ! -s "$RESTRICTED_STDERR" ]] || fail "T47b: raw stderr leaked: $(tr '\n' ' ' < "$RESTRICTED_STDERR")"
out="$(run_with_tools no-mktemp jq git awk sha256sum shasum rm)"
check_reason "$out" "environment_error" "T47c: missing mktemp"
[[ ! -s "$RESTRICTED_STDERR" ]] || fail "T47c: raw stderr leaked: $(tr '\n' ' ' < "$RESTRICTED_STDERR")"
out="$(run_with_tools no-digest jq git awk mktemp rm)"
check_reason "$out" "environment_error" "T47d: no sha256sum and no shasum"
[[ ! -s "$RESTRICTED_STDERR" ]] || fail "T47d: raw stderr leaked: $(tr '\n' ' ' < "$RESTRICTED_STDERR")"
out="$(run_with_tools no-rm jq git awk mktemp sha256sum shasum)"
check_reason "$out" "environment_error" "T47e: missing rm"
[[ ! -s "$RESTRICTED_STDERR" ]] || fail "T47e: raw stderr leaked: $(tr '\n' ' ' < "$RESTRICTED_STDERR")"
DIGEST_DIR="${FIXTURE_BASE}/digest-none"
make_path_dir "$DIGEST_DIR"
T47_DIGEST_STDERR="${FIXTURE_BASE}/t47-digest.stderr"
digest_out="$(PATH="$DIGEST_DIR" "$TEST_SHELL" -c \
  'source "$1"; printf "payload" | _premerge_digest' _ "$LIB_PATH" 2>"$T47_DIGEST_STDERR")"; digest_rc=$?
[[ $digest_rc -ne 0 && -z "$digest_out" ]] \
  && pass "T47f: _premerge_digest fails closed instead of emitting an empty digest" \
  || fail "T47f: digest fallback returned rc=$digest_rc out='$digest_out'"
[[ ! -s "$T47_DIGEST_STDERR" ]] && pass "T47g: dependency failures emit no raw shell error" \
  || fail "T47g: dependency failure leaked stderr: $(tr '\n' ' ' < "$T47_DIGEST_STDERR")"

# ── T48: schema unobtainable at B -> environment_error ───────────────────────
echo ""; echo "T48: the trusted contract must be obtainable from B"
R48="${FIXTURE_BASE}/t48"; build_pr_fixture "$R48"
E48="${FIXTURE_BASE}/t48-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E48"
R48B="${FIXTURE_BASE}/t48b"
rm -rf "$R48B"; mkdir -p "$R48B"
git init -q "$R48B"
git -C "$R48B" config user.email "test@gaai.local"
git -C "$R48B" config user.name "GAAI Test"
git -C "$R48B" config core.hooksPath /dev/null
make_manifest '["policy.json"]' '["job-a"]' > "$R48B/policy.json"
gcommit "$R48B" "no schema at B"
git -C "$R48B" update-ref refs/heads/base "$(git -C "$R48B" rev-parse HEAD)"
git -C "$R48B" update-ref refs/heads/candidate "$(git -C "$R48B" rev-parse HEAD)"
git -C "$R48B" update-ref refs/heads/merge "$(git -C "$R48B" rev-parse HEAD)"
out="$(run_verify "$R48B" "policy.json" "$E48")"
check_reason "$out" "environment_error" "T48a: schema absent at B"
R48C="${FIXTURE_BASE}/t48c"; build_pr_fixture "$R48C"
printf 'not json at all' > "$R48C/$SCHEMA_REPO_PATH"
gcommit "$R48C" "corrupt schema"
git -C "$R48C" update-ref refs/heads/base "$(git -C "$R48C" rev-parse HEAD)"
E48C="${FIXTURE_BASE}/t48c-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E48C"
out="$(run_verify "$R48C" "policy.json" "$E48C")"
check_reason "$out" "environment_error" "T48b: unparsable schema at B"
E48D="${FIXTURE_BASE}/t48d-evidence.json"
jq '.identity.base_ref = "no-such-base-ref"' "$ES_OK" > "$E48D"
out="$(run_verify "$RS" "policy.json" "$E48D")"
check_reason "$out" "environment_error" "T48c: base ref unresolvable, so no trust root can be acquired"
out="$(run_verify "$RS" "no/such/policy.json" "$ES_OK")"
check_reason "$out" "schema_invalid" "T48d: manifest absent at B is a stable reason, not a raw failure"

# ── T49: git diff-tree failure -> environment_error, not unchanged ───────────
echo ""; echo "T49: a Git failure in the trust-surface comparison is never 'unchanged'"
( cd "$RS" && _premerge_check_trust_surface "$CORR_B" "0000000000000000000000000000000000000000" "policy.json" )
rc=$?
[[ $rc -eq 2 ]] && pass "T49a: _premerge_check_trust_surface returns 2 on Git failure" \
  || fail "T49a: expected rc=2 on Git failure, got rc=$rc"
( cd "$RS" && _premerge_check_trust_surface "$CORR_B" "$CORR_T" "policy.json" )
[[ $? -eq 0 ]] && pass "T49b: an unchanged covered path still returns 0" || fail "T49b: unchanged path did not return 0"
mkdir -p "$R8/nested"
out="$(cd "$R8/nested" && bash -c 'source "$1"; _premerge_verify "$2" "$3"' \
  _ "$LIB_PATH" "policy.json" "$E8")"
check_reason "$out" "trust_surface_changed" "T49c: a protected change is detected from a repository subdirectory"
mkdir -p "$RS/nested"
out="$(cd "$RS/nested" && bash -c 'source "$1"; _premerge_verify "$2" "$3"' \
  _ "$LIB_PATH" "policy.json" "$ES_OK")"
check_success "$out" "T49d: an unchanged protected surface succeeds from a repository subdirectory"

# ── T50: truncated manifest-derived iteration -> environment_error ───────────
echo ""; echo "T50: observed-vs-declared iteration count assertion"
_PREMERGE_REASON=""
_premerge_verify_jobs '["a\nb"]' '[]' >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 && "$_PREMERGE_REASON" == "environment_error" ]] \
  && pass "T50a: an over-expanding required-job list is environment_error, not success" \
  || fail "T50a: expected environment_error, got ${_PREMERGE_REASON:-none}"
_PREMERGE_REASON=""
_premerge_verify_jobs '[]' '[]' >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 && "$_PREMERGE_REASON" == "environment_error" ]] \
  && pass "T50b: an empty required-job iteration is environment_error, not success" \
  || fail "T50b: expected environment_error, got ${_PREMERGE_REASON:-none}"
_premerge_verify_jobs '["job-a"]' "$JOBS_OK" >/dev/null 2>&1
[[ $? -eq 0 ]] && pass "T50c: a well-formed required-job list still verifies" || fail "T50c: valid job list rejected"

# ── T51: static Bash 3.2 construct assertion ─────────────────────────────────
echo ""; echo "T51: production code uses no construct absent from Bash 3.2"
t51_bad=0
check_absent() {  # <label> <extended-regex>
  local hits
  hits="$(production_code | grep -nE "$2" || true)"
  if [[ -n "$hits" ]]; then
    t51_bad=$((t51_bad + 1)); echo "    ($1): $hits"
  fi
}
check_absent "mapfile" '(^|[^[:alnum:]_])mapfile([^[:alnum:]_]|$)'
check_absent "readarray" '(^|[^[:alnum:]_])readarray([^[:alnum:]_]|$)'
check_absent "associative array" '(declare|local|typeset)[[:space:]]+-[A-Za-z]*A'
check_absent "nameref" '(declare|local|typeset)[[:space:]]+-[A-Za-z]*n[[:space:]]'
check_absent "case-conversion expansion" '\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(\^\^?|,,?)\}'
check_absent "parameter transformation" '\$\{[A-Za-z_][A-Za-z0-9_]*@[QEPAaKkLU]\}'
check_absent "coproc" '(^|[^[:alnum:]_])coproc([^[:alnum:]_]|$)'
check_absent "globstar" 'globstar|\*\*/'
check_absent "wait -n" '(^|[^[:alnum:]_])wait[[:space:]]+-n([^[:alnum:]_]|$)'
check_absent "resume-next case terminator" ';;&'
check_absent "append-both-streams redirect" '&>>'
check_absent "[[ -v ]] test" '\[\[[[:space:]]+-v[[:space:]]'
[[ $t51_bad -eq 0 ]] && pass "T51: no Bash-4-only construct in production code" \
  || fail "T51: ${t51_bad} Bash-4-only construct family(ies) present"

# ── T52: real Bash 3.2 execution when available ──────────────────────────────
echo ""; echo "T52: real Bash 3.2 execution"
BASH32=""
for candidate in /bin/bash /usr/bin/bash "$(command -v bash 2>/dev/null)"; do
  [[ -n "$candidate" && -x "$candidate" ]] || continue
  case "$("$candidate" -c 'echo $BASH_VERSION' 2>/dev/null)" in
    3.2*) BASH32="$candidate"; break ;;
  esac
done
if [[ -n "$BASH32" ]]; then
  "$BASH32" -n "$LIB_PATH" >/dev/null 2>&1 \
    && pass "T52a: parses under $("$BASH32" -c 'echo $BASH_VERSION')" \
    || fail "T52a: syntax error under Bash 3.2"
  b32_out="$(cd "$RS" && "$BASH32" -c 'source "$1"; _premerge_verify "$2" "$3"' _ "$LIB_PATH" "policy.json" "$ES_OK" 2>/dev/null)"
  check_success "$b32_out" "T52b: a valid proof verifies under a real Bash 3.2 interpreter"
  b32_rej="$(cd "$RS" && "$BASH32" -c 'source "$1"; _premerge_verify "$2" "$3"' _ "$LIB_PATH" "policy.json" "$E33" 2>/dev/null)"
  check_reason "$b32_rej" "schema_invalid" "T52c: a rejection path also runs under Bash 3.2"
else
  skip "T52: no Bash 3.2 interpreter on this host; the static assertion (T51) still ran"
fi

# ── T53: no network primitive in production code ─────────────────────────────
echo ""; echo "T53: no network or GitHub-API primitive in production code"
net_hits="$(production_code | grep -nE '(^|[^[:alnum:]_./-])(gh|curl|wget|nc|ssh|scp)[[:space:]]|https?://' || true)"
[[ -z "$net_hits" ]] && pass "T53: verification never calls gh, curl or any network primitive" \
  || fail "T53: network primitive found: $net_hits"
mut_hits="$(production_code | grep -nE 'git[[:space:]]+(commit|push|fetch|pull|merge|checkout|reset|update-ref|add|rm|clone|write-tree|commit-tree|gc|prune)([^[:alnum:]_-]|$)' || true)"
[[ -z "$mut_hits" ]] && pass "T53b: verification invokes no repository-mutating Git subcommand" \
  || fail "T53b: mutating Git subcommand found: $mut_hits"

# ── T54: verification mutates nothing ────────────────────────────────────────
echo ""; echo "T54: verification mutates nothing in the repository"
snapshot_repo() {
  git -C "$1" rev-parse HEAD
  git -C "$1" show-ref
  git -C "$1" status --porcelain
  git -C "$1" cat-file --batch-check --batch-all-objects | sort
}
R54="${FIXTURE_BASE}/t54"; build_pr_fixture "$R54"
E54="${FIXTURE_BASE}/t54-evidence.json"
build_evidence_pr "$PR_B" "$PR_H" "$PR_T" "$PR_TREE_T" "$PR_MANIFEST_DIGEST" "$JOBS_OK" 1 "$E54"
before="$(snapshot_repo "$R54")"
out="$(run_verify "$R54" "policy.json" "$E54")"
check_success "$out" "T54: the fixture still verifies"
out_rej="$(run_verify "$R54" "policy.json" "$E33")"
after="$(snapshot_repo "$R54")"
[[ "$before" == "$after" ]] \
  && pass "T54b: HEAD, refs, worktree status and object set are unchanged after verification" \
  || fail "T54b: verification changed repository state"
tmp_leftovers="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' -newer "$E54" -type d 2>/dev/null | wc -l | tr -d ' ')"
[[ "$tmp_leftovers" -eq 0 ]] && pass "T54c: no temporary trust-root directory is left behind" \
  || skip "T54c: ${tmp_leftovers} recent temp dir(s) present; not attributable to this run on a shared host"

# ── T55: local-admission resolver regression matrix stays in the OSS corpus ──
echo ""; echo "T55: local-admission resolver hermetic regression matrix"
node --test "${SCRIPT_DIR}/tests/local-admission-resolver.test.mjs" \
  && pass "T55: resolver matrix passed" \
  || fail "T55: resolver matrix failed"

echo ""
echo "════════════════════════════════════════"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${SKIP_COUNT} skipped"
echo "Verdicts checked against \$defs/verdict: ${VERDICTS_CHECKED}"
echo "════════════════════════════════════════"
[[ $FAIL_COUNT -eq 0 ]]
