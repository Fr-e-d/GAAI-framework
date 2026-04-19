#!/usr/bin/env bash
# canary.test.sh — E94 canary: validates CLAUDECODE="" workaround + OAuth isolation
#
# Maintenance-critical: re-run on every Claude Code CLI upgrade (D-15, O-4).
# AC7 / AC8 of Epic E94S10.
#
# Usage:
#   bash .gaai/core/tests/canary.test.sh
#
# Requires:
#   GAAI_IMPL_BASE_URL, GAAI_IMPL_AUTH_TOKEN, GAAI_IMPL_MODEL set in env
#   node (18+), claude CLI in PATH
#
# Exit codes:
#   0 — all assertions passed (CANARY: PASS)
#   1 — one or more assertions failed (CANARY: FAIL)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPAWN_JS="$(cd "$SCRIPT_DIR/../adapters/claude-code" && pwd)/nested-claude-spawn.js"

# ── Get real CLI version BEFORE the mock is in PATH ──────────────────────────
CLI_VER=$(claude --version 2>/dev/null | head -1 || echo "not-found")
PLATFORM=$(uname -s)

# ── Temp workspace ────────────────────────────────────────────────────────────
TMPDIR_WORK=$(mktemp -d)
trap "rm -rf '$TMPDIR_WORK'" EXIT

export CANARY_ENV_DUMP="$TMPDIR_WORK/child_env.txt"

# ── Mock claude binary ────────────────────────────────────────────────────────
# Writes child env to CANARY_ENV_DUMP, emits the impl completion marker, exits 0.
# nested-claude-spawn.js checks for "## Implementation" as the completion marker.
cat > "$TMPDIR_WORK/claude" << 'MOCK'
#!/usr/bin/env bash
env > "$CANARY_ENV_DUMP"
printf '## Implementation (canary mock)\n'
exit 0
MOCK
chmod +x "$TMPDIR_WORK/claude"

# Prepend mock dir so findCLI() in nested-claude-spawn.js finds the mock first.
export PATH="$TMPDIR_WORK:$PATH"

# ── Result tracking ───────────────────────────────────────────────────────────
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ── Header ────────────────────────────────────────────────────────────────────
echo "=== E94 Canary Test ==="
echo "Date        : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Platform    : $PLATFORM"
echo "CLI version : $CLI_VER"
echo "GAAI_IMPL_MODEL     : ${GAAI_IMPL_MODEL:-<not set>}"
echo "GAAI_IMPL_BASE_URL  : $(echo "${GAAI_IMPL_BASE_URL:-}" | sed 's|https://||;s|http://||' | cut -d'/' -f1) (domain only)"
echo ""

# ── Assert 0: required env vars are set ──────────────────────────────────────
if [[ -n "${GAAI_IMPL_BASE_URL:-}" && -n "${GAAI_IMPL_AUTH_TOKEN:-}" && -n "${GAAI_IMPL_MODEL:-}" ]]; then
  pass "GAAI_IMPL env vars configured"
else
  fail "GAAI_IMPL env vars missing — set GAAI_IMPL_BASE_URL, GAAI_IMPL_AUTH_TOKEN, GAAI_IMPL_MODEL"
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  echo "CANARY: FAIL"
  exit 1
fi

# ── Invoke nested-claude-spawn.js via mock ────────────────────────────────────
node --input-type=module <<NODESCRIPT
const spawn = await import('file://$SPAWN_JS');
const result = await spawn.spawnNestedClaude('canary echo ok', null);
if (!result.success) {
  process.stderr.write('spawn returned success=false: ' + result.error_reason + '\\n');
  process.exit(1);
}
NODESCRIPT
NODE_RC=$?

if [[ $NODE_RC -eq 0 ]]; then
  pass "spawnNestedClaude invocation succeeded (mock exited 0)"
else
  fail "spawnNestedClaude invocation failed (node exit $NODE_RC)"
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  echo "CANARY: FAIL"
  exit 1
fi

# ── Verify env dump was written ───────────────────────────────────────────────
if [[ ! -f "$CANARY_ENV_DUMP" ]]; then
  fail "child env dump not written — mock claude never ran"
  echo "CANARY: FAIL"
  exit 1
fi
pass "child env dump written by mock claude"

# ── Assert 1: CLAUDECODE is empty string ──────────────────────────────────────
CLAUDECODE_LINE=$(grep '^CLAUDECODE=' "$CANARY_ENV_DUMP" 2>/dev/null || echo "CLAUDECODE=__NOT_FOUND__")
CLAUDECODE_VAL="${CLAUDECODE_LINE#CLAUDECODE=}"

if [[ "$CLAUDECODE_VAL" == "" ]]; then
  pass "CLAUDECODE=\"\" (workaround active — nested-spawn detection bypassed)"
elif [[ "$CLAUDECODE_VAL" == "__NOT_FOUND__" ]]; then
  fail "CLAUDECODE not set in child env — workaround missing in nested-claude-spawn.js"
else
  fail "CLAUDECODE is non-empty ('$CLAUDECODE_VAL') — workaround may not be effective"
fi

# ── Assert 2: parent OAuth tokens NOT in child env ───────────────────────────
for KEY in CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY CLAUDE_API_KEY; do
  if grep -q "^${KEY}=" "$CANARY_ENV_DUMP" 2>/dev/null; then
    fail "$KEY leaked into child env (OAuth isolation broken)"
  else
    pass "$KEY absent from child env (isolation OK)"
  fi
done

# ── Assert 3: secondary provider vars remapped into child env ────────────────
for KEY in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN; do
  if grep -q "^${KEY}=" "$CANARY_ENV_DUMP" 2>/dev/null; then
    pass "$KEY present in child env (remapped from GAAI_IMPL_*)"
  else
    fail "$KEY absent from child env — GAAI_IMPL_* remapping failed in nested-claude-spawn.js"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  echo "CANARY: FAIL"
  exit 1
fi

echo "CANARY: PASS"
exit 0
