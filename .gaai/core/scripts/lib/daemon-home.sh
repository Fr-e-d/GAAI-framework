#!/usr/bin/env bash
# lib/daemon-home.sh — daemon home worktree provisioner
#
# _gaai_provision_daemon_home <home_path> <target_branch> [repo_root]
#
#   Provisions an idempotent, self-repairing git worktree at <home_path>.
#   The worktree is created DETACHED (not on a branch) so it never conflicts
#   with the main checkout still holding <target_branch>.
#   Branch adoption is deferred to the coordination-flip step (see backlog).
#
#   Behaviour:
#     - Fetches origin/<target_branch> (best-effort; offline acceptable).
#     - Valid home (registered worktree + HEAD resolves + clean tree):
#         bring to current origin/<target_branch> tip via reset --hard + clean.
#     - Stale or absent home:
#         remove + prune + rm -rf + re-add detached at origin/<target_branch>.
#
#   Returns: 0 on success, 1 on unrecoverable error.
#
# Idempotency guard: safe to source multiple times.

[[ -n "${_GAAI_DAEMON_HOME_SH_SOURCED:-}" ]] && return 0
_GAAI_DAEMON_HOME_SH_SOURCED=1

_gaai_provision_daemon_home() {
  local _home_path="$1"
  local _target_branch="$2"
  # Optional 3rd arg: repo root for git worktree commands.
  # Defaults to git rev-parse --show-toplevel from CWD (daemon-start.sh context).
  # Tests pass the sandbox repo dir explicitly to avoid CWD dependency.
  local _repo_root="${3:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"

  [[ -z "$_home_path" ]]    && { echo "daemon-home: ERROR: home path is empty" >&2;     return 1; }
  [[ -z "$_repo_root" ]]   && { echo "daemon-home: ERROR: cannot resolve repo root" >&2; return 1; }
  [[ -z "$_target_branch" ]] && { echo "daemon-home: ERROR: target branch is empty" >&2;  return 1; }

  # 1. Fetch remote tip (best-effort; offline is acceptable — we still provision
  #    against whatever origin/<target> ref is cached locally).
  git -C "$_repo_root" fetch origin "$_target_branch" --quiet 2>/dev/null || true

  # 2. Determine if home path is a valid registered worktree.
  # Resolve to physical path (handles /tmp → /private/tmp symlink on macOS and
  # similar cases) before grepping worktree list — git canonicalises paths with
  # realpath() at worktree-add time, so the stored path is always the physical one.
  local _is_valid=0
  if [[ -d "$_home_path" ]]; then
    local _home_real
    _home_real="$(cd "$_home_path" && pwd -P 2>/dev/null || echo "$_home_path")"
    if git -C "$_repo_root" worktree list --porcelain 2>/dev/null \
        | grep -qF "worktree $_home_real"; then
      # Registered — lightweight health check: HEAD resolves + tree is clean.
      if git -C "$_home_path" rev-parse HEAD >/dev/null 2>&1 \
          && git -C "$_home_path" diff --quiet 2>/dev/null \
          && git -C "$_home_path" diff --cached --quiet 2>/dev/null; then
        _is_valid=1
      fi
    fi
  fi

  if [[ "$_is_valid" -eq 1 ]]; then
    # Valid home — bring to current origin/<target_branch> tip (no-op if already there).
    git -C "$_home_path" reset --hard "origin/$_target_branch" >/dev/null 2>&1 || true
    git -C "$_home_path" clean -fd >/dev/null 2>&1 || true
    return 0
  fi

  # Stale or absent — repair.
  # worktree remove --force handles registered-but-broken worktrees.
  git -C "$_repo_root" worktree remove --force "$_home_path" 2>/dev/null || true
  git -C "$_repo_root" worktree prune 2>/dev/null || true
  # rm -rf: prune does not remove the directory itself; a plain non-worktree
  # directory at the path also needs to be cleared before worktree add.
  [[ -e "$_home_path" ]] && rm -rf "$_home_path"

  # Provision detached — never checks out a branch, so it cannot conflict with
  # the main checkout still holding <target_branch> at this stage
  # (provision-only; branch adoption deferred to the coordination-flip step).
  git -C "$_repo_root" worktree add --detach "$_home_path" "origin/$_target_branch"
}
