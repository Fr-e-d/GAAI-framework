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
CHORE_JOURNAL_OUTCOME=""
CHORE_JOURNAL_REASON=""
CHORE_JOURNAL_COMMIT=""
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

# Project all currently eligible lifecycle records from a fresh remote backlog
# object and publish a private-index commit through an explicit expected-old
# lease. The caller owns the shared staging lock; caller cutover is separate.
# Returns 0 for applied or clean no-op, 8 for retained pending/conflicted/invalid
# evidence with no independently applicable record, and 1 for closed failures.
chore_commit_project_journal() {
  local context="${1:-journal-projection}"
  local repo backlog_file backlog_rel target_branch journal_lib journal_root attempt_dir applied_attempt_dir
  local path_binding finalize_attempt counts counts_manifest
  local scratch snapshot projected manifest index_file base_sha base_blob result_blob base_tree new_tree candidate
  local applied waiting conflicted invalid attempt_path remote_sha before_head before_status push_rc=0
  CHORE_JOURNAL_OUTCOME=""; CHORE_JOURNAL_REASON=""; CHORE_JOURNAL_COMMIT=""
  case "$context" in
    journal-projection|daemon|dispatch|recovery|post-delivery-hook|pr-watcher) ;;
    *) CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="context_invalid"; return 1 ;;
  esac
  repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="input_invalid"; return 1; }
  backlog_file="${BACKLOG_FILE:-}"; backlog_rel="${BACKLOG_REL:-}"
  target_branch="${TARGET_BRANCH:-staging}"
  [[ -f "$backlog_file" && -n "$backlog_rel" && "$target_branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$ ]] || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="input_invalid"; return 1; }
  # Bind the Git path to the supplied backlog file itself. A second tracked
  # path with the same blob must never widen a journal record's authority.
  if ! path_binding=$(python3 - "$repo" "$backlog_file" "$backlog_rel" <<'PY'
import os, stat, sys, tempfile

repo_input, backlog_input, supplied_rel = sys.argv[1:4]

def normalize_temp_alias(path):
    path = os.path.abspath(path)
    temp_input = os.path.abspath(os.environ.get("TMPDIR", tempfile.gettempdir()))
    temp_root = os.path.realpath(temp_input)
    try:
        if os.path.commonpath([temp_input, path]) == temp_input:
            return os.path.join(temp_root, os.path.relpath(path, temp_input))
    except ValueError:
        pass
    return path

try:
    repo = normalize_temp_alias(repo_input)
    backlog = normalize_temp_alias(backlog_input)
    if os.path.realpath(repo) != repo or os.path.realpath(backlog) != backlog:
        raise ValueError
    mode = os.stat(backlog, follow_symlinks=False).st_mode
    if not stat.S_ISREG(mode) or os.path.commonpath([repo, backlog]) != repo:
        raise ValueError
    derived_rel = os.path.relpath(backlog, repo)
    if (os.path.isabs(supplied_rel) or os.path.normpath(supplied_rel) != supplied_rel
            or supplied_rel in {"", ".", ".."} or supplied_rel.startswith("../")
            or derived_rel != supplied_rel):
        raise ValueError
    print(f"{backlog}\t{derived_rel}")
except (OSError, ValueError):
    raise SystemExit(1)
PY
  ); then
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="backlog_path_invalid"; return 1
  fi
  IFS=$'\t' read -r backlog_file backlog_rel <<< "$path_binding"
  journal_lib="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/backlog-journal.sh"
  [[ -r "$journal_lib" ]] || { CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="journal_unavailable"; return 1; }
  # shellcheck source=lib/backlog-journal.sh
  source "$journal_lib"
  local backlog_dir
  backlog_dir=$(cd -P "$(dirname "$backlog_file")" && pwd -P) || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="backlog_path_invalid"; return 1; }
  journal_root="${GAAI_BACKLOG_JOURNAL_DIR:-$backlog_dir/.delivery-locks/journal}"
  attempt_dir="$journal_root/projections"; applied_attempt_dir="$journal_root/applied-projections"
  backlog_journal_prepare_projection_storage "$journal_root" || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="attempt_storage_unavailable"; return 1; }
  before_head=$(git rev-parse HEAD 2>/dev/null) || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="ambient_state_unavailable"; return 1; }
  before_status=$(git status --porcelain=v1 2>/dev/null) || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="ambient_state_unavailable"; return 1; }
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/gaai-backlog-projection.XXXXXX") || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="scratch_unavailable"; return 1; }
  snapshot="$scratch/base.yaml"; projected="$scratch/projected.yaml"; manifest="$scratch/manifest.json"
  index_file="$scratch/index"; rm -f "$index_file"
  cleanup_projection() { rm -rf "$scratch" 2>/dev/null || true; }

  if ! git fetch origin "$target_branch" --quiet 2>/dev/null; then
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="base_fetch_failed"; cleanup_projection; return 1
  fi
  base_sha=$(git rev-parse "origin/$target_branch" 2>/dev/null) || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="base_unresolvable"; cleanup_projection; return 1; }

  # Recover only attempts whose exact candidate is now proven in target history.
  local prior
  for prior in "$attempt_dir"/*.json; do
    [[ -f "$prior" && ! -L "$prior" ]] || continue
    if GAAI_BACKLOG_JOURNAL_DIR="$journal_root" \
        backlog_journal_finalize_projection "$prior" "$repo" "$backlog_rel" "$base_sha" >/dev/null 2>&1; then
      backlog_journal_archive_projection "$prior" "$applied_attempt_dir" \
        || { CHORE_JOURNAL_OUTCOME="retained"; CHORE_JOURNAL_REASON="archive_failed"; cleanup_projection; return 1; }
    fi
  done

  git show "${base_sha}:${backlog_rel}" > "$snapshot" 2>/dev/null || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="base_blob_missing"; cleanup_projection; return 1; }
  if ! GAAI_BACKLOG_JOURNAL_DIR="$journal_root" \
      backlog_journal_prepare_projection "$snapshot" "$base_sha" "$backlog_rel" "$projected" "$manifest"; then
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="projection_invalid"; cleanup_projection; return 1
  fi
  counts_manifest="$manifest"
  case "${GAAI_BACKLOG_PROJECTION_FAULT:-}" in
    counts_missing_manifest) counts_manifest="$manifest.missing" ;;
    counts_malformed_manifest) counts_manifest="$projected" ;;
  esac
  if ! counts=$(python3 - "$counts_manifest" 2>/dev/null <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    counts = json.load(handle)["counts"]
print(counts["applied"], counts["waiting"], counts["conflicted"], counts["invalid"])
PY
  ); then
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="projection_invalid"; cleanup_projection; return 1
  fi
  read -r applied waiting conflicted invalid <<< "$counts"
  [[ "$applied" =~ ^[0-9]+$ && "$waiting" =~ ^[0-9]+$ && "$conflicted" =~ ^[0-9]+$ \
      && "$invalid" =~ ^[0-9]+$ ]] || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="projection_invalid"; cleanup_projection; return 1; }
  if [[ "$applied" == "0" ]]; then
    if [[ "$waiting" == "0" && "$conflicted" == "0" && "$invalid" == "0" ]]; then
      CHORE_JOURNAL_OUTCOME="noop"; CHORE_JOURNAL_REASON="none"; cleanup_projection; return 0
    fi
    CHORE_JOURNAL_OUTCOME="pending"; CHORE_JOURNAL_REASON="no_eligible_record"; cleanup_projection; return 8
  fi
  [[ "${GAAI_BACKLOG_PROJECTION_FAULT:-}" != commit_failure ]] || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="commit_failed"; cleanup_projection; return 1; }
  result_blob=$(git hash-object -w -- "$projected" 2>/dev/null) || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="commit_failed"; cleanup_projection; return 1; }
  GIT_INDEX_FILE="$index_file" git read-tree "$base_sha" 2>/dev/null || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="commit_failed"; cleanup_projection; return 1; }
  GIT_INDEX_FILE="$index_file" git update-index --add --cacheinfo 100644 "$result_blob" "$backlog_rel" 2>/dev/null || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="commit_failed"; cleanup_projection; return 1; }
  new_tree=$(GIT_INDEX_FILE="$index_file" git write-tree 2>/dev/null) || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="commit_failed"; cleanup_projection; return 1; }
  candidate=$(printf '%s\n' "chore(framework): project lifecycle journal [$context]" \
    | git commit-tree "$new_tree" -p "$base_sha" 2>/dev/null) || {
      CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="commit_failed"; cleanup_projection; return 1; }
  [[ "$(git rev-parse "${candidate}^" 2>/dev/null)" == "$base_sha" ]] || {
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="commit_failed"; cleanup_projection; return 1; }
  attempt_path="$attempt_dir/${candidate}.json"
  local seal_manifest="$manifest"
  case "${GAAI_BACKLOG_PROJECTION_FAULT:-}" in
    seal_missing_manifest) seal_manifest="$manifest.missing" ;;
    seal_malformed_manifest) seal_manifest="$projected" ;;
  esac
  if ! GAAI_BACKLOG_JOURNAL_DIR="$journal_root" backlog_journal_seal_projection \
      "$seal_manifest" "$result_blob" "$candidate" "$new_tree" "$attempt_path"; then
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="seal_failed"; cleanup_projection; return 1
  fi
  if [[ "${GAAI_BACKLOG_PROJECTION_FAULT:-}" == before_push ]]; then
    CHORE_JOURNAL_OUTCOME="retained"; CHORE_JOURNAL_REASON="push_not_attempted"; cleanup_projection; return 1
  fi
  if git push origin "$candidate:refs/heads/$target_branch" \
      --force-with-lease="refs/heads/$target_branch:$base_sha" --quiet 2>/dev/null; then
    push_rc=0
  else
    push_rc=$?
  fi
  # Transport failure can still mean accepted; observe before classifying it.
  git fetch origin "$target_branch" --quiet 2>/dev/null || true
  remote_sha=$(git rev-parse "origin/$target_branch" 2>/dev/null || true)
  if [[ "${GAAI_BACKLOG_PROJECTION_FAULT:-}" == verification_failure ]]; then remote_sha=""; fi
  if [[ -z "$remote_sha" || "$remote_sha" != "$candidate" ]]; then
    CHORE_JOURNAL_OUTCOME="retained"
    if [[ $push_rc -ne 0 ]]; then CHORE_JOURNAL_REASON="lease_rejected"; else CHORE_JOURNAL_REASON="verification_failed"; fi
    cleanup_projection; return 1
  fi
  if [[ "${GAAI_BACKLOG_PROJECTION_FAULT:-}" == after_push ]]; then
    CHORE_JOURNAL_OUTCOME="retained"; CHORE_JOURNAL_REASON="interrupted_after_push"; cleanup_projection; return 1
  fi
  finalize_attempt="$attempt_path"
  case "${GAAI_BACKLOG_PROJECTION_FAULT:-}" in
    finalize_missing_attempt) finalize_attempt="$attempt_path.missing" ;;
    finalize_malformed_attempt) finalize_attempt="$manifest" ;;
  esac
  if [[ "${GAAI_BACKLOG_PROJECTION_FAULT:-}" == finalize_failure ]] \
     || ! GAAI_BACKLOG_JOURNAL_DIR="$journal_root" \
        backlog_journal_finalize_projection "$finalize_attempt" "$repo" "$backlog_rel" "$remote_sha"; then
    CHORE_JOURNAL_OUTCOME="retained"; CHORE_JOURNAL_REASON="finalization_failed"; cleanup_projection; return 1
  fi
  if [[ "${GAAI_BACKLOG_PROJECTION_FAULT:-}" == archive_failure ]]; then
    CHORE_JOURNAL_OUTCOME="retained"; CHORE_JOURNAL_REASON="archive_interrupted"; cleanup_projection; return 1
  fi
  backlog_journal_archive_projection "$attempt_path" "$applied_attempt_dir" \
    || { CHORE_JOURNAL_OUTCOME="retained"; CHORE_JOURNAL_REASON="archive_failed"; cleanup_projection; return 1; }
  if [[ "$(git rev-parse HEAD 2>/dev/null)" != "$before_head" \
      || "$(git status --porcelain=v1 2>/dev/null)" != "$before_status" ]]; then
    CHORE_JOURNAL_OUTCOME="rejected"; CHORE_JOURNAL_REASON="ambient_worktree_changed"; cleanup_projection; return 1
  fi
  CHORE_JOURNAL_OUTCOME="applied"; CHORE_JOURNAL_REASON="none"; CHORE_JOURNAL_COMMIT="$candidate"
  cleanup_projection
  return 0
}

# _commit_accumulated_backlog_drift <story_id> <backlog_rel> <target_branch> <context>
# Commits any uncommitted backlog diff and pushes with push-race rebase+retry.
# Returns: 0 = success (no diff OR diff committed+pushed), 6 = genuine rebase-conflict|commit-failure,
#          7 = push-race discard (rebase succeeded but the retry push also failed — the local drift
#          commit was reset away and never landed on origin; distinct from 6 so callers can tell a
#          discarded-but-otherwise-clean commit apart from a genuine conflict/commit failure).
# Must be called with cwd=PROJECT_DIR (callers are responsible for cd).
_commit_accumulated_backlog_drift() {
  local story_id="$1" backlog_rel="$2" target_branch="$3" context="${4:-daemon}"
  if git diff --quiet HEAD -- "$backlog_rel" 2>/dev/null; then
    return 0
  fi
  if git add "$backlog_rel" 2>/dev/null \
     && git commit -m "chore(daemon): commit accumulated wrapper-progress writes [$context $story_id]" \
          --quiet -- "$backlog_rel" 2>/dev/null; then
    if ! git push origin "HEAD:$target_branch" --quiet 2>/dev/null; then
      git fetch origin "$target_branch" --quiet 2>/dev/null || true
      if git rebase "origin/$target_branch" --quiet 2>/dev/null; then
        if ! git push origin "HEAD:$target_branch" --quiet 2>/dev/null; then
          git reset --hard "origin/$target_branch" --quiet 2>/dev/null || true
          echo "[COMMIT-DRIFT] $story_id : push-race re-sync to origin — local drift commit discarded, NOT landed [$context]" >&2
          return 7
        fi
      else
        git rebase --abort 2>/dev/null || true
        git reset --hard "origin/$target_branch" --quiet 2>/dev/null || true
        echo "[COMMIT-DRIFT] $story_id : genuine rebase conflict [$context]" >&2
        return 6
      fi
    fi
    echo "[COMMIT-DRIFT] $story_id : committed accumulated backlog drift [$context]" >&2
  else
    git reset HEAD -- "$backlog_rel" 2>/dev/null || true
    echo "[COMMIT-DRIFT] $story_id : drift commit failed [$context]" >&2
    return 6
  fi
  return 0
}

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
  local _cad_rc=0
  _commit_accumulated_backlog_drift "$story_id" "$backlog_rel" "$target_branch" "pre-mark" \
    || _cad_rc=$?
  if [[ "$_cad_rc" -eq 6 ]]; then
    _chore_a_done 6
    return $?
  elif [[ "$_cad_rc" -eq 7 ]]; then
    # A different story's drift commit was discarded by a push-race (see
    # _commit_accumulated_backlog_drift rc=7). That is not a reason to refuse
    # THIS story's own write — record it for audit and proceed to the field
    # write below (non-blocking; the discarded drift itself is reported by
    # whichever caller owns it as its own failure).
    printf '%s|%s|pre-mark-drift-discarded-rc7\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$story_id" \
      >> "${LOCK_DIR:-.}/.chore-drift-discarded.audit" 2>/dev/null || true
    echo "[CHORE-COMMIT] $story_id : pre-mark drift discarded by push-race (rc=7) — proceeding with own write" >&2
  fi
  while [[ $# -ge 2 ]]; do
    "${SCHEDULER:-}" --set-field "$story_id" "$1" "$2" "$backlog_file" 2>/dev/null || true
    shift 2
  done
  git add "$backlog_rel" 2>/dev/null
  # NOTE: no early-return on "no new staged diff" here. A clean cached-diff can
  # mean either (a) truly nothing to do, OR (b) the target value is already
  # committed to local HEAD but was never pushed (committed-but-unpushed flip —
  # the deadlock this story fixes). Both cases must still attempt the push
  # below so origin gets verified/landed either way; success is never reported
  # on local state alone (AC1/AC2).
  local _committed_now=0
  if ! git diff --cached --quiet; then
    if ! git commit -m "$commit_subject" --quiet -- "$backlog_rel" 2>/dev/null; then
      # Transactional rollback : commit failed → revert disk write to prevent
      # orphan drift blocking subsequent stories (RC: prior orphan-drift incident).
      git reset HEAD -- "$backlog_rel" 2>/dev/null || true
      git checkout HEAD -- "$backlog_rel" 2>/dev/null || true
      echo "[CHORE-COMMIT] $story_id : commit failed — disk write rolled back" >&2
      _chore_a_done 1
      return $?
    fi
    _committed_now=1
  fi
  if ! git push origin "HEAD:$target_branch" --quiet 2>/dev/null; then
    # Push failed → try rebase-retry once
    if git fetch origin "$target_branch" --quiet 2>/dev/null \
      && git rebase "origin/$target_branch" --quiet 2>/dev/null \
      && git push origin "HEAD:$target_branch" --quiet 2>/dev/null; then
      _chore_a_done 0
      return $?
    fi
    # Rebase or retry-push failed → cannot land on origin.
    git rebase --abort 2>/dev/null || true
    if [[ "$_committed_now" -eq 1 ]]; then
      # Only roll back a commit THIS call made — a pre-existing (not-ours)
      # committed-but-unpushed HEAD must be left in place, not discarded.
      git reset --soft HEAD~1 2>/dev/null || true
      git reset HEAD -- "$backlog_rel" 2>/dev/null || true
      git checkout HEAD -- "$backlog_rel" 2>/dev/null || true
    fi
    echo "[CHORE-COMMIT] $story_id : push failed — cannot land on origin (RECONCILE_UNLANDED)" >&2
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
  if git push origin "HEAD:$target_branch" --quiet 2>/dev/null; then
    exec 200>&-
    return 0
  fi
  if git fetch origin "$target_branch" --quiet 2>/dev/null \
    && git rebase "origin/$target_branch" --quiet 2>/dev/null \
    && git push origin "HEAD:$target_branch" --quiet 2>/dev/null; then
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

  if git push origin "HEAD:$target_branch" --quiet 2>/dev/null; then
    exec 200>&-
    return 0
  fi
  if git fetch origin "$target_branch" --quiet 2>/dev/null \
    && git rebase "origin/$target_branch" --quiet 2>/dev/null \
    && git push origin "HEAD:$target_branch" --quiet 2>/dev/null; then
    exec 200>&-
    return 0
  fi
  git rebase --abort 2>/dev/null || true
  echo "[CHORE-COMMIT] $story_id : push failed after rebase retry — refuse-skip" >&2
  exec 200>&-
  return 1
}
