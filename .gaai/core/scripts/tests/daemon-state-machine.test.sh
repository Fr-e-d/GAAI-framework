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
}
trap cleanup EXIT

cat > "$FIXTURE" << 'YAML_EOF'
- id: E133S01
  status: done
  phase_status: done
  delivery_pipeline: legacy
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

# shellcheck disable=SC1090
source "$DISPATCH_LIB"

echo "E134S02 — daemon-state-machine dispatch tests"
echo ""

# ── T1: get_delivery_pipeline returns correct value ───────────
echo "T1: get_delivery_pipeline — legacy story"
result=$(get_delivery_pipeline "E133S01")
if [[ "$result" == "legacy" ]]; then
  pass "T1: get_delivery_pipeline returns 'legacy' for E133S01"
else
  fail "T1: expected 'legacy', got '$result'"
fi

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

DISPATCH_SHIM_DIR="$DISPATCH_FIXTURE_DIR/shims"
mkdir -p "$DISPATCH_SHIM_DIR"
cat > "$DISPATCH_SHIM_DIR/claude" << 'DISPATCH_SHIM_EOF'
#!/usr/bin/env bash
if [[ -n "${GAAI_QA_REPORT_PATH:-}" ]]; then
  printf '## AC1\npass\n\n## Verdict: PASS\n' > "${GAAI_QA_REPORT_PATH}"
elif [[ -n "${GAAI_PLAN_PATH:-}" ]]; then
  printf '## Implementation Sequence\nStep 1.\n' > "${GAAI_PLAN_PATH}"
fi
exit 0
DISPATCH_SHIM_EOF
chmod +x "$DISPATCH_SHIM_DIR/claude"

# git shim for commit phase (T7c): intercept push → exit 0, delegate rest to real git
DISPATCH_REAL_GIT_BIN="$(command -v git)"
export DISPATCH_REAL_GIT_BIN
cat > "$DISPATCH_SHIM_DIR/git" << 'DISPATCH_GIT_SHIM_EOF'
#!/usr/bin/env bash
_i=0; _args=("$@")
while [[ $_i -lt ${#_args[@]} ]]; do
  [[ "${_args[$_i]}" == "-C" ]] && { _i=$(( _i + 2 )); continue; }
  break
done
[[ "${_args[$_i]:-}" == "push" ]] && exit 0
exec "$DISPATCH_REAL_GIT_BIN" "$@"
DISPATCH_GIT_SHIM_EOF
chmod +x "$DISPATCH_SHIM_DIR/git"

# gh shim for commit phase (T7c): returns fake PR URL
cat > "$DISPATCH_SHIM_DIR/gh" << 'DISPATCH_GH_SHIM_EOF'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "pr create") echo "https://github.com/test/repo/pull/999"; exit 0 ;;
  "pr view")
    [[ "$*" == *"--json url"* ]] && { echo "https://github.com/test/repo/pull/999"; exit 0; }
    [[ "$*" == *"--json number"* ]] && { echo "999"; exit 0; }
    [[ "$*" == *"--json autoMergeRequest"* ]] && { echo '{"mergeMethod":"squash"}'; exit 0; }
    exit 0 ;;
  *) exit 0 ;;
esac
DISPATCH_GH_SHIM_EOF
chmod +x "$DISPATCH_SHIM_DIR/gh"

# ── Impl-phase fixture worktrees for T5 and T7 ───────────────────────────────
# handle_impl_phase resolves worktrees as: $GAAI_WORKTREES_BASE/{story_id}-workspace
export GAAI_WORKTREES_BASE="$DISPATCH_FIXTURE_DIR"

for _impl_id in E134S01 TST-3PHASE-PLANNED; do
  _wt="$DISPATCH_FIXTURE_DIR/${_impl_id}-workspace"
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
  _t5_report="$DISPATCH_FIXTURE_DIR/TST-3PHASE-PLANNED-workspace/.gaai/project/contexts/artefacts/impl-reports/TST-3PHASE-PLANNED.impl-report.md"
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
unset _t7_qa _t7_commit

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
unset DISPATCH_REAL_NODE IMPL_SPAWN_STUB_PATH DISPATCH_FIXTURE_DIR DISPATCH_SHIM_DIR DISPATCH_OLD_PATH
rm -rf "/tmp/gaai-dispatch-tests-$$"

# ── T9-T14: handle_plan_phase real spawn tests ────────────────
# These tests exercise handle_plan_phase directly (not via dispatch_3phase_story)
# using a claude shim injected earlier in PATH.

# Setup: shared fixtures for T9-T14
PLAN_FIXTURE_DIR="/tmp/gaai-plan-phase-tests-$$"
rm -rf "$PLAN_FIXTURE_DIR"
mkdir -p "$PLAN_FIXTURE_DIR"

# Fixture story file (minimal — just needs 'epic:' field parseable by grep)
PLAN_STORY_ID="TST-PLAN-01"
PLAN_STORY_PATH="$PLAN_FIXTURE_DIR/${PLAN_STORY_ID}.story.md"
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

PLAN_WORKTREE="$PLAN_FIXTURE_DIR/worktree"
mkdir -p "$PLAN_WORKTREE/.gaai/project/contexts/artefacts/plans"
mkdir -p "$PLAN_WORKTREE/.delivery-logs"
# Place the story file inside the worktree at the canonical path
mkdir -p "$PLAN_WORKTREE/.gaai/project/contexts/artefacts/stories"
cp "$PLAN_STORY_PATH" "$PLAN_WORKTREE/.gaai/project/contexts/artefacts/stories/${PLAN_STORY_ID}.story.md"

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
export GAAI_WORKSPACE_ID="test-workspace"
export GAAI_ORG_ID="test-org"
export CLAUDE_MODEL_PRIMARY="claude-sonnet-4-6"

# Point PROJECT_DIR to the test project dir so handle_plan_phase finds planning.daemon-prompt.md
export PROJECT_DIR_ORIG="$PROJECT_DIR"
export PROJECT_DIR="$SCRIPT_DIR/../../../.."

# ── T9: successful Plan phase spawn — phase_status advances ──
echo "T9: handle_plan_phase — mock claude exits 0, valid plan output"
make_success_shim
"$SCHEDULER" --set-phase-status "$PLAN_STORY_ID" not_started "$FIXTURE" 2>/dev/null || true
rm -f "$PLAN_PATH"
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
STUB_PROMPT_FILE=$(mktemp /tmp/gaai-test-prompt-XXXXXX.md)
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
STUB_PROMPT_FILE_T20=$(mktemp /tmp/gaai-test-prompt-XXXXXX.md)
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

# Helper: write claude shim that emits a specific verdict
make_qa_claude_shim() {
  local verdict="$1"
  cat > "$QA_SHIM_DIR/claude" << QASHIM_EOF
#!/usr/bin/env bash
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

# claude shim that exits 0 but writes a report without a verdict marker
make_qa_claude_badverdict_shim() {
  cat > "$QA_SHIM_DIR/claude" << 'QABADVERDICT_EOF'
#!/usr/bin/env bash
if [[ -n "${GAAI_QA_REPORT_PATH:-}" ]]; then
  printf '## AC1\npass\n\nNo verdict marker here.\n' > "${GAAI_QA_REPORT_PATH}"
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
else
  fail "T22a: handle_qa_phase returned non-zero for PASS verdict"
  fail "T22b: (skipped — T22a failed)"
fi

# ── T23: QA FAIL verdict → qa_failed ─────────────────────────
echo "T23: handle_qa_phase — FAIL verdict → qa_failed"
make_qa_claude_shim "FAIL"
"$SCHEDULER" --set-phase-status "TST-QA-FAIL" implemented "$FIXTURE" 2>/dev/null || true
> "$ROUTING_LOG"
TRACE="test-trace-$(date +%s)-023"

if handle_qa_phase "TST-QA-FAIL" "$TRACE" 2>/dev/null; then
  fail "T23a: expected non-zero return for FAIL verdict, got 0"
  fail "T23b: (skipped)"
else
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
YAML_COMMIT

# Helper: create a real git worktree with optional story auto_merge frontmatter
make_commit_worktree() {
  local sid="$1" auto_merge_val="${2:-}"
  local wt="$COMMIT_FIXTURE_DIR/${sid}-workspace"
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
}

# Create worktrees for all commit test stories (TST-COMMIT-SKIPMERGE created separately below)
for _csid in TST-COMMIT-01 TST-COMMIT-NOTITLE TST-COMMIT-AUTOMERGE TST-COMMIT-PUSHFAIL TST-COMMIT-ALREADY-DONE; do
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
export COMMIT_REAL_GIT GAAI_SHIM_PUSH_FAIL GAAI_SHIM_GH_AUTH_FAIL GAAI_SHIM_GH_PR_EXISTS
export GAAI_SHIM_AUTOMERGE_NULL GAAI_SHIM_AUTOMERGE_FAIL
GAAI_SHIM_PUSH_FAIL=0
GAAI_SHIM_GH_AUTH_FAIL=0
GAAI_SHIM_GH_PR_EXISTS=0
GAAI_SHIM_AUTOMERGE_NULL=0
GAAI_SHIM_AUTOMERGE_FAIL=0

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
  exit 0
fi
exec "$COMMIT_REAL_GIT" "$@"
GIT_SHIM_EOF
chmod +x "$COMMIT_SHIM_DIR/git"

COMMIT_CALL_LOG="$COMMIT_FIXTURE_DIR/gh-calls.log"

cat > "$COMMIT_SHIM_DIR/gh" << 'GH_SHIM_EOF'
#!/usr/bin/env bash
# gh shim — configurable mock for PR operations
PR_CREATE_CALLED_FILE="${GAAI_COMMIT_CALL_LOG:-/tmp/gaai-gh-calls.log}"

_args=("$@")
_cmd="${_args[0]:-} ${_args[1]:-}"

case "$_cmd" in
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

# ── T44: dispatch qa_passed → done via full commit phase ───────
echo "T44: dispatch_3phase_story — qa_passed → done via handle_commit_phase"
> "$ROUTING_LOG"
make_commit_worktree "TST-COMMIT-01"
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

# Cleanup commit phase test fixtures
export PATH="$COMMIT_OLD_PATH"
unset GAAI_WORKTREES_BASE GAAI_SKIP_AUTO_MERGE GAAI_AUTO_MERGE_POLICY
unset GAAI_SHIM_PUSH_FAIL GAAI_SHIM_GH_AUTH_FAIL GAAI_SHIM_GH_PR_EXISTS
unset GAAI_SHIM_AUTOMERGE_NULL GAAI_SHIM_AUTOMERGE_FAIL GAAI_COMMIT_CALL_LOG
unset COMMIT_OLD_PATH COMMIT_FIXTURE_DIR COMMIT_SHIM_DIR COMMIT_REAL_GIT COMMIT_CALL_LOG
rm -rf "/tmp/gaai-commit-phase-tests-$$"

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
