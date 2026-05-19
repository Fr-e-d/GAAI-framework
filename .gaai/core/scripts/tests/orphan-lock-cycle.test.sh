#!/usr/bin/env bash
# orphan-lock-cycle.test.sh — regression tests for E160S02 cycle-time orphan-lock scan
#
# T1: lock file with live PID → not touched, log silent
# T2: lock file with dead PID + story in_progress → orphan detected, recovery invoked,
#     story reverted to refined, chore commit matches [daemon-recovery:] pattern
# T3: lock file with dead PID + story already done → lock removed without side-effect
#
# Usage: bash .gaai/core/scripts/tests/orphan-lock-cycle.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../delivery-daemon.sh"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"
BACKLIB="$SCRIPT_DIR/../lib/backlog-yaml.sh"

# ── Fixture setup ──────────────────────────────────────────────────────────────
FIXTURE_DIR="/tmp/gaai-orphan-lock-test-$$"
mkdir -p "$FIXTURE_DIR"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── Git repo helper ────────────────────────────────────────────────────────────
setup_git_repo() {
  local project_dir="$1" content="$2"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  mkdir -p "$project_dir/.gaai/project/contexts/backlog"
  printf '%s\n' "$content" > "$project_dir/.gaai/project/contexts/backlog/active.backlog.yaml"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push origin HEAD -q
}

# ── Harness builder ────────────────────────────────────────────────────────────
# Creates a bash script that sources cycle_orphan_lock_scan + crash_recovery_scan
# from delivery-daemon.sh via awk extraction, with all stubs and fixture paths.
build_harness() {
  local harness="$1"
  local project_dir="$2"
  local lock_dir="$3"
  local log_file="$4"
  local backlog_rel=".gaai/project/contexts/backlog/active.backlog.yaml"

  cat > "$harness" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail

PROJECT_DIR="$project_dir"
GAAI_PROJECT_DIR="$project_dir/.gaai/project"
BACKLOG_REL="$backlog_rel"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$lock_dir"
LOG_DIR="$FIXTURE_DIR/logs"
LOG_FILE="$log_file"
STAGING_LOCK="\$LOCK_DIR/.staging.lock"
RETRY_FILE="\$LOCK_DIR/.retry-counts"
RESOLUTION_TRACKING="\$LOCK_DIR/.resolution-tracking"
DRIFT_MARKER="\$LOCK_DIR/.drift-detected.audit"
SCHEDULER="$SCHEDULER"
TARGET_BRANCH="main"
DRY_RUN=false
STALENESS_THRESHOLD=14400
POLL_INTERVAL=30
MAX_CONCURRENT=3
EXIT_WHEN_IDLE_THRESHOLD=0
MAX_RETRIES=3
DELIVERY_TIMEOUT=14400
MAX_TURNS=200
CLAUDE_MODEL=sonnet
HEARTBEAT_STALE=1800
ORPHAN_SCAN_INTERVAL_TICKS=1
ORPHAN_SCAN_MAX_DURATION_SEC=30
SKIP_PERMISSIONS=true
STATUS_MODE=false
NOTIFICATION_WEBHOOK=""
WEBHOOK_SECRET=""
PLATFORM="\$(uname)"
LAUNCHER="tmux"
CLAUDE_FLAGS="--model sonnet --max-turns 200 --output-format stream-json --verbose"
CAFFEINATE_PID=""

mkdir -p "\$LOG_DIR" "\$LOCK_DIR"

RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

log() {
  local msg="[\$(date '+%H:%M:%S')] \$*"
  echo -e "\$msg" >> "\$LOG_FILE"
}

launch_3phase_in_tmux() { return 0; }
with_staging_lock() { "\$@"; }
notify_escalation() { return 0; }
is_locked() { [[ -f "\$LOCK_DIR/\$1.lock" ]]; }
file_mtime() { stat -f %m "\$1" 2>/dev/null || stat -c %Y "\$1" 2>/dev/null || echo 0; }
get_retry_count() { echo 0; }
increment_retry() { return 0; }
clean_stale_locks() { return 0; }

fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/main:\$BACKLOG_REL" 2>/dev/null \\
    || git -C "\$PROJECT_DIR" show "HEAD:\$BACKLOG_REL" 2>/dev/null \\
    || cat "\$BACKLOG"
}

_recovery_resolve_worktree() { echo "/nonexistent/\$1-workspace"; }
_recovery_relaunch() { return 0; }
_recovery_revert_refined() {
  local sid="\$1"
  # Simulate the revert: update YAML to refined + commit
  local bl="\$BACKLOG"
  if [[ -f "\$bl" ]]; then
    sed -i.bak "s/status: in_progress/status: refined/" "\$bl" 2>/dev/null || true
    rm -f "\$bl.bak"
    git -C "\$PROJECT_DIR" add "\$BACKLOG_REL" 2>/dev/null || true
    git -C "\$PROJECT_DIR" commit -m "chore(\$sid): [daemon-recovery:orphan-lock] reverted" -q 2>/dev/null || true
  fi
}
_recovery_set_status() { return 0; }

# Source backlog-yaml helpers
source "$BACKLIB" 2>/dev/null || true

# Extract functions from delivery-daemon.sh
eval "\$(awk '
  /^cycle_orphan_lock_scan\(\)/{p=1; depth=0}
  /^crash_recovery_scan\(\)/{p=1; depth=0}
  /^_write_drift_marker\(\)/{p=1; depth=0}
  /^_clear_drift_marker_if_clean\(\)/{p=1; depth=0}
  p {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == "{") depth++
      if (c == "}") depth--
    }
    if (p && depth == 0 && NR > 1) { p=0 }
  }
' "$DAEMON" 2>/dev/null)"

# Source backlog helper functions from lib
eval "\$(awk '
  /^backlog_status\(\)/{p=1; depth=0}
  /^backlog_in_progress_ids\(\)/{p=1; depth=0}
  /^backlog_phase_status\(\)/{p=1; depth=0}
  p {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == "{") depth++
      if (c == "}") depth--
    }
    if (p && depth == 0 && NR > 1) { p=0 }
  }
' "$BACKLIB" 2>/dev/null)"
HARNESS

  chmod +x "$harness"
}

# ═══════════════════════════════════════════════════════════════════════════════
# T1 — Lock file with live PID → not touched
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: live PID lock file not touched ==="

T1_DIR="$FIXTURE_DIR/t1-project"
T1_LOCK_DIR="$FIXTURE_DIR/t1-locks"
T1_LOG="$FIXTURE_DIR/t1-daemon.log"
T1_STORY="TST-ORPHAN-T1"
mkdir -p "$T1_LOCK_DIR"
touch "$T1_LOG"

T1_YAML="items:
- id: $T1_STORY
  status: in_progress
  phase_status: implementing
  delivery_pipeline: 3phase"
setup_git_repo "$T1_DIR" "$T1_YAML"

# Create a live PID using a background sleep
sleep 300 &
T1_LIVE_PID=$!

echo "$T1_LIVE_PID" > "$T1_LOCK_DIR/$T1_STORY.lock"

T1_HARNESS=$(mktemp /tmp/t1-harness-XXXXXX.sh)
build_harness "$T1_HARNESS" "$T1_DIR" "$T1_LOCK_DIR" "$T1_LOG"

# Append the test call to the harness
cat >> "$T1_HARNESS" <<'T1CALL'
cycle_orphan_lock_scan
T1CALL

bash "$T1_HARNESS" 2>/dev/null

# Verify: lock file still exists
if [[ -f "$T1_LOCK_DIR/$T1_STORY.lock" ]]; then
  pass "T1: lock file still exists (not removed)"
else
  fail "T1: lock file was incorrectly removed for live PID"
fi

# Verify: story still in_progress
T1_STATUS=$(grep 'status:' "$T1_DIR/.gaai/project/contexts/backlog/active.backlog.yaml" | head -1 | awk '{print $2}')
if [[ "$T1_STATUS" == "in_progress" ]]; then
  pass "T1: story status unchanged (in_progress)"
else
  fail "T1: story status changed unexpectedly to $T1_STATUS"
fi

# Verify: no orphan detection in log
if grep -q "dead PID.*detected" "$T1_LOG" 2>/dev/null; then
  fail "T1: false positive — dead PID detected for live process"
else
  pass "T1: no false positive orphan detection"
fi

kill $T1_LIVE_PID 2>/dev/null || true
rm -f "$T1_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T2 — Dead PID + story in_progress → orphan detected, recovery invoked
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: dead PID triggers recovery and revert ==="

T2_DIR="$FIXTURE_DIR/t2-project"
T2_LOCK_DIR="$FIXTURE_DIR/t2-locks"
T2_LOG="$FIXTURE_DIR/t2-daemon.log"
T2_STORY="TST-ORPHAN-T2"
mkdir -p "$T2_LOCK_DIR"
touch "$T2_LOG"

T2_YAML="items:
- id: $T2_STORY
  status: in_progress
  phase_status: not_started
  delivery_pipeline: 3phase"
setup_git_repo "$T2_DIR" "$T2_YAML"

# Create a dead PID: spawn sleep, record PID, kill it
sleep 300 &
T2_DEAD_PID=$!
kill -9 $T2_DEAD_PID 2>/dev/null
sleep 0.2  # ensure process is reaped

echo "$T2_DEAD_PID" > "$T2_LOCK_DIR/$T2_STORY.lock"

T2_HARNESS=$(mktemp /tmp/t2-harness-XXXXXX.sh)
build_harness "$T2_HARNESS" "$T2_DIR" "$T2_LOCK_DIR" "$T2_LOG"

# Append the test call
cat >> "$T2_HARNESS" <<'T2CALL'
cycle_orphan_lock_scan
T2CALL

bash "$T2_HARNESS" 2>/dev/null

# Verify: lock file removed
if [[ ! -f "$T2_LOCK_DIR/$T2_STORY.lock" ]]; then
  pass "T2: lock file removed after orphan detection"
else
  fail "T2: lock file still exists after orphan detection"
fi

# Verify: orphan detection logged
if grep -q "\[CYCLE-ORPHAN\].*dead PID.*detected" "$T2_LOG" 2>/dev/null; then
  pass "T2: orphan detection logged"
else
  fail "T2: no orphan detection log line found"
fi

# Verify: recovery classification logged
if grep -q "\[CYCLE-ORPHAN\].*recovery classified" "$T2_LOG" 2>/dev/null; then
  pass "T2: recovery classification logged"
else
  fail "T2: no recovery classification log line found"
fi

# Verify: scan summary logged
if grep -q "\[CYCLE-ORPHAN\].*scan complete" "$T2_LOG" 2>/dev/null; then
  pass "T2: scan complete summary logged"
else
  fail "T2: no scan complete summary log line"
fi

# Verify: story status reverted to refined after recovery
T2_STATUS=$(grep 'status:' "$T2_DIR/.gaai/project/contexts/backlog/active.backlog.yaml" | head -1 | awk '{print $2}')
if [[ "$T2_STATUS" == "refined" ]]; then
  pass "T2: story status reverted to refined after recovery"
else
  fail "T2: story status not refined after recovery — got: $T2_STATUS"
fi

# Verify: chore commit matches [daemon-recovery:] pattern
T2_LAST_COMMIT=$(git -C "$T2_DIR" log --oneline | head -1)
if echo "$T2_LAST_COMMIT" | grep -q "\[daemon-recovery:"; then
  pass "T2: commit message matches [daemon-recovery:] pattern"
else
  fail "T2: commit message does not match [daemon-recovery:] pattern — got: $T2_LAST_COMMIT"
fi

rm -f "$T2_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T3 — Dead PID + story already done → lock removed without side-effect
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: dead PID with done story — lock removed, no YAML change ==="

T3_DIR="$FIXTURE_DIR/t3-project"
T3_LOCK_DIR="$FIXTURE_DIR/t3-locks"
T3_LOG="$FIXTURE_DIR/t3-daemon.log"
T3_STORY="TST-ORPHAN-T3"
mkdir -p "$T3_LOCK_DIR"
touch "$T3_LOG"

# Story is done (wrapper finished + YAML reconciled but lock survived)
T3_YAML="items:
- id: $T3_STORY
  status: done
  phase_status: done
  delivery_pipeline: 3phase"
setup_git_repo "$T3_DIR" "$T3_YAML"

# Create a dead PID
sleep 300 &
T3_DEAD_PID=$!
kill -9 $T3_DEAD_PID 2>/dev/null
sleep 0.2

echo "$T3_DEAD_PID" > "$T3_LOCK_DIR/$T3_STORY.lock"

T3_HARNESS=$(mktemp /tmp/t3-harness-XXXXXX.sh)
build_harness "$T3_HARNESS" "$T3_DIR" "$T3_LOCK_DIR" "$T3_LOG"

cat >> "$T3_HARNESS" <<'T3CALL'
cycle_orphan_lock_scan
T3CALL

bash "$T3_HARNESS" 2>/dev/null

# Verify: lock file removed
if [[ ! -f "$T3_LOCK_DIR/$T3_STORY.lock" ]]; then
  pass "T3: lock file removed"
else
  fail "T3: lock file still exists"
fi

# Verify: story still done (no re-classification side-effect)
T3_STATUS=$(grep 'status:' "$T3_DIR/.gaai/project/contexts/backlog/active.backlog.yaml" | head -1 | awk '{print $2}')
if [[ "$T3_STATUS" == "done" ]]; then
  pass "T3: story status unchanged (done)"
else
  fail "T3: story status changed unexpectedly to $T3_STATUS"
fi

rm -f "$T3_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Results: $PASS_COUNT PASS, $FAIL_COUNT FAIL ==="

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
