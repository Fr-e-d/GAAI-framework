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
#
# The allocator serialises under an exclusive flock (Linux) or mkdir-spin (macOS), reads both
# the backlog and a host-stable ledger to compute next = max(backlog, ledger) + 1, writes a
# reservation row before returning, and prunes stale/landed entries on each run.
#
# Cross-worktree visibility: the ledger lives under ~/.gaai/reservations/ (outside any git
# worktree) and is keyed by a 12-char hash of the repo root path, so all local worktrees of
# the same repo share it before any branch merges.
#
# Graceful degradation: if flock/mkdir both fail, allocation proceeds with a stderr warning.
# If the ledger directory is unwritable, proceeds with backlog-only max and warns.

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

Ledger format (TSV):
  # GAAI ID reservation ledger — do not edit manually
  E221        epic    <epoch_secs>
  {EPIC}S{NN} story   <epoch_secs>

The allocator computes next = max(highest-in-backlog, highest-in-ledger) + 1, writes the
new reservation to the ledger, then prints the ID on stdout.
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

if [[ -f "$LEDGER_FILE" ]]; then
  while IFS=$'\t' read -r entry_id entry_kind entry_epoch; do
    # Skip blank lines and comment/header lines
    [[ -z "$entry_id" || "$entry_id" == \#* ]] && continue
    [[ -z "$entry_kind" || -z "$entry_epoch" ]] && continue

    # Prune: ID already appears in the merged backlog (landed)
    if [[ -f "$BACKLOG_PATH" ]] && grep -q "id: ${entry_id}" "$BACKLOG_PATH" 2>/dev/null; then
      continue
    fi

    # Prune: reservation older than TTL (abandoned)
    if [[ "$NOW_EPOCH" -gt 0 && "$entry_epoch" =~ ^[0-9]+$ ]]; then
      age=$(( NOW_EPOCH - entry_epoch ))
      if (( age > TTL_SECS )); then
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

# ── Compute next ID ───────────────────────────────────────────────────────────
if [[ "$MODE" == "epic" ]]; then
  MAX_BACKLOG="$(_backlog_max_epic)"
  MAX_LEDGER="$(_ledger_max_epic)"
  MAX_BACKLOG="${MAX_BACKLOG:-0}"
  MAX_LEDGER="${MAX_LEDGER:-0}"
  MAX=$(( MAX_BACKLOG > MAX_LEDGER ? MAX_BACKLOG : MAX_LEDGER ))
  NEXT_NUM=$(( MAX + 1 ))
  NEW_ID="E${NEXT_NUM}"
else
  MAX_BACKLOG="$(_backlog_max_story "$EPIC_PREFIX")"
  MAX_LEDGER="$(_ledger_max_story "$EPIC_PREFIX")"
  MAX_BACKLOG="${MAX_BACKLOG:-0}"
  MAX_LEDGER="${MAX_LEDGER:-0}"
  MAX=$(( MAX_BACKLOG > MAX_LEDGER ? MAX_BACKLOG : MAX_LEDGER ))
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
