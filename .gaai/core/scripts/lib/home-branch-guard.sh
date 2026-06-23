#!/usr/bin/env bash
# lib/home-branch-guard.sh — shared per-cycle and startup home-branch guard
#
# _gaai_home_branch_guard <project_dir> <target_branch>
#   Verifies the home checkout is on the target branch before coordination ops.
#
#   Returns:
#     0 — on-target AND clean working tree (no-op, caller may proceed)
#     1 — drifted AND dirty working tree (caller MUST pause+alert, no auto-stash)
#     2 — drifted AND clean working tree (auto-restored to target; caller may proceed)
#
#   Emits no log output — context-free, usable from daemon-start.sh (where the
#   daemon log() function is not available). Callers format their own messages.
#
# Idempotency guard: safe to source multiple times.

[[ -n "${_GAAI_HOME_BRANCH_GUARD_SH_SOURCED:-}" ]] && return 0
_GAAI_HOME_BRANCH_GUARD_SH_SOURCED=1

_gaai_home_branch_guard() {
  local _project_dir="$1"
  local _target_branch="$2"

  local _current_branch
  _current_branch="$(git -C "$_project_dir" branch --show-current 2>/dev/null || echo "")"

  # Happy path: already on target branch — check is a no-op
  [[ "$_current_branch" == "$_target_branch" ]] && return 0

  # Drifted — check for uncommitted changes (staged or unstaged)
  if ! git -C "$_project_dir" diff --quiet 2>/dev/null \
    || ! git -C "$_project_dir" diff --cached --quiet 2>/dev/null; then
    # Dirty working tree: caller must NOT auto-stash or switch — pause and alert
    return 1
  fi

  # Drifted AND clean — safe to auto-restore
  git -C "$_project_dir" checkout "$_target_branch" --quiet 2>/dev/null
  git -C "$_project_dir" pull origin "$_target_branch" --ff-only --quiet 2>/dev/null || true
  return 2
}
