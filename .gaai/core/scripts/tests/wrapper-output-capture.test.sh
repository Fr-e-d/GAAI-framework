#!/usr/bin/env bash
# E160S08 regression tests: wrapper output capture + bounded-retry commit-stall guard
# Self-contained — uses only a temporary git repository and daemon-state files.
# Exit 0 = all pass (T1 skipped if tmux unavailable or < 2.6).

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'

_ok()   { ((PASS++)) || true; echo -e "  ${GREEN}PASS${NC} $1"; }
_fail() { ((FAIL++)) || true; echo -e "  ${RED}FAIL${NC} $1"; }
_skip() { ((SKIP++)) || true; echo -e "  ${YELLOW}SKIP${NC} $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== wrapper-output-capture tests ==="

# ── T1a/T1b: pipe-pane captures wrapper stdout to .wrapper.log ────────────
TMUX_OK=false
if command -v tmux &>/dev/null; then
  _ver=$(tmux -V 2>/dev/null || true)
  _maj=0; _min=0
  if [[ "$_ver" =~ tmux[[:space:]]+([0-9]+)\.([0-9]+) ]]; then
    _maj="${BASH_REMATCH[1]}"; _min="${BASH_REMATCH[2]}"
  fi
  (( _maj > 2 || ( _maj == 2 && _min >= 6 ) )) && TMUX_OK=true
fi

if $TMUX_OK; then
  LOG_FILE="$TMP/t1a.wrapper.log"
  SN="test-e160s08-t1a-$$"
  # Start a long-lived session, wire pipe-pane, THEN produce output
  tmux new-session -d -s "$SN" "sleep 5" 2>/dev/null
  tmux pipe-pane -t "$SN" -o "cat >> ${LOG_FILE}" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$SN" "echo 'capture-marker-42'" Enter 2>/dev/null || true
  sleep 0.5
  tmux kill-session -t "$SN" 2>/dev/null || true
  sleep 0.3

  if grep -q 'capture-marker-42' "$LOG_FILE" 2>/dev/null; then
    _ok "T1a: pipe-pane captures stdout to wrapper.log"
  else
    _fail "T1a: wrapper.log missing or empty (got: $(cat "$LOG_FILE" 2>/dev/null || echo '<nothing>'))"
  fi

  # T1b: log file contains the last command output before kill
  LOG2="$TMP/t1b.wrapper.log"
  SN2="test-e160s08-t1b-$$"
  tmux new-session -d -s "$SN2" "sleep 5" 2>/dev/null
  tmux pipe-pane -t "$SN2" -o "cat >> ${LOG2}" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$SN2" "echo 'before-kill-line'" Enter 2>/dev/null || true
  sleep 0.5
  tmux kill-session -t "$SN2" 2>/dev/null || true
  sleep 0.3

  if grep -q 'before-kill-line' "$LOG2" 2>/dev/null; then
    _ok "T1b: wrapper.log contains output before kill"
  else
    _fail "T1b: wrapper.log missing expected output before kill (got: $(cat "$LOG2" 2>/dev/null || echo '<nothing>'))"
  fi
else
  _skip "T1a: tmux >= 2.6 not available"
  _skip "T1b: tmux >= 2.6 not available"
fi

# ── T2: retry containment follows content + outcome, not HEAD ─────────────
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
# shellcheck source=../lib/commit-retry-containment.sh
source "$ROOT/.gaai/core/scripts/lib/commit-retry-containment.sh"

LOCK_DIR="$TMP/locks"
mkdir -p "$LOCK_DIR"
# This unit matrix exercises the pre-threshold reset rules. Terminal behavior
# at the production default threshold is covered by T-COMMIT-RETRY-THRESHOLD.
COMMIT_PHASE_RETRY_THRESHOLD=10
SID="test-story-t2"
REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
printf 'base\n' > "$REPO/app.txt"
git -C "$REPO" add app.txt
git -C "$REPO" commit -qm base
git -C "$REPO" branch base
git -C "$REPO" switch -qc story
printf 'implementation\n' >> "$REPO/app.txt"
git -C "$REPO" commit -qam implementation -q

_commit_retry_write_observation "$SID" "blocked:tests_failed"
IFS='|' read -r C1 O1 P1 <<< "$(_commit_retry_observe "$SID" "$REPO" base)"
if [[ "$C1|$O1|$P1" == "1|blocked:tests_failed|initial" ]]; then
  _ok "T2a: first blocking outcome starts a bounded sequence"
else
  _fail "T2a: unexpected first observation '$C1|$O1|$P1'"
fi

mkdir -p "$REPO/.gaai/project/contexts/artefacts/qa-reports"
printf 'verdict cycle 1\n' > "$REPO/.gaai/project/contexts/artefacts/qa-reports/${SID}.qa-report.md"
git -C "$REPO" add .
git -C "$REPO" commit -qm 'bookkeeping cycle 1'
_commit_retry_write_observation "$SID" "blocked:tests_failed"
IFS='|' read -r C2 O2 P2 <<< "$(_commit_retry_observe "$SID" "$REPO" base)"
printf 'verdict cycle 2\n' >> "$REPO/.gaai/project/contexts/artefacts/qa-reports/${SID}.qa-report.md"
git -C "$REPO" commit -qam 'bookkeeping cycle 2' -q
_commit_retry_write_observation "$SID" "blocked:tests_failed"
IFS='|' read -r C3 O3 P3 <<< "$(_commit_retry_observe "$SID" "$REPO" base)"
if [[ "$C2|$P2|$C3|$P3" == "2|repeated|3|repeated" ]]; then
  _ok "T2b: bookkeeping commits cannot reset repeated-outcome containment"
else
  _fail "T2b: expected repeated counts 2 then 3, got '$C2|$P2|$C3|$P3'"
fi

_commit_retry_write_observation "$SID" "blocked:github_unavailable"
IFS='|' read -r C4 O4 P4 <<< "$(_commit_retry_observe "$SID" "$REPO" base)"
if [[ "$C4|$O4|$P4" == "1|blocked:github_unavailable|outcome_changed" ]]; then
  _ok "T2c: a different blocking outcome clears the sequence"
else
  _fail "T2c: outcome change did not reset: '$C4|$O4|$P4'"
fi

printf 'real fix\n' >> "$REPO/app.txt"
git -C "$REPO" commit -qam 'implementation progress' -q
_commit_retry_write_observation "$SID" "blocked:github_unavailable"
IFS='|' read -r C5 O5 P5 <<< "$(_commit_retry_observe "$SID" "$REPO" base)"
if [[ "$C5|$O5|$P5" == "1|blocked:github_unavailable|content_changed" ]]; then
  _ok "T2d: real implementation content clears the sequence despite the same outcome"
else
  _fail "T2d: implementation progress did not reset: '$C5|$O5|$P5'"
fi

printf 'bookkeeping after progress\n' >> "$REPO/.gaai/project/contexts/artefacts/qa-reports/${SID}.qa-report.md"
git -C "$REPO" commit -qam 'bookkeeping after progress' -q
_commit_retry_write_observation "$SID" "blocked:github_unavailable"
_ORIGINAL_SHA_HELPER=$(declare -f _commit_retry_sha256_stdin)
_commit_retry_sha256_stdin() { return 1; }
if _commit_retry_observe "$SID" "$REPO" base >/dev/null 2>&1; then
  _fail "T2e: unavailable content digest authorized another observation"
elif [[ -f "$(_commit_retry_observation_path "$SID")" ]] \
  && grep -q '^count=1$' "$(_commit_retry_state_path "$SID")"; then
  _ok "T2e: unavailable digest preserves outcome/state and cannot authorize relaunch"
else
  _fail "T2e: unavailable digest lost its one-shot outcome or prior state"
fi
eval "$_ORIGINAL_SHA_HELPER"

DAEMON="$ROOT/.gaai/core/scripts/delivery-daemon.sh"
if grep -q 'GAAI_COMMIT_PHASE_RETRY_THRESHOLD:-3' "$DAEMON" \
  && grep -q '_commit_retry_observe' "$DAEMON" \
  && grep -q 'repeated for ${_cd_new} cycles' "$DAEMON"; then
  _ok "T2f: configurable threshold, recovery integration and actionable cycle notification are wired"
else
  _fail "T2f: retry containment integration contract is incomplete"
fi

_commit_retry_clear "$SID"
if [[ ! -e "$(_commit_retry_state_path "$SID")" \
      && ! -e "$(_commit_retry_observation_path "$SID")" ]]; then
  _ok "T2g: terminal/reset cleanup removes retry state"
else
  _fail "T2g: retry state survived cleanup"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
