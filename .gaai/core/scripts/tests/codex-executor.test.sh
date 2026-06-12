#!/usr/bin/env bash
# ── codex-executor.test.sh ─────────────────────────────────────────────────
# Regression coverage for the GAAI daemon's Codex headless executor.
#
# Run: bash .gaai/core/scripts/tests/codex-executor.test.sh
# Exit 0 = all pass.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TMPDIR_TEST="$(mktemp -d /tmp/gaai-codex-executor-test-XXXXXX)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

PROJECT_DIR="$REPO_ROOT"
LOCK_DIR="$TMPDIR_TEST/locks"
WORKTREE="$TMPDIR_TEST/worktree"
FAKEBIN="$TMPDIR_TEST/bin"
mkdir -p "$LOCK_DIR" "$WORKTREE/.delivery-logs" "$FAKEBIN"

PROMPT_FILE="$TMPDIR_TEST/prompt.md"
LOG_FILE="$WORKTREE/.delivery-logs/T-CODEX.plan.log"
ARGS_FILE="$TMPDIR_TEST/codex.args"
STDIN_FILE="$TMPDIR_TEST/codex.stdin"
printf 'Write the required GAAI artefact.\n' > "$PROMPT_FILE"

cat > "$FAKEBIN/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$GAAI_CODEX_ARGS_FILE"
cat > "$GAAI_CODEX_STDIN_FILE"
printf '{"type":"thread.started","thread_id":"test"}\n'
printf '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}\n'
SH
chmod +x "$FAKEBIN/codex"

source "$REPO_ROOT/.gaai/core/scripts/daemon-dispatch.sh"

echo "T1: codex executor builds codex exec command and streams JSONL"
PATH="$FAKEBIN:$PATH" \
GAAI_DAEMON_EXECUTOR=codex \
GAAI_CODEX_MODEL=gpt-test \
GAAI_CODEX_SANDBOX=workspace-write \
GAAI_CODEX_ARGS_FILE="$ARGS_FILE" \
GAAI_CODEX_STDIN_FILE="$STDIN_FILE" \
  _run_claude_with_loop_breaker \
    "T-CODEX" "plan" "$LOG_FILE" "$PROMPT_FILE" "$WORKTREE" >/dev/null 2>&1
T1_RC=$?

if [[ "$T1_RC" -eq 0 ]]; then
  pass "T1a: codex executor returns child exit code 0"
else
  fail "T1a: codex executor returned $T1_RC"
fi

EXPECTED_ARGS="exec --json --sandbox workspace-write --cd $WORKTREE --model gpt-test --ephemeral -"
if [[ "$(cat "$ARGS_FILE" 2>/dev/null)" == "$EXPECTED_ARGS" ]]; then
  pass "T1b: codex exec args are canonical"
else
  fail "T1b: codex exec args mismatch: $(cat "$ARGS_FILE" 2>/dev/null)"
fi

if cmp -s "$PROMPT_FILE" "$STDIN_FILE"; then
  pass "T1c: prompt file is passed to codex exec stdin"
else
  fail "T1c: prompt stdin mismatch"
fi

if grep -q '"type":"turn.completed"' "$LOG_FILE" 2>/dev/null; then
  pass "T1d: codex JSONL stream is written to phase log"
else
  fail "T1d: codex JSONL stream missing from phase log"
fi

echo "T2: unsupported executor is rejected before spawn"
GAAI_DAEMON_EXECUTOR=bogus \
  _run_claude_with_loop_breaker \
    "T-CODEX" "plan" "$LOG_FILE" "$PROMPT_FILE" "$WORKTREE" >/dev/null 2>&1
T2_RC=$?

if [[ "$T2_RC" -eq 2 ]]; then
  pass "T2a: unsupported executor returns usage error"
else
  fail "T2a: unsupported executor returned $T2_RC"
fi

echo
echo "codex-executor tests: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
