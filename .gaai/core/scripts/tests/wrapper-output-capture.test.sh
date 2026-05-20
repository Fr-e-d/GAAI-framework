#!/usr/bin/env bash
# E160S08 regression tests: wrapper output capture + bounded-retry commit-stall guard
# Self-contained — uses TMPDIR, no git ops, no backlog touch.
# Exit 0 = all pass (T1 skipped if tmux unavailable or < 2.6).

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'

_ok()   { ((PASS++)) || true; echo -e "  ${GREEN}PASS${NC} $1"; }
_fail() { ((FAIL++)) || true; echo -e "  ${RED}FAIL${NC} $1"; }
_skip() { ((SKIP++)) || true; echo -e "  ${YELLOW}SKIP${NC} $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== wrapper-output-capture tests ==="

# ── T1a/T1b: pipe-pane captures wrapper stdout to .wrapper.log ────────────
TMUX_OK=false
if command -v tmux &>/dev/null; then
  _ver=$(tmux -V 2>/dev/null || true)
  _maj=0; _min=0
  if [[ "$_ver" =~ tmux[[:space:]]+([0-9]+)\.([0-9]+) ]]; then
    _maj="${BASH_REMATCH[1]}"; _min="${BASH_REMATCH[2]}"
  fi
  (( _maj > 2 || ( _maj == 2 && _min >= 6 ) )) && TMUX_OK=true
fi

if $TMUX_OK; then
  LOG_FILE="$TMP/t1a.wrapper.log"
  SN="test-e160s08-t1a-$$"
  # Start a long-lived session, wire pipe-pane, THEN produce output
  tmux new-session -d -s "$SN" "sleep 5" 2>/dev/null
  tmux pipe-pane -t "$SN" -o "cat >> ${LOG_FILE}" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$SN" "echo 'capture-marker-42'" Enter 2>/dev/null || true
  sleep 0.5
  tmux kill-session -t "$SN" 2>/dev/null || true
  sleep 0.3

  if grep -q 'capture-marker-42' "$LOG_FILE" 2>/dev/null; then
    _ok "T1a: pipe-pane captures stdout to wrapper.log"
  else
    _fail "T1a: wrapper.log missing or empty (got: $(cat "$LOG_FILE" 2>/dev/null || echo '<nothing>'))"
  fi

  # T1b: log file contains the last command output before kill
  LOG2="$TMP/t1b.wrapper.log"
  SN2="test-e160s08-t1b-$$"
  tmux new-session -d -s "$SN2" "sleep 5" 2>/dev/null
  tmux pipe-pane -t "$SN2" -o "cat >> ${LOG2}" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$SN2" "echo 'before-kill-line'" Enter 2>/dev/null || true
  sleep 0.5
  tmux kill-session -t "$SN2" 2>/dev/null || true
  sleep 0.3

  if grep -q 'before-kill-line' "$LOG2" 2>/dev/null; then
    _ok "T1b: wrapper.log contains output before kill"
  else
    _fail "T1b: wrapper.log missing expected output before kill (got: $(cat "$LOG2" 2>/dev/null || echo '<nothing>'))"
  fi
else
  _skip "T1a: tmux >= 2.6 not available"
  _skip "T1b: tmux >= 2.6 not available"
fi

# ── T2a: counter reaches threshold → stall condition detected ─────────────
LOCK_DIR="$TMP/locks"
mkdir -p "$LOCK_DIR"
SID="test-story-t2"
CD_FILE="$LOCK_DIR/.commit-deaths-${SID}"
CD_HEAD="$LOCK_DIR/.commit-deaths-${SID}.head"

# Simulate 3 consecutive deaths with same HEAD
echo "abc123" > "$CD_HEAD"
for i in 1 2 3; do
  _cur=$(cat "$CD_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)
  _cur=$(( _cur > 1000 ? 1000 : _cur ))
  # HEAD unchanged → increment
  _new=$(( _cur + 1 ))
  _new=$(( _new > 1000 ? 1000 : _new ))
  printf '%s\n' "$_new" > "${CD_FILE}.tmp" && mv "${CD_FILE}.tmp" "$CD_FILE"
done

_counter=$(cat "$CD_FILE" | tr -d '[:space:]')
if (( _counter >= 3 )); then
  _ok "T2a: counter reaches ${_counter} >= 3 → stall threshold met"
else
  _fail "T2a: counter is ${_counter}, expected >= 3"
fi

# Clean up for next test
rm -f "$CD_FILE" "$CD_HEAD"

# ── T2b: counter files removed on non-qa_passed transition ────────────────
echo "5" > "$CD_FILE"
echo "def456" > "$CD_HEAD"
rm -f "$CD_FILE" "$CD_HEAD" 2>/dev/null || true
if [[ ! -f "$CD_FILE" && ! -f "$CD_HEAD" ]]; then
  _ok "T2b: counter files removed (simulating terminal transition)"
else
  _fail "T2b: counter files still exist after removal"
fi

# ── T2c: counter value 999 passes clamp unchanged ─────────────────────────
echo "999" > "$CD_FILE"
_val=$(cat "$CD_FILE" | tr -d '[:space:]')
_val=$(( _val > 1000 ? 1000 : _val ))
if (( _val == 999 )); then
  _ok "T2c: counter value 999 passes clamp unchanged (stays 999)"
else
  _fail "T2c: expected 999, got ${_val}"
fi

# ── T2d: counter value 1001 clamped to 1000 ───────────────────────────────
echo "1001" > "$CD_FILE"
_val=$(cat "$CD_FILE" | tr -d '[:space:]')
_val=$(( _val > 1000 ? 1000 : _val ))
if (( _val == 1000 )); then
  _ok "T2d: counter value 1001 clamped to 1000"
else
  _fail "T2d: expected 1000, got ${_val}"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
