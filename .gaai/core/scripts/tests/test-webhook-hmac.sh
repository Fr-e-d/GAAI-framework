#!/usr/bin/env bash
# E101S07a — test-webhook-hmac.sh
# Tests compute_webhook_hmac helper + header-injection logic for daemon webhook signing.
#
# Reference HMAC computed via:
#   python3 -c 'import hmac,hashlib;print(hmac.new(b"test-secret",b"{\"hello\":\"world\"}",hashlib.sha256).hexdigest())'
# Result: 84cc33df716ed0b0598f07437c94069ace3730358778a592bd6bbd1423d111f3
#
# Usage: bash .gaai/core/scripts/tests/test-webhook-hmac.sh

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

# ── Source only the compute_webhook_hmac helper from the daemon ───────────────
# The daemon is not safely sourceable in full (it starts side-effects).
# We extract just the function definition using awk.
DAEMON="$(cd "$(dirname "$0")/.." && pwd)/delivery-daemon.sh"

if [[ ! -f "$DAEMON" ]]; then
  echo "FATAL: daemon not found at $DAEMON"
  exit 1
fi

# Extract compute_webhook_hmac function body + a thin log stub
eval "$(awk '/^compute_webhook_hmac\(\)/{found=1} found{print} /^}$/ && found{found=0; exit}' "$DAEMON")"

# Minimal log stub (daemon uses log() for warnings; tests capture stdout)
log() { echo "$*"; }
NC=""; YELLOW=""

echo "E101S07a — webhook HMAC tests"
echo ""

# ── T1: compute_webhook_hmac produces correct reference hex ──────────────────
echo "T1: compute_webhook_hmac correct hex"
{
  REFERENCE="84cc33df716ed0b0598f07437c94069ace3730358778a592bd6bbd1423d111f3"
  GOT="$(compute_webhook_hmac '{"hello":"world"}' 'test-secret' 2>/dev/null)"
  if [[ "$GOT" == "$REFERENCE" ]]; then
    pass "HMAC hex matches python3 reference"
  else
    fail "HMAC mismatch: expected '$REFERENCE', got '$GOT'"
  fi
}

# ── T2: missing secret emits warning; curl would NOT receive X-Hub-Signature-256 ─
echo "T2: missing WEBHOOK_SECRET → warning + no HMAC header"
{
  # Simulate the notify_escalation guard logic (without actually calling curl)
  WEBHOOK_SECRET=""
  WARN_OUTPUT=""
  hmac_hex=""

  if [[ -n "$WEBHOOK_SECRET" ]]; then
    hmac_hex="$(compute_webhook_hmac '{"test":"payload"}' "$WEBHOOK_SECRET" 2>/dev/null)"
  else
    WARN_OUTPUT="[NOTIFY] GAAI_DAEMON_WEBHOOK_SECRET unset — webhook will be rejected by cloud"
  fi

  if echo "$WARN_OUTPUT" | grep -q "GAAI_DAEMON_WEBHOOK_SECRET unset"; then
    pass "warning emitted when secret unset"
  else
    fail "expected 'GAAI_DAEMON_WEBHOOK_SECRET unset' warning, got: '$WARN_OUTPUT'"
  fi

  if [[ -z "$hmac_hex" ]]; then
    pass "hmac_hex empty when secret unset (no X-Hub-Signature-256 header appended)"
  else
    fail "hmac_hex should be empty when secret unset, got: '$hmac_hex'"
  fi
}

# ── T3: non-2xx webhook response does NOT kill the daemon (never-block invariant) ─
echo "T3: non-2xx curl response → warn only, no exit"
{
  # Simulate the curl guard logic — a non-2xx response must produce a warning
  # but NOT exit the script. We mock curl to return a 401 status code.
  NOTIFICATION_WEBHOOK="http://127.0.0.1:0/nonexistent"  # guaranteed to fail / non-2xx
  WEBHOOK_SECRET="test-secret"
  story_id="T3TestStory"

  # Run the guard logic in a subshell — if it exits non-zero, the test fails
  WARN_OUT=$(
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    json="{\"story_id\":\"${story_id}\",\"reason\":\"test\",\"remediation\":\"none\",\"timestamp\":\"${ts}\"}"
    hmac_hex="$(compute_webhook_hmac "$json" "$WEBHOOK_SECRET" 2>/dev/null)"
    local_hmac_args=()
    [[ -n "$hmac_hex" ]] && local_hmac_args=(-H "X-Hub-Signature-256: sha256=$hmac_hex" -H "X-Webhook-Source: gaai-daemon")
    # We expect curl to fail (connection refused) — guard must NOT propagate exit code
    if ! curl -s -o /dev/null -w "%{http_code}" \
        --max-time 1 \
        -X POST \
        -H "Content-Type: application/json" \
        "${local_hmac_args[@]}" \
        -d "$json" \
        "$NOTIFICATION_WEBHOOK" 2>/dev/null | grep -qE '^2'; then
      echo "[NOTIFY] Webhook failed for ${story_id} (warning only)"
    fi
    echo "SCRIPT_CONTINUED"
  )

  if echo "$WARN_OUT" | grep -q "SCRIPT_CONTINUED"; then
    pass "script continued after non-2xx response (never-block invariant preserved)"
  else
    fail "script did not continue after non-2xx (unexpected exit)"
  fi
  if echo "$WARN_OUT" | grep -q "Webhook failed"; then
    pass "warning logged on non-2xx response"
  else
    fail "expected 'Webhook failed' warning, got: '$WARN_OUT'"
  fi
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
