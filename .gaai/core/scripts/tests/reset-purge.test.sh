#!/usr/bin/env bash
# reset-purge.test.sh — AC5 regression for E222S01
#
# Asserts that _recovery_revert_refined atomically clears stale pr_url/pr_number,
# the retry-counter entry, and the worktree+branch when reverting a story to refined.
#
# Usage: bash .gaai/core/scripts/tests/reset-purge.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON="$SCRIPTS/delivery-daemon.sh"
SCHEDULER="$SCRIPTS/backlog-scheduler.sh"

FIXTURE_DIR="/tmp/gaai-reset-purge-test-$$"
cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT
mkdir -p "$FIXTURE_DIR"

SID="TST-RP01"
BRANCH="main"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"

# ── fixture setup ──────────────────────────────────────────────────────────────
PROJ="$FIXTURE_DIR/project"
REMOTE="$FIXTURE_DIR/project_remote.git"
WT_BASE="$FIXTURE_DIR/worktrees"
WT_PATH="$WT_BASE/${SID}-workspace"
LOCK_DIR="$FIXTURE_DIR/locks"
LOG_FILE="$FIXTURE_DIR/daemon.log"
BACKLOG="$PROJ/$BACKLOG_REL"
RETRY_FILE="$LOCK_DIR/.retry-counts"

mkdir -p "$LOCK_DIR" "$WT_BASE"
touch "$LOG_FILE"

# Backlog with pr_url + pr_number + a second story to verify no cross-story drift
BACKLOG_YAML='items:
- id: TST-RP01
  status: in_progress
  phase_status: qa_escalated
  delivery_pipeline: 3phase
  pr_url: "https://github.com/example/repo/pull/42"
  pr_number: "42"
- id: TST-OTHER
  status: refined
  phase_status: not_started
  delivery_pipeline: 3phase'

# Initialise bare remote + clone
git init --bare "$REMOTE" -q
git clone "$REMOTE" "$PROJ" -q
git -C "$PROJ" config user.email "test@gaai.local"
git -C "$PROJ" config user.name "GAAI Test"
git -C "$PROJ" checkout -b "$BRANCH" -q 2>/dev/null || true
mkdir -p "$(dirname "$BACKLOG")"
printf '%s\n' "$BACKLOG_YAML" > "$BACKLOG"
git -C "$PROJ" add .
git -C "$PROJ" commit -m "initial" -q
git -C "$PROJ" push origin "$BRANCH" -q

# Retry-counts with story at cap + another story (should be preserved)
printf '%s=3\nTST-OTHER=1\n' "$SID" > "$RETRY_FILE"

# Create story branch + worktree
git -C "$PROJ" checkout -b "story/$SID" -q
git -C "$PROJ" checkout "$BRANCH" -q
git -C "$PROJ" worktree add "$WT_PATH" "story/$SID" -q

echo ""
echo "=== reset-purge: AC5 — _recovery_revert_refined clears all stale state ==="
echo ""

# ── harness ────────────────────────────────────────────────────────────────────
HARNESS=$(mktemp /tmp/gaai-rp-harness-XXXXXX.sh)
cat > "$HARNESS" <<HARNESS_EOF
#!/usr/bin/env bash
set -uo pipefail

# Daemon global vars (all absolute paths, expanded at harness-generation time)
PROJECT_DIR="$PROJ"
GAAI_PROJECT_DIR="$PROJ/.gaai/project"
BACKLOG="$BACKLOG"
BACKLOG_FILE="$BACKLOG"
BACKLOG_REL="$BACKLOG_REL"
LOCK_DIR="$LOCK_DIR"
RETRY_FILE="$RETRY_FILE"
LOG_DIR="$FIXTURE_DIR"
LOG_FILE="$LOG_FILE"
STAGING_LOCK="$LOCK_DIR/.staging.lock"
REBASE_CONFLICT_MARKER="$LOCK_DIR/.rebase-conflict.audit"
DRIFT_MARKER="$LOCK_DIR/.drift-detected.audit"
TARGET_BRANCH="$BRANCH"
SCHEDULER="$SCHEDULER"
SCRIPT_DIR="$SCRIPTS"
GAAI_WORKTREES_BASE="$WT_BASE"
PLATFORM="\$(uname)"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

log() { printf '%s\n' "\$*" >> "$LOG_FILE" 2>/dev/null || true; }

# Minimal stubs
with_staging_lock() { "\$@"; }
notify_escalation()  { return 0; }
is_locked()          { [[ -f "$LOCK_DIR/\$1.lock" ]]; }

# Extract required functions from the daemon source
eval "\$(awk '
  /^sed_inplace\(\)/{p=1; depth=0}
  /^_write_drift_marker\(\)/{p=1; depth=0}
  /^_recovery_resolve_worktree\(\)/{p=1; depth=0}
  /^_recovery_revert_refined\(\)/{p=1; depth=0}
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

_recovery_revert_refined "$SID" "true" "test-reset"
exit \$?
HARNESS_EOF

chmod +x "$HARNESS"
set +e
bash "$HARNESS" 2>/dev/null
HARNESS_RC=$?
set -e
rm -f "$HARNESS"

if [[ $HARNESS_RC -ne 0 ]]; then
  fail "harness: _recovery_revert_refined returned $HARNESS_RC — commit or setup failed"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  exit 1
fi

# ── assertions ────────────────────────────────────────────────────────────────

echo "T1: pr_url removed from YAML for target story"
if grep -A 15 "id: $SID" "$BACKLOG" | grep -q "pr_url:"; then
  fail "T1: pr_url still present in YAML after reset"
else
  pass "T1: pr_url absent from YAML"
fi

echo "T2: pr_number removed from YAML for target story"
if grep -A 15 "id: $SID" "$BACKLOG" | grep -q "pr_number:"; then
  fail "T2: pr_number still present in YAML after reset"
else
  pass "T2: pr_number absent from YAML"
fi

echo "T3: phase_status=not_started"
PHASE=$(grep -A 10 "id: $SID" "$BACKLOG" | grep "phase_status:" | head -1 | awk '{print $2}')
if [[ "$PHASE" == "not_started" ]]; then
  pass "T3: phase_status=not_started"
else
  fail "T3: phase_status='$PHASE' (expected not_started)"
fi

echo "T4: retry-counter entry cleared for target story"
if [[ -f "$RETRY_FILE" ]] && grep -q "^${SID}=" "$RETRY_FILE"; then
  fail "T4: $SID entry still present in .retry-counts"
else
  pass "T4: $SID retry-counter cleared"
fi

echo "T4b: other story retry-counter preserved"
if [[ ! -f "$RETRY_FILE" ]] || ! grep -q "^TST-OTHER=1" "$RETRY_FILE"; then
  fail "T4b: TST-OTHER=1 missing from .retry-counts (cross-story leak)"
else
  pass "T4b: TST-OTHER retry-counter preserved"
fi

echo "T5: worktree directory removed"
if [[ -d "$WT_PATH" ]]; then
  fail "T5: worktree '$WT_PATH' still exists"
else
  pass "T5: worktree removed"
fi

echo "T6: story branch deleted"
if git -C "$PROJ" branch --list "story/$SID" 2>/dev/null | grep -q "story/$SID"; then
  fail "T6: branch story/$SID still exists"
else
  pass "T6: branch story/$SID deleted"
fi

echo "T7: non-target story YAML untouched (cross-story drift guard)"
STATUS_OTHER=$(grep -A 8 "id: TST-OTHER" "$BACKLOG" | grep "status:" | head -1 | awk '{print $2}')
if [[ "$STATUS_OTHER" == "refined" ]]; then
  pass "T7: TST-OTHER status unchanged (refined)"
else
  fail "T7: TST-OTHER status='$STATUS_OTHER' (expected refined — cross-story drift?)"
fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "FAILURES: $FAIL_COUNT"
  exit 1
fi
