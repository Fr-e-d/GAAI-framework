#!/usr/bin/env bash
# worktree-reconcile.test.sh — regression tests for reconcile_done_merged_worktrees()
#
# Covers: reconcile_done_merged_worktrees() (E160S10, AC1-AC5)
# Test cases: T1 clean+done+merged→removed, T1b idempotence, T2 dirty→preserved,
#             T3 not-done→preserved, T4 unmerged→preserved
#
# Usage: bash .gaai/core/scripts/tests/worktree-reconcile.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../delivery-daemon.sh"
LIB_DIR="$SCRIPT_DIR/../lib"

FIXTURE_DIR="/tmp/gaai-wt-reconcile-test-$$"
mkdir -p "$FIXTURE_DIR"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── Git repo helper ────────────────────────────────────────────────────────────
# Creates a bare remote + local clone with content committed to `staging` branch.
setup_git_repo() {
  local project_dir="$1" yaml_content="$2"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  git -C "$project_dir" checkout -b staging -q 2>/dev/null || git -C "$project_dir" checkout staging -q
  local backlog_dir="$project_dir/.gaai/project/contexts/backlog"
  mkdir -p "$backlog_dir"
  printf '%s\n' "$yaml_content" > "$backlog_dir/active.backlog.yaml"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push -u origin staging -q
}

# ── Harness builder ────────────────────────────────────────────────────────────
# Writes a self-contained bash script that:
#   - sets the minimal env vars the function needs
#   - sources lib/backlog-yaml.sh for backlog_ids_by_status
#   - mocks chore_commit_field (no git I/O in tests)
#   - extracts reconcile_done_merged_worktrees from the daemon via awk
build_harness() {
  local harness_file="$1" project_dir="$2" lock_dir="$3" daemon_log="$4"
  local extra_env="${5:-}"
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
TARGET_BRANCH="staging"
DRY_RUN=false
POLL_INTERVAL=30

$extra_env

mkdir -p "\$LOG_DIR" "\$LOCK_DIR"

RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

log() {
  local msg="[\$(date '+%H:%M:%S')] \$*"
  printf '%s\n' "\$msg" >> "\$LOG_FILE"
}

# Mock chore_commit_field — tests verify worktree removal, not git commits.
chore_commit_field() { return 0; }
_CHORE_HELPER_AVAILABLE=0

# Source backlog-yaml.sh for backlog_ids_by_status.
# shellcheck source=lib/backlog-yaml.sh
source "$LIB_DIR/backlog-yaml.sh"

# Extract reconcile_done_merged_worktrees from the daemon via brace-depth awk.
eval "\$(awk '
  /^reconcile_done_merged_worktrees\(\)/{ p=1; depth=0 }
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
# T1: done + merged + clean → worktree removed, log "removed", exit 0  (AC1, AC3)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: done+merged+clean → worktree removed ==="

T1_SID="E999T1-01"
T1_DIR="$FIXTURE_DIR/t1-project"
T1_LOCK="$FIXTURE_DIR/t1-locks"
T1_LOG="$FIXTURE_DIR/t1.log"
T1_WT_BASE="$FIXTURE_DIR/t1-worktrees"
T1_WT_PATH="$T1_WT_BASE/${T1_SID}-workspace"
mkdir -p "$T1_LOCK" "$T1_WT_BASE"
touch "$T1_LOG"

T1_YAML="items:
- id: $T1_SID
  status: done
  phase_status: done
  delivery_pipeline: 3phase"

setup_git_repo "$T1_DIR" "$T1_YAML"
# Create story branch pointing to the same commit as staging (already merged).
git -C "$T1_DIR" branch "story/$T1_SID" -q
git -C "$T1_DIR" worktree add "$T1_WT_PATH" "story/$T1_SID" -q

T1_HARNESS=$(mktemp "$FIXTURE_DIR/t1-XXXXXX.sh")
build_harness "$T1_HARNESS" "$T1_DIR" "$T1_LOCK" "$T1_LOG" \
  "export GAAI_WORKTREES_BASE=\"$T1_WT_BASE\""
printf 'reconcile_done_merged_worktrees\necho "EXIT:$?"\n' >> "$T1_HARNESS"
chmod +x "$T1_HARNESS"
T1_OUT=$(bash "$T1_HARNESS" 2>/dev/null || true)
T1_EXIT=$(printf '%s\n' "$T1_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)
T1_LOG_CONTENT=$(cat "$T1_LOG" 2>/dev/null || echo "")

if [[ ! -d "$T1_WT_PATH" ]]; then
  pass "T1: worktree directory removed"
else
  fail "T1: worktree directory still exists at $T1_WT_PATH"
fi

if [[ "${T1_EXIT:-}" == "0" ]]; then
  pass "T1: function exited 0"
else
  fail "T1: expected exit 0, got '${T1_EXIT:-}'"
fi

if printf '%s\n' "$T1_LOG_CONTENT" | grep -q "RECONCILE-SWEEP.*removed"; then
  pass "T1: log contains 'removed' entry (AC3)"
else
  fail "T1: expected RECONCILE-SWEEP removed in log (got: $(tail -5 "$T1_LOG" 2>/dev/null))"
fi

if printf '%s\n' "$T1_LOG_CONTENT" | grep -q "path=$T1_WT_PATH"; then
  pass "T1: log contains worktree path (AC3 path requirement)"
else
  fail "T1: expected path=$T1_WT_PATH in log (AC3 — wt_path missing from log)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T1b: idempotence — repeat sweep on same state (worktree already gone) → no-op, exit 0
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1b: idempotence — repeat sweep after removal ==="

rm -f "$T1_LOG" 2>/dev/null; touch "$T1_LOG"
T1B_HARNESS=$(mktemp "$FIXTURE_DIR/t1b-XXXXXX.sh")
build_harness "$T1B_HARNESS" "$T1_DIR" "$T1_LOCK" "$T1_LOG" \
  "export GAAI_WORKTREES_BASE=\"$T1_WT_BASE\""
printf 'reconcile_done_merged_worktrees\necho "EXIT:$?"\n' >> "$T1B_HARNESS"
chmod +x "$T1B_HARNESS"
T1B_OUT=$(bash "$T1B_HARNESS" 2>/dev/null || true)
T1B_EXIT=$(printf '%s\n' "$T1B_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)

if [[ "${T1B_EXIT:-}" == "0" ]]; then
  pass "T1b: idempotent second run exits 0"
else
  fail "T1b: expected exit 0 on repeat run, got '${T1B_EXIT:-}'"
fi

# Worktree should still be absent (not recreated).
if [[ ! -d "$T1_WT_PATH" ]]; then
  pass "T1b: worktree remains absent after repeat run"
else
  fail "T1b: worktree unexpectedly re-created on repeat run"
fi

rm -f "$T1_HARNESS" "$T1B_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T2: done + merged + DIRTY → worktree preserved, log "skipped:dirty"  (AC2)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: done+merged+dirty → worktree preserved (AC2 data-safety) ==="

T2_SID="E999T2-01"
T2_DIR="$FIXTURE_DIR/t2-project"
T2_LOCK="$FIXTURE_DIR/t2-locks"
T2_LOG="$FIXTURE_DIR/t2.log"
T2_WT_BASE="$FIXTURE_DIR/t2-worktrees"
T2_WT_PATH="$T2_WT_BASE/${T2_SID}-workspace"
mkdir -p "$T2_LOCK" "$T2_WT_BASE"
touch "$T2_LOG"

T2_YAML="items:
- id: $T2_SID
  status: done
  phase_status: done
  delivery_pipeline: 3phase"

setup_git_repo "$T2_DIR" "$T2_YAML"
git -C "$T2_DIR" branch "story/$T2_SID" -q
git -C "$T2_DIR" worktree add "$T2_WT_PATH" "story/$T2_SID" -q
# Add an untracked file to make the worktree dirty.
echo "operator note" > "$T2_WT_PATH/untracked-delivery-note.txt"

T2_HARNESS=$(mktemp "$FIXTURE_DIR/t2-XXXXXX.sh")
build_harness "$T2_HARNESS" "$T2_DIR" "$T2_LOCK" "$T2_LOG" \
  "export GAAI_WORKTREES_BASE=\"$T2_WT_BASE\""
printf 'reconcile_done_merged_worktrees\necho "EXIT:$?"\n' >> "$T2_HARNESS"
chmod +x "$T2_HARNESS"
T2_OUT=$(bash "$T2_HARNESS" 2>/dev/null || true)
T2_EXIT=$(printf '%s\n' "$T2_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)
T2_LOG_CONTENT=$(cat "$T2_LOG" 2>/dev/null || echo "")

if [[ -d "$T2_WT_PATH" ]]; then
  pass "T2: dirty worktree preserved (AC2)"
else
  fail "T2: dirty worktree was removed — data destroyed!"
fi

if [[ "${T2_EXIT:-}" == "0" ]]; then
  pass "T2: function exited 0 (no crash on dirty worktree)"
else
  fail "T2: expected exit 0, got '${T2_EXIT:-}'"
fi

if printf '%s\n' "$T2_LOG_CONTENT" | grep -q "skipped:dirty"; then
  pass "T2: log contains 'skipped:dirty' (AC3)"
else
  fail "T2: expected skipped:dirty in log (got: $(tail -5 "$T2_LOG" 2>/dev/null))"
fi

if printf '%s\n' "$T2_LOG_CONTENT" | grep -q "path=$T2_WT_PATH"; then
  pass "T2: log contains worktree path (AC3 path requirement)"
else
  fail "T2: expected path=$T2_WT_PATH in log (AC3 — wt_path missing from log)"
fi

rm -f "$T2_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T3: not-done → worktree preserved (status=in_progress, never returned by backlog_ids_by_status)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: not-done story → worktree preserved ==="

T3_SID="E999T3-01"
T3_DIR="$FIXTURE_DIR/t3-project"
T3_LOCK="$FIXTURE_DIR/t3-locks"
T3_LOG="$FIXTURE_DIR/t3.log"
T3_WT_BASE="$FIXTURE_DIR/t3-worktrees"
T3_WT_PATH="$T3_WT_BASE/${T3_SID}-workspace"
mkdir -p "$T3_LOCK" "$T3_WT_BASE"
touch "$T3_LOG"

# Story is in_progress, not done.
T3_YAML="items:
- id: $T3_SID
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase"

setup_git_repo "$T3_DIR" "$T3_YAML"
git -C "$T3_DIR" branch "story/$T3_SID" -q
git -C "$T3_DIR" worktree add "$T3_WT_PATH" "story/$T3_SID" -q

T3_HARNESS=$(mktemp "$FIXTURE_DIR/t3-XXXXXX.sh")
build_harness "$T3_HARNESS" "$T3_DIR" "$T3_LOCK" "$T3_LOG" \
  "export GAAI_WORKTREES_BASE=\"$T3_WT_BASE\""
printf 'reconcile_done_merged_worktrees\necho "EXIT:$?"\n' >> "$T3_HARNESS"
chmod +x "$T3_HARNESS"
T3_OUT=$(bash "$T3_HARNESS" 2>/dev/null || true)
T3_EXIT=$(printf '%s\n' "$T3_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)

if [[ -d "$T3_WT_PATH" ]]; then
  pass "T3: in_progress worktree preserved (not-done scope guard)"
else
  fail "T3: in_progress worktree was removed — scope guard failed!"
fi

if [[ "${T3_EXIT:-}" == "0" ]]; then
  pass "T3: function exited 0"
else
  fail "T3: expected exit 0, got '${T3_EXIT:-}'"
fi

rm -f "$T3_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T4: done + UNMERGED → worktree preserved, log "skipped:unmerged"  (AC1)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: done+unmerged → worktree preserved, log skipped:unmerged ==="

T4_SID="E999T4-01"
T4_DIR="$FIXTURE_DIR/t4-project"
T4_LOCK="$FIXTURE_DIR/t4-locks"
T4_LOG="$FIXTURE_DIR/t4.log"
T4_WT_BASE="$FIXTURE_DIR/t4-worktrees"
T4_WT_PATH="$T4_WT_BASE/${T4_SID}-workspace"
mkdir -p "$T4_LOCK" "$T4_WT_BASE"
touch "$T4_LOG"

T4_YAML="items:
- id: $T4_SID
  status: done
  phase_status: done
  delivery_pipeline: 3phase"

setup_git_repo "$T4_DIR" "$T4_YAML"
# Create story branch with an extra commit NOT merged into staging.
git -C "$T4_DIR" branch "story/$T4_SID" -q
git -C "$T4_DIR" worktree add "$T4_WT_PATH" "story/$T4_SID" -q
# Add a commit to the worktree branch — this makes it diverge from staging.
git -C "$T4_WT_PATH" config user.email "test@gaai.local"
git -C "$T4_WT_PATH" config user.name "GAAI Test"
echo "impl" > "$T4_WT_PATH/impl.txt"
git -C "$T4_WT_PATH" add impl.txt
git -C "$T4_WT_PATH" commit -m "impl work" -q
# Push the branch to origin so it exists remotely, but do NOT merge into staging.
git -C "$T4_DIR" push origin "story/$T4_SID" -q 2>/dev/null || true
# origin/staging does NOT include story/$T4_SID's extra commit → unmerged.

T4_HARNESS=$(mktemp "$FIXTURE_DIR/t4-XXXXXX.sh")
build_harness "$T4_HARNESS" "$T4_DIR" "$T4_LOCK" "$T4_LOG" \
  "export GAAI_WORKTREES_BASE=\"$T4_WT_BASE\""
printf 'reconcile_done_merged_worktrees\necho "EXIT:$?"\n' >> "$T4_HARNESS"
chmod +x "$T4_HARNESS"
T4_OUT=$(bash "$T4_HARNESS" 2>/dev/null || true)
T4_EXIT=$(printf '%s\n' "$T4_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)
T4_LOG_CONTENT=$(cat "$T4_LOG" 2>/dev/null || echo "")

if [[ -d "$T4_WT_PATH" ]]; then
  pass "T4: unmerged worktree preserved (AC1 merged-only guard)"
else
  fail "T4: unmerged worktree was removed — merged-only guard failed!"
fi

if [[ "${T4_EXIT:-}" == "0" ]]; then
  pass "T4: function exited 0"
else
  fail "T4: expected exit 0, got '${T4_EXIT:-}'"
fi

if printf '%s\n' "$T4_LOG_CONTENT" | grep -q "skipped:unmerged"; then
  pass "T4: log contains 'skipped:unmerged' (AC3)"
else
  fail "T4: expected skipped:unmerged in log (got: $(tail -5 "$T4_LOG" 2>/dev/null))"
fi

if printf '%s\n' "$T4_LOG_CONTENT" | grep -q "path=$T4_WT_PATH"; then
  pass "T4: log contains worktree path (AC3 path requirement)"
else
  fail "T4: expected path=$T4_WT_PATH in log (AC3 — wt_path missing from log)"
fi

rm -f "$T4_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T5: AC5 compliance — no auto_merge_policy change, no PR merge, exit 0
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: AC5 compliance — no policy change, no PR merge, exits 0 ==="

# Re-use T1's already-cleaned state: backlog has a done story, worktree gone.
# Sweep should be a no-op and must not touch any policy variable.
T5_LOG="$FIXTURE_DIR/t5.log"
touch "$T5_LOG"
T5_HARNESS=$(mktemp "$FIXTURE_DIR/t5-XXXXXX.sh")
build_harness "$T5_HARNESS" "$T1_DIR" "$T1_LOCK" "$T5_LOG" \
  "GAAI_AUTO_MERGE_POLICY=\"\${GAAI_AUTO_MERGE_POLICY:-staging_only}\"
   export GAAI_WORKTREES_BASE=\"$T1_WT_BASE\""
cat >> "$T5_HARNESS" <<'EOF'
POLICY_BEFORE="${GAAI_AUTO_MERGE_POLICY:-staging_only}"
reconcile_done_merged_worktrees
RC=$?
POLICY_AFTER="${GAAI_AUTO_MERGE_POLICY:-staging_only}"
echo "EXIT:$RC"
echo "POLICY_DELTA:$([ "$POLICY_BEFORE" == "$POLICY_AFTER" ] && echo unchanged || echo CHANGED)"
EOF
chmod +x "$T5_HARNESS"
T5_OUT=$(bash "$T5_HARNESS" 2>/dev/null || true)
T5_EXIT=$(printf '%s\n' "$T5_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)
T5_DELTA=$(printf '%s\n' "$T5_OUT" | grep "^POLICY_DELTA:" | sed 's/POLICY_DELTA://' | head -1)

if [[ "${T5_EXIT:-}" == "0" ]]; then
  pass "T5: sweep exits 0 (AC5 — no crash)"
else
  fail "T5: expected exit 0, got '${T5_EXIT:-}'"
fi

if [[ "${T5_DELTA:-}" == "unchanged" ]]; then
  pass "T5: GAAI_AUTO_MERGE_POLICY unchanged (AC5 — no policy mutation)"
else
  fail "T5: GAAI_AUTO_MERGE_POLICY was modified — AC5 violation!"
fi

rm -f "$T5_HARNESS"

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
