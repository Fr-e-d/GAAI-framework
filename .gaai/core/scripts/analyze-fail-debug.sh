#!/usr/bin/env bash
# Show recent secondary-provider failures captured by nested-claude-spawn.js
# Usage: bash .gaai/core/scripts/analyze-fail-debug.sh [N]   (default N=10)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
FAIL_LOG="$PROJECT_DIR/.gaai/project/contexts/logs/nested-fail-debug.jsonl"
ROUTE_LOG="$PROJECT_DIR/.gaai/project/contexts/logs/runtime-routing.jsonl"
N="${1:-10}"

if [[ ! -f "$FAIL_LOG" ]]; then
  echo "No fail-debug log yet at $FAIL_LOG"
  exit 0
fi

TOTAL=$(wc -l < "$FAIL_LOG" | tr -d ' ')
echo "═══ Secondary-provider failures (last $N of $TOTAL) ═══"
echo

tail -n "$N" "$FAIL_LOG" | jq -r '
  "── \(.ts) ──",
  "  trace_id:        \(.trace_id)",
  "  model_requested: \(.model_requested)  →  model_actual: \(.model_actual // "n/a")",
  "  exit_code:       \(.exit_code)   duration: \(.duration_ms)ms",
  "  base_url:        \(.base_url // "n/a")",
  "  stderr (tail):",
  ((.stderr_tail // "") | split("\n") | map("    " + .) | .[-8:] | join("\n")),
  ""
'

if [[ -f "$ROUTE_LOG" ]]; then
  echo "═══ Routing summary (last 24h, phase=impl) ═══"
  CUTOFF=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
  jq -r --arg cutoff "$CUTOFF" '
    select(.phase == "impl" and .timestamp > $cutoff) |
    "\(.provider)\t\(.model)\t\(.fallback_reason // "ok")"
  ' "$ROUTE_LOG" | sort | uniq -c | sort -rn
fi
