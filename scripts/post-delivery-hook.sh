#!/usr/bin/env bash
# ── GAAI Stop Hook — auto-record delivery metadata after delivery session ─────
#
# Description:
#   Fires on Claude Code Stop event. If a delivery just completed (detects
#   "chore({id}): done [delivery]" in recent git log), captures all missing
#   delivery metadata fields and writes them to the backlog.
#
# Fields captured (idempotent — skips if already set):
#   - cost_usd        (from session transcript)
#   - started_at      (from git log: in_progress commit timestamp)
#   - completed_at    (from git log: done commit timestamp)
#   - pr_url          (from gh pr list)
#   - pr_number       (from gh pr list)
#   - pr_status       (from gh pr list)
#
# Usage:
#   Invoked automatically by Claude Code via .claude/settings.json hooks.Stop.
#   Input: JSON via stdin (hook_event_name, session_id, transcript_path).
#
# Outputs:
#   Updates delivery metadata fields in active.backlog.yaml + commits + pushes
#   to staging. Exits 0 always (non-blocking — metadata is best-effort).
#
# Exit codes:
#   0 — always (errors are logged to stderr, never block the session)
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
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

# ── Helper: check if a field is already set on this story ─────────────────────
field_is_set() {
  local field="$1"
  local val
  val=$(grep -A 20 "id: $story_id" "$BACKLOG" 2>/dev/null \
    | grep -E "^\s+${field}:" \
    | head -1 \
    | sed "s/.*${field}: *//" \
    | tr -d ' \n"') || val=""
  [[ -n "$val" && "$val" != "null" ]]
}

# Track whether any field was updated
fields_updated=0

# ── 3. cost_usd — read from delivery log (type:result → total_cost_usd) ───────
# Source: stream-json output produced by the delivery agent. The type:result
# entry contains the authoritative API-reported cost including all subagents.
# No estimation — if the delivery log is absent or has no result entry, skip.
if ! field_is_set "cost_usd"; then
  cost=""
  delivery_log="$PROJECT_DIR/.gaai/project/contexts/backlog/.delivery-logs/${story_id}.log"
  if [[ -f "$delivery_log" ]]; then
    cost=$(python3 - "$delivery_log" <<'PYEOF'
import json, sys

log_path = sys.argv[1]

try:
    with open(log_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except:
                continue
            if d.get('type') == 'result':
                c = d.get('total_cost_usd') or d.get('costUSD') or 0
                if c:
                    print(round(float(c), 4))
                    sys.exit(0)
except Exception as e:
    sys.stderr.write(f'[post-delivery-hook] delivery log parse error: {e}\n')
PYEOF
    2>/dev/null) || cost=""
  fi

  if [[ -n "$cost" && "$cost" != "0" ]]; then
    "$SCHEDULER" --set-field "$story_id" cost_usd "$cost" "$BACKLOG" 2>/dev/null && {
      fields_updated=1
      echo "[post-delivery-hook] cost_usd=$cost" >&2
    }
  fi
fi

# ── 4. started_at — from git log (in_progress commit timestamp) ──────────────
if ! field_is_set "started_at"; then
  started=$(git log --all --format='%aI' --grep="chore(${story_id}): in_progress" -1 2>/dev/null) || started=""
  if [[ -n "$started" ]]; then
    "$SCHEDULER" --set-field "$story_id" started_at "$started" "$BACKLOG" 2>/dev/null && {
      fields_updated=1
      echo "[post-delivery-hook] started_at=$started" >&2
    }
  fi
fi

# ── 5. completed_at — from git log (done commit timestamp) ───────────────────
if ! field_is_set "completed_at"; then
  completed=$(git log --all --format='%aI' --grep="chore(${story_id}): done" -1 2>/dev/null) || completed=""
  if [[ -n "$completed" ]]; then
    "$SCHEDULER" --set-field "$story_id" completed_at "$completed" "$BACKLOG" 2>/dev/null && {
      fields_updated=1
      echo "[post-delivery-hook] completed_at=$completed" >&2
    }
  fi
fi

# ── 6. PR fields — from gh CLI ───────────────────────────────────────────────
if ! field_is_set "pr_url" || ! field_is_set "pr_number" || ! field_is_set "pr_status"; then
  if command -v gh &>/dev/null; then
    # Search for PR with this story ID in title or branch name
    pr_json=$(gh pr list --state all --search "$story_id" --json url,number,state,mergedAt --limit 1 2>/dev/null) || pr_json=""

    if [[ -n "$pr_json" && "$pr_json" != "[]" ]]; then
      pr_url=$(echo "$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('url',''))" 2>/dev/null) || pr_url=""
      pr_number=$(echo "$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('number',''))" 2>/dev/null) || pr_number=""
      pr_state=$(echo "$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); s=d[0]; print('merged' if s.get('mergedAt') else s.get('state','open').lower())" 2>/dev/null) || pr_state=""

      if [[ -n "$pr_url" ]] && ! field_is_set "pr_url"; then
        "$SCHEDULER" --set-field "$story_id" pr_url "$pr_url" "$BACKLOG" 2>/dev/null && {
          fields_updated=1
          echo "[post-delivery-hook] pr_url=$pr_url" >&2
        }
      fi

      if [[ -n "$pr_number" ]] && ! field_is_set "pr_number"; then
        "$SCHEDULER" --set-field "$story_id" pr_number "$pr_number" "$BACKLOG" 2>/dev/null && {
          fields_updated=1
          echo "[post-delivery-hook] pr_number=$pr_number" >&2
        }
      fi

      if [[ -n "$pr_state" ]] && ! field_is_set "pr_status"; then
        "$SCHEDULER" --set-field "$story_id" pr_status "$pr_state" "$BACKLOG" 2>/dev/null && {
          fields_updated=1
          echo "[post-delivery-hook] pr_status=$pr_state" >&2
        }
      fi
    fi
  fi
fi

# ── 7. Commit + push if any field was updated ────────────────────────────────
if [[ "$fields_updated" -eq 1 ]]; then
  (
    git add "$BACKLOG" 2>/dev/null || exit 1
    git diff --cached --quiet 2>/dev/null && exit 0  # No actual change
    git commit -m "chore($story_id): delivery-metadata [stop-hook]" --quiet 2>/dev/null || exit 1
    git push origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
    echo "[post-delivery-hook] delivery metadata committed for $story_id" >&2
  ) || echo "[post-delivery-hook] Warning: could not commit metadata for $story_id" >&2
fi

exit 0
