#!/usr/bin/env bash
# allocate-id.sh — flock-guarded epic/story ID allocator
# GAAI framework (OSS). Project-agnostic — no project-specific references.
#
# Usage:
#   allocate-id.sh epic                   Return next Epic ID (e.g., E221)
#   allocate-id.sh story <epic_prefix>   Return next Story ID (e.g., {EPIC}S{NN})
#   allocate-id.sh --help                Show help
#
# Env vars (all optional):
#   GAAI_BACKLOG_PATH        path to active.backlog.yaml (default: auto-detect from git root)
#   GAAI_RESERVATION_LEDGER  ledger file path (default: ~/.gaai/reservations/<repo_id>.tsv)
#   GAAI_RESERVATION_TTL_H   abandoned-reservation TTL in hours (default: 72)
#   GAAI_SCAN_REMOTE         scan remote branches for in-flight IDs (default: 1; 0/false/no/off disables)
#   GAAI_REMOTE              remote name to scan (default: origin)
#   GAAI_REMOTE_TIMEOUT      seconds to bound the remote scan before falling back (default: 5)
#
# The allocator serialises under an exclusive flock (Linux) or mkdir-spin (macOS) and computes
# next = max(backlog, ledger, remote-refs) + 1, writes a reservation row before returning, and
# prunes stale/landed entries on each run.
#
# Cross-worktree visibility: the ledger lives under ~/.gaai/reservations/ (outside any git
# worktree) and is keyed by a 12-char hash of the repo root path, so all local worktrees of
# the same repo share it before any branch merges.
#
# Cross-host visibility: the ledger is host-local and TTL-pruned, so it cannot see IDs reserved
# on another machine (a daemon host, a second clone, Cloud) nor an ID whose PR has stayed open
# past the TTL. Remote branch names are the only shared, durable record of an in-flight ID, so
# the allocator also scans `git ls-remote --heads <remote>` and folds the highest E<n>/E<n>S<nn>
# token found into the max. The same scan protects a still-on-a-branch ledger entry from being
# TTL-pruned. This augments — it does not replace — the ledger: a concurrent session that has
# not yet pushed a branch on another host remains invisible (irreducible without a shared backend).
#
# Graceful degradation: if flock/mkdir both fail, allocation proceeds with a stderr warning. If
# the ledger directory is unwritable, proceeds with backlog-only max and warns. If the remote
# scan fails or times out (and a remote IS configured), it warns and falls back to backlog+ledger;
# if no remote is configured (local-only repo), the scan is silently skipped.

set -euo pipefail

# ── Help ──────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
allocate-id.sh — flock-guarded GAAI ID allocator (OSS framework)

Usage:
  allocate-id.sh epic                   Return next Epic ID (e.g., E221)
  allocate-id.sh story <epic_prefix>   Return next Story ID (e.g., {EPIC}S{NN})
  allocate-id.sh --help                Show this help

Env vars (all optional):
  GAAI_BACKLOG_PATH        Path to active.backlog.yaml (default: auto-detect from git root)
  GAAI_RESERVATION_LEDGER  Ledger file (default: ~/.gaai/reservations/<repo_id>.tsv)
  GAAI_RESERVATION_TTL_H   Abandoned-reservation TTL in hours (default: 72)
  GAAI_SCAN_REMOTE         Scan remote branches for in-flight IDs (default: 1; 0/false/no/off off)
  GAAI_REMOTE              Remote name to scan (default: origin)
  GAAI_REMOTE_TIMEOUT      Seconds to bound the remote scan before fallback (default: 5)

Ledger format (TSV):
  # GAAI ID reservation ledger — do not edit manually
  E221        epic    <epoch_secs>
  {EPIC}S{NN} story   <epoch_secs>

The allocator computes next = max(highest-in-backlog, highest-in-ledger, highest-on-remote) + 1,
writes the new reservation to the ledger, then prints the ID on stdout. The remote source
serialises against IDs that live on pushed-but-unmerged branches on other hosts; the ledger
serialises local (not-yet-pushed) concurrent sessions on this host.
EOF
  exit 0
fi

# ── Mode validation ───────────────────────────────────────────────────────────
MODE="${1:-}"
EPIC_PREFIX=""

if [[ "$MODE" == "epic" ]]; then
  : # ok
elif [[ "$MODE" == "story" ]]; then
  EPIC_PREFIX="${2:-}"
  if [[ -z "$EPIC_PREFIX" ]]; then
    echo "allocate-id.sh: 'story' mode requires <epic_prefix> argument (e.g. E220)" >&2
    exit 1
  fi
  if [[ ! "$EPIC_PREFIX" =~ ^E[0-9]+$ ]]; then
    echo "allocate-id.sh: epic prefix must match E[0-9]+ (got '${EPIC_PREFIX}')" >&2
    exit 1
  fi
else
  echo "allocate-id.sh: unknown mode '${MODE:-<empty>}'. Use 'epic' or 'story <prefix>'." >&2
  exit 1
fi

# ── Repo identity (stable key across all worktrees of the same repo) ──────────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "allocate-id.sh: not inside a git repository" >&2
  exit 1
}

if command -v shasum >/dev/null 2>&1; then
  REPO_ID="$(printf '%s' "$REPO_ROOT" | shasum -a 256 | cut -c1-12)"
elif command -v sha256sum >/dev/null 2>&1; then
  REPO_ID="$(printf '%s' "$REPO_ROOT" | sha256sum | cut -c1-12)"
else
  REPO_ID="$(printf '%s' "$REPO_ROOT" | base64 2>/dev/null | tr -dc 'a-zA-Z0-9' | cut -c1-12)"
fi

# ── Paths ─────────────────────────────────────────────────────────────────────
DEFAULT_BACKLOG="${REPO_ROOT}/.gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG_PATH="${GAAI_BACKLOG_PATH:-$DEFAULT_BACKLOG}"
LEDGER_FILE="${GAAI_RESERVATION_LEDGER:-${HOME}/.gaai/reservations/${REPO_ID}.tsv}"
LOCK_FILE="${LEDGER_FILE}.lock"
LOCK_DIR="${LOCK_FILE}.d"
TTL_H="${GAAI_RESERVATION_TTL_H:-72}"

# ── Remote-scan configuration ─────────────────────────────────────────────────
GAAI_REMOTE="${GAAI_REMOTE:-origin}"
REMOTE_TIMEOUT="${GAAI_REMOTE_TIMEOUT:-5}"
SCAN_REMOTE=true
case "${GAAI_SCAN_REMOTE:-1}" in
  0|false|no|off|FALSE|NO|OFF) SCAN_REMOTE=false ;;
esac

# ── Scan remote branch names for in-flight IDs (read-only, runs BEFORE the lock) ──
# Cross-host serialisation primitive: a single `git ls-remote --heads` round-trip surfaces
# every ID that lives on a pushed-but-unmerged branch — the only shared, durable record an
# allocation on another host leaves behind. Kept outside the lock so a 5s network call never
# stalls a concurrent local allocator (the ledger read-modify-write under the lock stays fast).
REMOTE_HEADS_RAW=""

# Bounded `git ls-remote --heads <remote>` — prints "refs/heads/..." lines on success, returns
# non-zero on network failure/timeout. Prefer timeout(1)/gtimeout(1) when present: it kills the
# whole transport process group on expiry, so no orphaned git/transport-helper lingers. Otherwise
# fall back to backgrounding git DIRECTLY (not inside a pipe-subshell) so the bounded `kill "$pid"`
# targets the git process itself; awk runs afterwards in the foreground, leaving no grandchild to
# orphan. git's own exit status is captured via `wait`, so an empty-but-failed scan is never
# mistaken for "no branches" (which would silently drop the cross-host serialisation).
_ls_remote_heads() {
  local out_file
  out_file="$(mktemp "${TMPDIR:-/tmp}/gaai_lsremote.XXXXXX" 2>/dev/null)" || return 1

  local tobin=""
  if   command -v timeout  >/dev/null 2>&1; then tobin="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then tobin="gtimeout"; fi

  if [[ -n "$tobin" ]]; then
    if "$tobin" "${REMOTE_TIMEOUT}s" git ls-remote --heads "$GAAI_REMOTE" >"$out_file" 2>/dev/null; then
      awk '{print $2}' "$out_file" 2>/dev/null || true
      rm -f "$out_file" 2>/dev/null || true
      return 0
    fi
    rm -f "$out_file" 2>/dev/null || true
    return 1
  fi

  # Fallback (no timeout(1), common on stock macOS): background git directly and bound it by PID.
  git ls-remote --heads "$GAAI_REMOTE" >"$out_file" 2>/dev/null &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$(( waited + 1 ))
    if (( waited >= REMOTE_TIMEOUT )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f "$out_file" 2>/dev/null || true
      return 1
    fi
  done
  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  if (( rc != 0 )); then rm -f "$out_file" 2>/dev/null || true; return 1; fi
  awk '{print $2}' "$out_file" 2>/dev/null || true
  rm -f "$out_file" 2>/dev/null || true
  return 0
}

if [[ "$SCAN_REMOTE" == "true" ]] && git remote get-url "$GAAI_REMOTE" >/dev/null 2>&1; then
  if ! REMOTE_HEADS_RAW="$(_ls_remote_heads)"; then
    REMOTE_HEADS_RAW=""
    echo "allocate-id.sh: WARNING: remote scan of '${GAAI_REMOTE}' failed/timed out after ${REMOTE_TIMEOUT}s — falling back to backlog+ledger max; an unmerged ID reserved on another host may collide" >&2
  fi
fi

# ── Ensure ledger directory exists ────────────────────────────────────────────
LEDGER_WRITABLE=true
if ! mkdir -p "$(dirname "$LEDGER_FILE")" 2>/dev/null; then
  echo "allocate-id.sh: WARNING: cannot create ledger dir $(dirname "$LEDGER_FILE") — ledger disabled" >&2
  LEDGER_WRITABLE=false
fi

# ── Acquire portable lock (Linux: flock fd, macOS: mkdir spin) ────────────────
# LOCK_TYPE tracks what cleanup is needed: "none" | "flock" | "mkdir"
LOCK_TYPE="none"

_release_lock() {
  case "$LOCK_TYPE" in
    flock) exec 9>&- 2>/dev/null || true ;;
    mkdir) rmdir "$LOCK_DIR" 2>/dev/null || true ;;
  esac
  LOCK_TYPE="none"
}
trap '_release_lock' EXIT INT TERM

if [[ "$LEDGER_WRITABLE" == "true" ]]; then
  if command -v flock >/dev/null 2>&1; then
    # Linux: fd 9-based exclusive flock (bash 3.x compatible — uses fixed fd, not {var}>)
    touch "$LOCK_FILE" 2>/dev/null || true
    exec 9>>"$LOCK_FILE"
    LOCK_TYPE="flock"  # mark fd open so _release_lock always closes it
    if ! flock -x -w 5 9 2>/dev/null; then
      echo "allocate-id.sh: WARNING: flock -w 5 timed out — allocation may not be atomic" >&2
    fi
  else
    # macOS: mkdir-based atomic spin (5 second timeout)
    WAITED=0
    WAIT_MAX=5
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
      sleep 1
      WAITED=$(( WAITED + 1 ))
      if (( WAITED >= WAIT_MAX )); then
        echo "allocate-id.sh: WARNING: mkdir lock timeout after ${WAIT_MAX}s — allocation may not be atomic" >&2
        break
      fi
    done
    LOCK_TYPE="mkdir"
  fi
else
  echo "allocate-id.sh: WARNING: flock unavailable — allocation not atomic across concurrent sessions" >&2
fi

# ── Prune stale and landed ledger entries ─────────────────────────────────────
NOW_EPOCH="$(date +%s 2>/dev/null)" || NOW_EPOCH="0"
TTL_SECS=$(( TTL_H * 3600 ))
LEDGER_KEPT=""

# An ID is "still live" if its exact token appears in a remote branch name. A fixed-string
# match is intentional: a false positive only keeps a reservation slightly longer (conservative,
# never causes a collision), whereas a false negative would re-open the TTL-prune collision hole.
_id_on_remote() {
  [[ -n "$REMOTE_HEADS_RAW" ]] || return 1
  printf '%s\n' "$REMOTE_HEADS_RAW" | grep -qF "$1"
}

if [[ -f "$LEDGER_FILE" ]]; then
  while IFS=$'\t' read -r entry_id entry_kind entry_epoch; do
    # Skip blank lines and comment/header lines
    [[ -z "$entry_id" || "$entry_id" == \#* ]] && continue
    [[ -z "$entry_kind" || -z "$entry_epoch" ]] && continue

    # Prune: ID already appears in the merged backlog (landed)
    if [[ -f "$BACKLOG_PATH" ]] && grep -q "id: ${entry_id}" "$BACKLOG_PATH" 2>/dev/null; then
      continue
    fi

    # Prune: reservation older than TTL (abandoned) — UNLESS the ID is still live on a remote
    # branch (an open PR that has simply outlived the TTL; pruning it would let the number be
    # re-allocated and collide when the PR merges).
    if [[ "$NOW_EPOCH" -gt 0 && "$entry_epoch" =~ ^[0-9]+$ ]]; then
      age=$(( NOW_EPOCH - entry_epoch ))
      if (( age > TTL_SECS )) && ! _id_on_remote "$entry_id"; then
        continue
      fi
    fi

    LEDGER_KEPT="${LEDGER_KEPT}${entry_id}	${entry_kind}	${entry_epoch}"$'\n'
  done < "$LEDGER_FILE" || true

  # Rewrite ledger without pruned entries
  if [[ "$LEDGER_WRITABLE" == "true" ]]; then
    {
      printf '# GAAI ID reservation ledger — do not edit manually\n'
      printf '%s' "$LEDGER_KEPT"
    } > "${LEDGER_FILE}.tmp.$$" && mv "${LEDGER_FILE}.tmp.$$" "$LEDGER_FILE" || true
  fi
fi

# ── Max-extraction helpers ────────────────────────────────────────────────────

_backlog_max_epic() {
  [[ -f "$BACKLOG_PATH" ]] || { echo 0; return; }
  local result
  result="$(grep -oE 'E[0-9]+' "$BACKLOG_PATH" 2>/dev/null \
    | sed 's/^E//' \
    | sort -n | tail -1)" || true
  # Force base-10 so a leading-zero value never octal-parses in a caller's $(( )).
  echo "$(( 10#${result:-0} ))"
}

_backlog_max_story() {
  local prefix="$1"
  [[ -f "$BACKLOG_PATH" ]] || { echo 0; return; }
  local result
  result="$(grep -oE "${prefix}S[0-9]+" "$BACKLOG_PATH" 2>/dev/null \
    | grep -oE '[0-9]+$' \
    | sort -n | tail -1)" || true
  # Force base-10: story numbers are zero-padded (S08/S09 → "08"/"09"), which
  # bash arithmetic would otherwise reject as invalid octal.
  echo "$(( 10#${result:-0} ))"
}

_ledger_max_epic() {
  [[ -f "$LEDGER_FILE" ]] || { echo 0; return; }
  awk -F'\t' '$1 !~ /^#/ && $2=="epic" { sub(/^E/, "", $1); if ($1+0 > max) max=$1+0 } END { print max+0 }' \
    "$LEDGER_FILE" 2>/dev/null || echo 0
}

_ledger_max_story() {
  local prefix="$1"
  [[ -f "$LEDGER_FILE" ]] || { echo 0; return; }
  awk -F'\t' -v p="$prefix" \
    '$1 !~ /^#/ && $2=="story" && $1 ~ ("^"p"S[0-9]+$") { sub("^"p"S0*", "", $1); if ($1+0 > max) max=$1+0 } END { print max+0 }' \
    "$LEDGER_FILE" 2>/dev/null || echo 0
}

# Remote-ref maxima — extract the highest epic / story-for-prefix token from the branch names
# captured before the lock. Empty REMOTE_HEADS_RAW (scan disabled, no remote, or scan failed)
# yields 0, so this source is simply a no-op in those cases.
_remote_max_epic() {
  [[ -n "$REMOTE_HEADS_RAW" ]] || { echo 0; return; }
  # Extract E<n> tokens but reject word-embedded false matches like `E2E-test-harness` (where the
  # E<n> is followed by another letter). A real epic token is followed by `S<digit>` (story branch),
  # a separator, or end-of-name. Direction-safe regardless: an over- or under-match only moves the
  # next ID forward, never causes a collision.
  printf '%s\n' "$REMOTE_HEADS_RAW" | awk '
    { s = $0
      while (match(s, /E[0-9]+/)) {
        tok  = substr(s, RSTART, RLENGTH)
        rest = substr(s, RSTART + RLENGTH)
        if (rest ~ /^S[0-9]/ || rest == "" || rest ~ /^[^0-9A-Za-z]/) {
          n = substr(tok, 2) + 0
          if (n > max) max = n
        }
        s = rest
      }
    } END { print max + 0 }' 2>/dev/null || echo 0
}

_remote_max_story() {
  local prefix="$1"
  [[ -n "$REMOTE_HEADS_RAW" ]] || { echo 0; return; }
  local result
  result="$(printf '%s\n' "$REMOTE_HEADS_RAW" | grep -oE "${prefix}S[0-9]+" 2>/dev/null \
    | grep -oE '[0-9]+$' \
    | sort -n | tail -1)" || true
  echo "$(( 10#${result:-0} ))"
}

# ── Compute next ID ───────────────────────────────────────────────────────────
if [[ "$MODE" == "epic" ]]; then
  MAX_BACKLOG="$(_backlog_max_epic)"
  MAX_LEDGER="$(_ledger_max_epic)"
  MAX_REMOTE="$(_remote_max_epic)"
  MAX_BACKLOG="${MAX_BACKLOG:-0}"
  MAX_LEDGER="${MAX_LEDGER:-0}"
  MAX_REMOTE="${MAX_REMOTE:-0}"
  MAX=$(( MAX_BACKLOG > MAX_LEDGER ? MAX_BACKLOG : MAX_LEDGER ))
  MAX=$(( MAX > MAX_REMOTE ? MAX : MAX_REMOTE ))
  NEXT_NUM=$(( MAX + 1 ))
  NEW_ID="E${NEXT_NUM}"
else
  MAX_BACKLOG="$(_backlog_max_story "$EPIC_PREFIX")"
  MAX_LEDGER="$(_ledger_max_story "$EPIC_PREFIX")"
  MAX_REMOTE="$(_remote_max_story "$EPIC_PREFIX")"
  MAX_BACKLOG="${MAX_BACKLOG:-0}"
  MAX_LEDGER="${MAX_LEDGER:-0}"
  MAX_REMOTE="${MAX_REMOTE:-0}"
  MAX=$(( MAX_BACKLOG > MAX_LEDGER ? MAX_BACKLOG : MAX_LEDGER ))
  MAX=$(( MAX > MAX_REMOTE ? MAX : MAX_REMOTE ))
  NEXT_NUM=$(( MAX + 1 ))
  NEXT_PADDED="$(printf '%02d' "$NEXT_NUM")"
  NEW_ID="${EPIC_PREFIX}S${NEXT_PADDED}"
fi

# ── Write reservation to ledger ───────────────────────────────────────────────
if [[ "$LEDGER_WRITABLE" == "true" ]]; then
  {
    if [[ ! -f "$LEDGER_FILE" ]]; then
      printf '# GAAI ID reservation ledger — do not edit manually\n'
    fi
    printf '%s\t%s\t%s\n' "$NEW_ID" "$MODE" "$NOW_EPOCH"
  } >> "$LEDGER_FILE" 2>/dev/null || {
    echo "allocate-id.sh: WARNING: cannot write reservation to ${LEDGER_FILE}" >&2
  }
fi

# ── Output ────────────────────────────────────────────────────────────────────
printf '%s\n' "$NEW_ID"
