#!/usr/bin/env bash
# home-branch-guard.test.sh — regression tests for _gaai_home_branch_guard() (AC6, E222S05)
#
# Covers:
#   TC1: on-target + clean → rc=0 (no-op, branch unchanged, no stash)
#   TC2: clean drift to non-target branch → rc=2 (auto-restored to target, no stash)
#   TC3: dirty/foreign drift → rc=1 (paused; branch NOT switched, work preserved, no stash)
#
# Usage: bash .gaai/core/scripts/tests/home-branch-guard.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD_LIB="$SCRIPT_DIR/../lib/home-branch-guard.sh"

if [[ ! -f "$GUARD_LIB" ]]; then
  echo "ERROR: guard lib not found at $GUARD_LIB"
  exit 1
fi

# Source the lib under test
# shellcheck source=../lib/home-branch-guard.sh
source "$GUARD_LIB"

FIXTURE_DIR="/tmp/gaai-home-branch-guard-test-$$"
mkdir -p "$FIXTURE_DIR"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# Sets up a bare remote + local clone with an initial commit on 'staging'.
setup_git_repo() {
  local project_dir="$1"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  git -C "$project_dir" checkout -b staging -q
  touch "$project_dir/.keep"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push origin staging -q
}

# ═══════════════════════════════════════════════════════════════════════════════
# TC1: on-target + clean → rc=0 (no-op)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC1: on-target + clean → rc=0 (no-op) ==="

TC1_DIR="$FIXTURE_DIR/tc1-project"
setup_git_repo "$TC1_DIR"

TC1_RC=0
_gaai_home_branch_guard "$TC1_DIR" "staging" || TC1_RC=$?

if [[ "$TC1_RC" -eq 0 ]]; then
  pass "TC1-1: rc=0 on on-target clean working tree"
else
  fail "TC1-1: expected rc=0, got rc=$TC1_RC"
fi

TC1_BRANCH="$(git -C "$TC1_DIR" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC1_BRANCH" == "staging" ]]; then
  pass "TC1-2: branch unchanged ('staging')"
else
  fail "TC1-2: branch changed to '$TC1_BRANCH' (expected 'staging')"
fi

TC1_STASH="$(git -C "$TC1_DIR" stash list 2>/dev/null || echo "")"
if [[ -z "$TC1_STASH" ]]; then
  pass "TC1-3: no stash entries created"
else
  fail "TC1-3: unexpected stash entries: $TC1_STASH"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC2: clean drift → rc=2 (auto-restored to target, no stash)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC2: clean drift → rc=2 (auto-restored, no stash) ==="

TC2_DIR="$FIXTURE_DIR/tc2-project"
setup_git_repo "$TC2_DIR"

# Drift to a different branch with a clean working tree
git -C "$TC2_DIR" checkout -b other-branch -q

TC2_BRANCH_BEFORE="$(git -C "$TC2_DIR" branch --show-current 2>/dev/null || echo "")"

TC2_RC=0
_gaai_home_branch_guard "$TC2_DIR" "staging" || TC2_RC=$?

if [[ "$TC2_RC" -eq 2 ]]; then
  pass "TC2-1: rc=2 on clean drift (branch_before=$TC2_BRANCH_BEFORE)"
else
  fail "TC2-1: expected rc=2, got rc=$TC2_RC (branch_before=$TC2_BRANCH_BEFORE)"
fi

TC2_BRANCH_AFTER="$(git -C "$TC2_DIR" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC2_BRANCH_AFTER" == "staging" ]]; then
  pass "TC2-2: branch auto-restored to 'staging'"
else
  fail "TC2-2: branch is '$TC2_BRANCH_AFTER' after auto-restore (expected 'staging')"
fi

TC2_STASH="$(git -C "$TC2_DIR" stash list 2>/dev/null || echo "")"
if [[ -z "$TC2_STASH" ]]; then
  pass "TC2-3: no stash entries created"
else
  fail "TC2-3: unexpected stash entries: $TC2_STASH"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC3: dirty/foreign drift → rc=1 (paused; branch NOT switched, work preserved, no stash)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC3: dirty/foreign drift → rc=1 (no switch, no clobber, no stash) ==="

TC3_DIR="$FIXTURE_DIR/tc3-project"
setup_git_repo "$TC3_DIR"

# Drift to another branch AND stage a new file (dirty working tree)
git -C "$TC3_DIR" checkout -b other-branch -q
printf "uncommitted-work\n" > "$TC3_DIR/dirty.txt"
git -C "$TC3_DIR" add dirty.txt

TC3_RC=0
_gaai_home_branch_guard "$TC3_DIR" "staging" || TC3_RC=$?

if [[ "$TC3_RC" -eq 1 ]]; then
  pass "TC3-1: rc=1 on dirty/foreign drift"
else
  fail "TC3-1: expected rc=1, got rc=$TC3_RC"
fi

TC3_BRANCH_AFTER="$(git -C "$TC3_DIR" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC3_BRANCH_AFTER" == "other-branch" ]]; then
  pass "TC3-2: branch NOT switched (still 'other-branch')"
else
  fail "TC3-2: branch changed to '$TC3_BRANCH_AFTER' (expected 'other-branch')"
fi

TC3_FILE_STATUS="$(git -C "$TC3_DIR" status --porcelain 2>/dev/null || echo "")"
if echo "$TC3_FILE_STATUS" | grep -q "dirty.txt"; then
  pass "TC3-3: uncommitted file still present in working tree"
else
  fail "TC3-3: uncommitted file was clobbered or lost — status: $TC3_FILE_STATUS"
fi

TC3_STASH="$(git -C "$TC3_DIR" stash list 2>/dev/null || echo "")"
if [[ -z "$TC3_STASH" ]]; then
  pass "TC3-4: no stash entries created (no auto-stash)"
else
  fail "TC3-4: unexpected stash entries (auto-stash must NOT happen): $TC3_STASH"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "══════════════════════════════════════════════════"

exit "$FAIL_COUNT"
