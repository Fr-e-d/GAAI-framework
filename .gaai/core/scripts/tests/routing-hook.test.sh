#!/usr/bin/env bash
# ── routing-hook.test.sh ─────────────────────────────────────────────────────
# Synthetic fixture tests for .gaai/core/hooks/pre-push.d/20-routing-matrix-compliance.sh
# Covers AC5 and AC6 of E131S06 (post-refactor sanity check).
#
# Run from repo root: bash .gaai/core/scripts/tests/routing-hook.test.sh
# Exit 0 = all tests pass. Exit 1 = at least one failure.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

if ! command -v jq &>/dev/null; then
  echo "SKIP: jq not available" && exit 0
fi

TMPDIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$TMPDIR'" EXIT

ROUTING_LOG="$TMPDIR/routing.jsonl"
BACKLOG="$TMPDIR/backlog.yaml"
FAILURES=0

# Inline the hook compliance logic for test isolation.
# This mirrors 20-routing-matrix-compliance.sh exactly but accepts
# ROUTING_LOG and BACKLOG as function arguments instead of deriving
# from ROOT — avoids patching the production hook for test purposes.
run_compliance_check() {
  local story_id="$1"
  local routing_log="$2"
  local backlog="$3"

  [[ -f "$routing_log" ]] || return 0
  [[ -f "$backlog" ]]     || return 0

  local preflight_count
  preflight_count=$(jq -r --arg sid "$story_id" \
    'select(.story_id == $sid and .phase == "preflight") | .story_id' \
    "$routing_log" 2>/dev/null | wc -l | tr -d ' ')
  [[ "$preflight_count" -eq 0 ]] && return 0

  local declared_impl_model
  declared_impl_model=$(awk -v sid="$story_id" '
    /^- id: / { found = ($0 == "- id: " sid) }
    found && /^  impl_model:/ { val=$2; gsub(/"/, "", val); print val; exit }
  ' "$backlog" 2>/dev/null || true)
  [[ -z "$declared_impl_model" ]] && declared_impl_model="absent"

  local impl_log
  impl_log=$(jq -c --arg sid "$story_id" \
    'select(.story_id == $sid and .phase == "impl")' \
    "$routing_log" 2>/dev/null | tail -1)
  [[ -z "$impl_log" ]] && return 0

  local observed_impl_model_tag observed_provider
  observed_impl_model_tag=$(echo "$impl_log" | jq -r '.impl_model_tag // "absent"' 2>/dev/null)
  observed_provider=$(echo "$impl_log" | jq -r '.provider // "unknown"' 2>/dev/null)

  if [[ "$declared_impl_model" == "primary" ]]; then
    if [[ "$observed_impl_model_tag" != "primary" ]]; then
      echo "BLOCKED: story=$story_id declared=$declared_impl_model observed_tag=$observed_impl_model_tag observed_prov=$observed_provider"
      return 1
    fi
  fi
  echo "PASS: story=$story_id declared=$declared_impl_model observed_tag=$observed_impl_model_tag"
  return 0
}

check() {
  local label="$1" expected_exit="$2" actual_exit="$3"
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s — expected exit %d, got %d\n' "$label" "$expected_exit" "$actual_exit"
    FAILURES=$(( FAILURES + 1 ))
  fi
}

run_test() {
  local story_id="$1" declared="$2" preflight_entry="$3" impl_entries="$4"
  printf '%s\n' "$preflight_entry" > "$ROUTING_LOG"
  [[ -n "$impl_entries" ]] && printf '%s\n' "$impl_entries" >> "$ROUTING_LOG"
  # Use cat+heredoc to avoid printf treating "- id:" format as an option flag on macOS.
  cat > "$BACKLOG" << YAML_EOF
- id: ${story_id}
  impl_model: ${declared}
YAML_EOF
  run_compliance_check "$story_id" "$ROUTING_LOG" "$BACKLOG" > /dev/null 2>&1
}

# ── T1: AC5 — secondary declared + module-emitted impl(provider=secondary) → 0 ─
# After E131S02 the phase:impl record is emitted by nested-claude-spawn.js, not the
# agent. Schema is identical; hook must accept it and exit 0 (no hard check on secondary).
run_test "SMOKE01" "secondary" \
  '{"trace_id":"t1","story_id":"SMOKE01","phase":"preflight","provider":"wrapper","model":"n/a","duration_ms":0,"fallback_reason":"env_available","impl_model_tag":"secondary","timestamp":"2026-04-29T10:00:00.000Z"}' \
  '{"trace_id":"t1","story_id":"SMOKE01","phase":"impl","provider":"secondary","model":"glm-5.1","duration_ms":350000,"fallback_reason":null,"impl_model_tag":"secondary","timestamp":"2026-04-29T10:05:00.000Z"}'
check "T1 secondary-declared + module-emitted impl(secondary) → 0" 0 $?

# ── T2: primary declared + impl(primary tag) — compliant → 0 ─────────────────
run_test "SMOKE02" "primary" \
  '{"trace_id":"t2","story_id":"SMOKE02","phase":"preflight","provider":"wrapper","model":"n/a","duration_ms":0,"fallback_reason":"env_available","impl_model_tag":"primary","timestamp":"2026-04-29T10:00:00.000Z"}' \
  '{"trace_id":"t2","story_id":"SMOKE02","phase":"impl","provider":"primary","model":"claude-sonnet-4-6","duration_ms":0,"fallback_reason":null,"impl_model_tag":"primary","timestamp":"2026-04-29T10:05:00.000Z"}'
check "T2 primary-declared + impl(primary-tag) compliant → 0" 0 $?

# ── T3: AC5 BLOCKED — primary declared + impl(tag=secondary) → 1 ─────────────
run_test "SMOKE03" "primary" \
  '{"trace_id":"t3","story_id":"SMOKE03","phase":"preflight","provider":"wrapper","model":"n/a","duration_ms":0,"fallback_reason":"env_available","impl_model_tag":"primary","timestamp":"2026-04-29T10:00:00.000Z"}' \
  '{"trace_id":"t3","story_id":"SMOKE03","phase":"impl","provider":"secondary","model":"glm-5.1","duration_ms":0,"fallback_reason":null,"impl_model_tag":"secondary","timestamp":"2026-04-29T10:05:00.000Z"}'
check "T3 primary-declared + impl(secondary-tag) non-compliant → 1" 1 $?

# ── T4: AC5 absent-impl — primary declared, impl record missing → 0 (fail-open) ─
# Intentional fail-open: if no impl record exists, skip enforcement (Tier 1 / legacy).
# Diverges from original "empty→BLOCK" intent; preserved per E131S06 out-of-scope.
run_test "SMOKE04" "primary" \
  '{"trace_id":"t4","story_id":"SMOKE04","phase":"preflight","provider":"wrapper","model":"n/a","duration_ms":0,"fallback_reason":"env_available","impl_model_tag":"primary","timestamp":"2026-04-29T10:00:00.000Z"}' \
  ''
check "T4 primary-declared + no impl record → 0 (fail-open, documented)" 0 $?

# ── T5: AC6 — universal fallback: two impl records → 0 for secondary declared ──
# After E131S02, a secondary spawn failure produces two phase:impl records (one per
# attempt, shared trace_id). Hook reads tail -1; no hard check on secondary → exit 0.
run_test "SMOKE05" "secondary" \
  '{"trace_id":"t5","story_id":"SMOKE05","phase":"preflight","provider":"wrapper","model":"n/a","duration_ms":0,"fallback_reason":"env_available","impl_model_tag":"secondary","timestamp":"2026-04-29T10:00:00.000Z"}' \
  '{"trace_id":"t5","story_id":"SMOKE05","phase":"impl","provider":"secondary","model":"glm-5.1","duration_ms":350000,"fallback_reason":"EXIT_CODE_NON_ZERO","impl_model_tag":"secondary","timestamp":"2026-04-29T10:05:00.000Z"}
{"trace_id":"t5","story_id":"SMOKE05","phase":"impl","provider":"primary","model":"claude-sonnet-4-6","duration_ms":0,"fallback_reason":null,"impl_model_tag":"secondary","timestamp":"2026-04-29T10:11:00.000Z"}'
check "T5 AC6 universal-fallback two impl records + secondary-declared → 0" 0 $?

# ── T6: absent preflight — legacy delivery → 0 (fail-open) ───────────────────
run_test "SMOKE06" "secondary" \
  '' \
  '{"trace_id":"t6","story_id":"SMOKE06","phase":"impl","provider":"secondary","model":"glm-5.1","duration_ms":350000,"fallback_reason":null,"impl_model_tag":"secondary","timestamp":"2026-04-29T10:05:00.000Z"}'
check "T6 no preflight record → 0 (legacy, fail-open)" 0 $?

echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "ALL TESTS PASS (6/6)"
  exit 0
else
  echo "FAILED: $FAILURES test(s)"
  exit 1
fi
