#!/usr/bin/env bash
# ── GAAI Stop Hook — auto-record cost_usd after delivery session ─────────────
#
# Description:
#   Fires on Claude Code Stop event. If a delivery just completed (detects
#   "chore({id}): done [delivery]" in recent git log), extracts total_cost_usd
#   from the session transcript and writes it to the backlog.
#
# Usage:
#   Invoked automatically by Claude Code via .claude/settings.json hooks.Stop.
#   Input: JSON via stdin (hook_event_name, session_id, transcript_path).
#
# Outputs:
#   Updates cost_usd field in active.backlog.yaml + commits + pushes to staging.
#   Exits 0 always (non-blocking — cost is best-effort).
#
# Exit codes:
#   0 — always (errors are logged to stderr, never block the session)
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKLOG="$PROJECT_DIR/.gaai/project/contexts/backlog/active.backlog.yaml"
SCHEDULER="$PROJECT_DIR/.gaai/core/scripts/backlog-scheduler.sh"
TARGET_BRANCH="staging"

# ── 1. Read hook input ────────────────────────────────────────────────────────
input=$(cat 2>/dev/null) || { exit 0; }

transcript_path=$(echo "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path', ''))
except:
    print('')
" 2>/dev/null) || transcript_path=""

# ── 2. Find story ID from recent git log ──────────────────────────────────────
cd "$PROJECT_DIR" || exit 0

git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>/dev/null || true

story_id=$(git log --oneline -20 2>/dev/null \
  | grep -oE 'chore\([A-Z][0-9]+S[0-9]+\): done \[delivery\]' \
  | head -1 \
  | grep -oE '[A-Z][0-9]+S[0-9]+') || story_id=""

if [[ -z "$story_id" ]]; then
  exit 0  # No delivery just completed — skip silently
fi

# ── 3. Skip if cost_usd already set ──────────────────────────────────────────
existing_cost=$(grep -A 15 "id: $story_id" "$BACKLOG" 2>/dev/null \
  | grep 'cost_usd:' \
  | head -1 \
  | sed 's/.*cost_usd: *//' \
  | tr -d ' \n') || existing_cost=""

if [[ -n "$existing_cost" && "$existing_cost" != "null" ]]; then
  exit 0  # Already recorded — idempotent
fi

# ── 4. Extract cost from transcript ──────────────────────────────────────────
cost=""

if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  cost=$(python3 - "$transcript_path" <<'PYEOF'
import json, sys

path = sys.argv[1]
total_cost = 0.0

try:
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except:
                continue
            # Stream-json result message
            if d.get('type') == 'result':
                c = d.get('total_cost_usd') or d.get('cost_usd') or 0
                if c:
                    total_cost = float(c)
            # Transcript assistant message with costUSD field
            if d.get('role') == 'assistant':
                c = d.get('costUSD') or d.get('cost_usd') or 0
                if c:
                    total_cost += float(c)
except Exception as e:
    sys.stderr.write(f'[post-delivery-hook] transcript parse error: {e}\n')

if total_cost > 0:
    print(round(total_cost, 2))
PYEOF
  2>/dev/null) || cost=""
fi

if [[ -z "$cost" || "$cost" == "0" ]]; then
  exit 0  # Could not extract cost — skip silently
fi

# ── 5. Update backlog + commit + push ─────────────────────────────────────────
(
  "$SCHEDULER" --set-field "$story_id" cost_usd "$cost" "$BACKLOG" 2>/dev/null || exit 1
  git add "$BACKLOG" 2>/dev/null || exit 1
  git diff --cached --quiet 2>/dev/null && exit 0  # No change
  git commit -m "chore($story_id): cost_usd=$cost [stop-hook]" --quiet 2>/dev/null || exit 1
  git push origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  echo "[post-delivery-hook] cost_usd=$cost recorded for $story_id" >&2
) || echo "[post-delivery-hook] Warning: could not write cost_usd for $story_id" >&2

exit 0
