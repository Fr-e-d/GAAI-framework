#!/usr/bin/env bash
# ── E06S29: Callibrate Core — Staging Smoke Test ─────────────────────────────
#
# Tests the full happy path against the live staging worker:
#   AC1  health check (core)
#   AC2  health check (satellite → 302)
#   AC3  expert registration
#   AC4  expert profile update
#   AC5  gcal auth-url generation
#   AC6  AI freetext extraction
#   AC7  prospect submit (Turnstile test key)
#   AC8  GET matches/:prospect_id
#   AC9  booking availability (graceful fallback: 422 gcal_not_connected)
#   AC10 CF Dashboard Analytics — manual founder check
#   AC11 CF Analytics Engine dataset — manual founder check
#   AC12 PostHog Live Events — optional
#
# Usage:
#   bash scripts/smoke-test-staging.sh
#   SUPABASE_ANON_KEY=<key> bash scripts/smoke-test-staging.sh
#
# Requires: curl, bash >= 4

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

CORE_URL="https://callibrate-core-staging.frederic-geens-consulting.workers.dev"
SAT_URL="https://callibrate-satellite-staging.frederic-geens-consulting.workers.dev"
SUPABASE_URL="https://xiilmuuafyapkhflupqx.supabase.co"

# Supabase anon key — public/publishable key, safe to include in scripts
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhpaWxtdXVhZnlhcGtoZmx1cHF4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1MzgxODksImV4cCI6MjA4NzExNDE4OX0.a96YURgRrJuAkhDGnfA8mdf4meO74mnSGFFWjqmkOpg}"

SATELLITE_ID="default"

# Cloudflare Turnstile test token — staging uses the always-pass secret key
# (TURNSTILE_SECRET_KEY = "1x0000000000000000000000000000000AA" in wrangler.toml [env.staging.vars])
# Any non-empty string passes when the test secret key is active.
TURNSTILE_TOKEN="SMOKE.TEST.TOKEN.E06S29"

# Persistent smoke test user — pre-created with confirmed email via Supabase admin SQL
# Created by E06S29 delivery. Expert may already be registered (handled idempotently below).
TEST_EMAIL="smoke-runner@callibrate.io"
TEST_PASSWORD="SmokeRunner!2026"

# ── Output helpers ────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FAILURES=0
EXPERT_ID=""
PROSPECT_ID=""
JWT=""

# Temp file for curl response bodies (avoids macOS head -n -1 issues)
TMP_FILE=$(mktemp /tmp/smoke_test_XXXXXX.json)
trap 'rm -f "$TMP_FILE"' EXIT

RESP_BODY=""
RESP_CODE=""

pass() { echo -e "${GREEN}✓ PASS${NC}  $1"; }
fail() { echo -e "${RED}✗ FAIL${NC}  $1"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "${CYAN}→${NC}       $1"; }
note() { echo -e "${YELLOW}  note:${NC} $1"; }

# curl wrappers — write body to TMP_FILE, store code in RESP_CODE, body in RESP_BODY
do_get() {
  RESP_CODE=$(curl -s -o "$TMP_FILE" -w "%{http_code}" "$1" 2>/dev/null || echo "000")
  RESP_BODY=$(cat "$TMP_FILE" 2>/dev/null || echo "")
}

do_get_headers() {
  # Returns only headers (-I flag)
  RESP_CODE=$(curl -sI -o "$TMP_FILE" -w "%{http_code}" "$1" 2>/dev/null || echo "000")
  RESP_BODY=$(cat "$TMP_FILE" 2>/dev/null || echo "")
}

do_post() {
  local url="$1"
  local data="$2"
  shift 2
  RESP_CODE=$(curl -s -o "$TMP_FILE" -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$data" \
    "$@" \
    "$url" 2>/dev/null || echo "000")
  RESP_BODY=$(cat "$TMP_FILE" 2>/dev/null || echo "")
}

do_patch() {
  local url="$1"
  local data="$2"
  shift 2
  RESP_CODE=$(curl -s -o "$TMP_FILE" -w "%{http_code}" -X PATCH \
    -H "Content-Type: application/json" \
    -d "$data" \
    "$@" \
    "$url" 2>/dev/null || echo "000")
  RESP_BODY=$(cat "$TMP_FILE" 2>/dev/null || echo "")
}

# ── Header ────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Callibrate Core — Staging Smoke Test (E06S29)"
echo "  $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "══════════════════════════════════════════════════════════"
echo ""

# ── AC1: Core health ──────────────────────────────────────────────────────────

info "AC1: GET /api/health"
do_get "$CORE_URL/api/health"

if [[ "$RESP_CODE" == "200" ]] && echo "$RESP_BODY" | grep -q '"status":"ok"'; then
  supabase_status=$(echo "$RESP_BODY" | grep -o '"supabase":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
  pass "AC1: Core health — HTTP 200 | supabase=$supabase_status"
  if [[ "$supabase_status" != "connected" ]]; then
    note "Supabase shows '$supabase_status' — check SUPABASE_URL + SUPABASE_SERVICE_KEY secrets"
  fi
else
  fail "AC1: Core health — HTTP $RESP_CODE | $RESP_BODY"
fi

# ── AC2: Satellite health ─────────────────────────────────────────────────────

info "AC2: GET /health (satellite, no redirect)"
do_get "$SAT_URL/health"

if [[ "$RESP_CODE" == "302" ]]; then
  # Get location header
  location=$(curl -sI "$SAT_URL/health" 2>/dev/null | grep -i "^location:" | tr -d '\r\n' | sed 's/[Ll]ocation: //')
  pass "AC2: Satellite health — HTTP 302 → ${location:-callibrate.io} (no active satellite, expected)"
elif [[ "$RESP_CODE" == "200" ]]; then
  pass "AC2: Satellite health — HTTP 200"
else
  fail "AC2: Satellite health — HTTP $RESP_CODE | $RESP_BODY"
fi

# ── Supabase sign-in ──────────────────────────────────────────────────────────

info "Auth: signing in as smoke runner ($TEST_EMAIL)"
do_post "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" \
  -H "apikey: $SUPABASE_ANON_KEY"

JWT=$(echo "$RESP_BODY" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)
USER_ID=$(echo "$RESP_BODY" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

if [[ -z "$JWT" ]]; then
  echo ""
  echo -e "${RED}⚠ Auth BLOCKED — sign-in failed${NC}"
  echo "  HTTP $RESP_CODE: $RESP_BODY"
  echo ""
  echo "  The smoke runner user ($TEST_EMAIL) may not exist."
  echo "  Run this SQL in Supabase to create it:"
  echo "  INSERT INTO auth.users (id,instance_id,email,encrypted_password,email_confirmed_at,"
  echo "    raw_app_meta_data,raw_user_meta_data,created_at,updated_at,aud,role)"
  echo "  VALUES (gen_random_uuid(),'00000000-0000-0000-0000-000000000000'::uuid,"
  echo "    'smoke-runner@callibrate.io',crypt('SmokeRunner!2026',gen_salt('bf',10)),"
  echo "    now(),'{\"provider\":\"email\",\"providers\":[\"email\"]}'::jsonb,'{}', now(),now(),"
  echo "    'authenticated','authenticated');"
  echo ""
  echo "  Skipping AC3–AC9 (require JWT)."
  FAILURES=$((FAILURES + 7))
else
  echo -e "  ${GREEN}→ JWT obtained${NC} (${#JWT} chars, user_id=$USER_ID)"
fi

# ── AC3: Expert register ──────────────────────────────────────────────────────

if [[ -n "$JWT" ]]; then
  info "AC3: POST /api/experts/register"
  do_post "$CORE_URL/api/experts/register" \
    '{"display_name":"Smoke Test Expert E06S29","headline":"Expert in AI automation","bio":"Test bio for smoke testing","rate_min":150,"rate_max":500}' \
    -H "Authorization: Bearer $JWT"

  if [[ "$RESP_CODE" == "201" ]]; then
    EXPERT_ID=$(echo "$RESP_BODY" | grep -o '"expert_id":"[^"]*"' | cut -d'"' -f4 || true)
    pass "AC3: Expert registered — HTTP 201 | expert_id=$EXPERT_ID"
  elif [[ "$RESP_CODE" == "409" ]]; then
    # Idempotent: smoke runner already registered as expert — use user_id as expert_id
    EXPERT_ID="$USER_ID"
    pass "AC3: Expert already registered (idempotent) — HTTP 409, using expert_id=$EXPERT_ID"
  else
    fail "AC3: Expert register — HTTP $RESP_CODE | $RESP_BODY"
  fi
fi

# ── AC4: Expert profile update ────────────────────────────────────────────────

if [[ -n "$JWT" && -n "$EXPERT_ID" ]]; then
  info "AC4: PATCH /api/experts/$EXPERT_ID/profile"
  do_patch "$CORE_URL/api/experts/$EXPERT_ID/profile" \
    '{"profile":{"skills":["n8n","python","llm","automation","api-integration"],"industries":["saas","ecommerce"],"project_types":["automation","integration","consulting"],"languages":["en","fr"]},"preferences":{"min_budget":1000,"max_budget":50000}}' \
    -H "Authorization: Bearer $JWT"

  if [[ "$RESP_CODE" == "200" ]]; then
    pass "AC4: Profile updated — HTTP 200"
  else
    fail "AC4: Profile update — HTTP $RESP_CODE | $RESP_BODY"
  fi
fi

# ── AC5: GCal auth-url ────────────────────────────────────────────────────────

if [[ -n "$JWT" && -n "$EXPERT_ID" ]]; then
  info "AC5: GET /api/experts/$EXPERT_ID/gcal/auth-url"
  RESP_CODE=$(curl -s -o "$TMP_FILE" -w "%{http_code}" \
    -H "Authorization: Bearer $JWT" \
    "$CORE_URL/api/experts/$EXPERT_ID/gcal/auth-url" 2>/dev/null || echo "000")
  RESP_BODY=$(cat "$TMP_FILE" 2>/dev/null || echo "")

  if [[ "$RESP_CODE" == "200" ]] && echo "$RESP_BODY" | grep -q "accounts.google.com"; then
    pass "AC5: GCal auth-url — HTTP 200 | accounts.google.com URL present ✓"
  elif [[ "$RESP_CODE" == "200" ]] && echo "$RESP_BODY" | grep -q '"error"'; then
    fail "AC5: GCal auth-url — HTTP 200 but error in body | $RESP_BODY"
    note "Likely cause: GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET secret not set on staging"
  elif [[ "$RESP_CODE" == "200" ]]; then
    pass "AC5: GCal auth-url — HTTP 200 (non-error response)"
  else
    fail "AC5: GCal auth-url — HTTP $RESP_CODE | $RESP_BODY"
  fi
fi

# ── AC6: AI freetext extraction ───────────────────────────────────────────────

info "AC6: POST /api/extract"
do_post "$CORE_URL/api/extract" \
  '{"text":"Je cherche un expert n8n pour automatiser mon CRM, budget 5k euros"}'

if [[ "$RESP_CODE" == "200" ]]; then
  if echo "$RESP_BODY" | grep -qE '"skills_needed"|"budget_range"|"timeline"'; then
    pass "AC6: AI extraction — HTTP 200 | structured ProspectRequirements returned"
    note "response: $RESP_BODY"
  else
    pass "AC6: AI extraction — HTTP 200 | $RESP_BODY"
  fi
elif [[ "$RESP_CODE" == "503" ]]; then
  fail "AC6: AI extraction — HTTP 503 (OpenAI key missing or quota exceeded)"
  note "$RESP_BODY"
else
  fail "AC6: AI extraction — HTTP $RESP_CODE | $RESP_BODY"
fi

# ── AC7: Prospect submit ──────────────────────────────────────────────────────

info "AC7: POST /api/prospects/submit"
# Required quiz fields for 'default' satellite: challenge, budget_range, timeline, languages
SUBMIT_PAYLOAD="{
  \"satellite_id\": \"$SATELLITE_ID\",
  \"cf-turnstile-response\": \"$TURNSTILE_TOKEN\",
  \"quiz_answers\": {
    \"challenge\": \"Automate CRM workflows using n8n for lead qualification\",
    \"budget_range\": {\"min\": 3000, \"max\": 8000},
    \"timeline\": \"3_months\",
    \"languages\": [\"en\", \"fr\"],
    \"skills_needed\": [\"n8n\", \"python\", \"automation\"],
    \"industry\": \"saas\",
    \"company_size\": \"2_10\"
  }
}"

do_post "$CORE_URL/api/prospects/submit" "$SUBMIT_PAYLOAD"

if [[ "$RESP_CODE" == "200" || "$RESP_CODE" == "201" ]]; then
  PROSPECT_ID=$(echo "$RESP_BODY" | grep -o '"prospect_id":"[^"]*"' | cut -d'"' -f4 || true)
  pass "AC7: Prospect submitted — HTTP $RESP_CODE | prospect_id=$PROSPECT_ID"
elif [[ "$RESP_CODE" == "422" ]]; then
  fail "AC7: Prospect submit — HTTP 422 | $RESP_BODY"
  note "422 = Turnstile failed or quiz validation error"
  note "Check: TURNSTILE_SECRET_KEY='1x0000000000000000000000000000000AA' in staging vars"
else
  fail "AC7: Prospect submit — HTTP $RESP_CODE | $RESP_BODY"
fi

# ── AC8: GET matches ──────────────────────────────────────────────────────────

if [[ -n "$PROSPECT_ID" ]]; then
  info "AC8: GET /api/matches/$PROSPECT_ID"
  do_get "$CORE_URL/api/matches/$PROSPECT_ID"

  if [[ "$RESP_CODE" == "200" ]]; then
    pass "AC8: Matches returned — HTTP 200 | $RESP_BODY"
  else
    fail "AC8: Matches — HTTP $RESP_CODE | $RESP_BODY"
  fi
else
  note "AC8: Skipped (no prospect_id from AC7)"
  FAILURES=$((FAILURES + 1))
fi

# ── AC9: Booking availability (graceful GCal fallback) ───────────────────────

if [[ -n "$EXPERT_ID" ]]; then
  info "AC9: GET /api/experts/$EXPERT_ID/availability"
  do_get "$CORE_URL/api/experts/$EXPERT_ID/availability"

  if [[ "$RESP_CODE" == "422" ]]; then
    error_key=$(echo "$RESP_BODY" | grep -o '"error":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    pass "AC9: Availability — HTTP 422 | error=$error_key (graceful: GCal not connected, expected)"
  elif [[ "$RESP_CODE" == "200" ]]; then
    pass "AC9: Availability — HTTP 200 | $RESP_BODY"
  elif echo "$RESP_CODE" | grep -q "^5"; then
    fail "AC9: Availability — HTTP $RESP_CODE (5xx infra error!) | $RESP_BODY"
  else
    fail "AC9: Availability — unexpected HTTP $RESP_CODE | $RESP_BODY"
  fi
else
  note "AC9: Skipped (no expert_id from AC3)"
  FAILURES=$((FAILURES + 1))
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════"
if [[ "$FAILURES" == "0" ]]; then
  echo -e "${GREEN}✅  SMOKE TEST PASS — All AC1–AC9 validated${NC}"
else
  echo -e "${RED}❌  SMOKE TEST FAIL — $FAILURES failure(s)${NC}"
fi
echo "══════════════════════════════════════════════════════════"
echo ""
echo "Manual checks (founder):"
echo "  AC10: CF Dashboard → callibrate-core-staging → Analytics → ≥1 request visible"
echo "  AC11: CF Dashboard → Analytics Engine → matching-metrics → ≥1 data point (AC7/AC8)"
echo "  AC12: PostHog EU → Live Events → expert.registered + prospect.form_submitted (optional)"
echo ""

exit "$FAILURES"
