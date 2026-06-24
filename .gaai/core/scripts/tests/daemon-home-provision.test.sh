#!/usr/bin/env bash
# daemon-home-provision.test.sh — regression tests for _gaai_provision_daemon_home()
#
# Covers:
#   TC1: first run creates home worktree on gaai-daemon-home branch at origin/staging tip
#   TC2: second run is idempotent (no duplicate registration, home still valid)
#   TC3a: stale home (dirty working tree) is repaired to clean gaai-daemon-home tip
#   TC3b: plain non-worktree directory at home path is repaired to registered worktree
#   TC4: provisioning succeeds while main checkout is on <target> (named branch avoids conflict)
#
# Usage: bash .gaai/core/scripts/tests/daemon-home-provision.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_HOME_LIB="$SCRIPT_DIR/../lib/daemon-home.sh"

if [[ ! -f "$DAEMON_HOME_LIB" ]]; then
  echo "ERROR: daemon-home lib not found at $DAEMON_HOME_LIB"
  exit 1
fi

# Source the lib under test
# shellcheck source=../lib/daemon-home.sh
source "$DAEMON_HOME_LIB"

# Resolve to physical path upfront — git canonicalises worktree paths via realpath()
# so /tmp (macOS symlink → /private/tmp) would cause grep mismatches otherwise.
_FIXTURE_RAW="/tmp/gaai-daemon-home-provision-test-$$"
mkdir -p "$_FIXTURE_RAW"
FIXTURE_DIR="$(cd "$_FIXTURE_RAW" && pwd -P 2>/dev/null || echo "$_FIXTURE_RAW")"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# Sets up a bare remote + local clone with an initial commit on 'staging'.
# The clone's main checkout is left on 'staging' (mirroring real operator setup).
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
# TC1: first run creates home on gaai-daemon-home branch at origin/staging tip
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC1: first run creates home on gaai-daemon-home branch at origin/staging tip ==="

TC1_DIR="$FIXTURE_DIR/tc1-project"
TC1_HOME="$FIXTURE_DIR/tc1-home"
setup_git_repo "$TC1_DIR"

TC1_RC=0
_gaai_provision_daemon_home "$TC1_HOME" "staging" "$TC1_DIR" || TC1_RC=$?

if [[ "$TC1_RC" -eq 0 ]]; then
  pass "TC1-1: rc=0 on first provisioning"
else
  fail "TC1-1: expected rc=0, got rc=$TC1_RC"
fi

if [[ -d "$TC1_HOME" ]]; then
  pass "TC1-2: home directory exists"
else
  fail "TC1-2: home directory not created"
fi

TC1_HOME_REAL="$(cd "$TC1_HOME" && pwd -P 2>/dev/null || echo "$TC1_HOME")"
if git -C "$TC1_DIR" worktree list --porcelain 2>/dev/null | grep -qF "worktree $TC1_HOME_REAL"; then
  pass "TC1-3: home is a registered worktree"
else
  fail "TC1-3: home is not registered in git worktree list"
fi

TC1_CURRENT_BRANCH="$(git -C "$TC1_HOME" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC1_CURRENT_BRANCH" == "gaai-daemon-home" ]]; then
  pass "TC1-4: home HEAD is on 'gaai-daemon-home' branch"
else
  fail "TC1-4: home HEAD is on '${TC1_CURRENT_BRANCH:-<detached>}' (expected gaai-daemon-home)"
fi

TC1_ORIGIN_TIP="$(git -C "$TC1_DIR" rev-parse "origin/staging" 2>/dev/null || echo "?")"
TC1_HOME_HEAD="$(git -C "$TC1_HOME" rev-parse HEAD 2>/dev/null || echo "!")"
if [[ "$TC1_HOME_HEAD" == "$TC1_ORIGIN_TIP" ]]; then
  pass "TC1-5: home HEAD == origin/staging tip ($TC1_HOME_HEAD)"
else
  fail "TC1-5: home HEAD ($TC1_HOME_HEAD) != origin/staging tip ($TC1_ORIGIN_TIP)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC2: second run is idempotent (no duplicate registration, home still valid)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC2: second run is idempotent ==="

TC2_DIR="$FIXTURE_DIR/tc2-project"
TC2_HOME="$FIXTURE_DIR/tc2-home"
setup_git_repo "$TC2_DIR"

# First provisioning
_gaai_provision_daemon_home "$TC2_HOME" "staging" "$TC2_DIR" >/dev/null 2>&1

TC2_COUNT_BEFORE="$(git -C "$TC2_DIR" worktree list 2>/dev/null | wc -l | tr -d ' ')"

TC2_RC=0
_gaai_provision_daemon_home "$TC2_HOME" "staging" "$TC2_DIR" || TC2_RC=$?

if [[ "$TC2_RC" -eq 0 ]]; then
  pass "TC2-1: rc=0 on second provisioning (idempotent)"
else
  fail "TC2-1: expected rc=0 on second run, got rc=$TC2_RC"
fi

TC2_COUNT_AFTER="$(git -C "$TC2_DIR" worktree list 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$TC2_COUNT_AFTER" -eq "$TC2_COUNT_BEFORE" ]]; then
  pass "TC2-2: no duplicate worktree registration (count unchanged: $TC2_COUNT_AFTER)"
else
  fail "TC2-2: worktree count changed from $TC2_COUNT_BEFORE to $TC2_COUNT_AFTER (duplicate?)"
fi

TC2_STATUS="$(git -C "$TC2_HOME" status --porcelain 2>/dev/null || echo "ERROR")"
if [[ -z "$TC2_STATUS" ]]; then
  pass "TC2-3: home working tree is clean after idempotent run"
else
  fail "TC2-3: home has unexpected changes: $TC2_STATUS"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC3a: stale home (dirty working tree) is repaired to clean detached tip
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC3a: stale home (dirty working tree) is repaired ==="

TC3A_DIR="$FIXTURE_DIR/tc3a-project"
TC3A_HOME="$FIXTURE_DIR/tc3a-home"
setup_git_repo "$TC3A_DIR"

# First provisioning (create clean home)
_gaai_provision_daemon_home "$TC3A_HOME" "staging" "$TC3A_DIR" >/dev/null 2>&1

# Dirty the home
touch "$TC3A_HOME/dirty.txt"
git -C "$TC3A_HOME" add dirty.txt

TC3A_STATUS_BEFORE="$(git -C "$TC3A_HOME" status --porcelain 2>/dev/null || echo "")"

TC3A_RC=0
_gaai_provision_daemon_home "$TC3A_HOME" "staging" "$TC3A_DIR" || TC3A_RC=$?

if [[ "$TC3A_RC" -eq 0 ]]; then
  pass "TC3a-1: rc=0 — stale/dirty home repaired"
else
  fail "TC3a-1: expected rc=0, got rc=$TC3A_RC (status_before=$TC3A_STATUS_BEFORE)"
fi

TC3A_STATUS_AFTER="$(git -C "$TC3A_HOME" status --porcelain 2>/dev/null || echo "ERROR")"
if [[ -z "$TC3A_STATUS_AFTER" ]]; then
  pass "TC3a-2: home working tree is clean after repair"
else
  fail "TC3a-2: home still has changes after repair: $TC3A_STATUS_AFTER"
fi

TC3A_ORIGIN_TIP="$(git -C "$TC3A_DIR" rev-parse "origin/staging" 2>/dev/null || echo "?")"
TC3A_HOME_HEAD="$(git -C "$TC3A_HOME" rev-parse HEAD 2>/dev/null || echo "!")"
if [[ "$TC3A_HOME_HEAD" == "$TC3A_ORIGIN_TIP" ]]; then
  pass "TC3a-3: home HEAD == origin/staging tip after repair"
else
  fail "TC3a-3: home HEAD ($TC3A_HOME_HEAD) != origin/staging tip ($TC3A_ORIGIN_TIP)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC3b: plain non-worktree directory at home path is repaired
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC3b: plain non-worktree directory at home path is repaired ==="

TC3B_DIR="$FIXTURE_DIR/tc3b-project"
TC3B_HOME="$FIXTURE_DIR/tc3b-home"
setup_git_repo "$TC3B_DIR"

# Place a plain (non-worktree) directory at the home path
mkdir -p "$TC3B_HOME"
touch "$TC3B_HOME/foreign.txt"

TC3B_RC=0
_gaai_provision_daemon_home "$TC3B_HOME" "staging" "$TC3B_DIR" || TC3B_RC=$?

if [[ "$TC3B_RC" -eq 0 ]]; then
  pass "TC3b-1: rc=0 — plain directory repaired to worktree"
else
  fail "TC3b-1: expected rc=0, got rc=$TC3B_RC"
fi

TC3B_HOME_REAL="$(cd "$TC3B_HOME" && pwd -P 2>/dev/null || echo "$TC3B_HOME")"
if git -C "$TC3B_DIR" worktree list --porcelain 2>/dev/null | grep -qF "worktree $TC3B_HOME_REAL"; then
  pass "TC3b-2: home is now a registered worktree (not just a plain dir)"
else
  fail "TC3b-2: home is not a registered worktree after repair"
fi

TC3B_ORIGIN_TIP="$(git -C "$TC3B_DIR" rev-parse "origin/staging" 2>/dev/null || echo "?")"
TC3B_HOME_HEAD="$(git -C "$TC3B_HOME" rev-parse HEAD 2>/dev/null || echo "!")"
if [[ "$TC3B_HOME_HEAD" == "$TC3B_ORIGIN_TIP" ]]; then
  pass "TC3b-3: home HEAD == origin/staging tip"
else
  fail "TC3b-3: home HEAD ($TC3B_HOME_HEAD) != origin/staging tip ($TC3B_ORIGIN_TIP)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC4: provisioning succeeds while main checkout is on <target> (named branch avoids conflict)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC4: main checkout on 'staging' — named branch avoids conflict ==="

TC4_DIR="$FIXTURE_DIR/tc4-project"
TC4_HOME="$FIXTURE_DIR/tc4-home"
setup_git_repo "$TC4_DIR"

# Verify main is on staging (setup_git_repo leaves it there)
TC4_MAIN_BRANCH_BEFORE="$(git -C "$TC4_DIR" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC4_MAIN_BRANCH_BEFORE" == "staging" ]]; then
  pass "TC4-0: precondition — main checkout is on 'staging'"
else
  fail "TC4-0: precondition failed — main is on '$TC4_MAIN_BRANCH_BEFORE', not 'staging'"
fi

TC4_RC=0
_gaai_provision_daemon_home "$TC4_HOME" "staging" "$TC4_DIR" || TC4_RC=$?

if [[ "$TC4_RC" -eq 0 ]]; then
  pass "TC4-1: rc=0 — provisioning succeeded despite main checkout on 'staging'"
else
  fail "TC4-1: expected rc=0, got rc=$TC4_RC (gaai-daemon-home branch add should not conflict)"
fi

TC4_MAIN_BRANCH_AFTER="$(git -C "$TC4_DIR" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC4_MAIN_BRANCH_AFTER" == "staging" ]]; then
  pass "TC4-2: main checkout still on 'staging' (unchanged)"
else
  fail "TC4-2: main checkout moved to '$TC4_MAIN_BRANCH_AFTER' (unexpected)"
fi

TC4_HOME_BRANCH="$(git -C "$TC4_HOME" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC4_HOME_BRANCH" == "gaai-daemon-home" ]]; then
  pass "TC4-3: home HEAD is on 'gaai-daemon-home' branch"
else
  fail "TC4-3: home HEAD is on '${TC4_HOME_BRANCH:-<detached>}' (expected gaai-daemon-home)"
fi

TC4_ORIGIN_TIP="$(git -C "$TC4_DIR" rev-parse "origin/staging" 2>/dev/null || echo "?")"
TC4_HOME_HEAD="$(git -C "$TC4_HOME" rev-parse HEAD 2>/dev/null || echo "!")"
if [[ "$TC4_HOME_HEAD" == "$TC4_ORIGIN_TIP" ]]; then
  pass "TC4-4: home HEAD == origin/staging tip"
else
  fail "TC4-4: home HEAD ($TC4_HOME_HEAD) != origin/staging tip ($TC4_ORIGIN_TIP)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "══════════════════════════════════════════════════"

exit "$FAIL_COUNT"
