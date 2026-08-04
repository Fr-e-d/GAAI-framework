#!/usr/bin/env bash
# Retroactive baseline analysis of GLM secondary deliveries from per-story logs.
# Output: per-story compliance + outcome metrics for the pre-NOTES.md preamble era,
# to compare against post-R1-R6 results once they accumulate.
#
# Usage: bash .gaai/core/scripts/analyze-glm-baseline.sh

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
LOGS_DIR="$PROJECT_DIR/.gaai/project/contexts/backlog/.delivery-logs"
ROUTE_LOG="$PROJECT_DIR/.gaai/project/contexts/logs/runtime-routing.jsonl"
FAIL_LOG="$PROJECT_DIR/.gaai/project/contexts/logs/nested-fail-debug.jsonl"
STORIES_DIR="$PROJECT_DIR/.gaai/project/contexts/artefacts/stories"

# Stories to analyze: 7 fails + 2 successes from 2026-04-30
FAILS=("E107S06" "E107S07" "E109S01" "E111S01" "E120S11" "E120S16")
SUCCESSES=("E115S01" "E130S07")

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Returns: re-Read total violations across all files (count of duplicate Read events)
count_rereads() {
  local log="$1"
  [[ ! -f "$log" ]] && { echo 0; return; }
  grep -oE '"name":"Read","input":\{"file_path":"[^"]*"' "$log" 2>/dev/null \
    | sort | uniq -c | awk '$1 > 1 { sum += $1 - 1 } END { print sum+0 }'
}

# Top-3 most-reread files
top_rereads() {
  local log="$1"
  [[ ! -f "$log" ]] && return
  grep -oE '"name":"Read","input":\{"file_path":"[^"]*"' "$log" 2>/dev/null \
    | sort | uniq -c | sort -rn | awk '$1 > 1' | head -3 \
    | awk '{ count=$1; $1=""; sub(".*file_path\":\"",""); sub("\"$",""); n=split($0,a,"/"); print "      " count "× " a[n] }'
}

# Bash commands without head/tail/wc/jq (rough R4 violation proxy)
count_bash_no_tail() {
  local log="$1"
  [[ ! -f "$log" ]] && { echo "0 0"; return; }
  local total disciplined
  total=$(grep -oE '"name":"Bash","input":\{"command":"[^"]{30,}"' "$log" 2>/dev/null | wc -l | tr -d ' ')
  disciplined=$(grep -oE '"name":"Bash","input":\{"command":"[^"]{30,}"' "$log" 2>/dev/null \
    | grep -cE 'head |tail |wc -l|jq |grep -c|head -|tail -' || true)
  echo "$total $disciplined"
}

# Total tool_use count
count_tools() {
  local log="$1"
  [[ ! -f "$log" ]] && { echo 0; return; }
  grep -c '"type":"tool_use"' "$log" 2>/dev/null || true
}

# Story complexity from artefact
story_acs() {
  local sid="$1"
  local sf="$STORIES_DIR/$sid.story.md"
  [[ ! -f "$sf" ]] && { echo "?"; return; }
  grep -cE '^\*\*AC[0-9]+\*\*|^- \*\*AC[0-9]+\*\*|^### AC[0-9]+|^## AC[0-9]+' "$sf" 2>/dev/null || echo "?"
}

# GLM impl outcome from routing log
glm_outcome() {
  local sid="$1"
  jq -r --arg s "$sid" '
    select(.story_id == $s and .phase == "impl" and .provider == "secondary" and (.duration_ms // 0) > 0)
    | "\(.duration_ms)|\(.compact_events_count // "-")|\(.trace_id)"
  ' "$ROUTE_LOG" 2>/dev/null | tail -1
}

# Forensic terminal_reason if recorded
forensic_term() {
  local trace_id="$1"
  [[ ! -f "$FAIL_LOG" ]] && { echo "n/a"; return; }
  jq -r --arg tid "$trace_id" '
    select(.trace_id == $tid)
    | (.stdout_tail // "") | (capture("\"terminal_reason\":\"(?<v>[^\"]+)\"") // {}) | (.v // "?")
  ' "$FAIL_LOG" 2>/dev/null | tail -1
}

analyze_story() {
  local sid="$1" outcome_label="$2"
  local log="$LOGS_DIR/$sid.log"
  echo -e "${BOLD}── $sid ($outcome_label) ──${NC}"

  # GLM outcome
  local outcome dur compacts trace_id
  outcome=$(glm_outcome "$sid")
  if [[ -z "$outcome" ]]; then
    echo -e "  ${DIM}no GLM impl record${NC}"
    echo
    return
  fi
  IFS='|' read -r dur compacts trace_id <<<"$outcome"
  local dur_min=$((dur / 60000))m$(( (dur / 1000) % 60 ))s
  echo -e "  GLM duration: $dur_min   compacts: $compacts   trace: ${trace_id:0:8}"

  # Forensic
  local term
  term=$(forensic_term "$trace_id")
  if [[ "$term" != "n/a" && "$term" != "?" && -n "$term" ]]; then
    echo -e "  Terminal reason: ${RED}$term${NC}"
  fi

  # Tool count
  local tools
  tools=$(count_tools "$log")
  echo -e "  Total tools (whole orchestrator session): $tools"

  # Re-Read violations
  local rereads
  rereads=$(count_rereads "$log")
  local rrcolor="$GREEN"
  [[ "$rereads" -gt 5 ]]  && rrcolor="$YELLOW"
  [[ "$rereads" -gt 15 ]] && rrcolor="$RED"
  echo -e "  ${rrcolor}R2 re-Read violations: $rereads${NC}"
  top_rereads "$log"

  # Bash discipline
  local bash_metrics
  bash_metrics=$(count_bash_no_tail "$log")
  read -r bash_total bash_disc <<<"$bash_metrics"
  local bash_no_tail=$((bash_total - bash_disc))
  local pct=0
  [[ $bash_total -gt 0 ]] && pct=$((100 * bash_disc / bash_total))
  echo -e "  R4 bash discipline: $bash_disc/$bash_total disciplined (${pct}%)"

  # Story complexity
  local acs
  acs=$(story_acs "$sid")
  echo -e "  Story complexity: $acs ACs"

  echo
}

echo -e "${BOLD}═══ GLM Baseline Analysis (pre-NOTES.md, preamble V1) ═══${NC}"
echo -e "${DIM}Source: per-story stream-json logs + routing log + fail-debug dumps${NC}"
echo -e "${DIM}Era: workflow before commit 0d007fdf (no preamble) and 0d007fdf onwards (preamble V1, 5 simple rules, no NOTES.md)${NC}"
echo

echo -e "${BOLD}── FAILED on GLM (fallback to primary fired) ──${NC}"
for sid in "${FAILS[@]}"; do analyze_story "$sid" "FAIL"; done

echo -e "${BOLD}── SUCCEEDED on GLM (no fallback) ──${NC}"
for sid in "${SUCCESSES[@]}"; do analyze_story "$sid" "SUCCESS"; done

echo -e "${BOLD}── Aggregate baseline metrics ──${NC}"
total_fails=${#FAILS[@]}
total_succ=${#SUCCESSES[@]}
total=$((total_fails + total_succ))
echo "  Sample size: $total stories ($total_fails fails / $total_succ succeed = $((100 * total_succ / total))% success rate)"
echo
echo "  Reference for post-NOTES.md test:"
echo "  - Target success rate: ≥50% (vs $((100 * total_succ / total))% baseline)"
echo "  - Target re-Read median: ≤5 per story"
echo "  - Target compacts before fail: ≥6 (vs current cluster around 3-6)"
