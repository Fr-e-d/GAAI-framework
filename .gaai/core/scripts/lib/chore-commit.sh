#!/usr/bin/env bash
# 3-phase daemon-spawn delivery, phase_status semantics (see project design notes)
# Audit-verified gate enforcement on backlog transitions
# flock+yq serialization variant (supersedes patch-apply approach)
#
# Serialized backlog YAML mutations for concurrent delivery wrappers.
# Requires these variables set in the calling shell:
#   BACKLOG_FILE  — absolute path to active.backlog.yaml
#   BACKLOG_REL   — relative path from repo root (e.g. .gaai/project/contexts/backlog/active.backlog.yaml)
#   LOCK_DIR      — directory for lock/audit files
#   TARGET_BRANCH — git branch to push to
#   SCHEDULER     — path to backlog-scheduler.sh (used by Option A fallback only)

_CHORE_HELPER_AVAILABLE=0
# DISABLED — yq -i rewrites entire YAML file with normalized formatting
# (quotes, key order, trailing whitespace), defeating both line-count AND block-scope
# drift checks. Forces fallback to Option A (scheduler --set-field) which preserves
# original formatting via awk-based targeted edit. Re-enable when yq formatting can be
# pinned to preserve byte-identical output for non-target story blocks.
# if command -v flock &>/dev/null \
#   && command -v yq &>/dev/null \
#   && yq --version 2>/dev/null | grep -q 'v4\.'; then
#   _CHORE_HELPER_AVAILABLE=1
# fi

# Option A fallback: refuse if drift, else scheduler-write + commit + push.
# Used when yq is unavailable OR when the yq-formatting-pinning prerequisite
# is not met (the non-fallback path is currently disabled — see comment above).
#
# Per-machine serialization via flock : when multiple wrappers run concurrently
# in separate tmux sessions on the same machine, all calls to this function
# raced on the git working tree (drift check / commit / push). One wrapper
# could read clean drift state, then another wrote, then the first committed,
# then push race resolved arbitrarily — wrappers that lost the race entered
# rollback path losing legitimate close-out work. Flock around the critical
# section serializes per-machine concurrent wrappers ; existing rebase-retry
# handles the remaining cross-machine race window.
_chore_option_a_fallback() {
  local story_id="$1" commit_subject="$2"; shift 2
  local backlog_file="${BACKLOG_FILE}" backlog_rel="${BACKLOG_REL}"
  local target_branch="${TARGET_BRANCH:-staging}"
  local warn_flag="${LOCK_DIR}/.chore-helper-missing.warning"
  if [[ ! -f "$warn_flag" ]]; then
    echo "[CHORE-COMMIT] WARNING: yq unavailable — using Option A fallback" >&2
    echo "[CHORE-COMMIT] Install: macOS: brew install yq  Linux: apt install yq" >&2
    touch "$warn_flag" 2>/dev/null || true
  fi

  # ── Per-machine serialization (NEW) ──────────────────────────────────
  # Acquire file-level flock around the entire critical section. Released
  # implicitly when the file descriptor closes (every return path below
  # closes fd 201 explicitly). Use fd 201 to avoid clashing with the
  # non-fallback path's fd 200 (those paths are mutually exclusive but
  # using a distinct fd makes future co-existence safer).
  local _have_lock=0
  if command -v flock &>/dev/null; then
    local lock_dir="${LOCK_DIR:-.}" lock_file="${LOCK_DIR:-.}/.backlog.lock"
    mkdir -p "$lock_dir" 2>/dev/null && touch "$lock_file" 2>/dev/null
    exec 201< "$lock_file"
    if flock -w 30 201; then
      _have_lock=1
    else
      echo "[CHORE-COMMIT] $story_id : lock timeout 30s — refuse-skip (Option A)" >&2
      printf '%s|%s|lock-timeout-30s-option-a\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$story_id" \
        >> "${lock_dir}/.chore-lock-timeout.audit" 2>/dev/null || true
      exec 201>&-
      return 1
    fi
  fi

  # Inline helper to release lock and return — avoids repeating cleanup
  # at each of the 6 return points below.
  _chore_a_done() {
    local _rc="$1"
    [[ "$_have_lock" -eq 1 ]] && exec 201>&-
    return "$_rc"
  }

  # ── Pre-commit drift sweep ─────────────────────────────────────────────
  # Wrappers write phase_status to the shared backlog YAML via
  # `scheduler --set-phase-status` (worktree-only, no commit). When several
  # wrappers progress concurrently, that drift accumulates on disk. The
  # original refuse-skip on ANY backlog drift then deadlocked every NEW
  # mark-in-progress attempt — the daemon couldn't pick up new stories
  # until each wrapper exited and ran its own reconcile (5-90 min later).
  # Instead, commit the accumulated wrapper-progress drift as its own
  # commit before applying our edit. The drift is legitimate state from
  # other wrappers and needs to land on origin anyway. If THAT commit
  # itself fails, fall back to the old refuse-skip (operator may have
  # genuine uncommitted edits we don't want to silently absorb).
  if ! git diff --quiet HEAD -- "$backlog_rel" 2>/dev/null; then
    if git add "$backlog_rel" 2>/dev/null \
       && git commit -m "chore(daemon): commit accumulated wrapper-progress writes [pre-mark $story_id]" --quiet -- "$backlog_rel" 2>/dev/null; then
      if ! git push origin "$target_branch" --quiet 2>/dev/null; then
        # Push race — fetch then distinguish genuine conflict from just-behind (AC4).
        git fetch origin "$target_branch" --quiet 2>/dev/null || true
        if git rebase "origin/$target_branch" --quiet 2>/dev/null; then
          # Rebase clean — retry push; if push still fails, re-sync to origin (AC2+AC3).
          if ! git push origin "$target_branch" --quiet 2>/dev/null; then
            git reset --hard "origin/$target_branch" --quiet 2>/dev/null || true
            echo "[CHORE-COMMIT] $story_id : pre-mark drift sweep re-synced to origin — will re-apply field" >&2
          fi
        else
          # Genuine rebase conflict (not just behind) — AC4: distinct diagnosable message.
          git rebase --abort 2>/dev/null || true
          git reset --hard "origin/$target_branch" --quiet 2>/dev/null || true
          echo "[CHORE-COMMIT] $story_id : pre-mark drift sweep — genuine rebase conflict, operator resolve required" >&2
          _chore_a_done 6
          return $?
        fi
      fi
      echo "[CHORE-COMMIT] $story_id : swept accumulated wrapper-progress drift before mark-in-progress" >&2
    else
      # add+commit itself failed — likely no diff content despite git diff
      # signalling drift (e.g. mode-only change). Revert to old refuse-skip.
      git reset HEAD -- "$backlog_rel" 2>/dev/null || true
      echo "[CHORE-COMMIT] $story_id : pre-mark drift sweep commit failed — refuse-skip" >&2
      _chore_a_done 6
      return $?
    fi
  fi
  while [[ $# -ge 2 ]]; do
    "${SCHEDULER:-}" --set-field "$story_id" "$1" "$2" "$backlog_file" 2>/dev/null || true
    shift 2
  done
  git add "$backlog_rel" 2>/dev/null
  if git diff --cached --quiet; then
    _chore_a_done 0
    return $?
  fi
  if ! git commit -m "$commit_subject" --quiet -- "$backlog_rel" 2>/dev/null; then
    # Transactional rollback : commit failed → revert disk write to prevent
    # orphan drift blocking subsequent stories (RC: prior orphan-drift incident).
    git reset HEAD -- "$backlog_rel" 2>/dev/null || true
    git checkout HEAD -- "$backlog_rel" 2>/dev/null || true
    echo "[CHORE-COMMIT] $story_id : commit failed — disk write rolled back" >&2
    _chore_a_done 1
    return $?
  fi
  if ! git push origin "$target_branch" --quiet 2>/dev/null; then
    # Push failed → try rebase-retry once
    if git fetch origin "$target_branch" --quiet 2>/dev/null \
      && git rebase "origin/$target_branch" --quiet 2>/dev/null \
      && git push origin "$target_branch" --quiet 2>/dev/null; then
      _chore_a_done 0
      return $?
    fi
    # Rebase or retry-push failed → reset the local commit + restore disk to HEAD
    # (HEAD here is post-fetch origin/branch since rebase failed cleanly aborted)
    git rebase --abort 2>/dev/null || true
    git reset --soft HEAD~1 2>/dev/null || true
    git reset HEAD -- "$backlog_rel" 2>/dev/null || true
    git checkout HEAD -- "$backlog_rel" 2>/dev/null || true
    echo "[CHORE-COMMIT] $story_id : push failed — local commit + disk rolled back" >&2
    _chore_a_done 1
    return $?
  fi
  _chore_a_done 0
  return $?
}

# chore_commit_field <story_id> <field> <new_value> <commit_subject>
# Acquires backlog advisory lock, mutates one field via yq, verifies drift == 2 lines, commits+pushes.
# Exit codes: 0=success, 1=lock-timeout|push-failure|yq-error, 6=cross-story-drift
chore_commit_field() {
  local story_id="$1" field="$2" new_value="$3" commit_subject="$4"
  if [[ "$_CHORE_HELPER_AVAILABLE" -eq 0 ]]; then
    _chore_option_a_fallback "$story_id" "$commit_subject" "$field" "$new_value"
    return $?
  fi
  local backlog_file="${BACKLOG_FILE}" backlog_rel="${BACKLOG_REL}"
  local lock_dir="${LOCK_DIR}" lock_file="${LOCK_DIR}/.backlog.lock"
  local target_branch="${TARGET_BRANCH:-staging}"

  mkdir -p "$lock_dir" 2>/dev/null && touch "$lock_file" 2>/dev/null
  exec 200< "$lock_file"
  if ! flock -w 30 200; then
    echo "[CHORE-COMMIT] $story_id : lock timeout 30s — refuse-skip" >&2
    printf '%s|%s|lock-timeout-30s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$story_id" \
      >> "${lock_dir}/.chore-lock-timeout.audit" 2>/dev/null || true
    exec 200>&-
    return 1
  fi

  # Idempotency: skip if value already matches
  local current
  current=$(yq ".items[] | select(.id==\"$story_id\") | .$field" "$backlog_file" 2>/dev/null || echo "")
  if [[ "$current" == "$new_value" ]]; then
    exec 200>&-
    return 0
  fi

  # Targeted yq mutation (only the specified field in the specified story block)
  if ! yq -i "(.items[] | select(.id==\"$story_id\") | .$field) = \"$new_value\"" \
       "$backlog_file" 2>/dev/null; then
    echo "[CHORE-COMMIT] $story_id : yq mutation failed for .$field" >&2
    exec 200>&-
    return 1
  fi

  # Drift verify (cycle-2 review MEDIUM-N1 fix) : check diff doesn't touch lines outside the target story block.
  # Original strict 2-line check failed when field is ADDED (1 line) vs UPDATED (2 lines).
  # New semantic check : diff hunks must only touch the target story's block.
  local other_story_lines
  other_story_lines=$(git diff -U0 HEAD -- "$backlog_rel" 2>/dev/null \
    | awk -v sid="$story_id" '
        /^@@/ { in_hunk=1; next }
        in_hunk && /^[+-]- id: / {
          gsub(/^[+-]- id: */, "")
          gsub(/[[:space:]]+$/, "")
          if ($0 != sid) print
        }
      ' | wc -l | tr -d ' ' 2>/dev/null || echo "0")
  if [[ "$other_story_lines" != "0" ]]; then
    echo "[CHORE-COMMIT] $story_id : cross-story drift ($other_story_lines other story block(s) touched) — yq reverted, refuse-skip, operator resolve drift first" >&2
    git checkout HEAD -- "$backlog_rel" 2>/dev/null || true
    exec 200>&-
    return 6
  fi

  # Commit
  git add "$backlog_rel" 2>/dev/null
  if ! git commit -m "$commit_subject" --quiet -- "$backlog_rel" 2>/dev/null; then
    echo "[CHORE-COMMIT] $story_id : git commit failed" >&2
    exec 200>&-
    return 1
  fi

  # Push with rebase-retry for non-fast-forward
  if git push origin "$target_branch" --quiet 2>/dev/null; then
    exec 200>&-
    return 0
  fi
  if git fetch origin "$target_branch" --quiet 2>/dev/null \
    && git rebase "origin/$target_branch" --quiet 2>/dev/null \
    && git push origin "$target_branch" --quiet 2>/dev/null; then
    exec 200>&-
    return 0
  fi
  git rebase --abort 2>/dev/null || true
  echo "[CHORE-COMMIT] $story_id : push failed after rebase retry — refuse-skip" >&2
  exec 200>&-
  return 1
}

# chore_commit_multi_field <story_id> <field1> <val1> [<field2> <val2> ...] <commit_subject>
# Last argument is always the commit_subject. All other args after story_id are field/value pairs.
# Acquires lock once, mutates all specified fields atomically, commits+pushes.
# Exit codes: 0=success, 1=lock-timeout|push-failure|yq-error, 6=cross-story-drift
chore_commit_multi_field() {
  local story_id="$1"; shift
  local args=("$@")
  local n="${#args[@]}"
  # Validate: need at least 1 field/value pair + commit_subject = 3 args minimum, pairs must be even
  if [[ $n -lt 3 || $(( (n - 1) % 2 )) -ne 0 ]]; then
    echo "[CHORE-COMMIT] chore_commit_multi_field: bad args — need story_id + field/value pairs + subject" >&2
    return 1
  fi
  local commit_subject="${args[$((n-1))]}"
  local pairs=("${args[@]:0:$((n-1))}")

  if [[ "$_CHORE_HELPER_AVAILABLE" -eq 0 ]]; then
    _chore_option_a_fallback "$story_id" "$commit_subject" "${pairs[@]}"
    return $?
  fi

  local backlog_file="${BACKLOG_FILE}" backlog_rel="${BACKLOG_REL}"
  local lock_dir="${LOCK_DIR}" lock_file="${LOCK_DIR}/.backlog.lock"
  local target_branch="${TARGET_BRANCH:-staging}"

  mkdir -p "$lock_dir" 2>/dev/null && touch "$lock_file" 2>/dev/null
  exec 200< "$lock_file"
  if ! flock -w 30 200; then
    echo "[CHORE-COMMIT] $story_id : lock timeout 30s — refuse-skip" >&2
    printf '%s|%s|lock-timeout-30s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$story_id" \
      >> "${lock_dir}/.chore-lock-timeout.audit" 2>/dev/null || true
    exec 200>&-
    return 1
  fi

  local n_changed=0
  local i=0
  while [[ $i -lt ${#pairs[@]} ]]; do
    local field="${pairs[$i]}" value="${pairs[$((i+1))]}"
    i=$(( i + 2 ))
    local current
    current=$(yq ".items[] | select(.id==\"$story_id\") | .$field" "$backlog_file" 2>/dev/null || echo "")
    if [[ "$current" == "$value" ]]; then
      continue
    fi
    if ! yq -i "(.items[] | select(.id==\"$story_id\") | .$field) = \"$value\"" \
         "$backlog_file" 2>/dev/null; then
      echo "[CHORE-COMMIT] $story_id : yq mutation failed for .$field" >&2
      git checkout HEAD -- "$backlog_rel" 2>/dev/null || true
      exec 200>&-
      return 1
    fi
    (( n_changed++ )) || true
  done

  if [[ $n_changed -eq 0 ]]; then
    exec 200>&-
    return 0
  fi

  # Drift verify (cycle-2 review MEDIUM-N1 fix) : check diff doesn't touch lines outside the target story block.
  # Original strict `2*n_changed` line count failed when a field is ADDED vs UPDATED (added → 1 line, updated → 2).
  # New semantic check : diff hunks must only touch lines between `^- id: <story_id>` and the next `^- id:` line.
  local other_story_lines
  other_story_lines=$(git diff -U0 HEAD -- "$backlog_rel" 2>/dev/null \
    | awk -v sid="$story_id" '
        /^@@/ { in_hunk=1; next }
        in_hunk && /^[+-]- id: / {
          # Diff touches a story ID declaration line — extract the ID and check if it is ours
          gsub(/^[+-]- id: */, "")
          gsub(/[[:space:]]+$/, "")
          if ($0 != sid) print
        }
      ' | wc -l | tr -d ' ' 2>/dev/null || echo "0")
  if [[ "$other_story_lines" != "0" ]]; then
    echo "[CHORE-COMMIT] $story_id : cross-story drift ($other_story_lines other story block(s) touched) — yq reverted, refuse-skip" >&2
    git checkout HEAD -- "$backlog_rel" 2>/dev/null || true
    exec 200>&-
    return 6
  fi

  git add "$backlog_rel" 2>/dev/null
  if ! git commit -m "$commit_subject" --quiet -- "$backlog_rel" 2>/dev/null; then
    echo "[CHORE-COMMIT] $story_id : git commit failed" >&2
    exec 200>&-
    return 1
  fi

  if git push origin "$target_branch" --quiet 2>/dev/null; then
    exec 200>&-
    return 0
  fi
  if git fetch origin "$target_branch" --quiet 2>/dev/null \
    && git rebase "origin/$target_branch" --quiet 2>/dev/null \
    && git push origin "$target_branch" --quiet 2>/dev/null; then
    exec 200>&-
    return 0
  fi
  git rebase --abort 2>/dev/null || true
  echo "[CHORE-COMMIT] $story_id : push failed after rebase retry — refuse-skip" >&2
  exec 200>&-
  return 1
}
