#!/usr/bin/env bash
# worktree-branch-guard.test.sh — regression suite for the landed-or-preserved
# branch-deletion guard (E1057S02). Mirrors the bare-remote + clone + worktree
# fixture pattern already used by worktree-integrity.test.sh /
# recovery-non-destructive.test.sh.
#
# T1: incident replay — unpushed branch survives as a preserved rename
# T2: landed via remote backlog status:done — branch hard-deleted
# T3: landed via remote-ref presence (pushed, no PR yet) — branch hard-deleted
# T4: single-fire log throttle across two not-landed preservation events
set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

FIXTURE_BASE="/tmp/gaai-branch-guard-test-$$"
trap 'rm -rf "$FIXTURE_BASE"' EXIT

# Source the library under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/worktree-integrity.sh
source "${SCRIPT_DIR}/lib/worktree-integrity.sh"
# _worktree_branch_is_landed lazily sources lib/backlog-yaml.sh on first call,
# which itself runs under `set -euo pipefail` — sourcing flips that mode for
# this whole shell too (source is not scope-limited). This test intentionally
# never runs under -e (matches the `set -uo pipefail` header above); every rc
# below is captured explicitly, so re-assert +e defensively in case a guard
# call flips it before rc capture.
set +e

BACKLOG_REL_FIXTURE=".gaai/project/contexts/backlog/active.backlog.yaml"

# Bare remote + main clone on staging, with an empty backlog fixture at the
# default BACKLOG_REL path so the (a1) check has something to read.
setup_fixture() {
  local base="$1"
  rm -rf "${base}_remote.git" "${base}_main"

  git init --bare "${base}_remote.git" -q
  git clone "${base}_remote.git" "${base}_main" -q 2>/dev/null

  git -C "${base}_main" config user.email "test@gaai.local"
  git -C "${base}_main" config user.name "GAAI Test"
  git -C "${base}_main" config core.hooksPath /dev/null

  mkdir -p "$(dirname "${base}_main/${BACKLOG_REL_FIXTURE}")"
  cat > "${base}_main/${BACKLOG_REL_FIXTURE}" <<'YAML'
items: []
YAML

  echo "initial" > "${base}_main/file.txt"
  git -C "${base}_main" add .
  git -C "${base}_main" commit -m "init" -q
  git -C "${base}_main" branch -M staging
  git -C "${base}_main" push origin staging -q
  git -C "${base}_main" fetch origin -q
}

# Creates local branch story/<sid> with one commit NOT present on origin/staging.
# Leaves the main clone checked out back on staging when done (no worktree
# needed — this is a throwaway fixture, not a real delivery).
make_unpushed_branch() {
  local base="$1" sid="$2"
  git -C "${base}_main" checkout -B "story/${sid}" staging -q 2>/dev/null
  echo "unpushed-${sid}-$RANDOM-$(date +%s%N 2>/dev/null || date +%s)" >> "${base}_main/file.txt"
  git -C "${base}_main" add file.txt
  git -C "${base}_main" commit -m "unpushed-${sid}" -q
  git -C "${base}_main" checkout staging -q
}

# ── T1: incident replay — unpushed branch survives as a preserved rename ────
echo ""
echo "T1: incident replay (unpushed branch, no PR, no landed backlog status)"
T1="${FIXTURE_BASE}/t1"
setup_fixture "$T1"
make_unpushed_branch "$T1" "T1"

PROJECT_DIR="${T1}_main"
LOCK_DIR="${T1}_main/.gaai-locks"
mkdir -p "$LOCK_DIR"
TARGET_BRANCH="staging"

_t1_original_tip=$(git -C "${T1}_main" rev-parse "story/T1" 2>/dev/null || echo "")

# Subshell isolation: the guard's lazy backlog-yaml.sh source flips `set -e`
# for whatever shell runs it; `( ... )` confines that to the subshell so it
# never leaks into this test script's own option state.
( _worktree_branch_delete_or_preserve "T1" "story/T1" "test-incident" )
_rc_t1=$?

if ! git -C "${T1}_main" rev-parse --verify -q "story/T1" >/dev/null 2>&1; then
  pass "T1a: story/T1 no longer exists as a ref"
else
  fail "T1a: story/T1 still exists as a ref"
fi

_t1_preserved_count=$(git -C "${T1}_main" for-each-ref --format='%(refname:short)' "refs/heads/story/T1-preserved-*" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$_t1_preserved_count" -eq 1 ]]; then
  pass "T1b: exactly one story/T1-preserved-* ref exists"
else
  fail "T1b: expected exactly one preserved ref, got ${_t1_preserved_count}"
fi

_t1_preserved_ref=$(git -C "${T1}_main" for-each-ref --format='%(refname:short)' "refs/heads/story/T1-preserved-*" 2>/dev/null | head -1)
if [[ -n "$_t1_preserved_ref" ]] && git -C "${T1}_main" log "$_t1_preserved_ref" --format=%H 2>/dev/null | grep -qF "$_t1_original_tip"; then
  pass "T1c: original commit SHA present on the preserved ref"
else
  fail "T1c: original commit SHA NOT found on preserved ref"
fi

if grep -qE '\|T1\|' "${LOCK_DIR}/.branch-preserved.audit" 2>/dev/null; then
  pass "T1d: audit log contains an entry for T1"
else
  fail "T1d: audit log missing T1 entry"
fi

if grep -qF "$_t1_original_tip" "${LOCK_DIR}/.branch-preserved.audit" 2>/dev/null; then
  pass "T1d2: audit log entry records the branch tip SHA"
else
  fail "T1d2: audit log entry missing tip SHA"
fi

if [[ "$_rc_t1" -eq 1 ]]; then
  pass "T1e: function returns 1 (preserved)"
else
  fail "T1e: expected rc=1, got ${_rc_t1}"
fi

# ── T2: landed via remote backlog status:done → hard-deleted ───────────────
echo ""
echo "T2: landed via remote backlog status:done"
T2="${FIXTURE_BASE}/t2"
setup_fixture "$T2"
make_unpushed_branch "$T2" "T2"

cat > "${T2}_main/${BACKLOG_REL_FIXTURE}" <<'YAML'
items:
- id: T2
  status: done
YAML
git -C "${T2}_main" add "${BACKLOG_REL_FIXTURE}"
git -C "${T2}_main" commit -m "backlog: T2 done" -q
git -C "${T2}_main" push origin staging -q
git -C "${T2}_main" fetch origin -q

PROJECT_DIR="${T2}_main"
LOCK_DIR="${T2}_main/.gaai-locks"
mkdir -p "$LOCK_DIR"
TARGET_BRANCH="staging"

( _worktree_branch_delete_or_preserve "T2" "story/T2" "test-landed-backlog" )
_rc_t2=$?

if ! git -C "${T2}_main" rev-parse --verify -q "story/T2" >/dev/null 2>&1; then
  pass "T2a: story/T2 branch deleted"
else
  fail "T2a: story/T2 branch still exists"
fi

_t2_preserved_count=$(git -C "${T2}_main" for-each-ref --format='%(refname:short)' "refs/heads/story/T2-preserved-*" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$_t2_preserved_count" -eq 0 ]]; then
  pass "T2b: no preserved-* ref created"
else
  fail "T2b: unexpected preserved-* ref created (count=${_t2_preserved_count})"
fi

if [[ "$_rc_t2" -eq 0 ]]; then
  pass "T2c: function returns 0 (landed)"
else
  fail "T2c: expected rc=0, got ${_rc_t2}"
fi

# ── T3: landed via remote-ref presence (pushed, open-PR-equivalent) ────────
echo ""
echo "T3: landed via remote-ref presence (branch pushed, no PR entry)"
T3="${FIXTURE_BASE}/t3"
setup_fixture "$T3"
make_unpushed_branch "$T3" "T3"
git -C "${T3}_main" push origin "story/T3" -q

PROJECT_DIR="${T3}_main"
LOCK_DIR="${T3}_main/.gaai-locks"
mkdir -p "$LOCK_DIR"
TARGET_BRANCH="staging"

( _worktree_branch_delete_or_preserve "T3" "story/T3" "test-landed-remote-ref" )
_rc_t3=$?

if ! git -C "${T3}_main" rev-parse --verify -q "story/T3" >/dev/null 2>&1; then
  pass "T3a: story/T3 branch deleted"
else
  fail "T3a: story/T3 branch still exists"
fi

if [[ "$_rc_t3" -eq 0 ]]; then
  pass "T3b: function returns 0 (landed via remote ref)"
else
  fail "T3b: expected rc=0, got ${_rc_t3}"
fi

# ── T4: single-fire log throttle across two not-landed preservation events ─
echo ""
echo "T4: single-fire log throttle (2 preservation events, 1 log line)"
T4="${FIXTURE_BASE}/t4"
setup_fixture "$T4"
make_unpushed_branch "$T4" "T4"

PROJECT_DIR="${T4}_main"
LOCK_DIR="${T4}_main/.gaai-locks"
mkdir -p "$LOCK_DIR"
TARGET_BRANCH="staging"

_t4_out1=$(_worktree_branch_delete_or_preserve "T4" "story/T4" "test-throttle-1" 2>&1)
_rc_t4_1=$?

sleep 1  # guarantee a distinct preserved-branch timestamp for the 2nd rename

# Recreate story/T4 — simulates the daemon retry path handing out a fresh
# branch that then dies again (the fast-crash-retry-loop scenario AC4 bounds).
make_unpushed_branch "$T4" "T4"
_t4_out2=$(_worktree_branch_delete_or_preserve "T4" "story/T4" "test-throttle-2" 2>&1)
_rc_t4_2=$?

_t4_audit_count=$(grep -cE '\|T4\|' "${LOCK_DIR}/.branch-preserved.audit" 2>/dev/null || echo 0)
if [[ "$_t4_audit_count" -eq 2 ]]; then
  pass "T4a: audit log has 2 entries for T4 (both preservation events recorded)"
else
  fail "T4a: expected 2 audit entries for T4, got ${_t4_audit_count}"
fi

_t4_log_lines=$(printf '%s\n%s\n' "$_t4_out1" "$_t4_out2" | grep -c '\[WORKTREE-GUARD\]' || true)
if [[ "$_t4_log_lines" -eq 1 ]]; then
  pass "T4b: [WORKTREE-GUARD] log line printed exactly once across both calls (throttled)"
else
  fail "T4b: expected exactly 1 [WORKTREE-GUARD] line, got ${_t4_log_lines}"
fi

if [[ "$_rc_t4_1" -eq 1 && "$_rc_t4_2" -eq 1 ]]; then
  pass "T4c: both calls return 1 (preserved)"
else
  fail "T4c: expected rc=1 for both calls, got rc1=${_rc_t4_1} rc2=${_rc_t4_2}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== worktree-branch-guard test suite ==="
echo "PASS: $PASS_COUNT  FAIL: $FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
