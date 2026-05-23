#!/usr/bin/env bash
# ── agent-activity-stale.test.sh ─────────────────────────────────────────
# AC5 (E160S07): Agent-activity stale detector — log-mtime check
#
# T1: heartbeat fresh + log stale → AGENT_HANG_DETECTED emitted, PID SIGTERM'd
# T2: heartbeat fresh + log fresh → no-op (no SIGTERM)
# T3: reconcile-in-progress marker fresh → skipped (no AGENT_HANG_DETECTED)
#
# Run: bash .gaai/core/scripts/tests/agent-activity-stale.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

# ── Helpers ───────────────────────────────────────────────────────────────

# Cross-platform file_mtime (mirrors delivery-daemon.sh)
file_mtime() {
  local f="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f %m "$f" 2>/dev/null || echo 0
  else
    stat -c %Y "$f" 2>/dev/null || echo 0
  fi
}

# Cross-platform mtime backdating
backdate_file() {
  local f="$1"
  local minutes_ago="$2"
  if [[ "$(uname)" == "Darwin" ]]; then
    local target_epoch=$(( $(date +%s) - (minutes_ago * 60) ))
    local fmt=$(date -u -r "$target_epoch" +"%Y%m%d%H%M.%S")
    touch -m -t "$fmt" "$f"
  else
    touch -m -d "${minutes_ago} minutes ago" "$f"
  fi
}

# ── Setup: temp dirs ─────────────────────────────────────────────────────

TMPDIR_TEST="$(mktemp -d /tmp/gaai-agent-activity-stale-test-XXXXXX)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

LOCK_DIR="$TMPDIR_TEST/lock"
mkdir -p "$LOCK_DIR"

WORKTREE="$TMPDIR_TEST/worktree"
mkdir -p "$WORKTREE/.delivery-logs"

# Override constants
AGENT_HANG_THRESHOLD_SEC=480
HEARTBEAT_STALE=1800
RED='\033[0;31m'
NC='\033[0m'
AGENT_HANG_AUDIT="$LOCK_DIR/.agent-hang.audit"

# Mock _recovery_resolve_worktree: returns our temp worktree
_recovery_resolve_worktree() {
  echo "$WORKTREE"
}

# Mock log: prints to stdout for capture
log() {
  echo "$*"
}

# ── The function under test (extracted from delivery-daemon.sh) ──────────

check_agent_activity_stale() {
  local now
  now=$(date +%s)

  for lock in "$LOCK_DIR"/*.lock; do
    [[ -f "$lock" ]] || continue
    local sid pid
    sid=$(basename "$lock" .lock)
    pid=$(head -1 "$lock" 2>/dev/null || echo "")
    [[ -z "$pid" || "$pid" == "pending" ]] && continue

    kill -0 "$pid" 2>/dev/null || continue

    local lock_age=$(( now - $(file_mtime "$lock") ))
    (( lock_age < AGENT_HANG_THRESHOLD_SEC )) && continue

    local _rip_marker="$LOCK_DIR/${sid}.reconcile-in-progress"
    local _rip_ttl="${GAAI_RECONCILE_GRACE_SEC:-90}"
    if [[ -f "$_rip_marker" ]]; then
      local _rip_mtime
      _rip_mtime=$(file_mtime "$_rip_marker")
      local _rip_age=$(( now - _rip_mtime ))
      if (( _rip_age <= _rip_ttl )); then
        continue
      fi
    fi

    local hb_file="$LOCK_DIR/${sid}.heartbeat"
    [[ -f "$hb_file" ]] || continue
    local hb_age=$(( now - $(file_mtime "$hb_file") ))
    (( hb_age > HEARTBEAT_STALE )) && continue

    local worktree_path
    worktree_path=$(_recovery_resolve_worktree "$sid")
    local impl_log="${worktree_path}/.delivery-logs/${sid}.impl.log"

    local hang_marker="$LOCK_DIR/${sid}.agent-hang.marker"
    if [[ -f "$hang_marker" && -f "$impl_log" ]]; then
      local _fresh_mtime
      _fresh_mtime=$(file_mtime "$impl_log")
      if (( _fresh_mtime > 0 )); then
        local _fresh_age=$(( now - _fresh_mtime ))
        if (( _fresh_age < AGENT_HANG_THRESHOLD_SEC )); then
          log "[AGENT_HANG_RESOLVED] $sid"
          rm -f "$hang_marker" 2>/dev/null || true
          continue
        fi
      fi
    fi

    [[ -f "$impl_log" ]] || continue

    local _log_mtime
    _log_mtime=$(file_mtime "$impl_log")
    (( _log_mtime == 0 )) && continue

    local log_age=$(( now - _log_mtime ))
    (( log_age <= AGENT_HANG_THRESHOLD_SEC )) && continue

    local log_size=0
    log_size=$(wc -c < "$impl_log" 2>/dev/null | tr -d ' ' || echo 0)

    log "${RED}[AGENT_HANG_DETECTED] $sid — log-mtime stale ($(( log_age / 60 ))min) heartbeat-fresh ($(( hb_age / 60 ))min) — SIGTERM PID $pid${NC}"

    local _audit_ts
    _audit_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '{"event":"agent_hang_detected","ts":"%s","story_id":"%s","wrapper_pid":%s,"log_mtime_age_sec":%s,"heartbeat_age_sec":%s,"last_log_size_bytes":%s}\n' \
      "$_audit_ts" "$sid" "$pid" "$log_age" "$hb_age" "$log_size" \
      >> "$AGENT_HANG_AUDIT" 2>/dev/null || true

    touch "$hang_marker" 2>/dev/null || true

    kill -TERM "$pid" 2>/dev/null || true
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
      log "${RED}[AGENT_HANG_SIGKILL] $sid PID $pid did not respond to SIGTERM${NC}"
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
}

# ══════════════════════════════════════════════════════════════════════════════
# T1: heartbeat fresh + log stale → AGENT_HANG_DETECTED + SIGTERM
# ══════════════════════════════════════════════════════════════════════════════
echo "T1: Heartbeat fresh + log stale → AGENT_HANG_DETECTED, PID SIGTERM'd"

T1_SID="TST-ACTIVE01"

# Start a mock wrapper process
sleep 300 &
T1_PID=$!

# Create lock file with PID, backdated past grace period
echo "$T1_PID" > "$LOCK_DIR/${T1_SID}.lock"
backdate_file "$LOCK_DIR/${T1_SID}.lock" 10

# Fresh heartbeat
touch "$LOCK_DIR/${T1_SID}.heartbeat"

# Stale impl.log (10 min ago > 480s = 8min threshold)
echo '{"type":"tool_use"}' > "$WORKTREE/.delivery-logs/${T1_SID}.impl.log"
backdate_file "$WORKTREE/.delivery-logs/${T1_SID}.impl.log" 10

# Run function (using 2s sleep instead of 30s for test speed)
T1_OUT=$(AGENT_HANG_THRESHOLD_SEC=480 HEARTBEAT_STALE=1800 check_agent_activity_stale 2>&1)

# Give SIGTERM time to propagate
sleep 1

# Check process was killed
if ! kill -0 "$T1_PID" 2>/dev/null; then
  pass "T1.1: mock wrapper process was SIGTERM'd"
else
  kill -9 "$T1_PID" 2>/dev/null || true
  fail "T1.1: mock wrapper process still alive after check"
fi

if echo "$T1_OUT" | grep -q "AGENT_HANG_DETECTED"; then
  pass "T1.2: output contains AGENT_HANG_DETECTED"
else
  fail "T1.2: expected AGENT_HANG_DETECTED in output, got: $(echo "$T1_OUT" | head -5)"
fi

if echo "$T1_OUT" | grep -q "$T1_SID"; then
  pass "T1.3: log line references correct story ID"
else
  fail "T1.3: expected story ID $T1_SID in output"
fi

# Check audit file written
if [[ -f "$AGENT_HANG_AUDIT" ]] && grep -q "agent_hang_detected" "$AGENT_HANG_AUDIT"; then
  pass "T1.4: audit file contains agent_hang_detected event"
else
  fail "T1.4: audit file missing or does not contain event"
fi

# Check hang marker written
if [[ -f "$LOCK_DIR/${T1_SID}.agent-hang.marker" ]]; then
  pass "T1.5: hang marker file created"
else
  fail "T1.5: hang marker file not created"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T2: heartbeat fresh + log fresh → no-op (no SIGTERM)
# ══════════════════════════════════════════════════════════════════════════════
echo "T2: Heartbeat fresh + log fresh → no-op"

T2_SID="TST-ACTIVE02"

sleep 300 &
T2_PID=$!

echo "$T2_PID" > "$LOCK_DIR/${T2_SID}.lock"
backdate_file "$LOCK_DIR/${T2_SID}.lock" 10

touch "$LOCK_DIR/${T2_SID}.heartbeat"

# Fresh impl.log (just written)
echo '{"type":"tool_use"}' > "$WORKTREE/.delivery-logs/${T2_SID}.impl.log"

T2_OUT=$(AGENT_HANG_THRESHOLD_SEC=480 HEARTBEAT_STALE=1800 check_agent_activity_stale 2>&1)
sleep 1

if kill -0 "$T2_PID" 2>/dev/null; then
  pass "T2.1: mock wrapper process still alive (no SIGTERM)"
  kill "$T2_PID" 2>/dev/null || true
else
  fail "T2.1: mock wrapper was killed unexpectedly (should be no-op)"
fi

if ! echo "$T2_OUT" | grep -q "AGENT_HANG_DETECTED"; then
  pass "T2.2: output does NOT contain AGENT_HANG_DETECTED (healthy agent)"
else
  fail "T2.2: unexpected AGENT_HANG_DETECTED for healthy agent"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T3: reconcile-in-progress marker fresh → skipped
# ══════════════════════════════════════════════════════════════════════════════
echo "T3: reconcile-in-progress marker fresh → skipped"

T3_SID="TST-ACTIVE03"

sleep 300 &
T3_PID=$!

echo "$T3_PID" > "$LOCK_DIR/${T3_SID}.lock"
backdate_file "$LOCK_DIR/${T3_SID}.lock" 10

touch "$LOCK_DIR/${T3_SID}.heartbeat"

# Stale impl.log (like T1)
echo '{"type":"tool_use"}' > "$WORKTREE/.delivery-logs/${T3_SID}.impl.log"
backdate_file "$WORKTREE/.delivery-logs/${T3_SID}.impl.log" 10

# Fresh reconcile-in-progress marker
touch "$LOCK_DIR/${T3_SID}.reconcile-in-progress"

T3_OUT=$(AGENT_HANG_THRESHOLD_SEC=480 HEARTBEAT_STALE=1800 check_agent_activity_stale 2>&1)
sleep 1

if kill -0 "$T3_PID" 2>/dev/null; then
  pass "T3.1: mock wrapper process still alive (reconcile guard active)"
  kill "$T3_PID" 2>/dev/null || true
else
  fail "T3.1: mock wrapper was killed despite fresh reconcile marker"
fi

if ! echo "$T3_OUT" | grep -q "AGENT_HANG_DETECTED"; then
  pass "T3.2: output does NOT contain AGENT_HANG_DETECTED (guard skipped)"
else
  fail "T3.2: AGENT_HANG_DETECTED emitted despite fresh reconcile marker"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== $PASS_COUNT/9 PASS ==="
exit $FAIL_COUNT
