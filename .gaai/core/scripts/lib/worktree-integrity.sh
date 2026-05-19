#!/usr/bin/env bash
# lib/worktree-integrity.sh — worktree corruption detection + safe-base re-fetch
#
# Sourceable library. Two public functions:
#   _check_worktree_integrity <worktree_path> <expected_base> [<sid>]
#     Returns: 0=clean, 1=corruption suspected, 2=unrecoverable (fsck failure)
#   _recover_worktree_safe_base <sid> <worktree_path> <expected_base>
#     Returns: 0=recovered cleanly, 1=cherry-pick conflicts, 2=unrecoverable
#
# Env vars (all optional, have defaults):
#   GAAI_WORKTREE_COMMITS_AHEAD_MAX  — commits-ahead threshold (default 100)
#   GAAI_WORKTREE_BASE_LAG_MAX       — acceptable lag behind base (default 5)
#   GAAI_WORKTREE_DELETIONS_MAX      — phantom-deletion threshold (default 50)
#   GAAI_WORKTREE_RECOVERY_TIMEOUT_SEC — wall-clock recovery timeout (default 120)
#   PROJECT_DIR                      — repo root (required by _recover_worktree_safe_base)
#   LOCK_DIR                         — for audit log (optional, falls back to PROJECT_DIR)

[[ -n "${_WORKTREE_INTEGRITY_SH_SOURCED:-}" ]] && return 0
_WORKTREE_INTEGRITY_SH_SOURCED=1

_check_worktree_integrity() {
  local worktree_path="$1" expected_base="$2" sid="${3:-unknown}"
  local _base_branch _remote_ref _commits_ahead _deletions _threshold _fsck_out
  local _corruption_suspected=0

  local _commits_max="${GAAI_WORKTREE_COMMITS_AHEAD_MAX:-100}"
  local _deletions_max="${GAAI_WORKTREE_DELETIONS_MAX:-50}"

  echo "[WORKTREE-CHECK] ${sid} : verifying integrity (path=${worktree_path}, expected_base=${expected_base})"

  # First spawn: no worktree directory yet — nothing to check
  if [[ ! -d "$worktree_path" ]]; then
    echo "[WORKTREE-CHECK] ${sid} : no worktree directory — skipping (clean)"
    return 0
  fi

  # Normalize base: strip leading origin/ to get bare branch name
  _base_branch="${expected_base#origin/}"
  _remote_ref="origin/${_base_branch}"

  # Best-effort fetch — check still runs on stale refs if offline
  git -C "$worktree_path" --no-pager fetch origin "${_base_branch}" --quiet 2>/dev/null || true

  # fsck: object corruption is unrecoverable — return 2 immediately
  if ! _fsck_out=$(git -C "$worktree_path" --no-pager fsck --no-dangling 2>&1); then
    echo "[WORKTREE-CHECK] ${sid} : CORRUPTION SUSPECTED — commits_ahead=? deletions=? fsck=FAIL"
    echo "[WORKTREE-CHECK] ${sid} : fsck output: ${_fsck_out: -300}"
    return 2
  fi

  # Commits-ahead: wrapper producing >100 commits is almost certainly stuck on wrong base
  _commits_ahead=$(git -C "$worktree_path" --no-pager rev-list HEAD --not "${_remote_ref}" 2>/dev/null | wc -l | tr -d ' ')
  _commits_ahead="${_commits_ahead:-0}"

  # Phantom-deletes: files deleted in diff from remote base to HEAD
  _deletions=$(git -C "$worktree_path" --no-pager diff --diff-filter=D --name-only "${_remote_ref}...HEAD" 2>/dev/null | wc -l | tr -d ' ')
  _deletions="${_deletions:-0}"

  # Dynamic deletion threshold: max(50, 5 × story file count) if story is parseable
  _threshold="$_deletions_max"
  if [[ -n "$sid" && "$sid" != "unknown" ]]; then
    local _story_path="${worktree_path}/.gaai/project/contexts/artefacts/stories/${sid}.story.md"
    local _file_count
    _file_count=$(awk '/^## File Inventory/{found=1; next} found && /^\|.*\|/{count++} found && /^##/{exit} END{print count+0}' \
      "$_story_path" 2>/dev/null || echo 0)
    if [[ "${_file_count:-0}" -gt 0 ]]; then
      local _dynamic=$(( _file_count * 5 ))
      (( _dynamic > _threshold )) && _threshold="$_dynamic"
    fi
  fi

  if (( _commits_ahead > _commits_max )); then
    _corruption_suspected=1
  fi
  if (( _deletions > _threshold )); then
    _corruption_suspected=1
  fi

  if [[ "$_corruption_suspected" -eq 0 ]]; then
    echo "[WORKTREE-CHECK] ${sid} : clean (commits_ahead=${_commits_ahead}, deletions=${_deletions}, fsck=OK)"
    return 0
  else
    echo "[WORKTREE-CHECK] ${sid} : CORRUPTION SUSPECTED — commits_ahead=${_commits_ahead}, deletions=${_deletions}, fsck=OK"
    return 1
  fi
}

_recover_worktree_safe_base() {
  local sid="$1" worktree_path="$2" expected_base="$3"
  local _ts_start _elapsed _duration
  local _stash_out _stash_rc _stash_created=false _stash_label
  local _base_branch _remote_ref
  local _commits=() _sha _cp_out _cp_rc

  local _recovery_timeout="${GAAI_WORKTREE_RECOVERY_TIMEOUT_SEC:-120}"
  local _project_dir="${PROJECT_DIR:-}"
  local _lock_dir="${LOCK_DIR:-${_project_dir}/.gaai/project/contexts/backlog/.delivery-locks}"
  local _audit_log="${_lock_dir}/.cleanup-pending.audit"

  _ts_start=$(date +%s)
  _base_branch="${expected_base#origin/}"
  _remote_ref="origin/${_base_branch}"

  echo "[WORKTREE-RECOVER] ${sid} : starting safe-base re-fetch (path=${worktree_path}, base=${_base_branch})"

  # ── Step 1: Stash working tree + index + untracked (--include-untracked) ──
  # CRITICAL: stash before any destructive operation. If stash fails (non-empty
  # working tree with error), ABORT to prevent data loss.
  _stash_label="gaai-recovery-${sid}-$(date -u +%Y%m%dT%H%M%SZ)"
  _stash_out=$(git -C "$worktree_path" --no-pager stash push --include-untracked -m "$_stash_label" 2>&1)
  _stash_rc=$?

  if echo "$_stash_out" | grep -q "No local changes to save"; then
    _stash_created=false
    echo "[WORKTREE-RECOVER] ${sid} : nothing to stash — continuing"
  elif [[ $_stash_rc -ne 0 ]]; then
    echo "[WORKTREE-RECOVER] ${sid} : stash push FAILED (rc=${_stash_rc}): ${_stash_out: -300} — aborting recovery to prevent data loss"
    printf '%s|%s|worktree-recovery|failed-stash|0\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" >> "$_audit_log" 2>/dev/null || true
    return 2
  else
    _stash_created=true
    echo "[WORKTREE-RECOVER] ${sid} : stash created: ${_stash_label}"
  fi

  # ── Step 2: Capture wrapper's commits BEFORE worktree remove ──────────────
  # --reverse: oldest-first order is required for cherry-pick replay.
  # Objects survive worktree removal (shared object store in main repo .git).
  while IFS= read -r _sha; do
    [[ -n "$_sha" ]] && _commits+=("$_sha")
  done < <(git -C "$worktree_path" --no-pager log --reverse "${_remote_ref}..story/${sid}" --format=%H 2>/dev/null)

  echo "[WORKTREE-RECOVER] ${sid} : captured ${#_commits[@]} commits to cherry-pick"

  # ── Step 3: Remove worktree (destructive — stash in step 1 captured everything) ──
  git -C "$_project_dir" --no-pager worktree remove --force "$worktree_path" 2>&1 || true
  git -C "$_project_dir" --no-pager worktree prune 2>/dev/null || true
  # Defensive: remove lingering directory if worktree remove left it
  rm -rf "$worktree_path" 2>/dev/null || true

  # ── Step 4: Recreate worktree from current origin/<base> (clean base) ─────
  git -C "$_project_dir" --no-pager fetch origin "${_base_branch}" --quiet 2>/dev/null || true
  # Unconditional -D: bypass git "unmerged commits" safety check (we have the stash)
  git -C "$_project_dir" --no-pager branch -D "story/${sid}" 2>/dev/null || true
  local _wt_add_out
  if ! _wt_add_out=$(git -C "$_project_dir" --no-pager worktree add "$worktree_path" \
      -b "story/${sid}" "${_remote_ref}" 2>&1); then
    echo "[WORKTREE-RECOVER] ${sid} : FAILED to recreate worktree: ${_wt_add_out} — unrecoverable"
    printf '%s|%s|worktree-recovery|unrecoverable-recreate|%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "${#_commits[@]}" \
      >> "$_audit_log" 2>/dev/null || true
    return 2
  fi

  # ── Step 5: Cherry-pick each captured commit (timeout-guarded) ────────────
  # Use -c core.hooksPath=/dev/null so pre-commit/commit-msg hooks (e.g. linting)
  # don't block replay of already-validated commits. Genuine conflicts still fail.
  for _sha in "${_commits[@]}"; do
    _elapsed=$(( $(date +%s) - _ts_start ))
    if (( _elapsed > _recovery_timeout )); then
      git -C "$worktree_path" --no-pager cherry-pick --abort 2>/dev/null || true
      echo "[WORKTREE-RECOVER] ${sid} : TIMEOUT after ${_elapsed}s — recovery aborted"
      printf '%s|%s|worktree-recovery|timeout|%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "${#_commits[@]}" \
        >> "$_audit_log" 2>/dev/null || true
      return 2
    fi
    _cp_out=$(git -C "$worktree_path" --no-pager -c core.hooksPath=/dev/null cherry-pick "$_sha" 2>&1)
    _cp_rc=$?
    if [[ $_cp_rc -ne 0 ]]; then
      git -C "$worktree_path" --no-pager cherry-pick --abort 2>/dev/null || true
      echo "[WORKTREE-RECOVER] ${sid} : cherry-pick conflict on ${_sha} — recovery failed (operator must intervene)"
      echo "[WORKTREE-RECOVER] ${sid} : output: ${_cp_out: -400}"
      printf '%s|%s|worktree-recovery|failed-conflicts|%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "${#_commits[@]}" \
        >> "$_audit_log" 2>/dev/null || true
      return 1
    fi
  done

  # ── Step 6: Re-apply stash (best-effort — leave for operator on conflict) ──
  if [[ "$_stash_created" == "true" ]]; then
    if ! git -C "$worktree_path" --no-pager stash pop 2>&1; then
      echo "[WORKTREE-RECOVER] ${sid} : stash pop failed — stash preserved for operator (${_stash_label})"
    fi
  fi

  # ── Step 7: Audit log + success ───────────────────────────────────────────
  _duration=$(( $(date +%s) - _ts_start ))
  printf '%s|%s|worktree-recovery|success|%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "${#_commits[@]}" \
    >> "$_audit_log" 2>/dev/null || true
  echo "[WORKTREE-RECOVER] ${sid} : recovery success in ${_duration}s — commits_recovered=${#_commits[@]}"
  return 0
}
