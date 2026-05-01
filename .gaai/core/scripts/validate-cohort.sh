#!/usr/bin/env bash
# validate-cohort.sh — DEC-88 §validation-gates cohort evaluation harness
#
# Usage:
#   validate-cohort.sh --window <Nd|Nh>     (evaluate records in last N days|hours)
#   validate-cohort.sh --cohort-size <N>     (evaluate last N 3phase commit records)
#
# Output:
#   .gaai/project/contexts/artefacts/cohort-verdicts/{timestamp}.cohort-verdict.md
#
# Verdicts:
#   REMAIN_ON_3PHASE           — all gates PASS (or SKIP)
#   ROLLBACK_TO_LEGACY         — at least one gate FAIL
#   INCONCLUSIVE_INSUFFICIENT_DATA — at least one gate INSUFFICIENT_DATA (no FAIL)
#
# Gates:
#   Gate 1 — ≥5 stories with phase:commit AND pipeline:3phase AND status:done in backlog
#   Gate 2 — each cohort commit story has EXACTLY 1 impl record (0=VIOLATION/FAIL, ≥2=FLAG)
#   Gate 3 — rapid_refill_breaker rate parity vs legacy baseline ±10pp
#             SKIPPED if last_flip_at is null OR legacy n<5
#
# Note on field names in routing.jsonl:
#   - fallback_reason (NOT terminal_reason) is the correct field for rapid_refill_breaker signal
#   - Legacy records have no "pipeline" field — jq: select(.pipeline | not)
#   - 3phase records have pipeline == "3phase" — jq: select(.pipeline == "3phase")
#   - Cutover records have phase == "cutover" — excluded from all analysis
#
# Env var overrides (for test isolation):
#   ROUTING_LOG_PATH   — override routing.jsonl path
#   BACKLOG_FILE       — override active.backlog.yaml path
#   VERDICTS_DIR       — override output directory for verdict files
#
# Exit codes:
#   0 — always (verdict written to file; stdout = verdict string)
#   1 — argument error only

set -euo pipefail

# ── Named constants ────────────────────────────────────────────────────────
BREAKER_RATE_PARITY_PP=10

# ── Resolve paths ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GAAI_CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PROJECT_DIR="$(cd "$GAAI_CORE_DIR/../.." && pwd -P)"

# Allow external override via env vars (for test isolation)
ROUTING_LOG="${ROUTING_LOG_PATH:-$PROJECT_DIR/.gaai/project/contexts/logs/runtime-routing.jsonl}"
BACKLOG_FILE="${BACKLOG_FILE:-$PROJECT_DIR/.gaai/project/contexts/backlog/active.backlog.yaml}"
VERDICTS_DIR="${VERDICTS_DIR:-$PROJECT_DIR/.gaai/project/contexts/artefacts/cohort-verdicts}"

# ── Colors (suppressed if not a terminal) ─────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

# ── Argument parsing ───────────────────────────────────────────────────────
MODE=""
WINDOW_ARG=""
COHORT_SIZE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --window)
      MODE="window"
      WINDOW_ARG="${2:-}"
      if [[ -z "$WINDOW_ARG" ]]; then
        echo -e "${RED}Error: --window requires an argument (e.g. 30d or 72h)${RESET}" >&2
        exit 1
      fi
      if ! [[ "$WINDOW_ARG" =~ ^[0-9]+(d|h)$ ]]; then
        echo -e "${RED}Error: --window value must be Nd or Nh (e.g. 30d or 72h), got '${WINDOW_ARG}'${RESET}" >&2
        exit 1
      fi
      shift 2
      ;;
    --cohort-size)
      MODE="cohort-size"
      COHORT_SIZE="${2:-}"
      if [[ -z "$COHORT_SIZE" ]]; then
        echo -e "${RED}Error: --cohort-size requires a positive integer${RESET}" >&2
        exit 1
      fi
      if ! [[ "$COHORT_SIZE" =~ ^[0-9]+$ ]] || [[ "$COHORT_SIZE" -lt 1 ]]; then
        echo -e "${RED}Error: --cohort-size must be a positive integer, got '${COHORT_SIZE}'${RESET}" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo -e "${RED}Unknown argument: $1${RESET}" >&2
      echo "Usage: $0 {--window <Nd|Nh>|--cohort-size <N>}" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo -e "${RED}Error: --window or --cohort-size is required${RESET}" >&2
  echo "Usage: $0 {--window <Nd|Nh>|--cohort-size <N>}" >&2
  exit 1
fi

# ── Write verdict file helper ──────────────────────────────────────────────
write_verdict_and_exit() {
  local verdict="$1"
  local gate1_status="$2"
  local gate1_notes="$3"
  local gate2_status="$4"
  local gate2_notes="$5"
  local gate3_status="$6"
  local gate3_notes="$7"
  local cohort_list="$8"
  local cohort_count="$9"
  local gate2_detail="${10:-}"
  local gate3_legacy_rate="${11:-}"
  local gate3_3phase_rate="${12:-}"
  local gate2_ok="${13:-0}"
  local gate2_violations="${14:-0}"
  local gate2_flags="${15:-0}"
  local gate1_total="${16:-0}"
  local gate1_done="${17:-0}"
  local last_flip_at="${18:-null}"

  local TIMESTAMP
  TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$VERDICTS_DIR"
  local VERDICT_FILE="$VERDICTS_DIR/${TIMESTAMP}.cohort-verdict.md"

  {
    echo "---"
    echo "generated_at: ${TIMESTAMP}"
    echo "mode: ${MODE}"
    echo "window_or_size: ${WINDOW_ARG:-${COHORT_SIZE}}"
    echo "cohort_count: ${cohort_count}"
    echo "gate1: ${gate1_status}"
    echo "gate2: ${gate2_status}"
    echo "gate3: ${gate3_status}"
    echo "verdict: ${verdict}"
    echo "---"
    echo ""
    echo "## Overall Recommendation"
    echo ""
    echo "**${verdict}**"
    echo ""
    case "$verdict" in
      ROLLBACK_TO_LEGACY)
        echo "> One or more gates FAILED. The 3phase pipeline does not meet DEC-88 validation thresholds."
        echo "> Operator should evaluate failed gates and consider rollback via \`gaai-cutover.sh --to legacy\`."
        ;;
      INCONCLUSIVE_INSUFFICIENT_DATA)
        echo "> Insufficient data to render a verdict. Gather more stories and re-run."
        ;;
      REMAIN_ON_3PHASE)
        echo "> All gates PASS or SKIP. The 3phase pipeline meets DEC-88 validation thresholds."
        ;;
    esac
    echo ""
    echo "## Gate 1: Stories Success Count"
    echo ""
    echo "**Status: ${gate1_status}**"
    echo ""
    echo "- Cohort total: ${gate1_total}"
    echo "- Done in backlog: ${gate1_done}"
    echo "- Threshold: ≥5 done"
    echo "- Notes: ${gate1_notes}"
    echo ""
    echo "## Gate 2: §6a Violation Check"
    echo ""
    echo "**Status: ${gate2_status}**"
    echo ""
    echo "- OK: ${gate2_ok} stories (commit + exactly 1 impl record)"
    echo "- VIOLATION: ${gate2_violations} stories (commit + 0 impl records) — §6a breach"
    echo "- FLAG: ${gate2_flags} stories (commit + ≥2 impl records)"
    echo "- Notes: ${gate2_notes}"
    if [[ -n "$gate2_detail" ]]; then
      echo ""
      echo "### Per-Story Detail"
      echo ""
      echo -e "$gate2_detail"
    fi
    echo ""
    echo "## Gate 3: rapid_refill_breaker Rate Parity"
    echo ""
    echo "**Status: ${gate3_status}**"
    echo ""
    echo "- Threshold: ±${BREAKER_RATE_PARITY_PP}pp"
    echo "- last_flip_at: ${last_flip_at}"
    if [[ -n "$gate3_legacy_rate" ]]; then
      echo "- Legacy baseline rate: ${gate3_legacy_rate}%"
    fi
    if [[ -n "$gate3_3phase_rate" ]]; then
      echo "- 3phase cohort rate: ${gate3_3phase_rate}%"
    fi
    echo "- Notes: ${gate3_notes}"
    echo ""
    echo "## Cohort Details"
    echo ""
    echo "- Mode: ${MODE}"
    echo "- Arg: ${WINDOW_ARG:-${COHORT_SIZE}}"
    echo "- Stories (${cohort_count}):"
    if [[ -n "$cohort_list" ]]; then
      while IFS= read -r sid; do
        [[ -z "$sid" ]] && continue
        echo "  - ${sid}"
      done <<< "$cohort_list"
    fi
    echo ""
    echo "- Routing log: ${ROUTING_LOG}"
    echo "- Backlog: ${BACKLOG_FILE}"
  } > "$VERDICT_FILE"

  echo -e "${GREEN}Verdict written to: ${VERDICT_FILE}${RESET}" >&2
  echo "$verdict"
}

# ── Guard: missing routing.jsonl (AC5a) ───────────────────────────────────
if [[ ! -f "$ROUTING_LOG" ]]; then
  echo -e "${YELLOW}Warning: routing.jsonl not found at ${ROUTING_LOG}${RESET}" >&2
  echo -e "${YELLOW}All gates → INSUFFICIENT_DATA${RESET}" >&2
  write_verdict_and_exit \
    "INCONCLUSIVE_INSUFFICIENT_DATA" \
    "INSUFFICIENT_DATA" "routing.jsonl missing" \
    "INSUFFICIENT_DATA" "routing.jsonl missing" \
    "INSUFFICIENT_DATA" "routing.jsonl missing" \
    "" "0" "" "" "" "0" "0" "0" "0" "0" "null"
  exit 0
fi

# ── Step 1: Collect cohort story IDs from routing.jsonl ──────────────────
# Cohort = 3phase pipeline commit records, excluding cutover phase records
# Malformed JSON lines are skipped (AC5b) using the try/catch jq pattern
echo -e "${BOLD}Collecting cohort records...${RESET}" >&2

# jq safe-parse pattern: skips malformed lines silently
# Excludes cutover phase records per spec
JQ_SAFE='--raw-input . as $raw | try (fromjson | . as $r | select(($r.phase // "") != "cutover") | $r) catch empty'

# Extract all 3phase commit records with timestamps as JSON objects
# Then use Python to filter by window/cohort-size and extract story IDs
COHORT_STORY_IDS_RAW="$(python3 << PYEOF
import json, sys, time
from datetime import datetime, timezone

routing_log = "${ROUTING_LOG}"
mode = "${MODE}"
window_arg = "${WINDOW_ARG:-}"
cohort_size_arg = "${COHORT_SIZE:-}"

records = []
try:
    with open(routing_log) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                # Exclude cutover phase records
                if obj.get('phase', '') == 'cutover':
                    continue
                # Only 3phase commit records
                if obj.get('pipeline') == '3phase' and obj.get('phase') == 'commit':
                    ts = obj.get('timestamp')
                    if ts:
                        records.append(obj)
            except (json.JSONDecodeError, ValueError):
                # AC5b: malformed JSON — skip silently
                print(f"WARN: malformed JSON line skipped", file=sys.stderr)
                continue
except FileNotFoundError:
    pass

# Parse timestamps
def parse_ts(ts_str):
    try:
        dt = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
        return dt.timestamp()
    except Exception:
        return None

if mode == 'window':
    # Parse window arg (Nd or Nh)
    unit = window_arg[-1]
    num = int(window_arg[:-1])
    if unit == 'd':
        cutoff = time.time() - num * 86400
    else:
        cutoff = time.time() - num * 3600
    filtered = []
    for r in records:
        ep = parse_ts(r.get('timestamp', ''))
        if ep is not None and ep >= cutoff:
            filtered.append(r)
    records = filtered
elif mode == 'cohort-size':
    n = int(cohort_size_arg)
    # Sort by timestamp descending, take last N
    valid = [(parse_ts(r.get('timestamp', '')), r) for r in records]
    valid = [(ep, r) for ep, r in valid if ep is not None]
    valid.sort(key=lambda x: x[0], reverse=True)
    records = [r for _, r in valid[:n]]

# Deduplicate by story_id
seen = set()
for r in records:
    sid = r.get('story_id', '')
    if sid and sid not in seen:
        seen.add(sid)
        print(sid)
PYEOF
)" || true

# Filter out WARN lines that went to stdout (shouldn't happen with redirects, safety net)
COHORT_STORY_IDS="$(echo "$COHORT_STORY_IDS_RAW" | grep -v '^WARN:' || true)"

if [[ -n "$COHORT_STORY_IDS" ]]; then
  COHORT_COUNT="$(echo "$COHORT_STORY_IDS" | grep -c . || echo 0)"
else
  COHORT_STORY_IDS=""
  COHORT_COUNT=0
fi

echo -e "${BLUE}Cohort size: ${COHORT_COUNT} stories${RESET}" >&2

# ── Handle zero cohort (AC5d) ──────────────────────────────────────────────
if [[ "$COHORT_COUNT" -eq 0 ]]; then
  write_verdict_and_exit \
    "INCONCLUSIVE_INSUFFICIENT_DATA" \
    "INSUFFICIENT_DATA" "zero cohort records" \
    "INSUFFICIENT_DATA" "zero cohort records" \
    "INSUFFICIENT_DATA" "zero cohort records" \
    "" "0" "" "" "" "0" "0" "0" "0" "0" "null"
  exit 0
fi

# ── Gate 1: Stories Success Count ─────────────────────────────────────────
# Count cohort stories with phase:commit AND pipeline:3phase AND status:done in backlog
# <5 total → INSUFFICIENT_DATA; ≥5 total but <5 done → FAIL; ≥5 done → PASS
echo -e "${BOLD}Running Gate 1: Stories Success Count...${RESET}" >&2

GATE1_TOTAL=$COHORT_COUNT
GATE1_DONE=0

# Use Python to extract story statuses from YAML
GATE1_DONE="$(python3 << PYEOF
import re

backlog = "${BACKLOG_FILE}"
story_ids_str = """${COHORT_STORY_IDS}"""
story_ids = [s.strip() for s in story_ids_str.splitlines() if s.strip()]

try:
    content = open(backlog).read()
except FileNotFoundError:
    print(0)
    exit()

done_count = 0
for sid in story_ids:
    # Find block starting with '- id: <sid>'
    pattern = r'- id: ' + re.escape(sid) + r'\b(.*?)(?=\n- id:|\Z)'
    m = re.search(pattern, content, re.DOTALL)
    if m:
        block = m.group(0)
        sm = re.search(r'\bstatus:\s*([^\n]+)', block)
        if sm:
            status = sm.group(1).strip().strip("'").strip('"')
            if status == 'done':
                done_count += 1

print(done_count)
PYEOF
)"

if [[ "$GATE1_TOTAL" -lt 5 ]]; then
  GATE1_STATUS="INSUFFICIENT_DATA"
  GATE1_NOTES="Only ${GATE1_TOTAL} total cohort stories (need ≥5)"
elif [[ "$GATE1_DONE" -lt 5 ]]; then
  GATE1_STATUS="FAIL"
  GATE1_NOTES="${GATE1_DONE}/${GATE1_TOTAL} stories done (need ≥5 done)"
else
  GATE1_STATUS="PASS"
  GATE1_NOTES="${GATE1_DONE}/${GATE1_TOTAL} stories done"
fi

echo -e "  Gate 1: ${GATE1_STATUS} — ${GATE1_NOTES}" >&2

# ── Gate 2: §6a Violation Check ───────────────────────────────────────────
# For each cohort story, count 3phase impl records in routing.jsonl
# 0 → VIOLATION (FAIL); 1 → OK; ≥2 → FLAG (not a FAIL)
echo -e "${BOLD}Running Gate 2: §6a Violation Check...${RESET}" >&2

# Use Python to count impl records per story
GATE2_JSON="$(python3 << PYEOF
import json, sys

routing_log = "${ROUTING_LOG}"
story_ids_str = """${COHORT_STORY_IDS}"""
story_ids = set(s.strip() for s in story_ids_str.splitlines() if s.strip())

impl_counts = {sid: 0 for sid in story_ids}

try:
    with open(routing_log) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if obj.get('phase', '') == 'cutover':
                    continue
                if obj.get('pipeline') == '3phase' and obj.get('phase') == 'impl':
                    sid = obj.get('story_id', '')
                    if sid in impl_counts:
                        impl_counts[sid] += 1
            except (json.JSONDecodeError, ValueError):
                continue
except FileNotFoundError:
    pass

# Output as VIOLATION/OK/FLAG per story
violations = 0
flags = 0
ok = 0
detail_lines = []

for sid in sorted(story_ids):
    count = impl_counts[sid]
    if count == 0:
        violations += 1
        detail_lines.append(f"  - {sid}: VIOLATION (0 impl records)")
    elif count == 1:
        ok += 1
        detail_lines.append(f"  - {sid}: OK (1 impl record)")
    else:
        flags += 1
        detail_lines.append(f"  - {sid}: FLAG ({count} impl records — expected 1)")

print(f"violations={violations}")
print(f"flags={flags}")
print(f"ok={ok}")
for line in detail_lines:
    print(f"detail={line}")
PYEOF
)"

GATE2_VIOLATIONS="$(echo "$GATE2_JSON" | grep '^violations=' | cut -d= -f2 || echo "0")"
GATE2_FLAGS="$(echo "$GATE2_JSON" | grep '^flags=' | cut -d= -f2 || echo "0")"
GATE2_OK="$(echo "$GATE2_JSON" | grep '^ok=' | cut -d= -f2 || echo "0")"
GATE2_DETAIL="$(echo "$GATE2_JSON" | grep '^detail=' | sed 's/^detail=//' || echo "")"

if [[ "${GATE2_VIOLATIONS:-0}" -gt 0 ]]; then
  GATE2_STATUS="FAIL"
  GATE2_NOTES="${GATE2_VIOLATIONS} violation(s): stories committed without impl record (§6a breach)"
else
  GATE2_STATUS="PASS"
  GATE2_NOTES="OK=${GATE2_OK:-0}, FLAG=${GATE2_FLAGS:-0}, VIOLATION=0"
fi

echo -e "  Gate 2: ${GATE2_STATUS} — ${GATE2_NOTES}" >&2

# ── Gate 3: rapid_refill_breaker Rate Parity ──────────────────────────────
# Legacy baseline: fallback_reason==rapid_refill_breaker in phase:impl with NO pipeline field
#                  within 30d window before last_flip_at
# 3phase rate: same metric in cohort 3phase impl records
# |delta| ≤ BREAKER_RATE_PARITY_PP → PASS
# SKIP if last_flip_at is null OR legacy n<5
#
# Note: fallback_reason (not terminal_reason) is the correct routing.jsonl field
echo -e "${BOLD}Running Gate 3: rapid_refill_breaker Rate Parity...${RESET}" >&2

GATE3_STATUS="SKIP"
GATE3_NOTES=""
GATE3_LEGACY_RATE=""
GATE3_3PHASE_RATE=""

# Read last_flip_at from backlog YAML
LAST_FLIP_AT="$(python3 -c "
import re
try:
    content = open('${BACKLOG_FILE}').read()
    m = re.search(r'cutover_state:.*?last_flip_at:\s*([^\n]+)', content, re.DOTALL)
    if m:
        val = m.group(1).strip().strip(\"'\").strip('\"')
        print('null' if val in ('null', '~', '') else val)
    else:
        print('null')
except Exception:
    print('null')
" 2>/dev/null || echo "null")"

if [[ "$LAST_FLIP_AT" == "null" ]] || [[ -z "$LAST_FLIP_AT" ]]; then
  # AC5c: last_flip_at is null → Gate 3 SKIP
  GATE3_STATUS="SKIP"
  GATE3_NOTES="last_flip_at is null — no cutover yet, Gate 3 skipped"
else
  # Run Gate 3 with Python for reliable float arithmetic and timestamp comparison
  GATE3_JSON="$(python3 << PYEOF
import json, sys
from datetime import datetime, timezone

routing_log = "${ROUTING_LOG}"
last_flip_at_str = "${LAST_FLIP_AT}"
story_ids_str = """${COHORT_STORY_IDS}"""
cohort_story_ids = set(s.strip() for s in story_ids_str.splitlines() if s.strip())
parity_pp = ${BREAKER_RATE_PARITY_PP}

def parse_ts(ts_str):
    try:
        return datetime.fromisoformat(ts_str.replace('Z', '+00:00')).timestamp()
    except Exception:
        return None

# Parse last_flip_at
flip_epoch = parse_ts(last_flip_at_str)
if flip_epoch is None:
    print("status=SKIP")
    print("notes=Could not parse last_flip_at timestamp (AC5e)")
    sys.exit(0)

# Legacy 30d window
legacy_window_start = flip_epoch - 30 * 86400
legacy_window_end = flip_epoch

legacy_impl_total = 0
legacy_breaker_count = 0
phase3_impl_total = 0
phase3_breaker_count = 0

try:
    with open(routing_log) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                # AC5b: malformed JSON — skip
                continue

            if obj.get('phase', '') == 'cutover':
                continue

            pipeline = obj.get('pipeline')  # None for legacy
            phase = obj.get('phase', '')

            if phase == 'impl':
                ts = obj.get('timestamp', '')
                ep = parse_ts(ts) if ts else None

                # Legacy: no pipeline field (pipeline is None/absent)
                if pipeline is None:
                    if ep is not None and legacy_window_start <= ep < legacy_window_end:
                        legacy_impl_total += 1
                        # Note: fallback_reason (not terminal_reason) is the correct field
                        if obj.get('fallback_reason') == 'rapid_refill_breaker':
                            legacy_breaker_count += 1

                # 3phase: pipeline == "3phase" AND story in cohort
                elif pipeline == '3phase':
                    sid = obj.get('story_id', '')
                    if sid in cohort_story_ids:
                        phase3_impl_total += 1
                        if obj.get('fallback_reason') == 'rapid_refill_breaker':
                            phase3_breaker_count += 1

except FileNotFoundError:
    print("status=SKIP")
    print("notes=routing.jsonl not found")
    sys.exit(0)

# Legacy baseline check
if legacy_impl_total < 5:
    print("status=SKIP")
    print(f"notes=Legacy baseline n={legacy_impl_total} (<5 required) — Gate 3 skipped")
    sys.exit(0)

legacy_rate = round(legacy_breaker_count / legacy_impl_total * 100, 2)

if phase3_impl_total == 0:
    print("status=SKIP")
    print("notes=No 3phase impl records in cohort — Gate 3 skipped")
    sys.exit(0)

phase3_rate = round(phase3_breaker_count / phase3_impl_total * 100, 2)
delta = abs(legacy_rate - phase3_rate)

if delta <= parity_pp:
    print("status=PASS")
else:
    print("status=FAIL")
print(f"legacy_rate={legacy_rate}")
print(f"phase3_rate={phase3_rate}")
print(f"legacy_n={legacy_impl_total}")
print(f"phase3_n={phase3_impl_total}")
print(f"delta={round(delta, 2)}")
PYEOF
)"

  GATE3_STATUS="$(echo "$GATE3_JSON" | grep '^status=' | cut -d= -f2 || echo "SKIP")"
  GATE3_NOTES_RAW="$(echo "$GATE3_JSON" | grep '^notes=' | cut -d= -f2- || echo "")"
  GATE3_LEGACY_RATE="$(echo "$GATE3_JSON" | grep '^legacy_rate=' | cut -d= -f2 || echo "")"
  GATE3_3PHASE_RATE="$(echo "$GATE3_JSON" | grep '^phase3_rate=' | cut -d= -f2 || echo "")"
  GATE3_LEGACY_N="$(echo "$GATE3_JSON" | grep '^legacy_n=' | cut -d= -f2 || echo "")"
  GATE3_PHASE3_N="$(echo "$GATE3_JSON" | grep '^phase3_n=' | cut -d= -f2 || echo "")"
  GATE3_DELTA="$(echo "$GATE3_JSON" | grep '^delta=' | cut -d= -f2 || echo "")"

  if [[ -n "$GATE3_NOTES_RAW" ]]; then
    GATE3_NOTES="$GATE3_NOTES_RAW"
  elif [[ -n "$GATE3_LEGACY_RATE" ]] && [[ -n "$GATE3_3PHASE_RATE" ]]; then
    if [[ "$GATE3_STATUS" == "PASS" ]]; then
      GATE3_NOTES="Legacy=${GATE3_LEGACY_RATE}% (n=${GATE3_LEGACY_N:-?}), 3phase=${GATE3_3PHASE_RATE}% (n=${GATE3_PHASE3_N:-?}), delta=${GATE3_DELTA:-?}pp ≤${BREAKER_RATE_PARITY_PP}pp PASS"
    else
      GATE3_NOTES="Legacy=${GATE3_LEGACY_RATE}% (n=${GATE3_LEGACY_N:-?}), 3phase=${GATE3_3PHASE_RATE}% (n=${GATE3_PHASE3_N:-?}), delta=${GATE3_DELTA:-?}pp >${BREAKER_RATE_PARITY_PP}pp FAIL"
    fi
  fi
fi

echo -e "  Gate 3: ${GATE3_STATUS} — ${GATE3_NOTES}" >&2

# ── Overall Recommendation Logic ──────────────────────────────────────────
# - Any gate = FAIL → ROLLBACK_TO_LEGACY
# - Any gate = INSUFFICIENT_DATA (no FAIL) → INCONCLUSIVE_INSUFFICIENT_DATA
# - All gates PASS or SKIP → REMAIN_ON_3PHASE
# Note: SKIP does NOT block a positive verdict (current state: Gate 3 always SKIP bc last_flip_at=null)

HAS_FAIL=false
HAS_INSUFFICIENT=false

for gs in "$GATE1_STATUS" "$GATE2_STATUS" "$GATE3_STATUS"; do
  if [[ "$gs" == "FAIL" ]]; then
    HAS_FAIL=true
  elif [[ "$gs" == "INSUFFICIENT_DATA" ]]; then
    HAS_INSUFFICIENT=true
  fi
done

if [[ "$HAS_FAIL" == "true" ]]; then
  OVERALL_VERDICT="ROLLBACK_TO_LEGACY"
elif [[ "$HAS_INSUFFICIENT" == "true" ]]; then
  OVERALL_VERDICT="INCONCLUSIVE_INSUFFICIENT_DATA"
else
  OVERALL_VERDICT="REMAIN_ON_3PHASE"
fi

echo -e "" >&2
echo -e "${BOLD}Overall verdict: ${OVERALL_VERDICT}${RESET}" >&2

# ── Write verdict file and print result ───────────────────────────────────
write_verdict_and_exit \
  "$OVERALL_VERDICT" \
  "$GATE1_STATUS" "$GATE1_NOTES" \
  "$GATE2_STATUS" "$GATE2_NOTES" \
  "$GATE3_STATUS" "${GATE3_NOTES}" \
  "${COHORT_STORY_IDS}" "$COHORT_COUNT" \
  "${GATE2_DETAIL:-}" \
  "${GATE3_LEGACY_RATE:-}" "${GATE3_3PHASE_RATE:-}" \
  "${GATE2_OK:-0}" "${GATE2_VIOLATIONS:-0}" "${GATE2_FLAGS:-0}" \
  "${GATE1_TOTAL:-0}" "${GATE1_DONE:-0}" \
  "${LAST_FLIP_AT:-null}"
