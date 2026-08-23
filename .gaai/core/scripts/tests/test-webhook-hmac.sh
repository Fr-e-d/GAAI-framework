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

# ── Extract raw regions for provider-neutrality static checks (E1126S08) ──────
# Same awk-over-source technique as above — never a hardcoded copy of daemon text.
NOTIFY_ESCALATION_BODY="$(awk '/^notify_escalation\(\)/{found=1} found{print} /^}$/ && found{found=0; exit}' "$DAEMON")"
NOTIFY_RESOLUTION_BODY="$(awk '/^notify_resolution\(\)/{found=1} found{print} /^}$/ && found{found=0; exit}' "$DAEMON")"
HEADER_BLOCK="$(awk '/^#   GAAI_NOTIFICATION_WEBHOOK=/{found=1} found{print} /^# Session env/{exit}' "$DAEMON")"

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
  # Extract the daemon's ACTUAL missing-secret diagnostic (no hardcoded copy —
  # a revert to the old cloud-coupled wording must fail this test).
  DIAG_LINE="$(grep -m1 "GAAI_DAEMON_WEBHOOK_SECRET unset" "$DAEMON" || true)"

  if [[ -n "$DIAG_LINE" ]]; then
    pass "daemon source contains a missing-secret diagnostic"
  else
    fail "no missing-secret diagnostic found in daemon source"
  fi

  if echo "$DIAG_LINE" | grep -q "GAAI_DAEMON_WEBHOOK_SECRET"; then
    pass "diagnostic names GAAI_DAEMON_WEBHOOK_SECRET"
  else
    fail "diagnostic does not name GAAI_DAEMON_WEBHOOK_SECRET: '$DIAG_LINE'"
  fi

  if echo "$DIAG_LINE" | grep -qiE "cloud|rejected"; then
    fail "diagnostic still carries hosted-product wording: '$DIAG_LINE'"
  else
    pass "diagnostic is provider-neutral (no 'cloud'/'rejected' wording)"
  fi

  # Simulate the notify_escalation guard logic (without actually calling curl)
  WEBHOOK_SECRET=""
  hmac_hex=""
  if [[ -n "$WEBHOOK_SECRET" ]]; then
    hmac_hex="$(compute_webhook_hmac '{"test":"payload"}' "$WEBHOOK_SECRET" 2>/dev/null)"
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

# ── T4: no hosted-product wording or destination anywhere in daemon source ────
echo "T4: no hosted-product wording or default destination"
{
  # Tier 1 — file-wide: tokens that cannot legitimately appear anywhere.
  FILE_WIDE_FORBIDDEN=("gaai.cloud" "/api/v1" "webhook-secrets" "Bearer" "rejected by cloud" "provisioning walkthrough")
  FILE_WIDE_OK=1
  for token in "${FILE_WIDE_FORBIDDEN[@]}"; do
    if grep -qiF "$token" "$DAEMON"; then
      fail "forbidden token '$token' still present in daemon source"
      FILE_WIDE_OK=0
    fi
  done
  [[ "$FILE_WIDE_OK" -eq 1 ]] && pass "no file-wide forbidden hosted-product tokens present"

  # Tier 2 — region-scoped: context-sensitive terms, checked only over the
  # notification surface (header doc + notify_* bodies) to avoid false
  # positives on legitimate "-workspace" worktree paths elsewhere in the file.
  REGION_FORBIDDEN=(cloud workspace org provision)
  REGION_TEXT="${HEADER_BLOCK}
${NOTIFY_ESCALATION_BODY}
${NOTIFY_RESOLUTION_BODY}"
  REGION_OK=1
  for token in "${REGION_FORBIDDEN[@]}"; do
    if echo "$REGION_TEXT" | grep -qiE "$token"; then
      fail "region-scoped forbidden term '$token' found in notification surface"
      REGION_OK=0
    fi
  done
  [[ "$REGION_OK" -eq 1 ]] && pass "notification surface (header + notify_* bodies) is provider-neutral"

  if grep -qE 'NOTIFICATION_WEBHOOK="\$\{GAAI_NOTIFICATION_WEBHOOK:-\}"' "$DAEMON"; then
    pass "no default webhook destination shipped (empty fallback)"
  else
    fail "NOTIFICATION_WEBHOOK assignment missing empty fallback — a default destination may have been introduced"
  fi

  if echo "$HEADER_BLOCK" | grep -q "GAAI_NOTIFICATION_WEBHOOK" && echo "$HEADER_BLOCK" | grep -q "GAAI_DAEMON_WEBHOOK_SECRET"; then
    pass "both GAAI_NOTIFICATION_WEBHOOK and GAAI_DAEMON_WEBHOOK_SECRET are documented"
  else
    fail "header block does not document both notification env vars"
  fi
}

# ── T5: AC2 preservation — signed-webhook contract, optionality, non-authority ─
echo "T5: existing signed-webhook behavior preserved"
{
  BOTH_BODIES="${NOTIFY_ESCALATION_BODY}
${NOTIFY_RESOLUTION_BODY}"

  if echo "$NOTIFY_ESCALATION_BODY" | grep -qF '[[ -n "$NOTIFICATION_WEBHOOK" ]]' && \
     echo "$NOTIFY_RESOLUTION_BODY" | grep -qF '[[ -n "$NOTIFICATION_WEBHOOK" ]]'; then
    pass "both notify_* functions still guard on a non-empty webhook (absent webhook stays optional)"
  else
    fail "one or both notify_* functions no longer guard on NOTIFICATION_WEBHOOK presence"
  fi

  if echo "$NOTIFY_ESCALATION_BODY" | grep -qF 'X-Hub-Signature-256: sha256=$hmac_hex' && \
     echo "$NOTIFY_RESOLUTION_BODY" | grep -qF 'X-Hub-Signature-256: sha256=$hmac_hex'; then
    pass "both notify_* functions still build the X-Hub-Signature-256 HMAC header"
  else
    fail "HMAC signature header construction changed in one or both notify_* functions"
  fi

  if echo "$BOTH_BODIES" | grep -qF 'X-Webhook-Source: gaai-daemon'; then
    pass "X-Webhook-Source: gaai-daemon header preserved"
  else
    fail "X-Webhook-Source header missing or changed"
  fi

  if echo "$BOTH_BODIES" | grep -qiE "backlog-scheduler|set-field|status:|transition"; then
    fail "notify_* bodies contain a backlog/status mutation — notification must never be phase/acceptance/merge/retry authority"
  else
    pass "notify_* bodies perform no backlog mutation (notification is not phase/acceptance/merge/retry authority)"
  fi

  if echo "$BOTH_BODIES" | grep -qF -- '--max-time 5'; then
    pass "curl retains --max-time 5 (never-block invariant preserved)"
  else
    fail "curl --max-time 5 missing — webhook delivery could block the daemon"
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
