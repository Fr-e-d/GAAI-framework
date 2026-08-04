#!/usr/bin/env bash
# daemon-asset-home.test.sh — E1003S04 AC6 sandbox tests
#
# Covers:
#   TC1a: DAEMON_SCRIPT resolves to home copy when GAAI_DAEMON_HOME provisioned + file present
#   TC1b: DAEMON_SCRIPT falls back to main-checkout when home file absent
#   TC1c: DAEMON_SCRIPT falls back to main-checkout when provisioning failed (_dhome_rc != 0)
#   TC2:  representative §63 asset read (planning.daemon-prompt.md) is ${PROJECT_DIR}-rooted
#         in daemon-dispatch.sh — follows the home when PROJECT_DIR=GAAI_DAEMON_HOME
#   TC3:  completeness backstop — zero node/python/cat reads of .gaai/core/* or .mcp.json
#         in daemon-dispatch.sh + delivery-daemon.sh are rooted outside ${PROJECT_DIR}
#
# Usage: bash .gaai/core/scripts/tests/daemon-asset-home.test.sh
# Exit 0 = all pass.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '  PASS: %s\n' "$1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { printf '  FAIL: %s\n' "$1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
DD="$SCRIPTS_DIR/delivery-daemon.sh"
DX="$SCRIPTS_DIR/daemon-dispatch.sh"

for f in "$DD" "$DX"; do
  if [[ ! -f "$f" ]]; then
    printf 'ERROR: required script not found: %s\n' "$f"
    exit 1
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# TC1: DAEMON_SCRIPT re-resolution logic (mirrors the block added in daemon-start.sh)
#
# We inline the logic here because do_start() also requires tmux/nohup and
# daemon infrastructure — the unit under test is the 4-line re-resolution block.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== TC1: DAEMON_SCRIPT re-resolution ==="

_FIXTURE_RAW="/tmp/gaai-asset-home-test-$$"
mkdir -p "$_FIXTURE_RAW"
FIXTURE_DIR="$(cd "$_FIXTURE_RAW" && pwd -P 2>/dev/null || echo "$_FIXTURE_RAW")"
cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

MAIN_CHECKOUT_DAEMON="$FIXTURE_DIR/main-checkout/delivery-daemon.sh"
mkdir -p "$(dirname "$MAIN_CHECKOUT_DAEMON")"
touch "$MAIN_CHECKOUT_DAEMON"

# Inline the re-resolution logic from daemon-start.sh do_start()
_resolve_daemon_script() {
  local _dhome_rc="$1"
  local gaai_daemon_home="$2"
  local main_script="$3"

  local _daemon_script="$main_script"
  local _home_daemon="$gaai_daemon_home/.gaai/core/scripts/delivery-daemon.sh"
  if [[ "$_dhome_rc" -eq 0 && -f "$_home_daemon" ]]; then
    _daemon_script="$_home_daemon"
  fi
  echo "$_daemon_script"
}

# TC1a: home present + provisioning succeeded → resolves to home copy
TC1A_HOME="$FIXTURE_DIR/tc1a-home"
TC1A_SCRIPT="$TC1A_HOME/.gaai/core/scripts/delivery-daemon.sh"
mkdir -p "$(dirname "$TC1A_SCRIPT")"
touch "$TC1A_SCRIPT"

TC1A_RESULT=$(_resolve_daemon_script 0 "$TC1A_HOME" "$MAIN_CHECKOUT_DAEMON")
if [[ "$TC1A_RESULT" == "$TC1A_SCRIPT" ]]; then
  pass "TC1a: DAEMON_SCRIPT resolves to home copy when provisioned and file present"
else
  fail "TC1a: expected '$TC1A_SCRIPT', got '$TC1A_RESULT'"
fi

# TC1b: home script absent (provisioning succeeded but script not in home) → fallback
TC1B_HOME="$FIXTURE_DIR/tc1b-home"
mkdir -p "$TC1B_HOME"
# do NOT create the home delivery-daemon.sh

TC1B_RESULT=$(_resolve_daemon_script 0 "$TC1B_HOME" "$MAIN_CHECKOUT_DAEMON")
if [[ "$TC1B_RESULT" == "$MAIN_CHECKOUT_DAEMON" ]]; then
  pass "TC1b: DAEMON_SCRIPT falls back to main-checkout when home file absent"
else
  fail "TC1b: expected main-checkout path, got '$TC1B_RESULT'"
fi

# TC1c: provisioning failed (_dhome_rc != 0) → fallback to main-checkout regardless
TC1C_HOME="$FIXTURE_DIR/tc1c-home"
TC1C_SCRIPT="$TC1C_HOME/.gaai/core/scripts/delivery-daemon.sh"
mkdir -p "$(dirname "$TC1C_SCRIPT")"
touch "$TC1C_SCRIPT"  # file present, but provisioning failed

TC1C_RESULT=$(_resolve_daemon_script 1 "$TC1C_HOME" "$MAIN_CHECKOUT_DAEMON")
if [[ "$TC1C_RESULT" == "$MAIN_CHECKOUT_DAEMON" ]]; then
  pass "TC1c: DAEMON_SCRIPT falls back to main-checkout when provisioning failed"
else
  fail "TC1c: expected main-checkout path, got '$TC1C_RESULT'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TC2: representative §63 asset read (planning.daemon-prompt.md) is ${PROJECT_DIR}-rooted
#
# This is a static grep verifying the source of truth: daemon-dispatch.sh must read
# planning.daemon-prompt.md via ${PROJECT_DIR}/... so it automatically follows
# GAAI_DAEMON_HOME when PROJECT_DIR is re-pointed to the home (E1003S03).
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== TC2: planning.daemon-prompt.md is \${PROJECT_DIR}-rooted in daemon-dispatch.sh ==="

if grep -qE '\$\{?PROJECT_DIR\}?[/]\.gaai/core/agents/sub-agents/planning\.daemon-prompt\.md' "$DX"; then
  pass "TC2: planning.daemon-prompt.md is \${PROJECT_DIR}-rooted (follows home when PROJECT_DIR=GAAI_DAEMON_HOME)"
else
  fail "TC2: planning.daemon-prompt.md not \${PROJECT_DIR}-rooted in daemon-dispatch.sh — asset will not follow the home"
fi

# Spot-check: .mcp.json read is also ${PROJECT_DIR}-rooted
if grep -qE '\$\{?PROJECT_DIR\}?[/]\.mcp\.json' "$DX"; then
  pass "TC2b: .mcp.json is \${PROJECT_DIR}-rooted in daemon-dispatch.sh"
else
  fail "TC2b: .mcp.json not \${PROJECT_DIR}-rooted in daemon-dispatch.sh"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TC3: completeness backstop
#
# Assert zero node/python/cat reads of .gaai/core/... or .mcp.json in
# daemon-dispatch.sh and delivery-daemon.sh that are NOT ${PROJECT_DIR}-rooted.
#
# A future untracked / main-checkout-absolute asset read MUST fail this check.
# Scope: `node`, `python3`, `python`, `cat` invocations on paths containing
#        ".gaai/core/" or ".mcp.json" — excludes comment lines (#) and
#        daemon's own internal `source` of lib files (those are $SCRIPT_DIR-derived
#        intentionally and are not delivery-asset reads).
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== TC3: completeness backstop — zero non-\${PROJECT_DIR}-rooted asset reads ==="

_check_backstop() {
  local label="$1"
  local file="$2"

  # Find lines matching: node/python/cat ... .gaai/core/ or .mcp.json
  # Then exclude: comment lines, and lines that do contain ${PROJECT_DIR}
  local hits
  hits=$(grep -nE '^[[:space:]]*(node|python3?|cat) .*(\.gaai/core/|\.mcp\.json)' "$file" 2>/dev/null \
    | grep -vE '^[[:space:]]*#' \
    | grep -vE '\$\{PROJECT_DIR\}|\$PROJECT_DIR' \
    || true)

  if [[ -z "$hits" ]]; then
    pass "TC3-${label}: 0 non-\${PROJECT_DIR}-rooted asset reads"
  else
    fail "TC3-${label}: found non-\${PROJECT_DIR}-rooted asset reads:"
    printf '%s\n' "$hits" | while IFS= read -r line; do
      printf '    %s\n' "$line"
    done
  fi
}

_check_backstop "daemon-dispatch" "$DX"
_check_backstop "delivery-daemon" "$DD"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
printf '  Results: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
echo "══════════════════════════════════════════════════"

exit "$FAIL_COUNT"
