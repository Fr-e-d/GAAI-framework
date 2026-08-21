#!/usr/bin/env bash
# reconcile-origin-verify.test.sh — regression for E1057S01 (daemon reconcile
# claims success while the backlog write never lands — dirty daemon-home deadlock)
#
# Reproduces the "committed-but-unpushed flip" deadlock signature end-to-end
# through _reconcile_merged_pr(), using the REAL lib/chore-commit.sh (not the
# harness's own dead inline-fallback branch).
#
# T1: no concurrent writer — origin lands status:done, success log line present (AC1, AC2)
# T2: a concurrent writer advances origin after the pinned snapshot — the
#     exact-parent push fails without clobbering it, then a retry succeeds.
#
# Run: bash .gaai/core/scripts/tests/reconcile-origin-verify.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../delivery-daemon.sh"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"
CHORE_LIB="$SCRIPT_DIR/../lib/chore-commit.sh"
BACKLOG_LIB="$SCRIPT_DIR/../lib/backlog-yaml.sh"

FIXTURE_DIR="/tmp/gaai-reconcile-origin-verify-test-$$"
mkdir -p "$FIXTURE_DIR/lib"
cp "$CHORE_LIB" "$FIXTURE_DIR/lib/chore-commit.sh"
cp "$BACKLOG_LIB" "$FIXTURE_DIR/lib/backlog-yaml.sh"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── Git repo helper — commits an initial state to origin/staging, then adds a
#    SECOND local-only commit (never pushed) carrying the target reconciled
#    values. This is the "committed-but-unpushed flip" precondition. ──────────
setup_committed_unpushed_repo() {
  local project_dir="$1" sid="$2" merged_at="$3"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  git -C "$project_dir" checkout -b staging -q 2>/dev/null || git -C "$project_dir" checkout staging -q

  local backlog_dir="$project_dir/.gaai/project/contexts/backlog"
  mkdir -p "$backlog_dir"
  printf '%s\n' "items:
- id: $sid
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/99
  delivery_pipeline: 3phase
  started_at: \"2026-07-18T08:00:00Z\"" > "$backlog_dir/active.backlog.yaml"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push -u origin staging -q

  # Local-only commit with the target reconciled values — never pushed.
  printf '%s\n' "items:
- id: $sid
  status: done
  phase_status: done
  pr_url: https://github.com/org/repo/pull/99
  delivery_pipeline: 3phase
  started_at: \"2026-07-18T08:00:00Z\"
  completed_at: $merged_at" > "$backlog_dir/active.backlog.yaml"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "chore($sid): done [pre-existing local-only flip]" -q
}

# ── Harness builder — mirrors pr-watcher.test.sh's build_harness, but calls
#    _reconcile_merged_pr directly (no gh mocking needed). ─────────────────────
build_harness() {
  local harness_file="$1" project_dir="$2" lock_dir="$3" daemon_log="$4"
  local backlog_rel=".gaai/project/contexts/backlog/active.backlog.yaml"

  cat > "$harness_file" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail

PROJECT_DIR="$project_dir"
GAAI_PROJECT_DIR="$project_dir/.gaai/project"
BACKLOG_REL="$backlog_rel"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$lock_dir"
LOG_DIR="$lock_dir/logs"
LOG_FILE="$daemon_log"
STAGING_LOCK="\$LOCK_DIR/.staging.lock"
SCHEDULER="$SCHEDULER"
TARGET_BRANCH="staging"

mkdir -p "\$LOG_DIR" "\$LOCK_DIR"

RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

log() {
  local msg="[\$(date '+%H:%M:%S')] \$*"
  echo -e "\$msg" | sed 's/\o033\[[0-9;]*m//g' >> "\$LOG_FILE"
}

with_staging_lock() { "\$@"; }

# Extract _reconcile_merged_pr + its current-cycle gate dependencies from
# delivery-daemon.sh (brace-depth aware)
eval "\$(awk '
  /^_merged_pr_started_at\(\)|^_merged_pr_is_current_cycle\(\)|^_reconcile_merged_pr\(\)/{p=1; depth=0}
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

# ══════════════════════════════════════════════════════════════════════════════
# T1: committed-but-unpushed flip, no concurrent writer → self-heals on origin
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: committed-but-unpushed flip, no concurrent writer — lands on origin ==="

T1_DIR="$FIXTURE_DIR/t1-project"
T1_LOCK="$FIXTURE_DIR/t1-locks"
T1_LOG="$FIXTURE_DIR/t1.log"
mkdir -p "$T1_LOCK"
touch "$T1_LOG"

T1_SID="T1-STORY-01"
T1_MERGED_AT="2026-07-18T10:00:00Z"
setup_committed_unpushed_repo "$T1_DIR" "$T1_SID" "$T1_MERGED_AT"

T1_HARNESS="$FIXTURE_DIR/t1-harness.sh"
build_harness "$T1_HARNESS" "$T1_DIR" "$T1_LOCK" "$T1_LOG"
printf '_reconcile_merged_pr "%s" "%s" "%s" "%s"\n' "$T1_SID" "$T1_MERGED_AT" "99" "2026-07-18T09:00:00Z" >> "$T1_HARNESS"
chmod +x "$T1_HARNESS"
bash "$T1_HARNESS" 2>/dev/null

T1_BACKLOG=$(git -C "$T1_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null || echo "")
T1_STATUS=$(printf '%s\n' "$T1_BACKLOG" | grep "status:" | head -1 | awk '{print $2}' || echo "")

if [[ "$T1_STATUS" == "done" ]]; then
  pass "T1: origin/staging shows status: done — the committed-but-unpushed flip landed (AC1, AC2)"
else
  fail "T1: expected origin status=done, got '$T1_STATUS' — deadlock signature reproduced, fix did not self-heal"
fi

if grep -q "reconciled to status:done" "$T1_LOG" 2>/dev/null; then
  pass "T1: success log line present, matches a real origin-verified landing (AC2)"
else
  fail "T1: success log line missing despite origin landing"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T2: committed-but-unpushed flip, concurrent writer after snapshot → CAS + retry
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: concurrent writer after pinned snapshot — no clobber, later retry ==="

T2_DIR="$FIXTURE_DIR/t2-project"
T2_LOCK="$FIXTURE_DIR/t2-locks"
T2_LOG="$FIXTURE_DIR/t2.log"
mkdir -p "$T2_LOCK"
touch "$T2_LOG"

T2_SID="T2-STORY-02"
T2_MERGED_AT="2026-07-18T10:00:00Z"
setup_committed_unpushed_repo "$T2_DIR" "$T2_SID" "$T2_MERGED_AT"

# Second clone prepares an independent audit file. A pre-push hook on the
# reconciler publishes it only after reconciliation has captured its snapshot
# and built its exact-parent commit, forcing the real compare-and-swap failure
# without making the later retry semantically ineligible.
T2_REMOTE="${T2_DIR}_remote.git"
T2_CONFLICT_CLONE="$FIXTURE_DIR/t2-conflict-writer"
git clone --quiet "$T2_REMOTE" "$T2_CONFLICT_CLONE" 2>/dev/null
git -C "$T2_CONFLICT_CLONE" config user.email "conflict@gaai.local"
git -C "$T2_CONFLICT_CLONE" config user.name "Conflict Writer"
git -C "$T2_CONFLICT_CLONE" checkout -q staging 2>/dev/null || true
printf '%s\n' 'concurrent-writer-landed' > "$T2_CONFLICT_CLONE/.gaai/project/contexts/backlog/concurrent.audit"
git -C "$T2_CONFLICT_CLONE" add .
git -C "$T2_CONFLICT_CLONE" commit -q -m "test: concurrent origin advance"

T2_PRE_PUSH="$T2_DIR/.git/hooks/pre-push"
cat > "$T2_PRE_PUSH" <<HOOK
#!/usr/bin/env bash
set -euo pipefail
git -C "$T2_CONFLICT_CLONE" push -q origin staging
HOOK
chmod +x "$T2_PRE_PUSH"

T2_HARNESS="$FIXTURE_DIR/t2-harness.sh"
build_harness "$T2_HARNESS" "$T2_DIR" "$T2_LOCK" "$T2_LOG"
printf '_reconcile_merged_pr "%s" "%s" "%s" "%s"\n' "$T2_SID" "$T2_MERGED_AT" "99" "2026-07-18T09:00:00Z" >> "$T2_HARNESS"
chmod +x "$T2_HARNESS"
bash "$T2_HARNESS" 2>/dev/null

git -C "$T2_DIR" fetch -q origin staging
T2_BACKLOG=$(git -C "$T2_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null || echo "")
T2_STATUS=$(printf '%s\n' "$T2_BACKLOG" | grep "status:" | head -1 | awk '{print $2}' || echo "")

if [[ "$T2_STATUS" == "in_progress" ]]; then
  pass "T2: origin/staging stayed in_progress after the raced push (AC1)"
else
  fail "T2: expected in_progress after raced push, got '$T2_STATUS'"
fi

if grep -q "reconciled to status:done" "$T2_LOG" 2>/dev/null; then
  fail "T2: success log line present despite unresolved conflict — false success claim (AC1, AC5)"
else
  pass "T2: no false success log line emitted (AC1, AC5)"
fi

if grep -q "RECONCILE_UNLANDED" "$T2_LOG" 2>/dev/null || [[ -f "$T2_LOCK/.reconcile-unlanded.${T2_SID}" ]]; then
  pass "T2: RECONCILE_UNLANDED surfaced via log line or marker file (AC3)"
else
  fail "T2: no RECONCILE_UNLANDED signal — failure was swallowed silently"
fi

if grep -q "exact-parent push lost a race" "$T2_LOG" 2>/dev/null; then
  pass "T2: exercised the exact-parent push-race failure branch"
else
  fail "T2: did not reach the exact-parent push-race failure branch"
fi

if [[ "$(git -C "$T2_DIR" show origin/staging:.gaai/project/contexts/backlog/concurrent.audit 2>/dev/null)" == "concurrent-writer-landed" ]]; then
  pass "T2: concurrent writer state was preserved"
else
  fail "T2: concurrent writer state was lost"
fi

rm -f "$T2_PRE_PUSH"
bash "$T2_HARNESS" 2>/dev/null
git -C "$T2_DIR" fetch -q origin staging
T2_RETRY_BACKLOG=$(git -C "$T2_DIR" show "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null || echo "")
T2_RETRY_STATUS=$(printf '%s\n' "$T2_RETRY_BACKLOG" | grep "status:" | head -1 | awk '{print $2}' || echo "")
if [[ "$T2_RETRY_STATUS" == "done" ]] \
   && [[ "$(git -C "$T2_DIR" show origin/staging:.gaai/project/contexts/backlog/concurrent.audit 2>/dev/null)" == "concurrent-writer-landed" ]]; then
  pass "T2: later retry reconciled done while retaining concurrent state"
else
  fail "T2: later retry did not reconcile cleanly"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
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
