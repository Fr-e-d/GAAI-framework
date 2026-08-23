#!/usr/bin/env bash
# daemon-state-machine.test.sh — E134S02 test harness
#
# Tests daemon-dispatch.sh functions in isolation using a fixture YAML.
# Does NOT source delivery-daemon.sh (avoids triggering the main loop).
#
# Usage: bash .gaai/core/scripts/tests/daemon-state-machine.test.sh

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

# Real git binary, captured before any shim is prepended to PATH. The commit
# tests put a push-faking git shim on PATH (intercepts `push` -> exit 0 without
# pushing); routing the setup push below through it would silently no-op and
# leave origin/staging unfetchable in re-run fixtures.
_REAL_GIT_BIN="$(command -v git)"

# Give a test repo an `origin` remote whose `staging` branch matches the given
# start-point (default HEAD), so `origin/staging` resolves as a remote-tracking
# ref. Required since #2045 made handle_plan_phase branch each story from
# `origin/<base>` (not the stale local ref), and the commit test-gate fetches
# `origin/staging` as its differential baseline.
_setup_origin_staging() {
  local repo="$1" start_ref="${2:-HEAD}"
  local bare="${repo%/}.origin.git"
  rm -rf "$bare" 2>/dev/null || true
  "$_REAL_GIT_BIN" init -q --bare "$bare"
  "$_REAL_GIT_BIN" -C "$repo" remote remove origin 2>/dev/null || true
  "$_REAL_GIT_BIN" -C "$repo" remote add origin "$bare"
  # staging (daemon default base) + preview (a non-staging target some tests
  # set via TARGET_BRANCH, e.g. T43) so origin/<target> resolves either way.
  "$_REAL_GIT_BIN" -C "$repo" push -q origin "${start_ref}:refs/heads/staging" "${start_ref}:refs/heads/preview"
  "$_REAL_GIT_BIN" -C "$repo" fetch -q origin
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPATCH_LIB="$SCRIPT_DIR/../daemon-dispatch.sh"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# ── Fixture YAML in /tmp ──────────────────────────────────────
FIXTURE="/tmp/gaai-daemon-state-machine.test.yaml"
ROUTING_LOG="/tmp/gaai-daemon-state-machine.routing.jsonl"

# Clean up on exit
cleanup() {
  rm -f "$FIXTURE" "$ROUTING_LOG"
  rm -f "${ADMISSION_CALL_LOG:-}"
  rm -rf "${LOCAL_ADMISSION_FIXTURE:-}"
  rm -rf "${LOCK_DIR:-}"
}
trap cleanup EXIT

cat > "$FIXTURE" << 'YAML_EOF'
- id: E134S01
  status: in_progress
  phase_status: not_started
  delivery_pipeline: 3phase
  impl_model: primary
- id: TST-3PHASE-PLANNED
  status: refined
  phase_status: planned
  delivery_pipeline: 3phase
- id: TST-3PHASE-BOGUS
  status: refined
  phase_status: bogus_invalid_state
  delivery_pipeline: 3phase
- id: TST-QA-PASS
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
- id: TST-QA-FAIL
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
- id: TST-QA-ESCALATE
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
- id: TST-QA-SPAWN-ERR
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
YAML_EOF

# Truncate routing log before tests
> "$ROUTING_LOG"

# ── Source dispatch library with required env vars ────────────
export BACKLOG_FILE="$FIXTURE"
export SCHEDULER
export PROJECT_DIR
export ROUTING_LOG_PATH="$ROUTING_LOG"
export GAAI_STUB_DELAY_S=0
export LOCK_DIR="/tmp/gaai-daemon-state-machine.locks.$$"
mkdir -p "$LOCK_DIR"

# shellcheck disable=SC1090
source "$DISPATCH_LIB"

# Preserve the production boundaries for the real integration fixture at the
# end. Older state-machine cases isolate other concerns and receive an explicit
# PASS double whose call log proves placement and ordering.
REAL_PRE_QA_DEF=$(declare -f _prepare_pre_qa_admission)
REAL_ADMIT_DEF=$(declare -f _admit_current_candidate)
ADMISSION_CALL_LOG="/tmp/gaai-daemon-state-machine.admission.$$.log"
: > "$ADMISSION_CALL_LOG"
_prepare_pre_qa_admission() {
  printf 'pre_qa|%s\n' "$1" >> "$ADMISSION_CALL_LOG"
  GAAI_ADMITTED_SHA=$(git -C "$3" rev-parse HEAD 2>/dev/null || printf '%040d' 1)
  GAAI_ADMITTED_BASE_SHA=$(git -C "$3" rev-parse origin/staging 2>/dev/null || printf '%040d' 2)
  return 0
}
_admit_current_candidate() {
  printf '%s|%s\n' "$1" "$2" >> "$ADMISSION_CALL_LOG"
  GAAI_ADMITTED_SHA=$(git -C "$4" rev-parse HEAD 2>/dev/null || printf '%040d' 1)
  GAAI_ADMITTED_BASE_SHA=$(git -C "$4" rev-parse origin/staging 2>/dev/null || printf '%040d' 2)
  return 0
}

# State-machine tests below exercise commit/PR behavior downstream of merge
# authority. Bind those paths to an explicit hosted-pass tuple so the fixtures
# never rely on the forbidden missing-CI/local-fallback authorization removed
# by the hosted-only authority contract. The dedicated controller suite owns
# REST failure coverage.
_run_merge_test_gate() {
  TEST_GATE_OUTCOME=hosted_pass
  TEST_GATE_AUTH_PR_NUMBER=999
  TEST_GATE_AUTH_REPOSITORY_ID=42
  TEST_GATE_AUTH_REPOSITORY_NAME=test/repo
  TEST_GATE_AUTH_BASE_REF="${TARGET_BRANCH:-staging}"
  TEST_GATE_AUTH_BASE_SHA="$(git -C "$2" rev-parse "origin/${TARGET_BRANCH:-staging}" 2>/dev/null || printf '%040d' 1)"
  TEST_GATE_AUTH_HEAD_REF="story/$1"
  TEST_GATE_AUTH_HEAD_SHA="$5"
  TEST_GATE_AUTH_WORKFLOW_ID=7001
  TEST_GATE_AUTH_RUN_ID=9001
  TEST_GATE_AUTH_RUN_NUMBER=12
  TEST_GATE_AUTH_RUN_ATTEMPT=1
  TEST_GATE_AUTH_JOB_ID=9101
  TEST_GATE_AUTH_WORKTREE_PATH="$2"
  export TEST_GATE_OUTCOME TEST_GATE_AUTH_PR_NUMBER TEST_GATE_AUTH_REPOSITORY_ID \
    TEST_GATE_AUTH_REPOSITORY_NAME TEST_GATE_AUTH_BASE_REF TEST_GATE_AUTH_BASE_SHA TEST_GATE_AUTH_HEAD_REF \
    TEST_GATE_AUTH_HEAD_SHA TEST_GATE_AUTH_WORKFLOW_ID TEST_GATE_AUTH_RUN_ID TEST_GATE_AUTH_RUN_NUMBER \
    TEST_GATE_AUTH_RUN_ATTEMPT TEST_GATE_AUTH_JOB_ID TEST_GATE_AUTH_WORKTREE_PATH
  return 0
}
_test_gate_recheck_pr_tuple() { echo hosted_pass; return 0; }

echo "E134S02 — daemon-state-machine dispatch tests"
echo ""

# ── T2: get_delivery_pipeline — 3phase story ─────────────────
echo "T2: get_delivery_pipeline — 3phase story"
result=$(get_delivery_pipeline "E134S01")
if [[ "$result" == "3phase" ]]; then
  pass "T2: get_delivery_pipeline returns '3phase' for E134S01"
else
  fail "T2: expected '3phase', got '$result'"
fi

# ── T3: get_phase_status — not_started ───────────────────────
echo "T3: get_phase_status — not_started"
result=$(get_phase_status "E134S01")
if [[ "$result" == "not_started" ]]; then
  pass "T3: get_phase_status returns 'not_started' for E134S01"
else
  fail "T3: expected 'not_started', got '$result'"
fi

# ── Setup for T4-T8: handle_plan_phase requires GAAI_WORKTREE_PATH + claude shim ──
# handle_plan_phase is now the real spawn, not a stub.
# T4-T8 need a worktree fixture + success claude shim so plan phase can advance.
DISPATCH_FIXTURE_DIR="/tmp/gaai-dispatch-tests-$$"
mkdir -p "$DISPATCH_FIXTURE_DIR/.gaai/project/contexts/artefacts/stories"
mkdir -p "$DISPATCH_FIXTURE_DIR/.gaai/project/contexts/artefacts/plans"
mkdir -p "$DISPATCH_FIXTURE_DIR/.delivery-logs"
cp -R "$PROJECT_DIR/.gaai/core" "$DISPATCH_FIXTURE_DIR/.gaai/core"
# Synthesised, not copied from $PROJECT_DIR. The fixture only needs a parseable
# package.json for lib/test-gate.sh's scripts[] lookup; its contents are never
# asserted. Copying the host repo's file made this test depend on the host
# being a Node project — true in the dogfood repo, false in the published
# framework repo, which ships .gaai/core with no package.json at all, so the
# test died on a missing file the moment CI ran it there.
printf '{"name":"gaai-test-fixture","private":true,"version":"0.0.0"}\n' > "$DISPATCH_FIXTURE_DIR/package.json"
cat > "$DISPATCH_FIXTURE_DIR/.gaai/project/contexts/artefacts/stories/E134S01.story.md" << 'DISPATCH_STORY_EOF'
---
type: artefact
artefact_type: story
id: E134S01
related_decs: []
---
## Acceptance Criteria
- [ ] AC1: test
DISPATCH_STORY_EOF

git -C "$DISPATCH_FIXTURE_DIR" init -q
git -C "$DISPATCH_FIXTURE_DIR" config user.email "test@example.com"
git -C "$DISPATCH_FIXTURE_DIR" config user.name "Test"
git -C "$DISPATCH_FIXTURE_DIR" add . >/dev/null
git -C "$DISPATCH_FIXTURE_DIR" commit -m "dispatch fixture" --quiet
git -C "$DISPATCH_FIXTURE_DIR" checkout -B staging -q
_setup_origin_staging "$DISPATCH_FIXTURE_DIR"

DISPATCH_PROJECT_DIR="$DISPATCH_FIXTURE_DIR"
DISPATCH_WORKTREES_BASE="$DISPATCH_FIXTURE_DIR/worktrees"
mkdir -p "$DISPATCH_WORKTREES_BASE"

DISPATCH_SHIM_DIR="$DISPATCH_FIXTURE_DIR/shims"
mkdir -p "$DISPATCH_SHIM_DIR"
cat > "$DISPATCH_SHIM_DIR/claude" << 'DISPATCH_SHIM_EOF'
#!/usr/bin/env bash
if [[ -n "${GAAI_QA_REPORT_PATH:-}" ]]; then
  if [[ -n "${GAAI_QA_VERDICT_PATH:-}" ]]; then
    printf '{"schema_version":1,"story_id":"%s","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"PASS","plan_conformance":"PASS","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"PASS","remediation_route":null,"replan_required":null,"report_path":"qa-reports/%s.qa-report.md"}' "${GAAI_STORY_ID:-}" "${GAAI_STORY_ID:-}" > "${GAAI_QA_VERDICT_PATH}"
  fi
  printf '## AC1\npass\n\n## Verdict: PASS\n' > "${GAAI_QA_REPORT_PATH}"
elif [[ -n "${GAAI_PLAN_PATH:-}" ]]; then
  printf '## Implementation Sequence\nStep 1.\n' > "${GAAI_PLAN_PATH}"
fi
exit 0
DISPATCH_SHIM_EOF
chmod +x "$DISPATCH_SHIM_DIR/claude"

# git shim for commit phase (T7c): intercept push → exit 0, delegate rest to real git
DISPATCH_REAL_GIT_BIN="$(command -v git)"
export DISPATCH_REAL_GIT_BIN GAAI_DISPATCH_PUSH_SHA_FILE="$DISPATCH_FIXTURE_DIR/push-sha"
cat > "$DISPATCH_SHIM_DIR/git" << 'DISPATCH_GIT_SHIM_EOF'
#!/usr/bin/env bash
_i=0; _args=("$@")
while [[ $_i -lt ${#_args[@]} ]]; do
  [[ "${_args[$_i]}" == "-C" ]] && { _i=$(( _i + 2 )); continue; }
  break
done
if [[ "${_args[$_i]:-}" == "push" ]]; then
  for _arg in "${_args[@]}"; do
    [[ "$_arg" == *:refs/heads/* ]] && printf '%s\t%s\n' "${_arg%%:*}" "${_arg#*:}" > "$GAAI_DISPATCH_PUSH_SHA_FILE"
  done
  exit 0
fi
if [[ "${_args[$_i]:-}" == "ls-remote" && -s "$GAAI_DISPATCH_PUSH_SHA_FILE" ]]; then
  _last=$((${#_args[@]} - 1)); _wanted="${_args[$_last]}"
  IFS=$'\t' read -r _sha _dest < "$GAAI_DISPATCH_PUSH_SHA_FILE"
  [[ "$_wanted" == "$_dest" ]] && { printf '%s\t%s\n' "$_sha" "$_dest"; exit 0; }
fi
exec "$DISPATCH_REAL_GIT_BIN" "$@"
DISPATCH_GIT_SHIM_EOF
chmod +x "$DISPATCH_SHIM_DIR/git"

# gh shim for commit phase (T7c): returns fake PR URL
export GAAI_DISPATCH_MERGE_SHA_FILE="$DISPATCH_FIXTURE_DIR/merge-sha"
cat > "$DISPATCH_SHIM_DIR/gh" << 'DISPATCH_GH_SHIM_EOF'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "api --method")
    for _arg in "$@"; do
      [[ "$_arg" == sha=* ]] && printf '%s\n' "${_arg#sha=}" > "$GAAI_DISPATCH_MERGE_SHA_FILE"
    done
    echo "true"
    exit 0 ;;
  "pr create") echo "https://github.com/test/repo/pull/999"; exit 0 ;;
  "pr view")
    if [[ "$*" == *"--json state,headRefOid"* ]]; then
      merged_sha=$(cat "$GAAI_DISPATCH_MERGE_SHA_FILE" 2>/dev/null || true)
      if [[ -n "${TEST_GATE_AUTH_HEAD_SHA:-}" && "$merged_sha" == "$TEST_GATE_AUTH_HEAD_SHA" ]]; then
        printf 'MERGED\t%s\n' "$merged_sha"
      else
        printf 'OPEN\t%s\n' "${TEST_GATE_AUTH_HEAD_SHA:-}"
      fi
      exit 0
    fi
    [[ "$*" == *"--json url"* ]] && { echo "https://github.com/test/repo/pull/999"; exit 0; }
    [[ "$*" == *"--json number"* ]] && { echo "999"; exit 0; }
    [[ "$*" == *"--json autoMergeRequest"* ]] && { echo '{"mergeMethod":"squash"}'; exit 0; }
    exit 0 ;;
  *) exit 0 ;;
esac
DISPATCH_GH_SHIM_EOF
chmod +x "$DISPATCH_SHIM_DIR/gh"

cat > "$DISPATCH_SHIM_DIR/pnpm" << 'DISPATCH_PNPM_SHIM_EOF'
#!/usr/bin/env bash
mkdir -p node_modules/.pnpm  # _wt_deps_marker_dir default — deps-installed marker
exit 0
DISPATCH_PNPM_SHIM_EOF
chmod +x "$DISPATCH_SHIM_DIR/pnpm"

# ── Impl-phase fixture worktrees for T5 and T7 ───────────────────────────────
# handle_impl_phase resolves worktrees as: $GAAI_WORKTREES_BASE/{story_id}-workspace
DISPATCH_OLD_PROJECT_DIR="$PROJECT_DIR"
export PROJECT_DIR="$DISPATCH_PROJECT_DIR"
export GAAI_WORKTREES_BASE="$DISPATCH_WORKTREES_BASE"

for _impl_id in TST-3PHASE-PLANNED; do
  _wt="$DISPATCH_WORKTREES_BASE/${_impl_id}-workspace"
  mkdir -p "$_wt/.gaai/project/contexts/artefacts/stories"
  mkdir -p "$_wt/.gaai/project/contexts/artefacts/plans"
  mkdir -p "$_wt/.gaai/project/contexts/artefacts/impl-reports"
  mkdir -p "$_wt/.delivery-logs"
  cat > "$_wt/.gaai/project/contexts/artefacts/stories/${_impl_id}.story.md" << IMPL_STORY_EOF
---
type: artefact
artefact_type: story
id: ${_impl_id}
related_decs: []
---
## Acceptance Criteria
- [ ] AC1: test
IMPL_STORY_EOF
  printf '## Implementation Sequence\nStep 1.\n' \
    > "$_wt/.gaai/project/contexts/artefacts/plans/${_impl_id}.execution-plan.md"
  # git-init each worktree so handle_commit_phase can run git operations
  git -C "$_wt" init -q
  git -C "$_wt" config user.email "test@example.com"
  git -C "$_wt" config user.name "Test"
  git -C "$_wt" commit --allow-empty -m "init" --quiet
  git -C "$_wt" checkout -B "story/${_impl_id}" -q
done
unset _impl_id _wt

# ── node shim: redirects nested-claude-spawn.js to impl-spawn-stub.mjs ──────
# This exercises the real runImpl() routing via _setSpawnFn (AC6.a requirement).
DISPATCH_REAL_NODE="$(command -v node)"
IMPL_SPAWN_STUB_PATH="$SCRIPT_DIR/helpers/impl-spawn-stub.mjs"
export DISPATCH_REAL_NODE IMPL_SPAWN_STUB_PATH

cat > "$DISPATCH_SHIM_DIR/node" << 'NODE_SHIM_EOF'
#!/usr/bin/env bash
if [[ "$1" == *nested-claude-spawn.js* ]]; then
  exec "$DISPATCH_REAL_NODE" "$IMPL_SPAWN_STUB_PATH" "${@:2}" --stub-success true
fi
exec "$DISPATCH_REAL_NODE" "$@"
NODE_SHIM_EOF
chmod +x "$DISPATCH_SHIM_DIR/node"

export GAAI_WORKTREE_PATH="$DISPATCH_FIXTURE_DIR"
export CLAUDE_MODEL_PRIMARY="claude-sonnet-4-6"
DISPATCH_OLD_PATH="$PATH"
export PATH="$DISPATCH_SHIM_DIR:$PATH"

# ── T4: dispatch not_started → planned ───────────────────────
echo "T4: dispatch not_started → planned"
TRACE="test-trace-$(date +%s)-001"
if dispatch_3phase_story "E134S01" "$TRACE" 2>/dev/null; then
  new_ps=$(get_phase_status "E134S01")
  if [[ "$new_ps" == "planned" ]]; then
    pass "T4a: phase_status advanced to 'planned'"
  else
    fail "T4a: expected 'planned', got '$new_ps'"
  fi
  if grep -q '"phase":"plan"' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"provider":"primary"' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"pipeline":"3phase"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T4b: routing.jsonl has plan+primary+pipeline:3phase record"
  else
    fail "T4b: routing.jsonl missing expected fields — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T4: dispatch_3phase_story returned non-zero for not_started story"
  for dispatch_worktree in "$DISPATCH_WORKTREES_BASE"/*-workspace; do
    [[ -d "$dispatch_worktree" ]] || continue
    git -C "$DISPATCH_PROJECT_DIR" worktree remove -f "$dispatch_worktree" >/dev/null 2>&1 || rm -rf "$dispatch_worktree"
  done
fi

# ── T5: dispatch planned → implemented ───────────────────────
echo "T5: dispatch planned → implemented (TST-3PHASE-PLANNED)"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-002"
if dispatch_3phase_story "TST-3PHASE-PLANNED" "$TRACE"; then
  new_ps=$(get_phase_status "TST-3PHASE-PLANNED")
  if [[ "$new_ps" == "implemented" ]]; then
    pass "T5a: phase_status advanced to 'implemented'"
  else
    fail "T5a: expected 'implemented', got '$new_ps'"
  fi
  # Routing record for impl is emitted internally by runImpl (AC4 — no daemon duplicate-emit).
  # Verify the impl-report.md was written at the canonical worktree path instead.
  _t5_report="$DISPATCH_WORKTREES_BASE/TST-3PHASE-PLANNED-workspace/.gaai/project/contexts/artefacts/impl-reports/TST-3PHASE-PLANNED.impl-report.md"
  if [[ -f "$_t5_report" ]]; then
    pass "T5b: impl-report.md written at canonical worktree path"
  else
    fail "T5b: impl-report.md missing at $_t5_report"
  fi
  unset _t5_report
else
  fail "T5: dispatch_3phase_story returned non-zero for planned story"
fi

# ── T6: bogus phase_status triggers error (non-zero, no crash) ─
echo "T6: bogus phase_status → error (non-zero, no crash)"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-003"
original_ps=$(get_phase_status "TST-3PHASE-BOGUS")
if dispatch_3phase_story "TST-3PHASE-BOGUS" "$TRACE" 2>/dev/null; then
  fail "T6: expected non-zero for bogus phase_status, got exit 0"
else
  pass "T6a: dispatch_3phase_story exits non-zero for bogus phase_status"
  after_ps=$(get_phase_status "TST-3PHASE-BOGUS")
  if [[ "$after_ps" == "$original_ps" ]]; then
    pass "T6b: phase_status unchanged ('$after_ps') after error"
  else
    fail "T6b: phase_status changed from '$original_ps' to '$after_ps' — should be unchanged"
  fi
  if grep -q '"provider":"error"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T6c: routing.jsonl contains error record (provider:error)"
  else
    fail "T6c: routing.jsonl missing error record — content: $(cat "$ROUTING_LOG" 2>/dev/null | head -3)"
  fi
fi

# ── T7: full progression planned → implemented → qa_passed → done
echo "T7: full 3-phase stub progression (E134S01, continuing from planned per T4)"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-004"

dispatch_3phase_story "E134S01" "$TRACE" 2>/dev/null || true
ps=$(get_phase_status "E134S01")
[[ "$ps" == "implemented" ]] && pass "T7a: planned→implemented" || fail "T7a: expected implemented, got '$ps'"

dispatch_3phase_story "E134S01" "$TRACE" 2>/dev/null || true
ps=$(get_phase_status "E134S01")
[[ "$ps" == "qa_passed" ]] && pass "T7b: implemented→qa_passed" || fail "T7b: expected qa_passed, got '$ps'"

dispatch_3phase_story "E134S01" "$TRACE" 2>/dev/null || true
ps=$(get_phase_status "E134S01")
[[ "$ps" == "done" ]] && pass "T7c: qa_passed→done" || fail "T7c: expected done, got '$ps'"

# impl routing record is emitted internally by runImpl to DEFAULT_LOG_PATH (AC4 — no daemon dup).
# qa and commit stubs emit to ROUTING_LOG via _emit_routing_record.
_t7_qa=$(grep -c '"phase":"qa"' "$ROUTING_LOG" 2>/dev/null || true)
_t7_commit=$(grep -c '"phase":"commit"' "$ROUTING_LOG" 2>/dev/null || true)
if [[ "${_t7_qa:-0}" -ge 1 && "${_t7_commit:-0}" -ge 1 ]]; then
  pass "T7d: routing.jsonl has qa+commit phase records (impl recorded internally by runImpl)"
else
  fail "T7d: expected qa+commit records, got qa=${_t7_qa:-0} commit=${_t7_commit:-0}"
fi
_t7_story_id=$(awk '/^- id:/{print $3; exit}' "$FIXTURE")
if awk -F'|' -v sid="$_t7_story_id" '$1=="pre_qa"&&$2==sid{pre=NR} $1=="final"&&$2==sid{fin=NR} END{exit !(pre&&fin&&pre<fin)}' "$ADMISSION_CALL_LOG" \
    && [[ -s "$GAAI_DISPATCH_PUSH_SHA_FILE" ]]; then
  pass "T7e: pre-QA admission precedes final admission and exact-SHA publication"
else
  fail "T7e: local admission ordering or exact-SHA push evidence missing"
fi
unset _t7_qa _t7_commit _t7_story_id

# ── T8: dispatch on terminal state (done) returns 0 without crashing ──────
echo "T8: dispatch on done state returns 0"
TRACE="test-trace-$(date +%s)-005"
if dispatch_3phase_story "E134S01" "$TRACE" 2>/dev/null; then
  pass "T8: dispatch on done state returns 0 (no crash, no advance)"
else
  fail "T8: dispatch on done state returned non-zero"
fi

# ── T8b: YAML inline-comment stripping in extractors (regression guard) ──
# Bug : awk extractors (get_phase_status, get_delivery_pipeline, get_impl_model_tag,
# get_story_tier, get_story_title) stripped leading whitespace + outer quotes
# but did not strip inline `# comment` text. Symptom : a backlog entry like
# `impl_model: primary  # some comment` was read as the full string with the
# comment included, causing string-equality checks against `primary` to fail
# and the daemon hard-gate to fall back to secondary route on Tier 2 stories.
# Fix : added gsub `[[:space:]]+#.*$` to all 5 extractors. This test prevents
# regression by exercising each extractor against a fixture with inline comments.
echo "T8b: YAML inline-comment stripping in extractors (regression guard)"
T8b_FIXTURE="/tmp/gaai-t8b-fixture-$$.yaml"
cat > "$T8b_FIXTURE" <<'EOF'
items:
- id: TST-T8B-INLINE
  epic: TST
  title: Test inline comment   # leading title with comment
  status: refined
  phase_status: not_started   # phase_status with comment
  delivery_pipeline: 3phase  # pipeline with comment
  tier: 2  # tier with comment
  impl_model: primary  # impl_model with inline comment
EOF
T8B_OLD_BACKLOG="$BACKLOG_FILE"
export BACKLOG_FILE="$T8b_FIXTURE"
T8b_pass=0
T8b_fail=0
for _t in 'phase_status:not_started:get_phase_status' \
          'delivery_pipeline:3phase:get_delivery_pipeline' \
          'tier:2:get_story_tier' \
          'impl_model:primary:get_impl_model_tag'; do
  _field="${_t%%:*}"; _expected="${_t#*:}"; _expected="${_expected%%:*}"; _fn="${_t##*:}"
  _actual=$("$_fn" "TST-T8B-INLINE")
  if [[ "$_actual" == "$_expected" ]]; then
    pass "T8b: $_fn strips inline comment (got '$_actual')"
    T8b_pass=$((T8b_pass+1))
  else
    fail "T8b: $_fn expected '$_expected' got '$_actual' (inline-comment regression!)"
    T8b_fail=$((T8b_fail+1))
  fi
done
# Title is special — value is multi-word with embedded comment, just verify no `#` leaks
_title=$(get_story_title "TST-T8B-INLINE")
if [[ "$_title" != *"#"* ]]; then
  pass "T8b: get_story_title strips inline comment (got '$_title')"
else
  fail "T8b: get_story_title did not strip inline comment (got '$_title')"
fi
export BACKLOG_FILE="$T8B_OLD_BACKLOG"
unset T8B_OLD_BACKLOG _t _field _expected _fn _actual _title T8b_pass T8b_fail
rm -f "$T8b_FIXTURE"

# Cleanup T4-T8 dispatch fixtures
export PATH="$DISPATCH_OLD_PATH"
unset GAAI_WORKTREE_PATH CLAUDE_MODEL_PRIMARY GAAI_WORKTREES_BASE
export PROJECT_DIR="$DISPATCH_OLD_PROJECT_DIR"
unset DISPATCH_REAL_NODE IMPL_SPAWN_STUB_PATH DISPATCH_FIXTURE_DIR DISPATCH_SHIM_DIR DISPATCH_OLD_PATH DISPATCH_PROJECT_DIR DISPATCH_WORKTREES_BASE DISPATCH_OLD_PROJECT_DIR
rm -rf "/tmp/gaai-dispatch-tests-$$"

# ── T9-T14: handle_plan_phase real spawn tests ────────────────
# These tests exercise handle_plan_phase directly (not via dispatch_3phase_story)
# using a claude shim injected earlier in PATH.

# Setup: shared fixtures for T9-T14
PLAN_FIXTURE_DIR="/tmp/gaai-plan-phase-tests-$$"
rm -rf "$PLAN_FIXTURE_DIR"
mkdir -p "$PLAN_FIXTURE_DIR"
PLAN_PROJECT_DIR="$PLAN_FIXTURE_DIR/project"
PLAN_WORKTREES_BASE="$PLAN_FIXTURE_DIR/worktrees"
mkdir -p "$PLAN_PROJECT_DIR/.gaai/project/contexts/artefacts/stories" "$PLAN_WORKTREES_BASE"
cp -R "$PROJECT_DIR/.gaai/core" "$PLAN_PROJECT_DIR/.gaai/core"
# Synthesised, not copied from $PROJECT_DIR. The fixture only needs a parseable
# package.json for lib/test-gate.sh's scripts[] lookup; its contents are never
# asserted. Copying the host repo's file made this test depend on the host
# being a Node project — true in the dogfood repo, false in the published
# framework repo, which ships .gaai/core with no package.json at all, so the
# test died on a missing file the moment CI ran it there.
printf '{"name":"gaai-test-fixture","private":true,"version":"0.0.0"}\n' > "$PLAN_PROJECT_DIR/package.json"

# Fixture story file (minimal — just needs 'epic:' field parseable by grep)
PLAN_STORY_ID="TST-PLAN-01"
PLAN_STORY_PATH="$PLAN_PROJECT_DIR/.gaai/project/contexts/artefacts/stories/${PLAN_STORY_ID}.story.md"
cat > "$PLAN_STORY_PATH" << 'STORY_EOF'
---
type: artefact
artefact_type: story
id: TST-PLAN-01
epic: E134
related_decs: []
---
# Story: test story for T9-T14
## Acceptance Criteria
- [ ] AC1: test
STORY_EOF

git -C "$PLAN_PROJECT_DIR" init -q
git -C "$PLAN_PROJECT_DIR" config user.email "test@example.com"
git -C "$PLAN_PROJECT_DIR" config user.name "Test"
git -C "$PLAN_PROJECT_DIR" add . >/dev/null
git -C "$PLAN_PROJECT_DIR" commit -m "plan fixture" --quiet
git -C "$PLAN_PROJECT_DIR" checkout -B staging -q
_setup_origin_staging "$PLAN_PROJECT_DIR"

PLAN_WORKTREE="$PLAN_WORKTREES_BASE/${PLAN_STORY_ID}-workspace"
PLAN_PATH="$PLAN_WORKTREE/.gaai/project/contexts/artefacts/plans/${PLAN_STORY_ID}.execution-plan.md"

# Add fixture story to fixture YAML for scheduler calls
cat >> "$FIXTURE" << 'YAML_APPEND'
- id: TST-PLAN-01
  status: in_progress
  phase_status: not_started
  delivery_pipeline: 3phase
  impl_model: primary
YAML_APPEND

# ── claude shim directory ─────────────────────────────────────
SHIM_DIR="$PLAN_FIXTURE_DIR/shims"
mkdir -p "$SHIM_DIR"

cat > "$SHIM_DIR/pnpm" << 'PLAN_PNPM_SHIM_EOF'
#!/usr/bin/env bash
mkdir -p node_modules/.pnpm  # _wt_deps_marker_dir default — deps-installed marker
exit 0
PLAN_PNPM_SHIM_EOF
chmod +x "$SHIM_DIR/pnpm"

# Helper: create a valid-plan-content claude shim
make_success_shim() {
  cat > "$SHIM_DIR/claude" << 'SHIM_EOF'
#!/usr/bin/env bash
# claude shim: writes valid plan content and exits 0
if [[ -n "${GAAI_PLAN_PATH:-}" ]]; then
  cat > "$GAAI_PLAN_PATH" << 'PLAN_EOF'
---
type: artefact
artefact_type: execution-plan
id: TST-PLAN-01
---
## Implementation Sequence
Step 1: do the thing.
## Edge Cases
None.
PLAN_EOF
fi
exit 0
SHIM_EOF
  chmod +x "$SHIM_DIR/claude"
}

# Helper: create a failing claude shim (exits 1, writes nothing)
make_fail_shim() {
  cat > "$SHIM_DIR/claude" << 'SHIM_EOF'
#!/usr/bin/env bash
exit 1
SHIM_EOF
  chmod +x "$SHIM_DIR/claude"
}

# Prepend shim dir to PATH for all T9-T14 calls
OLD_PATH="$PATH"
export PATH="$SHIM_DIR:$PATH"

# Required env vars for handle_plan_phase
export GAAI_WORKTREE_PATH="$PLAN_WORKTREE"
export GAAI_WORKTREES_BASE="$PLAN_WORKTREES_BASE"
export GAAI_WORKSPACE_ID="test-workspace"
export GAAI_ORG_ID="test-org"
export CLAUDE_MODEL_PRIMARY="claude-sonnet-4-6"

# Point PROJECT_DIR to the test project dir so handle_plan_phase finds planning.daemon-prompt.md
export PROJECT_DIR_ORIG="$PROJECT_DIR"
export PROJECT_DIR="$PLAN_PROJECT_DIR"

# ── T9: successful Plan phase spawn — phase_status advances ──
echo "T9: handle_plan_phase — mock claude exits 0, valid plan output"
make_success_shim
"$SCHEDULER" --set-phase-status "$PLAN_STORY_ID" not_started "$FIXTURE" 2>/dev/null || true
rm -f "$PLAN_PATH"
git -C "$PLAN_PROJECT_DIR" worktree remove -f "$PLAN_WORKTREE" >/dev/null 2>&1 || rm -rf "$PLAN_WORKTREE"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-009"

if handle_plan_phase "$PLAN_STORY_ID" "$TRACE" 2>/dev/null; then
  pass "T9a: handle_plan_phase returns 0 with valid mock claude"
  new_ps=$(get_phase_status "$PLAN_STORY_ID")
  if [[ "$new_ps" == "planned" ]]; then
    pass "T9b: phase_status advanced to 'planned'"
  else
    fail "T9b: expected 'planned', got '$new_ps'"
  fi
  if [[ -f "$PLAN_PATH" ]]; then
    pass "T9c: plan file written at GAAI_PLAN_PATH"
  else
    fail "T9c: plan file missing at $PLAN_PATH"
  fi
else
  fail "T9a: handle_plan_phase returned non-zero (check planning.daemon-prompt.md at $PROJECT_DIR/.gaai/core/agents/sub-agents/planning.daemon-prompt.md)"
  fail "T9b: (skipped — T9a failed)"
  fail "T9c: (skipped — T9a failed)"
fi

# ── T10: routing record has pipeline:3phase + model field ──────
echo "T10: routing.jsonl has pipeline:3phase + model from CLAUDE_MODEL_PRIMARY"
if grep -q '"pipeline":"3phase"' "$ROUTING_LOG" 2>/dev/null; then
  pass "T10a: routing.jsonl has pipeline:3phase"
else
  fail "T10a: routing.jsonl missing pipeline:3phase — content: $(head -2 "$ROUTING_LOG" 2>/dev/null)"
fi
if grep -q '"model":"claude-sonnet-4-6"' "$ROUTING_LOG" 2>/dev/null; then
  pass "T10b: routing.jsonl has model:claude-sonnet-4-6 (from CLAUDE_MODEL_PRIMARY)"
else
  fail "T10b: routing.jsonl missing model field — content: $(head -2 "$ROUTING_LOG" 2>/dev/null)"
fi
if grep -q '"provider":"primary"' "$ROUTING_LOG" 2>/dev/null; then
  pass "T10c: routing.jsonl has provider:primary (success path)"
else
  fail "T10c: routing.jsonl missing provider:primary — content: $(head -2 "$ROUTING_LOG" 2>/dev/null)"
fi

# ── T11: error path — mock claude exits non-zero ───────────────
echo "T11: handle_plan_phase — mock claude exits 1 → no phase advance, error record"
make_fail_shim
"$SCHEDULER" --set-phase-status "$PLAN_STORY_ID" not_started "$FIXTURE" 2>/dev/null || true
rm -f "$PLAN_PATH"
git -C "$PLAN_PROJECT_DIR" worktree remove -f "$PLAN_WORKTREE" >/dev/null 2>&1 || rm -rf "$PLAN_WORKTREE"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-011"

if handle_plan_phase "$PLAN_STORY_ID" "$TRACE" 2>/dev/null; then
  fail "T11a: expected non-zero return when claude exits 1, got 0"
  fail "T11b: (skipped)"
  fail "T11c: (skipped)"
else
  pass "T11a: handle_plan_phase returns non-zero when claude exits 1"
  new_ps=$(get_phase_status "$PLAN_STORY_ID")
  if [[ "$new_ps" == "not_started" ]]; then
    pass "T11b: phase_status unchanged (not_started) after error"
  else
    fail "T11b: expected not_started, got '$new_ps'"
  fi
  if grep -q '"provider":"error"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T11c: error routing record emitted (provider:error)"
  else
    fail "T11c: routing.jsonl missing error record — content: $(head -2 "$ROUTING_LOG" 2>/dev/null)"
  fi
fi

# ── T12: pipefail propagation — mock exits 1, tee succeeds ────
echo "T12: pipefail propagation — PIPESTATUS[0] captures claude exit 1 through tee"
# Same shim as T11 (exits 1); tee will still succeed (exit 0).
# handle_plan_phase must detect claude_exit=1 via PIPESTATUS[0], not tee's exit.
make_fail_shim
"$SCHEDULER" --set-phase-status "$PLAN_STORY_ID" not_started "$FIXTURE" 2>/dev/null || true
rm -f "$PLAN_PATH"
git -C "$PLAN_PROJECT_DIR" worktree remove -f "$PLAN_WORKTREE" >/dev/null 2>&1 || rm -rf "$PLAN_WORKTREE"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-012"

if handle_plan_phase "$PLAN_STORY_ID" "$TRACE" 2>/dev/null; then
  fail "T12: expected non-zero (pipefail capture), got 0 — PIPESTATUS wiring broken"
else
  pass "T12: PIPESTATUS[0] correctly captures claude exit 1 through tee pipe"
fi

# ── T13: 0-byte plan output guard ─────────────────────────────
echo "T13: 0-byte plan file → NO_ARTEFACT error path"
cat > "$SHIM_DIR/claude" << 'SHIM_T13'
#!/usr/bin/env bash
if [[ -n "${GAAI_PLAN_PATH:-}" ]]; then
  touch "$GAAI_PLAN_PATH"
fi
exit 0
SHIM_T13
chmod +x "$SHIM_DIR/claude"
"$SCHEDULER" --set-phase-status "$PLAN_STORY_ID" not_started "$FIXTURE" 2>/dev/null || true
rm -f "$PLAN_PATH"
git -C "$PLAN_PROJECT_DIR" worktree remove -f "$PLAN_WORKTREE" >/dev/null 2>&1 || rm -rf "$PLAN_WORKTREE"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-013"

if handle_plan_phase "$PLAN_STORY_ID" "$TRACE" 2>/dev/null; then
  fail "T13a: expected non-zero for 0-byte plan file, got 0"
  fail "T13b: (skipped)"
else
  pass "T13a: handle_plan_phase returns non-zero for 0-byte plan output"
  new_ps=$(get_phase_status "$PLAN_STORY_ID")
  if [[ "$new_ps" == "not_started" ]]; then
    pass "T13b: phase_status NOT advanced after empty-file error"
  else
    fail "T13b: expected not_started, got '$new_ps'"
  fi
fi

# ── T14: missing '## ' heading guard ──────────────────────────
echo "T14: plan file without '## ' heading → PARSE_ERROR path"
cat > "$SHIM_DIR/claude" << 'SHIM_T14'
#!/usr/bin/env bash
if [[ -n "${GAAI_PLAN_PATH:-}" ]]; then
  printf '# Only h1 heading here\nSome content but no level-2 heading.\n' > "$GAAI_PLAN_PATH"
fi
exit 0
SHIM_T14
chmod +x "$SHIM_DIR/claude"
"$SCHEDULER" --set-phase-status "$PLAN_STORY_ID" not_started "$FIXTURE" 2>/dev/null || true
rm -f "$PLAN_PATH"
git -C "$PLAN_PROJECT_DIR" worktree remove -f "$PLAN_WORKTREE" >/dev/null 2>&1 || rm -rf "$PLAN_WORKTREE"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-014"

if handle_plan_phase "$PLAN_STORY_ID" "$TRACE" 2>/dev/null; then
  fail "T14a: expected non-zero for plan missing '## ' heading, got 0"
  fail "T14b: (skipped)"
else
  pass "T14a: handle_plan_phase returns non-zero for plan without '## ' heading"
  if grep -q '"fallback_reason":"PARSE_ERROR"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T14b: error record has fallback_reason:PARSE_ERROR"
  else
    fail "T14b: expected PARSE_ERROR in routing log — content: $(head -2 "$ROUTING_LOG" 2>/dev/null)"
  fi
fi

# Restore PATH and PROJECT_DIR
export PATH="$OLD_PATH"
export PROJECT_DIR="$PROJECT_DIR_ORIG"
unset GAAI_WORKTREES_BASE

# Cleanup plan phase test fixtures
rm -rf "$PLAN_FIXTURE_DIR"

# ── T15-T21: handle_impl_phase real spawn tests ───────────────
# These tests exercise handle_impl_phase directly using a node shim that
# redirects nested-claude-spawn.js to impl-spawn-stub.mjs (_setSpawnFn seam),
# exercising the real runImpl() routing logic per AC6.a.

IMPL_FIXTURE_DIR="/tmp/gaai-impl-phase-tests-$$"
rm -rf "$IMPL_FIXTURE_DIR"
mkdir -p "$IMPL_FIXTURE_DIR"

IMPL_STORY_ID="TST-IMPL-01"
IMPL_WORKTREE="$IMPL_FIXTURE_DIR/${IMPL_STORY_ID}-workspace"
mkdir -p "$IMPL_WORKTREE/.gaai/project/contexts/artefacts/stories"
mkdir -p "$IMPL_WORKTREE/.gaai/project/contexts/artefacts/plans"
mkdir -p "$IMPL_WORKTREE/.gaai/project/contexts/artefacts/impl-reports"
mkdir -p "$IMPL_WORKTREE/.delivery-logs"

IMPL_STORY_PATH="$IMPL_WORKTREE/.gaai/project/contexts/artefacts/stories/${IMPL_STORY_ID}.story.md"
IMPL_PLAN_PATH="$IMPL_WORKTREE/.gaai/project/contexts/artefacts/plans/${IMPL_STORY_ID}.execution-plan.md"
IMPL_REPORT_PATH="$IMPL_WORKTREE/.gaai/project/contexts/artefacts/impl-reports/${IMPL_STORY_ID}.impl-report.md"

cat > "$IMPL_STORY_PATH" << 'IMPL_STORY_EOF'
---
type: artefact
artefact_type: story
id: TST-IMPL-01
related_decs: []
---
## Acceptance Criteria
- [ ] AC1: test impl phase
IMPL_STORY_EOF

printf '## Implementation Sequence\nStep 1: do the thing.\n' > "$IMPL_PLAN_PATH"

# Add TST-IMPL-01 to fixture YAML with phase_status: planned
cat >> "$FIXTURE" << 'YAML_IMPL'
- id: TST-IMPL-01
  status: in_progress
  phase_status: planned
  delivery_pipeline: 3phase
  impl_model: primary
YAML_IMPL

# node shim dir for T15-T21 (separate from T4-T8 shim)
IMPL_SHIM_DIR="$IMPL_FIXTURE_DIR/shims"
mkdir -p "$IMPL_SHIM_DIR"

IMPL_REAL_NODE="$(command -v node)"
IMPL_SPAWN_STUB="$SCRIPT_DIR/helpers/impl-spawn-stub.mjs"
export IMPL_REAL_NODE IMPL_SPAWN_STUB

# claude stub: findCLI() inside nested-claude-spawn.js must find a 'claude' binary.
# _setSpawnFn intercepts the actual spawn so this stub is never really executed.
cat > "$IMPL_SHIM_DIR/claude" << 'IMPL_CLAUDE_STUB'
#!/usr/bin/env bash
exit 1
IMPL_CLAUDE_STUB
chmod +x "$IMPL_SHIM_DIR/claude"

make_impl_node_shim_success() {
  cat > "$IMPL_SHIM_DIR/node" << 'IMPL_NODE_SUCCESS_EOF'
#!/usr/bin/env bash
if [[ "$1" == *nested-claude-spawn.js* ]]; then
  exec "$IMPL_REAL_NODE" "$IMPL_SPAWN_STUB" "${@:2}" --stub-success true
fi
exec "$IMPL_REAL_NODE" "$@"
IMPL_NODE_SUCCESS_EOF
  chmod +x "$IMPL_SHIM_DIR/node"
}

make_impl_node_shim_failure() {
  cat > "$IMPL_SHIM_DIR/node" << 'IMPL_NODE_FAIL_EOF'
#!/usr/bin/env bash
if [[ "$1" == *nested-claude-spawn.js* ]]; then
  exec "$IMPL_REAL_NODE" "$IMPL_SPAWN_STUB" "${@:2}" --stub-success false --stub-error-reason FALLBACK_EXHAUSTED
fi
exec "$IMPL_REAL_NODE" "$@"
IMPL_NODE_FAIL_EOF
  chmod +x "$IMPL_SHIM_DIR/node"
}

IMPL_OLD_PATH="$PATH"
export PATH="$IMPL_SHIM_DIR:$PATH"
export GAAI_WORKTREES_BASE="$IMPL_FIXTURE_DIR"
export PROJECT_DIR_IMPL_ORIG="$PROJECT_DIR"

# ── T15: handle_impl_phase success path ──────────────────────
echo "T15: handle_impl_phase — success path (real runImpl via _setSpawnFn)"
make_impl_node_shim_success
"$SCHEDULER" --set-phase-status "$IMPL_STORY_ID" planned "$FIXTURE" 2>/dev/null || true
rm -f "$IMPL_REPORT_PATH"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-015"

if handle_impl_phase "$IMPL_STORY_ID" "$TRACE" 2>/dev/null; then
  pass "T15a: handle_impl_phase returns 0 on success"
  new_ps=$(get_phase_status "$IMPL_STORY_ID")
  if [[ "$new_ps" == "implemented" ]]; then
    pass "T15b: phase_status advanced to 'implemented'"
  else
    fail "T15b: expected 'implemented', got '$new_ps'"
  fi
  if [[ -f "$IMPL_REPORT_PATH" ]]; then
    pass "T15c: impl-report.md written at canonical path"
  else
    fail "T15c: impl-report.md missing at $IMPL_REPORT_PATH"
  fi
else
  fail "T15a: handle_impl_phase returned non-zero"
  fail "T15b: (skipped — T15a failed)"
  fail "T15c: (skipped — T15a failed)"
fi

# ── T16: impl-spawn-stub.mjs exercises real runImpl routing (AC6.a) ──
echo "T16: impl-spawn-stub.mjs — real runImpl routing with _setSpawnFn (primary path)"
IMPL_STUB_REPORT="$IMPL_FIXTURE_DIR/stub-direct-report.md"
rm -f "$IMPL_STUB_REPORT"
STUB_PROMPT_FILE=$(mktemp /tmp/gaai-test-prompt-XXXXXX)
printf '=== STORY: TST-IMPL-01 ===\nTest story content.\n=== EXECUTION PLAN ===\nStep 1.\n' > "$STUB_PROMPT_FILE"

STUB_RESULT=$(
  "$IMPL_REAL_NODE" "$IMPL_SPAWN_STUB" \
    --story-id "$IMPL_STORY_ID" \
    --report-path "$IMPL_STUB_REPORT" \
    --prompt-file "$STUB_PROMPT_FILE" \
    --impl-model-tag primary \
    --stub-success true \
    2>/dev/null || echo '{"success":false}'
)
rm -f "$STUB_PROMPT_FILE"

STUB_SUCCESS=$(printf '%s\n' "$STUB_RESULT" | python3 -c "
import sys, json
data = sys.stdin.read()
d = None
idx = data.rfind('\n{')
if idx >= 0:
    try: d = json.loads(data[idx + 1:])
    except Exception: pass
if d is None:
    for l in reversed(data.splitlines()):
        l = l.strip()
        if not l: continue
        try: d = json.loads(l); break
        except Exception: continue
print(d.get('success', False) if d is not None else False)
" 2>/dev/null || echo "False")

if [[ "$STUB_SUCCESS" == "True" ]]; then
  pass "T16a: impl-spawn-stub.mjs reports success:true (runImpl primary path)"
else
  fail "T16a: impl-spawn-stub.mjs did not report success:true — result: $(printf '%s\n' "$STUB_RESULT" | tail -5)"
fi
if [[ -f "$IMPL_STUB_REPORT" ]]; then
  pass "T16b: impl-spawn-stub.mjs wrote impl-report.md"
else
  fail "T16b: impl-report.md not written by stub at $IMPL_STUB_REPORT"
fi
rm -f "$IMPL_STUB_REPORT"

# ── T17: story file missing → error path ─────────────────────
echo "T17: handle_impl_phase — story file missing → non-zero, no phase advance"
"$SCHEDULER" --set-phase-status "$IMPL_STORY_ID" planned "$FIXTURE" 2>/dev/null || true
mv "$IMPL_STORY_PATH" "${IMPL_STORY_PATH}.bak"
TRACE="test-trace-$(date +%s)-017"

if handle_impl_phase "$IMPL_STORY_ID" "$TRACE" 2>/dev/null; then
  fail "T17a: expected non-zero when story file missing, got 0"
  fail "T17b: (skipped)"
else
  pass "T17a: handle_impl_phase returns non-zero when story file missing"
  new_ps=$(get_phase_status "$IMPL_STORY_ID")
  if [[ "$new_ps" == "planned" ]]; then
    pass "T17b: phase_status unchanged (planned) after missing-story error"
  else
    fail "T17b: expected 'planned', got '$new_ps'"
  fi
fi
mv "${IMPL_STORY_PATH}.bak" "$IMPL_STORY_PATH"

# ── T18: plan file missing → error path ──────────────────────
echo "T18: handle_impl_phase — plan file missing → non-zero, no phase advance"
"$SCHEDULER" --set-phase-status "$IMPL_STORY_ID" planned "$FIXTURE" 2>/dev/null || true
mv "$IMPL_PLAN_PATH" "${IMPL_PLAN_PATH}.bak"
TRACE="test-trace-$(date +%s)-018"

if handle_impl_phase "$IMPL_STORY_ID" "$TRACE" 2>/dev/null; then
  fail "T18a: expected non-zero when plan file missing, got 0"
  fail "T18b: (skipped)"
else
  pass "T18a: handle_impl_phase returns non-zero when plan file missing"
  new_ps=$(get_phase_status "$IMPL_STORY_ID")
  if [[ "$new_ps" == "planned" ]]; then
    pass "T18b: phase_status unchanged (planned) after missing-plan error"
  else
    fail "T18b: expected 'planned', got '$new_ps'"
  fi
fi
mv "${IMPL_PLAN_PATH}.bak" "$IMPL_PLAN_PATH"

# ── T19: stub returns failure JSON → no phase advance (AC6.e) ──
echo "T19: handle_impl_phase — stub returns success:false → no advance, error logged"
make_impl_node_shim_failure
"$SCHEDULER" --set-phase-status "$IMPL_STORY_ID" planned "$FIXTURE" 2>/dev/null || true
rm -f "$IMPL_REPORT_PATH"
TRACE="test-trace-$(date +%s)-019"

T19_OUTPUT=$(handle_impl_phase "$IMPL_STORY_ID" "$TRACE" 2>&1 || true)

new_ps=$(get_phase_status "$IMPL_STORY_ID")
if [[ "$new_ps" == "planned" ]]; then
  pass "T19a: phase_status unchanged (planned) when impl fails"
else
  fail "T19a: expected 'planned', got '$new_ps'"
fi
if echo "$T19_OUTPUT" | grep -q '\[ERROR\]'; then
  pass "T19b: [ERROR] line logged on impl failure"
else
  fail "T19b: expected [ERROR] line in output — got: $(echo "$T19_OUTPUT" | head -3)"
fi

# ── T20: primary routing confirmed via impl-spawn-stub ──
echo "T20: primary routing — impl-spawn-stub with primary tag outputs success"
make_impl_node_shim_success
STUB_PROMPT_FILE_T20=$(mktemp /tmp/gaai-test-prompt-XXXXXX)
printf '=== STORY: TST-IMPL-01 ===\nTest.\n=== EXECUTION PLAN ===\nStep 1.\n' > "$STUB_PROMPT_FILE_T20"
STUB_REPORT_T20="$IMPL_FIXTURE_DIR/t20-report.md"

T20_RESULT=$(
  "$IMPL_REAL_NODE" "$IMPL_SPAWN_STUB" \
    --story-id "$IMPL_STORY_ID" \
    --report-path "$STUB_REPORT_T20" \
    --prompt-file "$STUB_PROMPT_FILE_T20" \
    --impl-model-tag primary \
    --stub-success true \
    2>/dev/null || echo '{"success":false}'
)
rm -f "$STUB_PROMPT_FILE_T20" "$STUB_REPORT_T20"

T20_SUCCESS=$(printf '%s\n' "$T20_RESULT" | python3 -c "
import sys, json
data = sys.stdin.read()
d = None
idx = data.rfind('\n{')
if idx >= 0:
    try: d = json.loads(data[idx + 1:])
    except Exception: pass
if d is None:
    for l in reversed(data.splitlines()):
        l = l.strip()
        if not l: continue
        try: d = json.loads(l); break
        except Exception: continue
print(d.get('success', False) if d is not None else False)
" 2>/dev/null || echo "False")

if [[ "$T20_SUCCESS" == "True" ]]; then
  pass "T20: primary routing — runImpl(primary) reports success:true"
else
  fail "T20: expected success:true (primary routing), got: $(printf '%s\n' "$T20_RESULT" | tail -3)"
fi

# ── T21: daemon-prompt-construct.sh preamble when SECONDARY_ROUTE=true (AC6.b) ──
echo "T21: daemon-prompt-construct.sh — SECONDARY_ROUTE=true emits R1-R6 preamble"
GOLDEN_FIXTURE="$SCRIPT_DIR/fixtures/impl-phase-prompt-preamble.golden.md"
if [[ ! -f "$GOLDEN_FIXTURE" ]]; then
  fail "T21: golden fixture missing at $GOLDEN_FIXTURE"
else
  PROMPT_CONSTRUCT="$SCRIPT_DIR/../daemon-prompt-construct.sh"
  T21_OUTPUT=$(
    GAAI_STORY_ID="$IMPL_STORY_ID" \
    GAAI_STORY_PATH="$IMPL_STORY_PATH" \
    GAAI_PLAN_PATH="$IMPL_PLAN_PATH" \
    GAAI_EPIC_PATH="" \
    GAAI_WORKSPACE_PATH="$IMPL_WORKTREE" \
    SECONDARY_ROUTE="true" \
    PROJECT_DIR="$PROJECT_DIR" \
    bash "$PROMPT_CONSTRUCT" 2>/dev/null || echo ""
  )
  T21_FAIL=0
  while IFS= read -r _marker; do
    [[ -z "$_marker" ]] && continue
    if ! printf '%s\n' "$T21_OUTPUT" | grep -qF "$_marker"; then
      fail "T21: preamble marker missing: '$_marker'"
      T21_FAIL=1
    fi
  done < "$GOLDEN_FIXTURE"
  if [[ "$T21_FAIL" -eq 0 ]]; then
    pass "T21: daemon-prompt-construct.sh output contains all R1-R6 preamble markers"
  fi
  unset _marker
fi

# Cleanup impl phase test fixtures
export PATH="$IMPL_OLD_PATH"
unset GAAI_WORKTREES_BASE IMPL_OLD_PATH IMPL_REAL_NODE IMPL_SPAWN_STUB
unset IMPL_STORY_ID IMPL_WORKTREE IMPL_STORY_PATH IMPL_PLAN_PATH IMPL_REPORT_PATH
unset IMPL_FIXTURE_DIR IMPL_SHIM_DIR
rm -rf "/tmp/gaai-impl-phase-tests-$$"

# ── T22-T29: handle_qa_phase real spawn tests ─────────────────
# These tests exercise handle_qa_phase directly using a claude shim that
# writes various QA report verdicts to GAAI_QA_REPORT_PATH.

QA_FIXTURE_DIR="/tmp/gaai-qa-phase-tests-$$"
rm -rf "$QA_FIXTURE_DIR"
mkdir -p "$QA_FIXTURE_DIR"

# QA phase uses GAAI_WORKTREES_BASE/${story_id}-workspace layout
export GAAI_WORKTREES_BASE="$QA_FIXTURE_DIR"
export CLAUDE_MODEL_PRIMARY="claude-sonnet-4-6"
export GAAI_WORKSPACE_ID="test-workspace"
export GAAI_ORG_ID="test-org"

# Helper: create worktree fixture for a QA story ID
make_qa_worktree() {
  local sid="$1"
  local wt="$QA_FIXTURE_DIR/${sid}-workspace"
  mkdir -p "$wt/.gaai/project/contexts/artefacts/stories"
  mkdir -p "$wt/.gaai/project/contexts/artefacts/plans"
  mkdir -p "$wt/.gaai/project/contexts/artefacts/impl-reports"
  mkdir -p "$wt/.gaai/project/contexts/artefacts/qa-reports"
  mkdir -p "$wt/.gaai/project/contexts/artefacts/memory-deltas"
  mkdir -p "$wt/.delivery-logs"
  cat > "$wt/.gaai/project/contexts/artefacts/stories/${sid}.story.md" << QASTORY_EOF
---
type: artefact
artefact_type: story
id: ${sid}
related_decs: []
---
## Acceptance Criteria
- [ ] AC1: test qa phase
QASTORY_EOF
  printf '## Implementation Sequence\nStep 1: test.\n' \
    > "$wt/.gaai/project/contexts/artefacts/plans/${sid}.execution-plan.md"
  printf -- '---\nartefact_type: impl-report\nid: %s\n---\n## Summary\nImpl done.\n' "$sid" \
    > "$wt/.gaai/project/contexts/artefacts/impl-reports/${sid}.impl-report.md"
}

# claude shim dir for QA tests
QA_SHIM_DIR="$QA_FIXTURE_DIR/shims"
mkdir -p "$QA_SHIM_DIR"

# Helper: write claude shim that emits a specific verdict — writes BOTH the
# Markdown report AND a matching, internally-valid DEC-200 JSON sidecar
# (handle_qa_phase now fails closed when the JSON handoff is missing/invalid,
# per E1096S01). These QA fixture worktrees have no git repo and no Story
# "## File Inventory" / PLAN "Files" column, so the daemon's derived expected-
# surface set is empty — an empty changed_surface_inventory is the exact
# match, keeping this shim simple.
make_qa_claude_shim() {
  local verdict="$1"
  local route replan
  case "$verdict" in
    PASS) route="null"; replan="null" ;;
    FAIL) route="\"impl\""; replan="false" ;;
    ESCALATE) route="\"human\""; replan="null" ;;
  esac
  cat > "$QA_SHIM_DIR/claude" << QASHIM_EOF
#!/usr/bin/env bash
if [[ -n "\${GAAI_QA_VERDICT_PATH:-}" ]]; then
  printf '{"schema_version":1,"story_id":"%s","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"$verdict","plan_conformance":"$verdict","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"$verdict","remediation_route":$route,"replan_required":$replan,"report_path":"qa-reports/%s.qa-report.md"}' "\${GAAI_STORY_ID:-}" "\${GAAI_STORY_ID:-}" > "\$GAAI_QA_VERDICT_PATH"
fi
if [[ -n "\${GAAI_QA_REPORT_PATH:-}" ]]; then
  printf '## AC1\npass\n\n## Verdict: %s\n' "$verdict" > "\$GAAI_QA_REPORT_PATH"
fi
exit 0
QASHIM_EOF
  chmod +x "$QA_SHIM_DIR/claude"
}

# claude shim that exits non-zero (spawn error)
make_qa_claude_fail_shim() {
  cat > "$QA_SHIM_DIR/claude" << 'QAFAIL_EOF'
#!/usr/bin/env bash
exit 1
QAFAIL_EOF
  chmod +x "$QA_SHIM_DIR/claude"
}

# claude shim that exits 0 but writes nothing (artefact missing)
make_qa_claude_noartefact_shim() {
  cat > "$QA_SHIM_DIR/claude" << 'QANO_EOF'
#!/usr/bin/env bash
exit 0
QANO_EOF
  chmod +x "$QA_SHIM_DIR/claude"
}

# claude shim that exits 0 but writes a report without a verdict marker.
# Writes a valid JSON sidecar too, so this fixture still isolates the
# Markdown-verdict-marker-absent path (AC5c) rather than tripping the prior
# QA_HANDOFF_INVALID gate.
make_qa_claude_badverdict_shim() {
  cat > "$QA_SHIM_DIR/claude" << QABADVERDICT_EOF
#!/usr/bin/env bash
if [[ -n "\${GAAI_QA_VERDICT_PATH:-}" ]]; then
  printf '{"schema_version":1,"story_id":"%s","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"PASS","plan_conformance":"PASS","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"PASS","remediation_route":null,"replan_required":null,"report_path":"qa-reports/%s.qa-report.md"}' "\${GAAI_STORY_ID:-}" "\${GAAI_STORY_ID:-}" > "\$GAAI_QA_VERDICT_PATH"
fi
if [[ -n "\${GAAI_QA_REPORT_PATH:-}" ]]; then
  printf '## AC1\npass\n\nNo verdict marker here.\n' > "\${GAAI_QA_REPORT_PATH}"
fi
exit 0
QABADVERDICT_EOF
  chmod +x "$QA_SHIM_DIR/claude"
}

QA_OLD_PATH="$PATH"
export PATH="$QA_SHIM_DIR:$PATH"
export PROJECT_DIR_QA_ORIG="$PROJECT_DIR"
export PROJECT_DIR="$SCRIPT_DIR/../../../.."

# Create worktrees for all QA story IDs
for _qsid in TST-QA-PASS TST-QA-FAIL TST-QA-ESCALATE TST-QA-SPAWN-ERR; do
  make_qa_worktree "$_qsid"
done
unset _qsid

# ── T22: QA PASS verdict → qa_passed ─────────────────────────
echo "T22: handle_qa_phase — PASS verdict → qa_passed"
make_qa_claude_shim "PASS"
"$SCHEDULER" --set-phase-status "TST-QA-PASS" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-022"

if handle_qa_phase "TST-QA-PASS" "$TRACE" 2>/dev/null; then
  new_ps=$(get_phase_status "TST-QA-PASS")
  if [[ "$new_ps" == "qa_passed" ]]; then
    pass "T22a: phase_status advanced to 'qa_passed' on PASS verdict"
  else
    fail "T22a: expected 'qa_passed', got '$new_ps'"
  fi
  if grep -q '"phase":"qa"' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"provider":"primary"' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"pipeline":"3phase"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T22b: routing.jsonl has qa+primary+pipeline:3phase record"
  else
    fail "T22b: routing.jsonl missing expected fields — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
  # AC5 fix: the DEC-200 validator summary reaches the structured audit record
  # (runtime-routing.jsonl), not only an ad hoc stdout echo.
  if grep -q '"qa_summary":{' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"verdict":"PASS"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T22c: routing.jsonl has qa_summary with verdict=PASS"
  else
    fail "T22c: routing.jsonl missing qa_summary — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T22a: handle_qa_phase returned non-zero for PASS verdict"
  fail "T22b: (skipped — T22a failed)"
  fail "T22c: (skipped — T22a failed)"
fi

# ── T23: QA FAIL verdict → qa_failed ─────────────────────────
echo "T23: handle_qa_phase — FAIL verdict → qa_failed"
make_qa_claude_shim "FAIL"
"$SCHEDULER" --set-phase-status "TST-QA-FAIL" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-023"

if handle_qa_phase "TST-QA-FAIL" "$TRACE" 2>/dev/null; then
  new_ps=$(get_phase_status "TST-QA-FAIL")
  if [[ "$new_ps" == "qa_failed" ]]; then
    pass "T23a: phase_status advanced to 'qa_failed' on FAIL verdict"
  else
    fail "T23a: expected 'qa_failed', got '$new_ps'"
  fi
  if grep -q '"fallback_reason":"QA_VERDICT:FAIL"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T23b: routing.jsonl has QA_VERDICT:FAIL fallback_reason"
  else
    fail "T23b: routing.jsonl missing QA_VERDICT:FAIL — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
  if grep -q '"qa_summary":{' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"verdict":"FAIL"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T23c: routing.jsonl has qa_summary with verdict=FAIL (AC5: FAIL branch carries structured summary too)"
  else
    fail "T23c: routing.jsonl missing qa_summary — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T23a: handle_qa_phase returned non-zero for FAIL verdict; retry-loop convention expects qa_failed + rc=0"
  fail "T23b: (skipped)"
  fail "T23c: (skipped)"
fi

# ── T24: QA ESCALATE verdict → qa_escalated ──────────────────
echo "T24: handle_qa_phase — ESCALATE verdict → qa_escalated"
make_qa_claude_shim "ESCALATE"
"$SCHEDULER" --set-phase-status "TST-QA-ESCALATE" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-024"

if handle_qa_phase "TST-QA-ESCALATE" "$TRACE" 2>/dev/null; then
  fail "T24a: expected non-zero return for ESCALATE verdict, got 0"
  fail "T24b: (skipped)"
else
  new_ps=$(get_phase_status "TST-QA-ESCALATE")
  if [[ "$new_ps" == "qa_escalated" ]]; then
    pass "T24a: phase_status advanced to 'qa_escalated' on ESCALATE verdict"
  else
    fail "T24a: expected 'qa_escalated', got '$new_ps'"
  fi
  if grep -q '"fallback_reason":"QA_VERDICT:ESCALATE"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T24b: routing.jsonl has QA_VERDICT:ESCALATE fallback_reason"
  else
    fail "T24b: routing.jsonl missing QA_VERDICT:ESCALATE — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
  if grep -q '"qa_summary":{' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"verdict":"ESCALATE"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T24c: routing.jsonl has qa_summary with verdict=ESCALATE (AC5: ESCALATE branch carries structured summary too)"
  else
    fail "T24c: routing.jsonl missing qa_summary — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
fi

# ── T25: spawn error (claude exits 1) → return 1, no phase advance ──
echo "T25: handle_qa_phase — spawn error → no phase advance (AC5a)"
make_qa_claude_fail_shim
"$SCHEDULER" --set-phase-status "TST-QA-SPAWN-ERR" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-025"

if handle_qa_phase "TST-QA-SPAWN-ERR" "$TRACE" 2>/dev/null; then
  fail "T25a: expected non-zero return for spawn error, got 0"
  fail "T25b: (skipped)"
else
  new_ps=$(get_phase_status "TST-QA-SPAWN-ERR")
  if [[ "$new_ps" == "implemented" ]]; then
    pass "T25a: phase_status unchanged (implemented) after spawn error"
  else
    fail "T25a: expected 'implemented', got '$new_ps'"
  fi
  if grep -q '"fallback_reason":"QA_SPAWN_FAILED"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T25b: routing.jsonl has QA_SPAWN_FAILED fallback_reason"
  else
    fail "T25b: routing.jsonl missing QA_SPAWN_FAILED — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
fi

# ── T26: artefact missing (exit 0, no report) → return 1, no phase advance (AC5b) ──
echo "T26: handle_qa_phase — artefact missing → no phase advance (AC5b)"
make_qa_claude_noartefact_shim
"$SCHEDULER" --set-phase-status "TST-QA-SPAWN-ERR" implemented "$FIXTURE" 2>/dev/null || true
# Remove qa-report if it exists from prior test
rm -f "$QA_FIXTURE_DIR/TST-QA-SPAWN-ERR-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QA-SPAWN-ERR.qa-report.md"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-026"

if handle_qa_phase "TST-QA-SPAWN-ERR" "$TRACE" 2>/dev/null; then
  fail "T26a: expected non-zero when artefact missing, got 0"
  fail "T26b: (skipped)"
else
  new_ps=$(get_phase_status "TST-QA-SPAWN-ERR")
  if [[ "$new_ps" == "implemented" ]]; then
    pass "T26a: phase_status unchanged (implemented) when artefact missing"
  else
    fail "T26a: expected 'implemented', got '$new_ps'"
  fi
  if grep -q '"fallback_reason":"QA_NO_ARTEFACT"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T26b: routing.jsonl has QA_NO_ARTEFACT fallback_reason"
  else
    fail "T26b: routing.jsonl missing QA_NO_ARTEFACT — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
fi

# ── T27: verdict parse error → immediate failed, no retry (AC5c) ──
echo "T27: handle_qa_phase — verdict parse error → story marked 'failed' immediately (AC5c)"
make_qa_claude_badverdict_shim
"$SCHEDULER" --set-phase-status "TST-QA-SPAWN-ERR" implemented "$FIXTURE" 2>/dev/null || true
rm -f "$QA_FIXTURE_DIR/TST-QA-SPAWN-ERR-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QA-SPAWN-ERR.qa-report.md"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-027"

if handle_qa_phase "TST-QA-SPAWN-ERR" "$TRACE" 2>/dev/null; then
  fail "T27a: expected non-zero for verdict parse error, got 0"
  fail "T27b: (skipped)"
else
  new_ps=$(get_phase_status "TST-QA-SPAWN-ERR")
  if [[ "$new_ps" == "failed" ]]; then
    pass "T27a: story immediately marked 'failed' on verdict parse error (AC5c)"
  else
    fail "T27a: expected 'failed' after verdict parse error, got '$new_ps'"
  fi
  if grep -q '"fallback_reason":"QA_VERDICT_PARSE_ERROR"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T27b: routing.jsonl has QA_VERDICT_PARSE_ERROR fallback_reason"
  else
    fail "T27b: routing.jsonl missing QA_VERDICT_PARSE_ERROR — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
fi

# ── T28: scheduler VALID set includes qa_failed + qa_escalated ──
echo "T28: backlog-scheduler.sh VALID set includes qa_failed + qa_escalated"
# Add a scratch story to fixture YAML
cat >> "$FIXTURE" << 'YAML_SCHED'
- id: TST-SCHED-VALID
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
YAML_SCHED

T28_FAIL=0
if "$SCHEDULER" --set-phase-status "TST-SCHED-VALID" qa_failed "$FIXTURE" 2>/dev/null; then
  new_ps=$(get_phase_status "TST-SCHED-VALID")
  if [[ "$new_ps" == "qa_failed" ]]; then
    pass "T28a: scheduler accepts and persists qa_failed"
  else
    fail "T28a: scheduler accepted qa_failed but phase_status='$new_ps'"
    T28_FAIL=1
  fi
else
  fail "T28a: scheduler rejected qa_failed — not in VALID set"
  T28_FAIL=1
fi

if "$SCHEDULER" --set-phase-status "TST-SCHED-VALID" qa_escalated "$FIXTURE" 2>/dev/null; then
  new_ps=$(get_phase_status "TST-SCHED-VALID")
  if [[ "$new_ps" == "qa_escalated" ]]; then
    pass "T28b: scheduler accepts and persists qa_escalated"
  else
    fail "T28b: scheduler accepted qa_escalated but phase_status='$new_ps'"
  fi
else
  fail "T28b: scheduler rejected qa_escalated — not in VALID set"
fi

# ── T29: dispatch on qa_failed/qa_escalated returns 0 (terminal states) ──
echo "T29: dispatch_3phase_story — qa_failed/qa_escalated are terminal (return 0)"
# TST-QA-FAIL is now qa_failed, TST-QA-ESCALATE is now qa_escalated
TRACE="test-trace-$(date +%s)-029"

if dispatch_3phase_story "TST-QA-FAIL" "$TRACE" 2>/dev/null; then
  pass "T29a: dispatch returns 0 for qa_failed terminal state"
else
  fail "T29a: dispatch returned non-zero for qa_failed — should be terminal"
fi

if dispatch_3phase_story "TST-QA-ESCALATE" "$TRACE" 2>/dev/null; then
  pass "T29b: dispatch returns 0 for qa_escalated terminal state"
else
  fail "T29b: dispatch returned non-zero for qa_escalated — should be terminal"
fi

# ── T29c: complete AC4 rejection matrix blocks every QA spawn ─────────────
echo "T29c: every typed local-admission rejection blocks semantic QA spend"
QA_ADMISSION_SPEND_LOG="$QA_FIXTURE_DIR/admission-spend.log"
PRE_QA_BEFORE_AC4_MATRIX=$(declare -f _prepare_pre_qa_admission)
cat > "$QA_SHIM_DIR/claude" <<QA_ADMISSION_SHIM
#!/usr/bin/env bash
printf 'spawned\n' >> "$QA_ADMISSION_SPEND_LOG"
exit 99
QA_ADMISSION_SHIM
chmod +x "$QA_SHIM_DIR/claude"
_prepare_pre_qa_admission() {
  _route_admission_block "$1" "$2" pre_qa "$_AC4_MATRIX_OUTCOME"
  return 1
}
AC4_MATRIX=(
  blocked:risk_inputs_missing
  blocked:risk_input_unresolved
  blocked:stale_evidence
  blocked:candidate_stale
  blocked:candidate_unsealed
  blocked:candidate_path_unsafe
  blocked:policy_missing
  blocked:policy_malformed
  blocked:policy_unsafe
  blocked:policy_ambiguous
  blocked:repository_mismatch
  blocked:configuration_unresolved
  blocked:configuration_unsafe
  blocked:command_unresolved
  blocked:environment_fact_missing
  blocked:empty_executable_selection
  blocked:unknown_surface
  blocked:unknown_executable_surface
  blocked:adapter_semantic_mismatch
  blocked:command_skipped
  blocked:command_cancelled
  blocked:command_timed_out
  blocked:command_failed
)
for _matrix_outcome in "${AC4_MATRIX[@]}"; do
  _AC4_MATRIX_OUTCOME="$_matrix_outcome"
  : > "$QA_ADMISSION_SPEND_LOG"
  "$SCHEDULER" --set-phase-status TST-QA-SPAWN-ERR implemented "$FIXTURE" 2>/dev/null || true
  > "$ROUTING_LOG"
  handle_qa_phase TST-QA-SPAWN-ERR "trace-${_matrix_outcome//[:_]/-}" >/dev/null 2>&1 || true
  if [[ ! -s "$QA_ADMISSION_SPEND_LOG" ]] \
      && grep -q "\"fallback_reason\":\"${_matrix_outcome}\"" "$ROUTING_LOG"; then
    pass "T29c ${_matrix_outcome}: typed route emitted and no QA model spawned"
  else
    fail "T29c ${_matrix_outcome}: rejection reached model spend or lost its typed route"
  fi
done
eval "$PRE_QA_BEFORE_AC4_MATRIX"
unset _matrix_outcome _AC4_MATRIX_OUTCOME QA_ADMISSION_SPEND_LOG
unset PRE_QA_BEFORE_AC4_MATRIX

# Cleanup QA phase test fixtures
export PATH="$QA_OLD_PATH"
export PROJECT_DIR="$PROJECT_DIR_QA_ORIG"
unset GAAI_WORKTREES_BASE CLAUDE_MODEL_PRIMARY GAAI_WORKSPACE_ID GAAI_ORG_ID
unset QA_OLD_PATH QA_FIXTURE_DIR QA_SHIM_DIR PROJECT_DIR_QA_ORIG
rm -rf "/tmp/gaai-qa-phase-tests-$$"

# ── T30-T44: handle_commit_phase tests ────────────────────────
# Tests for the real commit phase implementation:
# git commit, push, gh pr create, auto-merge policy, routing record.

COMMIT_FIXTURE_DIR="/tmp/gaai-commit-phase-tests-$$"
rm -rf "$COMMIT_FIXTURE_DIR"
mkdir -p "$COMMIT_FIXTURE_DIR"

export GAAI_WORKTREES_BASE="$COMMIT_FIXTURE_DIR"

# Add commit-phase story IDs to fixture YAML
cat >> "$FIXTURE" << 'YAML_COMMIT'
- id: TST-COMMIT-01
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
  title: "Implement commit phase handler"
  impl_model: primary
- id: TST-COMMIT-NOTITLE
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
  impl_model: primary
- id: TST-COMMIT-AUTOMERGE
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
  title: "Auto-merge story"
  impl_model: primary
- id: TST-COMMIT-SKIPMERGE
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
  title: "Skip auto-merge story"
  impl_model: primary
- id: TST-COMMIT-PUSHFAIL
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
  title: "Push fail story"
  impl_model: primary
- id: TST-COMMIT-ALREADY-DONE
  status: in_progress
  phase_status: done
  delivery_pipeline: 3phase
  title: "Already done story"
  impl_model: primary
- id: TST-COMMIT-GUARD1
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
  title: "Guard 1 ancestor test story"
  impl_model: primary
- id: TST-COMMIT-GUARD2
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
  title: "Guard 2 merged PR test story"
  impl_model: primary
YAML_COMMIT

# Helper: create a real git worktree with optional story auto_merge frontmatter
make_commit_worktree() {
  local sid="$1" auto_merge_val="${2:-}"
  local wt="$COMMIT_FIXTURE_DIR/${sid}-workspace"
  # Idempotent: several tests re-create the same worktree to reset it for a
  # re-run. Start from a clean slate so a prior commit-phase run's mutations
  # never leak into the next.
  rm -rf "$wt" "${wt%/}.origin.git" 2>/dev/null || true
  mkdir -p "$wt/.gaai/project/contexts/artefacts/stories"
  mkdir -p "$wt/.gaai/project/contexts/artefacts/qa-reports"
  {
    echo "---"
    echo "type: artefact"
    echo "artefact_type: story"
    echo "id: ${sid}"
    [[ -n "$auto_merge_val" ]] && echo "auto_merge: ${auto_merge_val}"
    echo "related_decs: []"
    echo "---"
    echo "## Acceptance Criteria"
    echo "- [ ] AC1: test"
  } > "$wt/.gaai/project/contexts/artefacts/stories/${sid}.story.md"
  printf '## AC1\npass\n\n## Verdict: PASS\n' \
    > "$wt/.gaai/project/contexts/artefacts/qa-reports/${sid}.qa-report.md"
  git -C "$wt" init -q
  git -C "$wt" config user.email "test@example.com"
  git -C "$wt" config user.name "Test"
  git -C "$wt" commit --allow-empty -m "init" --quiet
  git -C "$wt" checkout -B "story/${sid}" -q
  # origin/staging baseline = the init commit -> the commit test-gate's
  # differential diff (origin/staging...HEAD) is a clean no-op for these fixtures.
  _setup_origin_staging "$wt"
}

# Create worktrees for all commit test stories (TST-COMMIT-SKIPMERGE created separately below)
for _csid in TST-COMMIT-01 TST-COMMIT-NOTITLE TST-COMMIT-AUTOMERGE TST-COMMIT-PUSHFAIL TST-COMMIT-ALREADY-DONE TST-COMMIT-GUARD1 TST-COMMIT-GUARD2; do
  make_commit_worktree "$_csid"
done
# TST-COMMIT-SKIPMERGE gets auto_merge: false frontmatter
make_commit_worktree "TST-COMMIT-SKIPMERGE" "false"
unset _csid

# ── Shim directory for commit tests ──────────────────────────
COMMIT_SHIM_DIR="$COMMIT_FIXTURE_DIR/shims"
mkdir -p "$COMMIT_SHIM_DIR"

# git shim: intercepts 'push', delegates everything else to real git
COMMIT_REAL_GIT="$(command -v git)"
export COMMIT_REAL_GIT GAAI_SHIM_PUSH_FAIL GAAI_SHIM_GH_AUTH_FAIL GAAI_SHIM_GH_PR_EXISTS GAAI_SHIM_HEAD_IS_ANCESTOR GAAI_SHIM_GH_PR_MERGED
export GAAI_COMMIT_PUSH_STATE_FILE="$COMMIT_FIXTURE_DIR/push-state"
export GAAI_SHIM_AUTOMERGE_NULL GAAI_SHIM_AUTOMERGE_FAIL
GAAI_SHIM_PUSH_FAIL=0
GAAI_SHIM_GH_AUTH_FAIL=0
GAAI_SHIM_GH_PR_EXISTS=0
GAAI_SHIM_AUTOMERGE_NULL=0
GAAI_SHIM_AUTOMERGE_FAIL=0
GAAI_SHIM_HEAD_IS_ANCESTOR=0
GAAI_SHIM_GH_PR_MERGED=0

cat > "$COMMIT_SHIM_DIR/git" << 'GIT_SHIM_EOF'
#!/usr/bin/env bash
# Intercept push; delegate everything else to real git binary
_args=("$@")
# Strip -C <path> from front if present, to get the subcommand
_i=0
while [[ $_i -lt ${#_args[@]} ]]; do
  if [[ "${_args[$_i]}" == "-C" ]]; then
    _i=$(( _i + 2 ))
    continue
  fi
  break
done
_subcmd="${_args[$_i]:-}"
if [[ "$_subcmd" == "push" ]]; then
  if [[ "${GAAI_SHIM_PUSH_FAIL:-0}" == "1" ]]; then
    echo "error: remote push failed" >&2; exit 1
  fi
  for _arg in "${_args[@]}"; do
    [[ "$_arg" == *:refs/heads/* ]] && printf '%s\t%s\n' "${_arg%%:*}" "${_arg#*:}" > "$GAAI_COMMIT_PUSH_STATE_FILE"
  done
  exit 0
fi
if [[ "$_subcmd" == "ls-remote" && -s "$GAAI_COMMIT_PUSH_STATE_FILE" ]]; then
  _last=$((${#_args[@]} - 1)); _wanted="${_args[$_last]}"
  IFS=$'\t' read -r _sha _dest < "$GAAI_COMMIT_PUSH_STATE_FILE"
  [[ "$_wanted" == "$_dest" ]] && { printf '%s\t%s\n' "$_sha" "$_dest"; exit 0; }
fi
# Guard 1 shim: intercept merge-base --is-ancestor when flag is set
if [[ "$_subcmd" == "merge-base" ]] && [[ "${GAAI_SHIM_HEAD_IS_ANCESTOR:-0}" == "1" ]]; then
  for _arg in "${_args[@]}"; do
    [[ "$_arg" == "--is-ancestor" ]] && exit 0
  done
fi
# Guard 1 shim: intercept fetch when flag is set (simulates successful fetch)
if [[ "$_subcmd" == "fetch" ]] && [[ "${GAAI_SHIM_HEAD_IS_ANCESTOR:-0}" == "1" ]]; then
  exit 0
fi
exec "$COMMIT_REAL_GIT" "$@"
GIT_SHIM_EOF
chmod +x "$COMMIT_SHIM_DIR/git"

COMMIT_CALL_LOG="$COMMIT_FIXTURE_DIR/gh-calls.log"
export GAAI_COMMIT_MERGE_SHA_FILE="$COMMIT_FIXTURE_DIR/merge-sha"

cat > "$COMMIT_SHIM_DIR/gh" << 'GH_SHIM_EOF'
#!/usr/bin/env bash
# gh shim — configurable mock for PR operations
PR_CREATE_CALLED_FILE="${GAAI_COMMIT_CALL_LOG:-/tmp/gaai-gh-calls.log}"

_args=("$@")
_cmd="${_args[0]:-} ${_args[1]:-}"

case "$_cmd" in
  "api --method")
    if [[ "${GAAI_SHIM_AUTOMERGE_FAIL:-0}" == "1" ]]; then
      echo "merge failed" >&2; exit 1
    fi
    for _arg in "$@"; do
      [[ "$_arg" == sha=* ]] && printf '%s\n' "${_arg#sha=}" > "$GAAI_COMMIT_MERGE_SHA_FILE"
    done
    echo "true"
    exit 0 ;;
  "pr create")
    echo "$@" >> "$PR_CREATE_CALLED_FILE"
    if [[ "${GAAI_SHIM_GH_AUTH_FAIL:-0}" == "1" ]]; then
      echo "GH_TOKEN not set" >&2; exit 1
    fi
    if [[ "${GAAI_SHIM_GH_PR_EXISTS:-0}" == "1" ]]; then
      echo "already exists" >&2; exit 1
    fi
    echo "https://github.com/test/repo/pull/999"
    exit 0 ;;
  "pr view")
    if [[ "$*" == *"--json state,headRefOid"* ]]; then
      merged_sha=$(cat "$GAAI_COMMIT_MERGE_SHA_FILE" 2>/dev/null || true)
      if [[ -n "${TEST_GATE_AUTH_HEAD_SHA:-}" && "$merged_sha" == "$TEST_GATE_AUTH_HEAD_SHA" ]]; then
        printf 'MERGED\t%s\n' "$merged_sha"
      else
        printf 'OPEN\t%s\n' "${TEST_GATE_AUTH_HEAD_SHA:-}"
      fi
      exit 0
    fi
    if [[ "$*" == *"--json url"* ]]; then
      echo "https://github.com/test/repo/pull/999"
      exit 0
    fi
    if [[ "$*" == *"--json number"* ]]; then
      echo "999"
      exit 0
    fi
    if [[ "$*" == *"--json autoMergeRequest"* ]]; then
      if [[ "${GAAI_SHIM_AUTOMERGE_NULL:-0}" == "1" ]]; then
        echo "null"; exit 0
      fi
      echo '{"mergeMethod":"squash"}'; exit 0
    fi
    exit 0 ;;
  "pr list")
    if [[ "${GAAI_SHIM_GH_PR_MERGED:-0}" == "1" ]]; then
      echo "https://github.com/test/repo/pull/888"
    fi
    exit 0 ;;
  "pr merge")
    if [[ "${GAAI_SHIM_AUTOMERGE_FAIL:-0}" == "1" ]]; then
      echo "merge failed" >&2; exit 1
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
GH_SHIM_EOF
chmod +x "$COMMIT_SHIM_DIR/gh"

COMMIT_OLD_PATH="$PATH"
export PATH="$COMMIT_SHIM_DIR:$PATH"
export GAAI_COMMIT_CALL_LOG="$COMMIT_CALL_LOG"

# ── T30: get_story_title helper returns correct title ──────────
echo "T30: get_story_title — returns title from backlog YAML"
_t30_title=$(get_story_title "TST-COMMIT-01")
if [[ "$_t30_title" == "Implement commit phase handler" ]]; then
  pass "T30a: get_story_title returns correct title"
else
  fail "T30a: expected 'Implement commit phase handler', got '$_t30_title'"
fi
_t30_empty=$(get_story_title "TST-COMMIT-NOTITLE")
if [[ -z "$_t30_empty" ]]; then
  pass "T30b: get_story_title returns empty string when title absent"
else
  fail "T30b: expected empty, got '$_t30_empty'"
fi
unset _t30_title _t30_empty

# ── T31: handle_commit_phase success — phase advances to done ──
echo "T31: handle_commit_phase — success path, phase_status → done"
> "$ROUTING_LOG"
> "$COMMIT_CALL_LOG"
"$SCHEDULER" --set-phase-status "TST-COMMIT-01" qa_passed "$FIXTURE" 2>/dev/null || true
GAAI_SHIM_PUSH_FAIL=0
TRACE="test-trace-$(date +%s)-031"

if handle_commit_phase "TST-COMMIT-01" "$TRACE" 2>/dev/null; then
  new_ps=$(get_phase_status "TST-COMMIT-01")
  if [[ "$new_ps" == "done" ]]; then
    pass "T31a: phase_status advanced to 'done'"
  else
    fail "T31a: expected 'done', got '$new_ps'"
  fi
  if grep -q '"phase":"commit"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T31b: routing.jsonl has commit phase record"
  else
    fail "T31b: routing.jsonl missing commit record — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
  if grep -q '"provider":"daemon-bash"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T31c: routing.jsonl has provider:daemon-bash (success path)"
  else
    fail "T31c: routing.jsonl missing provider:daemon-bash — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
  if grep -q '"pipeline":"3phase"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T31d: routing.jsonl has pipeline:3phase"
  else
    fail "T31d: routing.jsonl missing pipeline:3phase — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T31a: handle_commit_phase returned non-zero"
  fail "T31b: (skipped — T31a failed)"
  fail "T31c: (skipped — T31a failed)"
  fail "T31d: (skipped — T31a failed)"
fi

# ── T32: gh pr create called with --base staging ──────────────
echo "T32: gh pr create — called with --base staging"
if grep -q '\-\-base' "$COMMIT_CALL_LOG" 2>/dev/null && grep -q 'staging' "$COMMIT_CALL_LOG" 2>/dev/null; then
  pass "T32: gh pr create was called with --base staging"
else
  fail "T32: expected --base staging in gh call log — content: $(cat "$COMMIT_CALL_LOG" 2>/dev/null | head -3)"
fi

# ── T33: routing record has pr_url field ───────────────────────
echo "T33: routing.jsonl — commit record has pr_url field"
if grep -q '"pr_url"' "$ROUTING_LOG" 2>/dev/null; then
  pass "T33a: routing.jsonl commit record has pr_url field"
else
  fail "T33a: routing.jsonl missing pr_url — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
fi
if grep -q '"auto_merge_applied"' "$ROUTING_LOG" 2>/dev/null; then
  pass "T33b: routing.jsonl commit record has auto_merge_applied field"
else
  fail "T33b: routing.jsonl missing auto_merge_applied — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
fi

# ── T34: idempotency — already done → return 0, no duplicate record ──
echo "T34: handle_commit_phase — already done is idempotent (return 0)"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-034"
if handle_commit_phase "TST-COMMIT-ALREADY-DONE" "$TRACE" 2>/dev/null; then
  pass "T34a: handle_commit_phase returns 0 for already-done story"
  if [[ ! -s "$ROUTING_LOG" ]]; then
    pass "T34b: no routing record emitted for already-done story"
  else
    fail "T34b: routing record emitted for already-done story — should be idempotent"
  fi
else
  fail "T34a: handle_commit_phase returned non-zero for already-done story"
  fail "T34b: (skipped — T34a failed)"
fi

# ── T35: push failure → PUSH_FAILED error record, return 1 ────
echo "T35: handle_commit_phase — git push fails → PUSH_FAILED, no phase advance"
GAAI_SHIM_PUSH_FAIL=1
> "$ROUTING_LOG"
"$SCHEDULER" --set-phase-status "TST-COMMIT-PUSHFAIL" qa_passed "$FIXTURE" 2>/dev/null || true
TRACE="test-trace-$(date +%s)-035"

if handle_commit_phase "TST-COMMIT-PUSHFAIL" "$TRACE" 2>/dev/null; then
  fail "T35a: expected non-zero when push fails, got 0"
  fail "T35b: (skipped)"
else
  new_ps=$(get_phase_status "TST-COMMIT-PUSHFAIL")
  if [[ "$new_ps" == "qa_passed" ]]; then
    pass "T35a: phase_status unchanged (qa_passed) after push failure"
  else
    fail "T35a: expected 'qa_passed', got '$new_ps'"
  fi
  if grep -q '"fallback_reason":"PUSH_FAILED"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T35b: routing.jsonl has PUSH_FAILED fallback_reason"
  else
    fail "T35b: routing.jsonl missing PUSH_FAILED — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
fi
GAAI_SHIM_PUSH_FAIL=0

# ── T36: commit message contains story title (AC1-i) ──────────
echo "T36: commit message contains story title (AC1-i)"
_t36_log=$(git -C "$COMMIT_FIXTURE_DIR/TST-COMMIT-01-workspace" log -1 --format="%s" 2>/dev/null || echo "")
if printf '%s\n' "$_t36_log" | grep -q "TST-COMMIT-01"; then
  pass "T36a: commit subject contains story ID"
else
  fail "T36a: commit subject missing story ID — got: '$_t36_log'"
fi
if printf '%s\n' "$_t36_log" | grep -q "Implement commit phase handler"; then
  pass "T36b: commit subject contains story title"
else
  fail "T36b: commit subject missing story title — got: '$_t36_log'"
fi
unset _t36_log

# ── T37: story with no title falls back to story_id (AC1-i) ───
echo "T37: no title → story_id used as fallback in commit subject"
> "$ROUTING_LOG"
> "$COMMIT_CALL_LOG"
"$SCHEDULER" --set-phase-status "TST-COMMIT-NOTITLE" qa_passed "$FIXTURE" 2>/dev/null || true
TRACE="test-trace-$(date +%s)-037"

if handle_commit_phase "TST-COMMIT-NOTITLE" "$TRACE" 2>/dev/null; then
  _t37_log=$(git -C "$COMMIT_FIXTURE_DIR/TST-COMMIT-NOTITLE-workspace" log -1 --format="%s" 2>/dev/null || echo "")
  if printf '%s\n' "$_t37_log" | grep -q "TST-COMMIT-NOTITLE"; then
    pass "T37: commit subject contains story ID when title absent"
  else
    fail "T37: commit subject missing story ID fallback — got: '$_t37_log'"
  fi
  unset _t37_log
else
  fail "T37: handle_commit_phase returned non-zero for no-title story"
fi

# ── T38: GAAI_SKIP_AUTO_MERGE=1 → [skip-auto-merge] trailer ──
echo "T38: GAAI_SKIP_AUTO_MERGE=1 → [skip-auto-merge] trailer in commit"
> "$ROUTING_LOG"
"$SCHEDULER" --set-phase-status "TST-COMMIT-AUTOMERGE" qa_passed "$FIXTURE" 2>/dev/null || true
GAAI_SKIP_AUTO_MERGE=1
TRACE="test-trace-$(date +%s)-038"

if handle_commit_phase "TST-COMMIT-AUTOMERGE" "$TRACE" 2>/dev/null; then
  _t38_body=$(git -C "$COMMIT_FIXTURE_DIR/TST-COMMIT-AUTOMERGE-workspace" log -1 --format="%B" 2>/dev/null || echo "")
  if printf '%s\n' "$_t38_body" | grep -qE '^\[skip-auto-merge\]$'; then
    pass "T38: [skip-auto-merge] trailer present when GAAI_SKIP_AUTO_MERGE=1"
  else
    fail "T38: [skip-auto-merge] trailer missing — commit body: $(printf '%s\n' "$_t38_body" | head -5)"
  fi
  unset _t38_body
else
  fail "T38: handle_commit_phase returned non-zero"
fi
export GAAI_SKIP_AUTO_MERGE=0

# ── T39: story auto_merge: false → [skip-auto-merge] trailer ──
echo "T39: story auto_merge:false → [skip-auto-merge] trailer in commit"
> "$ROUTING_LOG"
# TST-COMMIT-SKIPMERGE was created with auto_merge: false
"$SCHEDULER" --set-phase-status "TST-COMMIT-SKIPMERGE" qa_passed "$FIXTURE" 2>/dev/null || true
GAAI_SKIP_AUTO_MERGE=0
TRACE="test-trace-$(date +%s)-039"

if handle_commit_phase "TST-COMMIT-SKIPMERGE" "$TRACE" 2>/dev/null; then
  _t39_body=$(git -C "$COMMIT_FIXTURE_DIR/TST-COMMIT-SKIPMERGE-workspace" log -1 --format="%B" 2>/dev/null || echo "")
  if printf '%s\n' "$_t39_body" | grep -qE '^\[skip-auto-merge\]$'; then
    pass "T39: [skip-auto-merge] trailer present when story auto_merge:false"
  else
    fail "T39: [skip-auto-merge] trailer missing — commit body: $(printf '%s\n' "$_t39_body" | head -5)"
  fi
  unset _t39_body
else
  fail "T39: handle_commit_phase returned non-zero for skip-merge story"
fi

# ── T40: GAAI_AUTO_MERGE_POLICY=on → auto_merge_applied=true ─
echo "T40: GAAI_AUTO_MERGE_POLICY=on → auto_merge_applied:true in routing record"
> "$ROUTING_LOG"
# Re-use TST-COMMIT-AUTOMERGE (already done — reset to qa_passed for re-run)
make_commit_worktree "TST-COMMIT-AUTOMERGE"
"$SCHEDULER" --set-phase-status "TST-COMMIT-AUTOMERGE" qa_passed "$FIXTURE" 2>/dev/null || true
GAAI_SKIP_AUTO_MERGE=0
GAAI_AUTO_MERGE_POLICY=on
TRACE="test-trace-$(date +%s)-040"

if handle_commit_phase "TST-COMMIT-AUTOMERGE" "$TRACE" 2>/dev/null; then
  if grep -q '"auto_merge_applied":true' "$ROUTING_LOG" 2>/dev/null; then
    pass "T40a: auto_merge_applied:true in routing record when policy=on"
  else
    fail "T40a: auto_merge_applied:true missing — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
  new_ps=$(get_phase_status "TST-COMMIT-AUTOMERGE")
  if [[ "$new_ps" == "done" ]]; then
    pass "T40b: phase_status still advances to done when auto-merge applied"
  else
    fail "T40b: expected 'done', got '$new_ps'"
  fi
else
  fail "T40a: handle_commit_phase returned non-zero with GAAI_AUTO_MERGE_POLICY=on"
  fail "T40b: (skipped)"
fi
export GAAI_AUTO_MERGE_POLICY=off

# ── T41: GAAI_AUTO_MERGE_POLICY=off → auto_merge_applied:false ─
echo "T41: GAAI_AUTO_MERGE_POLICY=off → auto_merge_applied:false in routing record"
> "$ROUTING_LOG"
make_commit_worktree "TST-COMMIT-AUTOMERGE"
"$SCHEDULER" --set-phase-status "TST-COMMIT-AUTOMERGE" qa_passed "$FIXTURE" 2>/dev/null || true
GAAI_SKIP_AUTO_MERGE=0
GAAI_AUTO_MERGE_POLICY=off
TRACE="test-trace-$(date +%s)-041"

if handle_commit_phase "TST-COMMIT-AUTOMERGE" "$TRACE" 2>/dev/null; then
  if grep -q '"auto_merge_applied":false' "$ROUTING_LOG" 2>/dev/null; then
    pass "T41: auto_merge_applied:false in routing record when policy=off"
  else
    fail "T41: expected auto_merge_applied:false — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T41: handle_commit_phase returned non-zero"
fi

# ── T42: PR already exists → fallback to gh pr view, return 0 ─
echo "T42: gh pr create returns 'already exists' → fallback to gh pr view, success"
> "$ROUTING_LOG"
make_commit_worktree "TST-COMMIT-AUTOMERGE"
"$SCHEDULER" --set-phase-status "TST-COMMIT-AUTOMERGE" qa_passed "$FIXTURE" 2>/dev/null || true
GAAI_SHIM_GH_PR_EXISTS=1
GAAI_SKIP_AUTO_MERGE=0
GAAI_AUTO_MERGE_POLICY=off
TRACE="test-trace-$(date +%s)-042"

if handle_commit_phase "TST-COMMIT-AUTOMERGE" "$TRACE" 2>/dev/null; then
  new_ps=$(get_phase_status "TST-COMMIT-AUTOMERGE")
  if [[ "$new_ps" == "done" ]]; then
    pass "T42a: phase_status advanced to done even when PR already existed"
  else
    fail "T42a: expected 'done', got '$new_ps'"
  fi
  if grep -q '"pr_url":"https://github.com/test/repo/pull/999"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T42b: routing record has the fallback pr_url from gh pr view"
  else
    fail "T42b: routing record missing pr_url — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T42a: handle_commit_phase returned non-zero even with existing PR fallback"
  fail "T42b: (skipped)"
fi
GAAI_SHIM_GH_PR_EXISTS=0

# ── T43: staging_only policy on non-staging branch → no merge ──
echo "T43: GAAI_AUTO_MERGE_POLICY=staging_only on non-staging branch → no auto-merge"
> "$ROUTING_LOG"
make_commit_worktree "TST-COMMIT-AUTOMERGE"
# Branch is already story/TST-COMMIT-AUTOMERGE (not staging)
"$SCHEDULER" --set-phase-status "TST-COMMIT-AUTOMERGE" qa_passed "$FIXTURE" 2>/dev/null || true
GAAI_SKIP_AUTO_MERGE=0
GAAI_AUTO_MERGE_POLICY=staging_only
export TARGET_BRANCH=preview
TRACE="test-trace-$(date +%s)-043"

if handle_commit_phase "TST-COMMIT-AUTOMERGE" "$TRACE" 2>/dev/null; then
  if grep -q '"auto_merge_applied":false' "$ROUTING_LOG" 2>/dev/null; then
    pass "T43: auto_merge_applied:false when staging_only + non-staging branch"
  else
    fail "T43: expected auto_merge_applied:false — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T43: handle_commit_phase returned non-zero"
fi
export GAAI_AUTO_MERGE_POLICY=off
unset TARGET_BRANCH

# ── T44: dispatch qa_passed → done via full commit phase ───────
echo "T44: dispatch_3phase_story — qa_passed → done via handle_commit_phase"
> "$ROUTING_LOG"
make_commit_worktree "TST-COMMIT-01"
# E1096S02 AC2/DEC-200 D7: dispatch_3phase_story's currentness gate reruns QA for
# any qa_passed/qa_failed story lacking a two-axis sidecar (make_commit_worktree only
# writes the legacy Markdown qa-report.md). This test exercises dispatch's qa_passed ->
# handle_commit_phase wiring specifically, so it needs a valid, agreeing sidecar to
# represent a REALISTIC current qa_passed state and avoid tripping the (correct, new)
# currentness rerun — QARERUN-1/2 below cover the missing-sidecar rerun path itself.
printf '{"schema_version":1,"story_id":"TST-COMMIT-01","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"PASS","plan_conformance":"PASS","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"PASS","remediation_route":null,"replan_required":null,"report_path":"qa-reports/TST-COMMIT-01.qa-report.md"}' \
  > "$COMMIT_FIXTURE_DIR/TST-COMMIT-01-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-COMMIT-01.qa-verdict.json"
"$SCHEDULER" --set-phase-status "TST-COMMIT-01" qa_passed "$FIXTURE" 2>/dev/null || true
GAAI_SHIM_PUSH_FAIL=0
TRACE="test-trace-$(date +%s)-044"

if dispatch_3phase_story "TST-COMMIT-01" "$TRACE" 2>/dev/null; then
  new_ps=$(get_phase_status "TST-COMMIT-01")
  if [[ "$new_ps" == "done" ]]; then
    pass "T44a: dispatch qa_passed → done via commit phase"
  else
    fail "T44a: expected 'done', got '$new_ps'"
  fi
  if grep -q '"phase":"commit"' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"provider":"daemon-bash"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T44b: routing.jsonl has commit+daemon-bash record from dispatch"
  else
    fail "T44b: routing.jsonl missing commit+daemon-bash — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T44a: dispatch_3phase_story returned non-zero for qa_passed story"
  fail "T44b: (skipped)"
fi

# ── T45: Guard 1 — HEAD ancestor of origin/staging → no gh pr create ──────
echo "T45: Guard 1 — HEAD ancestor fast-path"
GAAI_SHIM_HEAD_IS_ANCESTOR=1
> "$COMMIT_CALL_LOG"
make_commit_worktree "TST-COMMIT-GUARD1"
"$SCHEDULER" --set-phase-status "TST-COMMIT-GUARD1" qa_passed "$FIXTURE" 2>/dev/null || true
TRACE="test-trace-$(date +%s)-045"
if handle_commit_phase "TST-COMMIT-GUARD1" "$TRACE" 2>/dev/null; then
  if ! grep -q "pr create" "$COMMIT_CALL_LOG" 2>/dev/null; then
    pass "T45a: Guard 1 — zero gh pr create calls when HEAD is ancestor"
  else
    fail "T45a: Guard 1 fired but gh pr create was still called"
  fi
  new_ps=$(get_phase_status "TST-COMMIT-GUARD1")
  if [[ "$new_ps" == "done" ]]; then
    pass "T45b: phase_status advanced to done via Guard 1 path"
  else
    fail "T45b: expected done, got '$new_ps'"
  fi
else
  fail "T45a: handle_commit_phase returned non-zero on Guard 1 path"
  fail "T45b: (skipped)"
fi
GAAI_SHIM_HEAD_IS_ANCESTOR=0

# ── T46: Guard 2 — existing merged/open PR → reuse URL, no gh pr create ───
echo "T46: Guard 2 — existing PR reuse"
# T46a: MERGED PR variant (primary E177S04 scenario)
GAAI_SHIM_GH_PR_MERGED=1
> "$COMMIT_CALL_LOG"
> "$ROUTING_LOG"
make_commit_worktree "TST-COMMIT-GUARD2"
"$SCHEDULER" --set-phase-status "TST-COMMIT-GUARD2" qa_passed "$FIXTURE" 2>/dev/null || true
TRACE="test-trace-$(date +%s)-046a"
if handle_commit_phase "TST-COMMIT-GUARD2" "$TRACE" 2>/dev/null; then
  if ! grep -q "pr create" "$COMMIT_CALL_LOG" 2>/dev/null; then
    pass "T46a-1: Guard 2 (MERGED) — zero gh pr create calls"
  else
    fail "T46a-1: Guard 2 fired but gh pr create was still called"
  fi
  if grep -q '"pr_url":"https://github.com/test/repo/pull/888"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T46a-2: Guard 2 (MERGED) — merged PR URL reused in routing record"
  else
    fail "T46a-2: routing record missing reused pr_url — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T46a-1: handle_commit_phase returned non-zero on Guard 2 MERGED path"
  fail "T46a-2: (skipped)"
fi

# T46b: OPEN PR variant
> "$COMMIT_CALL_LOG"
> "$ROUTING_LOG"
make_commit_worktree "TST-COMMIT-GUARD2"
"$SCHEDULER" --set-phase-status "TST-COMMIT-GUARD2" qa_passed "$FIXTURE" 2>/dev/null || true
TRACE="test-trace-$(date +%s)-046b"
if handle_commit_phase "TST-COMMIT-GUARD2" "$TRACE" 2>/dev/null; then
  if ! grep -q "pr create" "$COMMIT_CALL_LOG" 2>/dev/null; then
    pass "T46b-1: Guard 2 (OPEN) — zero gh pr create calls"
  else
    fail "T46b-1: Guard 2 fired but gh pr create was still called (OPEN variant)"
  fi
  if grep -q '"pr_url":"https://github.com/test/repo/pull/888"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T46b-2: Guard 2 (OPEN) — PR URL reused in routing record"
  else
    fail "T46b-2: routing record missing reused pr_url (OPEN) — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
else
  fail "T46b-1: handle_commit_phase returned non-zero on Guard 2 OPEN path"
  fail "T46b-2: (skipped)"
fi
GAAI_SHIM_GH_PR_MERGED=0

# Cleanup commit phase test fixtures
export PATH="$COMMIT_OLD_PATH"
unset GAAI_WORKTREES_BASE GAAI_SKIP_AUTO_MERGE GAAI_AUTO_MERGE_POLICY
unset GAAI_SHIM_PUSH_FAIL GAAI_SHIM_GH_AUTH_FAIL GAAI_SHIM_GH_PR_EXISTS GAAI_SHIM_HEAD_IS_ANCESTOR GAAI_SHIM_GH_PR_MERGED
unset GAAI_SHIM_AUTOMERGE_NULL GAAI_SHIM_AUTOMERGE_FAIL GAAI_COMMIT_CALL_LOG
unset COMMIT_OLD_PATH COMMIT_FIXTURE_DIR COMMIT_SHIM_DIR COMMIT_REAL_GIT COMMIT_CALL_LOG
rm -rf "/tmp/gaai-commit-phase-tests-$$"

# ── QAJSON: DEC-200 two-axis qa-verdict.mjs hermetic fixture matrix (AC6) ──
# Pure-function fixtures against validateQaVerdict — no daemon spawn, no LLM,
# no network. Labels use a QAJSON prefix (not T-numbered) to avoid colliding
# with the T1-T46 sequence used elsewhere in this file.
echo "QAJSON: qa-verdict.mjs hermetic fixture matrix (AC6)"
QAJSON_SCRIPT="/tmp/gaai-qa-verdict-fixtures-$$.mjs"
QAJSON_MODULE="$PROJECT_DIR/.gaai/core/scripts/lib/qa-verdict.mjs"
cat > "$QAJSON_SCRIPT" << 'NODEFIX_EOF'
const { validateQaVerdict } = await import(process.env.GAAI_QA_VERDICT_MODULE);

function base(overrides = {}) {
  return {
    schema_version: 1,
    story_id: 'FIX-1',
    evaluated_as_of: '2026-08-07T00:00:00Z',
    state_of_the_art_conformance: 'PASS',
    plan_conformance: 'PASS',
    changed_surface_inventory: [],
    findings: [],
    evidence: [],
    verdict: 'PASS',
    remediation_route: null,
    replan_required: null,
    report_path: 'qa-reports/FIX-1.qa-report.md',
    ...overrides,
  };
}

function blockingCase(materiality, reviewDomain = 'other', domain = 'stable', verifiedAt = '2026-08-01T00:00:00Z') {
  return base({
    state_of_the_art_conformance: 'FAIL',
    verdict: 'FAIL',
    remediation_route: 'impl',
    replan_required: false,
    changed_surface_inventory: [{ surface: 'a.ts', classification: 'blocking', review_domain: reviewDomain, materiality }],
    findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'blocking', description: 'x', root_cause: 'implementation' }],
    evidence: [{
      surface: 'a.ts', finding_id: 'f1', outcome: 'contradicts', source_kind: 'governed_record',
      authority_uri: 'contexts/authority/a.md', authority_title: 'x', accessed_at: '2026-08-07T00:00:00Z',
      claim: 'y', excerpt: 'z', materiality,
      governed_record: { authority_record_version: 1, official_authority_url: 'https://x.com', verified_at: verifiedAt, authority_domain: domain, claim_scope: 'x' },
    }],
  });
}

const CASES = [];
// expectDefaulted (optional 5th arg): when set, asserts result.authorityDomainDefaulted
// matches — the DEC-200 D3 "emits authority_domain_defaulted" observability signal.
const add = (name, sidecar, expectedSurfaces, valid, expectDefaulted) => CASES.push({ name, sidecar, expectedSurfaces, valid, expectDefaulted });

// ── 9 axis-combination rows ────────────────────────────────────────────────
const AXES = ['PASS', 'FAIL', 'ESCALATE'];
for (const plan of AXES) {
  for (const sota of AXES) {
    let verdict = 'PASS';
    if (plan === 'ESCALATE' || sota === 'ESCALATE') verdict = 'ESCALATE';
    else if (plan === 'FAIL' || sota === 'FAIL') verdict = 'FAIL';
    let route = null; let replan = null;
    if (verdict === 'ESCALATE') { route = 'human'; replan = null; }
    else if (verdict === 'FAIL') { route = 'impl'; replan = false; }
    add(`axis-row plan=${plan} sota=${sota} -> ${verdict}`, base({
      plan_conformance: plan, state_of_the_art_conformance: sota, verdict, remediation_route: route, replan_required: replan,
    }), [], true);
  }
}

// ── Story-wins-PLAN-conflict marker: validator's role is limited to
// confirming a Story-scoped blocking finding is present with root_cause; it
// cannot mechanically arbitrate Story-vs-PLAN content (documented boundary).
add('story-wins marker: implementation-rooted blocking finding routes impl', blockingCase('deprecated'), ['a.ts'], true);

// ── 4 D5 remediation-route/replan_required invariants ──────────────────────
add('D5: ESCALATE -> human/null', base({ plan_conformance: 'ESCALATE', state_of_the_art_conformance: 'PASS', verdict: 'ESCALATE', remediation_route: 'human', replan_required: null }), [], true);
add('D5: FAIL plan-rooted -> plan/true', base({
  plan_conformance: 'FAIL', state_of_the_art_conformance: 'PASS', verdict: 'FAIL', remediation_route: 'plan', replan_required: true,
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'blocking', review_domain: 'other', materiality: 'deprecated' }],
  findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'blocking', description: 'x', root_cause: 'plan' }],
  evidence: [{ surface: 'a.ts', finding_id: 'f1', outcome: 'contradicts', source_kind: 'live', authority_uri: 'https://x.com/docs', authority_title: 'x', accessed_at: '2026-08-07T00:00:00Z', claim: 'y', excerpt: 'z', materiality: 'deprecated' }],
}), ['a.ts'], true);
add('D5: FAIL impl-rooted -> impl/false', blockingCase('unsupported'), ['a.ts'], true);
add('D5: PASS -> null/null', base(), [], true);

// ── 3 conditional classification/evidence shapes ────────────────────────────
add('classification: blocking without materiality -> invalid', base({
  state_of_the_art_conformance: 'FAIL', verdict: 'FAIL', remediation_route: 'impl', replan_required: false,
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'blocking', review_domain: 'other' }],
}), ['a.ts'], false);
add('classification: non_blocking with materiality -> invalid', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other', materiality: 'deprecated' }],
}), ['a.ts'], false);
add('classification: not_applicable without eligibility_reason -> invalid', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'not_applicable', review_domain: 'other' }],
}), ['a.ts'], false);
add('classification: not_applicable valid with eligibility_reason', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'not_applicable', review_domain: 'other', eligibility_reason: 'generated test fixture, no runtime effect' }],
}), ['a.ts'], true);

// ── missing / null / forbidden materiality ──────────────────────────────────
add('materiality: missing on blocking -> invalid', base({
  state_of_the_art_conformance: 'FAIL', verdict: 'FAIL', remediation_route: 'impl', replan_required: false,
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'blocking', review_domain: 'other' }],
  findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'blocking', description: 'x', root_cause: 'implementation' }],
}), ['a.ts'], false);
add('materiality: null on non_blocking -> invalid (must be absent, not null)', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other', materiality: null }],
}), ['a.ts'], false);
add('materiality: forbidden on not_applicable -> invalid', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'not_applicable', review_domain: 'other', eligibility_reason: 'x', materiality: 'deprecated' }],
}), ['a.ts'], false);

// ── closed outcome excluded from aggregate math ─────────────────────────────
add('outcome=supports does not change validity/aggregate', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' }],
  findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'non_blocking', description: 'x' }],
  evidence: [{ surface: 'a.ts', finding_id: 'f1', outcome: 'supports', source_kind: 'live', authority_uri: 'https://x.com/a', authority_title: 'x', accessed_at: '2026-08-07T00:00:00Z', claim: 'y', excerpt: 'z' }],
}), ['a.ts'], true);
add('outcome=contradicts does not change validity/aggregate (still PASS-eligible non_blocking)', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' }],
  findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'non_blocking', description: 'x' }],
  evidence: [{ surface: 'a.ts', finding_id: 'f1', outcome: 'contradicts', source_kind: 'live', authority_uri: 'https://x.com/a', authority_title: 'x', accessed_at: '2026-08-07T00:00:00Z', claim: 'y', excerpt: 'z' }],
}), ['a.ts'], true);

// ── newer-but-supported non-blocking evidence confirms non_blocking, not FAIL ──
add('newer-but-supported alt -> non_blocking, PASS-eligible', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' }],
  findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'non_blocking', description: 'newer supported alt exists' }],
  evidence: [{ surface: 'a.ts', finding_id: 'f1', outcome: 'supports', source_kind: 'live', authority_uri: 'https://x.com/a', authority_title: 'x', accessed_at: '2026-08-07T00:00:00Z', claim: 'still supported', excerpt: 'z' }],
}), ['a.ts'], true);

// ── every material FAIL class ────────────────────────────────────────────────
for (const m of ['deprecated', 'unsupported', 'materially_obsolete', 'unsafe', 'officially_discouraged', 'demonstrably_fragile']) {
  const domain = m === 'unsafe' ? 'security' : 'stable';
  add(`materiality class: ${m}`, blockingCase(m, m === 'unsafe' ? 'security' : 'other', domain), ['a.ts'], true);
}

// ── exact inventory equality: missing / duplicate / unexpected surface ──────
add('inventory: missing expected surface -> invalid', base(), ['a.ts', 'b.ts'], false);
add('inventory: duplicate surface -> invalid', base({
  changed_surface_inventory: [
    { surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' },
    { surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' },
  ],
}), ['a.ts'], false);
add('inventory: unexpected surface -> invalid', base({
  changed_surface_inventory: [{ surface: 'z.ts', classification: 'non_blocking', review_domain: 'other' }],
}), ['a.ts'], false);

// ── N-A eligible vs ineligible-but-claimed (shape-level; semantic eligibility
// is a documented validator boundary — see Story AC2 edge cases) ───────────
add('N-A eligible (shape valid)', base({
  changed_surface_inventory: [{ surface: 'fixture.json', classification: 'not_applicable', review_domain: 'other', eligibility_reason: 'test fixture data, no runtime effect' }],
}), ['fixture.json'], true);

// ── missing / invalid review_domain ──────────────────────────────────────────
add('review_domain: missing -> invalid', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking' }],
}), ['a.ts'], false);
add('review_domain: invalid value -> invalid', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'bogus' }],
}), ['a.ts'], false);

// ── official live evidence with durable digest/excerpt ───────────────────────
add('live evidence with content_digest', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' }],
  findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'non_blocking', description: 'x' }],
  evidence: [{ surface: 'a.ts', finding_id: 'f1', outcome: 'supports', source_kind: 'live', authority_uri: 'https://x.com/a', authority_title: 'x', accessed_at: '2026-08-07T00:00:00Z', claim: 'y', content_digest: 'sha256:abc123' }],
}), ['a.ts'], true);

// ── governed record freshness ────────────────────────────────────────────────
function grCase(domain, verifiedAt, evalAsOf = '2026-08-07T00:00:00Z') {
  return base({
    evaluated_as_of: evalAsOf,
    changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' }],
    findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'non_blocking', description: 'x' }],
    evidence: [{
      surface: 'a.ts', finding_id: 'f1', outcome: 'supports', source_kind: 'governed_record',
      authority_uri: 'contexts/authority/a.md', authority_title: 'x', accessed_at: evalAsOf, claim: 'y', excerpt: 'z',
      governed_record: { authority_record_version: 1, official_authority_url: 'https://x.com', verified_at: verifiedAt, authority_domain: domain, claim_scope: 'x' },
    }],
  });
}
add('governed record: fresh fast_moving (<30d)', grCase('fast_moving', '2026-07-20T00:00:00Z'), ['a.ts'], true, false);
add('governed record: stale fast_moving (>30d) claimed PASS -> invalid', grCase('fast_moving', '2026-06-01T00:00:00Z'), ['a.ts'], false);
add('governed record: fresh stable (<90d)', grCase('stable', '2026-06-01T00:00:00Z'), ['a.ts'], true);
add('governed record: stale stable (>90d) claimed PASS -> invalid', grCase('stable', '2026-01-01T00:00:00Z'), ['a.ts'], false);
{
  const staleEscalate = grCase('stable', '2026-01-01T00:00:00Z');
  staleEscalate.state_of_the_art_conformance = 'ESCALATE';
  staleEscalate.verdict = 'ESCALATE';
  staleEscalate.remediation_route = 'human';
  add('governed record: stale but correctly-ESCALATE -> valid', staleEscalate, ['a.ts'], true);
}

// ── missing / wrong record version ───────────────────────────────────────────
{
  const wrongVersion = grCase('stable', '2026-08-01T00:00:00Z');
  wrongVersion.evidence[0].governed_record.authority_record_version = 2;
  add('governed record: wrong authority_record_version -> invalid', wrongVersion, ['a.ts'], false);
}
{
  const missingVersion = grCase('stable', '2026-08-01T00:00:00Z');
  delete missingVersion.evidence[0].governed_record.authority_record_version;
  add('governed record: missing authority_record_version -> invalid', missingVersion, ['a.ts'], false);
}

// ── missing official_authority_url / verified_at / claim_scope ─────────────
{
  const missingUrl = grCase('stable', '2026-08-01T00:00:00Z');
  delete missingUrl.evidence[0].governed_record.official_authority_url;
  add('governed record: missing official_authority_url -> invalid', missingUrl, ['a.ts'], false);
}
{
  const missingScope = grCase('stable', '2026-08-01T00:00:00Z');
  delete missingScope.evidence[0].governed_record.claim_scope;
  add('governed record: missing claim_scope -> invalid', missingScope, ['a.ts'], false);
}

// ── fresh/stale missing or literal-unknown authority_domain (observable default) ──
// Each case asserts authorityDomainDefaulted === true — DEC-200 D3 requires the
// fallback to "emit authority_domain_defaulted", not merely apply the 30-day window.
{
  const freshMissingDomain = grCase('stable', '2026-08-01T00:00:00Z');
  delete freshMissingDomain.evidence[0].governed_record.authority_domain;
  add('governed record: missing authority_domain, fresh (<30d default) -> valid', freshMissingDomain, ['a.ts'], true, true);
}
{
  const staleMissingDomain = grCase('stable', '2026-06-01T00:00:00Z');
  delete staleMissingDomain.evidence[0].governed_record.authority_domain;
  add('governed record: missing authority_domain, stale (>30d default) claimed PASS -> invalid', staleMissingDomain, ['a.ts'], false, true);
}
{
  const freshUnknownDomain = grCase('unknown', '2026-08-01T00:00:00Z');
  add('governed record: literal unknown authority_domain, fresh -> valid', freshUnknownDomain, ['a.ts'], true, true);
}
{
  const staleUnknownDomain = grCase('unknown', '2026-06-01T00:00:00Z');
  add('governed record: literal unknown authority_domain, stale claimed PASS -> invalid', staleUnknownDomain, ['a.ts'], false, true);
}

// ── unrecognized / mismatched authority_domain — immediate escalation ───────
{
  const bogusDomain = grCase('sometimes', '2026-08-01T00:00:00Z');
  bogusDomain.state_of_the_art_conformance = 'ESCALATE';
  bogusDomain.verdict = 'ESCALATE';
  bogusDomain.remediation_route = 'human';
  add('governed record: unrecognized authority_domain -> invalid even under ESCALATE', bogusDomain, ['a.ts'], false);
}

// ── security and unsafe domain enforcement ──────────────────────────────────
add('security materiality with security domain, fresh -> valid', blockingCase('unsafe', 'security', 'security', '2026-08-01T00:00:00Z'), ['a.ts'], true);
{
  const mismatchEscalate = blockingCase('unsafe', 'security', 'stable', '2026-08-06T00:00:00Z');
  mismatchEscalate.state_of_the_art_conformance = 'ESCALATE';
  mismatchEscalate.verdict = 'ESCALATE';
  mismatchEscalate.remediation_route = 'human';
  mismatchEscalate.replan_required = null;
  add('security/unsafe with non-security domain + ESCALATE -> valid', mismatchEscalate, ['a.ts'], true);
}
{
  const mismatchPass = blockingCase('unsafe', 'security', 'stable', '2026-08-06T00:00:00Z');
  mismatchPass.state_of_the_art_conformance = 'FAIL';
  mismatchPass.verdict = 'FAIL';
  add('security/unsafe with non-security domain + claimed FAIL (not ESCALATE) -> invalid', mismatchPass, ['a.ts'], false);
}

// ── empty PASS: no surface coverage ─────────────────────────────────────────
add('empty inventory with non-empty expected surfaces -> invalid', base(), ['a.ts'], false);

// ── unsafe locators ──────────────────────────────────────────────────────────
add('governed locator: absolute path -> invalid', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' }],
  findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'non_blocking', description: 'x' }],
  evidence: [{ surface: 'a.ts', finding_id: 'f1', outcome: 'supports', source_kind: 'governed_record', authority_uri: '/etc/passwd', authority_title: 'x', accessed_at: '2026-08-07T00:00:00Z', claim: 'y', excerpt: 'z', governed_record: { authority_record_version: 1, official_authority_url: 'https://x.com', verified_at: '2026-08-01T00:00:00Z', authority_domain: 'stable', claim_scope: 'x' } }],
}), ['a.ts'], false);
add('governed locator: .. segment -> invalid', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' }],
  findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'non_blocking', description: 'x' }],
  evidence: [{ surface: 'a.ts', finding_id: 'f1', outcome: 'supports', source_kind: 'governed_record', authority_uri: '../../../secrets.md', authority_title: 'x', accessed_at: '2026-08-07T00:00:00Z', claim: 'y', excerpt: 'z', governed_record: { authority_record_version: 1, official_authority_url: 'https://x.com', verified_at: '2026-08-01T00:00:00Z', authority_domain: 'stable', claim_scope: 'x' } }],
}), ['a.ts'], false);

// ── secret-shaped query value on a live URL ──────────────────────────────────
add('live locator: secret-shaped query key -> invalid', base({
  changed_surface_inventory: [{ surface: 'a.ts', classification: 'non_blocking', review_domain: 'other' }],
  findings: [{ finding_id: 'f1', surface: 'a.ts', classification: 'non_blocking', description: 'x' }],
  evidence: [{ surface: 'a.ts', finding_id: 'f1', outcome: 'supports', source_kind: 'live', authority_uri: 'https://x.com/a?token=abc123', authority_title: 'x', accessed_at: '2026-08-07T00:00:00Z', claim: 'y', excerpt: 'z' }],
}), ['a.ts'], false);

// ── wrong story_id ────────────────────────────────────────────────────────────
CASES.push({ name: 'wrong story_id -> invalid', sidecar: base(), expectedSurfaces: [], valid: false, storyId: 'DIFFERENT-STORY' });

// ── state_of_the_art_conformance recorded before plan_conformance (D1 ordering) ──
{
  const outOfOrder = JSON.parse(JSON.stringify(base()));
  const reordered = {};
  reordered.schema_version = outOfOrder.schema_version;
  reordered.story_id = outOfOrder.story_id;
  reordered.evaluated_as_of = outOfOrder.evaluated_as_of;
  reordered.plan_conformance = outOfOrder.plan_conformance;
  reordered.state_of_the_art_conformance = outOfOrder.state_of_the_art_conformance;
  reordered.changed_surface_inventory = outOfOrder.changed_surface_inventory;
  reordered.findings = outOfOrder.findings;
  reordered.evidence = outOfOrder.evidence;
  reordered.verdict = outOfOrder.verdict;
  reordered.remediation_route = outOfOrder.remediation_route;
  reordered.replan_required = outOfOrder.replan_required;
  reordered.report_path = outOfOrder.report_path;
  add('D1 ordering: plan_conformance key before state_of_the_art_conformance -> invalid', reordered, [], false);
}

// ── report_path safety ────────────────────────────────────────────────────────
add('report_path: absolute path -> invalid', base({ report_path: '/etc/passwd' }), [], false);

let pass = 0; let fail = 0;
for (const c of CASES) {
  const result = validateQaVerdict({ sidecar: c.sidecar, storyId: c.storyId || 'FIX-1', expectedSurfaces: c.expectedSurfaces });
  let ok = result.valid === c.valid;
  if (ok && c.expectDefaulted !== undefined) ok = result.authorityDomainDefaulted === c.expectDefaulted;
  if (ok) { pass += 1; } else { fail += 1; }
  const detail = ok ? '' : JSON.stringify({ errors: result.errors, authorityDomainDefaulted: result.authorityDomainDefaulted });
  console.log(`SCENARIO_RESULT|${c.name}|${ok ? 'PASS' : 'FAIL'}|${detail}`);
}
console.log(`SCENARIO_SUMMARY|${pass}|${fail}`);
process.exit(fail === 0 ? 0 : 1);
NODEFIX_EOF

QAJSON_RC=0
GAAI_QA_VERDICT_MODULE="$QAJSON_MODULE" node "$QAJSON_SCRIPT" > /tmp/gaai-qa-verdict-fixtures-out-$$.txt 2>&1 || QAJSON_RC=$?
while IFS='|' read -r _tag _name _res _detail; do
  [[ "$_tag" != "SCENARIO_RESULT" ]] && continue
  if [[ "$_res" == "PASS" ]]; then
    pass "QAJSON: $_name"
  else
    fail "QAJSON: $_name -> $_detail"
  fi
done < <(grep '^SCENARIO_RESULT|' /tmp/gaai-qa-verdict-fixtures-out-$$.txt)
if [[ "$QAJSON_RC" -ne 0 ]] && ! grep -q '^SCENARIO_RESULT|' /tmp/gaai-qa-verdict-fixtures-out-$$.txt; then
  fail "QAJSON: fixture script crashed — $(cat /tmp/gaai-qa-verdict-fixtures-out-$$.txt)"
fi
rm -f "$QAJSON_SCRIPT" "/tmp/gaai-qa-verdict-fixtures-out-$$.txt"

# ── QAJSON-CLI: malformed JSON via the CLI wrapper (JSON.parse failure path) ──
echo "QAJSON-CLI: malformed sidecar JSON via CLI"
MALFORMED_SIDECAR="/tmp/gaai-qa-malformed-$$.json"
printf '{ this is not valid json' > "$MALFORMED_SIDECAR"
printf '[]' > "/tmp/gaai-qa-malformed-expected-$$.json"
if node "$QAJSON_MODULE" validate --sidecar "$MALFORMED_SIDECAR" --schema "$QAJSON_MODULE" \
    --story-id FIX-1 --expected-surfaces "/tmp/gaai-qa-malformed-expected-$$.json" >/dev/null 2>&1; then
  fail "QAJSON-CLI: malformed JSON should exit non-zero"
else
  pass "QAJSON-CLI: malformed JSON exits non-zero (QA_HANDOFF_INVALID)"
fi
rm -f "$MALFORMED_SIDECAR" "/tmp/gaai-qa-malformed-expected-$$.json"

# ── QAJSON-CLI2: successful validation echoes sidecar_path (AC5) ───────────
echo "QAJSON-CLI2: --sidecar-locator reaches the success summary as sidecar_path"
VALID_SIDECAR="/tmp/gaai-qa-valid-$$.json"
cat > "$VALID_SIDECAR" << 'VALIDFIX_EOF'
{
  "schema_version": 1,
  "story_id": "FIX-CLI",
  "evaluated_as_of": "2026-08-11T00:00:00Z",
  "state_of_the_art_conformance": "PASS",
  "plan_conformance": "PASS",
  "changed_surface_inventory": [],
  "findings": [],
  "evidence": [],
  "verdict": "PASS",
  "remediation_route": null,
  "replan_required": null,
  "report_path": "qa-reports/FIX-CLI.qa-report.md"
}
VALIDFIX_EOF
printf '[]' > "/tmp/gaai-qa-valid-expected-$$.json"
QAJSON_SCHEMA="$PROJECT_DIR/.gaai/core/schemas/qa-verdict.v1.schema.json"
QAJSON_CLI2_RC=0
QAJSON_CLI2_OUT=$(node "$QAJSON_MODULE" validate --sidecar "$VALID_SIDECAR" --schema "$QAJSON_SCHEMA" \
  --story-id FIX-CLI --expected-surfaces "/tmp/gaai-qa-valid-expected-$$.json" \
  --sidecar-locator "qa-reports/FIX-CLI.qa-verdict.json" 2>&1) || QAJSON_CLI2_RC=$?
if [[ "$QAJSON_CLI2_RC" -ne 0 ]]; then
  fail "QAJSON-CLI2: expected exit 0 on valid fixture, got $QAJSON_CLI2_RC — $QAJSON_CLI2_OUT"
elif [[ "$QAJSON_CLI2_OUT" == *'"sidecar_path":"qa-reports/FIX-CLI.qa-verdict.json"'* ]]; then
  pass "QAJSON-CLI2: success summary carries sidecar_path alongside report_path"
else
  fail "QAJSON-CLI2: summary missing sidecar_path — $QAJSON_CLI2_OUT"
fi
rm -f "$VALID_SIDECAR" "/tmp/gaai-qa-valid-expected-$$.json"

# ── QAJSON-D: daemon-level fail-closed fixtures (handle_qa_phase) ──────────
# Proves the new JSON gate overrides a well-formed Markdown PASS, and that a
# Markdown/JSON verdict disagreement is caught, even though phase routing
# still reads the Markdown line for AGREEING handoffs (T22-T24 above already
# cover the agree-and-pass-through path with the updated shim).
echo "QAJSON-D: handle_qa_phase fails closed on invalid/disagreeing JSON handoff"
QAD_FIXTURE_DIR="/tmp/gaai-qa-handoff-tests-$$"
rm -rf "$QAD_FIXTURE_DIR"; mkdir -p "$QAD_FIXTURE_DIR"
export GAAI_WORKTREES_BASE="$QAD_FIXTURE_DIR"
export CLAUDE_MODEL_PRIMARY="claude-sonnet-4-6"
export GAAI_WORKSPACE_ID="test-workspace"
export GAAI_ORG_ID="test-org"
cat >> "$FIXTURE" << 'YAML_QAD'
- id: TST-QA-HANDOFF
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QAD
QA_FIXTURE_DIR="$QAD_FIXTURE_DIR"
make_qa_worktree "TST-QA-HANDOFF"
QAD_SHIM_DIR="$QAD_FIXTURE_DIR/shims"
mkdir -p "$QAD_SHIM_DIR"
QAD_OLD_PATH="$PATH"
QAD_OLD_PROJECT_DIR="$PROJECT_DIR"
export PATH="$QAD_SHIM_DIR:$PATH"
export PROJECT_DIR="$SCRIPT_DIR/../../../.."

# Markdown PASS, JSON sidecar absent entirely.
cat > "$QAD_SHIM_DIR/claude" << 'QAD_MISSING_JSON_EOF'
#!/usr/bin/env bash
if [[ -n "${GAAI_QA_REPORT_PATH:-}" ]]; then
  printf '## AC1\npass\n\n## Verdict: PASS\n' > "${GAAI_QA_REPORT_PATH}"
fi
exit 0
QAD_MISSING_JSON_EOF
chmod +x "$QAD_SHIM_DIR/claude"
"$SCHEDULER" --set-phase-status "TST-QA-HANDOFF" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qad1"
if handle_qa_phase "TST-QA-HANDOFF" "$TRACE" 2>/dev/null; then
  fail "QAJSON-D1a: expected non-zero when JSON sidecar absent despite Markdown PASS"
else
  qad_ps=$(get_phase_status "TST-QA-HANDOFF")
  if [[ "$qad_ps" == "failed" ]]; then
    pass "QAJSON-D1a: JSON-absent-despite-Markdown-PASS -> story 'failed' (gate overrides Markdown)"
  else
    fail "QAJSON-D1a: expected 'failed', got '$qad_ps'"
  fi
  if grep -q '"fallback_reason":"QA_HANDOFF_INVALID"' "$ROUTING_LOG" 2>/dev/null; then
    pass "QAJSON-D1b: routing.jsonl has QA_HANDOFF_INVALID fallback_reason"
  else
    fail "QAJSON-D1b: routing.jsonl missing QA_HANDOFF_INVALID — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
fi

# Markdown PASS, JSON sidecar valid but claims FAIL (disagreement).
cat > "$QAD_SHIM_DIR/claude" << 'QAD_DISAGREE_EOF'
#!/usr/bin/env bash
if [[ -n "${GAAI_QA_VERDICT_PATH:-}" ]]; then
  printf '{"schema_version":1,"story_id":"%s","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"FAIL","plan_conformance":"FAIL","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"FAIL","remediation_route":"impl","replan_required":false,"report_path":"qa-reports/%s.qa-report.md"}' "${GAAI_STORY_ID:-}" "${GAAI_STORY_ID:-}" > "${GAAI_QA_VERDICT_PATH}"
fi
if [[ -n "${GAAI_QA_REPORT_PATH:-}" ]]; then
  printf '## AC1\npass\n\n## Verdict: PASS\n' > "${GAAI_QA_REPORT_PATH}"
fi
exit 0
QAD_DISAGREE_EOF
chmod +x "$QAD_SHIM_DIR/claude"
"$SCHEDULER" --set-phase-status "TST-QA-HANDOFF" implemented "$FIXTURE" 2>/dev/null || true
rm -f "$QAD_FIXTURE_DIR/TST-QA-HANDOFF-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QA-HANDOFF.qa-report.md"
rm -f "$QAD_FIXTURE_DIR/TST-QA-HANDOFF-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QA-HANDOFF.qa-verdict.json"
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qad2"
if handle_qa_phase "TST-QA-HANDOFF" "$TRACE" 2>/dev/null; then
  fail "QAJSON-D2a: expected non-zero on Markdown/JSON verdict disagreement"
else
  qad_ps=$(get_phase_status "TST-QA-HANDOFF")
  if [[ "$qad_ps" == "failed" ]]; then
    pass "QAJSON-D2a: Markdown=PASS vs JSON=FAIL disagreement -> story 'failed'"
  else
    fail "QAJSON-D2a: expected 'failed', got '$qad_ps'"
  fi
  if grep -q '"fallback_reason":"QA_HANDOFF_INVALID"' "$ROUTING_LOG" 2>/dev/null; then
    pass "QAJSON-D2b: routing.jsonl has QA_HANDOFF_INVALID fallback_reason"
  else
    fail "QAJSON-D2b: routing.jsonl missing QA_HANDOFF_INVALID — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
fi

export PATH="$QAD_OLD_PATH"
export PROJECT_DIR="$QAD_OLD_PROJECT_DIR"
unset GAAI_WORKTREES_BASE CLAUDE_MODEL_PRIMARY GAAI_WORKSPACE_ID GAAI_ORG_ID
rm -rf "$QAD_FIXTURE_DIR"

# ── QAROUTE/QARERUN/QAJSON-E/QAPARITY: E1096S02 AC3/AC4/AC6 live routing ───
# Route persistence, independent PLAN/IMPL counters, both exhaustion paths,
# the currentness gate (qa_passed/qa_failed/implemented) and Claude/Codex
# executor parity. Reuses the QAJSON-D self-contained fixture idiom exactly
# (fresh dir, GAAI_WORKTREES_BASE, make_qa_worktree, own shim dir/PATH).
echo "QAROUTE/QARERUN: E1096S02 live routing + currentness gate"
QAR_FIXTURE_DIR="/tmp/gaai-qaroute-tests-$$"
rm -rf "$QAR_FIXTURE_DIR"; mkdir -p "$QAR_FIXTURE_DIR"
export GAAI_WORKTREES_BASE="$QAR_FIXTURE_DIR"
export CLAUDE_MODEL_PRIMARY="claude-sonnet-4-6"
export GAAI_WORKSPACE_ID="test-workspace"
export GAAI_ORG_ID="test-org"
QA_FIXTURE_DIR="$QAR_FIXTURE_DIR"
QAR_SHIM_DIR="$QAR_FIXTURE_DIR/shims"
mkdir -p "$QAR_SHIM_DIR"
QAR_OLD_PATH="$PATH"
QAR_OLD_PROJECT_DIR="$PROJECT_DIR"
export PATH="$QAR_SHIM_DIR:$PATH"
export PROJECT_DIR="$SCRIPT_DIR/../../../.."

# Helper: claude shim writing a matching Markdown+JSON handoff. mixed=1 adds
# an extra impl-rooted blocking finding alongside the plan-rooted one (proves
# PLAN precedence wins when both root causes exist, per deriveRemediation()).
make_qaroute_claude_shim() {
  local verdict="$1" route="${2:-impl}" mixed="${3:-}"
  local sota_c="PASS" plan_c="PASS" route_json="null" replan_json="null" findings_json="[]"
  case "$verdict" in
    FAIL)
      plan_c="FAIL"
      if [[ "$route" == "plan" ]]; then
        route_json='"plan"'; replan_json="true"
        if [[ "$mixed" == "mixed" ]]; then
          findings_json='[{"finding_id":"f1","surface":"a.ts","classification":"blocking","description":"impl issue","root_cause":"implementation"},{"finding_id":"f2","surface":"b.ts","classification":"blocking","description":"plan issue","root_cause":"plan"}]'
        else
          findings_json='[{"finding_id":"f1","surface":"b.ts","classification":"blocking","description":"plan issue","root_cause":"plan"}]'
        fi
      else
        route_json='"impl"'; replan_json="false"
        findings_json='[{"finding_id":"f1","surface":"a.ts","classification":"blocking","description":"impl issue","root_cause":"implementation"}]'
      fi
      ;;
    ESCALATE) sota_c="ESCALATE"; route_json='"human"'; replan_json="null" ;;
  esac
  cat > "$QAR_SHIM_DIR/claude" << QARSHIM_EOF
#!/usr/bin/env bash
if [[ -n "\${GAAI_QA_VERDICT_PATH:-}" ]]; then
  printf '{"schema_version":1,"story_id":"%s","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"$sota_c","plan_conformance":"$plan_c","changed_surface_inventory":[],"findings":$findings_json,"evidence":[],"verdict":"$verdict","remediation_route":$route_json,"replan_required":$replan_json,"report_path":"qa-reports/%s.qa-report.md"}' "\${GAAI_STORY_ID:-}" "\${GAAI_STORY_ID:-}" > "\$GAAI_QA_VERDICT_PATH"
fi
if [[ -n "\${GAAI_QA_REPORT_PATH:-}" ]]; then
  printf '## AC1\ncheck\n\n## Verdict: %s\n' "$verdict" > "\$GAAI_QA_REPORT_PATH"
fi
exit 0
QARSHIM_EOF
  chmod +x "$QAR_SHIM_DIR/claude"
}

# ── QAROUTE-1: mixed root causes -> PLAN precedence wins ────────────────
echo "QAROUTE-1: handle_qa_phase persists 'plan' route on FAIL with mixed root-cause findings"
cat >> "$FIXTURE" << 'YAML_QAR1'
- id: TST-QAROUTE-1
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QAR1
make_qa_worktree "TST-QAROUTE-1"
make_qaroute_claude_shim "FAIL" "plan" "mixed"
"$SCHEDULER" --set-phase-status "TST-QAROUTE-1" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qar1"
if handle_qa_phase "TST-QAROUTE-1" "$TRACE" 2>/dev/null; then
  qar_ps=$(get_phase_status "TST-QAROUTE-1")
  if [[ "$qar_ps" == "qa_failed" ]]; then
    pass "QAROUTE-1a: FAIL verdict -> phase_status qa_failed"
  else
    fail "QAROUTE-1a: expected qa_failed, got '$qar_ps'"
  fi
  if [[ -f "${LOCK_DIR}/.qa-route-TST-QAROUTE-1" ]] && [[ "$(cat "${LOCK_DIR}/.qa-route-TST-QAROUTE-1")" == "plan" ]]; then
    pass "QAROUTE-1b: .qa-route marker persisted as 'plan' (PLAN-rooted finding wins over mixed IMPL-rooted finding)"
  else
    fail "QAROUTE-1b: .qa-route marker missing or not 'plan' — $(cat "${LOCK_DIR}/.qa-route-TST-QAROUTE-1" 2>/dev/null)"
  fi
else
  fail "QAROUTE-1a: handle_qa_phase returned non-zero for FAIL verdict"
  fail "QAROUTE-1b: (skipped)"
fi

# ── QAROUTE-2: single impl-rooted finding -> impl route ──────────────────
echo "QAROUTE-2: handle_qa_phase persists 'impl' route on FAIL with impl-rooted finding"
cat >> "$FIXTURE" << 'YAML_QAR2'
- id: TST-QAROUTE-2
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QAR2
make_qa_worktree "TST-QAROUTE-2"
make_qaroute_claude_shim "FAIL" "impl"
"$SCHEDULER" --set-phase-status "TST-QAROUTE-2" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qar2"
if handle_qa_phase "TST-QAROUTE-2" "$TRACE" 2>/dev/null; then
  qar_ps=$(get_phase_status "TST-QAROUTE-2")
  if [[ "$qar_ps" == "qa_failed" ]]; then
    pass "QAROUTE-2a: FAIL(impl) verdict -> phase_status qa_failed"
  else
    fail "QAROUTE-2a: expected qa_failed, got '$qar_ps'"
  fi
  if [[ -f "${LOCK_DIR}/.qa-route-TST-QAROUTE-2" ]] && [[ "$(cat "${LOCK_DIR}/.qa-route-TST-QAROUTE-2")" == "impl" ]]; then
    pass "QAROUTE-2b: .qa-route marker persisted as 'impl'"
  else
    fail "QAROUTE-2b: .qa-route marker missing or not 'impl' — $(cat "${LOCK_DIR}/.qa-route-TST-QAROUTE-2" 2>/dev/null)"
  fi
else
  fail "QAROUTE-2a: handle_qa_phase returned non-zero for FAIL(impl)"
  fail "QAROUTE-2b: (skipped)"
fi

# ── QAROUTE-3: dispatch consumes 'plan' route — rewinds not_started ──────
echo "QAROUTE-3: dispatch_3phase_story consumes plan route (rewind not_started, replans-only counter)"
cat >> "$FIXTURE" << 'YAML_QAR3'
- id: TST-QAROUTE-3
  status: in_progress
  phase_status: qa_failed
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QAR3
make_qa_worktree "TST-QAROUTE-3"
printf '{"schema_version":1,"story_id":"TST-QAROUTE-3","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"PASS","plan_conformance":"FAIL","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"FAIL","remediation_route":"plan","replan_required":true,"report_path":"qa-reports/TST-QAROUTE-3.qa-report.md"}' \
  > "$QAR_FIXTURE_DIR/TST-QAROUTE-3-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QAROUTE-3.qa-verdict.json"
rm -f "${LOCK_DIR}/.qa-retries-TST-QAROUTE-3" "${LOCK_DIR}/.qa-replans-TST-QAROUTE-3"
printf 'plan\n' > "${LOCK_DIR}/.qa-route-TST-QAROUTE-3"
"$SCHEDULER" --set-phase-status "TST-QAROUTE-3" qa_failed "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qar3"
if dispatch_3phase_story "TST-QAROUTE-3" "$TRACE" 2>/dev/null; then
  qar_ps=$(get_phase_status "TST-QAROUTE-3")
  if [[ "$qar_ps" == "not_started" ]]; then
    pass "QAROUTE-3a: plan route rewinds phase_status to not_started (not 'planned')"
  else
    fail "QAROUTE-3a: expected not_started, got '$qar_ps'"
  fi
  if [[ "$(cat "${LOCK_DIR}/.qa-replans-TST-QAROUTE-3" 2>/dev/null)" == "1" ]]; then
    pass "QAROUTE-3b: .qa-replans counter incremented to 1"
  else
    fail "QAROUTE-3b: .qa-replans counter not 1 — $(cat "${LOCK_DIR}/.qa-replans-TST-QAROUTE-3" 2>/dev/null)"
  fi
  if [[ ! -f "${LOCK_DIR}/.qa-retries-TST-QAROUTE-3" ]]; then
    pass "QAROUTE-3c: .qa-retries (IMPL counter) untouched by PLAN route"
  else
    fail "QAROUTE-3c: .qa-retries unexpectedly created by PLAN route"
  fi
  if grep -q '"fallback_reason":"QA_REPLAN_1"' "$ROUTING_LOG" 2>/dev/null; then
    pass "QAROUTE-3d: routing.jsonl has QA_REPLAN_1 retry record"
  else
    fail "QAROUTE-3d: routing.jsonl missing QA_REPLAN_1 — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
  if [[ "${GAAI_QA_INJECT_PHASE:-}" == "plan" ]]; then
    pass "QAROUTE-3e: GAAI_QA_INJECT_PHASE=plan exported for PLAN-route re-spawn"
  else
    fail "QAROUTE-3e: GAAI_QA_INJECT_PHASE not 'plan' — '${GAAI_QA_INJECT_PHASE:-}'"
  fi
else
  fail "QAROUTE-3a: dispatch_3phase_story returned non-zero"
  fail "QAROUTE-3b: (skipped)"; fail "QAROUTE-3c: (skipped)"
  fail "QAROUTE-3d: (skipped)"; fail "QAROUTE-3e: (skipped)"
fi
unset GAAI_QA_INJECT_PHASE GAAI_QA_REPORT_PATH 2>/dev/null || true

# ── QAROUTE-4: independence across alternating plan/impl cycles ──────────
echo "QAROUTE-4: independent counters across alternating PLAN/IMPL cycles"
cat >> "$FIXTURE" << 'YAML_QAR4'
- id: TST-QAROUTE-4
  status: in_progress
  phase_status: qa_failed
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QAR4
make_qa_worktree "TST-QAROUTE-4"
printf '{"schema_version":1,"story_id":"TST-QAROUTE-4","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"PASS","plan_conformance":"FAIL","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"FAIL","remediation_route":"plan","replan_required":true,"report_path":"qa-reports/TST-QAROUTE-4.qa-report.md"}' \
  > "$QAR_FIXTURE_DIR/TST-QAROUTE-4-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QAROUTE-4.qa-verdict.json"
rm -f "${LOCK_DIR}/.qa-retries-TST-QAROUTE-4" "${LOCK_DIR}/.qa-replans-TST-QAROUTE-4"
"$SCHEDULER" --set-phase-status "TST-QAROUTE-4" qa_failed "$FIXTURE" 2>/dev/null || true
printf 'plan\n' > "${LOCK_DIR}/.qa-route-TST-QAROUTE-4"
dispatch_3phase_story "TST-QAROUTE-4" "test-trace-qar4-1" 2>/dev/null || true
"$SCHEDULER" --set-phase-status "TST-QAROUTE-4" qa_failed "$FIXTURE" 2>/dev/null || true
printf 'impl\n' > "${LOCK_DIR}/.qa-route-TST-QAROUTE-4"
dispatch_3phase_story "TST-QAROUTE-4" "test-trace-qar4-2" 2>/dev/null || true
"$SCHEDULER" --set-phase-status "TST-QAROUTE-4" qa_failed "$FIXTURE" 2>/dev/null || true
printf 'plan\n' > "${LOCK_DIR}/.qa-route-TST-QAROUTE-4"
dispatch_3phase_story "TST-QAROUTE-4" "test-trace-qar4-3" 2>/dev/null || true
if [[ "$(cat "${LOCK_DIR}/.qa-replans-TST-QAROUTE-4" 2>/dev/null)" == "2" ]]; then
  pass "QAROUTE-4a: .qa-replans reflects 2 PLAN cycles (plan/impl/plan sequence)"
else
  fail "QAROUTE-4a: expected .qa-replans=2, got '$(cat "${LOCK_DIR}/.qa-replans-TST-QAROUTE-4" 2>/dev/null)'"
fi
if [[ "$(cat "${LOCK_DIR}/.qa-retries-TST-QAROUTE-4" 2>/dev/null)" == "1" ]]; then
  pass "QAROUTE-4b: .qa-retries reflects 1 IMPL cycle, independent of the PLAN counter"
else
  fail "QAROUTE-4b: expected .qa-retries=1, got '$(cat "${LOCK_DIR}/.qa-retries-TST-QAROUTE-4" 2>/dev/null)'"
fi
unset GAAI_QA_INJECT_PHASE GAAI_QA_REPORT_PATH 2>/dev/null || true

# ── QAROUTE-5: PLAN route exhaustion escalates ────────────────────────────
echo "QAROUTE-5: PLAN route exhaustion escalates to qa_escalated + cleans markers"
cat >> "$FIXTURE" << 'YAML_QAR5'
- id: TST-QAROUTE-5
  status: in_progress
  phase_status: qa_failed
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QAR5
make_qa_worktree "TST-QAROUTE-5"
printf '{"schema_version":1,"story_id":"TST-QAROUTE-5","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"PASS","plan_conformance":"FAIL","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"FAIL","remediation_route":"plan","replan_required":true,"report_path":"qa-reports/TST-QAROUTE-5.qa-report.md"}' \
  > "$QAR_FIXTURE_DIR/TST-QAROUTE-5-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QAROUTE-5.qa-verdict.json"
rm -f "${LOCK_DIR}/.qa-retries-TST-QAROUTE-5" "${LOCK_DIR}/.qa-replans-TST-QAROUTE-5"
printf '2\n' > "${LOCK_DIR}/.qa-replans-TST-QAROUTE-5"
printf 'plan\n' > "${LOCK_DIR}/.qa-route-TST-QAROUTE-5"
"$SCHEDULER" --set-phase-status "TST-QAROUTE-5" qa_failed "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qar5"
if dispatch_3phase_story "TST-QAROUTE-5" "$TRACE" 2>/dev/null; then
  qar_ps=$(get_phase_status "TST-QAROUTE-5")
  if [[ "$qar_ps" == "qa_escalated" ]]; then
    pass "QAROUTE-5a: PLAN cap reached (2/2) -> qa_escalated"
  else
    fail "QAROUTE-5a: expected qa_escalated, got '$qar_ps'"
  fi
  if grep -q '"fallback_reason":"QA_REPLAN_EXHAUSTED"' "$ROUTING_LOG" 2>/dev/null; then
    pass "QAROUTE-5b: routing.jsonl has QA_REPLAN_EXHAUSTED"
  else
    fail "QAROUTE-5b: routing.jsonl missing QA_REPLAN_EXHAUSTED — content: $(head -3 "$ROUTING_LOG" 2>/dev/null)"
  fi
  if [[ ! -f "${LOCK_DIR}/.qa-replans-TST-QAROUTE-5" && ! -f "${LOCK_DIR}/.qa-route-TST-QAROUTE-5" ]]; then
    pass "QAROUTE-5c: .qa-replans and .qa-route markers cleaned up on escalation"
  else
    fail "QAROUTE-5c: escalation markers not cleaned up"
  fi
else
  fail "QAROUTE-5a: dispatch_3phase_story returned non-zero"
  fail "QAROUTE-5b: (skipped)"; fail "QAROUTE-5c: (skipped)"
fi

# ── QAROUTE-6: IMPL route exhaustion escalates (regression) ──────────────
echo "QAROUTE-6: IMPL route exhaustion escalates to qa_escalated (regression — unchanged QA_RETRY_EXHAUSTED)"
cat >> "$FIXTURE" << 'YAML_QAR6'
- id: TST-QAROUTE-6
  status: in_progress
  phase_status: qa_failed
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QAR6
make_qa_worktree "TST-QAROUTE-6"
printf '{"schema_version":1,"story_id":"TST-QAROUTE-6","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"PASS","plan_conformance":"FAIL","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"FAIL","remediation_route":"impl","replan_required":false,"report_path":"qa-reports/TST-QAROUTE-6.qa-report.md"}' \
  > "$QAR_FIXTURE_DIR/TST-QAROUTE-6-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QAROUTE-6.qa-verdict.json"
rm -f "${LOCK_DIR}/.qa-retries-TST-QAROUTE-6" "${LOCK_DIR}/.qa-replans-TST-QAROUTE-6"
printf '3\n' > "${LOCK_DIR}/.qa-retries-TST-QAROUTE-6"
printf 'impl\n' > "${LOCK_DIR}/.qa-route-TST-QAROUTE-6"
"$SCHEDULER" --set-phase-status "TST-QAROUTE-6" qa_failed "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qar6"
if dispatch_3phase_story "TST-QAROUTE-6" "$TRACE" 2>/dev/null; then
  qar_ps=$(get_phase_status "TST-QAROUTE-6")
  if [[ "$qar_ps" == "qa_escalated" ]]; then
    pass "QAROUTE-6a: IMPL cap reached (3/3) -> qa_escalated"
  else
    fail "QAROUTE-6a: expected qa_escalated, got '$qar_ps'"
  fi
  if grep -q '"fallback_reason":"QA_RETRY_EXHAUSTED"' "$ROUTING_LOG" 2>/dev/null; then
    pass "QAROUTE-6b: routing.jsonl has QA_RETRY_EXHAUSTED (regression guard)"
  else
    fail "QAROUTE-6b: routing.jsonl missing QA_RETRY_EXHAUSTED"
  fi
  if [[ ! -f "${LOCK_DIR}/.qa-retries-TST-QAROUTE-6" && ! -f "${LOCK_DIR}/.qa-route-TST-QAROUTE-6" ]]; then
    pass "QAROUTE-6c: .qa-retries and .qa-route markers cleaned up on escalation"
  else
    fail "QAROUTE-6c: escalation markers not cleaned up"
  fi
else
  fail "QAROUTE-6a: dispatch_3phase_story returned non-zero"
  fail "QAROUTE-6b: (skipped)"; fail "QAROUTE-6c: (skipped)"
fi

# ── QARERUN-1: qa_passed lacking sidecar -> same-cycle currentness rerun ──
echo "QARERUN-1: qa_passed lacking two-axis sidecar triggers currentness rerun, same cycle"
cat >> "$FIXTURE" << 'YAML_QRR1'
- id: TST-QARERUN-1
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QRR1
make_qa_worktree "TST-QARERUN-1"
printf '## AC1\npass\n\n## Verdict: PASS\n' \
  > "$QAR_FIXTURE_DIR/TST-QARERUN-1-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QARERUN-1.qa-report.md"
make_qaroute_claude_shim "PASS"
"$SCHEDULER" --set-phase-status "TST-QARERUN-1" qa_passed "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qrr1"
if dispatch_3phase_story "TST-QARERUN-1" "$TRACE" 2>/dev/null; then
  if grep -q '"fallback_reason":"QA_CURRENTNESS_RERUN"' "$ROUTING_LOG" 2>/dev/null; then
    pass "QARERUN-1a: QA_CURRENTNESS_RERUN emitted for sidecar-less qa_passed story"
  else
    fail "QARERUN-1a: routing.jsonl missing QA_CURRENTNESS_RERUN — content: $(head -5 "$ROUTING_LOG" 2>/dev/null)"
  fi
  qar_ps=$(get_phase_status "TST-QARERUN-1")
  if [[ "$qar_ps" == "qa_passed" ]]; then
    pass "QARERUN-1b: fresh same-cycle QA re-executed and reached qa_passed under the current contract"
  else
    fail "QARERUN-1b: expected qa_passed after same-cycle rerun, got '$qar_ps'"
  fi
else
  fail "QARERUN-1a: dispatch_3phase_story returned non-zero"
  fail "QARERUN-1b: (skipped)"
fi

# ── QARERUN-2: qa_failed lacking sidecar -> same-cycle currentness rerun ──
echo "QARERUN-2: qa_failed lacking two-axis sidecar triggers currentness rerun, same cycle"
cat >> "$FIXTURE" << 'YAML_QRR2'
- id: TST-QARERUN-2
  status: in_progress
  phase_status: qa_failed
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QRR2
make_qa_worktree "TST-QARERUN-2"
printf '## AC1\nfail\n\n## Verdict: FAIL\n' \
  > "$QAR_FIXTURE_DIR/TST-QARERUN-2-workspace/.gaai/project/contexts/artefacts/qa-reports/TST-QARERUN-2.qa-report.md"
make_qaroute_claude_shim "FAIL" "impl"
"$SCHEDULER" --set-phase-status "TST-QARERUN-2" qa_failed "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qrr2"
if dispatch_3phase_story "TST-QARERUN-2" "$TRACE" 2>/dev/null; then
  if grep -q '"fallback_reason":"QA_CURRENTNESS_RERUN"' "$ROUTING_LOG" 2>/dev/null; then
    pass "QARERUN-2a: QA_CURRENTNESS_RERUN emitted for sidecar-less qa_failed story"
  else
    fail "QARERUN-2a: routing.jsonl missing QA_CURRENTNESS_RERUN — content: $(head -5 "$ROUTING_LOG" 2>/dev/null)"
  fi
  qar_ps=$(get_phase_status "TST-QARERUN-2")
  if [[ "$qar_ps" == "qa_failed" ]]; then
    pass "QARERUN-2b: fresh same-cycle QA re-executed and reached qa_failed under the current contract"
  else
    fail "QARERUN-2b: expected qa_failed after same-cycle rerun, got '$qar_ps'"
  fi
else
  fail "QARERUN-2a: dispatch_3phase_story returned non-zero"
  fail "QARERUN-2b: (skipped)"
fi
unset GAAI_QA_INJECT_PHASE GAAI_QA_REPORT_PATH 2>/dev/null || true

# ── QARERUN-3: implemented is out of gate scope (negative control) ───────
echo "QARERUN-3: implemented phase_status is out of gate scope — no currentness rerun"
cat >> "$FIXTURE" << 'YAML_QRR3'
- id: TST-QARERUN-3
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QRR3
make_qa_worktree "TST-QARERUN-3"
make_qaroute_claude_shim "PASS"
"$SCHEDULER" --set-phase-status "TST-QARERUN-3" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qrr3"
if dispatch_3phase_story "TST-QARERUN-3" "$TRACE" 2>/dev/null; then
  if grep -q "QA_CURRENTNESS_RERUN" "$ROUTING_LOG" 2>/dev/null; then
    fail "QARERUN-3a: QA_CURRENTNESS_RERUN unexpectedly emitted for implemented phase_status"
  else
    pass "QARERUN-3a: no QA_CURRENTNESS_RERUN emitted for implemented phase_status (negative control)"
  fi
  qar_ps=$(get_phase_status "TST-QARERUN-3")
  if [[ "$qar_ps" == "qa_passed" ]]; then
    pass "QARERUN-3b: dispatch proceeded straight into handle_qa_phase as normal"
  else
    fail "QARERUN-3b: expected qa_passed, got '$qar_ps'"
  fi
else
  fail "QARERUN-3a: dispatch_3phase_story returned non-zero"
  fail "QARERUN-3b: (skipped)"
fi

# ── QAJSON-E: PASS/agree regression (AC2->AC3 cutover safety) ────────────
echo "QAJSON-E: PASS/agree regression — qa_aggregate cutover doesn't break the agreeing PASS path"
cat >> "$FIXTURE" << 'YAML_QJE'
- id: TST-QAJSON-E
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase
  impl_model: primary
YAML_QJE
make_qa_worktree "TST-QAJSON-E"
make_qaroute_claude_shim "PASS"
"$SCHEDULER" --set-phase-status "TST-QAJSON-E" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-qje"
if handle_qa_phase "TST-QAJSON-E" "$TRACE" 2>/dev/null; then
  qar_ps=$(get_phase_status "TST-QAJSON-E")
  if [[ "$qar_ps" == "qa_passed" ]]; then
    pass "QAJSON-E: Markdown=PASS agrees with JSON=PASS -> qa_passed"
  else
    fail "QAJSON-E: expected qa_passed, got '$qar_ps'"
  fi
else
  fail "QAJSON-E: handle_qa_phase returned non-zero for agreeing PASS"
fi

# ── QAPARITY-1: identical routing outcome under claude vs codex ──────────
echo "QAPARITY-1: routing/counter outcome identical under claude vs codex executor"
for _qp_executor in claude codex; do
  _qp_sid="TST-QAPARITY-${_qp_executor}"
  printf -- '- id: %s\n  status: in_progress\n  phase_status: qa_failed\n  delivery_pipeline: 3phase\n  impl_model: primary\n' "$_qp_sid" >> "$FIXTURE"
  make_qa_worktree "$_qp_sid"
  printf '{"schema_version":1,"story_id":"%s","evaluated_as_of":"2026-08-07T00:00:00Z","state_of_the_art_conformance":"PASS","plan_conformance":"FAIL","changed_surface_inventory":[],"findings":[],"evidence":[],"verdict":"FAIL","remediation_route":"plan","replan_required":true,"report_path":"qa-reports/%s.qa-report.md"}' "$_qp_sid" "$_qp_sid" \
    > "$QAR_FIXTURE_DIR/${_qp_sid}-workspace/.gaai/project/contexts/artefacts/qa-reports/${_qp_sid}.qa-verdict.json"
  rm -f "${LOCK_DIR}/.qa-retries-${_qp_sid}" "${LOCK_DIR}/.qa-replans-${_qp_sid}"
  printf 'plan\n' > "${LOCK_DIR}/.qa-route-${_qp_sid}"
  "$SCHEDULER" --set-phase-status "$_qp_sid" qa_failed "$FIXTURE" 2>/dev/null || true
  if [[ "$_qp_executor" == "codex" ]]; then
    export GAAI_DAEMON_EXECUTOR=codex
  else
    unset GAAI_DAEMON_EXECUTOR
  fi
  dispatch_3phase_story "$_qp_sid" "test-trace-qp-${_qp_executor}" 2>/dev/null || true
  _qp_ps=$(get_phase_status "$_qp_sid")
  _qp_replans=$(cat "${LOCK_DIR}/.qa-replans-${_qp_sid}" 2>/dev/null || echo "")
  if [[ "$_qp_executor" == "claude" ]]; then
    _qp_claude_ps="$_qp_ps"; _qp_claude_replans="$_qp_replans"
  else
    _qp_codex_ps="$_qp_ps"; _qp_codex_replans="$_qp_replans"
  fi
done
unset GAAI_DAEMON_EXECUTOR GAAI_QA_INJECT_PHASE GAAI_QA_REPORT_PATH 2>/dev/null || true
if [[ "$_qp_claude_ps" == "$_qp_codex_ps" && "$_qp_claude_ps" == "not_started" ]]; then
  pass "QAPARITY-1a: identical phase_status rewind (not_started) for claude vs codex executor"
else
  fail "QAPARITY-1a: claude='$_qp_claude_ps' vs codex='$_qp_codex_ps' — routing diverged by executor"
fi
if [[ "$_qp_claude_replans" == "$_qp_codex_replans" && "$_qp_claude_replans" == "1" ]]; then
  pass "QAPARITY-1b: identical .qa-replans counter (1) for claude vs codex executor"
else
  fail "QAPARITY-1b: claude replans='$_qp_claude_replans' vs codex replans='$_qp_codex_replans'"
fi
unset _qp_executor _qp_sid _qp_ps _qp_replans _qp_claude_ps _qp_claude_replans _qp_codex_ps _qp_codex_replans

export PATH="$QAR_OLD_PATH"
export PROJECT_DIR="$QAR_OLD_PROJECT_DIR"
unset GAAI_WORKTREES_BASE CLAUDE_MODEL_PRIMARY GAAI_WORKSPACE_ID GAAI_ORG_ID
unset QAR_OLD_PATH QAR_OLD_PROJECT_DIR QAR_SHIM_DIR QAR_FIXTURE_DIR QA_FIXTURE_DIR
rm -rf "/tmp/gaai-qaroute-tests-$$"

# ── QAJSON-DERIVE: _derive_qa_expected_surfaces against a realistic ────────
# Story "## File Inventory" + PLAN "## Implementation Sequence" table whose
# Action/Checkpoint columns carry inline shell/CLI examples with slash-
# bearing backticked spans (the normal shape of a prepare-execution-plan
# table — see this very Story's own plan). Proves the derivation extracts
# only the leading-backtick Story path and the PLAN table's "Files" column,
# never prose fragments from other columns/sections, and that an escaped
# pipe ("\|") inside a cell does not shift the "Files" column index.
echo "QAJSON-DERIVE: expected-surface derivation ignores non-Files prose"
QDER_DIR="/tmp/gaai-qa-derive-tests-$$"
rm -rf "$QDER_DIR"; mkdir -p "$QDER_DIR"

QDER_STORY="$QDER_DIR/story.md"
cat > "$QDER_STORY" << 'QDER_STORY_EOF'
## File Inventory

- `.gaai/core/real/story-surface.ts` — implements X; see also `bash path/to/example.sh` for a
  reference invocation and `docs/notes/other.md` for background. `(impl)`

## Out of Scope
QDER_STORY_EOF

QDER_PLAN="$QDER_DIR/plan.md"
cat > "$QDER_PLAN" << 'QDER_PLAN_EOF'
## Implementation Sequence

| Step | Action | Files | Checkpoint |
|------|--------|-------|------------|
| 1 | Run `node scripts/tool.mjs run --flag` then inspect `logs/tool.log` for errors | `.gaai/core/real/plan-surface.ts` | Verify via `bash tests/check.sh` and confirm `reports/out.json` exists |
| 2 | Update the enum `A\|B\|C` in prose (escaped pipe must not shift columns) | `.gaai/core/real/plan-surface2.ts` | `node --check .gaai/core/real/plan-surface2.ts` passes |

## Edge Cases
QDER_PLAN_EOF

QDER_OUT="$QDER_DIR/expected-surfaces.json"
_derive_qa_expected_surfaces "$QDER_STORY" "$QDER_PLAN" "$QDER_DIR" "HEAD" "$QDER_OUT"

QDER_RESULT=$(cat "$QDER_OUT" 2>/dev/null || echo '[]')
QDER_CHECK=$(node -e '
  const fs = require("fs");
  const got = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const expected = [
    ".gaai/core/real/story-surface.ts",
    ".gaai/core/real/plan-surface.ts",
    ".gaai/core/real/plan-surface2.ts"
  ];
  const forbidden = [
    "path/to/example.sh", "docs/notes/other.md",
    "scripts/tool.mjs", "logs/tool.log",
    "tests/check.sh", "reports/out.json"
  ];
  const missing = expected.filter(e => !got.includes(e));
  const leaked = forbidden.filter(f => got.includes(f));
  const extra = got.filter(g => !expected.includes(g));
  if (missing.length === 0 && leaked.length === 0 && extra.length === 0) {
    console.log("OK");
  } else {
    console.log("MISSING=" + JSON.stringify(missing) + " LEAKED=" + JSON.stringify(leaked) + " EXTRA=" + JSON.stringify(extra) + " GOT=" + JSON.stringify(got));
  }
' "$QDER_OUT")

if [[ "$QDER_CHECK" == "OK" ]]; then
  pass "QAJSON-DERIVE: only real Files/leading-bullet surfaces derived, no Action/Checkpoint prose leaked"
else
  fail "QAJSON-DERIVE: $QDER_CHECK"
fi
rm -rf "$QDER_DIR"

# ── RUNBOOK-1: delivery-loop.workflow.md D8 runbook contract check ─────
# AC6's second sentence requires a hermetic check that the workflow doc names
# both DEC-200 D8 stop thresholds, the durable human-reversal record fields,
# and the hard-gate-preserving defer/human route — not just that the code
# behaves correctly. This test reads the doc directly (no daemon call) and
# fails if any required D8 clause has drifted or been removed from the doc.
echo "RUNBOOK-1: delivery-loop.workflow.md documents the DEC-200 D8 operator runbook"
RUNBOOK_DOC="$PROJECT_DIR/.gaai/core/workflows/delivery-loop.workflow.md"

if [[ ! -s "$RUNBOOK_DOC" ]]; then
  fail "RUNBOOK-1: delivery-loop.workflow.md missing or empty at $RUNBOOK_DOC"
else
  RUNBOOK_MISSING=()

  # Observation window
  grep -qF "30 calendar days" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("observation-window-30-days")
  grep -qF "20 completed dual-axis QA reviews" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("observation-window-20-reviews")

  # Stop trigger 1 — unsupported false PASS / security miss
  grep -qF "unsupported false PASS" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("stop-trigger-false-pass")
  grep -qF "security miss" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("stop-trigger-security-miss")

  # Stop trigger 2 — second human-overturned evidence-invalid state-of-the-art block
  grep -qF "second" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("stop-trigger-second-occurrence")
  grep -qF "human overturning an evidence-invalid" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("stop-trigger-human-overturn")
  grep -qF "state-of-the-art block" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("stop-trigger-sota-block")

  # Hard-gate-preserving defer/human route
  grep -qF "defers every affected Story through the existing" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("defer-route-scheduler")
  grep -qF "claim/scheduler protocol" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("defer-route-protocol-ref")
  grep -qF "continuation to a human" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("defer-route-human")
  grep -qF "weakened to advisory-only or silently accepted" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("defer-route-no-advisory-downgrade")

  # Durable human-reversal record — required field list
  grep -qF "Durable human-reversal record" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("reversal-record-heading")
  grep -qF "QA review ID" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("reversal-record-qa-review-id")
  grep -qF "Story ID" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("reversal-record-story-id")
  grep -qF "reviewed and decided timestamps" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("reversal-record-timestamps")
  grep -qF "classification and materiality" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("reversal-record-classification")
  grep -qF "reversal reason" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("reversal-record-reason")
  grep -qF "operator identity" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("reversal-record-operator")
  grep -qF "safe evidence/report" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("reversal-record-safe-locators")
  grep -qF "Report or evidence bodies and secrets are never included" "$RUNBOOK_DOC" || RUNBOOK_MISSING+=("reversal-record-no-bodies-secrets")

  if [[ ${#RUNBOOK_MISSING[@]} -eq 0 ]]; then
    pass "RUNBOOK-1: D8 runbook doc names both stop thresholds, the human-reversal record and the defer/human route"
  else
    fail "RUNBOOK-1: delivery-loop.workflow.md missing D8 clauses: ${RUNBOOK_MISSING[*]}"
  fi
  unset RUNBOOK_MISSING
fi
unset RUNBOOK_DOC

# ── LOCAL-ADMISSION-REAL: actual seal/reconcile/execute at both boundaries ─
echo "LOCAL-ADMISSION-REAL: real adapter seals distinct current receipts before remote publication"
eval "$REAL_PRE_QA_DEF"
eval "$REAL_ADMIT_DEF"
LOCAL_ADMISSION_FIXTURE=$(mktemp -d /tmp/gaai-daemon-admission-real-XXXXXX)
LAR_REPO="$LOCAL_ADMISSION_FIXTURE/repo"; LAR_REMOTE="$LOCAL_ADMISSION_FIXTURE/remote.git"
mkdir -p "$LAR_REPO/.gaai/project/ci" "$LAR_REPO/src" "$LOCAL_ADMISSION_FIXTURE/locks"
git init -q --bare "$LAR_REMOTE"; git init -q "$LAR_REPO"
git -C "$LAR_REPO" config user.email test@example.com; git -C "$LAR_REPO" config user.name Test
git -C "$LAR_REPO" checkout -q -b staging; git -C "$LAR_REPO" remote add origin "$LAR_REMOTE"
printf '{"name":"admission-fixture"}\n' > "$LAR_REPO/package.json"
cat > "$LAR_REPO/.gaai/project/ci/local-admission.json" <<POLICY_EOF
{"schema_version":"1.0.0","policy_version":"test-1","repository":{"project_id":"fixture/project","remote":"$LAR_REMOTE","base_ref":"staging"},"limits":{"max_policy_bytes":100000,"max_diff_bytes":100000,"max_changed_paths":20,"max_commands":5,"max_selectors":5,"max_identifier_bytes":80,"max_arguments_per_command":8,"max_argument_bytes":200,"max_receipt_bytes":65536,"max_result_bytes":32768},"commands":[{"id":"unit","argv":["node","-e","process.exit(0)"],"timeout_seconds":10,"output_limit_bytes":1024,"config_paths":["package.json"]}],"selectors":[{"id":"source","path_prefixes":["src"],"exact_paths":[],"command_ids":["unit"]}],"exhaustive_command_ids":["unit"],"non_executable_prefixes":[".gaai/project/contexts/artefacts"],"broadening_prefixes":["package.json"],"broadening_patterns":["tsconfig*.json"],"dependency_inputs":["package.json"],"risk_input_policy":{"keys":["cross_cutting","dependency_changed"],"exhaustive_when_true":["cross_cutting","dependency_changed"]},"required_environment":["node_version","platform","arch","path_digest"],"executable_suffixes":[".js",".mjs",".sh",".json"],"executable_names":["Dockerfile","Makefile"]}
POLICY_EOF
git -C "$LAR_REPO" add -A; git -C "$LAR_REPO" commit -q -m base; git -C "$LAR_REPO" push -q origin staging
git -C "$LAR_REPO" checkout -q -b story/TST-LOCAL-ADMISSION
printf '{"cross_cutting":false}\n' > "$LOCAL_ADMISSION_FIXTURE/risk.json"
mkdir -p "$LAR_REPO/.gaai/project/contexts/artefacts/plans" \
  "$LAR_REPO/.gaai/project/contexts/artefacts/impl-reports"
printf 'plan\n' > "$LAR_REPO/.gaai/project/contexts/artefacts/plans/TST-LOCAL-ADMISSION.execution-plan.md"
printf 'report\n' > "$LAR_REPO/.gaai/project/contexts/artefacts/impl-reports/TST-LOCAL-ADMISSION.impl-report.md"
LAR_BASE_HEAD=$(git -C "$LAR_REPO" rev-parse HEAD)
if LOCK_DIR="$LOCAL_ADMISSION_FIXTURE/locks" TARGET_BRANCH=staging \
  GAAI_LOCAL_ADMISSION_POLICY_PATH=.gaai/project/ci/local-admission.json \
    _prepare_pre_qa_admission TST-LOCAL-ADMISSION trace-empty "$LAR_REPO"; then
  LAR_EMPTY_RC=0
else
  LAR_EMPTY_RC=$?
fi
if [[ "$LAR_EMPTY_RC" -ne 0 && "$LOCAL_ADMISSION_OUTCOME" == blocked:empty_candidate_diff \
      && "$(git -C "$LAR_REPO" rev-parse HEAD)" == "$LAR_BASE_HEAD" \
      && ! -e "$LOCAL_ADMISSION_FIXTURE/locks/local-admission-receipts/.local-admission-TST-LOCAL-ADMISSION-pre_qa.json" ]]; then
  pass "LOCAL-ADMISSION-REAL-a: control artefacts alone are an empty implementation and cannot reach QA"
else
  fail "LOCAL-ADMISSION-REAL-a: empty implementation was not rejected before QA"
fi
printf 'change\n' > "$LAR_REPO/src/change.txt"
LOCK_DIR="$LOCAL_ADMISSION_FIXTURE/locks" TARGET_BRANCH=staging \
GAAI_LOCAL_ADMISSION_POLICY_PATH=.gaai/project/ci/local-admission.json \
  _prepare_pre_qa_admission TST-LOCAL-ADMISSION trace-real "$LAR_REPO"
LAR_PRE_RC=$?; LAR_PRE_RECEIPT="$GAAI_ADMISSION_RECEIPT"; LAR_PRE_SHA="$GAAI_ADMITTED_SHA"
if [[ "$LAR_PRE_RC" -eq 0 && -s "$LAR_PRE_RECEIPT" ]] \
    && git -C "$LAR_REPO" log -1 --format=%B | grep -q '^\[gaai-local-admission:pre_qa\]$' \
    && node -e 'const r=require(process.argv[1]);process.exit(r.boundary==="pre_qa"&&r.outcome==="pass"&&!r.publication_admitted&&r.results.every(x=>x.outcome==="passed")?0:1)' "$LAR_PRE_RECEIPT"; then
  pass "LOCAL-ADMISSION-REAL-b: implementation is sealed and real pre-QA commands PASS"
else
  fail "LOCAL-ADMISSION-REAL-b: real pre-QA boundary failed"
fi
mkdir -p "$LAR_REPO/.gaai/project/contexts/artefacts/qa-reports"
printf 'qa evidence\n' > "$LAR_REPO/.gaai/project/contexts/artefacts/qa-reports/TST-LOCAL-ADMISSION.qa-report.md"
git -C "$LAR_REPO" add -A; git -C "$LAR_REPO" commit -q -m 'final evidence'
LOCK_DIR="$LOCAL_ADMISSION_FIXTURE/locks" TARGET_BRANCH=staging \
GAAI_LOCAL_ADMISSION_POLICY_PATH=.gaai/project/ci/local-admission.json \
  _admit_current_candidate final TST-LOCAL-ADMISSION trace-real "$LAR_REPO"
LAR_FINAL_RC=$?; LAR_FINAL_RECEIPT="$GAAI_ADMISSION_RECEIPT"
if [[ "$LAR_FINAL_RC" -eq 0 && -s "$LAR_FINAL_RECEIPT" && "$LAR_FINAL_RECEIPT" != "$LAR_PRE_RECEIPT" \
      && "$GAAI_ADMITTED_SHA" != "$LAR_PRE_SHA" ]] \
    && node -e 'const r=require(process.argv[1]);process.exit(r.boundary==="final"&&r.outcome==="pass"&&r.publication_admitted?0:1)' "$LAR_FINAL_RECEIPT" \
    && [[ -z "$(git -C "$LAR_REPO" ls-remote --heads origin refs/heads/story/TST-LOCAL-ADMISSION)" ]]; then
  pass "LOCAL-ADMISSION-REAL-c: final receipt is distinct/current and no remote branch exists yet"
else
  fail "LOCAL-ADMISSION-REAL-c: final currentness/publication separation failed"
fi

# ── LOCAL-ADMISSION-AC4: every typed final rejection blocks remote calls ──
echo "LOCAL-ADMISSION-AC4: complete rejection matrix blocks publication"
AC4_REMOTE_LOG="$LOCAL_ADMISSION_FIXTURE/remote-calls.log"
git() {
  case " $* " in
    *" push "*|*" ls-remote "*) printf '%s\n' "$*" >> "$AC4_REMOTE_LOG" ;;
  esac
  command git "$@"
}
_admit_current_candidate() {
  _route_admission_block "$2" "$3" final "$_AC4_MATRIX_OUTCOME"
  return 1
}
for _matrix_outcome in "${AC4_MATRIX[@]}"; do
  _AC4_MATRIX_OUTCOME="$_matrix_outcome"
  : > "$AC4_REMOTE_LOG"
  if _auto_resolve_push /nonexistent "story/TST-LOCAL-ADMISSION" "" \
      TST-LOCAL-ADMISSION "trace-${_matrix_outcome//[:_]/-}" >/dev/null 2>&1; then
    fail "LOCAL-ADMISSION-AC4 ${_matrix_outcome}: rejected final admission returned success"
  elif [[ ! -s "$AC4_REMOTE_LOG" ]]; then
    pass "LOCAL-ADMISSION-AC4 ${_matrix_outcome}: no push or remote observation"
  else
    fail "LOCAL-ADMISSION-AC4 ${_matrix_outcome}: rejection reached a remote Git call"
  fi
done
unset -f git
unset _matrix_outcome _AC4_MATRIX_OUTCOME AC4_REMOTE_LOG AC4_MATRIX

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo "All tests PASSED."
  exit 0
else
  echo "SOME TESTS FAILED."
  exit 1
fi
