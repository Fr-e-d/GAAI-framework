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
# Used when flock/yq/yq-v4 are unavailable.
_chore_option_a_fallback() {
  local story_id="$1" commit_subject="$2"; shift 2
  local backlog_file="${BACKLOG_FILE}" backlog_rel="${BACKLOG_REL}"
  local target_branch="${TARGET_BRANCH:-staging}"
  local warn_flag="${LOCK_DIR}/.chore-helper-missing.warning"
  if [[ ! -f "$warn_flag" ]]; then
    echo "[CHORE-COMMIT] WARNING: flock/yq/yq-v4 unavailable — using Option A fallback" >&2
    echo "[CHORE-COMMIT] Install: macOS: brew install util-linux yq  Linux: apt install util-linux yq" >&2
    touch "$warn_flag" 2>/dev/null || true
  fi
  if ! git diff --quiet HEAD -- "$backlog_rel" 2>/dev/null; then
    echo "[CHORE-COMMIT] $story_id : working-tree drift — refuse-skip (Option A)" >&2
    return 6
  fi
  while [[ $# -ge 2 ]]; do
    "${SCHEDULER:-}" --set-field "$story_id" "$1" "$2" "$backlog_file" 2>/dev/null || true
    shift 2
  done
  git add "$backlog_rel" 2>/dev/null
  git diff --cached --quiet && return 0
  if ! git commit -m "$commit_subject" --quiet -- "$backlog_rel" 2>/dev/null; then
    # Transactional rollback : commit failed → revert disk write to prevent
    # orphan drift blocking subsequent stories (RC: prior orphan-drift incident).
    git reset HEAD -- "$backlog_rel" 2>/dev/null || true
    git checkout HEAD -- "$backlog_rel" 2>/dev/null || true
    echo "[CHORE-COMMIT] $story_id : commit failed — disk write rolled back" >&2
    return 1
  fi
  if ! git push origin "$target_branch" --quiet 2>/dev/null; then
    # Push failed → try rebase-retry once
    if git fetch origin "$target_branch" --quiet 2>/dev/null \
      && git rebase "origin/$target_branch" --quiet 2>/dev/null \
      && git push origin "$target_branch" --quiet 2>/dev/null; then
      return 0
    fi
    # Rebase or retry-push failed → reset the local commit + restore disk to HEAD
    # (HEAD here is post-fetch origin/branch since rebase failed cleanly aborted)
    git rebase --abort 2>/dev/null || true
    git reset --soft HEAD~1 2>/dev/null || true
    git reset HEAD -- "$backlog_rel" 2>/dev/null || true
    git checkout HEAD -- "$backlog_rel" 2>/dev/null || true
    echo "[CHORE-COMMIT] $story_id : push failed — local commit + disk rolled back" >&2
    return 1
  fi
  return 0
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
