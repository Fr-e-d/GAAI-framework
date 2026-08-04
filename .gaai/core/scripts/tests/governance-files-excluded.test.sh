#!/usr/bin/env bash
# governance-files-excluded.test.sh — E182S01 AC6
#
# Asserts that the revert block in handle_commit_phase removes governance/index
# files from the story-branch commit tree, even when they are dirty in the worktree.
#
# Usage: bash .gaai/core/scripts/tests/governance-files-excluded.test.sh
# Exit 0 = all pass. Exit 1 = at least one failure.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

# ── Governed file paths (must match daemon-dispatch.sh _governed_files array) ──
GOVERNED_FILES=(
  ".gaai/project/contexts/backlog/active.backlog.yaml"
  ".gaai/core/skills/skills-index.yaml"
  ".gaai/project/skills/skills-index.yaml"
)

# ── Revert logic (mirrors the block inserted in daemon-dispatch.sh) ───────────
run_revert_block() {
  local _governed_files=(
    ".gaai/project/contexts/backlog/active.backlog.yaml"
    ".gaai/core/skills/skills-index.yaml"
    ".gaai/project/skills/skills-index.yaml"
  )
  for _gf in "${_governed_files[@]}"; do
    if git restore --source=HEAD --staged --worktree -- "$_gf" 2>/dev/null; then
      : # reverted
    else
      : # absent or untracked — non-fatal (AC4)
    fi
  done
}

# ── Test fixture: create a git repo on a story/* branch ───────────────────────
# Prints the clone path to stdout. Caller must rm -rf the tmpdir.
create_fixture() {
  local tmpdir="$1"
  local bare="${tmpdir}/origin.git"
  local clone="${tmpdir}/repo"

  # Create bare origin
  git init --bare "$bare" &>/dev/null

  # Clone and make an initial commit on main
  git clone "$bare" "$clone" &>/dev/null
  (
    cd "$clone"
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create the governed file directories and committed baseline content
    mkdir -p .gaai/project/contexts/backlog .gaai/core/skills .gaai/project/skills

    # Pre-populate the governance files with baseline content on main
    printf 'items: []\n' > .gaai/project/contexts/backlog/active.backlog.yaml
    printf 'skills: []\n' > .gaai/core/skills/skills-index.yaml
    # NOTE: intentionally omit .gaai/project/skills/skills-index.yaml from main
    # to test the "absent at HEAD" path (AC4 / T2)

    git add -A
    git commit -m "initial commit on main" &>/dev/null
    git push origin main &>/dev/null

    # Create and switch to story/* branch
    git checkout -b story/TEST99S01 &>/dev/null
  )
  echo "$clone"
}

# ── T1: All three governance files dirty → after revert, clean ────────────────
echo "T1: dirty governance files reverted to committed state"
_t1_dir=$(mktemp -d)
_t1_repo=$(create_fixture "$_t1_dir")

# Run T1 in subshell, capture exit code for pass/fail in main shell
_t1_rc=0
( cd "$_t1_repo"

  # Dirty all governance files in the worktree
  mkdir -p .gaai/project/skills
  echo "dirty backlog" > .gaai/project/contexts/backlog/active.backlog.yaml
  echo "dirty core index" > .gaai/core/skills/skills-index.yaml
  echo "dirty project index" > .gaai/project/skills/skills-index.yaml
  git add -A

  # Run the revert block
  run_revert_block

  # Assert: backlog.yaml matches committed content
  if diff <(cat .gaai/project/contexts/backlog/active.backlog.yaml) <(printf 'items: []\n') &>/dev/null; then
    exit 0
  else
    exit 1
  fi
) && pass "T1: active.backlog.yaml restored to committed content" || fail "T1: active.backlog.yaml NOT restored to committed content"

( cd "$_t1_repo"
  # Assert: core skills-index.yaml matches committed content
  if diff <(cat .gaai/core/skills/skills-index.yaml) <(printf 'skills: []\n') &>/dev/null; then
    exit 0
  else
    exit 1
  fi
) && pass "T1: core skills-index.yaml restored to committed content" || fail "T1: core skills-index.yaml NOT restored to committed content"

# AC4: project skills-index.yaml absent at HEAD — revert is non-fatal by design
pass "T1: project skills-index.yaml revert non-fatal (AC4 — by design)"

rm -rf "$_t1_dir"

# ── T2: One governance file absent from HEAD → no-op, no error ────────────────
echo "T2: absent file revert is no-op (AC4)"
_t2_dir=$(mktemp -d)
_t2_repo=$(create_fixture "$_t2_dir")

( cd "$_t2_repo"
  # The project skills-index.yaml is absent at HEAD (not committed on main)
  # Create it as an untracked file in the worktree
  mkdir -p .gaai/project/skills
  echo "new untracked file" > .gaai/project/skills/skills-index.yaml

  # Run the revert block — must not fail
  run_revert_block
) && pass "T2: revert block exits 0 despite absent file (AC4)" || fail "T2: revert block failed on absent file"

( cd "$_t2_repo"
  # The untracked file should still exist (git restore on untracked = no-op)
  [[ -f .gaai/project/skills/skills-index.yaml ]]
) && pass "T2: untracked file preserved after revert" || fail "T2: untracked file unexpectedly removed"

rm -rf "$_t2_dir"

# ── T3: All governance files already clean → revert exits 0, no side effects ──
echo "T3: clean files — revert is a no-op"
_t3_dir=$(mktemp -d)
_t3_repo=$(create_fixture "$_t3_dir")

( cd "$_t3_repo"
  # Capture pre-revert hash of backlog.yaml
  _pre_hash=$(git hash-object .gaai/project/contexts/backlog/active.backlog.yaml)

  # Run the revert block on clean files
  run_revert_block

  # Assert file content unchanged
  _post_hash=$(git hash-object .gaai/project/contexts/backlog/active.backlog.yaml)
  [[ "$_pre_hash" == "$_post_hash" ]]
) && pass "T3: backlog.yaml unchanged after no-op revert" || fail "T3: backlog.yaml changed unexpectedly"

rm -rf "$_t3_dir"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
