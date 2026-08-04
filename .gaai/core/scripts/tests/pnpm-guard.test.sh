#!/usr/bin/env bash
# pnpm-guard.test.sh — unit tests for _ensure_worktree_deps_fresh()
#
# Tests the 4 scenarios from AC6:
#   T1  : marker hash matches current lockfile → skip (exit 0, 2 log lines, no pnpm)
#   T1b : timing ≤100ms on skip path
#   T2  : marker absent → install runs + marker written (exit 0, 3 log lines, pnpm called)
#   T3  : marker hash mismatch → install runs + marker updated (exit 0, 3 log lines, pnpm called)
#   T4  : install fails → non-zero exit, no marker write
#
# Usage: bash .gaai/core/scripts/tests/pnpm-guard.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$SCRIPT_DIR/../daemon-dispatch.sh"

# ── Fixture setup ──────────────────────────────────────────────────────────────
FIXTURE_DIR="/tmp/gaai-pnpm-guard-test-$$"
WT_PATH="$FIXTURE_DIR/worktree"
MOCK_BIN="$FIXTURE_DIR/bin"
PNPM_LOG="$FIXTURE_DIR/pnpm-calls.log"

mkdir -p "$MOCK_BIN" "$WT_PATH"
touch "$PNPM_LOG"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── Mock pnpm binary ───────────────────────────────────────────────────────────
cat > "$MOCK_BIN/pnpm" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "pnpm $*" >> "$PNPM_LOG"
exit "${MOCK_PNPM_EXIT_CODE:-0}"
MOCK_EOF
chmod +x "$MOCK_BIN/pnpm"

export PATH="$MOCK_BIN:$PATH"
export PNPM_LOG

# ── Minimal daemon globals ────────────────────────────────────────────────────
BACKLOG_FILE="$FIXTURE_DIR/active.backlog.yaml"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"
PROJECT_DIR="$FIXTURE_DIR"
LOCK_DIR="$FIXTURE_DIR/delivery-locks"
mkdir -p "$LOCK_DIR"
touch "$BACKLOG_FILE"
export BACKLOG_FILE SCHEDULER PROJECT_DIR LOCK_DIR

# ── Source daemon-dispatch.sh ──────────────────────────────────────────────────
# shellcheck source=/dev/null
source "$DISPATCH"

# ── Helper ────────────────────────────────────────────────────────────────────
line_count() {
  echo "$1" | grep -c '' || true
}

compute_hash() {
  local f="$1"
  sha256sum < "$f" 2>/dev/null | awk '{print $1}' || shasum -a 256 < "$f" 2>/dev/null | awk '{print $1}'
}

# ── Create lockfile with known content ────────────────────────────────────────
LOCKFILE="$WT_PATH/pnpm-lock.yaml"
echo "lockfileVersion: 6.0" > "$LOCKFILE"
echo "imports:" >> "$LOCKFILE"
KNOWN_HASH=$(compute_hash "$LOCKFILE")

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: marker hash matches → skip install ==="

printf '%s\n' "$KNOWN_HASH" > "$WT_PATH/.gaai-pnpm-install-marker"
> "$PNPM_LOG"

output=$(_ensure_worktree_deps_fresh "T1-STORY" "$WT_PATH")
rc=$?

if [[ $rc -eq 0 ]]; then
  pass "T1: exit 0"
else
  fail "T1: expected exit 0, got $rc"
fi

lc=$(line_count "$output")
if [[ $lc -eq 2 ]]; then
  pass "T1: exactly 2 log lines"
else
  fail "T1: expected 2 log lines, got $lc"
fi

if echo "$output" | grep -q "checking worktree deps freshness"; then
  pass "T1: log contains 'checking worktree deps freshness'"
else
  fail "T1: missing 'checking worktree deps freshness' in output"
fi

if echo "$output" | grep -q "worktree deps fresh (marker hash matches)"; then
  pass "T1: log contains 'worktree deps fresh (marker hash matches)'"
else
  fail "T1: missing 'worktree deps fresh' in output"
fi

pnpm_calls=$(wc -l < "$PNPM_LOG" | tr -d ' ')
if [[ "$pnpm_calls" -eq 0 ]]; then
  pass "T1: pnpm not invoked"
else
  fail "T1: pnpm was invoked $pnpm_calls times (expected 0)"
fi

marker_after=$(cat "$WT_PATH/.gaai-pnpm-install-marker" 2>/dev/null)
if [[ "$marker_after" == "$KNOWN_HASH" ]]; then
  pass "T1: marker unchanged"
else
  fail "T1: marker changed (expected $KNOWN_HASH, got $marker_after)"
fi

# ── T1b: timing ≤100ms ────────────────────────────────────────────────────────
echo ""
echo "=== T1b: skip path timing ≤100ms ==="

if [[ -n "${EPOCHREALTIME:-}" ]]; then
  t0=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  _ensure_worktree_deps_fresh "T1b-STORY" "$WT_PATH" >/dev/null
  t1=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  elapsed=$(( t1 - t0 ))
  if [[ $elapsed -le 100 ]]; then
    pass "T1b: skip path elapsed ${elapsed}ms ≤ 100ms"
  else
    fail "T1b: skip path elapsed ${elapsed}ms > 100ms"
  fi
else
  echo "  WARN: EPOCHREALTIME unavailable (bash < 5) — T1b timing skipped"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: marker absent → install runs, marker written ==="

rm -f "$WT_PATH/.gaai-pnpm-install-marker"
> "$PNPM_LOG"
export MOCK_PNPM_EXIT_CODE=0

output=$(_ensure_worktree_deps_fresh "T2-STORY" "$WT_PATH")
rc=$?

if [[ $rc -eq 0 ]]; then
  pass "T2: exit 0"
else
  fail "T2: expected exit 0, got $rc"
fi

lc=$(line_count "$output")
if [[ $lc -eq 3 ]]; then
  pass "T2: exactly 3 log lines"
else
  fail "T2: expected 3 log lines, got $lc"
fi

if echo "$output" | grep -q "worktree deps stale or absent"; then
  pass "T2: log contains 'worktree deps stale or absent'"
else
  fail "T2: missing 'worktree deps stale or absent' in output"
fi

if echo "$output" | grep -q "pnpm install completed in"; then
  pass "T2: log contains 'pnpm install completed in'"
else
  fail "T2: missing 'pnpm install completed in' in output"
fi

pnpm_calls=$(wc -l < "$PNPM_LOG" | tr -d ' ')
if [[ "$pnpm_calls" -eq 1 ]]; then
  pass "T2: pnpm called exactly once"
else
  fail "T2: pnpm called $pnpm_calls times (expected 1)"
fi

pnpm_args=$(head -1 "$PNPM_LOG")
if echo "$pnpm_args" | grep -q "\-\-frozen-lockfile"; then
  pass "T2: pnpm called with --frozen-lockfile"
else
  fail "T2: pnpm not called with --frozen-lockfile: $pnpm_args"
fi

marker_hash=$(cat "$WT_PATH/.gaai-pnpm-install-marker" 2>/dev/null)
if [[ "$marker_hash" == "$KNOWN_HASH" ]]; then
  pass "T2: marker contains correct lockfile hash"
else
  fail "T2: marker hash mismatch (expected $KNOWN_HASH, got $marker_hash)"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: marker hash mismatch → install runs, marker updated ==="

OLD_HASH="0000000000000000000000000000000000000000000000000000000000000000"
printf '%s\n' "$OLD_HASH" > "$WT_PATH/.gaai-pnpm-install-marker"
> "$PNPM_LOG"
export MOCK_PNPM_EXIT_CODE=0

output=$(_ensure_worktree_deps_fresh "T3-STORY" "$WT_PATH")
rc=$?

if [[ $rc -eq 0 ]]; then
  pass "T3: exit 0"
else
  fail "T3: expected exit 0, got $rc"
fi

lc=$(line_count "$output")
if [[ $lc -eq 3 ]]; then
  pass "T3: exactly 3 log lines"
else
  fail "T3: expected 3 log lines, got $lc"
fi

if echo "$output" | grep -q "worktree deps stale or absent"; then
  pass "T3: log contains 'worktree deps stale or absent'"
else
  fail "T3: missing 'worktree deps stale or absent' in output"
fi

pnpm_calls=$(wc -l < "$PNPM_LOG" | tr -d ' ')
if [[ "$pnpm_calls" -eq 1 ]]; then
  pass "T3: pnpm called exactly once"
else
  fail "T3: pnpm called $pnpm_calls times (expected 1)"
fi

marker_hash=$(cat "$WT_PATH/.gaai-pnpm-install-marker" 2>/dev/null)
if [[ "$marker_hash" == "$KNOWN_HASH" ]]; then
  pass "T3: marker updated to new hash (not old)"
else
  fail "T3: marker not updated (expected $KNOWN_HASH, got $marker_hash)"
fi

if [[ "$marker_hash" != "$OLD_HASH" ]]; then
  pass "T3: marker no longer contains old hash"
else
  fail "T3: marker still contains old hash"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: install fails → non-zero, no marker write ==="

rm -f "$WT_PATH/.gaai-pnpm-install-marker"
> "$PNPM_LOG"
export MOCK_PNPM_EXIT_CODE=1

output=$(_ensure_worktree_deps_fresh "T4-STORY" "$WT_PATH")
rc=$?

if [[ $rc -ne 0 ]]; then
  pass "T4: exit non-zero"
else
  fail "T4: expected non-zero exit, got $rc"
fi

pnpm_calls=$(wc -l < "$PNPM_LOG" | tr -d ' ')
if [[ "$pnpm_calls" -eq 1 ]]; then
  pass "T4: pnpm called exactly once"
else
  fail "T4: pnpm called $pnpm_calls times (expected 1)"
fi

if [[ ! -f "$WT_PATH/.gaai-pnpm-install-marker" ]]; then
  pass "T4: marker not written"
else
  fail "T4: marker was written (expected absent)"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Summary ==="
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo ""
  echo "RESULT: FAIL (${FAIL_COUNT} test(s) failed)"
  exit 1
fi

echo ""
echo "RESULT: PASS (all ${PASS_COUNT} tests passed)"
exit 0
