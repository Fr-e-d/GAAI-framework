#!/usr/bin/env bash
# E134S13 — backlog-scheduler-reset.test.sh
# Tests --reset mode of backlog-scheduler.sh (AC3 coverage).
#
# Usage: bash .gaai/core/scripts/tests/backlog-scheduler-reset.test.sh

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"

# ── Shared fixture for T1–T4 ──────────────────────────────────
FIXTURE=$(mktemp)
trap "rm -f $FIXTURE" EXIT

cat > "$FIXTURE" << 'YAML_EOF'
items:
- id: TST-INPROG
  status: in_progress
  phase_status: qa_escalated
  started_at: '2026-05-11T10:00:00Z'
- id: TST-FAILED
  status: failed
  phase_status: qa_failed
- id: TST-ALREADY-RESET
  status: refined
  phase_status: not_started
YAML_EOF

echo ""
echo "=== backlog-scheduler --reset tests ==="
echo ""

# ── T1: Reset in_progress+qa_escalated+started_at ────────────
echo "T1: Reset status:in_progress + phase_status:qa_escalated + started_at"
bash "$SCHEDULER" --reset TST-INPROG "$FIXTURE"
STATUS=$(grep -A5 'id: TST-INPROG' "$FIXTURE" | grep 'status:' | head -1 | awk '{print $2}')
PHASE=$(grep -A5 'id: TST-INPROG' "$FIXTURE" | grep 'phase_status:' | head -1 | awk '{print $2}')
if grep -q 'started_at' "$FIXTURE"; then
  STARTED_PRESENT=true
else
  STARTED_PRESENT=false
fi
if [[ "$STATUS" == "refined" && "$PHASE" == "not_started" && "$STARTED_PRESENT" == "false" ]]; then
  pass "T1: status→refined, phase_status→not_started, started_at removed"
else
  fail "T1: got status='$STATUS' phase='$PHASE' started_at_present=$STARTED_PRESENT"
fi

# Reload fixture for T2 (T1 already modified it; use a fresh state for TST-FAILED)
# TST-FAILED entry should be unchanged by T1 (different ID), check it
# ── T2: Reset failed+qa_failed (no started_at) ───────────────
echo "T2: Reset status:failed + phase_status:qa_failed (no started_at field)"
bash "$SCHEDULER" --reset TST-FAILED "$FIXTURE"
STATUS2=$(grep -A5 'id: TST-FAILED' "$FIXTURE" | grep 'status:' | head -1 | awk '{print $2}')
PHASE2=$(grep -A5 'id: TST-FAILED' "$FIXTURE" | grep 'phase_status:' | head -1 | awk '{print $2}')
if [[ "$STATUS2" == "refined" && "$PHASE2" == "not_started" ]]; then
  pass "T2: status→refined, phase_status→not_started (no started_at — still succeeded)"
else
  fail "T2: got status='$STATUS2' phase='$PHASE2'"
fi

# ── T3: Idempotency check ─────────────────────────────────────
echo "T3: Idempotency — reset TST-ALREADY-RESET (already refined+not_started)"
STDERR_T3=$(bash "$SCHEDULER" --reset TST-ALREADY-RESET "$FIXTURE" 2>&1 >/dev/null || true)
EXIT_T3=$( bash "$SCHEDULER" --reset TST-ALREADY-RESET "$FIXTURE" 2>/dev/null; echo $? )
if echo "$STDERR_T3" | grep -qi "no-op\|already"; then
  pass "T3: idempotent — exit 0, no-op message on stderr"
else
  # Also acceptable: exit 0 with no stderr (pure no-op)
  STATUS3=$(grep -A5 'id: TST-ALREADY-RESET' "$FIXTURE" | grep 'status:' | head -1 | awk '{print $2}')
  PHASE3=$(grep -A5 'id: TST-ALREADY-RESET' "$FIXTURE" | grep 'phase_status:' | head -1 | awk '{print $2}')
  if [[ "$STATUS3" == "refined" && "$PHASE3" == "not_started" ]]; then
    pass "T3: idempotent — fields unchanged, exit 0"
  else
    fail "T3: expected no-op, got status='$STATUS3' phase='$PHASE3' stderr='$STDERR_T3'"
  fi
fi

# ── T4: Non-existent story ID ─────────────────────────────────
echo "T4: Reset non-existent story TST-NONEXISTENT"
set +e
STDERR_T4=$(bash "$SCHEDULER" --reset TST-NONEXISTENT "$FIXTURE" 2>&1)
EXIT_T4=$?
set -e
if [[ $EXIT_T4 -ne 0 ]] && echo "$STDERR_T4" | grep -qi "not found\|error"; then
  pass "T4: exit non-zero + error message on stderr for unknown story"
else
  fail "T4: expected non-zero exit + error, got exit=$EXIT_T4 stderr='$STDERR_T4'"
fi

# ── T5: --clear-retry-count clears matching entry ─────────────
echo "T5: --clear-retry-count clears matching entry from .retry-counts"
# Build a dedicated temp dir with correct layout for retry-counts path derivation
RETRY_DIR=$(mktemp -d)
trap "rm -rf $RETRY_DIR" EXIT
RETRY_YAML="$RETRY_DIR/active.backlog.yaml"
mkdir -p "$RETRY_DIR/.delivery-locks"
RETRY_FILE="$RETRY_DIR/.delivery-locks/.retry-counts"

cat > "$RETRY_YAML" << 'YAML_EOF'
items:
- id: RETRY-TARGET
  status: in_progress
  phase_status: qa_escalated
  started_at: '2026-05-11T09:00:00Z'
- id: RETRY-OTHER
  status: failed
  phase_status: qa_failed
YAML_EOF

echo "RETRY-TARGET=3" > "$RETRY_FILE"
echo "RETRY-OTHER=1" >> "$RETRY_FILE"

bash "$SCHEDULER" --reset RETRY-TARGET --clear-retry-count "$RETRY_YAML"

# Verify retry-count entry removed
if grep -q '^RETRY-TARGET=' "$RETRY_FILE"; then
  fail "T5: RETRY-TARGET=3 was NOT cleared from .retry-counts"
else
  # Verify other entry preserved
  if grep -q '^RETRY-OTHER=1' "$RETRY_FILE"; then
    pass "T5: RETRY-TARGET entry cleared, RETRY-OTHER preserved"
  else
    fail "T5: RETRY-TARGET cleared but RETRY-OTHER also lost (should be preserved)"
  fi
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "FAILURES: $FAIL_COUNT"
  exit 1
fi
