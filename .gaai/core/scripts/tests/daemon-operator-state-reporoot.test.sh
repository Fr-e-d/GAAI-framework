#!/usr/bin/env bash
# Regression test: daemon operator-facing state (logs/locks/retry/drift) + the per-story
# worktree-base anchor (REPO_ROOT) resolve to the operator's REAL checkout (GAAI_REPO_ROOT),
# NOT the GAAI_DAEMON_HOME the daemon binary runs from (the dedicated daemon home worktree).
#
# Guards two invariants the flip broke:
#   1. delivery-daemon.sh LOG_FILE/LOG_DIR/LOCK_DIR follow GAAI_REPO_ROOT (else the monitor,
#      which reads the operator checkout, goes blank when the daemon runs from the home).
#   2. daemon-start.sh exports GAAI_REPO_ROOT and forwards it via tmux env (else delivery-daemon
#      REPO_ROOT falls back to PROJECT_DIR=home and the per-story worktree base nests/breaks).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPTS="$(cd "$SCRIPT_DIR/.." && pwd)"
DAEMON="$CORE_SCRIPTS/delivery-daemon.sh"
START="$CORE_SCRIPTS/daemon-start.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

echo "=== TC1: _STATE_PROJECT_DIR resolution (mirrors delivery-daemon.sh:~171) ==="
# Replicates the exact derivation; TC4 ties it to the real source.
resolve_state_dir() {
  local GAAI_REPO_ROOT="${1:-}" GAAI_PROJECT_DIR="$2" _STATE_PROJECT_DIR
  _STATE_PROJECT_DIR="${GAAI_REPO_ROOT:+$GAAI_REPO_ROOT/.gaai/project}"
  _STATE_PROJECT_DIR="${_STATE_PROJECT_DIR:-$GAAI_PROJECT_DIR}"
  printf '%s' "$_STATE_PROJECT_DIR"
}
HOME_PD="/tmp/wt/__daemon-home/.gaai/project"
REPO="/tmp/realcheckout"
got="$(resolve_state_dir "$REPO" "$HOME_PD")"
if [[ "$got" == "$REPO/.gaai/project" ]]; then
  pass "TC1-1: with GAAI_REPO_ROOT set, state dir resolves to the real checkout ($got)"
else
  fail "TC1-1: expected $REPO/.gaai/project, got $got"
fi

echo "=== TC2: fallback when GAAI_REPO_ROOT unset (no-home / direct run — no behavior change) ==="
got_unset="$(resolve_state_dir "" "$HOME_PD")"
if [[ "$got_unset" == "$HOME_PD" ]]; then
  pass "TC2-1: with GAAI_REPO_ROOT unset, falls back to GAAI_PROJECT_DIR ($got_unset)"
else
  fail "TC2-1: expected $HOME_PD, got $got_unset"
fi

echo "=== TC3: daemon-start.sh exports + forwards GAAI_REPO_ROOT ==="
if grep -qE '^[[:space:]]*export GAAI_REPO_ROOT="\$PROJECT_ROOT"' "$START"; then
  pass "TC3-1: daemon-start.sh exports GAAI_REPO_ROOT=PROJECT_ROOT"
else
  fail "TC3-1: daemon-start.sh does not export GAAI_REPO_ROOT=PROJECT_ROOT"
fi
if grep -qE 'tmux_env_args\+=\(-e "GAAI_REPO_ROOT=' "$START"; then
  pass "TC3-2: daemon-start.sh forwards GAAI_REPO_ROOT via tmux env"
else
  fail "TC3-2: daemon-start.sh does not forward GAAI_REPO_ROOT via tmux env"
fi
if grep -qE 'tmux_env_args\+=\(-e "GAAI_CI_TEST_GATE_TIMEOUT_SEC=' "$START"; then
  pass "TC3-3: daemon-start.sh forwards GAAI_CI_TEST_GATE_TIMEOUT_SEC via tmux env"
else
  fail "TC3-3: daemon-start.sh does not forward GAAI_CI_TEST_GATE_TIMEOUT_SEC via tmux env"
fi
if grep -qE 'tmux_env_args\+=\(-e "GAAI_CI_TEST_GATE_MATERIALIZE_SEC=' "$START"; then
  pass "TC3-4: daemon-start.sh forwards GAAI_CI_TEST_GATE_MATERIALIZE_SEC via tmux env"
else
  fail "TC3-4: daemon-start.sh does not forward GAAI_CI_TEST_GATE_MATERIALIZE_SEC via tmux env"
fi

echo "=== TC4: delivery-daemon.sh operator-state paths use _STATE_PROJECT_DIR (not raw GAAI_PROJECT_DIR) ==="
for var in LOG_FILE LOG_DIR LOCK_DIR; do
  if grep -qE "^${var}=\"\\\$_STATE_PROJECT_DIR/contexts/backlog" "$DAEMON"; then
    pass "TC4: $var derives from \$_STATE_PROJECT_DIR"
  else
    fail "TC4: $var does NOT derive from \$_STATE_PROJECT_DIR (still home-rooted?)"
  fi
done
# Completeness: no operator-state path may still root logs/locks directly at GAAI_PROJECT_DIR.
if grep -qE '^(LOG_FILE|LOG_DIR|LOCK_DIR)="\$GAAI_PROJECT_DIR/contexts/backlog' "$DAEMON"; then
  fail "TC4-completeness: an operator-state path still roots at \$GAAI_PROJECT_DIR (home) directly"
else
  pass "TC4-completeness: no operator-state path roots directly at \$GAAI_PROJECT_DIR"
fi

echo "=== TC5: BACKLOG deliberately stays on PROJECT_DIR (home — coordination, not operator state) ==="
if grep -qE '^BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"' "$DAEMON"; then
  pass "TC5: BACKLOG still follows PROJECT_DIR (home) — coordination state unchanged"
else
  fail "TC5: BACKLOG derivation changed unexpectedly"
fi

echo
echo "=== RESULT: $PASS_COUNT passed, $FAIL_COUNT failed ==="
[[ "$FAIL_COUNT" -eq 0 ]]
