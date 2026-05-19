#!/usr/bin/env bash
# E150S10 — mcp-config-spawn.test.sh
# Tests _gaai_build_mcp_config_inline() function (AC6):
#   (a) valid workspace_id → JSON contains X-GAAI-Workspace-Scope + Session-Mode: autonomous
#   (b) missing workspace_id → returns 1 + structured workspace_scope error message
#   (c) two parallel calls with different workspace_ids → no shared state contamination
#
# Usage: bash .gaai/core/scripts/tests/mcp-config-spawn.test.sh

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

DISPATCH_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/daemon-dispatch.sh"
PROJECT_DIR_STUB="$(mktemp -d)"
export PROJECT_DIR="$PROJECT_DIR_STUB"

# Extract only the _gaai_build_mcp_config_inline function body from the dispatch
# script, avoiding sourcing the full library (which requires BACKLOG_FILE etc.)
_EXTRACTED_FN="$(sed -n '/^_gaai_build_mcp_config_inline()/,/^}/p' "$DISPATCH_SCRIPT")"

echo "mcp-config-spawn tests — _gaai_build_mcp_config_inline()"
echo ""

# ── T1: valid workspace_id + auth token → JSON includes all 3 required headers ──
echo "T1: valid workspace_id + auth token → JSON includes X-GAAI-Workspace-Scope + Session-Mode"
{
  WS_UUID="test-workspace-scope-value-t1"
  AUTH_TOK="test-oauth-token-abc123"
  OUT=$(bash -c "
PROJECT_DIR='$PROJECT_DIR_STUB'
$_EXTRACTED_FN
export GAAI_WORKSPACE_ID='$WS_UUID'
export GAAI_MCP_AUTH_TOKEN='$AUTH_TOK'
_gaai_build_mcp_config_inline 'E150TEST' 'plan'
" 2>/dev/null)

  if echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
s = list(d['mcpServers'].values())[0]
h = s['headers']
assert h.get('X-GAAI-Workspace-Scope') == '$WS_UUID', 'bad scope'
assert h.get('X-GAAI-Session-Mode') == 'autonomous', 'bad mode'
assert 'Authorization' in h, 'missing auth'
" 2>/dev/null; then
    pass "JSON contains X-GAAI-Workspace-Scope, X-GAAI-Session-Mode, Authorization"
  else
    fail "JSON missing required headers; got: $OUT"
  fi
}

# ── T2: missing workspace_id → returns 1 + structured error ──────────────────
echo "T2: missing workspace_id → returns 1 + structured workspace_scope error"
{
  ERR_OUT=$(bash -c "
PROJECT_DIR='$PROJECT_DIR_STUB'
$_EXTRACTED_FN
unset GAAI_WORKSPACE_ID
_gaai_build_mcp_config_inline 'E150TEST' 'plan' && echo 'SHOULD_NOT_REACH'
" 2>&1 || true)

  if echo "$ERR_OUT" | grep -q 'workspace_scope required'; then
    pass "structured workspace_scope error emitted on missing workspace_id"
  else
    fail "expected workspace_scope error; got: $ERR_OUT"
  fi

  RC=0
  bash -c "
PROJECT_DIR='$PROJECT_DIR_STUB'
$_EXTRACTED_FN
unset GAAI_WORKSPACE_ID
_gaai_build_mcp_config_inline 'E150TEST' 'plan'
" 2>/dev/null && RC=0 || RC=$?
  if [[ "$RC" -ne 0 ]]; then
    pass "function returns non-zero when workspace_id missing"
  else
    fail "function returned 0 when workspace_id was missing (expected failure)"
  fi
}

# ── T3: two parallel calls with different workspace_ids → no shared state ─────
echo "T3: two parallel calls with different workspace_ids → each gets its own scope"
{
  WS_A="test-workspace-scope-value-alpha"
  WS_B="test-workspace-scope-value-bravo"

  JSON_A=$(bash -c "
PROJECT_DIR='$PROJECT_DIR_STUB'
$_EXTRACTED_FN
export GAAI_WORKSPACE_ID='$WS_A'
export GAAI_MCP_AUTH_TOKEN='token-a'
_gaai_build_mcp_config_inline 'E150A' 'plan'
" 2>/dev/null)

  JSON_B=$(bash -c "
PROJECT_DIR='$PROJECT_DIR_STUB'
$_EXTRACTED_FN
export GAAI_WORKSPACE_ID='$WS_B'
export GAAI_MCP_AUTH_TOKEN='token-b'
_gaai_build_mcp_config_inline 'E150B' 'qa'
" 2>/dev/null)

  SCOPE_A=$(echo "$JSON_A" | python3 -c "import json,sys; print(list(json.load(sys.stdin)['mcpServers'].values())[0]['headers']['X-GAAI-Workspace-Scope'])" 2>/dev/null)
  SCOPE_B=$(echo "$JSON_B" | python3 -c "import json,sys; print(list(json.load(sys.stdin)['mcpServers'].values())[0]['headers']['X-GAAI-Workspace-Scope'])" 2>/dev/null)

  if [[ "$SCOPE_A" == "$WS_A" && "$SCOPE_B" == "$WS_B" && "$SCOPE_A" != "$SCOPE_B" ]]; then
    pass "parallel spawns produce independent workspace scopes (no shared state)"
  else
    fail "scope contamination detected: A=$SCOPE_A B=$SCOPE_B (expected $WS_A and $WS_B)"
  fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
rm -rf "$PROJECT_DIR_STUB"
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo "All tests PASSED."
  exit 0
else
  echo "SOME TESTS FAILED."
  exit 1
fi
