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

# ── T4: dispatch not_started → planned ───────────────────────
echo "T4: dispatch not_started → planned"
TRACE="test-trace-$(date +%s)-001"
if dispatch_3phase_story "E134S01" "$TRACE"; then
  new_ps=$(get_phase_status "E134S01")
  if [[ "$new_ps" == "planned" ]]; then
    pass "T4a: phase_status advanced to 'planned'"
  else
    fail "T4a: expected 'planned', got '$new_ps'"
  fi
  if grep -q '"phase":"plan"' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"provider":"stub"' "$ROUTING_LOG" 2>/dev/null && \
     grep -q '"duration_ms":0' "$ROUTING_LOG" 2>/dev/null; then
    pass "T4b: routing.jsonl has plan+stub+duration_ms:0 record"
  else
    fail "T4b: routing.jsonl missing expected fields — content: $(cat "$ROUTING_LOG" 2>/dev/null | head -3)"
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

record_count=$(grep -c '"provider":"stub"' "$ROUTING_LOG" 2>/dev/null || echo "0")
if [[ "$record_count" -ge 3 ]]; then
  pass "T7d: routing.jsonl has $record_count stub records (>=3 expected)"
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
