#!/usr/bin/env bash
# ── GAAI Routing Matrix Compliance Hook ──────────────────────────────────────
# For each story branch being pushed (story/{id}), checks that the observed
# routing in runtime-routing.jsonl matches the declared impl_model in the
# backlog.  Fails open (exit 0) for legacy deliveries that pre-date the
# wrapper instrumentation (no preflight record = no enforcement).
#
# AC3 (E131S01): emits a clear diagnostic naming story_id, declared impl_model,
# observed routing log state, and bypass options on non-compliance.
# DEC-72: mode invariance — the check is read-only and never mutates the log.
# ─────────────────────────────────────────────────────────────────────────────

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
BACKLOG="${ROOT}/.gaai/project/contexts/backlog/active.backlog.yaml"
ROUTING_LOG="${ROOT}/.gaai/project/contexts/logs/runtime-routing.jsonl"

# jq required for log inspection; fail open if unavailable
if ! command -v jq &>/dev/null; then
  exit 0
fi
# No routing log yet → fail open (first delivery after install)
[[ -f "$ROUTING_LOG" ]] || exit 0
# No backlog → fail open
[[ -f "$BACKLOG" ]] || exit 0

while read -r local_ref _local_sha _remote_ref _remote_sha; do
  branch="${local_ref#refs/heads/}"

  # Only act on story/ branches
  [[ "$branch" =~ ^story/(.+)$ ]] || continue
  story_id="${BASH_REMATCH[1]}"

  # ── 1. Check for preflight record (fail open if absent = legacy delivery) ──
  preflight_count=$(jq -r --arg sid "$story_id" \
    'select(.story_id == $sid and .phase == "preflight") | .story_id' \
    "$ROUTING_LOG" 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$preflight_count" -eq 0 ]]; then
    # No preflight record → legacy delivery, no enforcement
    continue
  fi

  # ── 2. Read declared impl_model from backlog ─────────────────────────────
  declared_impl_model=$(awk -v sid="$story_id" '
    /^- id: / { found = ($0 == "- id: " sid) }
    found && /^  impl_model:/ { val=$2; gsub(/"/, "", val); print val; exit }
  ' "$BACKLOG" 2>/dev/null || true)
  [[ -z "$declared_impl_model" ]] && declared_impl_model="absent"

  # ── 3. Read observed impl phase routing from log ─────────────────────────
  impl_log=$(jq -c --arg sid "$story_id" \
    'select(.story_id == $sid and .phase == "impl")' \
    "$ROUTING_LOG" 2>/dev/null | tail -1)

  if [[ -z "$impl_log" ]]; then
    # No impl record yet (story may not have reached impl phase); skip check
    continue
  fi

  observed_impl_model_tag=$(echo "$impl_log" | jq -r '.impl_model_tag // "absent"' 2>/dev/null)
  observed_provider=$(echo "$impl_log" | jq -r '.provider // "unknown"' 2>/dev/null)

  # ── 4. Compliance check ───────────────────────────────────────────────────
  compliant=true

  if [[ "$declared_impl_model" == "primary" ]]; then
    # Declared primary → tag must be "primary", provider must be "primary"
    if [[ "$observed_impl_model_tag" != "primary" ]]; then
      compliant=false
    fi
  fi
  # For secondary / absent: no hard compliance check in V1 (env_missing is a
  # valid fallback, and secondary_but_env_missing is a known expected value).
  # The preflight record's env_state already surfaces env availability.

  if [[ "$compliant" == "false" ]]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  GAAI Routing Matrix Non-Compliance                              ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║  Story:          $story_id"
    echo "║  Declared:       impl_model: $declared_impl_model"
    echo "║  Observed tag:   $observed_impl_model_tag"
    echo "║  Observed prov:  $observed_provider"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║  Bypass options:                                                 ║"
    echo "║    (A) Re-deliver — run /gaai-deliver $story_id in a fresh session"
    echo "║    (B) Flip tag  — set impl_model: primary on the backlog entry  ║"
    echo "║        then re-push this branch                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
  fi

done

exit 0
