#!/usr/bin/env bash
# validate-cohort.test.sh — Test harness for validate-cohort.sh
#
# Tests all DEC-88 §validation-gates acceptance criteria (AC1-AC6)
#
# Usage: bash .gaai/core/scripts/tests/validate-cohort.test.sh
# Exit 0 = all pass. Exit 1 = at least one failure.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
VALIDATE_SCRIPT="$SCRIPT_DIR/../validate-cohort.sh"

# Use resolved TMPDIR (avoids macOS /tmp→/private/tmp symlink issue)
_TMPDIR="${TMPDIR:-/tmp}"
_TMPDIR="${_TMPDIR%/}"

# ── Temp directory for all fixtures ───────────────────────────────────────
TEST_DIR="$(mktemp -d "${_TMPDIR}/validate-cohort-test.XXXXXX")"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Directories within test tmp
mkdir -p "$TEST_DIR/logs"
mkdir -p "$TEST_DIR/backlog"
mkdir -p "$TEST_DIR/verdicts"

ROUTING_LOG="$TEST_DIR/logs/runtime-routing.jsonl"
BACKLOG_FILE="$TEST_DIR/backlog/active.backlog.yaml"
VERDICTS_DIR="$TEST_DIR/verdicts"

# ── Helper: write base backlog YAML ───────────────────────────────────────
write_base_backlog() {
  local last_flip_at="${1:-null}"
  cat > "$BACKLOG_FILE" << YAML
cutover_state:
  default_pipeline: legacy
  last_flip_at: ${last_flip_at}
  last_flip_by: null
  last_flip_forced: false
  last_flip_pre_in_progress_count: 0
items:
YAML
}

# ── Helper: append a story to backlog ─────────────────────────────────────
append_story() {
  local id="$1"
  local status="$2"
  local pipeline="${3:-3phase}"
  cat >> "$BACKLOG_FILE" << YAML
- id: ${id}
  status: ${status}
  phase_status: done
  delivery_pipeline: ${pipeline}
YAML
}

# ── Helper: write a routing.jsonl record ──────────────────────────────────
# Fixed past timestamps are used for deterministic Gate 3 tests (not relative to now)
append_routing_record() {
  local story_id="$1"
  local phase="$2"
  local pipeline="$3"     # "3phase" | "legacy" (empty = no pipeline field) | "cutover"
  local fallback_reason="${4:-null}"
  local timestamp="${5:-2026-04-15T10:00:00.000Z}"

  local pipeline_field=""
  if [[ "$pipeline" == "3phase" ]]; then
    pipeline_field='"pipeline":"3phase",'
  elif [[ "$pipeline" == "cutover" ]]; then
    pipeline_field='"pipeline":"cutover",'
  fi
  # legacy = no pipeline field (select(.pipeline | not) in jq)

  local fb_value="null"
  if [[ "$fallback_reason" != "null" ]]; then
    fb_value="\"${fallback_reason}\""
  fi

  echo "{\"trace_id\":\"trace-${RANDOM}\",\"story_id\":\"${story_id}\",\"phase\":\"${phase}\",${pipeline_field}\"provider\":\"daemon-bash\",\"model\":\"n/a\",\"duration_ms\":1000,\"fallback_reason\":${fb_value},\"impl_model_tag\":\"primary\",\"timestamp\":\"${timestamp}\"}" >> "$ROUTING_LOG"
}

# ── Helper: run validate-cohort and capture stdout ────────────────────────
run_validate() {
  local args="$*"
  # Capture stdout (the verdict string); stderr goes to /dev/null in tests
  ROUTING_LOG_PATH="$ROUTING_LOG" \
  BACKLOG_FILE="$BACKLOG_FILE" \
  VERDICTS_DIR="$VERDICTS_DIR" \
  bash "$VALIDATE_SCRIPT" $args 2>/dev/null
}

# ── Helper: get last verdict file ─────────────────────────────────────────
last_verdict_file() {
  ls -t "$VERDICTS_DIR"/*.cohort-verdict.md 2>/dev/null | head -1
}

echo "validate-cohort — test suite"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# T1: Cutover record exclusion (AC1 — phase:cutover excluded from cohort)
# ═══════════════════════════════════════════════════════════════════════════
echo "T1: Cutover record exclusion"

> "$ROUTING_LOG"
write_base_backlog "null"

# Add 5 3phase done stories with cutover records interspersed
for i in 1 2 3 4 5; do
  append_story "T1-STORY-${i}" "done" "3phase"
  # Add a commit record for each story
  append_routing_record "T1-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  # Add an impl record for each story
  append_routing_record "T1-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
# Add cutover records that should be excluded
append_routing_record "T1-STORY-1" "cutover" "cutover" "null" "2026-04-15T12:00:00.000Z"
append_routing_record "T1-STORY-2" "cutover" "3phase" "null" "2026-04-15T13:00:00.000Z"

result="$(run_validate --cohort-size 10)"

# Cutover records should not inflate the cohort or cause issues
# We expect 5 commit records found → Gate 1 PASS (5 done) → REMAIN_ON_3PHASE
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T1: cutover records excluded — verdict REMAIN_ON_3PHASE"
else
  fail "T1: expected REMAIN_ON_3PHASE, got '${result}'"
fi

# Verify cutover story IDs do NOT appear in the Cohort Details section
# Note: the word "cutover" may legitimately appear in Gate 3 notes text
# (e.g. "last_flip_at is null — no cutover yet") — we only check the cohort list
vf="$(last_verdict_file)"
if [[ -n "$vf" ]] && ! grep -q "  - .*cutover\|  - .*CUTOVER" "$vf" 2>/dev/null; then
  pass "T1b: verdict cohort list has no cutover story IDs"
else
  fail "T1b: verdict cohort list unexpectedly contains cutover story IDs"
fi

# ═══════════════════════════════════════════════════════════════════════════
# T2: Gate 1 — Stories Success Count (AC2)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "T2: Gate 1 — Stories Success Count"

# T2a: 5 done stories → Gate 1 PASS
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3 4 5; do
  append_story "T2A-STORY-${i}" "done" "3phase"
  append_routing_record "T2A-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T2A-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
result="$(run_validate --cohort-size 5)"
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T2a: 5 done stories → Gate 1 PASS → REMAIN_ON_3PHASE"
else
  fail "T2a: expected REMAIN_ON_3PHASE, got '${result}'"
fi
vf="$(last_verdict_file)"
if [[ -n "$vf" ]] && grep -q "Gate 1.*PASS\|Status: PASS" "$vf" 2>/dev/null; then
  pass "T2a-gate1: verdict file reports Gate 1 PASS"
else
  fail "T2a-gate1: verdict file does not report Gate 1 PASS"
fi

# T2b: 5 stories with only 3/5 done → Gate 1 FAIL
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3; do
  append_story "T2B-DONE-${i}" "done" "3phase"
  append_routing_record "T2B-DONE-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T2B-DONE-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
for i in 4 5; do
  append_story "T2B-INPROG-${i}" "in_progress" "3phase"
  append_routing_record "T2B-INPROG-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T2B-INPROG-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
result="$(run_validate --cohort-size 5)"
if [[ "$result" == "ROLLBACK_TO_LEGACY" ]]; then
  pass "T2b: 3/5 done → Gate 1 FAIL → ROLLBACK_TO_LEGACY"
else
  fail "T2b: expected ROLLBACK_TO_LEGACY, got '${result}'"
fi

# T2c: only 4 total cohort stories → Gate 1 INSUFFICIENT_DATA
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3 4; do
  append_story "T2C-STORY-${i}" "done" "3phase"
  append_routing_record "T2C-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T2C-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
result="$(run_validate --cohort-size 4)"
if [[ "$result" == "INCONCLUSIVE_INSUFFICIENT_DATA" ]]; then
  pass "T2c: 4 total stories → Gate 1 INSUFFICIENT_DATA → INCONCLUSIVE"
else
  fail "T2c: expected INCONCLUSIVE_INSUFFICIENT_DATA, got '${result}'"
fi

# ═══════════════════════════════════════════════════════════════════════════
# T3: Gate 2 — §6a Violation Check (AC3)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "T3: Gate 2 — §6a Violation Check"

# T3a: commit + impl → Gate 2 OK
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3 4 5; do
  append_story "T3A-STORY-${i}" "done" "3phase"
  append_routing_record "T3A-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T3A-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
result="$(run_validate --cohort-size 5)"
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T3a: commit + 1 impl → Gate 2 OK → REMAIN_ON_3PHASE"
else
  fail "T3a: expected REMAIN_ON_3PHASE, got '${result}'"
fi

# T3b: commit but NO impl record → Gate 2 VIOLATION → FAIL
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3 4 5; do
  append_story "T3B-STORY-${i}" "done" "3phase"
  append_routing_record "T3B-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  # No impl record for T3B-STORY-1
  if [[ "$i" -ne 1 ]]; then
    append_routing_record "T3B-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
  fi
done
result="$(run_validate --cohort-size 5)"
if [[ "$result" == "ROLLBACK_TO_LEGACY" ]]; then
  pass "T3b: commit + no impl → Gate 2 VIOLATION → ROLLBACK_TO_LEGACY"
else
  fail "T3b: expected ROLLBACK_TO_LEGACY, got '${result}'"
fi
vf="$(last_verdict_file)"
if [[ -n "$vf" ]] && grep -q "VIOLATION" "$vf" 2>/dev/null; then
  pass "T3b-violation: verdict file contains VIOLATION marker"
else
  fail "T3b-violation: verdict file missing VIOLATION marker"
fi

# T3c: commit + 2 impl records → Gate 2 FLAG (not FAIL — verdict still REMAIN if other gates pass)
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3 4 5; do
  append_story "T3C-STORY-${i}" "done" "3phase"
  append_routing_record "T3C-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  # Add 2 impl records for T3C-STORY-1
  append_routing_record "T3C-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
  if [[ "$i" -eq 1 ]]; then
    append_routing_record "T3C-STORY-${i}" "impl" "3phase" "null" "2026-04-15T08:01:00.000Z"
  fi
done
result="$(run_validate --cohort-size 5)"
# FLAG does not cause FAIL — verdict should be REMAIN_ON_3PHASE
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T3c: commit + 2 impl → FLAG (not FAIL) → REMAIN_ON_3PHASE"
else
  fail "T3c: expected REMAIN_ON_3PHASE (FLAG is not FAIL), got '${result}'"
fi
vf="$(last_verdict_file)"
if [[ -n "$vf" ]] && grep -q "FLAG" "$vf" 2>/dev/null; then
  pass "T3c-flag: verdict file contains FLAG marker"
else
  fail "T3c-flag: verdict file missing FLAG marker"
fi

# ═══════════════════════════════════════════════════════════════════════════
# T4: Gate 3 — rapid_refill_breaker Rate Parity (AC4)
# Uses FIXED timestamps (not relative to now) for determinism
# last_flip_at: 2026-04-01T12:00:00Z
# Legacy window: 2026-03-02T12:00:00Z → 2026-04-01T12:00:00Z (30d)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "T4: Gate 3 — rapid_refill_breaker Rate Parity"

FLIP_AT="2026-04-01T12:00:00Z"
# Legacy impl timestamps — within 30d window before flip_at
LEGACY_TS_1="2026-03-15T10:00:00.000Z"
LEGACY_TS_2="2026-03-16T10:00:00.000Z"
LEGACY_TS_3="2026-03-17T10:00:00.000Z"
LEGACY_TS_4="2026-03-18T10:00:00.000Z"
LEGACY_TS_5="2026-03-19T10:00:00.000Z"
LEGACY_TS_6="2026-03-20T10:00:00.000Z"
LEGACY_TS_7="2026-03-21T10:00:00.000Z"
LEGACY_TS_8="2026-03-22T10:00:00.000Z"
LEGACY_TS_9="2026-03-23T10:00:00.000Z"
LEGACY_TS_10="2026-03-24T10:00:00.000Z"
LEGACY_TS_11="2026-03-25T10:00:00.000Z"
LEGACY_TS_12="2026-03-26T10:00:00.000Z"
LEGACY_TS_13="2026-03-27T10:00:00.000Z"
LEGACY_TS_14="2026-03-28T10:00:00.000Z"
LEGACY_TS_15="2026-03-29T10:00:00.000Z"
LEGACY_TS_16="2026-03-30T10:00:00.000Z"
LEGACY_TS_17="2026-03-31T10:00:00.000Z"
LEGACY_TS_18="2026-03-31T14:00:00.000Z"
LEGACY_TS_19="2026-03-31T16:00:00.000Z"
LEGACY_TS_20="2026-03-31T18:00:00.000Z"

# 3phase timestamps — after flip_at
PHASE3_TS_1="2026-04-05T10:00:00.000Z"
PHASE3_TS_2="2026-04-06T10:00:00.000Z"
PHASE3_TS_3="2026-04-07T10:00:00.000Z"
PHASE3_TS_4="2026-04-08T10:00:00.000Z"
PHASE3_TS_5="2026-04-09T10:00:00.000Z"
PHASE3_TS_6="2026-04-10T10:00:00.000Z"
PHASE3_TS_7="2026-04-11T10:00:00.000Z"
PHASE3_TS_8="2026-04-12T10:00:00.000Z"
PHASE3_TS_9="2026-04-13T10:00:00.000Z"
PHASE3_TS_10="2026-04-14T10:00:00.000Z"

# T4a: Legacy 5% (1/20 rapid_refill_breaker), 3phase 8% (8/10 * 10%) = within ±10pp → PASS
> "$ROUTING_LOG"
write_base_backlog "$FLIP_AT"
# 5 done stories with commit+impl records after flip
for i in 1 2 3 4 5; do
  append_story "T4A-STORY-${i}" "done" "3phase"
  append_routing_record "T4A-STORY-${i}" "commit" "3phase" "null" "$(eval echo \$PHASE3_TS_${i})"
  # 3phase impl: 0% rapid_refill_breaker for this test
  # Actually use 1/10 = 10% to test borderline
done
# 5 more done stories for Gate 1 (need ≥5 done)
# Actually gate1 uses cohort size - we need 5 done stories in the cohort
# The cohort here will be all 3phase commits → use cohort-size 5

# Write 20 legacy impl records in window, 1 with rapid_refill_breaker (5%)
for i in $(seq 1 20); do
  ts_var="LEGACY_TS_${i}"
  fb="null"
  if [[ "$i" -eq 1 ]]; then fb="rapid_refill_breaker"; fi
  echo "{\"trace_id\":\"leg-${i}\",\"story_id\":\"LEG-${i}\",\"phase\":\"impl\",\"provider\":\"primary\",\"model\":\"claude-sonnet-4-6\",\"duration_ms\":0,\"fallback_reason\":$([ "$fb" == "null" ] && echo "null" || echo "\"$fb\""),\"impl_model_tag\":\"secondary\",\"timestamp\":\"${!ts_var}\"}" >> "$ROUTING_LOG"
done

# Write 5 3phase commit + impl records (2 with breaker = 40% — but we need to test delta with 5%)
# Actually let's do 1/20 legacy = 5%, and for 3phase let's test 10% (1/10) → delta=5pp ≤10 → PASS
for i in 1 2 3 4 5; do
  append_routing_record "T4A-STORY-${i}" "commit" "3phase" "null" "$(eval echo \$PHASE3_TS_${i})" || true
  fb="null"
  if [[ "$i" -eq 1 ]]; then fb="rapid_refill_breaker"; fi  # 1/5 = 20% — wait let's use 10 records
  append_routing_record "T4A-STORY-${i}" "impl" "3phase" "$fb" "$(eval echo \$PHASE3_TS_${i})" || true
done
# Add 5 more 3phase impl for non-cohort stories to make 10 total, 1 with breaker → 10%
for i in 6 7 8 9 10; do
  append_routing_record "T4A-EXTRA-${i}" "commit" "3phase" "null" "$(eval echo \$PHASE3_TS_${i})"
  append_routing_record "T4A-EXTRA-${i}" "impl" "3phase" "null" "$(eval echo \$PHASE3_TS_${i})"
done

# Cohort = the 5 T4A-STORY-* stories (commit records in log)
# Legacy rate = 1/20 = 5%, 3phase rate for cohort = 1/5 = 20% → delta=15pp > 10 → FAIL
# Let's reconfigure: use 0 breakers in 3phase → 0% vs 5% = 5pp delta → PASS
> "$ROUTING_LOG"
write_base_backlog "$FLIP_AT"
for i in 1 2 3 4 5; do
  append_story "T4A-STORY-${i}" "done" "3phase"
done
# Legacy: 20 records, 1 with breaker = 5% rate
for i in $(seq 1 20); do
  ts_var="LEGACY_TS_${i}"
  fb_json="null"
  if [[ "$i" -eq 1 ]]; then fb_json="\"rapid_refill_breaker\""; fi
  echo "{\"trace_id\":\"leg-${i}\",\"story_id\":\"LEG-${i}\",\"phase\":\"impl\",\"provider\":\"primary\",\"model\":\"claude-sonnet-4-6\",\"duration_ms\":0,\"fallback_reason\":${fb_json},\"impl_model_tag\":\"secondary\",\"timestamp\":\"${!ts_var}\"}" >> "$ROUTING_LOG"
done
# 3phase: 5 commit + 5 impl, 0 breakers = 0% rate → delta = 5pp ≤ 10pp → PASS
for i in 1 2 3 4 5; do
  append_routing_record "T4A-STORY-${i}" "commit" "3phase" "null" "$(eval echo \$PHASE3_TS_${i})"
  append_routing_record "T4A-STORY-${i}" "impl" "3phase" "null" "$(eval echo \$PHASE3_TS_${i})"
done

result="$(run_validate --cohort-size 5)"
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T4a: legacy 5% vs 3phase 0% → delta=5pp ≤10pp → Gate 3 PASS → REMAIN_ON_3PHASE"
else
  fail "T4a: expected REMAIN_ON_3PHASE, got '${result}'"
fi

# T4b: Legacy 5% (1/20), 3phase 80% (4/5) → delta=75pp > 10pp → Gate 3 FAIL
> "$ROUTING_LOG"
write_base_backlog "$FLIP_AT"
for i in 1 2 3 4 5; do
  append_story "T4B-STORY-${i}" "done" "3phase"
done
# Legacy: same 1/20 = 5%
for i in $(seq 1 20); do
  ts_var="LEGACY_TS_${i}"
  fb_json="null"
  if [[ "$i" -eq 1 ]]; then fb_json="\"rapid_refill_breaker\""; fi
  echo "{\"trace_id\":\"leg-${i}\",\"story_id\":\"LEG-${i}\",\"phase\":\"impl\",\"provider\":\"primary\",\"model\":\"claude-sonnet-4-6\",\"duration_ms\":0,\"fallback_reason\":${fb_json},\"impl_model_tag\":\"secondary\",\"timestamp\":\"${!ts_var}\"}" >> "$ROUTING_LOG"
done
# 3phase: 5 commit + 5 impl, 4 breakers = 80% → delta = 75pp > 10pp → FAIL
for i in 1 2 3 4 5; do
  append_routing_record "T4B-STORY-${i}" "commit" "3phase" "null" "$(eval echo \$PHASE3_TS_${i})"
  fb="null"
  if [[ "$i" -le 4 ]]; then fb="rapid_refill_breaker"; fi
  append_routing_record "T4B-STORY-${i}" "impl" "3phase" "$fb" "$(eval echo \$PHASE3_TS_${i})"
done

result="$(run_validate --cohort-size 5)"
if [[ "$result" == "ROLLBACK_TO_LEGACY" ]]; then
  pass "T4b: legacy 5% vs 3phase 80% → delta=75pp >10pp → Gate 3 FAIL → ROLLBACK_TO_LEGACY"
else
  fail "T4b: expected ROLLBACK_TO_LEGACY, got '${result}'"
fi

# T4c: Legacy n<5 → Gate 3 SKIP (even if other gates pass → verdict REMAIN_ON_3PHASE)
> "$ROUTING_LOG"
write_base_backlog "$FLIP_AT"
for i in 1 2 3 4 5; do
  append_story "T4C-STORY-${i}" "done" "3phase"
done
# Only 3 legacy impl records (< 5 required for baseline)
for i in 1 2 3; do
  ts_var="LEGACY_TS_${i}"
  echo "{\"trace_id\":\"leg-${i}\",\"story_id\":\"LEG-${i}\",\"phase\":\"impl\",\"provider\":\"primary\",\"model\":\"claude-sonnet-4-6\",\"duration_ms\":0,\"fallback_reason\":null,\"impl_model_tag\":\"secondary\",\"timestamp\":\"${!ts_var}\"}" >> "$ROUTING_LOG"
done
# 3phase commit + impl records
for i in 1 2 3 4 5; do
  append_routing_record "T4C-STORY-${i}" "commit" "3phase" "null" "$(eval echo \$PHASE3_TS_${i})"
  append_routing_record "T4C-STORY-${i}" "impl" "3phase" "null" "$(eval echo \$PHASE3_TS_${i})"
done

result="$(run_validate --cohort-size 5)"
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T4c: legacy n=3 (<5) → Gate 3 SKIP → REMAIN_ON_3PHASE"
else
  fail "T4c: expected REMAIN_ON_3PHASE (gate3 SKIP), got '${result}'"
fi
vf="$(last_verdict_file)"
if [[ -n "$vf" ]] && grep -q "SKIP" "$vf" 2>/dev/null; then
  pass "T4c-skip: verdict file records Gate 3 SKIP"
else
  fail "T4c-skip: verdict file missing SKIP marker"
fi

# ═══════════════════════════════════════════════════════════════════════════
# T5: Overall recommendation logic (AC2+AC3+AC4 combined)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "T5: Overall recommendation logic"

# T5a: All gates PASS → REMAIN_ON_3PHASE (covered by T4a + T3a + T2a above)
# Reuse a clean config with all passing
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3 4 5; do
  append_story "T5A-STORY-${i}" "done" "3phase"
  append_routing_record "T5A-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T5A-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
result="$(run_validate --cohort-size 5)"
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T5a: Gate1=PASS Gate2=PASS Gate3=SKIP → REMAIN_ON_3PHASE"
else
  fail "T5a: expected REMAIN_ON_3PHASE, got '${result}'"
fi

# T5b: Gate 1 FAIL → ROLLBACK_TO_LEGACY (even with others PASS/SKIP)
> "$ROUTING_LOG"
write_base_backlog "null"
# Only 3/5 done → Gate 1 FAIL
for i in 1 2 3; do
  append_story "T5B-DONE-${i}" "done" "3phase"
  append_routing_record "T5B-DONE-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T5B-DONE-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
for i in 4 5; do
  append_story "T5B-INPROG-${i}" "in_progress" "3phase"
  append_routing_record "T5B-INPROG-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T5B-INPROG-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
result="$(run_validate --cohort-size 5)"
if [[ "$result" == "ROLLBACK_TO_LEGACY" ]]; then
  pass "T5b: Gate1=FAIL → ROLLBACK_TO_LEGACY"
else
  fail "T5b: expected ROLLBACK_TO_LEGACY, got '${result}'"
fi

# T5c: Gate 1 PASS, Gate 2 PASS, Gate 3 SKIP → REMAIN_ON_3PHASE
# (SKIP does not block positive verdict)
> "$ROUTING_LOG"
write_base_backlog "null"  # last_flip_at=null → Gate 3 always SKIP
for i in 1 2 3 4 5; do
  append_story "T5C-STORY-${i}" "done" "3phase"
  append_routing_record "T5C-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T5C-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
result="$(run_validate --cohort-size 5)"
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T5c: Gate1=PASS Gate2=PASS Gate3=SKIP → REMAIN_ON_3PHASE (SKIP not blocking)"
else
  fail "T5c: expected REMAIN_ON_3PHASE (SKIP non-blocking), got '${result}'"
fi

# T5d: Gate 1 INSUFFICIENT_DATA (total<5) and no FAIL → INCONCLUSIVE
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3; do
  append_story "T5D-STORY-${i}" "done" "3phase"
  append_routing_record "T5D-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T5D-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
result="$(run_validate --cohort-size 3)"
if [[ "$result" == "INCONCLUSIVE_INSUFFICIENT_DATA" ]]; then
  pass "T5d: Gate1=INSUFFICIENT_DATA → INCONCLUSIVE_INSUFFICIENT_DATA"
else
  fail "T5d: expected INCONCLUSIVE_INSUFFICIENT_DATA, got '${result}'"
fi

# ═══════════════════════════════════════════════════════════════════════════
# T6: Error handling (AC5)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "T6: Error handling"

# T6a: Missing routing.jsonl → exit 0, INCONCLUSIVE_INSUFFICIENT_DATA
rm -f "$ROUTING_LOG"
write_base_backlog "null"
result="$(run_validate --cohort-size 5)"
exit_code=$?
> "$ROUTING_LOG"  # Recreate for subsequent tests
if [[ "$result" == "INCONCLUSIVE_INSUFFICIENT_DATA" ]] && [[ "$exit_code" -eq 0 ]]; then
  pass "T6a: missing routing.jsonl → exit 0 + INCONCLUSIVE_INSUFFICIENT_DATA"
else
  fail "T6a: expected INCONCLUSIVE(exit 0), got '${result}'(exit ${exit_code})"
fi

# T6b: Malformed JSON lines in routing.jsonl — no crash, valid records still processed
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3 4 5; do
  append_story "T6B-STORY-${i}" "done" "3phase"
  append_routing_record "T6B-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T6B-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
# Inject malformed lines
echo "NOT_VALID_JSON{{{" >> "$ROUTING_LOG"
echo "GARBAGE_LINE" >> "$ROUTING_LOG"
echo '{"partial": true' >> "$ROUTING_LOG"
result="$(run_validate --cohort-size 5)"
exit_code=$?
if [[ "$exit_code" -eq 0 ]]; then
  pass "T6b: malformed JSON lines — no crash (exit 0)"
else
  fail "T6b: malformed JSON caused non-zero exit: ${exit_code}"
fi
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T6b-result: malformed lines skipped, valid records processed correctly"
else
  fail "T6b-result: expected REMAIN_ON_3PHASE after malformed line skip, got '${result}'"
fi

# T6c: last_flip_at is null → Gate 3 SKIP (not FAIL, not INSUFFICIENT_DATA)
> "$ROUTING_LOG"
write_base_backlog "null"  # explicit null
for i in 1 2 3 4 5; do
  append_story "T6C-STORY-${i}" "done" "3phase"
  append_routing_record "T6C-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T6C-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
result="$(run_validate --cohort-size 5)"
vf="$(last_verdict_file)"
# Gate 3 SKIP should not block REMAIN_ON_3PHASE
if [[ "$result" == "REMAIN_ON_3PHASE" ]]; then
  pass "T6c: last_flip_at=null → Gate 3 SKIP → REMAIN_ON_3PHASE (not blocked)"
else
  fail "T6c: expected REMAIN_ON_3PHASE (gate3=SKIP), got '${result}'"
fi
if [[ -n "$vf" ]] && grep -q "Gate 3.*SKIP\|Status: SKIP" "$vf" 2>/dev/null; then
  pass "T6c-skip: verdict file records Gate 3 SKIP"
else
  fail "T6c-skip: verdict file missing Gate 3 SKIP"
fi

# T6d: Zero stories in routing.jsonl → INCONCLUSIVE (exit 0)
> "$ROUTING_LOG"
write_base_backlog "null"
result="$(run_validate --cohort-size 5)"
exit_code=$?
if [[ "$result" == "INCONCLUSIVE_INSUFFICIENT_DATA" ]] && [[ "$exit_code" -eq 0 ]]; then
  pass "T6d: zero stories → exit 0 + INCONCLUSIVE_INSUFFICIENT_DATA"
else
  fail "T6d: expected INCONCLUSIVE(exit 0), got '${result}'(exit ${exit_code})"
fi

# T6e: Timestamp parse error in routing.jsonl — skip + no crash
> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3 4 5; do
  append_story "T6E-STORY-${i}" "done" "3phase"
  append_routing_record "T6E-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T6E-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
# Inject record with bad timestamp
echo '{"trace_id":"bad-ts","story_id":"T6E-STORY-6","phase":"commit","pipeline":"3phase","provider":"daemon-bash","model":"n/a","duration_ms":0,"fallback_reason":null,"impl_model_tag":"primary","timestamp":"INVALID-TIMESTAMP"}' >> "$ROUTING_LOG"
result="$(run_validate --cohort-size 10)"
exit_code=$?
if [[ "$exit_code" -eq 0 ]]; then
  pass "T6e: timestamp parse error — no crash (exit 0)"
else
  fail "T6e: timestamp parse error caused non-zero exit: ${exit_code}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# T7: Verdict file structure — required section headers (AC6e)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "T7: Verdict file structure"

> "$ROUTING_LOG"
write_base_backlog "null"
for i in 1 2 3 4 5; do
  append_story "T7-STORY-${i}" "done" "3phase"
  append_routing_record "T7-STORY-${i}" "commit" "3phase" "null" "2026-04-15T10:0${i}:00.000Z"
  append_routing_record "T7-STORY-${i}" "impl" "3phase" "null" "2026-04-15T09:0${i}:00.000Z"
done
run_validate --cohort-size 5 > /dev/null

vf="$(last_verdict_file)"
if [[ -z "$vf" ]]; then
  fail "T7: no verdict file found in ${VERDICTS_DIR}"
else
  pass "T7-file: verdict file created"

  # Check required headers per AC6e
  if grep -q "^## Overall Recommendation" "$vf"; then
    pass "T7-h1: ## Overall Recommendation present"
  else
    fail "T7-h1: ## Overall Recommendation missing"
  fi

  if grep -q "^## Gate 1: Stories Success Count" "$vf"; then
    pass "T7-h2: ## Gate 1: Stories Success Count present"
  else
    fail "T7-h2: ## Gate 1: Stories Success Count missing"
  fi

  if grep -q "^## Gate 2: §6a Violation Check" "$vf"; then
    pass "T7-h3: ## Gate 2: §6a Violation Check present"
  else
    fail "T7-h3: ## Gate 2: §6a Violation Check missing"
  fi

  if grep -q "^## Gate 3: rapid_refill_breaker Rate Parity" "$vf"; then
    pass "T7-h4: ## Gate 3: rapid_refill_breaker Rate Parity present"
  else
    fail "T7-h4: ## Gate 3: rapid_refill_breaker Rate Parity missing"
  fi

  if grep -q "^## Cohort Details" "$vf"; then
    pass "T7-h5: ## Cohort Details present"
  else
    fail "T7-h5: ## Cohort Details missing"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "──────────────────────────────────────"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
