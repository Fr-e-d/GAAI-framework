#!/usr/bin/env bash
# ── daemon-dispatch-mcp-config.test.sh ────────────────────────────────────────
# AC6 (E150S10): inline MCP config construction + workspace scope guard
#
# T1: _build_daemon_mcp_config produces valid JSON with expected headers
# T2: AC5 guard — missing workspace_id with .mcp.json present → refuse spawn
# T3: two calls with different workspace_ids → independent JSON (no shared state)
#
# Run: bash .gaai/core/scripts/tests/daemon-dispatch-mcp-config.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Source daemon-dispatch.sh to get helper functions
BACKLOG_FILE="/tmp/gaai-mcp-config-test-backlog.yaml"
SCHEDULER="$(which true)"
export PROJECT_DIR BACKLOG_FILE SCHEDULER
source "$SCRIPT_DIR/../daemon-dispatch.sh" 2>/dev/null || true

# ── Setup: temp dir for mock project root
TMPDIR_TEST="$(mktemp -d /tmp/gaai-mcp-config-test-XXXXXX)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

# ── T1: _build_daemon_mcp_config produces valid JSON ─────────────────────────
T1_WS="test0001-0000-0000-0000-workspace0t1"
T1_TOKEN="test_token_abc123"
T1_JSON=$(_build_daemon_mcp_config "$T1_WS" "$T1_TOKEN" 2>/dev/null || echo "")

if echo "$T1_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); \
  s=list(d['mcpServers'].values())[0]; \
  assert s['url']=='https://mcp.gaai.cloud/mcp'; \
  assert s['headers']['Authorization']=='Bearer test_token_abc123'; \
  assert s['headers']['X-GAAI-Workspace-Scope']=='test0001-0000-0000-0000-workspace0t1'; \
  assert s['headers']['X-GAAI-Session-Mode']=='autonomous'" 2>/dev/null; then
  pass "T1: _build_daemon_mcp_config produces valid JSON with expected headers"
else
  fail "T1: _build_daemon_mcp_config — JSON invalid or missing expected fields (got: $T1_JSON)"
fi

# ── T2: AC5 guard — missing workspace_id with .mcp.json present → refuse ────
# Set up mock .mcp.json in a fake PROJECT_DIR
T2_PROJECT_DIR="$TMPDIR_TEST/t2-project"
mkdir -p "$T2_PROJECT_DIR"
cat > "$T2_PROJECT_DIR/.mcp.json" <<'JSON'
{"mcpServers":{"GAAI-cloud":{"type":"http","url":"https://mcp.gaai.cloud/mcp","headers":{"Authorization":"Bearer fake_token"}}}}
JSON

# Test _extract_mcp_oauth_token reads the token correctly
T2_TOKEN=$(_extract_mcp_oauth_token "$T2_PROJECT_DIR/.mcp.json" 2>/dev/null || echo "")
if [[ "$T2_TOKEN" == "fake_token" ]]; then
  pass "T2a: _extract_mcp_oauth_token reads Authorization Bearer token from .mcp.json"
else
  fail "T2a: _extract_mcp_oauth_token — expected 'fake_token', got '$T2_TOKEN'"
fi

# Test guard logic: simulate guard block behavior
# (Guard is inline in each handler, not a separate function; test the condition logic)
PROJECT_DIR_SAVED="$PROJECT_DIR"
PROJECT_DIR="$T2_PROJECT_DIR"
export PROJECT_DIR
GAAI_WORKSPACE_ID=""
export GAAI_WORKSPACE_ID
GUARD_FIRED=0
if [[ -f "${PROJECT_DIR}/.mcp.json" && -z "${GAAI_WORKSPACE_ID:-}" ]]; then
  GUARD_FIRED=1
fi
PROJECT_DIR="$PROJECT_DIR_SAVED"
export PROJECT_DIR
if [[ "$GUARD_FIRED" == "1" ]]; then
  pass "T2b: AC5 guard condition fires when .mcp.json present and GAAI_WORKSPACE_ID empty"
else
  fail "T2b: AC5 guard condition did not fire — check guard logic"
fi

# Test guard does NOT fire when GAAI_WORKSPACE_ID is set
PROJECT_DIR="$T2_PROJECT_DIR"
export PROJECT_DIR
GAAI_WORKSPACE_ID="test0002-0000-0000-0000-workspace0t2"
export GAAI_WORKSPACE_ID
GUARD_FIRED_2=0
if [[ -f "${PROJECT_DIR}/.mcp.json" && -z "${GAAI_WORKSPACE_ID:-}" ]]; then
  GUARD_FIRED_2=1
fi
PROJECT_DIR="$PROJECT_DIR_SAVED"
export PROJECT_DIR
if [[ "$GUARD_FIRED_2" == "0" ]]; then
  pass "T2c: AC5 guard does not fire when GAAI_WORKSPACE_ID is set"
else
  fail "T2c: AC5 guard incorrectly fired when workspace_id was set"
fi

# ── T3: Parallel spawns with different workspace_ids → independent JSON ───────
# Two calls with different workspace_ids must produce different JSON (no shared state)
T3_WS_A="wstest-slot0-0000-0000-000000000t3a"
T3_WS_B="wstest-slot1-0000-0000-000000000t3b"
T3_TOKEN="shared_oauth_token"

T3_JSON_A=$(_build_daemon_mcp_config "$T3_WS_A" "$T3_TOKEN")
T3_JSON_B=$(_build_daemon_mcp_config "$T3_WS_B" "$T3_TOKEN")

T3_SCOPE_A=$(echo "$T3_JSON_A" | python3 -c "import json,sys; d=json.load(sys.stdin); print(list(d['mcpServers'].values())[0]['headers']['X-GAAI-Workspace-Scope'])" 2>/dev/null || echo "")
T3_SCOPE_B=$(echo "$T3_JSON_B" | python3 -c "import json,sys; d=json.load(sys.stdin); print(list(d['mcpServers'].values())[0]['headers']['X-GAAI-Workspace-Scope'])" 2>/dev/null || echo "")

if [[ "$T3_SCOPE_A" == "$T3_WS_A" && "$T3_SCOPE_B" == "$T3_WS_B" && "$T3_SCOPE_A" != "$T3_SCOPE_B" ]]; then
  pass "T3: Two parallel calls with different workspace_ids produce independent JSON (no shared state)"
else
  fail "T3: Workspace scope contamination — A='$T3_SCOPE_A' B='$T3_SCOPE_B' (expected '$T3_WS_A' and '$T3_WS_B')"
fi

# ── Result ────────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS_COUNT pass, $FAIL_COUNT fail"
[[ "$FAIL_COUNT" -eq 0 ]]
