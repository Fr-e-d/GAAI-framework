#!/usr/bin/env bash
# ── stale-race-mutex.test.sh ───────────────────────────────────────────────
# AC6 (E160S01): Stale-race mutex between wrapper EXIT trap and daemon staleness check
#
# T1: Marker fresh → verdict skipped
# T2: Marker stale (mtime beyond TTL) → verdict proceeds
# T3: No marker → verdict proceeds (current behavior unchanged)
# T4: Wrapper _reconcile_yaml_status_on_exit with read-only LOCK_DIR → no crash, warning logged
#
# Run: bash .gaai/core/scripts/tests/stale-race-mutex.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# ── Setup: temp dir for ephemeral LOCK_DIR fixture
TMPDIR_TEST="$(mktemp -d /tmp/gaai-stale-race-mutex-test-XXXXXX)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

LOCK_DIR="$TMPDIR_TEST/lock"
mkdir -p "$LOCK_DIR"

# ── marker_check_verdict: reproduces the AC2/AC4 logic from delivery-daemon.sh ──
# Returns "skip" if marker is fresh, "proceed" otherwise.
# Prints log lines to stdout for assertion.
marker_check_verdict() {
  local sid="$1"
  local now="$2"
  local ttl="${3:-90}"
  local _rip_marker="$LOCK_DIR/${sid}.reconcile-in-progress"

  if [[ -f "$_rip_marker" ]]; then
    local _rip_mtime=0
    if [[ "$(uname)" == "Darwin" ]]; then
      _rip_mtime=$(stat -f %m "$_rip_marker" 2>/dev/null || echo 0)
    else
      _rip_mtime=$(stat -c %Y "$_rip_marker" 2>/dev/null || echo 0)
    fi
    local _rip_age=$(( now - _rip_mtime ))
    if (( _rip_age <= ttl )); then
      echo "[STALE-CHECK] $sid : reconcile-in-progress marker fresh (age=${_rip_age}s, ttl=${ttl}s) — skipping (will recheck next tick)"
      echo "VERDICT:skip"
      return 0
    else
      echo "[STALE-CHECK] $sid : reconcile-in-progress marker stale (age=${_rip_age}s > ttl=${ttl}s) — proceeding with normal verdict"
      echo "VERDICT:proceed"
      return 0
    fi
  fi

  echo "VERDICT:proceed"
}

# ══════════════════════════════════════════════════════════════════════════════
# T1: Marker fresh → verdict skipped
# ══════════════════════════════════════════════════════════════════════════════
echo "T1: Fresh marker — staleness verdict should be skipped"

T1_SID="TST-S01"
touch "$LOCK_DIR/${T1_SID}.reconcile-in-progress"
T1_NOW=$(date +%s)

T1_OUT=$(marker_check_verdict "$T1_SID" "$T1_NOW" 90)
T1_VERDICT=$(echo "$T1_OUT" | grep "^VERDICT:" | head -1 | cut -d: -f2)

if [[ "$T1_VERDICT" == "skip" ]] && echo "$T1_OUT" | grep -q "reconcile-in-progress marker fresh"; then
  pass "T1: fresh marker → verdict skipped, log contains 'marker fresh'"
else
  fail "T1: expected verdict=skip with 'marker fresh' log, got: $T1_OUT"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T2: Marker stale (mtime beyond TTL) → verdict proceeds
# ══════════════════════════════════════════════════════════════════════════════
echo "T2: Stale marker — staleness verdict should proceed"

T2_SID="TST-S02"
touch "$LOCK_DIR/${T2_SID}.reconcile-in-progress"
# Set mtime to epoch 0 (always stale)
if [[ "$(uname)" == "Darwin" ]]; then
  touch -m -t 197001010000.00 "$LOCK_DIR/${T2_SID}.reconcile-in-progress"
else
  touch -m -d "1970-01-01 00:00:00" "$LOCK_DIR/${T2_SID}.reconcile-in-progress"
fi
T2_NOW=$(date +%s)

T2_OUT=$(marker_check_verdict "$T2_SID" "$T2_NOW" 90)
T2_VERDICT=$(echo "$T2_OUT" | grep "^VERDICT:" | head -1 | cut -d: -f2)

if [[ "$T2_VERDICT" == "proceed" ]] && echo "$T2_OUT" | grep -q "reconcile-in-progress marker stale"; then
  pass "T2: stale marker → verdict proceeds, log contains 'marker stale'"
else
  fail "T2: expected verdict=proceed with 'marker stale' log, got: $T2_OUT"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T3: No marker → verdict proceeds (current behavior unchanged)
# ══════════════════════════════════════════════════════════════════════════════
echo "T3: No marker — staleness verdict should proceed (unchanged behavior)"

T3_SID="TST-S03"
# Intentionally do NOT create any marker file
T3_NOW=$(date +%s)

T3_OUT=$(marker_check_verdict "$T3_SID" "$T3_NOW" 90)
T3_VERDICT=$(echo "$T3_OUT" | grep "^VERDICT:" | head -1 | cut -d: -f2)

if [[ "$T3_VERDICT" == "proceed" ]] && ! echo "$T3_OUT" | grep -q "reconcile-in-progress"; then
  pass "T3: no marker → verdict proceeds, no reconcile log line"
else
  fail "T3: expected verdict=proceed with no reconcile log, got: $T3_OUT"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T4: Wrapper _reconcile_yaml_status_on_exit with read-only LOCK_DIR → no crash
# ══════════════════════════════════════════════════════════════════════════════
echo "T4: Read-only LOCK_DIR — wrapper must not crash, warning logged"

T4_SID="TST-READONLY"
T4_LOCK_DIR="$TMPDIR_TEST/readonly-lock"
mkdir -p "$T4_LOCK_DIR"
chmod a-w "$T4_LOCK_DIR"

# Source daemon-dispatch.sh in a subshell with minimal env, capture output
T4_OUT=$(
  BACKLOG_FILE="/dev/null" \
  PROJECT_DIR="$TMPDIR_TEST" \
  SCHEDULER="$(which true)" \
  LOCK_DIR="$T4_LOCK_DIR" \
  bash -c '
    set -uo pipefail
    SCRIPT_DIR="'"$SCRIPT_DIR"'"
    # Source the dispatch script to get the function
    source "$SCRIPT_DIR/../daemon-dispatch.sh" 2>/dev/null || true
    _reconcile_yaml_status_on_exit "TST-READONLY" 2>&1
    echo "EXIT_CODE=$?"
  ' 2>&1
)

T4_EXIT=$(echo "$T4_OUT" | grep "^EXIT_CODE=" | head -1 | cut -d= -f2)

# Restore write permission for cleanup
chmod u+w "$T4_LOCK_DIR" 2>/dev/null || true

if [[ "$T4_EXIT" == "0" ]] && echo "$T4_OUT" | grep -q "warning — could not create reconcile-in-progress marker"; then
  pass "T4: read-only LOCK_DIR → no crash (exit 0), warning logged"
else
  fail "T4: expected exit=0 with warning, got exit=$T4_EXIT output=$(echo "$T4_OUT" | head -5)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== $PASS_COUNT/4 PASS ==="
exit $FAIL_COUNT
