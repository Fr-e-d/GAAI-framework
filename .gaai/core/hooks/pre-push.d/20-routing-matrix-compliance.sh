#!/usr/bin/env bash
# ── GAAI Routing Matrix Compliance Guard ────────────────────────────────────
# Blocks push of a `story/<id>` branch when the agent skipped the DEC-72
# implementation routing matrix.
#
# Matrix (delivery-loop.workflow.md §6a):
#   impl_model = secondary  AND  GAAI_IMPL_* env present  →  MUST invoke
#   nested-claude-spawn.js (= produce a `phase: impl, provider: secondary`
#   entry in runtime-routing.jsonl)
#
# Enforcement scope (intentionally narrow):
#   We only enforce when BOTH (a) the backlog declares `impl_model: secondary`
#   AND (b) the wrapper preflight observed env_available. In any other case
#   (impl_model absent / primary / env missing), the matrix permits primary
#   in-session execution per E94 D-0 OSS non-regression — no enforcement.
#
# Failure mode:
#   - Push exits non-zero with a clear diagnostic
#   - Story branch stays local; agent must re-run impl with nested wrapper
#     OR the human flips `impl_model: primary` in the backlog as explicit
#     opt-out before retrying the push
#
# Bypass:
#   - Setting `impl_model: primary` in the backlog (legitimate opt-out)
#   - Standard `git push --no-verify` for human-operator emergency
# ─────────────────────────────────────────────────────────────────────────────

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -z "$ROOT" ]] && exit 0

ROUTING_LOG="$ROOT/.gaai/project/contexts/logs/runtime-routing.jsonl"
BACKLOG="$ROOT/.gaai/project/contexts/backlog/active.backlog.yaml"

# Skip if dependencies missing — fail-open to avoid blocking legitimate pushes
# when the project hasn't bootstrapped the routing infra yet
[[ ! -f "$ROUTING_LOG" ]] && exit 0
[[ ! -f "$BACKLOG" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

while read -r local_ref local_sha remote_ref remote_sha; do
  branch="${remote_ref#refs/heads/}"
  [[ "$branch" =~ ^story/(.+)$ ]] || continue
  story_id="${BASH_REMATCH[1]}"

  # Read impl_model from backlog (look 30 lines ahead of the story id anchor)
  impl_model="$(grep -A 30 "^- id: $story_id$" "$BACKLOG" 2>/dev/null \
    | grep -m1 'impl_model:' \
    | sed 's/.*impl_model: *//;s/ *$//;s/^"//;s/"$//' \
    | tr -d '[:space:]')"

  # No impl_model declared OR primary opt-out → matrix permits primary, no enforcement
  [[ -z "$impl_model" || "$impl_model" == "primary" ]] && continue
  [[ "$impl_model" != "secondary" ]] && continue

  # Read wrapper preflight verdict for this story (most recent)
  preflight_env="$(jq -r --arg sid "$story_id" \
    'select(.story_id == $sid and .phase == "preflight") | .fallback_reason' \
    "$ROUTING_LOG" 2>/dev/null | tail -n 1)"

  # No preflight entry → wrapper didn't run (legacy delivery, or hand-launched
  # outside the daemon). Do NOT block — fail-open preserves OSS non-regression
  [[ -z "$preflight_env" || "$preflight_env" == "null" ]] && continue

  # Env was missing at preflight → silent fallback to primary is permitted by
  # the matrix (E94 D-0 OSS non-regression). No enforcement
  [[ "$preflight_env" != "env_available" ]] && continue

  # Strict case: secondary declared + env was available → must have an
  # `impl` phase entry with provider=secondary
  has_secondary_impl="$(jq -r --arg sid "$story_id" \
    'select(.story_id == $sid and .phase == "impl" and .provider == "secondary") | .story_id' \
    "$ROUTING_LOG" 2>/dev/null | head -n 1)"

  if [[ -z "$has_secondary_impl" ]]; then
    echo ""
    echo "BLOCKED: routing matrix compliance violation for $story_id"
    echo ""
    echo "  Backlog declares:    impl_model: secondary"
    echo "  Wrapper preflight:   GAAI_IMPL_* env available"
    echo "  Expected:            runtime-routing.jsonl entry with"
    echo "                       phase=impl, provider=secondary"
    echo "  Found:               none"
    echo ""
    echo "  → Agent ran the implementation phase on primary in-session"
    echo "    instead of invoking nested-claude-spawn.js (DEC-72 §6a)."
    echo ""
    echo "Resolution:"
    echo "  (a) Re-deliver the story so the agent honours the matrix, OR"
    echo "  (b) Flip 'impl_model: primary' in the backlog as explicit opt-out"
    echo "      and re-push (legitimate when the story needs primary reasoning)."
    echo ""
    exit 1
  fi
done

exit 0
