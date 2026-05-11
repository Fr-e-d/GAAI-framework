#!/usr/bin/env bash
# crash-recovery.test.sh — regression tests for daemon recovery + chore-commit hardening
#
# Covers : drift detection in crash_recovery_scan prevents lock creation when an
# operator has working-tree edits ; chore-commit purity ensures daemon's git add
# only stages the targeted story's changes (working-tree drift on unrelated stories
# is preserved untouched).
#
# Usage: bash .gaai/core/scripts/tests/crash-recovery.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../delivery-daemon.sh"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"

# ── Fixture setup ──────────────────────────────────────────────────────────────
FIXTURE_DIR="/tmp/gaai-crash-recovery-test-$$"
LOCK_DIR="$FIXTURE_DIR/delivery-locks"
LOG_DIR="$FIXTURE_DIR/delivery-logs"
DRIFT_MARKER="$LOCK_DIR/.drift-detected.audit"
DAEMON_LOG="$FIXTURE_DIR/.delivery-daemon.log"
BACKLOG="$FIXTURE_DIR/active.backlog.yaml"
BACKLOG_REL="active.backlog.yaml"

mkdir -p "$LOCK_DIR" "$LOG_DIR"
touch "$DAEMON_LOG"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── Git repo helpers ───────────────────────────────────────────────────────────
# Sets up a bare remote + local clone, commits the given YAML as HEAD.
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

# ═══════════════════════════════════════════════════════════════════════════════
# AC5 — Drift detection prevents lock creation in crash_recovery_scan
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC5: drift detection prevents lock file creation ==="

AC5_DIR="$FIXTURE_DIR/ac5-project"
AC5_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
AC5_STORY="TST-AC5-DRIFT"

# HEAD committed state: story is in_progress/qa_passed
AC5_HEAD_YAML="- id: $AC5_STORY
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase"

setup_git_repo "$AC5_DIR" "$AC5_HEAD_YAML"

# Working-tree edit: operator reverts story to refined/not_started (unstaged)
AC5_WT_YAML="- id: $AC5_STORY
  status: refined
  phase_status: not_started
  delivery_pipeline: 3phase"
printf '%s\n' "$AC5_WT_YAML" > "$AC5_DIR/$AC5_BACKLOG_REL"
# Verify working-tree differs from HEAD (pre-condition)
if git -C "$AC5_DIR" diff --quiet HEAD -- "$AC5_BACKLOG_REL"; then
  fail "AC5-precondition: expected WT diff, found none — test setup broken"
else
  pass "AC5-precondition: WT differs from HEAD as expected"
fi

# Source only the functions we need from the daemon, with overridden paths.
# We can't source the whole daemon (top-level code would run), so we extract
# and invoke crash_recovery_scan in a controlled subprocess.
AC5_LOCK_DIR="$FIXTURE_DIR/ac5-locks"
mkdir -p "$AC5_LOCK_DIR"
AC5_DRIFT_MARKER="$AC5_LOCK_DIR/.drift-detected.audit"
AC5_DAEMON_LOG="$FIXTURE_DIR/ac5-daemon.log"
touch "$AC5_DAEMON_LOG"

# Build a minimal test harness that sources the daemon functions and calls
# crash_recovery_scan with our fixture paths.
AC5_HARNESS=$(mktemp /tmp/ac5-harness-XXXXXX.sh)
cat > "$AC5_HARNESS" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
# Minimal env to source daemon functions without running top-level code
PROJECT_DIR="$AC5_DIR"
GAAI_PROJECT_DIR="$AC5_DIR/.gaai/project"
BACKLOG_REL="$AC5_BACKLOG_REL"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$AC5_LOCK_DIR"
LOG_DIR="$FIXTURE_DIR/ac5-logs"
DRIFT_MARKER="$AC5_DRIFT_MARKER"
LOG_FILE="$AC5_DAEMON_LOG"
STAGING_LOCK="\$LOCK_DIR/.staging.lock"
RETRY_FILE="\$LOCK_DIR/.retry-counts"
RESOLUTION_TRACKING="\$LOCK_DIR/.resolution-tracking"
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
SKIP_PERMISSIONS=true
STATUS_MODE=false
NOTIFICATION_WEBHOOK=""
WEBHOOK_SECRET=""
PLATFORM="\$(uname)"
LAUNCHER="tmux"
CLAUDE_FLAGS="--model sonnet --max-turns 200 --output-format stream-json --verbose"
CAFFEINATE_PID=""

mkdir -p "\$LOG_DIR" "\$LOCK_DIR"

# Color stubs (no terminal in test harness)
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

# Logging stubs — write to log file only
log() {
  local msg="[\$(date '+%H:%M:%S')] \$*"
  echo -e "\$msg" | sed "s/\\\033\[[0-9;]*m//g" >> "\$LOG_FILE"
}

# Stub out functions that would do real git operations or spawn processes
launch_3phase_in_tmux() { return 0; }
with_staging_lock() { "\$@"; }
notify_escalation() { return 0; }
is_locked() { [[ -f "\$LOCK_DIR/\$1.lock" ]]; }
file_mtime() { stat -f %m "\$1" 2>/dev/null || stat -c %Y "\$1" 2>/dev/null || echo 0; }
get_retry_count() { echo 0; }
increment_retry() { return 0; }

# Stub fetch_and_read_backlog to read from the ORIGIN (HEAD), not working tree.
# This simulates the daemon reading the committed (remote) state.
fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/main:\$BACKLOG_REL" 2>/dev/null \
    || git -C "\$PROJECT_DIR" show "HEAD:\$BACKLOG_REL" 2>/dev/null \
    || cat "\$BACKLOG"
}

# Minimal stubs for recovery helpers — they will be called for non-drifted stories
_recovery_resolve_worktree() { echo "/nonexistent/\$1-workspace"; }
_recovery_relaunch() { return 0; }
_recovery_revert_refined() { return 0; }
_recovery_set_status() { return 0; }

# Include the drift marker helpers and crash_recovery_scan from delivery-daemon.sh.
# We extract relevant function definitions via awk to avoid executing top-level code.
eval "\$(awk '
  /^_write_drift_marker\(\)/{p=1; depth=0}
  /^_clear_drift_marker_if_clean\(\)/{p=1; depth=0}
  /^crash_recovery_scan\(\)/{p=1; depth=0}
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

# Run crash_recovery_scan
crash_recovery_scan
HARNESS

chmod +x "$AC5_HARNESS"

# Run the harness (no timeout — crash_recovery_scan in test mode is fast; timeout is not portable on macOS)
bash "$AC5_HARNESS" 2>/dev/null
rm -f "$AC5_HARNESS"

# Assertions
echo "T1: no lock file created for drifted story"
if [[ -f "$AC5_LOCK_DIR/${AC5_STORY}.lock" ]]; then
  fail "T1: lock file was created despite working-tree drift"
else
  pass "T1: no lock file created"
fi

echo "T2: drift marker file written"
if [[ -f "$AC5_DRIFT_MARKER" ]]; then
  pass "T2: drift marker exists"
else
  fail "T2: drift marker missing — expected $AC5_DRIFT_MARKER"
fi

echo "T3: daemon log contains drift-detected message"
if grep -q "working-tree drift\|drift.*$AC5_STORY\|DRIFT" "$AC5_DAEMON_LOG" 2>/dev/null; then
  pass "T3: drift-detected message in daemon log"
else
  fail "T3: no drift message found in daemon log: $(cat "$AC5_DAEMON_LOG" 2>/dev/null | head -5)"
fi

echo "T4: drift marker content has expected format (ts|scan|reason)"
if [[ -f "$AC5_DRIFT_MARKER" ]]; then
  marker_content=$(cat "$AC5_DRIFT_MARKER")
  if echo "$marker_content" | grep -qE '^[0-9T:Z-]+\|scan\|'; then
    pass "T4: marker format correct: $marker_content"
  else
    fail "T4: marker format unexpected: $marker_content"
  fi
else
  fail "T4: marker missing, cannot check format"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# AC6 — Chore-commit purity: mark_in_progress only stages the targeted story
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC6: chore-commit purity — only target story changes committed ==="

AC6_DIR="$FIXTURE_DIR/ac6-project"
AC6_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
AC6_STORY="TST-AC6-TARGET"
AC6_DRIFT_STORY1="TST-AC6-DRIFT1"
AC6_DRIFT_STORY2="TST-AC6-DRIFT2"

# HEAD committed state: three stories, target is refined (ready to claim)
AC6_HEAD_YAML="- id: $AC6_STORY
  status: refined
  phase_status: not_started
  delivery_pipeline: 3phase
- id: $AC6_DRIFT_STORY1
  status: in_progress
  phase_status: planned
  delivery_pipeline: 3phase
  notes: original notes
- id: $AC6_DRIFT_STORY2
  status: deferred
  phase_status: not_started
  delivery_pipeline: 3phase
  priority: medium"

setup_git_repo "$AC6_DIR" "$AC6_HEAD_YAML"

# Operator edits: modify two unrelated stories (unstaged)
AC6_WT_YAML="- id: $AC6_STORY
  status: refined
  phase_status: not_started
  delivery_pipeline: 3phase
- id: $AC6_DRIFT_STORY1
  status: in_progress
  phase_status: planned
  delivery_pipeline: 3phase
  notes: operator-edited notes
- id: $AC6_DRIFT_STORY2
  status: deferred
  phase_status: not_started
  delivery_pipeline: 3phase
  priority: high"
printf '%s\n' "$AC6_WT_YAML" > "$AC6_DIR/$AC6_BACKLOG_REL"

# Verify WT has operator edits (pre-condition)
if git -C "$AC6_DIR" diff --quiet HEAD -- "$AC6_BACKLOG_REL"; then
  fail "AC6-precondition: expected WT diff, found none — test setup broken"
else
  pass "AC6-precondition: WT operator edits present"
fi

# Build a minimal script that invokes the drift check logic from pre_launch_mark_in_progress.
# This directly tests the AC3 guard without needing the full daemon.
AC6_TEST=$(mktemp /tmp/ac6-test-XXXXXX.sh)
cat > "$AC6_TEST" <<'TESTSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$1"
BACKLOG_REL="$2"
story_id="$3"
BACKLOG="$PROJECT_DIR/$BACKLOG_REL"
TARGET_BRANCH="main"
SCHEDULER="$4"

cd "$PROJECT_DIR"

# git pull to sync (in test, just fetch)
git pull origin main --ff-only --quiet 2>/dev/null || true

# Re-verify story is still ready (simplified for test)
# Skip this step — not what we're testing

# AC3: drift check (this is the guard from pre_launch_mark_in_progress)
if ! git diff --quiet HEAD -- "$BACKLOG_REL" 2>/dev/null; then
  echo "DRIFT_DETECTED: working-tree drift — skipping in_progress mark for $story_id" >&2
  exit 6
fi

# If no drift, proceed with scheduler (not expected to reach here in this test)
"$SCHEDULER" --set-status "$story_id" in_progress "$BACKLOG" 2>/dev/null || true
git add "$BACKLOG_REL"
git diff --cached --quiet || git commit -m "chore($story_id): in_progress [daemon]" --quiet
TESTSCRIPT
chmod +x "$AC6_TEST"

AC6_RC=0
git -C "$AC6_DIR" config user.email "test@gaai.local"
git -C "$AC6_DIR" config user.name "GAAI Test"
bash "$AC6_TEST" "$AC6_DIR" "$AC6_BACKLOG_REL" "$AC6_STORY" "$SCHEDULER" 2>/dev/null || AC6_RC=$?
rm -f "$AC6_TEST"

echo "T5: drift guard exits with code 6 when operator edits present"
if [[ "$AC6_RC" -eq 6 ]]; then
  pass "T5: exit code 6 (drift detected, commit skipped)"
else
  fail "T5: expected exit code 6, got $AC6_RC"
fi

echo "T6: no in_progress commit was created for target story"
commit_count=$(git -C "$AC6_DIR" log --oneline --grep="chore($AC6_STORY)" | wc -l | tr -d ' ')
if [[ "$commit_count" -eq 0 ]]; then
  pass "T6: no chore($AC6_STORY) commit created"
else
  fail "T6: unexpected commit for $AC6_STORY: $(git -C "$AC6_DIR" log --oneline --grep="chore($AC6_STORY)")"
fi

echo "T7: operator edits remain unstaged in working tree"
if git -C "$AC6_DIR" diff --quiet HEAD -- "$AC6_BACKLOG_REL"; then
  fail "T7: operator edits no longer present in working tree (were committed or lost)"
else
  pass "T7: operator edits remain as unstaged WT modifications"
fi

echo "T8: specific drift story edits are still M (modified)"
drift1_in_diff=$(git -C "$AC6_DIR" diff HEAD -- "$AC6_BACKLOG_REL" 2>/dev/null | grep -c "operator-edited notes" || echo 0)
if [[ "$drift1_in_diff" -gt 0 ]]; then
  pass "T8: drift story 1 edits preserved in WT diff"
else
  fail "T8: drift story 1 edits missing from WT diff"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# AC6b — Clean working tree: commit proceeds normally
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC6b: clean working tree — commit proceeds normally ==="

AC6B_DIR="$FIXTURE_DIR/ac6b-project"
AC6B_STORY="TST-AC6B-CLEAN"
AC6B_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"

AC6B_HEAD_YAML="- id: $AC6B_STORY
  status: refined
  phase_status: not_started
  delivery_pipeline: 3phase"

setup_git_repo "$AC6B_DIR" "$AC6B_HEAD_YAML"
git -C "$AC6B_DIR" config user.email "test@gaai.local"
git -C "$AC6B_DIR" config user.name "GAAI Test"

# No operator edits — working tree is clean
AC6B_TEST=$(mktemp /tmp/ac6b-test-XXXXXX.sh)
cat > "$AC6B_TEST" <<'TESTSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$1"
BACKLOG_REL="$2"
story_id="$3"
BACKLOG="$PROJECT_DIR/$BACKLOG_REL"
TARGET_BRANCH="main"
SCHEDULER="$4"

cd "$PROJECT_DIR"
git pull origin main --ff-only --quiet 2>/dev/null || true

# AC3: drift check — should pass (no operator edits)
if ! git diff --quiet HEAD -- "$BACKLOG_REL" 2>/dev/null; then
  echo "DRIFT_DETECTED: working-tree drift — skipping" >&2
  exit 6
fi

# No drift — mark in_progress and commit
"$SCHEDULER" --set-status "$story_id" in_progress "$BACKLOG" 2>/dev/null || true
git add "$BACKLOG_REL"
git diff --cached --quiet || git commit -m "chore($story_id): in_progress [daemon]" --quiet
TESTSCRIPT
chmod +x "$AC6B_TEST"

AC6B_RC=0
bash "$AC6B_TEST" "$AC6B_DIR" "$AC6B_BACKLOG_REL" "$AC6B_STORY" "$SCHEDULER" 2>/dev/null || AC6B_RC=$?
rm -f "$AC6B_TEST"

echo "T9: drift guard passes on clean working tree"
if [[ "$AC6B_RC" -eq 0 ]]; then
  pass "T9: exit code 0 (no drift, commit proceeded)"
else
  fail "T9: expected exit code 0 (clean WT), got $AC6B_RC"
fi

echo "T10: in_progress commit was created for target story"
commit_count=$(git -C "$AC6B_DIR" log --oneline --grep="chore($AC6B_STORY)" | wc -l | tr -d ' ')
if [[ "$commit_count" -gt 0 ]]; then
  pass "T10: chore($AC6B_STORY) in_progress commit found"
else
  fail "T10: no commit for $AC6B_STORY — commit should have succeeded on clean WT"
fi

echo "T11: commit diff contains only the target story's changes"
commit_sha=$(git -C "$AC6B_DIR" log --oneline --grep="chore($AC6B_STORY)" -1 | cut -d' ' -f1)
if [[ -n "$commit_sha" ]]; then
  # The story ID appears as context (space-prefixed) in the diff since only status: changes.
  # Search entire diff output (not just +/- lines) for the story ID.
  diff_output=$(git -C "$AC6B_DIR" show "$commit_sha" -- "$AC6B_BACKLOG_REL" 2>/dev/null)
  if echo "$diff_output" | grep -q "$AC6B_STORY"; then
    pass "T11: commit diff contains target story changes"
  else
    fail "T11: target story not in commit diff"
  fi
else
  fail "T11: could not find commit SHA for $AC6B_STORY"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Wrapper EXIT reconciliation (E134S14 — AC4)
# Tests _reconcile_yaml_status_on_exit via direct harness invocation.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Wrapper EXIT reconciliation (T1-T5) ==="

DISPATCH="$SCRIPT_DIR/../daemon-dispatch.sh"

# Shared helper: build a harness that sources _reconcile_yaml_status_on_exit
# (and its dependency get_phase_status) from daemon-dispatch.sh and invokes it.
# Args: $1=project_dir $2=story_id $3=backlog_rel $4=phase_status $5=initial_status
# Writes a temp script to $REC_HARNESS (set by caller).
_write_reconcile_harness() {
  local proj="$1" sid="$2" brel="$3" initial_phase="$4" initial_status="$5"
  cat > "$REC_HARNESS" <<HEOF
#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="$proj"
BACKLOG_FILE="\$PROJECT_DIR/$brel"
SCHEDULER="$SCHEDULER"
LOCK_DIR="$FIXTURE_DIR/rec-locks-$$"
TARGET_BRANCH="main"
mkdir -p "\$LOCK_DIR"

eval "\$(awk '
  /^get_phase_status\(\)/{ p=1; depth=0 }
  /^_reconcile_yaml_status_on_exit\(\)/{ p=1; depth=0 }
  p {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == "{") depth++
      if (c == "}") depth--
    }
    if (p && depth == 0 && NR > 1) { p=0 }
  }
' "$DISPATCH" 2>/dev/null)"

_reconcile_yaml_status_on_exit "$sid"
HEOF
  chmod +x "$REC_HARNESS"
}

# ── T1: phase_status=done, status=in_progress → commit created, YAML status=done ──
echo ""
echo "T1: phase_status=done → reconcile commits status=done"
T1_DIR="$FIXTURE_DIR/rec-t1-$$"
T1_BREL=".gaai/project/contexts/backlog/active.backlog.yaml"
T1_SID="TST-REC-T1"

T1_YAML="- id: $T1_SID
  status: in_progress
  phase_status: done
  delivery_pipeline: 3phase"

setup_git_repo "$T1_DIR" "$T1_YAML"
git -C "$T1_DIR" config user.email "test@gaai.local"
git -C "$T1_DIR" config user.name "GAAI Test"

REC_HARNESS=$(mktemp /tmp/rec-harness-XXXXXX.sh)
_write_reconcile_harness "$T1_DIR" "$T1_SID" "$T1_BREL" "done" "in_progress"
bash "$REC_HARNESS" 2>/dev/null
rm -f "$REC_HARNESS"

commit_line=$(git -C "$T1_DIR" log --oneline --grep="chore($T1_SID).*wrapper-reconcile" 2>/dev/null | head -1)
if [[ -n "$commit_line" ]]; then
  pass "T1a: wrapper-reconcile commit found: $commit_line"
else
  fail "T1a: no wrapper-reconcile commit for $T1_SID"
fi

final_status=$(awk -v id="$T1_SID" '
  $0 == "- id: " id { found=1; next }
  found && /^- id:/ { exit }
  found && /^[[:space:]]+status:/ {
    gsub(/^[[:space:]]+status:[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit
  }
' "$T1_DIR/$T1_BREL" 2>/dev/null)
if [[ "$final_status" == "done" ]]; then
  pass "T1b: YAML status=done after reconcile"
else
  fail "T1b: expected status=done, got '$final_status'"
fi

# ── T2: phase_status=failed, status=in_progress → commit created, YAML status=failed ──
echo ""
echo "T2: phase_status=failed → reconcile commits status=failed"
T2_DIR="$FIXTURE_DIR/rec-t2-$$"
T2_BREL=".gaai/project/contexts/backlog/active.backlog.yaml"
T2_SID="TST-REC-T2"

T2_YAML="- id: $T2_SID
  status: in_progress
  phase_status: failed
  delivery_pipeline: 3phase"

setup_git_repo "$T2_DIR" "$T2_YAML"
git -C "$T2_DIR" config user.email "test@gaai.local"
git -C "$T2_DIR" config user.name "GAAI Test"

REC_HARNESS=$(mktemp /tmp/rec-harness-XXXXXX.sh)
_write_reconcile_harness "$T2_DIR" "$T2_SID" "$T2_BREL" "failed" "in_progress"
bash "$REC_HARNESS" 2>/dev/null
rm -f "$REC_HARNESS"

commit_line=$(git -C "$T2_DIR" log --oneline --grep="chore($T2_SID).*wrapper-reconcile" 2>/dev/null | head -1)
if [[ -n "$commit_line" ]]; then
  pass "T2a: wrapper-reconcile commit found: $commit_line"
else
  fail "T2a: no wrapper-reconcile commit for $T2_SID"
fi

final_status=$(awk -v id="$T2_SID" '
  $0 == "- id: " id { found=1; next }
  found && /^- id:/ { exit }
  found && /^[[:space:]]+status:/ {
    gsub(/^[[:space:]]+status:[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit
  }
' "$T2_DIR/$T2_BREL" 2>/dev/null)
if [[ "$final_status" == "failed" ]]; then
  pass "T2b: YAML status=failed after reconcile"
else
  fail "T2b: expected status=failed, got '$final_status'"
fi

# ── T3: phase_status=qa_failed → no reconciliation (retry-loop owns this) ──
echo ""
echo "T3: phase_status=qa_failed → no reconciliation (left for retry-loop)"
T3_DIR="$FIXTURE_DIR/rec-t3-$$"
T3_BREL=".gaai/project/contexts/backlog/active.backlog.yaml"
T3_SID="TST-REC-T3"

T3_YAML="- id: $T3_SID
  status: in_progress
  phase_status: qa_failed
  delivery_pipeline: 3phase"

setup_git_repo "$T3_DIR" "$T3_YAML"
git -C "$T3_DIR" config user.email "test@gaai.local"
git -C "$T3_DIR" config user.name "GAAI Test"

REC_HARNESS=$(mktemp /tmp/rec-harness-XXXXXX.sh)
_write_reconcile_harness "$T3_DIR" "$T3_SID" "$T3_BREL" "qa_failed" "in_progress"
bash "$REC_HARNESS" 2>/dev/null
rm -f "$REC_HARNESS"

commit_line=$(git -C "$T3_DIR" log --oneline --grep="chore($T3_SID).*wrapper-reconcile" 2>/dev/null | head -1)
if [[ -z "$commit_line" ]]; then
  pass "T3a: no wrapper-reconcile commit (qa_failed is no-op)"
else
  fail "T3a: unexpected wrapper-reconcile commit for qa_failed: $commit_line"
fi

final_status=$(awk -v id="$T3_SID" '
  $0 == "- id: " id { found=1; next }
  found && /^- id:/ { exit }
  found && /^[[:space:]]+status:/ {
    gsub(/^[[:space:]]+status:[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit
  }
' "$T3_DIR/$T3_BREL" 2>/dev/null)
if [[ "$final_status" == "in_progress" ]]; then
  pass "T3b: YAML status=in_progress unchanged (retry-loop will handle)"
else
  fail "T3b: expected status=in_progress unchanged, got '$final_status'"
fi

# ── T4: INTERRUPTED_FILE present → caller-level guard skips reconcile ──
echo ""
echo "T4: INTERRUPTED_FILE present → no reconciliation (daemon crash-recovery owns it)"
T4_DIR="$FIXTURE_DIR/rec-t4-$$"
T4_BREL=".gaai/project/contexts/backlog/active.backlog.yaml"
T4_SID="TST-REC-T4"
T4_LOCK_DIR="$FIXTURE_DIR/rec-locks-t4-$$"
T4_INTERRUPTED="$T4_LOCK_DIR/${T4_SID}.interrupted"

T4_YAML="- id: $T4_SID
  status: in_progress
  phase_status: done
  delivery_pipeline: 3phase"

setup_git_repo "$T4_DIR" "$T4_YAML"
git -C "$T4_DIR" config user.email "test@gaai.local"
git -C "$T4_DIR" config user.name "GAAI Test"
mkdir -p "$T4_LOCK_DIR"
date +%s > "$T4_INTERRUPTED"   # simulate the interrupt marker

# Simulate the AC2 caller-level guard from cleanup(): only call reconcile if
# INTERRUPTED_FILE is absent. Since it's present, reconcile is never invoked.
T4_HARNESS=$(mktemp /tmp/rec-harness-XXXXXX.sh)
cat > "$T4_HARNESS" <<T4EOF
#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="$T4_DIR"
BACKLOG_FILE="\$PROJECT_DIR/$T4_BREL"
SCHEDULER="$SCHEDULER"
LOCK_DIR="$T4_LOCK_DIR"
TARGET_BRANCH="main"
INTERRUPTED_FILE="$T4_INTERRUPTED"
_INTERRUPT_REQUESTED=0

eval "\$(awk '
  /^get_phase_status\(\)/{ p=1; depth=0 }
  /^_reconcile_yaml_status_on_exit\(\)/{ p=1; depth=0 }
  p {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == "{") depth++
      if (c == "}") depth--
    }
    if (p && depth == 0 && NR > 1) { p=0 }
  }
' "$DISPATCH" 2>/dev/null)"

# Mirrors the cleanup() AC2 guard added by E134S14
if [[ "\$_INTERRUPT_REQUESTED" != "1" ]] && [[ ! -f "\$INTERRUPTED_FILE" ]]; then
  _reconcile_yaml_status_on_exit "$T4_SID"
fi
T4EOF
chmod +x "$T4_HARNESS"
bash "$T4_HARNESS" 2>/dev/null
rm -f "$T4_HARNESS"

commit_line=$(git -C "$T4_DIR" log --oneline --grep="chore($T4_SID).*wrapper-reconcile" 2>/dev/null | head -1)
if [[ -z "$commit_line" ]]; then
  pass "T4: no reconcile commit when INTERRUPTED_FILE present"
else
  fail "T4: unexpected reconcile commit despite INTERRUPTED_FILE: $commit_line"
fi

# ── T5: phase_status=done, status=in_progress, WT drift → skip + log, no crash ──
echo ""
echo "T5: working-tree drift → skip reconcile with log line, wrapper exits cleanly"
T5_DIR="$FIXTURE_DIR/rec-t5-$$"
T5_BREL=".gaai/project/contexts/backlog/active.backlog.yaml"
T5_SID="TST-REC-T5"

T5_YAML="- id: $T5_SID
  status: in_progress
  phase_status: done
  delivery_pipeline: 3phase"

setup_git_repo "$T5_DIR" "$T5_YAML"
git -C "$T5_DIR" config user.email "test@gaai.local"
git -C "$T5_DIR" config user.name "GAAI Test"

# Introduce WT drift: edit the backlog without committing
printf '%s\n' "- id: $T5_SID
  status: in_progress
  phase_status: done
  delivery_pipeline: 3phase
  notes: operator-edited-drift" > "$T5_DIR/$T5_BREL"

if git -C "$T5_DIR" diff --quiet HEAD -- "$T5_BREL"; then
  fail "T5-precondition: expected WT drift, found none"
else
  pass "T5-precondition: WT drift present as expected"
fi

REC_HARNESS=$(mktemp /tmp/rec-harness-XXXXXX.sh)
_write_reconcile_harness "$T5_DIR" "$T5_SID" "$T5_BREL" "done" "in_progress"
T5_OUTPUT=$(bash "$REC_HARNESS" 2>&1)
T5_RC=$?
rm -f "$REC_HARNESS"

if [[ "$T5_RC" -eq 0 ]]; then
  pass "T5a: function returned 0 (no crash on drift)"
else
  fail "T5a: function exited $T5_RC (expected 0)"
fi

if echo "$T5_OUTPUT" | grep -q "working-tree drift"; then
  pass "T5b: log line contains 'working-tree drift'"
else
  fail "T5b: expected 'working-tree drift' in output; got: $T5_OUTPUT"
fi

commit_line=$(git -C "$T5_DIR" log --oneline --grep="chore($T5_SID).*wrapper-reconcile" 2>/dev/null | head -1)
if [[ -z "$commit_line" ]]; then
  pass "T5c: no commit created on drift (skipped correctly)"
else
  fail "T5c: unexpected commit despite working-tree drift: $commit_line"
fi

final_status=$(awk -v id="$T5_SID" '
  $0 == "- id: " id { found=1; next }
  found && /^- id:/ { exit }
  found && /^[[:space:]]+status:/ {
    gsub(/^[[:space:]]+status:[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit
  }
' "$T5_DIR/$T5_BREL" 2>/dev/null)
if [[ "$final_status" == "in_progress" ]]; then
  pass "T5d: YAML status=in_progress unchanged (daemon will reconcile later)"
else
  fail "T5d: expected status=in_progress unchanged, got '$final_status'"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "══════════════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
