#!/usr/bin/env bash
# pr-watcher.test.sh — regression tests for the PR merge watcher
#
# Covers: watch_pr_merge_status(), _reconcile_merged_pr(), sweep_cleanup_pending()
# All 8 acceptance-criteria tests (T1–T8).
#
# Usage: bash .gaai/core/scripts/tests/pr-watcher.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../delivery-daemon.sh"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"

FIXTURE_DIR="/tmp/gaai-pr-watcher-test-$$"
mkdir -p "$FIXTURE_DIR"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── Git repo helper ────────────────────────────────────────────────────────────
# Creates a bare remote + local clone with content committed to the `staging` branch.
setup_git_repo() {
  local project_dir="$1" content="$2"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  # Use `staging` branch (matches TARGET_BRANCH in harnesses)
  git -C "$project_dir" checkout -b staging -q 2>/dev/null || git -C "$project_dir" checkout staging -q
  local backlog_dir="$project_dir/.gaai/project/contexts/backlog"
  mkdir -p "$backlog_dir"
  printf '%s\n' "$content" > "$backlog_dir/active.backlog.yaml"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push -u origin staging -q
}

# ── Mock gh helper ─────────────────────────────────────────────────────────────
# Creates a mock `gh` binary that reads MOCK_GH_RESPONSE and MOCK_GH_EXIT from env.
create_mock_gh() {
  local mock_dir="$1"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "${MOCK_GH_RESPONSE:-{}}"
exit "${MOCK_GH_EXIT:-0}"
MOCK_EOF
  chmod +x "$mock_dir/gh"
}

# ── Harness builder ────────────────────────────────────────────────────────────
# Builds a minimal test harness that sources the three new watcher functions
# from delivery-daemon.sh via awk extraction.
build_harness() {
  local harness_file="$1"
  local project_dir="$2"
  local lock_dir="$3"
  local daemon_log="$4"
  local mock_gh_dir="$5"
  local extra_env="${6:-}"

  local backlog_rel=".gaai/project/contexts/backlog/active.backlog.yaml"

  cat > "$harness_file" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
# Mock gh must be first in PATH so auth checks pass
export PATH="$mock_gh_dir:\$PATH"

PROJECT_DIR="$project_dir"
GAAI_PROJECT_DIR="$project_dir/.gaai/project"
BACKLOG_REL="$backlog_rel"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$lock_dir"
LOG_DIR="$lock_dir/logs"
DRIFT_MARKER="$lock_dir/.drift-detected.audit"
LOG_FILE="$daemon_log"
STAGING_LOCK="\$LOCK_DIR/.staging.lock"
RETRY_FILE="\$LOCK_DIR/.retry-counts"
RESOLUTION_TRACKING="\$LOCK_DIR/.resolution-tracking"
SCHEDULER="$SCHEDULER"
TARGET_BRANCH="staging"
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
SKIP_PERMISSIONS=true
STATUS_MODE=false
NOTIFICATION_WEBHOOK=""
WEBHOOK_SECRET=""
PLATFORM="\$(uname)"
LAUNCHER="tmux"
CLAUDE_FLAGS="--model sonnet --max-turns 200"
CAFFEINATE_PID=""

$extra_env

mkdir -p "\$LOG_DIR" "\$LOCK_DIR"

# Color stubs (no terminal in test harness)
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

log() {
  local msg="[\$(date '+%H:%M:%S')] \$*"
  echo -e "\$msg" | sed 's/\o033\[[0-9;]*m//g' >> "\$LOG_FILE"
}

with_staging_lock() { "\$@"; }
file_mtime() { stat -f %m "\$1" 2>/dev/null || stat -c %Y "\$1" 2>/dev/null || echo 0; }

# Extract the three new watcher functions from delivery-daemon.sh
eval "\$(awk '
  /^sweep_cleanup_pending\(\)/{p=1; depth=0}
  /^watch_pr_merge_status\(\)/{p=1; depth=0}
  /^_reconcile_merged_pr\(\)/{p=1; depth=0}
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
HARNESS
}

# ═══════════════════════════════════════════════════════════════════════════════
# T1: pr_url set + gh returns mergedAt:null → story stays in_progress
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: no reconcile when mergedAt is null ==="

T1_DIR="$FIXTURE_DIR/t1-project"
T1_LOCK="$FIXTURE_DIR/t1-locks"
T1_LOG="$FIXTURE_DIR/t1.log"
T1_MOCK_GH="$FIXTURE_DIR/t1-mock-gh"
mkdir -p "$T1_LOCK"
touch "$T1_LOG"

T1_SID="T1-STORY-01"
T1_YAML="- id: $T1_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/42
  delivery_pipeline: 3phase"

setup_git_repo "$T1_DIR" "$T1_YAML"
create_mock_gh "$T1_MOCK_GH"
export MOCK_GH_RESPONSE='{"mergedAt":null,"state":"OPEN","baseRefName":"staging"}'
export MOCK_GH_EXIT=0

T1_HARNESS=$(mktemp "$FIXTURE_DIR/t1-XXXXXX.sh")
build_harness "$T1_HARNESS" "$T1_DIR" "$T1_LOCK" "$T1_LOG" "$T1_MOCK_GH"
printf 'watch_pr_merge_status\n' >> "$T1_HARNESS"
chmod +x "$T1_HARNESS"
bash "$T1_HARNESS" 2>/dev/null

T1_STATUS=$(git -C "$T1_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null \
  | grep "status:" | head -1 | awk '{print $2}' || echo "")

if [[ "$T1_STATUS" == "in_progress" ]]; then
  pass "T1: story stayed in_progress when mergedAt is null"
else
  fail "T1: expected in_progress, got '$T1_STATUS'"
fi
rm -f "$T1_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T2: gh returns mergedAt + state:MERGED + baseRefName:staging → reconcile to done
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: reconcile to done when mergedAt is non-null and targets staging ==="

T2_DIR="$FIXTURE_DIR/t2-project"
T2_LOCK="$FIXTURE_DIR/t2-locks"
T2_LOG="$FIXTURE_DIR/t2.log"
T2_MOCK_GH="$FIXTURE_DIR/t2-mock-gh"
mkdir -p "$T2_LOCK"
touch "$T2_LOG"

T2_SID="T2-STORY-02"
T2_YAML="- id: $T2_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/99
  delivery_pipeline: 3phase"

setup_git_repo "$T2_DIR" "$T2_YAML"
create_mock_gh "$T2_MOCK_GH"
export MOCK_GH_RESPONSE='{"mergedAt":"2026-05-11T10:00:00Z","state":"MERGED","baseRefName":"staging"}'
export MOCK_GH_EXIT=0

T2_HARNESS=$(mktemp "$FIXTURE_DIR/t2-XXXXXX.sh")
build_harness "$T2_HARNESS" "$T2_DIR" "$T2_LOCK" "$T2_LOG" "$T2_MOCK_GH"
printf 'watch_pr_merge_status\n' >> "$T2_HARNESS"
chmod +x "$T2_HARNESS"
bash "$T2_HARNESS" 2>/dev/null

T2_BACKLOG=$(git -C "$T2_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null \
  || cat "$T2_DIR/.gaai/project/contexts/backlog/active.backlog.yaml")
T2_STATUS=$(printf '%s\n' "$T2_BACKLOG" | grep "status:" | head -1 | awk '{print $2}' || echo "")
T2_PHASE=$(printf '%s\n' "$T2_BACKLOG" | grep "phase_status:" | head -1 | awk '{print $2}' || echo "")

if [[ "$T2_STATUS" == "done" ]]; then
  pass "T2: status reconciled to done"
else
  fail "T2: expected done, got '$T2_STATUS'"
fi

if [[ "$T2_PHASE" == "done" ]]; then
  pass "T2: phase_status reconciled to done"
else
  fail "T2: expected phase_status=done, got '$T2_PHASE'"
fi

if printf '%s\n' "$T2_BACKLOG" | grep -q "completed_at:"; then
  pass "T2: completed_at field set"
else
  fail "T2: completed_at field missing"
fi
rm -f "$T2_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T3: gh returns state:CLOSED + mergedAt:null → .pr-abandoned.audit + flag, no double-emit
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: PR closed without merge — single emission, no double-emit (MEDIUM-F6) ==="

T3_DIR="$FIXTURE_DIR/t3-project"
T3_LOCK="$FIXTURE_DIR/t3-locks"
T3_LOG="$FIXTURE_DIR/t3.log"
T3_MOCK_GH="$FIXTURE_DIR/t3-mock-gh"
mkdir -p "$T3_LOCK"
touch "$T3_LOG"

T3_SID="T3-STORY-03"
T3_YAML="- id: $T3_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/55
  delivery_pipeline: 3phase"

setup_git_repo "$T3_DIR" "$T3_YAML"
create_mock_gh "$T3_MOCK_GH"
export MOCK_GH_RESPONSE='{"mergedAt":null,"state":"CLOSED","baseRefName":"staging"}'
export MOCK_GH_EXIT=0

T3_HARNESS=$(mktemp "$FIXTURE_DIR/t3-XXXXXX.sh")
build_harness "$T3_HARNESS" "$T3_DIR" "$T3_LOCK" "$T3_LOG" "$T3_MOCK_GH"
printf 'watch_pr_merge_status\n' >> "$T3_HARNESS"
chmod +x "$T3_HARNESS"

# First poll
bash "$T3_HARNESS" 2>/dev/null

T3_AUDIT="$T3_LOCK/.pr-abandoned.audit"
T3_FLAG="$T3_LOCK/.pr-abandoned.emitted.${T3_SID}"

if [[ -f "$T3_AUDIT" ]]; then
  pass "T3: .pr-abandoned.audit created on first poll"
else
  fail "T3: .pr-abandoned.audit not created on first poll"
fi

if [[ -f "$T3_FLAG" ]]; then
  pass "T3: .pr-abandoned.emitted flag created on first poll"
else
  fail "T3: .pr-abandoned.emitted flag not created on first poll"
fi

# Count lines before second poll
T3_LINES_BEFORE=$(wc -l < "$T3_AUDIT" 2>/dev/null || echo 0)

# Reset rate-limit so second poll fires
rm -f "$T3_LOCK/.pr-watcher.last-poll" 2>/dev/null || true

# Second poll (flag present → should NOT re-emit)
bash "$T3_HARNESS" 2>/dev/null

T3_LINES_AFTER=$(wc -l < "$T3_AUDIT" 2>/dev/null || echo 0)

if [[ "$T3_LINES_AFTER" -eq "$T3_LINES_BEFORE" ]]; then
  pass "T3: no double-emission on second poll (MEDIUM-F6 fix verified)"
else
  fail "T3: audit file grew from $T3_LINES_BEFORE to $T3_LINES_AFTER lines on second poll"
fi
rm -f "$T3_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T4: gh CLI exits non-zero (rate limit) → watcher returns gracefully, story untouched
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: gh API failure — graceful skip, story stays in_progress ==="

T4_DIR="$FIXTURE_DIR/t4-project"
T4_LOCK="$FIXTURE_DIR/t4-locks"
T4_LOG="$FIXTURE_DIR/t4.log"
T4_MOCK_GH="$FIXTURE_DIR/t4-mock-gh"
mkdir -p "$T4_LOCK"
touch "$T4_LOG"

T4_SID="T4-STORY-04"
T4_YAML="- id: $T4_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/77
  delivery_pipeline: 3phase"

setup_git_repo "$T4_DIR" "$T4_YAML"
create_mock_gh "$T4_MOCK_GH"
export MOCK_GH_RESPONSE='rate limit exceeded'
export MOCK_GH_EXIT=1

T4_HARNESS=$(mktemp "$FIXTURE_DIR/t4-XXXXXX.sh")
build_harness "$T4_HARNESS" "$T4_DIR" "$T4_LOCK" "$T4_LOG" "$T4_MOCK_GH"
printf 'watch_pr_merge_status\necho "EXIT:$?"\n' >> "$T4_HARNESS"
chmod +x "$T4_HARNESS"

T4_OUTPUT=$(bash "$T4_HARNESS" 2>/dev/null || true)
T4_EXIT=$(printf '%s\n' "$T4_OUTPUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)
T4_STATUS=$(git -C "$T4_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null \
  | grep "status:" | head -1 | awk '{print $2}' || echo "")

if [[ "$T4_EXIT" == "0" ]]; then
  pass "T4: watcher returned exit 0 on gh API failure"
else
  fail "T4: expected exit 0, got '$T4_EXIT'"
fi

if [[ "$T4_STATUS" == "in_progress" ]]; then
  pass "T4: story stays in_progress after gh failure"
else
  fail "T4: expected in_progress, got '$T4_STATUS'"
fi
rm -f "$T4_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T5: GAAI_PR_WATCHER_DISABLED=1 → watcher is no-op, story untouched
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: GAAI_PR_WATCHER_DISABLED=1 — watcher no-op ==="

T5_DIR="$FIXTURE_DIR/t5-project"
T5_LOCK="$FIXTURE_DIR/t5-locks"
T5_LOG="$FIXTURE_DIR/t5.log"
T5_MOCK_GH="$FIXTURE_DIR/t5-mock-gh"
mkdir -p "$T5_LOCK"
touch "$T5_LOG"

T5_SID="T5-STORY-05"
T5_YAML="- id: $T5_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/88
  delivery_pipeline: 3phase"

setup_git_repo "$T5_DIR" "$T5_YAML"
create_mock_gh "$T5_MOCK_GH"
export MOCK_GH_RESPONSE='{"mergedAt":"2026-05-11T10:00:00Z","state":"MERGED","baseRefName":"staging"}'
export MOCK_GH_EXIT=0

T5_HARNESS=$(mktemp "$FIXTURE_DIR/t5-XXXXXX.sh")
build_harness "$T5_HARNESS" "$T5_DIR" "$T5_LOCK" "$T5_LOG" "$T5_MOCK_GH" "export GAAI_PR_WATCHER_DISABLED=1"
printf 'watch_pr_merge_status\n' >> "$T5_HARNESS"
chmod +x "$T5_HARNESS"
bash "$T5_HARNESS" 2>/dev/null

T5_STATUS=$(git -C "$T5_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null \
  | grep "status:" | head -1 | awk '{print $2}' || echo "")

if [[ "$T5_STATUS" == "in_progress" ]]; then
  pass "T5: story untouched when GAAI_PR_WATCHER_DISABLED=1"
else
  fail "T5: expected in_progress (watcher disabled), got '$T5_STATUS'"
fi

# The disabled log message is emitted by the daemon startup code, not the function itself.
# The function just returns 0 immediately. Verify the function returns 0 cleanly:
T5_HARNESS2=$(mktemp "$FIXTURE_DIR/t5b-XXXXXX.sh")
build_harness "$T5_HARNESS2" "$T5_DIR" "$T5_LOCK" "$T5_LOG" "$T5_MOCK_GH" "export GAAI_PR_WATCHER_DISABLED=1"
printf 'watch_pr_merge_status\necho "EXIT:$?"\n' >> "$T5_HARNESS2"
chmod +x "$T5_HARNESS2"
T5_OUTPUT=$(bash "$T5_HARNESS2" 2>/dev/null || true)
T5_EXIT=$(printf '%s\n' "$T5_OUTPUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)

if [[ "$T5_EXIT" == "0" ]]; then
  pass "T5: watch_pr_merge_status returns 0 when disabled"
else
  fail "T5: expected exit 0 when disabled, got '$T5_EXIT'"
fi
rm -f "$T5_HARNESS" "$T5_HARNESS2"

# ═══════════════════════════════════════════════════════════════════════════════
# T6 (HIGH-F1): malformed pr_url → parse failure logged, story untouched, no crash
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: malformed pr_url — parse failure, no crash, story stays in_progress (HIGH-F1) ==="

T6_DIR="$FIXTURE_DIR/t6-project"
T6_LOCK="$FIXTURE_DIR/t6-locks"
T6_LOG="$FIXTURE_DIR/t6.log"
T6_MOCK_GH="$FIXTURE_DIR/t6-mock-gh"
mkdir -p "$T6_LOCK"
touch "$T6_LOG"

T6_SID="T6-STORY-06"
T6_YAML="- id: $T6_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://example.com/no-pull-pattern
  delivery_pipeline: 3phase"

setup_git_repo "$T6_DIR" "$T6_YAML"
create_mock_gh "$T6_MOCK_GH"
export MOCK_GH_RESPONSE='{"mergedAt":"2026-05-11T10:00:00Z","state":"MERGED","baseRefName":"staging"}'
export MOCK_GH_EXIT=0

T6_HARNESS=$(mktemp "$FIXTURE_DIR/t6-XXXXXX.sh")
build_harness "$T6_HARNESS" "$T6_DIR" "$T6_LOCK" "$T6_LOG" "$T6_MOCK_GH"
printf 'watch_pr_merge_status\necho "EXIT:$?"\n' >> "$T6_HARNESS"
chmod +x "$T6_HARNESS"
T6_OUTPUT=$(bash "$T6_HARNESS" 2>/dev/null || true)
T6_EXIT=$(printf '%s\n' "$T6_OUTPUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)

T6_STATUS=$(git -C "$T6_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null \
  | grep "status:" | head -1 | awk '{print $2}' || echo "")

if [[ "$T6_EXIT" == "0" ]]; then
  pass "T6: watcher returned exit 0 on malformed pr_url (no crash)"
else
  fail "T6: expected exit 0, got '$T6_EXIT'"
fi

if [[ "$T6_STATUS" == "in_progress" ]]; then
  pass "T6: story stays in_progress on malformed pr_url"
else
  fail "T6: expected in_progress, got '$T6_STATUS'"
fi

T6_LOG_CONTENT=$(cat "$T6_LOG" 2>/dev/null || echo "")
if printf '%s\n' "$T6_LOG_CONTENT" | grep -q "does not match canonical"; then
  pass "T6: parse-failure warning logged"
else
  fail "T6: expected 'does not match canonical' in log (got: $(cat "$T6_LOG" 2>/dev/null | tail -5))"
fi
rm -f "$T6_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T7 (HIGH-F3): cleanup-pending.audit written on failure + sweep_cleanup_pending retries
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: cleanup failure → .cleanup-pending.audit + sweep_cleanup_pending retries (HIGH-F3) ==="

T7_DIR="$FIXTURE_DIR/t7-project"
T7_LOCK="$FIXTURE_DIR/t7-locks"
T7_LOG="$FIXTURE_DIR/t7.log"
T7_MOCK_GH="$FIXTURE_DIR/t7-mock-gh"
mkdir -p "$T7_LOCK"
touch "$T7_LOG"

T7_SID="T7-STORY-07"
T7_YAML="- id: $T7_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/707
  delivery_pipeline: 3phase"

setup_git_repo "$T7_DIR" "$T7_YAML"
create_mock_gh "$T7_MOCK_GH"
export MOCK_GH_RESPONSE='{"mergedAt":"2026-05-11T10:00:00Z","state":"MERGED","baseRefName":"staging"}'
export MOCK_GH_EXIT=0

# Create a non-worktree directory at the worktree path.
# git worktree remove --force will fail on a directory that isn't a registered worktree.
# This simulates a worktree that was partially cleaned or is inaccessible.
T7_WT_BASE="$FIXTURE_DIR/t7-worktrees"
T7_WORKTREE_PATH="$T7_WT_BASE/${T7_SID}-workspace"
mkdir -p "$T7_WORKTREE_PATH"

# Set GAAI_WORKTREES_BASE so _reconcile_merged_pr resolves the same path
T7_HARNESS=$(mktemp "$FIXTURE_DIR/t7-XXXXXX.sh")
build_harness "$T7_HARNESS" "$T7_DIR" "$T7_LOCK" "$T7_LOG" "$T7_MOCK_GH" \
  "export GAAI_WORKTREES_BASE=\"$T7_WT_BASE\""
printf 'watch_pr_merge_status\n' >> "$T7_HARNESS"
chmod +x "$T7_HARNESS"
bash "$T7_HARNESS" 2>/dev/null

# Assertions after first run:
T7_BACKLOG=$(git -C "$T7_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null \
  || cat "$T7_DIR/.gaai/project/contexts/backlog/active.backlog.yaml")
T7_STATUS=$(printf '%s\n' "$T7_BACKLOG" | grep "status:" | head -1 | awk '{print $2}' || echo "")
T7_MARKER="$T7_LOCK/.cleanup-pending.audit"

if [[ "$T7_STATUS" == "done" ]]; then
  pass "T7: backlog reconciled to done despite cleanup failure"
else
  fail "T7: expected done after reconcile, got '$T7_STATUS'"
fi

if [[ -f "$T7_MARKER" ]]; then
  pass "T7: .cleanup-pending.audit marker written on cleanup failure"
else
  fail "T7: .cleanup-pending.audit not written"
fi

# Now simulate the blocking condition being resolved: remove the directory
# so sweep_cleanup_pending can clear the marker entry cleanly.
# (When worktree_path doesn't exist, wt_ok stays true → entry cleared.)
rm -rf "$T7_WORKTREE_PATH" 2>/dev/null || true

# Run sweep_cleanup_pending
T7_SWEEP=$(mktemp "$FIXTURE_DIR/t7-sweep-XXXXXX.sh")
build_harness "$T7_SWEEP" "$T7_DIR" "$T7_LOCK" "$T7_LOG" "$T7_MOCK_GH" \
  "export GAAI_WORKTREES_BASE=\"$T7_WT_BASE\""
printf 'sweep_cleanup_pending\n' >> "$T7_SWEEP"
chmod +x "$T7_SWEEP"
bash "$T7_SWEEP" 2>/dev/null

if [[ ! -f "$T7_MARKER" ]]; then
  pass "T7: .cleanup-pending.audit marker cleared after successful sweep"
else
  # Marker may exist but be empty
  T7_MARKER_LINES=$(wc -l < "$T7_MARKER" 2>/dev/null || echo 0)
  if [[ "$T7_MARKER_LINES" -eq 0 ]]; then
    pass "T7: .cleanup-pending.audit marker empty after sweep (cleared)"
  else
    fail "T7: .cleanup-pending.audit still has $T7_MARKER_LINES lines after sweep with no directory"
  fi
fi
rm -f "$T7_HARNESS" "$T7_SWEEP"

# ═══════════════════════════════════════════════════════════════════════════════
# T8 (MEDIUM-F5): gh returns baseRefName != staging → skip reconcile, story in_progress
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: PR targets wrong base branch — skip reconcile, story stays in_progress (MEDIUM-F5) ==="

T8_DIR="$FIXTURE_DIR/t8-project"
T8_LOCK="$FIXTURE_DIR/t8-locks"
T8_LOG="$FIXTURE_DIR/t8.log"
T8_MOCK_GH="$FIXTURE_DIR/t8-mock-gh"
mkdir -p "$T8_LOCK"
touch "$T8_LOG"

T8_SID="T8-STORY-08"
T8_YAML="- id: $T8_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/808
  delivery_pipeline: 3phase"

setup_git_repo "$T8_DIR" "$T8_YAML"
create_mock_gh "$T8_MOCK_GH"
# PR targets feature-branch, not staging
export MOCK_GH_RESPONSE='{"mergedAt":"2026-05-11T10:00:00Z","state":"MERGED","baseRefName":"feature-branch"}'
export MOCK_GH_EXIT=0

T8_HARNESS=$(mktemp "$FIXTURE_DIR/t8-XXXXXX.sh")
build_harness "$T8_HARNESS" "$T8_DIR" "$T8_LOCK" "$T8_LOG" "$T8_MOCK_GH"
printf 'watch_pr_merge_status\n' >> "$T8_HARNESS"
chmod +x "$T8_HARNESS"
bash "$T8_HARNESS" 2>/dev/null

T8_STATUS=$(git -C "$T8_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null \
  | grep "status:" | head -1 | awk '{print $2}' || echo "")

if [[ "$T8_STATUS" == "in_progress" ]]; then
  pass "T8: story stays in_progress when PR targets wrong base branch"
else
  fail "T8: expected in_progress, got '$T8_STATUS'"
fi

T8_LOG_CONTENT=$(cat "$T8_LOG" 2>/dev/null || echo "")
if printf '%s\n' "$T8_LOG_CONTENT" | grep -q "PR targets baseRefName"; then
  pass "T8: skip-reconcile log message present"
else
  fail "T8: expected 'PR targets baseRefName' in log (got: $(cat "$T8_LOG" 2>/dev/null | tail -5))"
fi
rm -f "$T8_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RESULTS: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  exit 0
else
  exit 1
fi
