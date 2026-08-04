#!/usr/bin/env bash
# daemon-safe-increment.test.sh — regression guard for set -e post-increments
#
# Usage: bash .gaai/core/scripts/tests/daemon-safe-increment.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../delivery-daemon.sh"

if [[ ! -f "$DAEMON" ]]; then
  echo "ERROR: delivery daemon not found at $DAEMON"
  exit 1
fi

echo "=== Safe post-increment regression guard ==="

# A bare arithmetic post-increment exits 1 when its pre-increment value is zero.
# Under set -e that stops the caller, so every post-increment command in the daemon
# must explicitly neutralise that status.
#
# Comment lines are skipped: the scan looks for post-increment *commands*, and the
# daemon documents this very hazard in prose that quotes `((counter++))` and
# `((i++))`. Matching those made the guard flag its own documentation — the scan
# reported them as unguarded commands because a comment can carry no `|| true`.
POST_INCREMENT_LINES=$(awk '
  {
    line = $0
    if (line ~ /^[[:space:]]*#/) next
    if (line ~ /(^|[^[:alnum:]_])\(\([[:space:]]*[[:alpha:]_][[:alnum:]_]*[[:space:]]*\+\+[[:space:]]*\)\)/) {
      print NR ":" line
    }
  }
' "$DAEMON")

POST_INCREMENT_COUNT=$(printf '%s\n' "$POST_INCREMENT_LINES" | awk 'NF { count++ } END { print count + 0 }')
if [[ "$POST_INCREMENT_COUNT" -gt 0 ]]; then
  pass "T1: found $POST_INCREMENT_COUNT daemon post-increment command(s) to guard"
else
  fail "T1: expected at least one daemon post-increment command"
fi

UNSAFE_LINES=$(printf '%s\n' "$POST_INCREMENT_LINES" | awk '!/\|\|[[:space:]]*true/')
if [[ -z "$UNSAFE_LINES" ]]; then
  pass "T2: every daemon post-increment neutralises its arithmetic exit status"
else
  fail "T2: unsafe post-increment command(s):"
  printf '%s\n' "$UNSAFE_LINES"
fi

LAUNCHED_GUARDS=$(awk '
  /\(\([[:space:]]*launched[[:space:]]*\+\+[[:space:]]*\)\)[[:space:]]*\|\|[[:space:]]*true/ { count++ }
  END { print count + 0 }
' "$DAEMON")
if [[ "$LAUNCHED_GUARDS" -eq 2 ]]; then
  pass "T3: both dry-run and wrapper-launch counter paths are guarded"
else
  fail "T3: expected 2 guarded launched++ paths, found $LAUNCHED_GUARDS"
fi

FIRST_LAUNCH_OUTPUT=$(bash -c '
  set -e
  launched=0
  ((launched++)) || true
  printf "continued:%s" "$launched"
' 2>&1)

if [[ "$FIRST_LAUNCH_OUTPUT" == "continued:1" ]]; then
  pass "T4: a zero-valued first launch increments and continues under set -e"
else
  fail "T4: guarded first launch did not continue as expected: $FIRST_LAUNCH_OUTPUT"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
exit "$FAIL_COUNT"
