#!/usr/bin/env bash
# triage-3phase-hook.test.sh — E134S20 regression test
#
# Verifies that _run_triage_for_story is wired into the live 3-phase pipeline
# (daemon-dispatch.sh), NOT only the dead legacy wrappers in delivery-daemon.sh.
#
# AC1: structural grep confirms hook is defined + called in daemon-dispatch.sh
# AC2: calling _run_triage_for_story with a delta file produces .triage-*.log
# AC3: second call returns already_done without re-running
# AC4: no-delta story produces no log and skips silently
# AC6: this file IS the 3-phase regression test (legacy on_exit check ≠ 3-phase)
#
# Usage: bash .gaai/core/scripts/tests/triage-3phase-hook.test.sh

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPATCH_LIB="${SCRIPT_DIR}/../daemon-dispatch.sh"

# ── Temp environment ──────────────────────────────────────────────────────────
TMPDIR_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_ROOT"; }
trap cleanup EXIT

# Fake project structure
FAKE_PROJECT="${TMPDIR_ROOT}/project"
mkdir -p \
  "${FAKE_PROJECT}/.gaai/project/contexts/artefacts/memory-deltas" \
  "${FAKE_PROJECT}/.gaai/project/contexts/backlog/.delivery-locks" \
  "${FAKE_PROJECT}/.gaai/core/agents" \
  "${FAKE_PROJECT}/.gaai/core/skills/cross/memory-delta-triage"

# Fake agent file (non-empty so the check passes)
echo "Discovery Agent identity stub" > "${FAKE_PROJECT}/.gaai/core/agents/discovery.agent.md"

# Fake skill file
echo "memory-delta-triage SKILL stub" > "${FAKE_PROJECT}/.gaai/core/skills/cross/memory-delta-triage/SKILL.md"

# Fake backlog file (dispatch library requires BACKLOG_FILE)
FAKE_BACKLOG="${FAKE_PROJECT}/active.backlog.yaml"
cat > "$FAKE_BACKLOG" << 'YAML_EOF'
- id: TST-T1
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
YAML_EOF

# Fake SCHEDULER (not called in these unit tests, but must be set)
FAKE_SCHEDULER="${TMPDIR_ROOT}/backlog-scheduler.sh"
cat > "$FAKE_SCHEDULER" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_SCHEDULER"

# Fake claude binary that writes a valid triage verdict to stdout
FAKE_BIN="${TMPDIR_ROOT}/bin"
mkdir -p "$FAKE_BIN"
cat > "${FAKE_BIN}/claude" << 'EOF'
#!/usr/bin/env bash
cat << 'VERDICT_EOF'
## Triage Verdict
mode: draft
delta_id: TST-T1
overall: ACCEPT
candidates:
  - candidate_id: c1
    verdict: ACCEPT
schema_check: pass
VERDICT_EOF
exit 0
EOF
chmod +x "${FAKE_BIN}/claude"

export PATH="${FAKE_BIN}:${PATH}"

# ── Source the dispatch library ───────────────────────────────────────────────
export BACKLOG_FILE="$FAKE_BACKLOG"
export SCHEDULER="$FAKE_SCHEDULER"
export PROJECT_DIR="$FAKE_PROJECT"
export LOCK_DIR="${FAKE_PROJECT}/.gaai/project/contexts/backlog/.delivery-locks"
export ROUTING_LOG_PATH="${TMPDIR_ROOT}/routing.jsonl"

# Source: must NOT trigger daemon main loop — dispatch library is function-only
source "$DISPATCH_LIB"

echo ""
echo "=== triage-3phase-hook.test.sh ==="
echo ""

# ── AC1: Structural check — hook must exist in daemon-dispatch.sh ─────────────
echo "[ AC1 — structural: _run_triage_for_story must be defined in daemon-dispatch.sh ]"

if grep -q "^_run_triage_for_story()" "$DISPATCH_LIB" 2>/dev/null; then
  pass "_run_triage_for_story() is defined in daemon-dispatch.sh"
else
  fail "_run_triage_for_story() NOT found in daemon-dispatch.sh — hook is missing from the 3-phase pipeline"
fi

# Verify the call appears inside handle_commit_phase (not just the legacy legacy on_exit path)
DISPATCH_CALL_COUNT=$(grep -c "_run_triage_for_story" "$DISPATCH_LIB" 2>/dev/null || echo "0")
if [[ "$DISPATCH_CALL_COUNT" -ge 2 ]]; then
  pass "_run_triage_for_story referenced ${DISPATCH_CALL_COUNT}x in daemon-dispatch.sh (definition + call in handle_commit_phase)"
else
  fail "_run_triage_for_story referenced only ${DISPATCH_CALL_COUNT}x in daemon-dispatch.sh — expected ≥2 (definition + call)"
fi

# Verify it is actually called inside handle_commit_phase (within ~30 lines after --set-status done)
if awk '/handle_commit_phase\(\)/{in_fn=1} in_fn && /_run_triage_for_story/{found=1; exit} in_fn && /^}$/{in_fn=0}' "$DISPATCH_LIB" | grep -q "_run_triage_for_story" 2>/dev/null ||
   awk 'f && /_run_triage_for_story/{print; exit} /^handle_commit_phase\(\)/{f=1}' "$DISPATCH_LIB" | grep -q "_run_triage_for_story"; then
  pass "_run_triage_for_story is called inside handle_commit_phase"
else
  fail "_run_triage_for_story is NOT called inside handle_commit_phase"
fi

echo ""

# ── AC2: Triage fires and produces .triage-*.log ─────────────────────────────
echo "[ AC2 — expected behavior: triage fires on done, produces log ]"

DELTA_FILE="${FAKE_PROJECT}/.gaai/project/contexts/artefacts/memory-deltas/TST-T1.memory-delta.md"
cat > "$DELTA_FILE" << 'EOF'
# Memory delta for TST-T1
Some candidate memory entry.
EOF

TRIAGE_RESULT="not_set"
_run_triage_for_story "TST-T1"

TRIAGE_LOG="${LOCK_DIR}/.triage-TST-T1.log"
if [[ -f "$TRIAGE_LOG" ]]; then
  pass ".triage-TST-T1.log was created"
else
  fail ".triage-TST-T1.log was NOT created"
fi

if grep -q "## Triage Verdict" "$TRIAGE_LOG" 2>/dev/null; then
  pass ".triage-TST-T1.log contains '## Triage Verdict'"
else
  fail ".triage-TST-T1.log does NOT contain '## Triage Verdict'"
fi

if [[ "$TRIAGE_RESULT" == draft_produced* ]]; then
  pass "TRIAGE_RESULT starts with 'draft_produced': ${TRIAGE_RESULT}"
else
  fail "TRIAGE_RESULT is '${TRIAGE_RESULT}' (expected draft_produced|...)"
fi

# AC5: delta file must NOT have been modified
DELTA_MTIME_BEFORE=$(stat -f "%m" "$DELTA_FILE" 2>/dev/null || stat -c "%Y" "$DELTA_FILE" 2>/dev/null || echo "0")
# (File was not modified by _run_triage_for_story — we check it didn't gain a Verdict block)
if ! grep -q "## Triage Verdict" "$DELTA_FILE" 2>/dev/null; then
  pass "AC5: delta file was NOT modified (verdict is in log, not delta)"
else
  fail "AC5: delta file was modified — draft mode contract violated"
fi

echo ""

# ── AC3: Single-fire guard — second call must skip ───────────────────────────
echo "[ AC3 — single-fire guard: second call must return already_done ]"

# Record log mtime before second call
LOG_MTIME_BEFORE=$(stat -f "%m" "$TRIAGE_LOG" 2>/dev/null || stat -c "%Y" "$TRIAGE_LOG" 2>/dev/null || echo "0")
sleep 1  # Ensure mtime would differ if file were rewritten

TRIAGE_RESULT="not_set"
_run_triage_for_story "TST-T1"

if [[ "$TRIAGE_RESULT" == "no triage — reason: already_done" ]]; then
  pass "Second call returned: ${TRIAGE_RESULT}"
else
  fail "Second call returned '${TRIAGE_RESULT}' (expected 'no triage — reason: already_done')"
fi

LOG_MTIME_AFTER=$(stat -f "%m" "$TRIAGE_LOG" 2>/dev/null || stat -c "%Y" "$TRIAGE_LOG" 2>/dev/null || echo "0")
if [[ "$LOG_MTIME_BEFORE" == "$LOG_MTIME_AFTER" ]]; then
  pass ".triage-TST-T1.log was NOT overwritten on second call (mtime unchanged)"
else
  fail ".triage-TST-T1.log was overwritten on second call (mtime changed)"
fi

echo ""

# ── AC4: No-delta story — skip without error ─────────────────────────────────
echo "[ AC4 — no-delta: story with no delta file skips without error ]"

TRIAGE_RESULT="not_set"
_run_triage_for_story "TST-T2"  # no delta file created for TST-T2

if [[ "$TRIAGE_RESULT" == "no triage — reason: no_delta" ]]; then
  pass "No-delta story returned: ${TRIAGE_RESULT}"
else
  fail "No-delta story returned '${TRIAGE_RESULT}' (expected 'no triage — reason: no_delta')"
fi

if [[ ! -f "${LOCK_DIR}/.triage-TST-T2.log" ]]; then
  pass "No .triage-TST-T2.log created for no-delta story"
else
  fail ".triage-TST-T2.log was created for no-delta story (unexpected)"
fi

echo ""

# ── Whitelist check: _run_triage_for_story must not INVOKE non-triage skills ──
# The triage prompt legitimately NAMES forbidden skills (to tell the agent not to
# use them). This check looks for actual bash-level invocations of other skill
# scripts, not mere textual mentions in the prompt.
echo "[ Whitelist: _run_triage_for_story must only spawn claude (no other skill scripts) ]"

TRIAGE_FN_BODY=$(awk '/^_run_triage_for_story\(\)/{in_fn=1} in_fn{print} in_fn && /^\}$/{in_fn=0}' "$DISPATCH_LIB")

# Verify the only external program spawned is 'claude' (and standard tools: cat, date, grep, touch, etc.)
if echo "$TRIAGE_FN_BODY" | grep -qE 'bash.*skill|run_skill|invoke_skill|gaai-discover|gaai-bootstrap|memory-ingest\.sh|memory-refresh\.sh' 2>/dev/null; then
  fail "_run_triage_for_story invokes a non-triage skill script from bash"
else
  pass "No non-triage skill scripts are invoked from _run_triage_for_story"
fi

# Verify memory-delta-triage is referenced (ensures we didn't accidentally remove the skill path)
if echo "$TRIAGE_FN_BODY" | grep -q "memory-delta-triage" 2>/dev/null; then
  pass "memory-delta-triage skill path is referenced in function"
else
  fail "memory-delta-triage skill path is NOT referenced in function"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=== Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
