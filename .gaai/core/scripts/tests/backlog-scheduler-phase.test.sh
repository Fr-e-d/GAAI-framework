#!/usr/bin/env bash
# E134S01 — backlog-scheduler-phase.test.sh
# Tests --set-phase-status and --set-pipeline modes of backlog-scheduler.sh.
#
# Usage: bash .gaai/core/scripts/tests/backlog-scheduler-phase.test.sh

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"

# ── Create fixture in /tmp ────────────────────────────────────
FIXTURE=$(mktemp)
trap "rm -f $FIXTURE" EXIT

cat > "$FIXTURE" << 'YAML_EOF'
items:
- id: TST-REFINED
  status: refined
  phase_status: not_started
  delivery_pipeline: 3phase
- id: TST-DONE
  status: done
  phase_status: done
  delivery_pipeline: legacy
YAML_EOF

echo "E134S01 — backlog-scheduler-phase tests"
echo ""

# ── T1: --set-phase-status valid value ───────────────────────
echo "T1: --set-phase-status valid value"
OUT=$(bash "$SCHEDULER" --set-phase-status TST-REFINED planned "$FIXTURE" 2>&1)
# (a) field updated in file
if grep -q 'phase_status: planned' "$FIXTURE"; then
  pass "T1a: phase_status updated to planned in file"
else
  fail "T1a: phase_status not updated — file content: $(grep phase_status $FIXTURE)"
fi
# (b) YAML still parses
if python3 -c "import yaml; yaml.safe_load(open('$FIXTURE'))" 2>/dev/null; then
  pass "T1b: YAML parses after set-phase-status"
else
  fail "T1b: YAML parse failed after set-phase-status"
fi
# (c) stdout confirmation
if echo "$OUT" | grep -q 'TST-REFINED phase_status -> planned'; then
  pass "T1c: stdout confirmation line present"
else
  fail "T1c: expected 'TST-REFINED phase_status -> planned', got: $OUT"
fi

# ── T2: --set-phase-status invalid value exits 1 ─────────────
echo "T2: --set-phase-status invalid value"
if bash "$SCHEDULER" --set-phase-status TST-REFINED invalid_val "$FIXTURE" 2>/dev/null; then
  fail "T2: expected exit 1 for invalid phase_status, got exit 0"
else
  pass "T2: exits 1 for invalid phase_status value"
fi

# ── T3: --set-pipeline valid value ───────────────────────────
echo "T3: --set-pipeline valid value"
OUT=$(bash "$SCHEDULER" --set-pipeline TST-REFINED legacy "$FIXTURE" 2>&1)
# (a) field updated in file
if grep -q 'delivery_pipeline: legacy' "$FIXTURE"; then
  pass "T3a: delivery_pipeline updated to legacy in file"
else
  fail "T3a: delivery_pipeline not updated — file content: $(grep delivery_pipeline $FIXTURE)"
fi
# (b) YAML still parses
if python3 -c "import yaml; yaml.safe_load(open('$FIXTURE'))" 2>/dev/null; then
  pass "T3b: YAML parses after set-pipeline"
else
  fail "T3b: YAML parse failed after set-pipeline"
fi
# (c) stdout confirmation
if echo "$OUT" | grep -q 'TST-REFINED pipeline -> legacy'; then
  pass "T3c: stdout confirmation line present"
else
  fail "T3c: expected 'TST-REFINED pipeline -> legacy', got: $OUT"
fi

# ── T4: --set-pipeline invalid value exits 1 ─────────────────
echo "T4: --set-pipeline invalid value"
if bash "$SCHEDULER" --set-pipeline TST-REFINED invalid_val "$FIXTURE" 2>/dev/null; then
  fail "T4: expected exit 1 for invalid pipeline, got exit 0"
else
  pass "T4: exits 1 for invalid delivery_pipeline value"
fi

# ── T5: --set-status existing mode still works ───────────────
echo "T5: --set-status existing mode still works"
OUT=$(bash "$SCHEDULER" --set-status TST-DONE cancelled "$FIXTURE" 2>&1)
if grep -q 'status: cancelled' "$FIXTURE"; then
  pass "T5: --set-status unaffected by new modes"
else
  fail "T5: --set-status broken — file: $(grep 'status:' $FIXTURE)"
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
