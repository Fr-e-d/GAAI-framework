#!/usr/bin/env bash
# recovery-non-destructive.test.sh — regression tests for non-destructive push-race recovery
#
# Covers: git fetch + git rebase replaces stash + git reset --hard in failure-recovery paths.
# AC3 of E134S15: T1 (uncommitted edits preserved), T2 (conflict marker), T3 (clean rebase).
#
# Usage: bash .gaai/core/scripts/tests/recovery-non-destructive.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

FIXTURE_DIR="/tmp/gaai-recovery-nondestructive-test-$$"
cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT
mkdir -p "$FIXTURE_DIR"

# ── Git repo helpers ───────────────────────────────────────────────────────────
setup_git_repo() {
  local project_dir="$1" content="$2"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  git -C "$project_dir" config rebase.autoStash false
  mkdir -p "$project_dir/.gaai/project/contexts/backlog"
  printf '%s\n' "$content" > "$project_dir/.gaai/project/contexts/backlog/active.backlog.yaml"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push origin HEAD -q
  # Set up staging branch tracking
  git -C "$project_dir" checkout -b staging -q
  git -C "$project_dir" push origin staging -q
}

# Helper: advance origin by one commit (simulates concurrent daemon push)
advance_origin() {
  local project_dir="$1"
  local clone_dir="${project_dir}_advancer"
  git clone "${project_dir}_remote.git" "$clone_dir" -q
  git -C "$clone_dir" config user.email "test@gaai.local"
  git -C "$clone_dir" config user.name "GAAI Advancer"
  git -C "$clone_dir" checkout -b staging -q 2>/dev/null || git -C "$clone_dir" checkout staging -q
  # Modify a different file to advance the branch
  echo "advance-$(date +%s)" > "$clone_dir/.gaai/project/contexts/backlog/advance-marker.txt"
  git -C "$clone_dir" add .
  git -C "$clone_dir" commit -m "concurrent advance" -q
  git -C "$clone_dir" push origin staging -q
  rm -rf "$clone_dir"
}

BACKLOG_YAML="stories:
  - id: TEST01
    status: in_progress
    epic: E999"

# ═══════════════════════════════════════════════════════════════════════════════
# T1 — Uncommitted edits preserved on origin advance
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: uncommitted edits preserved on origin advance ==="

T1_DIR="$FIXTURE_DIR/t1"
setup_git_repo "$T1_DIR" "$BACKLOG_YAML"
TARGET_BRANCH="staging"
test_log="$T1_DIR/test-recovery.log"
test_marker="$T1_DIR/.rebase-conflict.audit"

# Make a local commit so local diverges from origin (required for git pull --ff-only to fail)
echo "local-prior-work" > "$T1_DIR/.gaai/project/contexts/backlog/prior-commit.txt"
git -C "$T1_DIR" add .
git -C "$T1_DIR" commit -m "local commit that diverges from origin" -q

# Add an uncommitted working-tree edit (NOT staged)
echo "my-important-work" > "$T1_DIR/.gaai/project/contexts/backlog/working-note.txt"

# Advance origin (simulates concurrent push)
advance_origin "$T1_DIR"

# Build inline recovery script (isolates the rebase logic from daemon)
RECOVERY_SCRIPT=$(mktemp)
cat > "$RECOVERY_SCRIPT" <<'ENDSCRIPT'
#!/usr/bin/env bash
set -uo pipefail
cd "$1"
TARGET_BRANCH="$2"
LOG_FILE="$3"
REBASE_CONFLICT_MARKER="$4"
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  if ! git rebase "origin/$TARGET_BRANCH" --quiet 2>/dev/null; then
    git rebase --abort --quiet 2>/dev/null || true
    echo "rebase-failed" >> "$LOG_FILE" 2>/dev/null || true
    printf '%s|recovery|rebase-failed-test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
    exit 1
  fi
  echo "rebased-cleanly" >> "$LOG_FILE" 2>/dev/null || true
  rm -f "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
fi
ENDSCRIPT
chmod +x "$RECOVERY_SCRIPT"

bash "$RECOVERY_SCRIPT" "$T1_DIR" "$TARGET_BRANCH" "$test_log" "$test_marker"
t1_rc=$?

# Assert: uncommitted edit still present
if [[ -f "$T1_DIR/.gaai/project/contexts/backlog/working-note.txt" ]] && \
   grep -q "my-important-work" "$T1_DIR/.gaai/project/contexts/backlog/working-note.txt" 2>/dev/null; then
  pass "T1: uncommitted edit preserved after rebase"
else
  fail "T1: uncommitted edit was LOST after recovery"
fi

# Assert: no conflict marker (rebase succeeded)
if [[ ! -f "$test_marker" ]]; then
  pass "T1: no rebase-conflict marker created (rebase clean)"
else
  fail "T1: unexpected rebase-conflict marker created"
fi

# Assert: log shows clean rebase
if grep -q "rebased-cleanly" "$test_log" 2>/dev/null; then
  pass "T1: log shows clean rebase"
else
  fail "T1: log missing clean rebase message"
fi

rm -f "$RECOVERY_SCRIPT"

# ═══════════════════════════════════════════════════════════════════════════════
# T2 — Genuine conflict → audit marker created + non-zero exit + WT not wiped
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: genuine conflict → audit marker + non-zero exit ==="

T2_DIR="$FIXTURE_DIR/t2"
BACKLOG_YAML_T2="stories:
  - id: TEST02
    status: in_progress
    epic: E999"
setup_git_repo "$T2_DIR" "$BACKLOG_YAML_T2"
test_log2="$T2_DIR/test-recovery.log"
test_marker2="$T2_DIR/.rebase-conflict.audit"

# Make a local STAGED change to the SAME line that origin will change
# Use the backlog YAML as the conflict target
cat > "$T2_DIR/.gaai/project/contexts/backlog/active.backlog.yaml" <<'YAMLEOF'
stories:
  - id: TEST02
    status: failed
    epic: E999
YAMLEOF
git -C "$T2_DIR" add .gaai/project/contexts/backlog/active.backlog.yaml

# Advance origin with a DIFFERENT value on the same line
advance_dir="${T2_DIR}_conflicter"
git clone "${T2_DIR}_remote.git" "$advance_dir" -q
git -C "$advance_dir" config user.email "test@gaai.local"
git -C "$advance_dir" config user.name "GAAI Conflicter"
git -C "$advance_dir" checkout staging -q 2>/dev/null || git -C "$advance_dir" checkout -b staging -q
cat > "$advance_dir/.gaai/project/contexts/backlog/active.backlog.yaml" <<'YAMLEOF'
stories:
  - id: TEST02
    status: done
    epic: E999
YAMLEOF
git -C "$advance_dir" add .
git -C "$advance_dir" commit -m "conflicting remote change" -q
git -C "$advance_dir" push origin staging -q
rm -rf "$advance_dir"

# Build recovery script (same as T1)
RECOVERY_SCRIPT2=$(mktemp)
cat > "$RECOVERY_SCRIPT2" <<'ENDSCRIPT'
#!/usr/bin/env bash
set -uo pipefail
cd "$1"
TARGET_BRANCH="$2"
LOG_FILE="$3"
REBASE_CONFLICT_MARKER="$4"
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  if ! git rebase "origin/$TARGET_BRANCH" --quiet 2>/dev/null; then
    git rebase --abort --quiet 2>/dev/null || true
    echo "rebase-failed" >> "$LOG_FILE" 2>/dev/null || true
    printf '%s|recovery|rebase-failed-test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
    exit 1
  fi
  echo "rebased-cleanly" >> "$LOG_FILE" 2>/dev/null || true
  rm -f "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
fi
ENDSCRIPT
chmod +x "$RECOVERY_SCRIPT2"

bash "$RECOVERY_SCRIPT2" "$T2_DIR" "$TARGET_BRANCH" "$test_log2" "$test_marker2"
t2_rc=$?

# Assert: non-zero exit code
if [[ "$t2_rc" -ne 0 ]]; then
  pass "T2: recovery exited non-zero ($t2_rc) on conflict"
else
  fail "T2: recovery exited 0 despite genuine conflict"
fi

# Assert: audit marker exists
if [[ -f "$test_marker2" ]]; then
  pass "T2: .rebase-conflict.audit marker created"
  # Check format
  if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\|recovery\|rebase-failed-' "$test_marker2"; then
    pass "T2: audit marker has correct format"
  else
    fail "T2: audit marker format incorrect (got: $(cat "$test_marker2"))"
  fi
else
  fail "T2: .rebase-conflict.audit marker NOT created"
fi

# Assert: working tree NOT wiped (our staged change should still be present after abort)
if grep -q "failed" "$T2_DIR/.gaai/project/contexts/backlog/active.backlog.yaml" 2>/dev/null; then
  pass "T2: working tree preserved after rebase abort"
else
  fail "T2: working tree was wiped despite rebase abort"
fi

rm -f "$RECOVERY_SCRIPT2"

# ═══════════════════════════════════════════════════════════════════════════════
# T3 — Clean working tree + origin advance → clean rebase, WT unchanged
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: clean WT + origin advance → clean rebase ==="

T3_DIR="$FIXTURE_DIR/t3"
BACKLOG_YAML_T3="stories:
  - id: TEST03
    status: in_progress
    epic: E999"
setup_git_repo "$T3_DIR" "$BACKLOG_YAML_T3"
test_log3="$T3_DIR/test-recovery.log"
test_marker3="$T3_DIR/.rebase-conflict.audit"

# Make a local commit so local diverges from origin (required for git pull --ff-only to fail)
echo "local-prior-work" > "$T3_DIR/.gaai/project/contexts/backlog/prior-commit.txt"
git -C "$T3_DIR" add .
git -C "$T3_DIR" commit -m "local commit that diverges from origin" -q

# Working tree is clean after the commit (no uncommitted edits)
# Advance origin
advance_origin "$T3_DIR"

# Build recovery script (same as T1)
RECOVERY_SCRIPT3=$(mktemp)
cat > "$RECOVERY_SCRIPT3" <<'ENDSCRIPT'
#!/usr/bin/env bash
set -uo pipefail
cd "$1"
TARGET_BRANCH="$2"
LOG_FILE="$3"
REBASE_CONFLICT_MARKER="$4"
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  if ! git rebase "origin/$TARGET_BRANCH" --quiet 2>/dev/null; then
    git rebase --abort --quiet 2>/dev/null || true
    echo "rebase-failed" >> "$LOG_FILE" 2>/dev/null || true
    printf '%s|recovery|rebase-failed-test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
    exit 1
  fi
  echo "rebased-cleanly" >> "$LOG_FILE" 2>/dev/null || true
  rm -f "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
fi
ENDSCRIPT
chmod +x "$RECOVERY_SCRIPT3"

bash "$RECOVERY_SCRIPT3" "$T3_DIR" "$TARGET_BRANCH" "$test_log3" "$test_marker3"
t3_rc=$?

# Assert: exit 0
if [[ "$t3_rc" -eq 0 ]]; then
  pass "T3: recovery exited 0 on clean rebase"
else
  fail "T3: recovery exited $t3_rc (expected 0)"
fi

# Assert: no conflict marker
if [[ ! -f "$test_marker3" ]]; then
  pass "T3: no rebase-conflict marker created"
else
  fail "T3: unexpected rebase-conflict marker created"
fi

# Assert: log shows clean rebase
if grep -q "rebased-cleanly" "$test_log3" 2>/dev/null; then
  pass "T3: log shows clean rebase"
else
  fail "T3: log missing clean rebase message"
fi

# Assert: origin is an ancestor of local HEAD (local commit rebased on top of origin)
if git -C "$T3_DIR" merge-base --is-ancestor "origin/$TARGET_BRANCH" HEAD 2>/dev/null; then
  pass "T3: origin/$TARGET_BRANCH is an ancestor of HEAD after rebase"
else
  fail "T3: origin/$TARGET_BRANCH is NOT an ancestor of HEAD after rebase"
fi

# Assert: working tree clean
if git -C "$T3_DIR" diff --quiet 2>/dev/null && git -C "$T3_DIR" diff --cached --quiet 2>/dev/null; then
  pass "T3: working tree clean after rebase"
else
  fail "T3: working tree dirty after clean rebase"
fi

rm -f "$RECOVERY_SCRIPT3"

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Results: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
