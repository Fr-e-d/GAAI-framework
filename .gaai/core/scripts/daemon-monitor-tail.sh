#!/usr/bin/env bash
# Helper: continuously shows human-readable status of active deliveries
# Parses stream-json NDJSON logs into readable summaries via jq

LOG_DIR="${1:-.gaai/project/contexts/backlog/.delivery-logs}"
PROJECT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
BACKLOG="$PROJECT_DIR/.gaai/project/contexts/backlog/active.backlog.yaml"

HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

# ANSI colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

format_duration() {
  local seconds="$1"
  if [[ $seconds -lt 60 ]]; then
    echo "${seconds}s"
  elif [[ $seconds -lt 3600 ]]; then
    echo "$(( seconds / 60 ))m$(( seconds % 60 ))s"
  else
    echo "$(( seconds / 3600 ))h$(( (seconds % 3600) / 60 ))m"
  fi
}

health_color() {
  local age_s="$1"
  if [[ $age_s -lt 30 ]]; then
    echo "$GREEN"
  elif [[ $age_s -lt 120 ]]; then
    echo "$YELLOW"
  else
    echo "$RED"
  fi
}

parse_log() {
  local log_file="$1"
  local story_id="$2"

  if [[ ! -f "$log_file" ]]; then
    echo -e "  ${DIM}(log not yet created)${NC}"
    return
  fi

  local size
  size=$(wc -c < "$log_file" | tr -d ' ')
  if [[ "$size" -eq 0 ]]; then
    echo -e "  ${DIM}(waiting for output...)${NC}"
    return
  fi

  # ── Log age & health ──
  local mod_time now age_s age_label color
  if [[ "$(uname)" == "Darwin" ]]; then
    mod_time=$(stat -f %m "$log_file" 2>/dev/null || echo 0)
  else
    mod_time=$(stat -c %Y "$log_file" 2>/dev/null || echo 0)
  fi
  now=$(date +%s)
  age_s=$(( now - mod_time ))
  age_label=$(format_duration $age_s)
  color=$(health_color $age_s)

  # ── Duration (time since delivery started) ──
  local started_at duration_label=""
  started_at=$(grep -A 5 "id: $story_id" "$BACKLOG" 2>/dev/null | grep 'started_at:' | head -1 | sed 's/.*started_at: *"//;s/".*//' || true)
  if [[ -n "$started_at" ]]; then
    local start_epoch
    if [[ "$(uname)" == "Darwin" ]]; then
      start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || echo 0)
    else
      start_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo 0)
    fi
    if [[ "$start_epoch" -gt 0 ]]; then
      duration_label=$(format_duration $(( now - start_epoch )))
    fi
  fi

  # ── Tool call count ──
  local tool_count=0
  if $HAS_JQ; then
    tool_count=$(jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")' "$log_file" 2>/dev/null | wc -l | tr -d ' ')
  else
    tool_count=$(grep -c '"type":"tool_use"' "$log_file" 2>/dev/null || echo 0)
  fi

  # ── Last activity (from system task_progress events) ──
  local last_activity=""
  local last_tool=""
  if $HAS_JQ; then
    last_activity=$(tail -300 "$log_file" 2>/dev/null \
      | jq -r 'select(.type=="system" and .subtype=="task_progress") | .description // empty' 2>/dev/null \
      | tail -1 || true)
    if [[ -z "$last_activity" ]]; then
      # Fallback: last tool_use name + file_path if available
      last_activity=$(tail -300 "$log_file" 2>/dev/null \
        | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | "\(.name) \(.input.file_path // .input.command // .input.pattern // "" | tostring | split("/") | last // "")"' 2>/dev/null \
        | tail -1 || true)
    fi
  else
    last_tool=$(tail -200 "$log_file" 2>/dev/null \
      | grep -o '"type":"tool_use"[^}]*"name":"[^"]*"' \
      | tail -1 \
      | sed 's/.*"name":"\([^"]*\)".*/\1/' 2>/dev/null || true)
    last_activity="$last_tool"
  fi

  # ── Cost ──
  local cost=""
  if $HAS_JQ; then
    cost=$(tail -100 "$log_file" 2>/dev/null \
      | jq -r 'select(.costUSD) | .costUSD' 2>/dev/null \
      | tail -1 || true)
  fi

  # ── Output ──
  local health_icon
  if [[ $age_s -lt 30 ]]; then health_icon="●"
  elif [[ $age_s -lt 120 ]]; then health_icon="◐"
  else health_icon="○"
  fi

  echo -e "  ${color}${health_icon}${NC} ${tool_count} tools | Last update: ${color}${age_label} ago${NC}${duration_label:+ | Running: ${duration_label}}${cost:+ | \$${cost}}"
  [[ -n "$last_activity" ]] && echo -e "  ${DIM}→ ${last_activity:0:100}${NC}"
}

while true; do
  clear
  echo "═══ Active Deliveries (refreshes every 5s) ═══"
  echo ""

  # Find active tmux delivery sessions
  active_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | grep '^gaai-deliver-' \
    | sed 's/gaai-deliver-//' || true)

  if [[ -z "$active_sessions" ]]; then
    echo -e "  ${DIM}No active deliveries. Use /gaai-discover to create stories for the backlog.${NC}"
    sleep 5
    continue
  fi

  for story_id in $active_sessions; do
    log_file="$LOG_DIR/${story_id}.log"
    echo "── $story_id ──"
    parse_log "$log_file" "$story_id"
    echo ""
  done

  sleep 5
done
