#!/usr/bin/env bash
# GAAI Cost Analysis — Delivery Log Extraction Script
# Extracts cost data from .gaai/project/contexts/backlog/.delivery-logs/*.log JSONL files
# Requires: jq >= 1.6
#
# Usage:
#   ./extract-costs.sh [--json] [--logs-dir PATH]
#
# Options:
#   --json       Output raw JSON instead of formatted table
#   --logs-dir   Override delivery logs directory (default: .gaai/project/contexts/backlog/.delivery-logs)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
LOGS_DIR="${LOGS_DIR:-.gaai/project/contexts/backlog/.delivery-logs}"
OUTPUT_FORMAT="table"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --json) OUTPUT_FORMAT="json"; shift ;;
    --logs-dir) LOGS_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

if [[ ! -d "$LOGS_DIR" ]]; then
  echo "Error: Delivery logs directory not found: $LOGS_DIR" >&2
  exit 1
fi

LOG_COUNT=$(ls "$LOGS_DIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
if [[ "$LOG_COUNT" -eq 0 ]]; then
  echo "Error: No .log files found in $LOGS_DIR" >&2
  exit 1
fi

# ── Extract ───────────────────────────────────────────────────────────────────
# For each log, extract result events. Some logs have 0 (interrupted), some have 1,
# some have 2+ (multi-session delivery). We sum across all result events per story.

extract_json() {
  local tmpfile
  tmpfile=$(mktemp)

  for f in "$LOGS_DIR"/*.log; do
    story=$(basename "$f" .log)
    # Extract all result events from this log
    grep '"type":"result"' "$f" 2>/dev/null | while IFS= read -r line; do
      echo "$line" | jq -c --arg story "$story" '{
        story: $story,
        cost: .total_cost_usd,
        duration_min: ((.duration_ms // 0) / 60000 | . * 10 | round / 10),
        turns: (.num_turns // 0),
        models: (
          [.modelUsage | to_entries[] | {
            model: .key,
            cost: .value.costUSD,
            input: .value.inputTokens,
            output: .value.outputTokens,
            cache_read: (.value.cacheReadInputTokens // 0),
            cache_write: (.value.cacheCreationInputTokens // 0)
          }]
        )
      }' 2>/dev/null
    done
  done > "$tmpfile"

  # If grep found nothing (no "type":"result" with that exact format), try jq directly
  if [[ ! -s "$tmpfile" ]]; then
    for f in "$LOGS_DIR"/*.log; do
      story=$(basename "$f" .log)
      jq -c --arg story "$story" 'select(.type=="result") | {
        story: $story,
        cost: .total_cost_usd,
        duration_min: ((.duration_ms // 0) / 60000 | . * 10 | round / 10),
        turns: (.num_turns // 0),
        models: (
          [.modelUsage | to_entries[] | {
            model: .key,
            cost: .value.costUSD,
            input: .value.inputTokens,
            output: .value.outputTokens,
            cache_read: (.value.cacheReadInputTokens // 0),
            cache_write: (.value.cacheCreationInputTokens // 0)
          }]
        )
      }' "$f" 2>/dev/null
    done > "$tmpfile"
  fi

  # Aggregate: group by story, sum multi-session costs
  jq -s '
    group_by(.story) | map({
      story: .[0].story,
      cost: (map(.cost) | add | . * 100 | round / 100),
      duration_min: (map(.duration_min) | add),
      turns: (map(.turns) | add),
      sessions: length,
      models: (
        [map(.models[]) | group_by(.model) | .[] | {
          model: .[0].model,
          cost: (map(.cost) | add | . * 10000 | round / 10000),
          input: (map(.input) | add),
          output: (map(.output) | add),
          cache_read: (map(.cache_read) | add),
          cache_write: (map(.cache_write) | add)
        }]
      )
    }) | sort_by(.story) |
    {
      stories: .,
      summary: {
        total_stories: length,
        total_cost_usd: (map(.cost) | add | . * 100 | round / 100),
        total_duration_min: (map(.duration_min) | add | . * 10 | round / 10),
        total_turns: (map(.turns) | add),
        avg_cost_per_story: (if length > 0 then (map(.cost) | add / length | . * 100 | round / 100) else 0 end),
        min_cost: (map(.cost) | min),
        max_cost: (map(.cost) | max),
        by_model: (
          [map(.models[]) | group_by(.model) | .[] | {
            model: .[0].model,
            total_cost: (map(.cost) | add | . * 100 | round / 100),
            total_output_tokens: (map(.output) | add),
            total_cache_read_tokens: (map(.cache_read) | add),
            total_cache_write_tokens: (map(.cache_write) | add)
          }]
        )
      },
      missing: []
    }
  ' "$tmpfile"

  rm -f "$tmpfile"
}

# ── Check for missing result events ──────────────────────────────────────────
find_missing() {
  for f in "$LOGS_DIR"/*.log; do
    story=$(basename "$f" .log)
    has_result=$(jq -c 'select(.type=="result")' "$f" 2>/dev/null | head -1)
    if [[ -z "$has_result" ]]; then
      echo "$story"
    fi
  done
}

# ── Format table ──────────────────────────────────────────────────────────────
format_table() {
  local data="$1"
  local missing="$2"

  echo ""
  echo "## GAAI Cost Analysis Report"
  echo ""
  echo "| Story | Cost (USD) | Duration | Turns | Sessions |"
  echo "|---|---:|---:|---:|---:|"

  echo "$data" | jq -r '.stories[] | "| \(.story) | $\(.cost) | \(.duration_min)m | \(.turns) | \(.sessions) |"'

  echo ""
  echo "### Summary"
  echo ""
  echo "$data" | jq -r '.summary | "- **Total cost:** $\(.total_cost_usd)\n- **Stories tracked:** \(.total_stories)\n- **Average cost/story:** $\(.avg_cost_per_story)\n- **Range:** $\(.min_cost) — $\(.max_cost)\n- **Total duration:** \(.total_duration_min) min (\(.total_duration_min / 60 | . * 10 | round / 10)h)\n- **Total API turns:** \(.total_turns)"'

  echo ""
  echo "### By Model"
  echo ""
  echo "$data" | jq -r '.summary.by_model[] | "- **\(.model):** $\(.total_cost)"'

  if [[ -n "$missing" ]]; then
    echo ""
    echo "### Missing (no result event)"
    echo ""
    echo "$missing" | while read -r story; do
      echo "- $story (session interrupted — no cost data)"
    done
  fi

  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
DATA=$(extract_json)
MISSING=$(find_missing)

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  # Inject missing list into JSON
  echo "$DATA" | jq --argjson missing "$(echo "$MISSING" | jq -R -s 'split("\n") | map(select(. != ""))')" '.missing = $missing'
else
  format_table "$DATA" "$MISSING"
fi
