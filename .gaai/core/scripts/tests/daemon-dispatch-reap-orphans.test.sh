#!/usr/bin/env bash
# ── daemon-dispatch-reap-orphans.test.sh ──────────────────────────────────────
# _reap_worktree_orphans: reap orphaned worktree descendants (test runners, dev/
# build servers, worker pools) a delivery phase left running — the daemon-side
# memory-leak guard.
#
# T1: empty pattern → pkill is NOT invoked (safety: `pkill -f ""` would match every process)
# T2: pattern not ending in `-workspace` → pkill is NOT invoked (safety)
# T3: `<storyId>-workspace` pattern → pkill -9 -f invoked with that exact pattern
# T4: a full worktree path ending in `-workspace` → pkill -9 -f invoked with the path
#
# Run: bash .gaai/core/scripts/tests/daemon-dispatch-reap-orphans.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BACKLOG_FILE="/tmp/gaai-reap-test-backlog.yaml"
SCHEDULER="$(which true)"
export PROJECT_DIR BACKLOG_FILE SCHEDULER

source "$SCRIPT_DIR/../daemon-dispatch.sh" 2>/dev/null || true

# Mock pkill: record every invocation's args, one per line. Overrides the real
# binary for the duration of the test so no actual process is ever signalled.
PKILL_LOG="$(mktemp /tmp/gaai-reap-pkill-XXXXXX)"
pkill() { printf '%s\n' "$*" >> "$PKILL_LOG"; return 0; }
cleanup() { rm -f "$PKILL_LOG"; }
trap cleanup EXIT

reset_log() { : > "$PKILL_LOG"; }
pkill_calls() { local n; n=$(wc -l < "$PKILL_LOG" 2>/dev/null); echo "${n//[[:space:]]/}"; }

# ── T1: empty pattern → no pkill ─────────────────────────────────────────────
reset_log
_reap_worktree_orphans ""
if [[ "$(pkill_calls)" -eq 0 ]]; then
  pass "T1: empty pattern does not invoke pkill (no host-wide match)"
else
  fail "T1: empty pattern invoked pkill — DANGEROUS (got: $(cat "$PKILL_LOG"))"
fi

# ── T2: pattern not ending in -workspace → no pkill ──────────────────────────
reset_log
_reap_worktree_orphans "/Users/x/some/random/path"
if [[ "$(pkill_calls)" -eq 0 ]]; then
  pass "T2: non-'-workspace' pattern does not invoke pkill"
else
  fail "T2: non-'-workspace' pattern invoked pkill (got: $(cat "$PKILL_LOG"))"
fi

# ── T3: <storyId>-workspace pattern → pkill -9 -f <pattern> ───────────────────
reset_log
_reap_worktree_orphans "E203S02-workspace"
if [[ "$(pkill_calls)" -eq 1 ]] && grep -qx -- "-9 -f E203S02-workspace" "$PKILL_LOG"; then
  pass "T3: '<storyId>-workspace' invokes pkill -9 -f with the exact pattern"
else
  fail "T3: expected 'pkill -9 -f E203S02-workspace' (got: $(cat "$PKILL_LOG"))"
fi

# ── T4: full worktree path ending in -workspace → pkill -9 -f <path> ─────────
reset_log
WT="/Users/x/.gaai-worktrees/repo/E204S02-workspace"
_reap_worktree_orphans "$WT"
if [[ "$(pkill_calls)" -eq 1 ]] && grep -qx -- "-9 -f $WT" "$PKILL_LOG"; then
  pass "T4: full worktree path invokes pkill -9 -f with the path"
else
  fail "T4: expected 'pkill -9 -f $WT' (got: $(cat "$PKILL_LOG"))"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "  ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[[ "$FAIL_COUNT" -eq 0 ]]
