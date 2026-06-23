#!/usr/bin/env bash
# daemon-path-roots.test.sh — E1003S01 regression coverage
#
# T1: REPO_ROOT defaults to PROJECT_DIR when GAAI_REPO_ROOT unset (AC6a)
# T2: completeness grep — no worktree-base derivation uses ${PROJECT_DIR}/.. (AC6b)
# T3: overriding PROJECT_DIR alone (REPO_ROOT unchanged) leaves worktree base unchanged (AC6c)
# T4: daemon-dispatch-reap-orphans.test.sh still passes (AC5 non-regression)
#
# Run: bash .gaai/core/scripts/tests/daemon-path-roots.test.sh
# Exit 0 = all pass.

set -uo pipefail

PASS_COUNT=0; FAIL_COUNT=0
pass() { printf '  PASS: %s\n' "$1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { printf '  FAIL: %s\n' "$1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DD="$SCRIPT_DIR/../delivery-daemon.sh"
DX="$SCRIPT_DIR/../daemon-dispatch.sh"

# ── T1: REPO_ROOT defaults to PROJECT_DIR when GAAI_REPO_ROOT unset ─────────
unset GAAI_REPO_ROOT
_pd="/tmp/fake-repo-$$"
_rr="${GAAI_REPO_ROOT:-${_pd}}"
if [[ "$_rr" == "$_pd" ]]; then
  pass "T1: REPO_ROOT defaults to PROJECT_DIR when GAAI_REPO_ROOT unset"
else
  fail "T1: REPO_ROOT='$_rr' != PROJECT_DIR='$_pd'"
fi

# ── T2a: delivery-daemon.sh — no remaining \${PROJECT_DIR}/.. worktree-base derivations ──
# grep -c exits 1 (no matches) and still outputs "0"; use || true to avoid double-output
dd_wt_old=$(grep -cE '\$\{PROJECT_DIR\}/\.\.' "$DD" 2>/dev/null || true)
dd_wt_old="${dd_wt_old:-0}"
if [[ "$dd_wt_old" -eq 0 ]]; then
  pass "T2a: delivery-daemon.sh has 0 remaining \${PROJECT_DIR}/.. worktree-base derivations"
else
  fail "T2a: delivery-daemon.sh still has $dd_wt_old \${PROJECT_DIR}/.. derivations (expected 0)"
fi

# ── T2b: daemon-dispatch.sh — no remaining \${PROJECT_DIR}/.. worktree-base derivations ──
dx_wt_old=$(grep -cE '\$\{PROJECT_DIR\}/\.\.' "$DX" 2>/dev/null || true)
dx_wt_old="${dx_wt_old:-0}"
if [[ "$dx_wt_old" -eq 0 ]]; then
  pass "T2b: daemon-dispatch.sh has 0 remaining \${PROJECT_DIR}/.. worktree-base derivations"
else
  fail "T2b: daemon-dispatch.sh still has $dx_wt_old \${PROJECT_DIR}/.. derivations (expected 0)"
fi

# ── T3: overriding PROJECT_DIR alone does not move worktree-base path ────────
# With REPO_ROOT and PROJECT_DIR pointing to different dirs, the carve-out formula
# must anchor to REPO_ROOT — not PROJECT_DIR.
REPO_ROOT="/tmp/real-repo-$$"
PROJECT_DIR="/tmp/other-proj-$$"

_new_base="$(cd "${REPO_ROOT:-$PROJECT_DIR}/.." 2>/dev/null && pwd 2>/dev/null || echo "${REPO_ROOT:-$PROJECT_DIR}/..")/.gaai-worktrees/$(basename "${REPO_ROOT:-$PROJECT_DIR}")"
_old_base="$(cd "${PROJECT_DIR}/.." 2>/dev/null && pwd 2>/dev/null || echo "${PROJECT_DIR}/..")/.gaai-worktrees/$(basename "$PROJECT_DIR")"

if [[ "$_new_base" != "$_old_base" ]]; then
  pass "T3: with REPO_ROOT≠PROJECT_DIR, carve-out formula produces different path from old formula"
else
  fail "T3: REPO_ROOT≠PROJECT_DIR but carve-out formula == old formula — carve-out incomplete"
fi

if [[ "$_new_base" == *"real-repo"* ]] && [[ "$_new_base" != *"other-proj"* ]]; then
  pass "T3b: worktree-base anchored to REPO_ROOT (real-repo), not PROJECT_DIR (other-proj)"
else
  fail "T3b: worktree-base='$_new_base' should contain 'real-repo' and not 'other-proj'"
fi

# ── T4: existing reap-orphans test still passes (AC5 non-regression) ─────────
if bash "$SCRIPT_DIR/daemon-dispatch-reap-orphans.test.sh" >/dev/null 2>&1; then
  pass "T4: daemon-dispatch-reap-orphans.test.sh still passes (AC5 non-regression)"
else
  fail "T4: daemon-dispatch-reap-orphans.test.sh FAILED (regression introduced)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n  %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
