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
# Emits a schema-valid backlog document for a fixture: the real file nests its
# story sequence under a top-level "items:" key, which every yq-backed helper
# (backlog_in_progress_ids, backlog_status, ...) queries as ".items[]".
# Idempotent — content that already carries the header is returned unchanged.
backlog_fixture() {
  local content="$1"
  if [[ "$content" == items:* ]]; then
    printf '%s' "$content"
  else
    printf 'items:\n%s' "$content"
  fi
}

setup_git_repo() {
  local project_dir="$1" content="$2"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  # -b main is explicit on purpose: these fixtures push to and read from
  # origin/main, but a bare init otherwise takes the branch name from the
  # host's init.defaultBranch. Developers who set it to main saw this pass
  # while CI runners, which keep git's built-in default, produced a repo with
  # no main ref at all — every fixture push then failed with "couldn't find
  # remote ref main" and the code under test never ran.
  git init --bare -b main "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  mkdir -p "$project_dir/.gaai/project/contexts/backlog"
  # Most callers pass a bare story sequence. The real backlog nests it under a
  # top-level "items:" key, and recovery now selects stories through
  # backlog_in_progress_ids, whose yq query is ".items[] | select(...)". A bare
  # sequence returns nothing from that query, so recovery saw an empty backlog
  # and reported "No in_progress stories to evaluate" instead of exercising the
  # drift path under test. AC4 already supplies its own "items:" header, so wrap
  # only when it is absent.
  printf '%s\n' "$(backlog_fixture "$content")" > "$project_dir/.gaai/project/contexts/backlog/active.backlog.yaml"
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
printf '%s\n' "$(backlog_fixture "$AC5_WT_YAML")" > "$AC5_DIR/$AC5_BACKLOG_REL"
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

# crash_recovery_scan selects its candidate stories through
# backlog_in_progress_ids, which lives in lib/backlog-yaml.sh since the yq
# migration. Without this source the call resolved to nothing, its trailing
# "|| true" swallowed the error, and the scan logged "No in_progress stories to
# evaluate" instead of reaching the drift-marker path this AC exercises.
# NOTE: this heredoc is unquoted — keep comments here backtick-free.
# shellcheck source=../lib/backlog-yaml.sh
source "$SCRIPT_DIR/../lib/backlog-yaml.sh"
# The lib declares "set -euo pipefail" and source is not scope-limited; the
# extracted daemon functions rely on non-zero commands staying non-fatal.
set +e

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
printf '%s\n' "$(backlog_fixture "$AC6_WT_YAML")" > "$AC6_DIR/$AC6_BACKLOG_REL"

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
# AC4 — Concurrent chore-commit serialization (E134S16 — T12–T17)
# Tests chore_commit_field / chore_commit_multi_field: single-field write,
# idempotency, cross-story drift detection, multi-field atomicity,
# concurrent caller serialization, and Option A fallback warning.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC4: chore-commit serialization (T12-T17) ==="

CHORE_LIB="$SCRIPT_DIR/../lib/chore-commit.sh"
AC4_DIR="$FIXTURE_DIR/ac4-project"
AC4_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
AC4_LOCK_DIR="$FIXTURE_DIR/ac4-locks"
AC4_STORY_A="TST-CC-A"
AC4_STORY_B="TST-CC-B"
mkdir -p "$AC4_LOCK_DIR"

AC4_HEAD_YAML="items:
- id: $AC4_STORY_A
  status: refined
  phase_status: not_started
- id: $AC4_STORY_B
  status: refined
  phase_status: not_started"

setup_git_repo "$AC4_DIR" "$AC4_HEAD_YAML"
git -C "$AC4_DIR" config user.email "test@gaai.local"
git -C "$AC4_DIR" config user.name "GAAI Test"

# ── T12: single-field write succeeds on clean working tree ────────────────────
echo "T12: chore_commit_field single-field write on clean WT"
T12_HARNESS=$(mktemp /tmp/ac4-t12-XXXXXX.sh)
cat > "$T12_HARNESS" <<SCRIPT
#!/usr/bin/env bash
BACKLOG_FILE="$AC4_DIR/$AC4_BACKLOG_REL"
BACKLOG_REL="$AC4_BACKLOG_REL"
LOCK_DIR="$AC4_LOCK_DIR"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
cd "$AC4_DIR"
source "$CHORE_LIB"
chore_commit_field "$AC4_STORY_A" status in_progress "chore($AC4_STORY_A): in_progress [test]"
SCRIPT
chmod +x "$T12_HARNESS"
T12_RC=0
bash "$T12_HARNESS" 2>/dev/null || T12_RC=$?
rm -f "$T12_HARNESS"

if [[ "$T12_RC" -eq 0 ]]; then
  pass "T12: chore_commit_field exited 0 on clean WT"
else
  fail "T12: chore_commit_field exited $T12_RC (expected 0)"
fi
T12_STATUS=$(git -C "$AC4_DIR" show HEAD:"$AC4_BACKLOG_REL" 2>/dev/null \
  | grep -A 4 "id: $AC4_STORY_A" | grep "status:" | head -1 | sed 's/.*status: *//' | tr -d '"' || echo "")
if [[ "$T12_STATUS" == "in_progress" ]]; then
  pass "T12b: status committed as in_progress"
else
  fail "T12b: status in HEAD is '$T12_STATUS' (expected in_progress)"
fi

# ── T13: idempotency — same value → no new commit ─────────────────────────────
echo "T13: chore_commit_field idempotency (same value)"
T13_COUNT_BEFORE=$(git -C "$AC4_DIR" log --oneline | wc -l | tr -d ' ')
T13_HARNESS=$(mktemp /tmp/ac4-t13-XXXXXX.sh)
cat > "$T13_HARNESS" <<SCRIPT
#!/usr/bin/env bash
BACKLOG_FILE="$AC4_DIR/$AC4_BACKLOG_REL"
BACKLOG_REL="$AC4_BACKLOG_REL"
LOCK_DIR="$AC4_LOCK_DIR"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
cd "$AC4_DIR"
source "$CHORE_LIB"
chore_commit_field "$AC4_STORY_A" status in_progress "chore($AC4_STORY_A): in_progress [test-dup]"
SCRIPT
chmod +x "$T13_HARNESS"
T13_RC=0
bash "$T13_HARNESS" 2>/dev/null || T13_RC=$?
rm -f "$T13_HARNESS"
T13_COUNT_AFTER=$(git -C "$AC4_DIR" log --oneline | wc -l | tr -d ' ')

if [[ "$T13_RC" -eq 0 ]]; then
  pass "T13: idempotent call exited 0"
else
  fail "T13: idempotent call exited $T13_RC (expected 0)"
fi
if [[ "$T13_COUNT_BEFORE" -eq "$T13_COUNT_AFTER" ]]; then
  pass "T13b: no new commit on idempotent call"
else
  fail "T13b: unexpected new commit ($T13_COUNT_BEFORE → $T13_COUNT_AFTER)"
fi

# ── T14: cross-story drift → exit 6 ──────────────────────────────────────────
echo "T14: chore_commit_field exits 6 on cross-story drift (dirty WT)"
# Introduce unstaged edit to simulate operator editing an unrelated story
python3 -c "
with open('$AC4_DIR/$AC4_BACKLOG_REL') as f: content = f.read()
content = content.replace('  phase_status: not_started', '  phase_status: not_started\n  notes: operator-edited', 1)
with open('$AC4_DIR/$AC4_BACKLOG_REL', 'w') as f: f.write(content)
" 2>/dev/null || true

if git -C "$AC4_DIR" diff --quiet HEAD -- "$AC4_BACKLOG_REL" 2>/dev/null; then
  fail "T14-precondition: expected dirty WT, found clean"
else
  T14_HARNESS=$(mktemp /tmp/ac4-t14-XXXXXX.sh)
  cat > "$T14_HARNESS" <<SCRIPT
#!/usr/bin/env bash
BACKLOG_FILE="$AC4_DIR/$AC4_BACKLOG_REL"
BACKLOG_REL="$AC4_BACKLOG_REL"
LOCK_DIR="$AC4_LOCK_DIR"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
cd "$AC4_DIR"
source "$CHORE_LIB"
chore_commit_field "$AC4_STORY_B" status in_progress "chore($AC4_STORY_B): in_progress [test]"
SCRIPT
  chmod +x "$T14_HARNESS"
  T14_RC=0
  bash "$T14_HARNESS" 2>/dev/null || T14_RC=$?
  rm -f "$T14_HARNESS"

  # T14 asserted rc=6 ("refuse the write when an unrelated story is dirty").
  # chore_commit_field no longer takes that path: _CHORE_HELPER_AVAILABLE is
  # pinned to 0 (the yq -i route is disabled because it reformats the whole
  # file and defeats the drift checks), so every call routes to
  # _chore_option_a_fallback. That function deliberately replaced refuse-on-drift
  # with a pre-commit drift sweep — its own comment records that refusing on ANY
  # backlog drift "deadlocked every NEW" story once concurrent wrappers started
  # accumulating uncommitted progress writes.
  #
  # So the contract under test moved from "refuse" to "absorb safely". Assert the
  # property that actually protects the operator: the unrelated edit is committed
  # rather than silently discarded, and the target story's own write still lands.
  if [[ "$T14_RC" -eq 0 ]]; then
    pass "T14: cross-story drift absorbed without deadlock (rc=0)"
  else
    fail "T14: expected rc=0 (drift absorbed), got $T14_RC"
  fi
  # The target story's own write must land despite the unrelated dirty edit.
  T14_STATUS=$(git -C "$AC4_DIR" show HEAD:"$AC4_BACKLOG_REL" 2>/dev/null \
    | grep -A 4 "id: $AC4_STORY_B" | grep "status:" | head -1 | sed 's/.*status: *//' | tr -d '"' || echo "")
  if [[ "$T14_STATUS" == "in_progress" ]]; then
    pass "T14b: story B write landed in HEAD despite unrelated drift"
  else
    fail "T14b: story B status in HEAD is '$T14_STATUS' (expected in_progress)"
  fi
  # The operator's unrelated edit must be committed, never silently dropped —
  # this is the data-safety property that replaced the old refuse-on-drift.
  if git -C "$AC4_DIR" show HEAD:"$AC4_BACKLOG_REL" 2>/dev/null | grep -q "notes: operator-edited"; then
    pass "T14c: unrelated operator edit preserved in HEAD (absorbed, not discarded)"
  else
    fail "T14c: unrelated operator edit lost — drift sweep discarded it"
  fi
fi
# Reset WT before T15
git -C "$AC4_DIR" checkout HEAD -- "$AC4_BACKLOG_REL" 2>/dev/null || true

# ── T15: chore_commit_multi_field atomic multi-field write ────────────────────
echo "T15: chore_commit_multi_field writes multiple fields in one commit"
T15_HARNESS=$(mktemp /tmp/ac4-t15-XXXXXX.sh)
cat > "$T15_HARNESS" <<SCRIPT
#!/usr/bin/env bash
BACKLOG_FILE="$AC4_DIR/$AC4_BACKLOG_REL"
BACKLOG_REL="$AC4_BACKLOG_REL"
LOCK_DIR="$AC4_LOCK_DIR"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
cd "$AC4_DIR"
source "$CHORE_LIB"
chore_commit_multi_field "$AC4_STORY_B" status in_progress phase_status planning \
  "chore($AC4_STORY_B): in_progress [test]"
SCRIPT
chmod +x "$T15_HARNESS"
T15_RC=0
bash "$T15_HARNESS" 2>/dev/null || T15_RC=$?
rm -f "$T15_HARNESS"

if [[ "$T15_RC" -eq 0 ]]; then
  pass "T15: chore_commit_multi_field exited 0"
else
  fail "T15: chore_commit_multi_field exited $T15_RC (expected 0)"
fi
T15_SNAP=$(git -C "$AC4_DIR" show HEAD:"$AC4_BACKLOG_REL" 2>/dev/null \
  | grep -A 6 "id: $AC4_STORY_B")
T15_STATUS=$(echo "$T15_SNAP" | grep "status:" | head -1 | sed 's/.*status: *//' | tr -d '"' || echo "")
T15_PHASE=$(echo "$T15_SNAP" | grep "phase_status:" | head -1 | sed 's/.*phase_status: *//' | tr -d '"' || echo "")
if [[ "$T15_STATUS" == "in_progress" ]]; then
  pass "T15b: status field committed as in_progress"
else
  fail "T15b: status in HEAD is '$T15_STATUS' (expected in_progress)"
fi
if [[ "$T15_PHASE" == "planning" ]]; then
  pass "T15c: phase_status field committed as planning"
else
  fail "T15c: phase_status in HEAD is '$T15_PHASE' (expected planning)"
fi

# ── T16: concurrent callers on distinct stories both succeed ──────────────────
echo "T16: two concurrent chore_commit_field calls on distinct stories both succeed"
AC4B_DIR="$FIXTURE_DIR/ac4b-project"
AC4B_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
AC4B_LOCK_DIR="$FIXTURE_DIR/ac4b-locks"
AC4B_STORY_A="TST-CC-C"
AC4B_STORY_B="TST-CC-D"
mkdir -p "$AC4B_LOCK_DIR"

AC4B_HEAD_YAML="items:
- id: $AC4B_STORY_A
  status: refined
  phase_status: not_started
- id: $AC4B_STORY_B
  status: refined
  phase_status: not_started"
setup_git_repo "$AC4B_DIR" "$AC4B_HEAD_YAML"
git -C "$AC4B_DIR" config user.email "test@gaai.local"
git -C "$AC4B_DIR" config user.name "GAAI Test"

T16_HARNESS_A=$(mktemp /tmp/ac4-t16a-XXXXXX.sh)
T16_HARNESS_B=$(mktemp /tmp/ac4-t16b-XXXXXX.sh)
for _hf in "$T16_HARNESS_A" "$T16_HARNESS_B"; do
  _sid="$AC4B_STORY_A"; [[ "$_hf" == "$T16_HARNESS_B" ]] && _sid="$AC4B_STORY_B"
  cat > "$_hf" <<SCRIPT
#!/usr/bin/env bash
BACKLOG_FILE="$AC4B_DIR/$AC4B_BACKLOG_REL"
BACKLOG_REL="$AC4B_BACKLOG_REL"
LOCK_DIR="$AC4B_LOCK_DIR"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
cd "$AC4B_DIR"
source "$CHORE_LIB"
chore_commit_field "$_sid" status in_progress "chore($_sid): in_progress [test]"
SCRIPT
  chmod +x "$_hf"
done

T16_RC_A=0; T16_RC_B=0
if command -v flock &>/dev/null && command -v yq &>/dev/null \
    && yq --version 2>/dev/null | grep -q 'v4\.'; then
  # Option B' available — true concurrent execution, flock serializes safely
  bash "$T16_HARNESS_A" 2>/dev/null & T16_PID_A=$!
  bash "$T16_HARNESS_B" 2>/dev/null & T16_PID_B=$!
  wait "$T16_PID_A" || T16_RC_A=$?
  wait "$T16_PID_B" || T16_RC_B=$?
else
  # Option A fallback — sequential (no flock serialization available)
  bash "$T16_HARNESS_A" 2>/dev/null || T16_RC_A=$?
  bash "$T16_HARNESS_B" 2>/dev/null || T16_RC_B=$?
fi
rm -f "$T16_HARNESS_A" "$T16_HARNESS_B"

if [[ "$T16_RC_A" -eq 0 ]]; then
  pass "T16: caller A ($AC4B_STORY_A) exited 0"
else
  fail "T16: caller A exited $T16_RC_A (expected 0)"
fi
if [[ "$T16_RC_B" -eq 0 ]]; then
  pass "T16b: caller B ($AC4B_STORY_B) exited 0"
else
  fail "T16b: caller B exited $T16_RC_B (expected 0)"
fi
T16_SA=$(git -C "$AC4B_DIR" show HEAD:"$AC4B_BACKLOG_REL" 2>/dev/null \
  | grep -A 3 "id: $AC4B_STORY_A" | grep "status:" | head -1 | sed 's/.*status: *//' | tr -d '"' || echo "")
T16_SB=$(git -C "$AC4B_DIR" show HEAD:"$AC4B_BACKLOG_REL" 2>/dev/null \
  | grep -A 3 "id: $AC4B_STORY_B" | grep "status:" | head -1 | sed 's/.*status: *//' | tr -d '"' || echo "")
if [[ "$T16_SA" == "in_progress" ]]; then
  pass "T16c: story $AC4B_STORY_A committed as in_progress"
else
  fail "T16c: story $AC4B_STORY_A status in HEAD is '$T16_SA' (expected in_progress)"
fi
if [[ "$T16_SB" == "in_progress" ]]; then
  pass "T16d: story $AC4B_STORY_B committed as in_progress"
else
  fail "T16d: story $AC4B_STORY_B status in HEAD is '$T16_SB' (expected in_progress)"
fi

# ── T17: Option A fallback warning flag written ───────────────────────────────
echo "T17: Option A fallback writes warning flag when flock/yq unavailable"
T17_LOCK_DIR="$FIXTURE_DIR/ac4-t17-locks"
mkdir -p "$T17_LOCK_DIR"
T17_HARNESS=$(mktemp /tmp/ac4-t17-XXXXXX.sh)
cat > "$T17_HARNESS" <<SCRIPT
#!/usr/bin/env bash
BACKLOG_FILE="$AC4_DIR/$AC4_BACKLOG_REL"
BACKLOG_REL="$AC4_BACKLOG_REL"
LOCK_DIR="$T17_LOCK_DIR"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
cd "$AC4_DIR"
source "$CHORE_LIB"
# Force Option A path to test the warning flag regardless of flock/yq presence
_CHORE_HELPER_AVAILABLE=0
chore_commit_field "$AC4_STORY_A" status done "chore($AC4_STORY_A): done [test-fallback]"
SCRIPT
chmod +x "$T17_HARNESS"
T17_RC=0
bash "$T17_HARNESS" 2>/dev/null || T17_RC=$?
rm -f "$T17_HARNESS"

if [[ "$T17_RC" -eq 0 ]]; then
  pass "T17: Option A fallback exited 0"
else
  fail "T17: Option A fallback exited $T17_RC (expected 0)"
fi
if [[ -f "$T17_LOCK_DIR/.chore-helper-missing.warning" ]]; then
  pass "T17b: warning flag written at .chore-helper-missing.warning"
else
  fail "T17b: warning flag not found at $T17_LOCK_DIR/.chore-helper-missing.warning"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# E156S06 — Periodic orphan-lock recovery scan during polling
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== E156S06: periodic orphan-lock recovery scan ==="

PS_DIR="$FIXTURE_DIR/periodic-scan-project"
PS_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
PS_STORY="TST-PS-ORPHAN"
PS_LOCK_DIR="$FIXTURE_DIR/periodic-scan-locks"
PS_LOG_DIR="$FIXTURE_DIR/periodic-scan-logs"
PS_DAEMON_LOG="$FIXTURE_DIR/periodic-scan-daemon.log"
PS_SENTINEL="$FIXTURE_DIR/periodic-scan-sentinel"

mkdir -p "$PS_LOCK_DIR" "$PS_LOG_DIR"
touch "$PS_DAEMON_LOG"

PS_HEAD_YAML="items:
- id: $PS_STORY
  status: in_progress
  phase_status: not_started
  delivery_pipeline: 3phase"

setup_git_repo "$PS_DIR" "$PS_HEAD_YAML"

# Create a dead-PID lock file (PID 99999 does not exist on any real system)
echo "99999" > "$PS_LOCK_DIR/${PS_STORY}.lock"

PS_HARNESS=$(mktemp /tmp/periodic-scan-harness-XXXXXX.sh)
cat > "$PS_HARNESS" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail

PROJECT_DIR="$PS_DIR"
GAAI_PROJECT_DIR="$PS_DIR/.gaai/project"
BACKLOG_REL="$PS_BACKLOG_REL"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$PS_LOCK_DIR"
LOG_DIR="$PS_LOG_DIR"
DRIFT_MARKER="\$LOCK_DIR/.drift-detected.audit"
LOG_FILE="$PS_DAEMON_LOG"
STAGING_LOCK="\$LOCK_DIR/.staging.lock"
RETRY_FILE="\$LOCK_DIR/.retry-counts"
RESOLUTION_TRACKING="\$LOCK_DIR/.resolution-tracking"
SCHEDULER="$SCHEDULER"
TARGET_BRANCH="main"
DRY_RUN=false
STALENESS_THRESHOLD=14400
POLL_INTERVAL=1
RECOVERY_SCAN_INTERVAL=5
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

RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

log() {
  local msg="[\$(date '+%H:%M:%S')] \$*"
  echo -e "\$msg" | sed "s/\\\033\[[0-9;]*m//g" >> "\$LOG_FILE"
}

launch_3phase_in_tmux() { return 0; }
with_staging_lock() { "\$@"; }
notify_escalation() { return 0; }

# is_locked checks file existence AND PID liveness (matching real daemon behavior)
is_locked() {
  local lock_file="\$LOCK_DIR/\$1.lock"
  [[ -f "\$lock_file" ]] || return 1
  local pid
  pid=\$(cat "\$lock_file" 2>/dev/null | tr -d '[:space:]')
  [[ -n "\$pid" ]] && kill -0 "\$pid" 2>/dev/null
}

file_mtime() { stat -f %m "\$1" 2>/dev/null || stat -c %Y "\$1" 2>/dev/null || echo 0; }
get_retry_count() { echo 0; }
increment_retry() { return 0; }

fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/main:\$BACKLOG_REL" 2>/dev/null \
    || git -C "\$PROJECT_DIR" show "HEAD:\$BACKLOG_REL" 2>/dev/null \
    || cat "\$BACKLOG"
}

_recovery_resolve_worktree() { echo "/nonexistent/\$1-workspace"; }
_recovery_relaunch() { return 0; }
_recovery_set_status() { return 0; }
_recovery_revert_refined() { echo "called" > "$PS_SENTINEL"; return 0; }

# Source backlog-yaml helpers
source "$SCRIPT_DIR/../lib/backlog-yaml.sh" 2>/dev/null || true

# Extract drift helpers and crash_recovery_scan from daemon
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

# Simulate clean_stale_locks: remove dead-PID locks (matching main-loop behavior)
for lock in "\$LOCK_DIR"/*.lock; do
  [[ -f "\$lock" ]] || continue
  _pid=\$(cat "\$lock" 2>/dev/null | tr -d '[:space:]')
  if [[ -n "\$_pid" ]] && ! kill -0 "\$_pid" 2>/dev/null; then
    rm -f "\$lock"
  fi
done

# Simulate periodic scan invocation (matching the new main-loop block)
_now_ts=\$(date +%s)
log "[RECOVERY] periodic-scan triggered (interval=\${RECOVERY_SCAN_INTERVAL}s)"
crash_recovery_scan
HARNESS

chmod +x "$PS_HARNESS"
bash "$PS_HARNESS" 2>/dev/null
rm -f "$PS_HARNESS"

# T18: Dead-PID lock file was removed by simulated clean_stale_locks
if [[ ! -f "$PS_LOCK_DIR/${PS_STORY}.lock" ]]; then
  pass "T18: dead-PID lock file removed by clean_stale_locks"
else
  fail "T18: dead-PID lock file still present after clean_stale_locks"
fi

# T19: periodic-scan triggered marker in daemon log
if grep -q '\[RECOVERY\] periodic-scan triggered' "$PS_DAEMON_LOG" 2>/dev/null; then
  pass "T19: [RECOVERY] periodic-scan triggered marker present in log"
else
  fail "T19: periodic-scan triggered marker NOT found in log"
fi

# T20: Scan done line present in daemon log
if grep -q '\[RECOVERY\] Scan done' "$PS_DAEMON_LOG" 2>/dev/null; then
  pass "T20: [RECOVERY] Scan done line present in log"
else
  fail "T20: Scan done line NOT found in log"
fi

# T21: reverted >= 1 in scan-done line (not_started path triggers revert)
if grep 'Scan done' "$PS_DAEMON_LOG" 2>/dev/null | grep -q 'reverted=[^0]'; then
  pass "T21: reverted >= 1 in scan-done summary"
else
  fail "T21: reverted=0 or not found in scan-done summary"
fi

# T22: _recovery_revert_refined was called (sentinel file) — no daemon restart needed
if [[ -f "$PS_SENTINEL" ]]; then
  pass "T22: _recovery_revert_refined called (recovery without daemon restart)"
else
  fail "T22: _recovery_revert_refined NOT called (sentinel file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Crash-drift self-heal regression
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== crash-drift self-heal regression ==="

CD_DIR="$FIXTURE_DIR/crash-drift-project"
CD_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
CD_STORY="TST-CRASH-DRIFT"
CD_LOCK_DIR="$FIXTURE_DIR/crash-drift-locks"
CD_LOG_DIR="$FIXTURE_DIR/crash-drift-logs"
CD_DAEMON_LOG="$FIXTURE_DIR/crash-drift-daemon.log"
CD_AUDIT="$CD_LOCK_DIR/.crash-drift-reconcile.audit"
CD_DRIFT_MARKER="$CD_LOCK_DIR/.drift-detected.audit"

mkdir -p "$CD_LOCK_DIR" "$CD_LOG_DIR"
touch "$CD_DAEMON_LOG"

# HEAD committed state: story is in_progress with phase_status not_started
CD_HEAD_YAML="items:
- id: $CD_STORY
  status: in_progress
  phase_status: not_started
  delivery_pipeline: 3phase"

setup_git_repo "$CD_DIR" "$CD_HEAD_YAML"

# Working-tree edit: daemon wrote phase_status before being killed (crash-drift)
CD_WT_YAML="items:
- id: $CD_STORY
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase"
printf '%s\n' "$(backlog_fixture "$CD_WT_YAML")" > "$CD_DIR/$CD_BACKLOG_REL"

# Verify WT differs from HEAD (pre-condition)
if git -C "$CD_DIR" diff --quiet HEAD -- "$CD_BACKLOG_REL"; then
  fail "CD-precondition: expected WT diff, found none — test setup broken"
else
  pass "CD-precondition: WT phase_status drift present (not_started → implemented)"
fi

# Place the agent-hang marker (crash-drift signature requirement)
touch "$CD_LOCK_DIR/${CD_STORY}.agent-hang.marker"

# No lock file — simulates dead wrapper (crash_recovery_scan should see ! is_locked)

CD_HARNESS=$(mktemp /tmp/crash-drift-harness-XXXXXX.sh)
cat > "$CD_HARNESS" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail

PROJECT_DIR="$CD_DIR"
GAAI_PROJECT_DIR="$CD_DIR/.gaai/project"
BACKLOG_REL="$CD_BACKLOG_REL"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$CD_LOCK_DIR"
LOG_DIR="$CD_LOG_DIR"
DRIFT_MARKER="$CD_DRIFT_MARKER"
CRASH_DRIFT_RECONCILE_AUDIT="$CD_AUDIT"
REBASE_CONFLICT_MARKER="$CD_LOCK_DIR/.rebase-conflict.audit"
LOG_FILE="$CD_DAEMON_LOG"
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

RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

log() {
  local msg="[\$(date '+%H:%M:%S')] \$*"
  echo -e "\$msg" | sed "s/\\\033\[[0-9;]*m//g" >> "\$LOG_FILE"
}

# with_staging_lock executes its argument directly (no flock in tests)
with_staging_lock() { "\$@"; }
notify_escalation() { return 0; }
notify_escalation_inline() { return 0; }
launch_3phase_in_tmux() { return 0; }
classify_stuck_story() { return 2; }

# is_locked checks file existence (matching real daemon)
is_locked() { [[ -f "\$LOCK_DIR/\$1.lock" ]]; }

file_mtime() { stat -f %m "\$1" 2>/dev/null || stat -c %Y "\$1" 2>/dev/null || echo 0; }
get_retry_count() { echo 0; }
increment_retry() { return 0; }

# fetch_and_read_backlog reads the committed (HEAD) state from origin
fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/main:\$BACKLOG_REL" 2>/dev/null \
    || git -C "\$PROJECT_DIR" show "HEAD:\$BACKLOG_REL" 2>/dev/null \
    || cat "\$BACKLOG"
}

_recovery_resolve_worktree() { echo "/nonexistent/\$1-workspace"; }
_recovery_relaunch() { return 0; }
_recovery_set_status() { return 0; }
_recovery_revert_refined() { return 0; }

# Source backlog-yaml helpers (backlog_status, backlog_phase_status, backlog_in_progress_ids)
source "$SCRIPT_DIR/../lib/backlog-yaml.sh" 2>/dev/null || true

# Extract drift helpers, _recovery_reconcile_crash_drift, and crash_recovery_scan from daemon
eval "\$(awk '
  /^_write_drift_marker\(\)/{p=1; depth=0}
  /^_clear_drift_marker_if_clean\(\)/{p=1; depth=0}
  /^_recovery_reconcile_crash_drift\(\)/{p=1; depth=0}
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

crash_recovery_scan
HARNESS

chmod +x "$CD_HARNESS"
bash "$CD_HARNESS" 2>/dev/null
rm -f "$CD_HARNESS"

# T23: crash-drift signature detected log line present
if grep -q 'RECOVERY-CRASH-DRIFT.*crash-drift signature detected' "$CD_DAEMON_LOG" 2>/dev/null; then
  pass "T23: [RECOVERY-CRASH-DRIFT] crash-drift signature detected message in log"
else
  fail "T23: crash-drift signature detected message NOT found in log ($(head -5 "$CD_DAEMON_LOG" 2>/dev/null | tr '\n' '|'))"
fi

# T24: git commit with crash-drift-reconcile in subject, HEAD phase_status=implemented
T24_LOG=$(git -C "$CD_DIR" log --oneline 2>/dev/null | head -3)
if echo "$T24_LOG" | grep -q 'crash-drift-reconcile'; then
  pass "T24: crash-drift-reconcile commit found in git log"
else
  fail "T24: crash-drift-reconcile commit NOT found — git log: $T24_LOG"
fi
T24_HEAD_PS=$(git -C "$CD_DIR" show "HEAD:$CD_BACKLOG_REL" 2>/dev/null \
  | grep 'phase_status:' | head -1 | sed 's/.*phase_status: *//' | tr -d '"' || echo "")
if [[ "$T24_HEAD_PS" == "implemented" ]]; then
  pass "T24b: HEAD phase_status=implemented after reconcile commit"
else
  fail "T24b: HEAD phase_status='$T24_HEAD_PS' (expected implemented)"
fi

# T25: audit record written with correct fields
if [[ -f "$CD_AUDIT" ]]; then
  pass "T25: crash-drift-reconcile.audit file exists"
  if grep -q '"event":"crash_drift_reconciled"' "$CD_AUDIT" 2>/dev/null; then
    pass "T25b: audit contains event=crash_drift_reconciled"
  else
    fail "T25b: audit missing event field — content: $(cat "$CD_AUDIT" 2>/dev/null | head -1)"
  fi
  if grep -q "\"story_id\":\"$CD_STORY\"" "$CD_AUDIT" 2>/dev/null; then
    pass "T25c: audit contains correct story_id"
  else
    fail "T25c: audit missing story_id=$CD_STORY — content: $(cat "$CD_AUDIT" 2>/dev/null | head -1)"
  fi
  if grep -q '"outcome":"committed"' "$CD_AUDIT" 2>/dev/null; then
    pass "T25d: audit outcome=committed"
  else
    fail "T25d: audit outcome not committed — content: $(cat "$CD_AUDIT" 2>/dev/null | head -1)"
  fi
else
  fail "T25: crash-drift-reconcile.audit file missing — expected $CD_AUDIT"
fi

# T26: daemon does NOT enter staleness loop (no skip message, scan resumes)
if grep -q "working-tree drift.*skipping relaunch this scan" "$CD_DAEMON_LOG" 2>/dev/null; then
  fail "T26: daemon entered skip/staleness loop (found 'skipping relaunch this scan' for crash-drift story)"
else
  pass "T26: daemon did NOT enter staleness loop (no 'skipping relaunch this scan' for crash-drift story)"
fi
if grep -q 'Scan done.*resumed=1' "$CD_DAEMON_LOG" 2>/dev/null; then
  pass "T26b: Scan done shows resumed=1 (crash-drift story processed via relaunch path)"
else
  fail "T26b: Scan done resumed=1 not found — log tail: $(tail -3 "$CD_DAEMON_LOG" 2>/dev/null | tr '\n' '|')"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T-DRIFT-SELF-RESOLVE (AC4a)
# Local drift on story-A block + origin ahead on story-B block (same file,
# non-overlapping lines) → chore_commit_field self-resolves, both changes land.
# This is the exact failing case: same-file collision is the trigger.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-DRIFT-SELF-RESOLVE (AC4a): behind+dirty self-resolve (non-overlapping blocks) ==="

DSR_DIR="$FIXTURE_DIR/dsr-project"
DSR_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
DSR_STORY_A="DSR-A"
DSR_STORY_B="DSR-B"
DSR_LOCK_DIR="$FIXTURE_DIR/dsr-locks"
DSR_LOG="$FIXTURE_DIR/dsr.log"
DSR_DAEMON_DIR="$(dirname "$DAEMON")"
mkdir -p "$DSR_LOCK_DIR"

DSR_INIT_YAML="- id: $DSR_STORY_A
  status: in_progress
  phase_status: planned
  delivery_pipeline: 3phase
- id: $DSR_STORY_B
  status: in_progress
  phase_status: planned
  delivery_pipeline: 3phase"

setup_git_repo "$DSR_DIR" "$DSR_INIT_YAML"

# Origin advances: story-B phase_status=implemented (different block from story-A)
DSR_ORIGIN_YAML="- id: $DSR_STORY_A
  status: in_progress
  phase_status: planned
  delivery_pipeline: 3phase
- id: $DSR_STORY_B
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase"
printf '%s\n' "$(backlog_fixture "$DSR_ORIGIN_YAML")" > "$DSR_DIR/$DSR_BACKLOG_REL"
git -C "$DSR_DIR" add "$DSR_BACKLOG_REL"
git -C "$DSR_DIR" commit -m "chore($DSR_STORY_B): implemented [daemon]" -q
git -C "$DSR_DIR" push origin HEAD -q
# Reset local to initial — behind origin by 1, story-B back to planned locally
git -C "$DSR_DIR" reset --hard HEAD~1 -q
# Add uncommitted local drift on story-A block only
DSR_DRIFT_YAML="- id: $DSR_STORY_A
  status: in_progress
  phase_status: qa_failed
  delivery_pipeline: 3phase
- id: $DSR_STORY_B
  status: in_progress
  phase_status: planned
  delivery_pipeline: 3phase"
printf '%s\n' "$(backlog_fixture "$DSR_DRIFT_YAML")" > "$DSR_DIR/$DSR_BACKLOG_REL"

DSR_HARNESS="$FIXTURE_DIR/dsr-harness.sh"
cat > "$DSR_HARNESS" <<DSR_HEREDOC
#!/usr/bin/env bash
set -euo pipefail
cd "$DSR_DIR"
export LOCK_DIR="$DSR_LOCK_DIR"
export BACKLOG_FILE="$DSR_DIR/$DSR_BACKLOG_REL"
export BACKLOG="$DSR_DIR/$DSR_BACKLOG_REL"
export BACKLOG_REL="$DSR_BACKLOG_REL"
export TARGET_BRANCH="main"
export SCHEDULER="$SCHEDULER"
source "$DSR_DAEMON_DIR/lib/chore-commit.sh"
chore_commit_field "$DSR_STORY_A" phase_status implemented "chore($DSR_STORY_A): implemented [daemon]"
DSR_HEREDOC
chmod +x "$DSR_HARNESS"
DSR_RC=0
bash "$DSR_HARNESS" > "$DSR_LOG" 2>&1 || DSR_RC=$?
rm -f "$DSR_HARNESS"

if [[ "$DSR_RC" -eq 0 ]]; then
  pass "T-DSR-1: chore_commit_field self-resolved behind+dirty (rc=0)"
else
  fail "T-DSR-1: expected rc=0, got rc=$DSR_RC — log: $(head -5 "$DSR_LOG" 2>/dev/null | tr '\n' '|')"
fi

DSR_ORIGIN=$(git -C "$DSR_DIR" show "origin/main:$DSR_BACKLOG_REL" 2>/dev/null || echo "MISSING")
DSR_A_PS=$(printf '%s\n' "$DSR_ORIGIN" | awk '/^- id: '"$DSR_STORY_A"'/{f=1} f && /^  phase_status:/{print $2; exit}')
if [[ "$DSR_A_PS" == "implemented" ]]; then
  pass "T-DSR-2: story-A phase_status=implemented on origin"
else
  fail "T-DSR-2: story-A phase_status='$DSR_A_PS' (expected implemented)"
fi

DSR_B_PS=$(printf '%s\n' "$DSR_ORIGIN" | awk '/^- id: '"$DSR_STORY_B"'/{f=1} f && /^  phase_status:/{print $2; exit}')
if [[ "$DSR_B_PS" == "implemented" ]]; then
  pass "T-DSR-3: story-B drift swept to origin (implemented)"
else
  fail "T-DSR-3: story-B phase_status='$DSR_B_PS' (expected implemented — drift not swept)"
fi

if grep -qi "operator intervention required" "$DSR_LOG" 2>/dev/null; then
  fail "T-DSR-4: spurious 'operator intervention required' message present"
else
  pass "T-DSR-4: no 'operator intervention required' message"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T-SAME-LINE-CONFLICT (AC4d)
# Both sides edit the SAME yaml line → rc=6 via chore-commit helper,
# confirming AC2 compliance (no bespoke conflict message).
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-SAME-LINE-CONFLICT (AC4d): same-line edit on both sides → rc=6 ==="

SLC_DIR="$FIXTURE_DIR/slc-project"
SLC_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
SLC_STORY="SLC-A"
SLC_LOCK_DIR="$FIXTURE_DIR/slc-locks"
SLC_LOG="$FIXTURE_DIR/slc.log"
SLC_DAEMON_DIR="$(dirname "$DAEMON")"
mkdir -p "$SLC_LOCK_DIR"

SLC_INIT_YAML="- id: $SLC_STORY
  status: in_progress
  phase_status: planned
  delivery_pipeline: 3phase"
setup_git_repo "$SLC_DIR" "$SLC_INIT_YAML"

# Origin: story status changes to done (modifies the status: line on story-A)
SLC_ORIGIN_YAML="- id: $SLC_STORY
  status: done
  phase_status: done
  delivery_pipeline: 3phase"
printf '%s\n' "$(backlog_fixture "$SLC_ORIGIN_YAML")" > "$SLC_DIR/$SLC_BACKLOG_REL"
git -C "$SLC_DIR" add "$SLC_BACKLOG_REL"
git -C "$SLC_DIR" commit -m "chore($SLC_STORY): done [pr-watcher]" -q
git -C "$SLC_DIR" push origin HEAD -q
# Local: reset to initial (behind), then drift the SAME line to a different value
git -C "$SLC_DIR" reset --hard HEAD~1 -q
SLC_DRIFT_YAML="- id: $SLC_STORY
  status: refined
  phase_status: not_started
  delivery_pipeline: 3phase"
printf '%s\n' "$(backlog_fixture "$SLC_DRIFT_YAML")" > "$SLC_DIR/$SLC_BACKLOG_REL"

SLC_HARNESS="$FIXTURE_DIR/slc-harness.sh"
cat > "$SLC_HARNESS" <<SLC_HEREDOC
#!/usr/bin/env bash
set -uo pipefail
cd "$SLC_DIR"
export LOCK_DIR="$SLC_LOCK_DIR"
export BACKLOG_FILE="$SLC_DIR/$SLC_BACKLOG_REL"
export BACKLOG="$SLC_DIR/$SLC_BACKLOG_REL"
export BACKLOG_REL="$SLC_BACKLOG_REL"
export TARGET_BRANCH="main"
export SCHEDULER="$SCHEDULER"
source "$SLC_DAEMON_DIR/lib/chore-commit.sh"
chore_commit_field "$SLC_STORY" status failed "chore($SLC_STORY): failed [daemon-staleness]"
SLC_HEREDOC
chmod +x "$SLC_HARNESS"
SLC_RC=0
bash "$SLC_HARNESS" > "$SLC_LOG" 2>&1 || SLC_RC=$?
rm -f "$SLC_HARNESS"

if [[ "$SLC_RC" -eq 6 ]]; then
  pass "T-SLC-1: genuine same-line conflict returns rc=6"
else
  fail "T-SLC-1: expected rc=6, got rc=$SLC_RC — log: $(head -5 "$SLC_LOG" 2>/dev/null | tr '\n' '|')"
fi

# The helper's conflict line is emitted by _commit_accumulated_backlog_drift as
# "[COMMIT-DRIFT] <sid> : genuine rebase conflict [<context>]". The trailing
# ", operator resolve required" this asserted no longer appears anywhere in the
# scripts — the message carries the caller context in brackets instead. What AC2
# actually pins is that the conflict is reported by the shared helper rather than
# a bespoke per-caller deadlock string, so match the helper's real format.
if grep -qi "\[COMMIT-DRIFT\].*genuine rebase conflict" "$SLC_LOG" 2>/dev/null; then
  pass "T-SLC-2: helper conflict message present (AC2 — no bespoke deadlock string)"
else
  fail "T-SLC-2: expected '[COMMIT-DRIFT] ... genuine rebase conflict' — log: $(head -5 "$SLC_LOG" 2>/dev/null | tr '\n' '|')"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T-STALE-MERGED-PR (AC4b)
# in_progress past stale threshold with a MERGED delivery PR → reconcile done,
# NOT stale-failed. Validates AC3a guard in check_stale_in_progress.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-STALE-MERGED-PR (AC4b): stale story with merged PR → reconcile done ==="

SMPR_DIR="$FIXTURE_DIR/smpr-project"
SMPR_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
SMPR_STORY="TST-SMPR"
SMPR_LOCK_DIR="$FIXTURE_DIR/smpr-locks"
SMPR_LOG="$FIXTURE_DIR/smpr.log"
SMPR_FLAG="$FIXTURE_DIR/smpr-reconcile-flag"
SMPR_MOCK_GH_DIR="$FIXTURE_DIR/smpr-mock-gh"
SMPR_DAEMON_DIR="$(dirname "$DAEMON")"
mkdir -p "$SMPR_LOCK_DIR" "$SMPR_MOCK_GH_DIR"

SMPR_YAML="items:
- id: $SMPR_STORY
  status: in_progress
  phase_status: planned
  delivery_pipeline: 3phase"
setup_git_repo "$SMPR_DIR" "$SMPR_YAML"
# Stale in_progress commit: timestamp set to 2020 so age > STALENESS_THRESHOLD=0
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" \
  git -C "$SMPR_DIR" commit --allow-empty \
  -m "chore($SMPR_STORY): in_progress [daemon]" -q
git -C "$SMPR_DIR" push origin HEAD -q

cat > "$SMPR_MOCK_GH_DIR/gh" <<'GH_SMPR_EOF'
#!/usr/bin/env bash
echo "${MOCK_GH_RESPONSE:-[]}"
exit 0
GH_SMPR_EOF
chmod +x "$SMPR_MOCK_GH_DIR/gh"

SMPR_HARNESS="$FIXTURE_DIR/smpr-harness.sh"
cat > "$SMPR_HARNESS" <<SMPR_EOF
#!/usr/bin/env bash
set -uo pipefail
export PATH="$SMPR_MOCK_GH_DIR:\$PATH"
export MOCK_GH_RESPONSE='[{"number":42,"mergedAt":"2026-06-17T10:00:00Z","state":"MERGED"}]'

PROJECT_DIR="$SMPR_DIR"
BACKLOG_REL="$SMPR_BACKLOG_REL"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$SMPR_LOCK_DIR"
LOG_DIR="$SMPR_LOCK_DIR/logs"
LOG_FILE="$SMPR_LOG"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
DRY_RUN=false
STALENESS_THRESHOLD=0
SUSPEND_GRACE_UNTIL=0
GAAI_RECONCILE_GRACE_SEC=0

mkdir -p "\$LOG_DIR" "\$LOCK_DIR"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log() { echo "\$*" >> "\$LOG_FILE"; }
is_locked() { return 1; }
with_staging_lock() { "\$@"; }
notify_escalation() { return 0; }
track_for_resolution() { return 0; }
_write_drift_marker() { return 0; }
_reconcile_merged_pr() { touch "$SMPR_FLAG"; return 0; }
fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/main:\$BACKLOG_REL" 2>/dev/null || cat "\$BACKLOG"
}

source "$SMPR_DAEMON_DIR/lib/backlog-yaml.sh"
_BACKLOG_YQ_AVAILABLE="no"

eval "\$(awk '
  /^check_stale_in_progress\(\)/{p=1; depth=0}
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

check_stale_in_progress
SMPR_EOF
chmod +x "$SMPR_HARNESS"
bash "$SMPR_HARNESS" > /dev/null 2>&1 || true
rm -f "$SMPR_HARNESS"

if [[ -f "$SMPR_FLAG" ]]; then
  pass "T-SMPR-1: _reconcile_merged_pr called (merged story not stale-failed)"
else
  fail "T-SMPR-1: _reconcile_merged_pr NOT called — merged story went to fail path"
fi

SMPR_FAIL_COUNT=$(git -C "$SMPR_DIR" log --oneline "origin/main" 2>/dev/null \
  | grep -c "chore($SMPR_STORY): failed" 2>/dev/null; true)
if [[ "$SMPR_FAIL_COUNT" -eq 0 ]]; then
  pass "T-SMPR-2: no 'failed' commit pushed (story correctly not stale-failed)"
else
  fail "T-SMPR-2: $SMPR_FAIL_COUNT 'failed' commit(s) found — story incorrectly stale-failed"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T-QA-PASSED-OPEN-PR (AC4c)
# qa_passed story past stale threshold with OPEN delivery PR → held, not failed.
# Validates AC3b guard in check_stale_in_progress.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-QA-PASSED-OPEN-PR (AC4c): qa_passed + OPEN PR → hold, not fail ==="

QAOP_DIR="$FIXTURE_DIR/qaop-project"
QAOP_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
QAOP_STORY="TST-QAOP"
QAOP_LOCK_DIR="$FIXTURE_DIR/qaop-locks"
QAOP_LOG="$FIXTURE_DIR/qaop.log"
QAOP_MOCK_GH_DIR="$FIXTURE_DIR/qaop-mock-gh"
QAOP_DAEMON_DIR="$(dirname "$DAEMON")"
mkdir -p "$QAOP_LOCK_DIR" "$QAOP_MOCK_GH_DIR"

QAOP_YAML="items:
- id: $QAOP_STORY
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase"
setup_git_repo "$QAOP_DIR" "$QAOP_YAML"
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" \
  git -C "$QAOP_DIR" commit --allow-empty \
  -m "chore($QAOP_STORY): in_progress [daemon]" -q
git -C "$QAOP_DIR" push origin HEAD -q

cat > "$QAOP_MOCK_GH_DIR/gh" <<'GH_QAOP_EOF'
#!/usr/bin/env bash
echo "${MOCK_GH_RESPONSE:-[]}"
exit 0
GH_QAOP_EOF
chmod +x "$QAOP_MOCK_GH_DIR/gh"

QAOP_HARNESS="$FIXTURE_DIR/qaop-harness.sh"
cat > "$QAOP_HARNESS" <<QAOP_EOF
#!/usr/bin/env bash
set -uo pipefail
export PATH="$QAOP_MOCK_GH_DIR:\$PATH"
export MOCK_GH_RESPONSE='[{"number":99,"mergedAt":null,"state":"OPEN"}]'

PROJECT_DIR="$QAOP_DIR"
BACKLOG_REL="$QAOP_BACKLOG_REL"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$QAOP_LOCK_DIR"
LOG_DIR="$QAOP_LOCK_DIR/logs"
LOG_FILE="$QAOP_LOG"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
DRY_RUN=false
STALENESS_THRESHOLD=0
SUSPEND_GRACE_UNTIL=0
GAAI_RECONCILE_GRACE_SEC=0

mkdir -p "\$LOG_DIR" "\$LOCK_DIR"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log() { echo "\$*" >> "\$LOG_FILE"; }
is_locked() { return 1; }
with_staging_lock() { "\$@"; }
notify_escalation() { return 0; }
track_for_resolution() { return 0; }
_write_drift_marker() { return 0; }
_reconcile_merged_pr() { return 0; }
fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/main:\$BACKLOG_REL" 2>/dev/null || cat "\$BACKLOG"
}

source "$QAOP_DAEMON_DIR/lib/backlog-yaml.sh"
_BACKLOG_YQ_AVAILABLE="no"

eval "\$(awk '
  /^check_stale_in_progress\(\)/{p=1; depth=0}
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

check_stale_in_progress
QAOP_EOF
chmod +x "$QAOP_HARNESS"
bash "$QAOP_HARNESS" > /dev/null 2>&1 || true
rm -f "$QAOP_HARNESS"

QAOP_FAIL_COUNT=$(git -C "$QAOP_DIR" log --oneline "origin/main" 2>/dev/null \
  | grep -c "chore($QAOP_STORY): failed" 2>/dev/null; true)
if [[ "$QAOP_FAIL_COUNT" -eq 0 ]]; then
  pass "T-QAOP-1: no 'failed' commit pushed (qa_passed+OPEN PR story held)"
else
  fail "T-QAOP-1: $QAOP_FAIL_COUNT 'failed' commit(s) found — story incorrectly stale-failed"
fi

if [[ -f "$QAOP_LOG" ]] && grep -qi "holding" "$QAOP_LOG" 2>/dev/null; then
  pass "T-QAOP-2: 'holding' log message present (AC3b hold path taken)"
else
  fail "T-QAOP-2: 'holding' message not found — log: $(head -5 "$QAOP_LOG" 2>/dev/null | tr '\n' '|')"
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
