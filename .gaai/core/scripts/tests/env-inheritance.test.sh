#!/usr/bin/env bash
# E99S11 — env-inheritance.test.sh
# Tests _gaai_resolve_session_env + _gaai_read_hint_for_env logic.
#
# The functions live inside daemon wrapper heredocs (so sourcing from the daemon
# directly is not feasible). This harness defines equivalent functions with
# a test-controlled PROJECT_DIR, then exercises all AC6 scenarios.
#
# Usage: bash .gaai/core/scripts/tests/env-inheritance.test.sh

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

# ── Write a valid hint file at TEST_PROJECT_DIR ───────────────────────────────
_write_hint() {
  local dir="$1" ws_id="$2" org_id="$3"
  mkdir -p "$dir/.gaai/local"
  printf '{\n  "version": 1,\n  "workspace_id": "%s",\n  "org_id": "%s",\n  "hinted_at": "2026-04-23T00:00:00.000Z"\n}\n' \
    "$ws_id" "$org_id" > "$dir/.gaai/local/workspace-preference.json"
}

# ── Build and run a self-contained test subprocess ───────────────────────────
# Each test case runs in `bash -c "..."` so env state is fully isolated.
# The subprocess defines the two functions with TEST_PROJECT_DIR baked in,
# then calls _gaai_resolve_session_env and prints the resulting env vars.

_run_scenario() {
  local test_project_dir="$1"
  local extra_env="$2"   # bash assignments to prepend (e.g. "export GAAI_WORKSPACE_ID=foo")
  # Resolve plugin path from the repo root (worktree has same structure as main repo)
  local repo_root
  repo_root="$(cd "$(dirname "$0")/../../../.." && pwd)"
  local plugin_src="$repo_root/packages/gaai-cloud-plugin/src/hint-file.mjs"

  bash -c "
export PATH='$PATH'

set -euo pipefail
$extra_env

_gaai_read_hint_for_env() {
  local hint_json
  local _timeout_cmd=''
  if command -v gtimeout &>/dev/null; then _timeout_cmd='gtimeout 5'
  elif command -v timeout &>/dev/null; then _timeout_cmd='timeout 5'
  fi
  hint_json=\$(\${_timeout_cmd} node -e \"
    import('$plugin_src').then(m => {
      const h = m.readHint('$test_project_dir');
      if (h) console.log(JSON.stringify(h));
    }).catch(() => {});
  \" 2>/dev/null)
  if [[ -n \"\$hint_json\" ]]; then
    export GAAI_WORKSPACE_ID=\$(echo \"\$hint_json\" | python3 -c \"import json,sys;print(json.load(sys.stdin).get('workspace_id',''))\" 2>/dev/null || echo '')
    export GAAI_ORG_ID=\$(echo \"\$hint_json\" | python3 -c \"import json,sys;print(json.load(sys.stdin).get('org_id',''))\" 2>/dev/null || echo '')
  fi
}

_gaai_resolve_session_env() {
  local UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$'
  if [[ -n \"\${GAAI_WORKSPACE_ID:-}\" ]]; then
    if ! echo \"\$GAAI_WORKSPACE_ID\" | grep -qE \"\$UUID_RE\"; then
      echo '[E99S11] GAAI_WORKSPACE_ID malformed (expected UUIDv4, got: \${GAAI_WORKSPACE_ID:0:8}...); treating as unset.' >&2
      unset GAAI_WORKSPACE_ID
    fi
  fi
  if [[ -n \"\${GAAI_ORG_ID:-}\" ]]; then
    if ! echo \"\$GAAI_ORG_ID\" | grep -qE \"\$UUID_RE\"; then
      echo '[E99S11] GAAI_ORG_ID malformed (expected UUIDv4, got: \${GAAI_ORG_ID:0:8}...); treating as unset.' >&2
      unset GAAI_ORG_ID
    fi
  fi
  if [[ -n \"\${GAAI_WORKSPACE_ID:-}\" && -n \"\${GAAI_ORG_ID:-}\" ]]; then return 0; fi
  _gaai_read_hint_for_env
  if [[ -z \"\${GAAI_WORKSPACE_ID:-}\" || -z \"\${GAAI_ORG_ID:-}\" ]]; then
    echo '[E99S11] Session env unresolved — spawned subprocesses will see no workspace binding; E99S05 AC5 will surface session binding unresolved to the user.' >&2
  fi
}

_gaai_resolve_session_env 2>&1
echo \"RESULT_WS=\${GAAI_WORKSPACE_ID:-}\"
echo \"RESULT_ORG=\${GAAI_ORG_ID:-}\"
" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

echo "E99S11 — env-inheritance tests"
echo ""

# T1: operator env present + valid → preserved, no hint needed
echo "T1: operator env present + valid → preserved"
{
  TMPDIR_T1="$(mktemp -d)"
  OUT="$(_run_scenario "$TMPDIR_T1" \
    "export GAAI_WORKSPACE_ID='550e8400-e29b-41d4-a716-446655440000'
     export GAAI_ORG_ID='7c9e6679-7425-40de-944b-e07fc1f90ae7'")"
  WS="$(echo "$OUT" | grep '^RESULT_WS=' | cut -d= -f2)"
  if [[ "$WS" == "550e8400-e29b-41d4-a716-446655440000" ]]; then
    pass "GAAI_WORKSPACE_ID preserved from operator env"
  else
    fail "GAAI_WORKSPACE_ID changed: got '$WS'"
  fi
  rm -rf "$TMPDIR_T1"
}

# T2: hint-only → exact UUID from hint file (AC4 functional gate — AC6 requirement)
echo "T2: hint-only → values match hint exactly"
{
  TMPDIR_T2="$(mktemp -d)"
  WS_ID="a3bb189e-8bf9-3888-9912-ace4e6543002"
  ORG_ID="c2f2aee2-5f4e-4fcf-b534-7d15cad6123a"
  _write_hint "$TMPDIR_T2" "$WS_ID" "$ORG_ID"

  OUT="$(_run_scenario "$TMPDIR_T2" "")"
  WS="$(echo "$OUT" | grep '^RESULT_WS=' | cut -d= -f2)"
  ORG="$(echo "$OUT" | grep '^RESULT_ORG=' | cut -d= -f2)"

  if [[ "$WS" == "$WS_ID" ]]; then
    pass "GAAI_WORKSPACE_ID equals hint's workspace_id exactly"
  else
    fail "GAAI_WORKSPACE_ID mismatch: expected '$WS_ID', got '$WS'"
  fi
  if [[ "$ORG" == "$ORG_ID" ]]; then
    pass "GAAI_ORG_ID equals hint's org_id exactly"
  else
    fail "GAAI_ORG_ID mismatch: expected '$ORG_ID', got '$ORG'"
  fi
  rm -rf "$TMPDIR_T2"
}

# T3: no env + no hint → vars empty + WARN emitted
echo "T3: nothing set → vars empty + WARN on stderr"
{
  TMPDIR_T3="$(mktemp -d)"
  OUT="$(_run_scenario "$TMPDIR_T3" "")"
  WS="$(echo "$OUT" | grep '^RESULT_WS=' | cut -d= -f2 || echo '')"
  WARN="$(echo "$OUT" | grep 'E99S11' | grep -v RESULT || echo '')"

  if [[ -z "$WS" ]]; then
    pass "GAAI_WORKSPACE_ID empty when nothing set"
  else
    fail "unexpected GAAI_WORKSPACE_ID: '$WS'"
  fi
  if [[ -n "$WARN" ]]; then
    pass "WARN message emitted"
  else
    fail "expected [E99S11] WARN, got nothing (output: $OUT)"
  fi
  rm -rf "$TMPDIR_T3"
}

# T4: malformed operator env → WARN + unset + hint fallback
echo "T4: malformed operator env → WARN + unset + hint fallback"
{
  TMPDIR_T4="$(mktemp -d)"
  WS_ID_HINT="b3bb189e-8bf9-3888-9912-ace4e6543002"
  ORG_ID_HINT="d2f2aee2-5f4e-4fcf-b534-7d15cad6123a"
  _write_hint "$TMPDIR_T4" "$WS_ID_HINT" "$ORG_ID_HINT"

  OUT="$(_run_scenario "$TMPDIR_T4" \
    "export GAAI_WORKSPACE_ID='not-a-uuid'
     export GAAI_ORG_ID='also-not-a-uuid'")"
  WS="$(echo "$OUT" | grep '^RESULT_WS=' | cut -d= -f2 || echo '')"
  WARN="$(echo "$OUT" | grep 'malformed' || echo '')"

  if [[ -n "$WARN" ]]; then
    pass "malformed WARN emitted"
  else
    fail "expected 'malformed' WARN, got: '$OUT'"
  fi
  if [[ "$WS" == "$WS_ID_HINT" ]]; then
    pass "GAAI_WORKSPACE_ID fell back to hint after malformed operator env"
  else
    fail "expected hint fallback '$WS_ID_HINT', got '$WS'"
  fi
  rm -rf "$TMPDIR_T4"
}

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo "All tests PASSED."
  exit 0
else
  echo "SOME TESTS FAILED."
  exit 1
fi
