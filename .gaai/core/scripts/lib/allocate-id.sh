#!/usr/bin/env bash
# allocate-id.sh — Concurrent-safe epic/story ID allocator.
#
# Returns the next epic ID (or the next story ID for a given epic prefix),
# computed as max(highest merged ID in active.backlog.yaml, highest reserved
# ID in the host-stable ledger) + 1. Allocation is serialized under an
# exclusive flock so two racing invocations never receive the same ID.
# Reservations live in a ledger at a host-stable path keyed by repository
# identity, so an in-flight ID reserved by one Discovery session is visible to
# parallel sessions on the same host BEFORE any branch merges.
#
# Usage:
#   allocate-id.sh epic                 # → E221
#   allocate-id.sh story <EPIC_ID>      # → <EPIC_ID>S05    (EPIC_ID e.g. E220)
#
# Env overrides:
#   GAAI_LEDGER_DIR        base dir for the ledger   (default: $HOME/.gaai)
#   GAAI_LEDGER_TTL        stale-reservation seconds (default: 259200 = 72h)
#   GAAI_LEDGER_LOCK_WAIT  flock timeout seconds     (default: 30)
#   GAAI_BACKLOG_PATH      explicit backlog path     (default discovered)
#
# Exit 0 with the ID on stdout. Exit 1 on lock timeout or fatal error.
# If flock is unavailable, emits a WARNING to stderr and proceeds without a
# lock (best-effort). This is a SAME-HOST coordination primitive only: it does
# NOT coordinate sessions on different machines (documented limitation; rare
# for OSS standalone Discovery).
#
# Project-agnostic: contains no project-specific references. Works in any repo
# that ships the GAAI framework at <root>/.gaai/.

set -uo pipefail

GAAI_LEDGER_DIR="${GAAI_LEDGER_DIR:-$HOME/.gaai}"
GAAI_LEDGER_TTL="${GAAI_LEDGER_TTL:-259200}"
LOCK_WAIT="${GAAI_LEDGER_LOCK_WAIT:-30}"
LOCK_FD=200

warn() { echo "[allocate-id] WARNING: $*" >&2; }
err()  { echo "[allocate-id] ERROR: $*" >&2; }

usage() {
  cat >&2 <<EOF
Usage: allocate-id.sh epic
       allocate-id.sh story <EPIC_ID>   (e.g. story E220)
EOF
  exit 1
}

# --- repository key ---------------------------------------------------------
# All worktrees of the same repository share the same git common dir, so they
# hash to the same key → the same ledger file → cross-worktree visibility (AC2).
hash_string() {
  printf '%s' "$1" | {
    if   command -v shasum    >/dev/null 2>&1; then shasum    | cut -c1-12
    elif command -v sha1sum   >/dev/null 2>&1; then sha1sum   | cut -c1-12
    elif command -v md5sum    >/dev/null 2>&1; then md5sum    | cut -c1-12
    else cksum | cut -d' ' -f1 | head -c 12
    fi
  }
}

compute_repo_key() {
  local common_dir root
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || common_dir=""
  if [ -n "$common_dir" ]; then
    # Resolve a relative common-dir against the repo root so the hash is stable
    # regardless of the caller's working directory.
    case "$common_dir" in
      /*) : ;;
      *)
        root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
        [ -n "$root" ] && common_dir="$root/$common_dir"
        ;;
    esac
    hash_string "$common_dir"
    return
  fi
  warn "no git repo found — using host-global 'default' ledger key"
  printf 'default'
}

# --- backlog path -----------------------------------------------------------
resolve_backlog() {
  if [ -n "${GAAI_BACKLOG_PATH:-}" ]; then
    [ -f "$GAAI_BACKLOG_PATH" ] && { printf '%s' "$GAAI_BACKLOG_PATH"; return; }
  fi
  local root default_path
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  if [ -n "$root" ]; then
    default_path="$root/.gaai/project/contexts/backlog/active.backlog.yaml"
    [ -f "$default_path" ] && { printf '%s' "$default_path"; return; }
  fi
  return 0  # empty stdout = no backlog found
}

# Single awk pass over the backlog → epic numbers (one per line, no "E") and
# full story IDs (one per line), into two temp files.
backlog_extract() {
  local path="$1" epics="$2" stories="$3"
  awk -v E="$epics" -v S="$stories" '
    match($0, /^[[:space:]]*-[[:space:]]*id:[[:space:]]*E[0-9]+S[0-9]+/) {
      id = substr($0, RSTART, RLENGTH)
      sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", id)   # id = EXXXSYY
      print id > S
      e = id; sub(/S[0-9]+$/, "", e); sub(/^E/, "", e)
      print e > E
      next
    }
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*E[0-9]+[[:space:]]*$/ {
      e = $0; sub(/.*id:[[:space:]]*/, "", e); sub(/[[:space:]]+$/, "", e); sub(/^E/, "", e)
      print e > E
    }
  ' "$path"
}

max_int() {   # print max of a newline-separated integer file, or 0
  local f="$1"
  [ -s "$f" ] || { printf '0'; return; }
  sort -n "$f" | tail -1
}

max_story_num() {   # $1=stories file  $2=epic prefix "E220"  → max story number (0 if none)
  local f="$1" prefix="$2" nums
  nums="$(grep -E "^${prefix}S[0-9]+\$" "$f" 2>/dev/null | sed "s/^${prefix}S//")" || nums=""
  [ -n "$nums" ] || { printf '0'; return; }
  printf '%s' "$nums" | sort -n | tail -1
}

main() {
  local alloc_type="${1:-}" epic_prefix="${2:-}"

  case "$alloc_type" in
    epic) ;;
    story)
      [ -n "$epic_prefix" ] || { err "story allocation requires an EPIC_ID prefix (e.g. E220)"; usage; }
      printf '%s' "$epic_prefix" | grep -qE '^E[0-9]+$' \
        || { err "invalid EPIC_ID '$epic_prefix' (expected E<number>)"; exit 1; }
      ;;
    *) usage ;;
  esac

  local repo_key ledger_dir ledger_file backlog_path now
  repo_key="$(compute_repo_key)"
  ledger_dir="$GAAI_LEDGER_DIR/reservations"
  ledger_file="$ledger_dir/${repo_key}.ledger"
  now="$(date +%s)"

  backlog_path="$(resolve_backlog)"
  [ -z "$backlog_path" ] && warn "no active.backlog.yaml found — computing from ledger only"

  # Temp files for backlog-derived sets (landed epics / landed stories).
  local tmp_base epics_tmp stories_tmp
  tmp_base="$(mktemp -d "${TMPDIR:-/tmp}/allocate-id.XXXXXX")"
  epics_tmp="$tmp_base/epics"; stories_tmp="$tmp_base/stories"
  : > "$epics_tmp"; : > "$stories_tmp"
  trap 'rm -rf "$tmp_base"' EXIT

  [ -n "$backlog_path" ] && backlog_extract "$backlog_path" "$epics_tmp" "$stories_tmp"

  local max_backlog_epic max_backlog_story
  max_backlog_epic="$(max_int "$epics_tmp")"; max_backlog_epic="$((10#${max_backlog_epic:-0}))"
  max_backlog_story=0
  [ "$alloc_type" = story ] && { max_backlog_story="$(max_story_num "$stories_tmp" "$epic_prefix")"; max_backlog_story="$((10#${max_backlog_story:-0}))"; }

  # --- acquire lock --------------------------------------------------------
  mkdir -p "$ledger_dir" 2>/dev/null || { err "cannot create ledger dir $ledger_dir"; exit 1; }
  touch "$ledger_file"   2>/dev/null || { err "cannot touch ledger $ledger_file"; exit 1; }

  local have_lock=0
  if command -v flock >/dev/null 2>&1; then
    exec 200<>"$ledger_file"   # RW open, no truncate → lock stays on this inode
    if flock -w "$LOCK_WAIT" "$LOCK_FD"; then
      have_lock=1
    else
      err "lock timeout ${LOCK_WAIT}s on $ledger_file — aborting"
      exec 200>&- 2>/dev/null || true
      exit 1
    fi
  else
    warn "flock unavailable — race window possible; IDs may collide under extreme concurrency"
  fi

  # --- read + prune ledger, compute ledger max, collect survivors ----------
  local max_ledger_epic=0 max_ledger_story=0 surviving="" age ltype lid landed stale enum snum sid_epic
  if [ -s "$ledger_file" ]; then
    while IFS=$'\t' read -r age ltype lid || [ -n "$lid" ]; do
      [ -n "$lid" ] || continue
      case "$ltype" in epic|story) ;; *) continue ;; esac
      # Validate shape; skip malformed ledger lines.
      if [ "$ltype" = epic ]; then
        printf '%s' "$lid" | grep -qE '^E[0-9]+$' || continue
      else
        printf '%s' "$lid" | grep -qE '^E[0-9]+S[0-9]+$' || continue
      fi
      landed=0; stale=0
      [ "$(( now - age ))" -gt "$GAAI_LEDGER_TTL" ] 2>/dev/null && stale=1
      if [ "$ltype" = epic ]; then
        grep -qxF "${lid#E}" "$epics_tmp" && landed=1
      else
        grep -qxF "$lid" "$stories_tmp" && landed=1
      fi
      [ "$stale" -eq 1 ] || [ "$landed" -eq 1 ] && continue   # prune
      surviving+="${age}"$'\t'"${ltype}"$'\t'"${lid}"$'\n'
      if [ "$ltype" = epic ]; then
        enum=$((10#${lid#E}))
        [ "$enum" -gt "$max_ledger_epic" ] && max_ledger_epic="$enum"
      else
        sid_epic="${lid%S*}"
        if [ "$sid_epic" = "$epic_prefix" ]; then
          snum=$((10#${lid#${epic_prefix}S}))
          [ "$snum" -gt "$max_ledger_story" ] && max_ledger_story="$snum"
        fi
      fi
    done < "$ledger_file"
  fi

  # --- compute next ID -----------------------------------------------------
  local next new_id
  if [ "$alloc_type" = epic ]; then
    next=$(( max_backlog_epic > max_ledger_epic ? max_backlog_epic : max_ledger_epic ))
    next=$(( next + 1 ))
    new_id="E${next}"
  else
    next=$(( max_backlog_story > max_ledger_story ? max_backlog_story : max_ledger_story ))
    next=$(( next + 1 ))
    new_id="${epic_prefix}S$(printf '%02d' "$next")"
  fi

  # --- append reservation + rewrite ledger IN PLACE (same inode) -----------
  # Never mv over the ledger: the lock is bound to its inode. Truncate+rewrite
  # the existing inode so concurrent callers blocked on flock stay blocked.
  surviving+="${now}"$'\t'"${alloc_type}"$'\t'"${new_id}"$'\n'
  printf '%s' "$surviving" > "$ledger_file"

  [ "$have_lock" -eq 1 ] && exec 200>&- 2>/dev/null || true

  printf '%s\n' "$new_id"
  exit 0
}

main "$@"
