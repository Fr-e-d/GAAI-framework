#!/usr/bin/env bash
# commit-retry-containment.sh — classify commit-phase retry progress without
# treating daemon-authored delivery evidence as implementation progress.

_commit_retry_state_path() {
  printf '%s/.commit-deaths-%s\n' "$LOCK_DIR" "$1"
}

_commit_retry_observation_path() {
  printf '%s/.commit-retry-observation-%s\n' "$LOCK_DIR" "$1"
}

_commit_retry_stall_marker_path() {
  printf '%s/.commit-retry-stalled-%s\n' "$LOCK_DIR" "$1"
}

_commit_retry_sanitize_outcome() {
  local outcome="${1:-wrapper_exit_nonzero}"
  outcome=$(printf '%s' "$outcome" | tr '\r\n|' '___' \
    | LC_ALL=C sed 's/[^A-Za-z0-9:._\/-]/_/g' | LC_ALL=C cut -c1-160)
  printf '%s\n' "${outcome:-wrapper_exit_nonzero}"
}

_commit_retry_write_observation() {
  local story_id="$1" outcome marker tmp
  outcome=$(_commit_retry_sanitize_outcome "${2:-}")
  marker=$(_commit_retry_observation_path "$story_id")
  tmp="${marker}.tmp.$$"
  mkdir -p "$LOCK_DIR" 2>/dev/null || return 1
  (
    umask 077
    printf '%s\n' "$outcome" > "$tmp"
  ) || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  mv "$tmp" "$marker" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null || true; return 1; }
}

_commit_retry_write_stall_marker() {
  local story_id="$1" outcome cycles="$3" threshold="$4" marker tmp
  outcome=$(_commit_retry_sanitize_outcome "${2:-}")
  marker=$(_commit_retry_stall_marker_path "$story_id")
  tmp="${marker}.tmp.$$"
  mkdir -p "$LOCK_DIR" 2>/dev/null || return 1
  (
    umask 077
    printf 'story_id=%s\noutcome=%s\ncycles=%s\nthreshold=%s\ncreated_at=%s\n' \
      "$story_id" "$outcome" "$cycles" "$threshold" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$tmp"
  ) || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  mv "$tmp" "$marker" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null || true; return 1; }
}

_commit_retry_sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    return 1
  fi
}

_commit_retry_content_digest() {
  local story_id="$1" worktree_path="$2" base_ref="$3" digest
  digest=$(set -o pipefail; git -C "$worktree_path" diff \
    --binary --full-index --no-ext-diff --no-textconv \
    "${base_ref}...HEAD" -- . \
    ':(exclude).gaai/project/contexts/backlog/active.backlog.yaml' \
    ':(exclude).gaai/core/skills/skills-index.yaml' \
    ':(exclude).gaai/project/skills/skills-index.yaml' \
    ":(exclude,glob).gaai/project/contexts/artefacts/**/${story_id}.*" \
    2>/dev/null | _commit_retry_sha256_stdin) || return 1
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf 'diff:%s\n' "$digest"
}

# Print: count|outcome|classification
_commit_retry_observe() {
  local story_id="$1" worktree_path="$2" base_ref="$3"
  local threshold="${4:-${COMMIT_PHASE_RETRY_THRESHOLD:-3}}"
  local state marker previous_count=0 previous_digest="" previous_outcome=""
  local previous_stall_pending=0 outcome digest count classification tmp stall_pending=0
  state=$(_commit_retry_state_path "$story_id")
  marker=$(_commit_retry_observation_path "$story_id")

  [[ "$threshold" =~ ^[1-9][0-9]*$ ]] || return 1
  (( threshold > 1000 )) && threshold=1000

  if [[ -f "$state" ]]; then
    previous_count=$(awk -F= '$1=="count" {print $2; exit}' "$state" 2>/dev/null || true)
    previous_digest=$(awk -F= '$1=="content_digest" {sub(/^[^=]*=/,""); print; exit}' "$state" 2>/dev/null || true)
    previous_outcome=$(awk -F= '$1=="outcome" {sub(/^[^=]*=/,""); print; exit}' "$state" 2>/dev/null || true)
    previous_stall_pending=$(awk -F= '$1=="stall_pending" {print $2; exit}' "$state" 2>/dev/null || true)
  fi
  [[ "$previous_count" =~ ^[0-9]+$ ]] || previous_count=0
  (( previous_count > 1000 )) && previous_count=1000

  # Once the threshold is reached, the state itself is the durable fail-closed
  # authority. A restart must retry stall persistence, never consume a missing
  # observation as a different outcome and buy another hosted run. Only the
  # operator-owned reset path (_commit_retry_clear) may reopen delivery.
  if [[ "$previous_stall_pending" == "1" ]]; then
    [[ "$previous_count" =~ ^[1-9][0-9]*$ && -n "$previous_outcome" ]] || return 1
    printf '%s|%s|stall_pending\n' "$previous_count" \
      "$(_commit_retry_sanitize_outcome "$previous_outcome")"
    return 0
  fi

  outcome=$(head -1 "$marker" 2>/dev/null || true)
  outcome=$(_commit_retry_sanitize_outcome "$outcome")
  digest=$(_commit_retry_content_digest "$story_id" "$worktree_path" "$base_ref") \
    || return 1

  if [[ -z "$previous_digest" || -z "$previous_outcome" ]]; then
    count=1; classification="initial"
  elif [[ "$digest" != "$previous_digest" ]]; then
    count=1; classification="content_changed"
  elif [[ "$outcome" != "$previous_outcome" ]]; then
    count=1; classification="outcome_changed"
  else
    count=$(( previous_count + 1 )); classification="repeated"
  fi
  (( count > 1000 )) && count=1000
  (( count >= threshold )) && stall_pending=1

  tmp="${state}.tmp.$$"
  (
    umask 077
    printf 'count=%s\ncontent_digest=%s\noutcome=%s\nstall_pending=%s\n' \
      "$count" "$digest" "$outcome" "$stall_pending" > "$tmp"
  ) || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  mv "$tmp" "$state" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  rm -f "$marker" 2>/dev/null || true
  printf '%s|%s|%s\n' "$count" "$outcome" "$classification"
}

_commit_retry_clear() {
  local story_id="$1"
  rm -f "$(_commit_retry_state_path "$story_id")" \
    "$(_commit_retry_state_path "$story_id").head" \
    "$(_commit_retry_observation_path "$story_id")" 2>/dev/null || true
}
