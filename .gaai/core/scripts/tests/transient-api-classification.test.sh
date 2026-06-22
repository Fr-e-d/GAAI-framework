#!/usr/bin/env bash
# transient-api-classification.test.sh — regression for transient API failure detection
#
# Covers AC6: log fixtures assert:
#   (a) 529/overloaded phase log  → classified transient → returns 0
#   (b) deterministic error log   → terminal failure    → returns 1
#   (c) rate_limit main log       → classified transient → returns 0
#
# Also verifies: phase log (not only main log) is scanned (AC3).
#
# Usage: bash .gaai/core/scripts/tests/transient-api-classification.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

# ── Fixture setup ──────────────────────────────────────────────────────────────
FIXTURE_DIR="$(mktemp -d /tmp/gaai-transient-api-test-XXXXXX)"
STUB_BIN="$FIXTURE_DIR/stub-bin"
LOG_DIR="$FIXTURE_DIR/delivery-logs"
WORKTREE_DIR="$FIXTURE_DIR/story-worktree"
PHASE_LOG_DIR="$WORKTREE_DIR/.delivery-logs"
TEST_STORY="TST-TRANSIENT-API-001"
PROJECT_DIR="$FIXTURE_DIR/project"

mkdir -p "$STUB_BIN" "$LOG_DIR" "$PHASE_LOG_DIR" "$PROJECT_DIR"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── git stub: returns a known worktree for TEST_STORY ──────────────────────────
# Emits exact `git worktree list --porcelain` format so awk can parse it.
cat > "$STUB_BIN/git" <<GIT_STUB
#!/usr/bin/env bash
if [[ "\$*" =~ "worktree list --porcelain" ]]; then
  printf 'worktree %s\nHEAD 0000000000000000000000000000000000000000\nbranch refs/heads/story/$TEST_STORY\n\n' "$WORKTREE_DIR"
  exit 0
fi
exec /usr/bin/git "\$@"
GIT_STUB
chmod +x "$STUB_BIN/git"

# Prepend stub bin to PATH for the duration of this test
export PATH="$STUB_BIN:$PATH"

# ── Local is_rate_limit_failure — mirrors the production generated-wrapper ─────
# Uses runtime vars (LOG_DIR, story_id, PROJECT_DIR) that the daemon bakes in at
# wrapper-generation time. Grep patterns must stay in sync with delivery-daemon.sh.
is_rate_limit_failure() {
  local _wt _log
  local -a _logs
  _logs=("$LOG_DIR/${story_id}.log")

  _wt=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{wt=substr($0,10)} /^branch refs\/heads\/story\/'"${story_id}"'$/{print wt; exit}' \
    || echo "")
  if [[ -n "$_wt" && -d "$_wt" ]]; then
    _logs+=( "$_wt/.delivery-logs/${story_id}.plan.log"
             "$_wt/.delivery-logs/${story_id}.impl.log"
             "$_wt/.delivery-logs/${story_id}.qa.log" )
  fi

  for _log in "${_logs[@]}"; do
    [[ -f "$_log" ]] || continue
    if grep -q '"type":"rate_limit_event"' "$_log" && grep -q '"status":"rejected"' "$_log"; then return 0; fi
    if grep -q '"error":"rate_limit"' "$_log"; then return 0; fi
    if grep -qE '"error":"overloaded"' "$_log"; then return 0; fi
    if grep -qE '"subtype":"api_retry"' "$_log"; then return 0; fi
    if grep -qE '"api_error_status":[[:space:]]*529|"error_status":[[:space:]]*529' "$_log"; then return 0; fi
  done
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# AC6a — 529/overloaded in QA phase log → transient (return 0)
# Simulates E243S02: QA phase hit 529 Overloaded, errors land in the phase log
# (not the main delivery log). No code defect — must be classified as transient.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC6a: 529/overloaded phase log → classified transient (return 0) ==="

story_id="$TEST_STORY"

# Main log is empty (no 529 there — the errors are in the phase log)
touch "$LOG_DIR/${story_id}.log"

# QA phase log contains 529 / overloaded signatures from Anthropic API
cat > "$PHASE_LOG_DIR/${story_id}.qa.log" <<'FIXTURE_A'
{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Running QA..."}}
{"type":"message_delta","delta":{"stop_reason":"end_turn"}}
{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"},"error":"overloaded"}
{"api_error_status":529,"subtype":"api_retry","retry_count":1}
{"api_error_status":529,"subtype":"api_retry","retry_count":2}
{"api_error_status":529,"subtype":"api_retry","retry_count":3}
{"error":"server_error","error_status":529,"message":"Service temporarily unavailable"}
FIXTURE_A

echo "T1: 529/overloaded in qa phase log → function returns 0 (transient)"
RC=0
is_rate_limit_failure || RC=$?
if [[ "$RC" -eq 0 ]]; then
  pass "T1: is_rate_limit_failure returned 0 (transient) for 529/overloaded qa phase log"
else
  fail "T1: expected return 0 (transient), got $RC — 529/overloaded not detected"
fi

echo "T2: phase log coverage — 529 NOT in main log but still detected (AC3)"
# Verify main log alone would NOT trigger (proves phase log was scanned)
MAIN_RC=0
if grep -qE '"error":"overloaded"' "$LOG_DIR/${story_id}.log" 2>/dev/null; then
  fail "T2-precondition: main log should be empty of 529 markers"
else
  pass "T2-precondition: main log clean — 529 only in phase log"
fi
# The function found it → phase log was scanned ✓ (already confirmed by T1)
if [[ "$RC" -eq 0 ]]; then
  pass "T2: phase log (qa) was scanned — 529 detected despite clean main log"
else
  fail "T2: phase log was NOT scanned or 529 not detected"
fi

echo "T3: api_error_status:529 pattern matches (AC1 boundary)"
# Isolated check on the specific api_error_status grep pattern
TMP_LOG="$FIXTURE_DIR/tmp-529-status.log"
echo '{"api_error_status":529,"subtype":"api_retry"}' > "$TMP_LOG"
if grep -qE '"api_error_status":[[:space:]]*529' "$TMP_LOG"; then
  pass "T3: api_error_status:529 grep pattern matches"
else
  fail "T3: api_error_status:529 grep pattern failed to match"
fi
rm -f "$TMP_LOG"

echo "T4: error_status:529 alternate key pattern matches (AC1 boundary)"
TMP_LOG="$FIXTURE_DIR/tmp-error-status.log"
echo '{"error":"server_error","error_status":529}' > "$TMP_LOG"
if grep -qE '"error_status":[[:space:]]*529' "$TMP_LOG"; then
  pass "T4: error_status:529 alternate key matches"
else
  fail "T4: error_status:529 alternate key failed to match"
fi
rm -f "$TMP_LOG"

# ── cleanup between test cases ──────────────────────────────────────────────
rm -f "$LOG_DIR/${story_id}.log" "$PHASE_LOG_DIR/${story_id}.qa.log"

# ═══════════════════════════════════════════════════════════════════════════════
# AC6b — deterministic non-API error → terminal (return 1)
# A real code defect or invalid-api-key error must NOT be classified transient.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC6b: deterministic non-API error → terminal failure (return 1) ==="

story_id="$TEST_STORY"

# Main log: a real authentication / code-level error — no 529 / rate-limit
cat > "$LOG_DIR/${story_id}.log" <<'FIXTURE_B'
{"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","content":[]}}
{"type":"error","error":{"type":"authentication_error","message":"Invalid API key"},"error":"invalid_api_key"}
FIXTURE_B

# Phase logs absent (QA never started)

echo "T5: deterministic error (invalid_api_key) → function returns 1 (terminal)"
RC=0
is_rate_limit_failure && RC=0 || RC=$?
if [[ "$RC" -ne 0 ]]; then
  pass "T5: is_rate_limit_failure returned non-zero (terminal) for invalid_api_key"
else
  fail "T5: expected non-zero return (terminal), got 0 — false positive transient"
fi

echo "T6: no false positive when log has no API-outage signature (AC4)"
TMP_LOG="$FIXTURE_DIR/tmp-generic-error.log"
echo '{"error":"permission_denied","message":"Access denied to resource"}' > "$TMP_LOG"
if grep -qE '"error":"overloaded"|"subtype":"api_retry"|"api_error_status":[[:space:]]*529|"error_status":[[:space:]]*529' "$TMP_LOG"; then
  fail "T6: false positive — generic error log triggered transient pattern"
else
  pass "T6: no false positive — generic error not matched by transient patterns"
fi
rm -f "$TMP_LOG"

# ── cleanup ──────────────────────────────────────────────────────────────────
rm -f "$LOG_DIR/${story_id}.log"

# ═══════════════════════════════════════════════════════════════════════════════
# AC6c — existing rate_limit in main log → still transient (return 0)
# Non-regression: the original rate-limit path must continue to work.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC6c: existing rate_limit pattern → still classified transient (AC4 non-regression) ==="

story_id="$TEST_STORY"

# Main log: classic rate_limit_event signature (pre-existing behavior)
cat > "$LOG_DIR/${story_id}.log" <<'FIXTURE_C'
{"type":"rate_limit_event","status":"rejected","retry_after":60}
FIXTURE_C

echo "T7: rate_limit_event + rejected → function returns 0 (transient, non-regression)"
RC=0
is_rate_limit_failure || RC=$?
if [[ "$RC" -eq 0 ]]; then
  pass "T7: rate_limit_event+rejected still classified transient"
else
  fail "T7: rate_limit_event+rejected broke — existing rate-limit path regressed"
fi

echo "T8: error:rate_limit pattern → function returns 0 (non-regression)"
rm -f "$LOG_DIR/${story_id}.log"
cat > "$LOG_DIR/${story_id}.log" <<'FIXTURE_C2'
{"error":"rate_limit","message":"Too many requests"}
FIXTURE_C2
RC=0
is_rate_limit_failure || RC=$?
if [[ "$RC" -eq 0 ]]; then
  pass "T8: error:rate_limit still classified transient"
else
  fail "T8: error:rate_limit broke — existing rate_limit path regressed"
fi

# ── cleanup ──────────────────────────────────────────────────────────────────
rm -f "$LOG_DIR/${story_id}.log"

# ═══════════════════════════════════════════════════════════════════════════════
# AC3 coverage — no phase log file written yet (plan died early) → no crash
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC3 edge: missing phase log files → graceful skip (no crash) ==="

story_id="$TEST_STORY"

# Main log has a real non-transient error; no phase logs present
cat > "$LOG_DIR/${story_id}.log" <<'FIXTURE_D'
{"error":"context_length_exceeded","message":"Prompt too long"}
FIXTURE_D
# Phase logs deliberately absent

echo "T9: missing phase log files → function returns 1 safely (no crash)"
RC=0
is_rate_limit_failure && RC=0 || RC=$?
if [[ "$RC" -ne 0 ]]; then
  pass "T9: function returned non-zero without crashing when phase logs absent"
else
  fail "T9: false positive — context_length_exceeded incorrectly classified as transient"
fi

# ── cleanup ──────────────────────────────────────────────────────────────────
rm -f "$LOG_DIR/${story_id}.log"

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "══════════════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
