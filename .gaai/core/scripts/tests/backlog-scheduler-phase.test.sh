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
JOURNAL_REPO=$(mktemp -d "${TMPDIR:-/tmp}/scheduler-journal-test.XXXXXX")
cleanup() {
  rm -f "$FIXTURE"
  case "$JOURNAL_REPO" in
    "${TMPDIR:-/tmp}"/scheduler-journal-test.*) rm -rf "$JOURNAL_REPO" ;;
  esac
}
trap cleanup EXIT

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

OUT=$(bash "$SCHEDULER" --set-field TST-REFINED blocked_reason true "$FIXTURE" 2>&1)
DIRECT_REASON_TYPE=$(python3 -c '
import sys, yaml
item = yaml.safe_load(open(sys.argv[1]))["items"][0]
print(type(item["blocked_reason"]).__name__)
' "$FIXTURE")
if [[ "$DIRECT_REASON_TYPE" == bool ]] && grep -q 'blocked_reason: true' "$FIXTURE"; then
  pass "T5b: direct blocked_reason true keeps legacy YAML boolean behavior"
else
  fail "T5b: direct set-field drifted: type=$DIRECT_REASON_TYPE out=$OUT"
fi

# ── Journal fixture: tracked source blob in an isolated repository ──────────
mkdir -p "$JOURNAL_REPO/.gaai/project/contexts/backlog"
JOURNAL_BACKLOG="$JOURNAL_REPO/.gaai/project/contexts/backlog/active.backlog.yaml"
cat > "$JOURNAL_BACKLOG" <<'YAML_EOF'
items:
- id: J-REFINED
  status: refined
  phase_status: not_started
  pr_status: null
YAML_EOF
git -C "$JOURNAL_REPO" init -q
git -C "$JOURNAL_REPO" config user.email test@example.invalid
git -C "$JOURNAL_REPO" config user.name backlog-scheduler-test
git -C "$JOURNAL_REPO" add .
git -C "$JOURNAL_REPO" commit -qm init
JOURNAL_DIR="$JOURNAL_REPO/journal"

# ── T6: journal-set emits durably, then applies existing set-field ──────────
echo "T6: --journal-set valid mutation"
OUT=$(GAAI_BACKLOG_JOURNAL_DIR="$JOURNAL_DIR" bash "$SCHEDULER" \
  --journal-set J-REFINED status in_progress "$JOURNAL_BACKLOG" 2>&1)
if [[ "$?" -eq 0 ]] && grep -q 'status: in_progress' "$JOURNAL_BACKLOG"; then
  pass "T6a: emitted journal record authorizes working-copy mutation"
else
  fail "T6a: valid journal-set failed: $OUT"
fi
JOURNAL_RECORD_COUNT=$(find "$JOURNAL_DIR/writers" -path '*/records/*.json' -type f | wc -l | tr -d ' ')
if [[ "$JOURNAL_RECORD_COUNT" -eq 1 ]]; then
  pass "T6b: exactly one durable record precedes mutation"
else
  fail "T6b: expected one journal record, got $JOURNAL_RECORD_COUNT"
fi

OUT=$(GAAI_BACKLOG_JOURNAL_DIR="$JOURNAL_DIR" bash "$SCHEDULER" \
  --journal-set J-REFINED blocked_reason 'json:"true"' "$JOURNAL_BACKLOG" 2>&1)
BLOCKED_REASON_TYPE=$(python3 -c '
import sys, yaml
item = yaml.safe_load(open(sys.argv[1]))["items"][0]
print(type(item["blocked_reason"]).__name__)
' "$JOURNAL_BACKLOG")
if [[ "$?" -eq 0 && "$BLOCKED_REASON_TYPE" == str ]] \
    && grep -q 'blocked_reason: "true"' "$JOURNAL_BACKLOG"; then
  pass "T6c: policy text remains YAML text after mutation"
else
  fail "T6c: blocked_reason type drifted: type=$BLOCKED_REASON_TYPE out=$OUT"
fi

git -C "$JOURNAL_REPO" add .gaai/project/contexts/backlog/active.backlog.yaml
git -C "$JOURNAL_REPO" commit -qm typed-reason-source
OUT=$(GAAI_BACKLOG_JOURNAL_DIR="$JOURNAL_DIR" bash "$SCHEDULER" \
  --journal-set J-REFINED blocked_reason 'json:"null"' "$JOURNAL_BACKLOG" 2>&1)
EXACT_NULL_TYPE=$(python3 -c '
import sys, yaml
item = yaml.safe_load(open(sys.argv[1]))["items"][0]
print(type(item["blocked_reason"]).__name__)
' "$JOURNAL_BACKLOG")
if [[ "$?" -eq 0 && "$EXACT_NULL_TYPE" == str ]] \
    && grep -q 'blocked_reason: "null"' "$JOURNAL_BACKLOG"; then
  pass "T6d: exact text null remains distinct from YAML null"
else
  fail "T6d: exact text null drifted: type=$EXACT_NULL_TYPE out=$OUT"
fi

# Restore only the working-copy fixture. HEAD remains the canonical source blob.
git -C "$JOURNAL_REPO" checkout -q -- .gaai/project/contexts/backlog/active.backlog.yaml

# ── T7: rejected fields never mutate or append ─────────────────────────────
echo "T7: --journal-set rejected field"
PREIMAGE=$(git -C "$JOURNAL_REPO" hash-object "$JOURNAL_BACKLOG")
set +e
GAAI_BACKLOG_JOURNAL_DIR="$JOURNAL_DIR" bash "$SCHEDULER" \
  --journal-set J-REFINED retry_count 1 "$JOURNAL_BACKLOG" >"$JOURNAL_REPO/t7.out" 2>&1
T7_RC=$?
set -e
POSTIMAGE=$(git -C "$JOURNAL_REPO" hash-object "$JOURNAL_BACKLOG")
POST_REJECT_COUNT=$(find "$JOURNAL_DIR/writers" -path '*/records/*.json' -type f | wc -l | tr -d ' ')
if [[ "$T7_RC" -eq 5 && "$PREIMAGE" == "$POSTIMAGE" && "$POST_REJECT_COUNT" -eq 3 ]]; then
  pass "T7: policy rejection exits 5 with no record or mutation"
else
  fail "T7: rc=$T7_RC pre=$PREIMAGE post=$POSTIMAGE records=$POST_REJECT_COUNT"
fi

# ── T8: crash-after-publish and replay remain non-authorizing ───────────────
echo "T8: pending replay never mutates"
source "$SCRIPT_DIR/../lib/backlog-journal.sh"
export GAAI_BACKLOG_JOURNAL_DIR="$JOURNAL_DIR"
backlog_journal_begin_run "$JOURNAL_BACKLOG" backlog-scheduler.journal-set
REPLAY_TOKEN="$BACKLOG_JOURNAL_RUN_TOKEN"
PREIMAGE=$(git -C "$JOURNAL_REPO" hash-object "$JOURNAL_BACKLOG")
set +e
GAAI_BACKLOG_JOURNAL_FAULT=after_record_publish \
GAAI_BACKLOG_JOURNAL_RUN_TOKEN="$REPLAY_TOKEN" \
  bash "$SCHEDULER" --journal-set J-REFINED pr_status open "$JOURNAL_BACKLOG" \
  >"$JOURNAL_REPO/t8-first.out" 2>&1
T8_FIRST_RC=$?
GAAI_BACKLOG_JOURNAL_RUN_TOKEN="$REPLAY_TOKEN" \
  bash "$SCHEDULER" --journal-set J-REFINED pr_status open "$JOURNAL_BACKLOG" \
  >"$JOURNAL_REPO/t8-replay.out" 2>&1
T8_REPLAY_RC=$?
set -e
POSTIMAGE=$(git -C "$JOURNAL_REPO" hash-object "$JOURNAL_BACKLOG")
if [[ "$T8_FIRST_RC" -eq 5 && "$T8_REPLAY_RC" -eq 6 && "$PREIMAGE" == "$POSTIMAGE" ]] \
    && grep -q 'pending:replay' "$JOURNAL_REPO/t8-replay.out"; then
  pass "T8: interrupted append and replay preserve backlog"
else
  fail "T8: first=$T8_FIRST_RC replay=$T8_REPLAY_RC pre=$PREIMAGE post=$POSTIMAGE"
fi

# ── T9: missing library is a distinct closed failure ───────────────────────
echo "T9: journal library unavailable"
mkdir -p "$JOURNAL_REPO/no-lib"
cp "$SCHEDULER" "$JOURNAL_REPO/no-lib/backlog-scheduler.sh"
set +e
bash "$JOURNAL_REPO/no-lib/backlog-scheduler.sh" \
  --journal-set J-REFINED status in_progress "$JOURNAL_BACKLOG" >/dev/null 2>&1
T9_RC=$?
set -e
if [[ "$T9_RC" -eq 4 ]]; then
  pass "T9: missing library exits 4"
else
  fail "T9: expected 4, got $T9_RC"
fi

# ── T10: invalid writer context is non-authorizing ─────────────────────────
echo "T10: invalid writer context"
PREIMAGE=$(git -C "$JOURNAL_REPO" hash-object "$JOURNAL_BACKLOG")
set +e
GAAI_BACKLOG_JOURNAL_DIR="$JOURNAL_DIR" \
GAAI_BACKLOG_JOURNAL_WRITER_CONTEXT='../bad writer' \
  bash "$SCHEDULER" --journal-set J-REFINED status in_progress "$JOURNAL_BACKLOG" \
  >/dev/null 2>&1
T10_RC=$?
set -e
POSTIMAGE=$(git -C "$JOURNAL_REPO" hash-object "$JOURNAL_BACKLOG")
if [[ "$T10_RC" -eq 5 && "$PREIMAGE" == "$POSTIMAGE" ]]; then
  pass "T10: invalid writer exits 5 without mutation"
else
  fail "T10: rc=$T10_RC pre=$PREIMAGE post=$POSTIMAGE"
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
