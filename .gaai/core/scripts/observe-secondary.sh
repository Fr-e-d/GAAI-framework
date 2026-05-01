#!/usr/bin/env bash
# Live observability for secondary-routed (GLM) IMPL deliveries.
# Tracks R1-R5 preamble compliance (NOTES.md, re-read patterns, Bash discipline)
# and forensic outcomes (rapid_refill_breaker, fallback rate).
#
# Usage:
#   bash .gaai/core/scripts/observe-secondary.sh           # one-shot snapshot
#   bash .gaai/core/scripts/observe-secondary.sh --watch   # refresh every 15s
#   bash .gaai/core/scripts/observe-secondary.sh --story E120S15  # single story
#
# Surfaces ground truth from per-story stream-json logs + forensic dump +
# routing log. No inference, no heuristics that don't map to actual events.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
LOGS_DIR="$PROJECT_DIR/.gaai/project/contexts/backlog/.delivery-logs"
FAIL_LOG="$PROJECT_DIR/.gaai/project/contexts/logs/nested-fail-debug.jsonl"
ROUTE_LOG="$PROJECT_DIR/.gaai/project/contexts/logs/runtime-routing.jsonl"
WORKTREE_BASE="$(cd "$PROJECT_DIR/.." && pwd)/.gaai-worktrees/$(basename "$PROJECT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

WATCH=false
SINGLE_STORY=""
case "${1:-}" in
  --watch)  WATCH=true ;;
  --story)  SINGLE_STORY="${2:-}" ;;
esac

# Active secondary stories : look at the routing log for impl_model_tag=secondary
# preflight events whose story isn't yet `done` in routing log.
list_secondary_stories() {
  if [[ -n "$SINGLE_STORY" ]]; then
    echo "$SINGLE_STORY"
    return
  fi
  # Active tmux sessions correspond to active deliveries
  tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | grep '^gaai-deliver-' \
    | sed 's/gaai-deliver-//' \
    | while read -r s; do
        # Only stories tagged secondary
        if [[ -f "$LOGS_DIR/$s.log" ]] && grep -q '"impl-model-tag" "secondary"\|"impl_model_tag":"secondary"\|--impl-model-tag "secondary"' "$LOGS_DIR/$s.log" 2>/dev/null; then
          echo "$s"
        fi
      done
}

# Returns: NOTES_PRESENT NOTES_BYTES NOTES_MTIME_AGO_SEC
notes_status() {
  local story_id="$1"
  local notes_path="$WORKTREE_BASE/${story_id}-workspace/.gaai/project/contexts/artefacts/notes/${story_id}.notes.md"
  if [[ ! -f "$notes_path" ]]; then
    echo "0 0 -1"
    return
  fi
  local size mtime now
  size=$(wc -c < "$notes_path" | tr -d ' ')
  if [[ "$(uname)" == "Darwin" ]]; then
    mtime=$(stat -f %m "$notes_path")
  else
    mtime=$(stat -c %Y "$notes_path")
  fi
  now=$(date +%s)
  echo "1 $size $((now - mtime))"
}

# Counts agent-level R-rule violations from the per-story log.
# Returns space-separated: REREAD_VIOLATIONS BASH_NO_TAIL_COUNT NOTES_WRITES
compliance_counts() {
  local story_id="$1"
  local log="$LOGS_DIR/$story_id.log"
  [[ ! -f "$log" ]] && { echo "0 0 0"; return; }

  # Reads of the same file_path more than once = R2 violations
  local reread
  reread=$(grep -oE '"name":"Read","input":\{"file_path":"[^"]*"' "$log" 2>/dev/null \
    | sort | uniq -c | awk '$1 > 1 { sum += $1 - 1 } END { print sum+0 }')

  # Bash commands without head/tail/wc (rough heuristic for R4 violation)
  # Whitelist: very short commands, ls, mkdir, cat for impl-report etc.
  local bash_total bash_disciplined
  bash_total=$(grep -oE '"name":"Bash","input":\{"command":"[^"]{50,}"' "$log" 2>/dev/null | wc -l | tr -d ' ')
  bash_disciplined=$(grep -oE '"name":"Bash","input":\{"command":"[^"]{50,}"' "$log" 2>/dev/null \
    | grep -cE 'head|tail|wc -l|jq|grep -c|head -|tail -' || true)
  local bash_no_tail=$((bash_total - bash_disciplined))
  [[ $bash_no_tail -lt 0 ]] && bash_no_tail=0

  # Writes/Edits to NOTES.md path
  local notes_writes
  notes_writes=$(grep -cE '"name":"(Write|Edit)","input":\{"file_path":"[^"]*\.notes\.md"' "$log" 2>/dev/null || echo 0)

  echo "$reread $bash_no_tail $notes_writes"
}

# Latest routing event for the story (impl phase)
latest_impl_outcome() {
  local story_id="$1"
  [[ ! -f "$ROUTE_LOG" ]] && { echo "no-data"; return; }
  jq -r --arg s "$story_id" '
    select(.story_id == $s and .phase == "impl" and (.duration_ms // 0) > 0)
    | "\(.provider)|\(.model)|\(.duration_ms)|\(.fallback_reason // "ok")|\(.compact_events_count // "?")"
  ' "$ROUTE_LOG" 2>/dev/null | tail -1
}

# Latest fail-debug record for the story
latest_fail_dump() {
  local story_id="$1"
  [[ ! -f "$FAIL_LOG" ]] && { echo ""; return; }
  # the dump records don't have story_id directly — match via trace_id from routing log
  local trace_ids
  trace_ids=$(jq -r --arg s "$story_id" \
    'select(.story_id == $s) | .trace_id' "$ROUTE_LOG" 2>/dev/null \
    | sort -u | tr '\n' '|' | sed 's/|$//')
  [[ -z "$trace_ids" ]] && { echo ""; return; }
  jq -r --arg ids "$trace_ids" '
    select(.trace_id | inside($ids | split("|")))
    | "term=\((.stdout_tail // "") | (try capture("\"terminal_reason\":\"(?<v>[^\"]+)\"") // {}) | (.v // "?")) compacts=\((.stdout_tail // "") | (try capture("\"compact_events_count\":(?<v>[0-9]+)") // {}) | (.v // "?")) cost=$\((.stdout_tail // "") | (try capture("\"total_cost_usd\":(?<v>[0-9.]+)") // {}) | (.v // "?"))"
  ' "$FAIL_LOG" 2>/dev/null | tail -1
}

render_story() {
  local story_id="$1"

  # Header
  echo -e "${BOLD}── $story_id ──${NC}"

  # NOTES.md status
  read -r notes_present notes_bytes notes_age_s <<<"$(notes_status "$story_id")"
  if [[ "$notes_present" == "1" ]]; then
    local age_h="$((notes_age_s / 60))m$((notes_age_s % 60))s"
    echo -e "  ${GREEN}✅ NOTES.md${NC}  ${notes_bytes}B  updated ${DIM}${age_h} ago${NC}"
  else
    echo -e "  ${RED}❌ NOTES.md absent${NC}  ${DIM}— R1 violation if IMPL is past first turn${NC}"
  fi

  # Compliance counts
  read -r reread bash_no_tail notes_writes <<<"$(compliance_counts "$story_id")"
  local r2_color="$GREEN" r4_color="$GREEN"
  [[ "$reread" -gt 3 ]]      && r2_color="$YELLOW"
  [[ "$reread" -gt 10 ]]     && r2_color="$RED"
  [[ "$bash_no_tail" -gt 5 ]]  && r4_color="$YELLOW"
  [[ "$bash_no_tail" -gt 15 ]] && r4_color="$RED"
  echo -e "  ${r2_color}R2 re-read violations: $reread${NC}  ${r4_color}R4 bash-no-tail: $bash_no_tail${NC}  ${DIM}NOTES writes: $notes_writes${NC}"

  # Latest impl outcome
  local impl_line
  impl_line="$(latest_impl_outcome "$story_id")"
  if [[ -n "$impl_line" ]]; then
    IFS='|' read -r prov model dur fb compacts <<<"$impl_line"
    local dur_min=$((dur / 60000))s
    local outcome_color="$GREEN" outcome="success"
    if [[ "$fb" != "ok" ]]; then
      outcome_color="$RED"; outcome="$fb"
    fi
    echo -e "  Impl: ${outcome_color}${outcome}${NC}  prov=$prov  model=$model  dur=${dur_min}  compacts=$compacts"

    # Forensic detail if failure
    if [[ "$outcome" != "success" ]]; then
      local fail_line
      fail_line="$(latest_fail_dump "$story_id")"
      [[ -n "$fail_line" ]] && echo -e "  ${DIM}forensic: $fail_line${NC}"
    fi
  else
    echo -e "  Impl: ${DIM}no impl record yet (still in plan/preflight)${NC}"
  fi

  # Recent activity from per-story log
  local last_event
  if [[ -f "$LOGS_DIR/$story_id.log" ]] && command -v jq &>/dev/null; then
    last_event=$(tail -200 "$LOGS_DIR/$story_id.log" 2>/dev/null \
      | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") |
               if .name == "Bash" then ("Bash " + (.input.command // "" | tostring | .[0:80]))
               elif .name == "Read" then ("Read " + (.input.file_path // "" | split("/") | .[-1]))
               elif .name == "Write" or .name == "Edit" then (.name + " " + (.input.file_path // "" | split("/") | .[-1]))
               else .name end' 2>/dev/null \
      | tail -1)
    [[ -n "$last_event" ]] && echo -e "  ${DIM}↳ $last_event${NC}"
  fi

  echo
}

render_all() {
  clear
  echo -e "${BOLD}═══ Secondary IMPL Observability — $(date '+%H:%M:%S') ═══${NC}"
  echo

  local stories
  stories="$(list_secondary_stories)"
  if [[ -z "$stories" ]]; then
    echo -e "  ${DIM}No active secondary deliveries.${NC}"
    echo
    echo -e "  ${BOLD}Recent secondary outcomes (last 24h):${NC}"
    if [[ -f "$ROUTE_LOG" ]]; then
      local cutoff
      cutoff=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
      jq -r --arg cutoff "$cutoff" '
        select(.phase == "impl" and (.duration_ms // 0) > 0 and .timestamp > $cutoff)
        | "\(.story_id)\t\(.provider)\t\(.fallback_reason // "ok")\t\((.duration_ms / 60000 | floor))min"
      ' "$ROUTE_LOG" 2>/dev/null | sort -u | column -t -s $'\t' | head -15
    fi
    return
  fi

  while IFS= read -r s; do
    [[ -n "$s" ]] && render_story "$s"
  done <<<"$stories"
}

if $WATCH; then
  while true; do
    render_all
    sleep 15
  done
else
  render_all
fi
