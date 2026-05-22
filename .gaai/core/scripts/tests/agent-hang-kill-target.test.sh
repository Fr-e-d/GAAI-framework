#!/usr/bin/env bash
# ── agent-hang-kill-target.test.sh ───────────────────────────────────────────
# E160S11 regression: kill agent subprocess (not wrapper) so EXIT trap runs
#
# T5: sidecar present + agent alive → agent killed, wrapper survives
# T6: sidecar present but agent dead → fallback kills wrapper
# T7: killing agent unblocks wrapper fifo-read → EXIT trap runs (AC3 regression)
#
# Run: bash .gaai/core/scripts/tests/agent-hang-kill-target.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

# ── Helpers ───────────────────────────────────────────────────────────────────

file_mtime() {
  local f="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f %m "$f" 2>/dev/null || echo 0
  else
    stat -c %Y "$f" 2>/dev/null || echo 0
  fi
}

backdate_file() {
  local f="$1" minutes_ago="$2"
  if [[ "$(uname)" == "Darwin" ]]; then
    local target_epoch=$(( $(date +%s) - (minutes_ago * 60) ))
    local fmt; fmt=$(date -u -r "$target_epoch" +"%Y%m%d%H%M.%S")
    touch -m -t "$fmt" "$f"
  else
    touch -m -d "${minutes_ago} minutes ago" "$f"
  fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────

TMPDIR_TEST="$(mktemp -d /tmp/gaai-agent-hang-kill-target-test-XXXXXX)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

LOCK_DIR="$TMPDIR_TEST/lock"
mkdir -p "$LOCK_DIR"

WORKTREE="$TMPDIR_TEST/worktree"
mkdir -p "$WORKTREE/.delivery-logs"

AGENT_HANG_THRESHOLD_SEC=480
HEARTBEAT_STALE=1800
RED='\033[0;31m'
NC='\033[0m'
AGENT_HANG_AUDIT="$LOCK_DIR/.agent-hang.audit"

_recovery_resolve_worktree() { echo "$WORKTREE"; }
log() { echo "$*"; }

# ── Inline function under test ────────────────────────────────────────────────
# Updated version with E160S11 sidecar logic. Uses sleep 2 (not 30) for speed.

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

    local _agent_pid_sidecar="$LOCK_DIR/${sid}.agent.pid"
    local _kill_pid="$pid"
    local _pid_kind="wrapper"
    if [[ -f "$_agent_pid_sidecar" ]]; then
      local _agent_pid
      _agent_pid=$(head -1 "$_agent_pid_sidecar" 2>/dev/null || echo "")
      if [[ -n "$_agent_pid" ]] && kill -0 "$_agent_pid" 2>/dev/null; then
        _kill_pid="$_agent_pid"
        _pid_kind="agent"
      fi
    fi

    log "${RED}[AGENT_HANG_DETECTED] $sid — log-mtime stale ($(( log_age / 60 ))min) heartbeat-fresh ($(( hb_age / 60 ))min) — SIGTERM ${_pid_kind} PID ${_kill_pid}${NC}"

    local _audit_ts
    _audit_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '{"event":"agent_hang_detected","ts":"%s","story_id":"%s","wrapper_pid":%s,"kill_pid":%s,"pid_kind":"%s","log_mtime_age_sec":%s,"heartbeat_age_sec":%s,"last_log_size_bytes":%s}\n' \
      "$_audit_ts" "$sid" "$pid" "$_kill_pid" "$_pid_kind" "$log_age" "$hb_age" "$log_size" \
      >> "$AGENT_HANG_AUDIT" 2>/dev/null || true

    touch "$hang_marker" 2>/dev/null || true

    kill -TERM "$_kill_pid" 2>/dev/null || true
    sleep 2
    if kill -0 "$_kill_pid" 2>/dev/null; then
      log "${RED}[AGENT_HANG_SIGKILL] $sid ${_pid_kind} PID ${_kill_pid} did not respond to SIGTERM${NC}"
      kill -KILL "$_kill_pid" 2>/dev/null || true
    fi
  done
}

# ══════════════════════════════════════════════════════════════════════════════
# T5: sidecar present + agent alive → agent killed, wrapper NOT killed
# ══════════════════════════════════════════════════════════════════════════════
echo "T5: Sidecar present + agent alive → agent killed, wrapper survives"

T5_SID="HKT-T5"

sleep 300 &
T5_WRAPPER_PID=$!
sleep 300 &
T5_AGENT_PID=$!

echo "$T5_WRAPPER_PID" > "$LOCK_DIR/${T5_SID}.lock"
backdate_file "$LOCK_DIR/${T5_SID}.lock" 10

echo "$T5_AGENT_PID" > "$LOCK_DIR/${T5_SID}.agent.pid"
touch "$LOCK_DIR/${T5_SID}.heartbeat"

echo '{}' > "$WORKTREE/.delivery-logs/${T5_SID}.impl.log"
backdate_file "$WORKTREE/.delivery-logs/${T5_SID}.impl.log" 10

T5_OUT=$(AGENT_HANG_THRESHOLD_SEC=480 HEARTBEAT_STALE=1800 check_agent_activity_stale 2>&1)
sleep 1

if ! kill -0 "$T5_AGENT_PID" 2>/dev/null; then
  pass "T5.1: agent subprocess killed"
else
  kill -9 "$T5_AGENT_PID" 2>/dev/null || true
  fail "T5.1: agent subprocess still alive"
fi

if kill -0 "$T5_WRAPPER_PID" 2>/dev/null; then
  pass "T5.2: wrapper process survived (not the kill target)"
  kill "$T5_WRAPPER_PID" 2>/dev/null || true
else
  fail "T5.2: wrapper process was killed unexpectedly"
fi

if echo "$T5_OUT" | grep -q "agent PID"; then
  pass "T5.3: log line identifies kill target as agent PID"
else
  fail "T5.3: expected 'agent PID' in output, got: $(echo "$T5_OUT" | head -3)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T6: sidecar present but agent already dead → fallback kills wrapper
# ══════════════════════════════════════════════════════════════════════════════
echo "T6: Sidecar present but agent dead → fallback kills wrapper"

T6_SID="HKT-T6"

sleep 300 &
T6_WRAPPER_PID=$!

echo "$T6_WRAPPER_PID" > "$LOCK_DIR/${T6_SID}.lock"
backdate_file "$LOCK_DIR/${T6_SID}.lock" 10

# Write a dead PID to sidecar (no such process)
echo "99999999" > "$LOCK_DIR/${T6_SID}.agent.pid"

touch "$LOCK_DIR/${T6_SID}.heartbeat"

echo '{}' > "$WORKTREE/.delivery-logs/${T6_SID}.impl.log"
backdate_file "$WORKTREE/.delivery-logs/${T6_SID}.impl.log" 10

T6_OUT=$(AGENT_HANG_THRESHOLD_SEC=480 HEARTBEAT_STALE=1800 check_agent_activity_stale 2>&1)
sleep 1

if ! kill -0 "$T6_WRAPPER_PID" 2>/dev/null; then
  pass "T6.1: wrapper killed (fallback — sidecar PID was dead)"
else
  kill -9 "$T6_WRAPPER_PID" 2>/dev/null || true
  fail "T6.1: wrapper still alive (should have been killed as fallback)"
fi

if echo "$T6_OUT" | grep -q "wrapper PID"; then
  pass "T6.2: log line identifies kill target as wrapper PID (fallback)"
else
  fail "T6.2: expected 'wrapper PID' in output, got: $(echo "$T6_OUT" | head -3)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T7: killing agent unblocks wrapper fifo-read → EXIT trap runs (AC3 regression)
# ══════════════════════════════════════════════════════════════════════════════
echo "T7: Kill agent → fifo unblocks → wrapper EXIT trap runs"

T7_SID="HKT-T7"
T7_FIFO="$TMPDIR_TEST/t7-fifo"
mkfifo "$T7_FIFO"
T7_MARKER="$TMPDIR_TEST/t7-exit-trap-ran"

# Agent: holds fifo write end open as fd 3 (single process — kill cleanly closes fd)
sleep 600 3>"$T7_FIFO" &
T7_AGENT_PID=$!

# Wrapper: blocks reading from fifo, writes marker on EXIT (simulates daemon-dispatch EXIT trap)
(
  trap "touch '$T7_MARKER'" EXIT
  while IFS= read -r _line; do :; done < "$T7_FIFO"
) &
T7_WRAPPER_PID=$!

# Wait for both sides to open the fifo and enter their respective blocking states
sleep 1

echo "$T7_WRAPPER_PID" > "$LOCK_DIR/${T7_SID}.lock"
backdate_file "$LOCK_DIR/${T7_SID}.lock" 10
echo "$T7_AGENT_PID" > "$LOCK_DIR/${T7_SID}.agent.pid"
touch "$LOCK_DIR/${T7_SID}.heartbeat"

echo '{}' > "$WORKTREE/.delivery-logs/${T7_SID}.impl.log"
backdate_file "$WORKTREE/.delivery-logs/${T7_SID}.impl.log" 10

AGENT_HANG_THRESHOLD_SEC=480 HEARTBEAT_STALE=1800 check_agent_activity_stale 2>&1

# Poll for wrapper EXIT trap to run (up to 5s)
_deadline=$(( $(date +%s) + 5 ))
while [[ ! -f "$T7_MARKER" ]] && (( $(date +%s) < _deadline )); do
  sleep 0.2
done

kill "$T7_WRAPPER_PID" 2>/dev/null || true

if [[ -f "$T7_MARKER" ]]; then
  pass "T7.1: wrapper EXIT trap ran after agent was killed (fifo unblocked)"
else
  fail "T7.1: wrapper EXIT trap did not run — fifo block was not released"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== $PASS_COUNT/6 PASS ==="
exit $FAIL_COUNT
