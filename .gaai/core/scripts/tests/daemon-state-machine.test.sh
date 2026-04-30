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
# handle_plan_phase is now the real spawn (E134S03), not a stub.
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
if [[ -n "${GAAI_PLAN_PATH:-}" ]]; then
  printf '## Implementation Sequence\nStep 1.\n' > "$GAAI_PLAN_PATH"
fi
exit 0
DISPATCH_SHIM_EOF
chmod +x "$DISPATCH_SHIM_DIR/claude"
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
  if grep -q '"phase":"impl"' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"provider":"stub"' "$ROUTING_LOG" 2>/dev/null; then
    pass "T5b: routing.jsonl has impl+stub record"
  else
    fail "T5b: routing.jsonl missing expected impl+stub fields"
  fi
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

record_count=$(grep -c '"provider":"stub"' "$ROUTING_LOG" 2>/dev/null || true)
record_count=${record_count:-0}
if [[ "$record_count" -ge 3 ]]; then
  pass "T7d: routing.jsonl has $record_count stub records (>=3 expected — impl+qa+commit)"
else
  fail "T7d: expected >=3 stub records, found $record_count"
fi

# ── T8: dispatch on terminal state (done) returns 0 without crashing ──────
echo "T8: dispatch on done state returns 0"
TRACE="test-trace-$(date +%s)-005"
if dispatch_3phase_story "E134S01" "$TRACE" 2>/dev/null; then
  pass "T8: dispatch on done state returns 0 (no crash, no advance)"
else
  fail "T8: dispatch on done state returned non-zero"
fi

# Cleanup T4-T8 dispatch fixtures
export PATH="$DISPATCH_OLD_PATH"
unset GAAI_WORKTREE_PATH CLAUDE_MODEL_PRIMARY DISPATCH_FIXTURE_DIR DISPATCH_SHIM_DIR DISPATCH_OLD_PATH
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
