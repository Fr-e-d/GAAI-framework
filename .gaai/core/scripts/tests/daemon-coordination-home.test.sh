#!/usr/bin/env bash
# daemon-coordination-home.test.sh — AC6 sandbox tests for E1003S03
#
# Covers:
#   TC1: coordination push from gaai-daemon-home lands on origin/staging (AC6a)
#   TC2: dirty / branch-switched main checkout is INERT to daemon (AC6b — DEC-162 proof)
#   TC3: completeness backstop — zero coordination push sites lack HEAD: refspec (AC6c)
#   TC4: home is on gaai-daemon-home; main checkout's staging ref never modified (AC6d)
#
# Usage: bash .gaai/core/scripts/tests/daemon-coordination-home.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
DAEMON_HOME_LIB="$SCRIPTS_DIR/lib/daemon-home.sh"

if [[ ! -f "$DAEMON_HOME_LIB" ]]; then
  echo "ERROR: daemon-home lib not found at $DAEMON_HOME_LIB"
  exit 1
fi

# Source the provisioner under test
# shellcheck source=../lib/daemon-home.sh
source "$DAEMON_HOME_LIB"

# Resolve to physical path — git canonicalises worktree paths via realpath()
# so /tmp (macOS symlink → /private/tmp) would cause grep mismatches.
_FIXTURE_RAW="/tmp/gaai-coord-home-test-$$"
mkdir -p "$_FIXTURE_RAW"
FIXTURE_DIR="$(cd "$_FIXTURE_RAW" && pwd -P 2>/dev/null || echo "$_FIXTURE_RAW")"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# Sets up a bare remote + local clone with one commit on 'staging'.
# Clone's main checkout is left on 'staging'.
# The bare remote is at "${project_dir}_remote.git"; the clone's origin points there.
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
# TC1: coordination push from gaai-daemon-home lands on origin/staging (AC6a)
# ═══════════════════════════════════════════════════════════════════════════════
# Structure: bare_remote ← origin ← main checkout (TC1_DIR) ← worktree (TC1_HOME)
# Push from home uses "push origin HEAD:staging" (same refspec as post-flip daemon).
# Verifies the bare remote's staging tip == home HEAD.
echo ""
echo "=== TC1: coordination push from gaai-daemon-home lands on origin/staging ==="

TC1_DIR="$FIXTURE_DIR/tc1-project"
TC1_HOME="$FIXTURE_DIR/tc1-home"
TC1_BARE="${TC1_DIR}_remote.git"
setup_git_repo "$TC1_DIR"

_gaai_provision_daemon_home "$TC1_HOME" "staging" "$TC1_DIR" >/dev/null 2>&1

# Make a coordination commit in the home (mirroring daemon chore-commit)
touch "$TC1_HOME/coord.txt"
git -C "$TC1_HOME" add coord.txt
git -C "$TC1_HOME" config user.email "test@gaai.local"
git -C "$TC1_HOME" config user.name "GAAI Test"
git -C "$TC1_HOME" commit -m "coord-commit-from-home" -q

TC1_HOME_HEAD="$(git -C "$TC1_HOME" rev-parse HEAD 2>/dev/null || echo "?")"

# Push via origin with explicit HEAD:staging refspec — the post-flip coordination pattern.
# The home is on gaai-daemon-home; "HEAD:staging" pushes HEAD to origin's staging ref.
TC1_PUSH_RC=0
git -C "$TC1_HOME" push origin "HEAD:staging" --quiet 2>/dev/null || TC1_PUSH_RC=$?

if [[ "$TC1_PUSH_RC" -eq 0 ]]; then
  pass "TC1-1: push from home with HEAD:staging refspec succeeded (rc=0)"
else
  fail "TC1-1: push from home with HEAD:staging failed (rc=$TC1_PUSH_RC)"
fi

# Verify bare remote's staging tip == home HEAD (push went to origin/staging correctly)
TC1_BARE_TIP="$(git -C "$TC1_BARE" rev-parse "staging" 2>/dev/null || echo "!")"
if [[ "$TC1_BARE_TIP" == "$TC1_HOME_HEAD" ]]; then
  pass "TC1-2: bare remote's staging tip == home HEAD after push ($TC1_HOME_HEAD)"
else
  fail "TC1-2: bare remote staging ($TC1_BARE_TIP) != home HEAD ($TC1_HOME_HEAD)"
fi

TC1_BRANCH_AFTER="$(git -C "$TC1_HOME" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC1_BRANCH_AFTER" == "gaai-daemon-home" ]]; then
  pass "TC1-3: home remains on gaai-daemon-home after push"
else
  fail "TC1-3: home is on '${TC1_BRANCH_AFTER:-<detached>}' after push (expected gaai-daemon-home)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC2: dirty / branch-switched main checkout is INERT (AC6b — DEC-162 proof)
# ═══════════════════════════════════════════════════════════════════════════════
# The daemon's home is a separate worktree sharing the same .git as the main checkout.
# When the home pushes to "origin HEAD:staging", it goes to the bare remote.
# The main checkout's LOCAL staging branch ref (refs/heads/staging) must NOT advance —
# only refs/remotes/origin/staging is updated by the push (tracking branch auto-update).
echo ""
echo "=== TC2: dirty / branch-switched main checkout is INERT to daemon coordination ==="

TC2_DIR="$FIXTURE_DIR/tc2-project"
TC2_HOME="$FIXTURE_DIR/tc2-home"
TC2_BARE="${TC2_DIR}_remote.git"
setup_git_repo "$TC2_DIR"

_gaai_provision_daemon_home "$TC2_HOME" "staging" "$TC2_DIR" >/dev/null 2>&1

# Record main checkout's LOCAL staging branch SHA before daemon coordination.
# This is refs/heads/staging in the shared .git, NOT refs/remotes/origin/staging.
TC2_LOCAL_STAGING_BEFORE="$(git -C "$TC2_DIR" rev-parse "staging" 2>/dev/null || echo "?")"

# Dirty the main checkout: checkout a new branch + leave uncommitted changes
git -C "$TC2_DIR" checkout -b "feature/dirty-interference" -q 2>/dev/null
echo "dirty" > "$TC2_DIR/dirty.txt"

# Make a coordination commit from the home and push to origin with HEAD:staging
touch "$TC2_HOME/daemon-op.txt"
git -C "$TC2_HOME" add daemon-op.txt
git -C "$TC2_HOME" config user.email "test@gaai.local"
git -C "$TC2_HOME" config user.name "GAAI Test"
git -C "$TC2_HOME" commit -m "chore(daemon): mark in_progress [from-home]" -q

TC2_HOME_HEAD="$(git -C "$TC2_HOME" rev-parse HEAD 2>/dev/null || echo "?")"

TC2_PUSH_RC=0
git -C "$TC2_HOME" push origin "HEAD:staging" --quiet 2>/dev/null || TC2_PUSH_RC=$?

if [[ "$TC2_PUSH_RC" -eq 0 ]]; then
  pass "TC2-1: coordination push succeeded despite dirty main checkout (rc=0)"
else
  fail "TC2-1: coordination push failed (rc=$TC2_PUSH_RC) — dirty main checkout interfered"
fi

TC2_MAIN_BRANCH_AFTER="$(git -C "$TC2_DIR" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC2_MAIN_BRANCH_AFTER" == "feature/dirty-interference" ]]; then
  pass "TC2-2: main checkout remains on 'feature/dirty-interference' (daemon did not touch it)"
else
  fail "TC2-2: main checkout moved to '$TC2_MAIN_BRANCH_AFTER' (daemon interfered)"
fi

# Local staging ref (refs/heads/staging) must be unchanged — push went to origin (bare),
# not to the main checkout's local branch.
TC2_LOCAL_STAGING_AFTER="$(git -C "$TC2_DIR" rev-parse "staging" 2>/dev/null || echo "?")"
if [[ "$TC2_LOCAL_STAGING_AFTER" == "$TC2_LOCAL_STAGING_BEFORE" ]]; then
  pass "TC2-3: main checkout's local staging ref unchanged (daemon coordination stayed in home)"
else
  fail "TC2-3: main checkout's local staging moved from $TC2_LOCAL_STAGING_BEFORE to $TC2_LOCAL_STAGING_AFTER (unexpected)"
fi

# Bare remote's staging must advance to home's commit
TC2_BARE_TIP="$(git -C "$TC2_BARE" rev-parse "staging" 2>/dev/null || echo "!")"
if [[ "$TC2_BARE_TIP" == "$TC2_HOME_HEAD" ]]; then
  pass "TC2-4: bare remote's staging advanced to home's commit ($TC2_HOME_HEAD)"
else
  fail "TC2-4: bare remote staging ($TC2_BARE_TIP) != home commit ($TC2_HOME_HEAD)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC3: completeness backstop — zero coordination push sites lack HEAD: refspec (AC6c)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC3: completeness backstop — zero coordination pushes lack HEAD: refspec ==="

TC3_PASS=1

for _script in \
    "$SCRIPTS_DIR/delivery-daemon.sh" \
    "$SCRIPTS_DIR/lib/chore-commit.sh" \
    "$SCRIPTS_DIR/daemon-dispatch.sh"; do

  if [[ ! -f "$_script" ]]; then
    fail "TC3: script not found at $_script"
    TC3_PASS=0
    continue
  fi

  # Grep for coordination push patterns without HEAD: prefix.
  # Excludes: story-branch pushes (story/), already-correct HEAD: refspecs, comment lines.
  _missing=$(grep -nE 'git push origin[[:space:]]+"?\$\{?(TARGET_BRANCH|target_branch)' "$_script" \
    | grep -v 'HEAD:' \
    | grep -v 'story/' \
    | grep -v '^[[:space:]]*#' || true)

  if [[ -z "$_missing" ]]; then
    pass "TC3: $(basename "$_script") — no unconverted coordination push sites"
  else
    fail "TC3: $(basename "$_script") has push sites missing HEAD: refspec:"
    echo "$_missing" | while IFS= read -r line; do echo "    $line"; done
    TC3_PASS=0
  fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# TC4: home is on gaai-daemon-home; main checkout's <target> ref unchanged (AC6d)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC4: home on gaai-daemon-home; main checkout's staging ref unchanged ==="

TC4_DIR="$FIXTURE_DIR/tc4-project"
TC4_HOME="$FIXTURE_DIR/tc4-home"
setup_git_repo "$TC4_DIR"

TC4_MAIN_STAGING_BEFORE="$(git -C "$TC4_DIR" rev-parse "staging" 2>/dev/null || echo "?")"

_gaai_provision_daemon_home "$TC4_HOME" "staging" "$TC4_DIR" >/dev/null 2>&1

TC4_HOME_BRANCH="$(git -C "$TC4_HOME" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC4_HOME_BRANCH" == "gaai-daemon-home" ]]; then
  pass "TC4-1: home is on 'gaai-daemon-home' branch after provisioning"
else
  fail "TC4-1: home is on '${TC4_HOME_BRANCH:-<detached>}' (expected gaai-daemon-home)"
fi

TC4_MAIN_STAGING_AFTER="$(git -C "$TC4_DIR" rev-parse "staging" 2>/dev/null || echo "?")"
if [[ "$TC4_MAIN_STAGING_AFTER" == "$TC4_MAIN_STAGING_BEFORE" ]]; then
  pass "TC4-2: main checkout's local 'staging' ref unchanged by provisioning ($TC4_MAIN_STAGING_AFTER)"
else
  fail "TC4-2: main checkout's 'staging' moved from $TC4_MAIN_STAGING_BEFORE to $TC4_MAIN_STAGING_AFTER (daemon modified it)"
fi

TC4_MAIN_BRANCH="$(git -C "$TC4_DIR" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC4_MAIN_BRANCH" == "staging" ]]; then
  pass "TC4-3: main checkout remains on 'staging' (daemon never checked out its branch)"
else
  fail "TC4-3: main checkout is on '$TC4_MAIN_BRANCH' (expected staging)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "══════════════════════════════════════════════════"

exit "$FAIL_COUNT"
