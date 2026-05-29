#!/usr/bin/env bash
# gaai-claim.sh — run a backlog/staging write-burst while holding the SAME staging
# lock the delivery daemon uses, so an interactive Discovery session and the daemon
# are mutually exclusive on writes to the backlog and the `staging` branch.
#
# WHY: the daemon continuously `git reset --hard origin/staging` its working tree.
# The only durable state is `origin/staging`. A Discovery edit that is not committed
# AND pushed under the lock can be clobbered by a concurrent daemon reset/commit.
# This wrapper acquires the daemon's staging lock for the whole burst, so the daemon
# waits; the burst commits + pushes to origin; once on origin the daemon's reset
# preserves it.
#
# USAGE:
#   gaai-claim.sh -- <command...>
#
# The command should be the full atomic burst, e.g.:
#   gaai-claim.sh -- bash -c '
#     "$SCHED" --set-status E01S01 refined "$BACKLOG" &&
#     git add <files> && git commit -m "..." && git push origin "$BRANCH"
#   '
#
# CONTRACT (the Discovery claim protocol — see orchestration.rules.md):
#   1. Backlog mutations go through backlog-scheduler.sh --set-status/--set-field
#      ONLY (atomic, daemon-format-compatible, field-scoped → clean rebase merges).
#      Never raw whole-file rewrites of active.backlog.yaml.
#   2. The burst commits AND pushes to the staging branch (origin is the source of
#      truth; the local working tree is ephemeral under the daemon's reset).
#   3. Run on the primary working tree (its installed deps let the pre-push hooks
#      pass) — no throwaway worktree needed.
#
# Environment overrides (else derived):
#   GAAI_PROJECT_ROOT   project root (default: git toplevel, else $PWD)
#   GAAI_PROJECT_DIR    GAAI project dir (default: $GAAI_PROJECT_ROOT/.gaai/project)
#   GAAI_CLAIM_LOCK_WAIT macOS lock wait seconds before timeout (default 180)
set -euo pipefail

PROJECT_ROOT="${GAAI_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
GAAI_PROJECT_DIR="${GAAI_PROJECT_DIR:-$PROJECT_ROOT/.gaai/project}"
LOCK_DIR="$GAAI_PROJECT_DIR/contexts/backlog/.delivery-locks"
STAGING_LOCK="$LOCK_DIR/.staging.lock"
WAIT_MAX="${GAAI_CLAIM_LOCK_WAIT:-180}"

mkdir -p "$LOCK_DIR"

# Strip the leading "--" separator if present.
[[ "${1:-}" == "--" ]] && shift
if [[ $# -eq 0 ]]; then
  echo "gaai-claim.sh: no command given. Usage: gaai-claim.sh -- <command...>" >&2
  exit 2
fi

# Portable staging lock — MUST mirror delivery-daemon.sh with_staging_lock() so the
# daemon and Discovery contend on the same primitive (flock on Linux, mkdir on macOS).
if command -v flock >/dev/null 2>&1; then
  : > "$STAGING_LOCK" 2>/dev/null || true
  exec flock "$STAGING_LOCK" "$@"
else
  lockdir="${STAGING_LOCK}.d"
  waited=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if (( waited >= WAIT_MAX )); then
      echo "gaai-claim.sh: staging lock timeout after ${WAIT_MAX}s (daemon busy?)" >&2
      exit 1
    fi
  done
  trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT
  "$@"
fi
