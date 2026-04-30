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
  # Extract from stdout_tail the most diagnostic fields of the stream-json
  # `result` event when present. Claude Code emits its session-terminating
  # reason there (rapid_refill_breaker, completed, max_turns, etc.) — that
  # field is the actual root cause indicator, not stderr.
  # capture() emits no output (not null) on no-match — must wrap with `// {}`
  # so the pipeline yields a value and `.v // default` works for all records.
  ((.stdout_tail // "") | (capture("\"terminal_reason\":\"(?<v>[^\"]+)\"") // {}) | (.v // "?")) as $term |
  ((.stdout_tail // "") | (capture("\"num_turns\":(?<v>[0-9]+)") // {}) | (.v // "?")) as $turns |
  ((.stdout_tail // "") | (capture("\"total_cost_usd\":(?<v>[0-9.]+)") // {}) | (.v // "?")) as $cost |
  # When a fatal API error is the trigger, Claude Code embeds it in result.result
  # as "API Error: {...}". Surface the first 200 chars when present.
  ((.stdout_tail // "") | (capture("\"result\":\"(?<v>API Error[^\"]{0,200})") // {}) | (.v // "")) as $apierr |
  ((.stderr_tail // "") | split("\n") | map("    " + .) | .[-6:] | join("\n")) as $stderr_block |
  "── \(.ts) ──",
  "  trace_id:        \(.trace_id)",
  "  model_requested: \(.model_requested)  →  model_actual: \(.model_actual // "n/a")",
  "  exit_code:       \(.exit_code)   duration: \(.duration_ms)ms   turns: \($turns)   cost: $\($cost)",
  "  terminal_reason: \($term)",
  "  base_url:        \(.base_url // "n/a")",
  ("  api_error:       " + (if ($apierr | length) > 0 then "\($apierr)…" else "(none)" end)),
  ("  stderr_tail:     " + (if (.stderr_tail // "" | length) > 0 then "\n\($stderr_block)" else "(empty)" end)),
  ""
'

if [[ -f "$ROUTE_LOG" ]]; then
  echo "═══ Routing summary (last 24h, phase=impl, real spawns only) ═══"
  CUTOFF=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
  # Filter:
  # - duration_ms == 0   → pre-spawn bookkeeping records (manual logger calls in
  #                        the workflow before the actual spawn). Not real spawns.
  # - duration_ms == null → broken logger calls (missing --duration-ms flag).
  # Dedup: same (story_id, provider, duration_ms) → orchestrator double-logged
  #        the same spawn (e.g. runImpl internal + manual post-call). Keep one.
  # Field semantics reminder:
  #   fallback_reason on a `primary` record  = WHY the secondary spawn failed
  #                                            (not whether the primary itself
  #                                            succeeded). A primary record
  #                                            with fallback_reason="X" means
  #                                            "this primary attempt was a
  #                                            fallback triggered by secondary
  #                                            failure X" — the primary may
  #                                            still have succeeded.
  #   fallback_reason on a `secondary` record = the secondary's own failure
  #                                            reason if it failed.
  jq -c --arg cutoff "$CUTOFF" '
    select(.phase == "impl"
           and .timestamp > $cutoff
           and (.duration_ms // 0) > 0)
  ' "$ROUTE_LOG" \
    | jq -r '"\(.story_id)\t\(.provider)\t\(.duration_ms)\t\(.model)\t\(.fallback_reason // "direct")"' \
    | sort -u \
    | awk -F'\t' '{
        prov=$2; model=$4; reason=$5;
        if (prov == "secondary")   { tag = (reason == "direct" ? "success" : "fail:"reason) }
        else                       { tag = (reason == "direct" ? "direct"  : "fallback-from:"reason) }
        print prov"\t"model"\t"tag
      }' \
    | sort | uniq -c | sort -rn
fi
