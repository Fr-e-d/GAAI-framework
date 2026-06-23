#!/usr/bin/env bash
# reconcile-own-write.test.sh — AC6 regression for E222S06
#
# Asserts that _commit_accumulated_backlog_drift (the shared helper now used by
# the wrapper-reconcile hook and the recovery-scan drift path) commits and pushes
# accumulated backlog drift instead of writing a drift-marker and bailing.
#
# T1: pending diff, wrapper-reconcile context  → committed+pushed, no drift-marker
# T2: pending diff, recovery-scan context      → committed+pushed, returns 0
# T3: push-race (remote has extra commit)      → rebase+push, committed successfully
# T4: genuine rebase conflict on same lines    → returns 6 (caller writes drift-marker)
#
# Run: bash .gaai/core/scripts/tests/reconcile-own-write.test.sh
# Exit 0 = all pass.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
CHORE_COMMIT_SH="$LIB_DIR/chore-commit.sh"

FIXTURE_DIR="/tmp/gaai-reconcile-own-write-$$"
mkdir -p "$FIXTURE_DIR"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"

# ── Git repo helper ────────────────────────────────────────────────────────────
# Creates a bare remote + local clone with an initial backlog on the staging branch.
setup_git_repo() {
  local project_dir="$1"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  git -C "$project_dir" checkout -b staging -q 2>/dev/null \
    || git -C "$project_dir" checkout staging -q
  local backlog_dir="$project_dir/.gaai/project/contexts/backlog"
  mkdir -p "$backlog_dir"
  cat > "$backlog_dir/active.backlog.yaml" <<'YAML'
items:
- id: E999TEST-01
  status: in_progress
  phase_status: not_started
  delivery_pipeline: 3phase
YAML
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push -u origin staging -q
}

# ── Harness builder ─────────────────────────────────────────────────────────
# Returns a path to a self-contained bash script that sources chore-commit.sh
# and exposes _commit_accumulated_backlog_drift for direct invocation.
build_harness() {
  local harness_file="$1" project_dir="$2" lock_dir="$3"
  local extra_body="${4:-}"
  mkdir -p "$lock_dir"
  cat > "$harness_file" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail

PROJECT_DIR="$project_dir"
BACKLOG_REL="$BACKLOG_REL"
BACKLOG_FILE="\$PROJECT_DIR/\$BACKLOG_REL"
LOCK_DIR="$lock_dir"
TARGET_BRANCH="staging"
SCHEDULER=""

# Source the lib — defines _commit_accumulated_backlog_drift
source "$CHORE_COMMIT_SH"

$extra_body
HARNESS
  chmod +x "$harness_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# T1: wrapper-reconcile context — pending diff → committed+pushed, no drift-marker
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: wrapper-reconcile — pending diff → committed+pushed ==="

T1_SID="E999T1-01"
T1_DIR="$FIXTURE_DIR/t1-project"
T1_LOCK="$FIXTURE_DIR/t1-locks"
T1_MARKER="$T1_LOCK/.drift-detected.audit"

setup_git_repo "$T1_DIR"

# Simulate accumulated daemon-written drift: edit backlog on disk without committing
sed -i.bak 's/phase_status: not_started/phase_status: qa_passed/' \
  "$T1_DIR/$BACKLOG_REL" 2>/dev/null \
  || perl -pi -e 's/phase_status: not_started/phase_status: qa_passed/' \
       "$T1_DIR/$BACKLOG_REL"
rm -f "$T1_DIR/${BACKLOG_REL}.bak" 2>/dev/null || true

T1_HARNESS=$(mktemp "$FIXTURE_DIR/t1-XXXXXX.sh")
build_harness "$T1_HARNESS" "$T1_DIR" "$T1_LOCK" "
_commit_accumulated_backlog_drift '$T1_SID' '$BACKLOG_REL' 'staging' 'wrapper-reconcile'
echo \"EXIT:\$?\"
"

T1_OUT=$(bash "$T1_HARNESS" 2>/dev/null || true)
T1_EXIT=$(printf '%s\n' "$T1_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)

# After the helper runs, remote should have the committed change
T1_REMOTE_PS=$(git -C "$T1_DIR" show "origin/staging:$BACKLOG_REL" 2>/dev/null \
  | grep "phase_status:" | sed 's/.*phase_status: //' | head -1)

if [[ "${T1_EXIT:-}" == "0" ]]; then
  pass "T1: helper returned 0"
else
  fail "T1: expected exit 0, got '${T1_EXIT:-}'"
fi

if git -C "$T1_DIR" diff --quiet HEAD -- "$BACKLOG_REL" 2>/dev/null; then
  pass "T1: local working tree is clean (diff committed)"
else
  fail "T1: working tree still has uncommitted diff"
fi

if [[ "${T1_REMOTE_PS:-}" == "qa_passed" ]]; then
  pass "T1: change landed on origin/staging (AC1)"
else
  fail "T1: change NOT on origin/staging — got phase_status='${T1_REMOTE_PS:-}'"
fi

if [[ ! -f "$T1_MARKER" ]]; then
  pass "T1: no drift-marker written (AC1 — committed instead of bailing)"
else
  fail "T1: drift-marker exists but should not have been written"
fi

rm -f "$T1_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T2: recovery-scan context — pending diff → committed+pushed, returns 0
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: recovery-scan — pending diff → committed+pushed ==="

T2_SID="E999T2-01"
T2_DIR="$FIXTURE_DIR/t2-project"
T2_LOCK="$FIXTURE_DIR/t2-locks"
T2_MARKER="$T2_LOCK/.drift-detected.audit"

setup_git_repo "$T2_DIR"

sed -i.bak 's/phase_status: not_started/phase_status: implemented/' \
  "$T2_DIR/$BACKLOG_REL" 2>/dev/null \
  || perl -pi -e 's/phase_status: not_started/phase_status: implemented/' \
       "$T2_DIR/$BACKLOG_REL"
rm -f "$T2_DIR/${BACKLOG_REL}.bak" 2>/dev/null || true

T2_HARNESS=$(mktemp "$FIXTURE_DIR/t2-XXXXXX.sh")
build_harness "$T2_HARNESS" "$T2_DIR" "$T2_LOCK" "
_commit_accumulated_backlog_drift '$T2_SID' '$BACKLOG_REL' 'staging' 'recovery-scan'
echo \"EXIT:\$?\"
"

T2_OUT=$(bash "$T2_HARNESS" 2>/dev/null || true)
T2_EXIT=$(printf '%s\n' "$T2_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)

T2_REMOTE_PS=$(git -C "$T2_DIR" show "origin/staging:$BACKLOG_REL" 2>/dev/null \
  | grep "phase_status:" | sed 's/.*phase_status: //' | head -1)

if [[ "${T2_EXIT:-}" == "0" ]]; then
  pass "T2: helper returned 0"
else
  fail "T2: expected exit 0, got '${T2_EXIT:-}'"
fi

if git -C "$T2_DIR" diff --quiet HEAD -- "$BACKLOG_REL" 2>/dev/null; then
  pass "T2: local working tree clean (AC2)"
else
  fail "T2: working tree still has uncommitted diff"
fi

if [[ "${T2_REMOTE_PS:-}" == "implemented" ]]; then
  pass "T2: change landed on origin/staging (AC2)"
else
  fail "T2: change NOT on origin/staging — got '${T2_REMOTE_PS:-}'"
fi

if [[ ! -f "$T2_MARKER" ]]; then
  pass "T2: no drift-marker written (AC2)"
else
  fail "T2: drift-marker exists but should not have been written"
fi

rm -f "$T2_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T3: push-race — remote has extra commit, rebase+retry lands the drift
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: push-race — remote has extra commit → rebase+push → committed ==="

T3_SID="E999T3-01"
T3_DIR="$FIXTURE_DIR/t3-project"
T3_LOCK="$FIXTURE_DIR/t3-locks"

setup_git_repo "$T3_DIR"

# Add an extra commit directly on the remote (simulating another wrapper pushing)
T3_REMOTE="${T3_DIR}_remote.git"
T3_TMP_CLONE="$FIXTURE_DIR/t3-tmp-clone"
git clone "$T3_REMOTE" "$T3_TMP_CLONE" -q
git -C "$T3_TMP_CLONE" config user.email "test@gaai.local"
git -C "$T3_TMP_CLONE" config user.name "GAAI Test"
git -C "$T3_TMP_CLONE" checkout staging -q
echo "# extra" >> "$T3_TMP_CLONE/extra.txt"
git -C "$T3_TMP_CLONE" add extra.txt
git -C "$T3_TMP_CLONE" commit -q -m "chore: remote-only commit (simulates push-race)"
git -C "$T3_TMP_CLONE" push -q origin staging
rm -rf "$T3_TMP_CLONE"

# Now T3_DIR is behind origin/staging. Simulate pending drift on the backlog.
sed -i.bak 's/phase_status: not_started/phase_status: qa_passed/' \
  "$T3_DIR/$BACKLOG_REL" 2>/dev/null \
  || perl -pi -e 's/phase_status: not_started/phase_status: qa_passed/' \
       "$T3_DIR/$BACKLOG_REL"
rm -f "$T3_DIR/${BACKLOG_REL}.bak" 2>/dev/null || true

T3_HARNESS=$(mktemp "$FIXTURE_DIR/t3-XXXXXX.sh")
build_harness "$T3_HARNESS" "$T3_DIR" "$T3_LOCK" "
_commit_accumulated_backlog_drift '$T3_SID' '$BACKLOG_REL' 'staging' 'wrapper-reconcile'
echo \"EXIT:\$?\"
"

T3_OUT=$(bash "$T3_HARNESS" 2>/dev/null || true)
T3_EXIT=$(printf '%s\n' "$T3_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)

T3_REMOTE_PS=$(git -C "$T3_DIR" show "origin/staging:$BACKLOG_REL" 2>/dev/null \
  | grep "phase_status:" | sed 's/.*phase_status: //' | head -1)

if [[ "${T3_EXIT:-}" == "0" ]]; then
  pass "T3: push-race handled — helper returned 0 (AC5: push-race self-heal preserved)"
else
  fail "T3: expected exit 0 after push-race, got '${T3_EXIT:-}'"
fi

if [[ "${T3_REMOTE_PS:-}" == "qa_passed" ]]; then
  pass "T3: change landed on origin/staging despite push-race"
else
  fail "T3: change NOT on origin/staging after push-race — got '${T3_REMOTE_PS:-}'"
fi

rm -f "$T3_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T4: genuine rebase conflict → helper returns 6, fallback preserved
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: genuine rebase conflict → returns 6 (drift-marker preserved) ==="

T4_SID="E999T4-01"
T4_DIR="$FIXTURE_DIR/t4-project"
T4_LOCK="$FIXTURE_DIR/t4-locks"
T4_MARKER="$T4_LOCK/.drift-detected.audit"

setup_git_repo "$T4_DIR"

# Create a conflicting commit on origin/staging that edits the SAME LINE as the
# pending local diff. When the helper tries: commit local→push fails→fetch→rebase,
# the rebase hits a conflict because both sides modified phase_status.
T4_REMOTE="${T4_DIR}_remote.git"
T4_TMP_CLONE="$FIXTURE_DIR/t4-tmp-clone"
git clone "$T4_REMOTE" "$T4_TMP_CLONE" -q
git -C "$T4_TMP_CLONE" config user.email "test@gaai.local"
git -C "$T4_TMP_CLONE" config user.name "GAAI Test"
git -C "$T4_TMP_CLONE" checkout staging -q

# Remote: change phase_status to "done" (different value on same line)
sed -i.bak 's/phase_status: not_started/phase_status: done/' \
  "$T4_TMP_CLONE/$BACKLOG_REL" 2>/dev/null \
  || perl -pi -e 's/phase_status: not_started/phase_status: done/' \
       "$T4_TMP_CLONE/$BACKLOG_REL"
rm -f "$T4_TMP_CLONE/${BACKLOG_REL}.bak" 2>/dev/null || true
git -C "$T4_TMP_CLONE" add "$BACKLOG_REL"
git -C "$T4_TMP_CLONE" commit -q -m "chore: remote conflicting phase_status change"
git -C "$T4_TMP_CLONE" push -q origin staging
rm -rf "$T4_TMP_CLONE"

# Local: change phase_status to a DIFFERENT value on the same line (diverged from origin)
sed -i.bak 's/phase_status: not_started/phase_status: qa_passed/' \
  "$T4_DIR/$BACKLOG_REL" 2>/dev/null \
  || perl -pi -e 's/phase_status: not_started/phase_status: qa_passed/' \
       "$T4_DIR/$BACKLOG_REL"
rm -f "$T4_DIR/${BACKLOG_REL}.bak" 2>/dev/null || true

# Write a pre-existing drift-marker to confirm it is not cleared on failure
mkdir -p "$T4_LOCK"
printf 'pre-existing\n' > "$T4_MARKER"

T4_HARNESS=$(mktemp "$FIXTURE_DIR/t4-XXXXXX.sh")
build_harness "$T4_HARNESS" "$T4_DIR" "$T4_LOCK" "
_commit_accumulated_backlog_drift '$T4_SID' '$BACKLOG_REL' 'staging' 'wrapper-reconcile'
echo \"EXIT:\$?\"
"

# Disable git conflict resolution helpers that might auto-resolve
T4_OUT=$(GIT_MERGE_AUTOEDIT=no bash "$T4_HARNESS" 2>/dev/null || true)
T4_EXIT=$(printf '%s\n' "$T4_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)

if [[ "${T4_EXIT:-}" == "6" ]]; then
  pass "T4: helper returned 6 on genuine conflict (AC3/AC5: fallback preserved)"
else
  fail "T4: expected exit 6 on genuine conflict, got '${T4_EXIT:-}'"
fi

# Verify working tree is clean after abort (no leftover partial state)
if git -C "$T4_DIR" diff --cached --quiet 2>/dev/null; then
  pass "T4: no staged changes left after conflict abort (clean fallback)"
else
  fail "T4: staged changes remain after conflict abort — unclean state"
fi

# The drift-marker should still be present (caller responsibility to write it)
# Here we verify the helper did NOT silently clear the pre-existing marker
if [[ -f "$T4_MARKER" ]]; then
  pass "T4: drift-marker present — caller can still write it (AC3)"
else
  fail "T4: drift-marker was unexpectedly removed"
fi

rm -f "$T4_HARNESS"

# ═══════════════════════════════════════════════════════════════════════════════
# T5: clean working tree → no-op, returns 0 (AC5)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: clean working tree → no-op, returns 0 (AC5) ==="

T5_SID="E999T5-01"
T5_DIR="$FIXTURE_DIR/t5-project"
T5_LOCK="$FIXTURE_DIR/t5-locks"

setup_git_repo "$T5_DIR"
# No local edits — working tree is clean

T5_HARNESS=$(mktemp "$FIXTURE_DIR/t5-XXXXXX.sh")
build_harness "$T5_HARNESS" "$T5_DIR" "$T5_LOCK" "
_commit_accumulated_backlog_drift '$T5_SID' '$BACKLOG_REL' 'staging' 'pre-mark'
echo \"EXIT:\$?\"
"

T5_OUT=$(bash "$T5_HARNESS" 2>/dev/null || true)
T5_EXIT=$(printf '%s\n' "$T5_OUT" | grep "^EXIT:" | sed 's/EXIT://' | head -1)

# Remote should not have gained any new commit
T5_INITIAL_SHA=$(git -C "$T5_DIR" rev-parse "origin/staging" 2>/dev/null || echo "")
T5_OUT2=$(bash "$T5_HARNESS" 2>/dev/null || true)  # run again to capture post-state
T5_POST_SHA=$(git -C "$T5_DIR" rev-parse "origin/staging" 2>/dev/null || echo "")

if [[ "${T5_EXIT:-}" == "0" ]]; then
  pass "T5: no-op on clean tree returns 0 (AC5)"
else
  fail "T5: expected exit 0 on clean tree, got '${T5_EXIT:-}'"
fi

if [[ "$T5_INITIAL_SHA" == "$T5_POST_SHA" ]]; then
  pass "T5: origin/staging unchanged (no spurious commit on clean tree)"
else
  fail "T5: origin/staging changed even though working tree was clean"
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
