#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# GAAI Delivery Daemon — Autonomous story delivery loop
# ═══════════════════════════════════════════════════════════════════════════
#
# Description:
#   Polls the active backlog on the staging branch and auto-launches Claude
#   Code delivery sessions for stories that are ready (status: refined, all
#   dependencies done). Prevents double-launching via git-committed
#   in_progress status + PID-based lock files + retry tracking.
#
# Branch model:
#   staging    ←── AI works here (read backlog, create worktrees, merge, push)
#   production ←── Human only. Promote via GitHub PR: staging → production.
#   The AI NEVER interacts with the production branch.
#
# Cross-device coordination:
#   Before launching, the daemon commits status: in_progress to staging and
#   pushes. Other daemons (on other VPS or Mac) see the update via git fetch.
#   PID-based lock files are a local-only backup for same-machine dedup.
#
# Permissions:
#   --dangerously-skip-permissions is always enabled (required for -p mode).
#   Without it, permission prompts hang forever in headless mode.
#   Override with GAAI_SKIP_PERMISSIONS=false to force interactive (not recommended).
#
# Usage:
#   .gaai/core/scripts/delivery-daemon.sh                     # defaults: 30s, 3 slots
#   .gaai/core/scripts/delivery-daemon.sh --interval 15       # poll every 15s
#   .gaai/core/scripts/delivery-daemon.sh --max-concurrent 2  # parallel deliveries
#   .gaai/core/scripts/delivery-daemon.sh --dry-run           # show what would launch
#   .gaai/core/scripts/delivery-daemon.sh --status            # show active/ready/exceeded
#   .gaai/core/scripts/delivery-daemon.sh --exit-when-idle    # auto-stop after 5 idle polls
#   .gaai/core/scripts/delivery-daemon.sh --exit-when-idle 10 # auto-stop after 10 idle polls
#
# Environment overrides:
#   GAAI_POLL_INTERVAL=15            poll every 15s
#   GAAI_MAX_CONCURRENT=2            allow 2 parallel deliveries
#   GAAI_EXIT_WHEN_IDLE=5            auto-stop after N consecutive idle polls (0 = disabled)
#   GAAI_TARGET_BRANCH=staging       target branch (default: staging)
#   GAAI_DELIVERY_TIMEOUT=14400      hard kill timeout in seconds (default: 4h, last resort)
#   GAAI_MAX_TURNS=200               max claude tool-call turns per delivery (primary safety)
#   GAAI_HEARTBEAT_STALE=900         seconds without log output before killing (default: 15min)
#   GAAI_CLAUDE_MODEL=sonnet         claude model to use (default: sonnet)
#   GAAI_STALENESS_THRESHOLD=15000   seconds before orphan in_progress is stale (default: timeout+10min)
#   GAAI_SKIP_PERMISSIONS=true       force --dangerously-skip-permissions
#   GAAI_SKIP_PERMISSIONS=false      force interactive mode (even on VPS)
#   GAAI_DAEMON_WEBHOOK_SECRET=<hex> HMAC-SHA256 secret for signing outgoing webhook POSTs.
#                                    Generate: openssl rand -hex 32
#                                    Provision in cloud: PUT /api/v1/workspaces/:id/webhook-secrets/gaai-daemon
#                                      Body: {"secret":"<hex>"}  Auth: Bearer token (workspace owner)
#                                    When unset, webhooks are sent unsigned and cloud endpoint returns 401.
#                                    See E101S07b FAQ for full provisioning walkthrough.
#
# Session env (DEC-75 §6 — injected into every spawned claude -p subprocess):
#   GAAI_WORKSPACE_ID=<uuid>         workspace UUIDv4; if unset at daemon start, read from
#                                    .gaai/local/workspace-preference.json hint file (E99S11)
#   GAAI_ORG_ID=<uuid>               org UUIDv4; same fallback as GAAI_WORKSPACE_ID
#   GAAI_IMPL_BASE_URL=<url>         secondary impl provider base URL (DEC-72)
#   GAAI_IMPL_AUTH_TOKEN=<token>     secondary impl provider auth token (DEC-72)
#   GAAI_IMPL_MODEL=<model>          secondary impl provider model name (DEC-72)
#   Subprocess fallback: if env unresolved after hint read, E99S05 AC5 surfaces
#   "session binding unresolved" to the user (daemon itself never aborts — AC5).
#
# Requirements:
#   - python3 (macOS built-in, or apt install python3 on VPS)
#   - claude CLI in PATH
#   - Terminal.app (macOS) or tmux (VPS/headless)
#
# VPS setup:
#   git clone <repo> && cd <repo>
#   git checkout staging
#   git config core.hooksPath .githooks     # activate pre-push hook
#   npm install                              # dependencies
#   bash .gaai/core/scripts/daemon-setup.sh  # auto-creates secrets file
#
# Required: suppress the --dangerously-skip-permissions warning dialog:
#   mkdir -p ~/.claude && cat > ~/.claude/settings.json << 'EOF'
#   { "skipDangerousModePermissionPrompt": true }
#   EOF
#
# Run daemon:
#   tmux new-session -d -s gaai-daemon '.gaai/core/scripts/delivery-daemon.sh --max-concurrent 3'
#   tmux attach -t gaai-daemon
#
# Observability:
#   .gaai/core/scripts/delivery-daemon.sh --status
#   tail -f .gaai/project/contexts/backlog/.delivery-logs/E06S11.log
#   tmux attach -t gaai-deliver-E06S11
#   tmux ls | grep gaai-deliver
#
# Promote to production (from GitHub):
#   Create PR: staging → production
#   Review changes, merge, GitHub Actions deploys
#
# Exit codes:
#   0 — clean shutdown (Ctrl+C)
#   1 — missing dependency or config error
# ═══════════════════════════════════════════════════════════════════════════

# ── Resolve project root + auto-detect core/project layout ────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAAI_CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$GAAI_CORE_DIR/../.." && pwd)"

# Auto-detect project directory (v2.x core/project split vs v1.x flat)
if [[ -d "$GAAI_CORE_DIR/../project" ]]; then
  GAAI_PROJECT_DIR="$GAAI_CORE_DIR/../project"
else
  GAAI_PROJECT_DIR="$GAAI_CORE_DIR/contexts"  # backwards compat v1.x
fi

# ── Configuration ─────────────────────────────────────────────────────────
POLL_INTERVAL="${GAAI_POLL_INTERVAL:-30}"
MAX_CONCURRENT="${GAAI_MAX_CONCURRENT:-3}"
TARGET_BRANCH="${GAAI_TARGET_BRANCH:-staging}"
# Auto-stop when fully idle (no ready stories + zero in-flight deliveries) for
# this many consecutive polls. 0 = disabled (default ; daemon polls forever).
# Set via --exit-when-idle [N] CLI flag or GAAI_EXIT_WHEN_IDLE env var.
EXIT_WHEN_IDLE_THRESHOLD="${GAAI_EXIT_WHEN_IDLE:-0}"
DELIVERY_TIMEOUT="${GAAI_DELIVERY_TIMEOUT:-14400}"   # 4h hard kill (last resort)
MAX_TURNS="${GAAI_MAX_TURNS:-200}"                    # primary safety net
CLAUDE_MODEL="${GAAI_CLAUDE_MODEL:-sonnet}"           # model (sonnet = cost-effective)
HEARTBEAT_STALE="${GAAI_HEARTBEAT_STALE:-1800}"       # 30min no output = stuck (allows long MCP calls like deep research)
STALENESS_THRESHOLD="${GAAI_STALENESS_THRESHOLD:-}"   # auto-computed below
DRY_RUN=false
STATUS_MODE=false

BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="$PROJECT_DIR/$BACKLOG_REL"
BACKLOG_FILE="$BACKLOG"   # alias for daemon-dispatch.sh library (E134S02)
SCHEDULER="$SCRIPT_DIR/backlog-scheduler.sh"
LOCK_DIR="$GAAI_PROJECT_DIR/contexts/backlog/.delivery-locks"
DRIFT_MARKER="$LOCK_DIR/.drift-detected.audit"
REBASE_CONFLICT_MARKER="$LOCK_DIR/.rebase-conflict.audit"
LOG_DIR="$GAAI_PROJECT_DIR/contexts/backlog/.delivery-logs"
STAGING_LOCK="$LOCK_DIR/.staging.lock"
RETRY_FILE="$LOCK_DIR/.retry-counts"
RESOLUTION_TRACKING="$LOCK_DIR/.resolution-tracking"
LOG_FILE="$GAAI_PROJECT_DIR/contexts/backlog/.delivery-daemon.log"
MAX_RETRIES=3

# Source chore-commit helper (Option B' flock+yq — E134S16)
# shellcheck source=lib/chore-commit.sh
BACKLOG_FILE="$BACKLOG"
source "$SCRIPT_DIR/lib/chore-commit.sh"
NOTIFICATION_WEBHOOK="${GAAI_NOTIFICATION_WEBHOOK:-}"
WEBHOOK_SECRET="${GAAI_DAEMON_WEBHOOK_SECRET:-}"

# Staleness: stories in_progress for longer than this are considered orphaned
# Default: delivery timeout + 10 min buffer
if [[ -z "$STALENESS_THRESHOLD" ]]; then
  STALENESS_THRESHOLD=$(( DELIVERY_TIMEOUT + 600 ))
fi

# ── Platform detection ──────────────────────────────────────────────────
PLATFORM="$(uname)"
case "$PLATFORM" in
  Darwin|Linux) ;;
  MINGW*|MSYS*|CYGWIN*)
    echo -e "${RED:-}ERROR: Native Windows (Git Bash/MSYS2) is not supported.${NC:-}"
    echo "Use WSL (Windows Subsystem for Linux) instead:"
    echo "  wsl --install && wsl"
    echo "  cd /mnt/c/path/to/project && .gaai/core/scripts/delivery-daemon.sh"
    exit 1
    ;;
  *)
    echo -e "${RED:-}WARNING: Untested platform '$PLATFORM' — proceeding with Linux defaults${NC:-}"
    ;;
esac

# --dangerously-skip-permissions: required for -p mode (headless).
# Without it, permission prompts hang forever since there's no interactive input.
# Override with GAAI_SKIP_PERMISSIONS=false to force interactive (not recommended for -p).
if [[ -n "${GAAI_SKIP_PERMISSIONS:-}" ]]; then
  SKIP_PERMISSIONS="$GAAI_SKIP_PERMISSIONS"
else
  SKIP_PERMISSIONS=true
fi

# Launcher: prefer tmux (background, robust, cross-platform), fallback to Terminal.app on macOS
if command -v tmux &>/dev/null; then
  LAUNCHER="tmux"
elif [[ "$PLATFORM" == "Darwin" ]] && command -v osascript &>/dev/null; then
  LAUNCHER="terminal-app"
else
  echo -e "${RED:-}ERROR: Neither tmux nor Terminal.app available. Install tmux: brew install tmux (macOS) / apt install tmux (Linux)${NC:-}"
  exit 1
fi

# Claude flags (expanded into wrapper scripts at generation time)
# --output-format stream-json: streams NDJSON events in real-time (tool calls, text)
#   instead of buffering everything until completion. This gives:
#   1. Real-time observability via tail -f on the log file
#   2. Natural heartbeat (log mtime updates continuously)
CLAUDE_FLAGS="--model $CLAUDE_MODEL --max-turns $MAX_TURNS --output-format stream-json --verbose"
if [[ "$SKIP_PERMISSIONS" == "true" ]]; then
  CLAUDE_FLAGS="--dangerously-skip-permissions $CLAUDE_FLAGS"
fi

# Cross-platform: file modification time (epoch seconds)
file_mtime() {
  if [[ "$PLATFORM" == "Darwin" ]]; then
    stat -f %m "$1" 2>/dev/null || echo "0"
  else
    stat -c %Y "$1" 2>/dev/null || echo "0"
  fi
}

# Cross-platform: sed in-place
sed_inplace() {
  if [[ "$PLATFORM" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# ── HMAC signing helper for outgoing webhook POSTs (AC1 — E101S07a) ──────────
# Returns lowercase-hex HMAC-SHA256. Emits a warning and returns "" when
# openssl or xxd is unavailable — callers skip the X-Hub-Signature-256 header.
compute_webhook_hmac() {
  local json="$1" secret="$2"
  if ! command -v openssl &>/dev/null || ! command -v xxd &>/dev/null; then
    log "${YELLOW}[NOTIFY] openssl or xxd not found — webhook sent unsigned (install openssl+xxd for HMAC signing)${NC}"
    echo ""
    return 0
  fi
  printf '%s' "$json" | openssl dgst -sha256 -mac HMAC -macopt "key:$secret" -binary | xxd -p -c 256 | tr -d '\n'
}

# ── Escalation notifications (daemon scope — staleness detection) ─────────
notify_escalation() {
  local story_id="$1"
  local reason="$2"
  local remediation="$3"

  # AC1: terminal bell in daemon's session
  printf '\a'

  # AC2 / AC-ERR: OS-level notification on macOS only
  if [[ "$PLATFORM" == "Darwin" ]]; then
    osascript -e "display notification \"${remediation}\" with title \"GAAI Escalation: ${story_id}\" subtitle \"${reason}\"" 2>/dev/null || true
  fi

  # AC3 / AC4 / AC2(E101S07a): webhook POST (best-effort, never blocks daemon)
  if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local json="{\"story_id\":\"${story_id}\",\"reason\":\"${reason}\",\"remediation\":\"${remediation}\",\"timestamp\":\"${ts}\"}"
    local hmac_hex=""
    if [[ -n "$WEBHOOK_SECRET" ]]; then
      hmac_hex="$(compute_webhook_hmac "$json" "$WEBHOOK_SECRET")"
    else
      log "${YELLOW}[NOTIFY] GAAI_DAEMON_WEBHOOK_SECRET unset — webhook will be rejected by cloud${NC}"
    fi
    local -a hmac_args=()
    [[ -n "$hmac_hex" ]] && hmac_args=(-H "X-Hub-Signature-256: sha256=$hmac_hex" -H "X-Webhook-Source: gaai-daemon")
    if ! curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
        "${hmac_args[@]}" \
        -d "$json" \
        "$NOTIFICATION_WEBHOOK" 2>/dev/null | grep -qE '^2'; then
      log "${YELLOW}[NOTIFY] Webhook failed for $story_id (warning only)${NC}"
    fi
  fi
}

# ── Resolution notifications (daemon scope — escalated/failed → done) ────
notify_resolution() {
  local story_id="$1"
  local prior_status="$2"
  local pr_url="${3:-}"   # may be empty — callers pass "" when absent

  # AC1: terminal bell in daemon's session
  printf '\a'

  # AC2 / AC-ERR1: OS-level notification on macOS only
  if [[ "$PLATFORM" == "Darwin" ]]; then
    local subtitle="Story ${story_id} resolved from ${prior_status} to done"
    if [[ -n "$pr_url" ]]; then
      subtitle="${subtitle} — ${pr_url}"
    fi
    osascript -e "display notification \"${subtitle}\" with title \"GAAI Resolved: ${story_id}\"" 2>/dev/null || true
  fi

  # AC3 / AC4 / AC2(E101S07a): webhook POST (best-effort, never blocks daemon)
  if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    # AC3: pr_url omitted from payload when absent — not null, not empty string
    local json
    if [[ -n "$pr_url" ]]; then
      json="{\"story_id\":\"${story_id}\",\"resolution\":\"done\",\"prior_status\":\"${prior_status}\",\"pr_url\":\"${pr_url}\",\"timestamp\":\"${ts}\"}"
    else
      json="{\"story_id\":\"${story_id}\",\"resolution\":\"done\",\"prior_status\":\"${prior_status}\",\"timestamp\":\"${ts}\"}"
    fi
    local hmac_hex=""
    if [[ -n "$WEBHOOK_SECRET" ]]; then
      hmac_hex="$(compute_webhook_hmac "$json" "$WEBHOOK_SECRET")"
    else
      log "${YELLOW}[NOTIFY] GAAI_DAEMON_WEBHOOK_SECRET unset — webhook will be rejected by cloud${NC}"
    fi
    local -a hmac_args=()
    [[ -n "$hmac_hex" ]] && hmac_args=(-H "X-Hub-Signature-256: sha256=$hmac_hex" -H "X-Webhook-Source: gaai-daemon")
    if ! curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
        "${hmac_args[@]}" \
        -d "$json" \
        "$NOTIFICATION_WEBHOOK" 2>/dev/null | grep -qE '^2'; then
      log "${YELLOW}[NOTIFY] Resolution webhook failed for $story_id (warning only)${NC}"
    fi
  fi
}

# ── Resolution tracking ──────────────────────────────────────────────────
# Persistent file: $RESOLUTION_TRACKING ($LOCK_DIR/.resolution-tracking)
# Format: one line per tracked story: story_id|prior_status
# Semantics:
#   - Written when daemon observes escalated or failed status
#   - Removed when resolution notification fires
#   - Survives daemon restart (persistent, not in-memory)

track_for_resolution() {
  local story_id="$1"
  local status="$2"   # escalated or failed

  # Only track escalated/failed (guard against accidental calls)
  [[ "$status" == "escalated" || "$status" == "failed" ]] || return 0

  # Idempotent write: only add if not already tracked for this story
  # Preserves original prior_status across daemon restarts
  if [[ -f "$RESOLUTION_TRACKING" ]] && grep -q "^${story_id}|" "$RESOLUTION_TRACKING" 2>/dev/null; then
    return 0
  fi

  echo "${story_id}|${status}" >> "$RESOLUTION_TRACKING"
}

untrack_resolved() {
  local story_id="$1"
  [[ -f "$RESOLUTION_TRACKING" ]] || return 0
  # Atomic removal via temp file on same filesystem (avoids partial read during sed)
  local tmp
  tmp=$(mktemp "${RESOLUTION_TRACKING}.XXXXXX")
  grep -v "^${story_id}|" "$RESOLUTION_TRACKING" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$RESOLUTION_TRACKING"
}

scan_and_track_escalated_failed() {
  local backlog_content
  backlog_content=$(fetch_and_read_backlog)
  [[ -z "$backlog_content" ]] && return 0

  local escalated_failed_ids
  escalated_failed_ids=$(echo "$backlog_content" | python3 -c "
import sys
content = sys.stdin.read()
current_id = None
for line in content.splitlines():
    stripped = line.strip()
    if stripped.startswith('- id:'):
        current_id = stripped.split(':', 1)[1].strip()
    elif current_id and stripped.startswith('status:'):
        # Quote-tolerant : strip surrounding quotes so 'status: "escalated"'
        # and 'status: escalated' both parse to 'escalated'. See 2026-05-13
        # ghost-in_progress RCA — writer asymmetry produced quoted output
        # invisible to naive split().strip() readers.
        status = stripped.split(':', 1)[1].strip().strip('\"').strip(\"'\")
        if status in ('escalated', 'failed'):
            print(current_id + '|' + status)
        current_id = None
" 2>/dev/null) || return 0

  [[ -z "$escalated_failed_ids" ]] && return 0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local sid sstatus
    sid="${line%%|*}"
    sstatus="${line##*|}"
    track_for_resolution "$sid" "$sstatus"
  done <<< "$escalated_failed_ids"
}

check_resolution_notifications() {
  [[ -f "$RESOLUTION_TRACKING" ]] || return 0
  [[ -s "$RESOLUTION_TRACKING" ]] || return 0

  local backlog_content
  backlog_content=$(fetch_and_read_backlog)
  [[ -z "$backlog_content" ]] && return 0

  # Read tracking file into array (avoids subshell variable scope issues)
  local -a tracked_entries=()
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    tracked_entries+=("$entry")
  done < "$RESOLUTION_TRACKING"

  local entry
  for entry in "${tracked_entries[@]}"; do
    local tracked_id tracked_prior
    tracked_id="${entry%%|*}"
    tracked_prior="${entry##*|}"
    [[ -z "$tracked_id" || -z "$tracked_prior" ]] && continue

    # Extract current status for this story from backlog
    local current_status
    current_status=$(echo "$backlog_content" | python3 -c "
import sys
content = sys.stdin.read()
current_id = None
for line in content.splitlines():
    stripped = line.strip()
    if stripped.startswith('- id:'):
        current_id = stripped.split(':', 1)[1].strip()
    elif current_id and stripped.startswith('status:'):
        if current_id == '${tracked_id}':
            print(stripped.split(':', 1)[1].strip())
            break
        current_id = None
" 2>/dev/null) || current_status=""

    [[ -z "$current_status" ]] && continue
    [[ "$current_status" != "done" ]] && continue

    # Story transitioned to done — extract pr_url if present
    local pr_url
    pr_url=$(echo "$backlog_content" | python3 -c "
import sys
content = sys.stdin.read()
in_story = False
for line in content.splitlines():
    stripped = line.strip()
    if stripped.startswith('- id:'):
        in_story = stripped.split(':', 1)[1].strip() == '${tracked_id}'
    elif in_story and stripped.startswith('pr_url:'):
        val = stripped.split(':', 1)[1].strip().strip('\"').strip(\"'\")
        if val:
            print(val)
        break
    elif in_story and stripped.startswith('- id:'):
        break
" 2>/dev/null) || pr_url=""

    log "${GREEN}[RESOLVE] ${tracked_id} transitioned from ${tracked_prior} to done — firing resolution notification${NC}"
    notify_resolution "$tracked_id" "$tracked_prior" "$pr_url"
    untrack_resolved "$tracked_id"
  done
}

# ── Parse CLI args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)       POLL_INTERVAL="$2"; shift 2 ;;
    --max-concurrent) MAX_CONCURRENT="$2"; shift 2 ;;
    --exit-when-idle)
      # Optional N — if next arg is a positive integer, use it ; else default 5.
      if [[ -n "${2:-}" && "$2" =~ ^[1-9][0-9]*$ ]]; then
        EXIT_WHEN_IDLE_THRESHOLD="$2"
        shift 2
      else
        EXIT_WHEN_IDLE_THRESHOLD=5
        shift
      fi
      ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --status)         STATUS_MODE=true; shift ;;
    --help|-h)
      sed -n '/^# Description:/,/^# ═══.*═══$/{ /^# ═══.*═══$/d; p; }' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1. Use --help for usage."
      exit 1
      ;;
  esac
done

# ── Colors ────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# ── Logging ───────────────────────────────────────────────────────────────
log() {
  local msg="[$(date '+%H:%M:%S')] $*"
  echo -e "$msg"
  local ESC=$'\033'
  echo -e "$msg" | sed "s/${ESC}\[[0-9;]*m//g" >> "$LOG_FILE"
}

# ── AC4: Drift marker helpers ─────────────────────────────────────────────
# Single-slot file: last-write wins. Cleared when working tree is clean again.
_write_drift_marker() {
  local context="$1" reason="$2"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  printf '%s|%s|%s\n' "$ts" "$context" "$reason" > "$DRIFT_MARKER" 2>/dev/null || true
  log "${YELLOW}[DRIFT] working-tree drift detected ($context): $reason${NC}"
}

_clear_drift_marker_if_clean() {
  if git -C "$PROJECT_DIR" diff --quiet HEAD -- "$BACKLOG_REL" 2>/dev/null; then
    rm -f "$DRIFT_MARKER"
  fi
}

# ── Preflight checks ─────────────────────────────────────────────────────
mkdir -p "$LOCK_DIR" "$LOG_DIR"

if ! command -v python3 &>/dev/null; then
  echo -e "${RED}ERROR: python3 is required${NC}"
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo -e "${RED}ERROR: claude CLI not found in PATH${NC}"
  echo "Install: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi

if [[ ! -f "$SCHEDULER" ]]; then
  echo -e "${RED}ERROR: backlog-scheduler.sh not found at $SCHEDULER${NC}"
  exit 1
fi

if [[ "$LAUNCHER" == "tmux" ]] && ! command -v tmux &>/dev/null; then
  echo -e "${RED}ERROR: tmux is required on Linux/VPS (apt install tmux)${NC}"
  exit 1
fi

# ── Portable flock wrapper ───────────────────────────────────────────────
# Uses flock on Linux, mkdir-based atomic lock on macOS
with_staging_lock() {
  if command -v flock &>/dev/null; then
    flock "$STAGING_LOCK" "$@"
  else
    # macOS fallback: mkdir is atomic on all filesystems
    local lockdir="${STAGING_LOCK}.d"
    local waited=0
    while ! mkdir "$lockdir" 2>/dev/null; do
      sleep 1
      ((waited++))
      if (( waited >= 60 )); then
        log "${RED}Staging lock timeout after 60s${NC}"
        return 1
      fi
    done
    "$@"
    local rc=$?
    rmdir "$lockdir" 2>/dev/null || true
    return $rc
  fi
}

# ── Backlog reading (via git fetch + scheduler) ──────────────────────────
fetch_and_read_backlog() {
  # Fetch latest remote state (does not touch working tree)
  git -C "$PROJECT_DIR" fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true

  # Read backlog from remote ref (always latest committed state)
  local content
  content=$(git -C "$PROJECT_DIR" show "origin/${TARGET_BRANCH}:${BACKLOG_REL}" 2>/dev/null) && {
    echo "$content"
    return
  }

  # Fallback: read from local filesystem
  if [[ -f "$BACKLOG" ]]; then
    cat "$BACKLOG"
  fi
}

find_ready_stories() {
  local backlog_content
  backlog_content=$(fetch_and_read_backlog)
  [[ -z "$backlog_content" ]] && return

  echo "$backlog_content" | "$SCHEDULER" --ready-ids --stdin
}

# ── Lock management ──────────────────────────────────────────────────────
clean_stale_locks() {
  for lock in "$LOCK_DIR"/*.lock; do
    [[ -f "$lock" ]] || continue
    local pid
    pid=$(head -1 "$lock" 2>/dev/null || echo "")
    if [[ -z "$pid" || "$pid" == "pending" ]]; then
      # Placeholder lock older than 60s is stale
      local age
      age=$(( $(date +%s) - $(file_mtime "$lock") ))
      if (( age > 60 )); then
        local sid
        sid=$(basename "$lock" .lock)
        log "${YELLOW}Stale placeholder lock removed: $sid${NC}"
        rm -f "$lock"
      fi
      continue
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      local sid
      sid=$(basename "$lock" .lock)
      log "${YELLOW}Stale lock removed: $sid (PID $pid gone)${NC}"
      rm -f "$lock"
    fi
  done
}

# ── Heartbeat monitoring ─────────────────────────────────────────────────
# Liveness signal is decoupled from claude -p log output: the wrapper runs a
# background loop that touches $LOCK_DIR/<sid>.heartbeat every 30s for the
# entire wrapper lifetime. This covers commit-phase (pure bash, writes no
# claude log) which previously triggered false-positive kills during long
# `gh pr merge` retry waits.
#
# Fallback: if no .heartbeat file exists yet (wrapper still bootstrapping),
# fall back to lock file mtime within the grace period; outside that window,
# legacy log mtime is consulted as a last resort for legacy pipeline wrappers.
check_heartbeats() {
  local now
  now=$(date +%s)

  for lock in "$LOCK_DIR"/*.lock; do
    [[ -f "$lock" ]] || continue
    local sid pid
    sid=$(basename "$lock" .lock)
    pid=$(head -1 "$lock" 2>/dev/null || echo "")
    [[ -z "$pid" || "$pid" == "pending" ]] && continue

    # Check if process is still alive
    if ! kill -0 "$pid" 2>/dev/null; then
      continue  # Will be cleaned by clean_stale_locks
    fi

    # Grace period: skip heartbeat for recently-launched sessions.
    local lock_age=$(( now - $(file_mtime "$lock") ))
    if (( lock_age < HEARTBEAT_STALE )); then
      continue
    fi

    # ── Primary: dedicated heartbeat file written by wrapper ────────────────
    local hb_file="$LOCK_DIR/${sid}.heartbeat"
    if [[ -f "$hb_file" ]]; then
      local hb_age=$(( now - $(file_mtime "$hb_file") ))
      if (( hb_age > HEARTBEAT_STALE )); then
        log "${RED}HEARTBEAT: $sid — heartbeat stale ($(( hb_age / 60 ))min) — sending SIGTERM to PID $pid${NC}"
        kill -TERM "$pid" 2>/dev/null || true
        sleep 30
        if kill -0 "$pid" 2>/dev/null; then
          log "${RED}HEARTBEAT: $sid — SIGKILL PID $pid (did not respond to SIGTERM)${NC}"
          kill -KILL "$pid" 2>/dev/null || true
        fi
      fi
      continue
    fi

    # ── Fallback (legacy / pre-heartbeat wrappers): log mtime ──────────────
    # Kept narrow to avoid the false-positive class fixed by the dedicated
    # heartbeat. Legacy 1-process wrappers and any in-flight wrapper started
    # before this fix still produce log output, so this branch covers them
    # until the next daemon restart cycles all wrappers to the new contract.
    local logfile="$LOG_DIR/${sid}.log"
    if [[ -f "$logfile" ]]; then
      local log_age=$(( now - $(file_mtime "$logfile") ))
      if (( log_age > HEARTBEAT_STALE )); then
        log "${RED}HEARTBEAT: $sid (legacy log fallback) — no output for $(( log_age / 60 ))min — sending SIGTERM to PID $pid${NC}"
        kill -TERM "$pid" 2>/dev/null || true
        sleep 30
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
      fi
      continue
    fi

    # No heartbeat, no log — wrapper is past grace and produced nothing.
    log "${RED}HEARTBEAT: $sid has no heartbeat or log after ${lock_age}s — killing PID $pid${NC}"
    kill -TERM "$pid" 2>/dev/null || true
  done
}

active_count() {
  local count=0
  for lock in "$LOCK_DIR"/*.lock; do
    [[ -f "$lock" ]] || continue
    ((count++))
  done
  echo "$count"
}

active_stories() {
  for lock in "$LOCK_DIR"/*.lock; do
    [[ -f "$lock" ]] || continue
    local sid pid age_s age_min
    sid=$(basename "$lock" .lock)
    pid=$(head -1 "$lock" 2>/dev/null || echo "?")
    age_s=$(( $(date +%s) - $(file_mtime "$lock") ))
    age_min=$(( age_s / 60 ))
    echo "$sid (PID $pid, ${age_min}min)"
  done
}

is_locked() {
  [[ -f "$LOCK_DIR/$1.lock" ]]
}

# ── Retry tracking ────────────────────────────────────────────────────────
# Tracks launch count per story. Resets on daemon restart (intentional).
get_retry_count() {
  local story_id="$1"
  if [[ -f "$RETRY_FILE" ]]; then
    local count
    count=$(grep "^${story_id}=" "$RETRY_FILE" 2>/dev/null | cut -d= -f2 || echo "0")
    echo "${count:-0}"
  else
    echo "0"
  fi
}

increment_retry() {
  local story_id="$1"
  local current next
  current=$(get_retry_count "$story_id")
  next=$(( current + 1 ))
  if [[ -f "$RETRY_FILE" ]]; then
    if grep -q "^${story_id}=" "$RETRY_FILE" 2>/dev/null; then
      sed_inplace "s/^${story_id}=.*/${story_id}=${next}/" "$RETRY_FILE"
    else
      echo "${story_id}=${next}" >> "$RETRY_FILE"
    fi
  else
    echo "${story_id}=${next}" > "$RETRY_FILE"
  fi
}

has_exceeded_retries() {
  local story_id="$1"
  local count
  count=$(get_retry_count "$story_id")
  (( count >= MAX_RETRIES ))
}

exceeded_stories() {
  [[ -f "$RETRY_FILE" ]] || return 0
  while IFS='=' read -r sid count; do
    if (( count >= MAX_RETRIES )); then
      echo "$sid ($count retries)"
    fi
  done < "$RETRY_FILE"
  return 0
}

# ── Staleness detection ──────────────────────────────────────────────────
# Detects stories stuck in in_progress for longer than STALENESS_THRESHOLD.
# Uses git log to find when the story was marked in_progress.
# If stale and no local lock exists → mark as failed on staging.
check_stale_in_progress() {
  local backlog_content
  backlog_content=$(fetch_and_read_backlog)
  [[ -z "$backlog_content" ]] && return 0

  # Extract story IDs with status: in_progress
  local in_progress_ids
  in_progress_ids=$(echo "$backlog_content" | python3 -c '
import sys, re
content = sys.stdin.read()
current_id = None
for line in content.splitlines():
    stripped = line.strip()
    if stripped.startswith("- id:"):
        current_id = stripped.split(":", 1)[1].strip()
    elif current_id and stripped.startswith("status:"):
        # Quote-tolerant : 2026-05-13 ghost-in_progress RCA. chr(34)+chr(39)
        # used to strip both quote types because this Python code is embedded
        # in a bash single-quoted heredoc where a literal quote char would
        # prematurely close the outer bash string.
        status = stripped.split(":", 1)[1].strip().strip(chr(34)+chr(39))
        if status == "in_progress":
            print(current_id)
        current_id = None
' 2>/dev/null) || return 0

  [[ -z "$in_progress_ids" ]] && return 0

  local now
  now=$(date +%s)

  while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue

    # Skip if we have an active local lock (delivery is running on this machine)
    if is_locked "$sid"; then
      continue
    fi

    # Check when the in_progress commit was made (git log on staging)
    local commit_epoch
    commit_epoch=$(git -C "$PROJECT_DIR" log "origin/${TARGET_BRANCH}" \
      --format='%at' -1 --grep="chore(${sid}): in_progress" 2>/dev/null || echo "")

    if [[ -z "$commit_epoch" ]]; then
      # Can't determine age — skip
      continue
    fi

    local age=$(( now - commit_epoch ))

    if (( age > STALENESS_THRESHOLD )); then
      local age_min=$(( age / 60 ))
      log "${RED}STALE: $sid has been in_progress for ${age_min}min (threshold: $(( STALENESS_THRESHOLD / 60 ))min)${NC}"

      if $DRY_RUN; then
        log "${YELLOW}[DRY RUN] Would mark $sid as failed${NC}"
        continue
      fi

      # Mark as failed on staging
      log "${YELLOW}Marking $sid as failed (stale in_progress)...${NC}"
      local reset_script
      reset_script=$(mktemp)
      cat > "$reset_script" <<RSTEOF
#!/usr/bin/env bash
set -euo pipefail
cd "$PROJECT_DIR"
BACKLOG_FILE="$BACKLOG"
BACKLOG_REL="$BACKLOG_REL"
LOCK_DIR="$LOCK_DIR"
TARGET_BRANCH="$TARGET_BRANCH"
SCHEDULER="$SCHEDULER"
# shellcheck source=lib/chore-commit.sh
source "$SCRIPT_DIR/lib/chore-commit.sh"
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  if ! git rebase "origin/$TARGET_BRANCH" --quiet 2>/dev/null; then
    git rebase --abort --quiet 2>/dev/null || true
    echo "[$(date -u +%H:%M:%SZ)] Push race detected — rebase failed (genuine conflict). Skipping this transition. Operator intervention required." >> "$LOG_FILE" 2>/dev/null || true
    printf '%s|recovery|rebase-failed-staleness-$sid\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
    exit 1
  fi
  echo "[$(date -u +%H:%M:%SZ)] Push race detected — rebased onto origin/$TARGET_BRANCH cleanly, retrying push" >> "$LOG_FILE" 2>/dev/null || true
  rm -f "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
fi
chore_commit_field "$sid" status failed "chore($sid): failed [daemon-staleness]" || exit \$?
RSTEOF
      chmod +x "$reset_script"
      local stale_rc=0
      with_staging_lock bash "$reset_script" 2>/dev/null || stale_rc=$?
      rm -f "$reset_script"
      if [[ "$stale_rc" -eq 0 ]]; then
        log "${GREEN}$sid marked as failed (stale recovery)${NC}"
        notify_escalation "$sid" "Stale: stuck in_progress for ${age_min}min" "Run: git log --oneline origin/staging | grep $sid — then reset manually or re-refine"
        track_for_resolution "$sid" "failed"
      elif [[ "$stale_rc" -eq 6 ]]; then
        _write_drift_marker "commit" "staleness-failed-$sid"
      else
        log "${RED}Could not mark $sid as failed — manual intervention needed${NC}"
      fi
    fi
  done <<< "$in_progress_ids"
}

# ── OSS-5 : Crash-recovery scan ──────────────────────────────────────────
# Runs ONCE at daemon start, BEFORE the main loop. For each story
# `status: in_progress` in the backlog with NO live wrapper lock,
# classifies the story state via (.interrupted touch, phase_status, worktree
# state, artefact filesystem) and decides : skip / re-launch (resume) /
# revert refined / reconcile-status.
#
# Rationale : the historical check_stale_in_progress brute-force-marks
# orphan in_progress stories as `failed` after STALENESS_THRESHOLD even
# when the work was intact (commits pushed, PR created, artefacts
# produced). This scan inspects what was actually accomplished and
# resumes from the latest valid checkpoint instead.
#
# Coexistence : check_stale_in_progress stays in the main loop as a
# fallback for during-life orphans not caught at startup. V1.5 may
# deprecate it once OSS-5 is proven.
#
# Decision table :
#   .interrupted touch present
#     → revert status:refined, KEEP phase_status, no retry++, rm touch
#       Reason : daemon-start.sh --stop graceful drain (OSS-3) ; clean resume next start.
#   live wrapper (lock + PID alive)
#     → skip — wrapper survived daemon restart via independent tmux
#   phase_status terminal (done|failed|escalated|qa_escalated)
#     → reconcile YAML status if mismatched, no relaunch
#   phase_status in {qa_passed, implemented, qa_failed}
#     → re-launch wrapper to resume from current phase
#   phase_status == planned + execution-plan.md present
#     → re-launch (resumes impl)
#   phase_status == planned + no execution-plan
#     → revert refined + reset phase_status:not_started + retry++
#   phase_status == not_started or empty
#     → revert refined + retry++
crash_recovery_scan() {
  local backlog_content
  backlog_content=$(fetch_and_read_backlog)
  [[ -z "$backlog_content" ]] && return 0

  # AC1: Read working-tree backlog for per-story drift comparison (before any relaunch).
  # Parses id|status|phase_status for all stories. Empty on python3 failure (graceful degrade).
  local wt_all_status=""
  if [[ -f "$BACKLOG" ]]; then
    wt_all_status=$(python3 -c '
import sys
content = open(sys.argv[1]).read()
cur_id = None; cur_status = None; cur_phase = None
def emit():
    if cur_id:
        print(cur_id + "|" + (cur_status or "") + "|" + (cur_phase or ""))
for line in content.splitlines():
    s = line.strip()
    if s.startswith("- id:"): emit(); cur_id = s.split(":",1)[1].strip(); cur_status = None; cur_phase = None
    elif cur_id and s.startswith("status:"): cur_status = s.split(":",1)[1].strip().strip(chr(34)+chr(39))  # quote-tolerant 2026-05-13 RCA
    elif cur_id and s.startswith("phase_status:"): cur_phase = s.split(":",1)[1].strip().strip(chr(34)+chr(39))  # quote-tolerant
emit()
' "$BACKLOG" 2>/dev/null) || wt_all_status=""
  fi

  # Extract (id|phase_status) pairs for status:in_progress stories in one pass.
  local in_progress_pairs
  in_progress_pairs=$(echo "$backlog_content" | python3 -c '
import sys
content = sys.stdin.read()
cur_id = None
cur_status = None
cur_phase = None
def emit():
    if cur_id and cur_status == "in_progress":
        print(cur_id + "|" + (cur_phase or ""))
for line in content.splitlines():
    stripped = line.strip()
    if stripped.startswith("- id:"):
        emit()
        cur_id = stripped.split(":", 1)[1].strip()
        cur_status = None
        cur_phase = None
    elif cur_id and stripped.startswith("status:"):
        # Quote-tolerant strip via chr() : strips both " and avoids literal
        # quote chars in the Python source (this code is embedded in a bash
        # single-quoted heredoc where any literal quote char would prematurely
        # close the outer bash string). 2026-05-13 ghost-in_progress RCA.
        cur_status = stripped.split(":", 1)[1].strip().strip(chr(34)+chr(39))
    elif cur_id and stripped.startswith("phase_status:"):
        cur_phase = stripped.split(":", 1)[1].strip().strip(chr(34)+chr(39))
emit()
' 2>/dev/null) || return 0

  [[ -z "$in_progress_pairs" ]] && {
    log "${CYAN}[RECOVERY] No in_progress stories to evaluate${NC}"
    return 0
  }

  log "${CYAN}[RECOVERY] Crash-recovery scan : evaluating in_progress stories${NC}"

  local resumed=0 reverted=0 reconciled=0 skipped=0 interrupted=0 drift_detected=0

  while IFS= read -r pair; do
    [[ -z "$pair" ]] && continue
    local sid ps
    sid="${pair%%|*}"
    ps="${pair##*|}"

    # ── AC1: per-story working-tree drift check (in_progress targets only) ───────────
    # HEAD says in_progress; compare WT status/phase_status. Only checks stories that
    # are already in in_progress_pairs (HEAD status == in_progress). Benign edits on
    # draft/deferred/refined stories do NOT freeze recovery for the whole backlog.
    if [[ -n "$wt_all_status" ]]; then
      local wt_row wt_status wt_ps
      wt_row=$(printf '%s\n' "$wt_all_status" | grep "^${sid}|" | head -1)
      wt_status="${wt_row#*|}"
      wt_status="${wt_status%%|*}"
      wt_ps="${wt_row##*|}"
      if [[ -n "$wt_row" ]] && ( [[ "$wt_status" != "in_progress" ]] || [[ "$wt_ps" != "$ps" ]] ); then
        log "${YELLOW}[RECOVERY] $sid : working-tree drift (HEAD=in_progress/${ps:-empty}, WT=${wt_status:-?}/${wt_ps:-?}) — skipping relaunch this scan${NC}"
        _write_drift_marker "scan" "drift-$sid"
        drift_detected=1
        continue
      fi
    fi

    # ── Path 1 : .interrupted touch (graceful daemon-start.sh --stop, OSS-3) ─────────
    local interrupted_marker="$LOCK_DIR/${sid}.interrupted"
    if [[ -f "$interrupted_marker" ]]; then
      log "${YELLOW}[RECOVERY] $sid : .interrupted present — graceful stop, reverting refined (keep phase_status=${ps:-empty})${NC}"
      if $DRY_RUN; then
        log "${YELLOW}[RECOVERY] [DRY RUN] would revert $sid refined + rm .interrupted${NC}"
        ((interrupted++))
        continue
      fi
      if _recovery_revert_refined "$sid" "false" "interrupted"; then
        rm -f "$interrupted_marker"
        ((interrupted++))
      else
        log "${RED}[RECOVERY] $sid : revert refined failed — manual intervention${NC}"
      fi
      continue
    fi

    # ── Path 2 : live wrapper survived restart → skip ─────────────────────
    if is_locked "$sid"; then
      log "${BLUE}[RECOVERY] $sid : live wrapper detected — skipping (will continue independently)${NC}"
      ((skipped++))
      continue
    fi

    # ── Resolve worktree path (mirror handle_*_phase formula) ─────────────
    local worktree_path
    worktree_path=$(_recovery_resolve_worktree "$sid")

    # ── Classify by phase_status ──────────────────────────────────────────
    case "$ps" in
      done)
        log "${GREEN}[RECOVERY] $sid : phase_status=done — reconciling YAML status${NC}"
        if $DRY_RUN; then
          log "${YELLOW}[RECOVERY] [DRY RUN] would set $sid status=done${NC}"
          ((reconciled++))
          continue
        fi
        if _recovery_set_status "$sid" "done" "reconcile-done"; then
          ((reconciled++))
        fi
        ;;
      failed)
        log "${YELLOW}[RECOVERY] $sid : phase_status=failed — reconciling YAML status${NC}"
        if $DRY_RUN; then
          log "${YELLOW}[RECOVERY] [DRY RUN] would set $sid status=failed${NC}"
          ((reconciled++))
          continue
        fi
        if _recovery_set_status "$sid" "failed" "reconcile-failed"; then
          ((reconciled++))
        fi
        ;;
      escalated|qa_escalated)
        log "${YELLOW}[RECOVERY] $sid : phase_status=$ps — reconciling YAML status escalated${NC}"
        if $DRY_RUN; then
          log "${YELLOW}[RECOVERY] [DRY RUN] would set $sid status=escalated${NC}"
          ((reconciled++))
          continue
        fi
        if _recovery_set_status "$sid" "escalated" "reconcile-escalated"; then
          ((reconciled++))
        fi
        ;;
      qa_passed|implemented|qa_failed)
        log "${GREEN}[RECOVERY] $sid : phase_status=$ps — re-launching wrapper to resume${NC}"
        if $DRY_RUN; then
          log "${YELLOW}[RECOVERY] [DRY RUN] would re-launch $sid${NC}"
          ((resumed++))
          continue
        fi
        if _recovery_relaunch "$sid"; then
          ((resumed++))
        fi
        ;;
      planned)
        local plan_path="${worktree_path}/.gaai/project/contexts/artefacts/plans/${sid}.execution-plan.md"
        if [[ -s "$plan_path" ]]; then
          log "${GREEN}[RECOVERY] $sid : phase_status=planned + execution-plan.md present — re-launching${NC}"
          if $DRY_RUN; then
            log "${YELLOW}[RECOVERY] [DRY RUN] would re-launch $sid${NC}"
            ((resumed++))
            continue
          fi
          if _recovery_relaunch "$sid"; then
            ((resumed++))
          fi
        else
          log "${YELLOW}[RECOVERY] $sid : phase_status=planned but no execution-plan.md — revert refined + reset phase_status${NC}"
          if $DRY_RUN; then
            log "${YELLOW}[RECOVERY] [DRY RUN] would revert $sid refined + reset phase_status${NC}"
            ((reverted++))
            continue
          fi
          if _recovery_revert_refined "$sid" "true" "missing-plan"; then
            increment_retry "$sid"
            ((reverted++))
          fi
        fi
        ;;
      not_started|"")
        log "${YELLOW}[RECOVERY] $sid : phase_status=${ps:-empty} — revert refined + retry++${NC}"
        if $DRY_RUN; then
          log "${YELLOW}[RECOVERY] [DRY RUN] would revert $sid refined${NC}"
          ((reverted++))
          continue
        fi
        if _recovery_revert_refined "$sid" "false" "no-progress"; then
          increment_retry "$sid"
          ((reverted++))
        fi
        ;;
      *)
        log "${RED}[RECOVERY] $sid : unknown phase_status='$ps' — skipping (manual review)${NC}"
        ((skipped++))
        ;;
    esac
  done <<< "$in_progress_pairs"

  # AC1/AC4: if this scan detected no drift, clear the marker (working tree is clean).
  if [[ "$drift_detected" -eq 0 ]]; then
    _clear_drift_marker_if_clean
  fi

  log "${CYAN}[RECOVERY] Scan done : resumed=$resumed reverted=$reverted reconciled=$reconciled interrupted=$interrupted skipped=$skipped${NC}"
}

# ── OSS-5 helper : worktree path resolution ──────────────────────────────
# Mirror of the formula in handle_plan_phase / handle_impl_phase / handle_qa_phase.
# Kept duplicated here so crash_recovery_scan does not depend on dispatch
# library being sourced (forward-compat : recovery may move to its own helper
# script V1.5).
_recovery_resolve_worktree() {
  local sid="$1"
  if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
    echo "${GAAI_WORKTREES_BASE}/${sid}-workspace"
  else
    local repo_name
    repo_name=$(basename "$PROJECT_DIR")
    echo "$(cd "${PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${sid}-workspace"
  fi
}

# ── OSS-5 helper : revert YAML status to refined (cross-device pushed) ────
# Args: sid, reset_phase_status (true|false), reason (log marker).
# Pulls staging, sets status, optionally resets phase_status, commits with
# [daemon-recovery:reason] tag, pushes. Mirrors check_stale_in_progress
# pattern (line ~800) — V1 accepts the duplication ; V1.5 may factor.
_recovery_revert_refined() {
  local sid="$1" reset_phase="$2" reason="$3"
  local script
  script=$(mktemp)
  cat > "$script" <<RSTEOF
#!/usr/bin/env bash
set -euo pipefail
cd "$PROJECT_DIR"
BACKLOG_FILE="$BACKLOG"
BACKLOG_REL="$BACKLOG_REL"
LOCK_DIR="$LOCK_DIR"
TARGET_BRANCH="$TARGET_BRANCH"
SCHEDULER="$SCHEDULER"
# shellcheck source=lib/chore-commit.sh
source "$SCRIPT_DIR/lib/chore-commit.sh"
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  if ! git rebase "origin/$TARGET_BRANCH" --quiet 2>/dev/null; then
    git rebase --abort --quiet 2>/dev/null || true
    echo "[$(date -u +%H:%M:%SZ)] Push race detected — rebase failed (genuine conflict). Skipping this transition. Operator intervention required." >> "$LOG_FILE" 2>/dev/null || true
    printf '%s|recovery|rebase-failed-revert-$sid\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
    exit 1
  fi
  echo "[$(date -u +%H:%M:%SZ)] Push race detected — rebased onto origin/$TARGET_BRANCH cleanly, retrying push" >> "$LOG_FILE" 2>/dev/null || true
  rm -f "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
fi
RSTEOF
  if [[ "$reset_phase" == "true" ]]; then
    cat >> "$script" <<RSTEOF
chore_commit_multi_field "$sid" status refined phase_status not_started "chore($sid): refined [daemon-recovery:$reason]" || exit \$?
RSTEOF
  else
    cat >> "$script" <<RSTEOF
chore_commit_field "$sid" status refined "chore($sid): refined [daemon-recovery:$reason]" || exit \$?
RSTEOF
  fi
  cat >> "$script" <<'RSTEOF'
RSTEOF
  chmod +x "$script"
  local rc=0
  with_staging_lock bash "$script" 2>/dev/null || rc=$?
  rm -f "$script"
  if [[ "$rc" -eq 6 ]]; then
    _write_drift_marker "commit" "revert-refined-$sid"
  fi
  return $rc
}

# ── OSS-5 helper : reconcile YAML status to a target value ────────────────
# Used when phase_status is terminal (done|failed|escalated) but YAML status
# still reads in_progress. Idempotent : commits only if there's a real diff.
_recovery_set_status() {
  local sid="$1" new_status="$2" reason="$3"
  local script
  script=$(mktemp)
  cat > "$script" <<RSTEOF
#!/usr/bin/env bash
set -euo pipefail
cd "$PROJECT_DIR"
BACKLOG_FILE="$BACKLOG"
BACKLOG_REL="$BACKLOG_REL"
LOCK_DIR="$LOCK_DIR"
TARGET_BRANCH="$TARGET_BRANCH"
SCHEDULER="$SCHEDULER"
# shellcheck source=lib/chore-commit.sh
source "$SCRIPT_DIR/lib/chore-commit.sh"
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  if ! git rebase "origin/$TARGET_BRANCH" --quiet 2>/dev/null; then
    git rebase --abort --quiet 2>/dev/null || true
    echo "[$(date -u +%H:%M:%SZ)] Push race detected — rebase failed (genuine conflict). Skipping this transition. Operator intervention required." >> "$LOG_FILE" 2>/dev/null || true
    printf '%s|recovery|rebase-failed-reconcile-$new_status-$sid\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
    exit 1
  fi
  echo "[$(date -u +%H:%M:%SZ)] Push race detected — rebased onto origin/$TARGET_BRANCH cleanly, retrying push" >> "$LOG_FILE" 2>/dev/null || true
  rm -f "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
fi
chore_commit_field "$sid" status "$new_status" "chore($sid): $new_status [daemon-recovery:$reason]" || exit \$?
RSTEOF
  chmod +x "$script"
  local rc=0
  with_staging_lock bash "$script" 2>/dev/null || rc=$?
  rm -f "$script"
  if [[ "$rc" -eq 6 ]]; then
    _write_drift_marker "commit" "reconcile-$new_status-$sid"
  fi
  return $rc
}

# ── OSS-5 helper : re-launch a 3phase wrapper for an in_progress story ────
# Skips pre_launch_mark_in_progress — story is already status:in_progress in
# YAML (we're resuming, not initiating). Generates a fresh trace_id.
# Requires daemon-dispatch.sh sourced (caller orders the call site).
_recovery_relaunch() {
  local sid="$1"

  # AC2: re-read WT status immediately before spawning (covers the narrow race window
  # between AC1's scan-time drift check and the wrapper spawn — e.g. operator commits
  # a reset between the case "$ps" branch and this function call).
  local wt_recheck_status=""
  if [[ -f "$BACKLOG" ]]; then
    wt_recheck_status=$(python3 -c "
import sys, os
content = open('$BACKLOG').read() if os.path.isfile('$BACKLOG') else ''
cur_id = None; cur_status = None
for line in content.splitlines():
    s = line.strip()
    if s.startswith('- id:'): cur_id = s.split(':',1)[1].strip(); cur_status = None
    elif cur_id == '${sid}' and s.startswith('status:'): cur_status = s.split(':',1)[1].strip().strip('\"').strip(\"'\"); break  # quote-tolerant (2026-05-13 RCA)
print(cur_status or '')
" 2>/dev/null) || wt_recheck_status=""
  fi
  if [[ -n "$wt_recheck_status" && "$wt_recheck_status" != "in_progress" ]]; then
    log "${YELLOW}[RECOVERY] $sid : status changed to $wt_recheck_status mid-scan — skipping relaunch${NC}"
    return 1
  fi

  local trace_id
  trace_id=$(node -e "import('node:crypto').then(m=>process.stdout.write(m.randomUUID()))" 2>/dev/null \
    || python3 -c "import uuid; print(str(uuid.uuid4()),end='')" 2>/dev/null \
    || echo "recovery-$(date +%s)-$$-$RANDOM")
  launch_3phase_in_tmux "$sid" "$trace_id"
}

# ── PR merge watcher + reconcile helpers ────────────────────────────────────

# Retries pending worktree/branch cleanup entries from .cleanup-pending.audit.
# Called each main-loop cycle. Idempotent: entries cleared on success, kept on failure.
sweep_cleanup_pending() {
  local marker="$LOCK_DIR/.cleanup-pending.audit"
  [[ -f "$marker" ]] || return 0

  local tmp_remaining
  tmp_remaining=$(mktemp "$LOCK_DIR/.cleanup-pending-tmp-XXXXXX.audit")
  local cleaned=0 kept=0

  while IFS='|' read -r ts sid marker_type; do
    [[ -z "$sid" ]] && continue
    [[ "$marker_type" != "cleanup-pending" ]] && continue

    local worktree_path
    if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
      worktree_path="${GAAI_WORKTREES_BASE}/${sid}-workspace"
    else
      local repo_name
      repo_name=$(basename "$PROJECT_DIR")
      worktree_path="$(cd "${PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${sid}-workspace"
    fi

    local wt_ok=true
    if [[ -d "$worktree_path" ]]; then
      git -C "$PROJECT_DIR" worktree remove "$worktree_path" --force 2>/dev/null || wt_ok=false
    fi
    git -C "$PROJECT_DIR" branch -D "story/$sid" 2>/dev/null || true  # already gone = ok

    if $wt_ok; then
      log "${GREEN}[PR-WATCHER] sweep: cleaned pending worktree/branch for $sid${NC}"
      (( cleaned++ )) || true
    else
      printf '%s|%s|cleanup-pending\n' "$ts" "$sid" >> "$tmp_remaining"
      (( kept++ )) || true
    fi
  done < "$marker"

  if [[ $kept -eq 0 ]]; then
    rm -f "$marker" "$tmp_remaining" 2>/dev/null || true
  else
    mv "$tmp_remaining" "$marker" 2>/dev/null || rm -f "$tmp_remaining" 2>/dev/null || true
  fi
}

# PR merge watcher — polls GitHub for merged PRs on every daemon cycle.
# Daemon is sole coordinator: phase_status transitions are daemon-owned, never agent-owned.
# Watcher is read-only: observes operator merges, never auto-merges (trust arc — manual review default).
# Requires chore-commit infrastructure; falls back to inline scheduler if lib/chore-commit.sh absent.
#
# @see governance:3-phase-pipeline — phase_status semantics, daemon owns transitions.
# @see governance:trust-arc-auto-merge — auto-merge OFF baseline ; watcher observes manual merges only.
watch_pr_merge_status() {
  # AC4: opt-out env var
  if [[ "${GAAI_PR_WATCHER_DISABLED:-}" == "1" ]]; then
    return 0
  fi

  # Rate-limit guard: skip if last poll was < 60s ago (silent)
  local poll_ts_file="$LOCK_DIR/.pr-watcher.last-poll"
  if [[ -f "$poll_ts_file" ]]; then
    local last_poll now_ts
    last_poll=$(cat "$poll_ts_file" 2>/dev/null || echo 0)
    now_ts=$(date +%s)
    if (( now_ts - last_poll < 60 )); then
      return 0
    fi
  fi

  # gh availability check (warn once per daemon session)
  local gh_warn_flag="$LOCK_DIR/.pr-watcher.gh-warning-emitted"
  if ! command -v gh &>/dev/null; then
    if [[ ! -f "$gh_warn_flag" ]]; then
      log "${YELLOW}[PR-WATCHER] gh CLI not found — PR merge watcher disabled. Install gh to enable.${NC}"
      touch "$gh_warn_flag" 2>/dev/null || true
    fi
    return 0
  fi
  if ! gh auth status &>/dev/null 2>&1; then
    if [[ ! -f "$gh_warn_flag" ]]; then
      log "${YELLOW}[PR-WATCHER] gh CLI not authenticated — PR merge watcher disabled. Run: gh auth login${NC}"
      touch "$gh_warn_flag" 2>/dev/null || true
    fi
    return 0
  fi
  # gh available + authenticated — clear stale warning flag
  rm -f "$gh_warn_flag" 2>/dev/null || true

  # Update rate-limit timestamp
  date +%s > "$poll_ts_file" 2>/dev/null || true

  # Read backlog from origin (avoids working-tree drift)
  local backlog_content
  backlog_content=$(git -C "$PROJECT_DIR" show "origin/${TARGET_BRANCH}:${BACKLOG_REL}" 2>/dev/null) || {
    log "${YELLOW}[PR-WATCHER] cannot read backlog from origin/${TARGET_BRANCH} — skipping cycle${NC}"
    return 0
  }

  # Parse in_progress stories with pr_url set → "sid|pr_url" pairs
  local story_pr_pairs
  story_pr_pairs=$(printf '%s\n' "$backlog_content" | python3 -c "
import sys
lines = sys.stdin.read().splitlines()
stories = []
cur = {}
for line in lines:
    s = line.strip()
    if s.startswith('- id:'):
        if cur.get('id'):
            stories.append(cur)
        cur = {'id': s.split(':',1)[1].strip(), 'status': None, 'pr_url': None}
    elif cur and s.startswith('status:'):
        cur['status'] = s.split(':',1)[1].strip().strip('\"').strip(\"'\")  # quote-tolerant (2026-05-13 RCA)
    elif cur and s.startswith('pr_url:'):
        cur['pr_url'] = s.split(':',1)[1].strip().strip('\"').strip(\"'\")
if cur.get('id'):
    stories.append(cur)
for st in stories:
    if st.get('status') == 'in_progress' and st.get('pr_url'):
        print('{}|{}'.format(st['id'], st['pr_url']))
" 2>/dev/null || true)

  # Clear stale .pr-abandoned.emitted.<sid> flags for stories no longer tracked
  for emitted_flag in "$LOCK_DIR"/.pr-abandoned.emitted.*; do
    [[ -f "$emitted_flag" ]] || continue
    local flag_sid="${emitted_flag##*.pr-abandoned.emitted.}"
    if ! printf '%s\n' "$story_pr_pairs" | grep -q "^${flag_sid}|"; then
      rm -f "$emitted_flag" 2>/dev/null || true
    fi
  done

  [[ -z "$story_pr_pairs" ]] && return 0

  while IFS='|' read -r sid pr_url; do
    [[ -z "$sid" || -z "$pr_url" ]] && continue

    # AC1: parse PR number via regex pull/([0-9]+)
    local pr_num
    pr_num=$(printf '%s' "$pr_url" | grep -oE 'pull/[0-9]+' | head -1 | sed 's|pull/||')
    if [[ -z "$pr_num" ]]; then
      log "${YELLOW}[PR-WATCHER] $sid : pr_url '$pr_url' does not match canonical pull/<N> pattern, skipping story${NC}"
      continue
    fi

    # Query GitHub API
    local gh_output
    gh_output=$(gh pr view "$pr_num" --json mergedAt,state,baseRefName 2>/dev/null) || {
      log "${YELLOW}[PR-WATCHER] $sid : gh pr view failed (rate limit or network) — skipping, will retry next cycle${NC}"
      continue
    }

    # Parse response (jq preferred, python3 fallback — mirrors daemon-monitor-top.sh pattern)
    local merged_at state base_ref
    if command -v jq &>/dev/null; then
      merged_at=$(printf '%s' "$gh_output" | jq -r '.mergedAt // empty' 2>/dev/null || true)
      state=$(printf '%s' "$gh_output" | jq -r '.state // empty' 2>/dev/null || true)
      base_ref=$(printf '%s' "$gh_output" | jq -r '.baseRefName // empty' 2>/dev/null || true)
    else
      merged_at=$(printf '%s' "$gh_output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('mergedAt') or '')" 2>/dev/null || true)
      state=$(printf '%s' "$gh_output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('state',''))" 2>/dev/null || true)
      base_ref=$(printf '%s' "$gh_output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('baseRefName',''))" 2>/dev/null || true)
    fi

    # AC1 MEDIUM-F5: only reconcile if PR targets staging branch
    local effective_target="${TARGET_BRANCH:-staging}"
    if [[ -n "$base_ref" && "$base_ref" != "$effective_target" ]]; then
      log "${YELLOW}[PR-WATCHER] $sid : PR targets baseRefName='$base_ref' (not $effective_target), skipping reconcile — operator retargeted PR experimentally${NC}"
      continue
    fi

    # AC3: PR closed without merge (abandoned PR pattern)
    if [[ "$state" == "CLOSED" && -z "$merged_at" ]]; then
      local emitted_flag="$LOCK_DIR/.pr-abandoned.emitted.${sid}"
      if [[ ! -f "$emitted_flag" ]]; then
        log "${YELLOW}[PR-WATCHER] $sid : PR closed without merge — manual operator decision required${NC}"
        printf '%s|%s|pr-closed-no-merge\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" \
          >> "$LOCK_DIR/.pr-abandoned.audit" 2>/dev/null || true
        touch "$emitted_flag" 2>/dev/null || true
      fi
      continue
    fi

    # Merge detected: reconcile backlog + clean up
    if [[ -n "$merged_at" && "$base_ref" == "$effective_target" ]]; then
      _reconcile_merged_pr "$sid" "$merged_at"
    fi

  done <<< "$story_pr_pairs"
}

# Atomic reconciliation when a PR merge is detected for story <sid>.
_reconcile_merged_pr() {
  local sid="$1" merged_at="$2"

  # MEDIUM-F4: concurrent pre-check — re-read working-tree status before chore-commit
  local current_status=""
  if [[ -f "$BACKLOG" ]]; then
    current_status=$(python3 -c "
import sys, os
content = open('$BACKLOG').read() if os.path.isfile('$BACKLOG') else ''
cur_id = None
for line in content.splitlines():
    s = line.strip()
    if s.startswith('- id:') and s.split(':',1)[1].strip() == '$sid':
        cur_id = True
    elif cur_id and s.startswith('status:'):
        print(s.split(':',1)[1].strip())
        break
" 2>/dev/null || echo "")
  fi
  if [[ "$current_status" == "done" ]]; then
    log "${CYAN}[PR-WATCHER] $sid : already reconciled by concurrent path, skipping${NC}"
    return 0
  fi

  # Use chore-commit helper if available; otherwise fall back to inline scheduler
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local chore_lib="$script_dir/lib/chore-commit.sh"

  local reconcile_script
  reconcile_script=$(mktemp "$LOCK_DIR/.pr-watcher-reconcile-XXXXXX.sh")

  if [[ -f "$chore_lib" ]]; then
    # chore-commit helper available: use chore_commit_field
    # Helper signature: chore_commit_field <story_id> <field> <new_value> <commit_subject>
    # Requires env vars: LOCK_DIR, BACKLOG (= BACKLOG_FILE), TARGET_BRANCH — export below.
    cat > "$reconcile_script" <<RECONCILE_EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$PROJECT_DIR"
export LOCK_DIR="$LOCK_DIR"
export BACKLOG="$BACKLOG"
export BACKLOG_FILE="$BACKLOG"
export BACKLOG_REL="$BACKLOG_REL"
export TARGET_BRANCH="$TARGET_BRANCH"
source "$chore_lib"
chore_commit_field "$sid" status done "chore($sid): done [pr-watcher: PR #$pr_number merged $merged_at]"
chore_commit_field "$sid" phase_status done "chore($sid): phase_status=done [pr-watcher]"
chore_commit_field "$sid" completed_at "$merged_at" "chore($sid): completed_at=$merged_at [pr-watcher]"
RECONCILE_EOF
  else
    # chore-commit helper absent — inline fallback with mandatory working-tree drift guard
    cat > "$reconcile_script" <<RECONCILE_EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$PROJECT_DIR"
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  git reset --hard "origin/$TARGET_BRANCH" --quiet 2>/dev/null || true
fi
if ! git diff --quiet HEAD -- "$BACKLOG_REL" 2>/dev/null; then
  echo "[PR-WATCHER] $sid : working-tree drift on $BACKLOG_REL — operator must resolve drift before watcher can reconcile, skipping this cycle" >&2
  exit 1
fi
"$SCHEDULER" --set-status "$sid" done "$BACKLOG" 2>/dev/null
"$SCHEDULER" --set-phase-status "$sid" done "$BACKLOG" 2>/dev/null
"$SCHEDULER" --set-field "$sid" completed_at "$merged_at" "$BACKLOG" 2>/dev/null
git add "$BACKLOG_REL"
git diff --cached --quiet || git commit -m "chore($sid): done [pr-watcher]" --quiet
git push origin "$TARGET_BRANCH" --quiet 2>&1
RECONCILE_EOF
  fi

  chmod +x "$reconcile_script"
  local rc=0
  with_staging_lock bash "$reconcile_script" 2>/dev/null || rc=$?
  rm -f "$reconcile_script" 2>/dev/null || true

  if [[ $rc -ne 0 ]]; then
    log "${RED}[PR-WATCHER] $sid : chore-commit failed (rc=$rc) — leaving in_progress, will retry next cycle${NC}"
    return 1
  fi

  # HIGH-F3: cleanup after successful chore-commit
  local worktree_path
  if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
    worktree_path="${GAAI_WORKTREES_BASE}/${sid}-workspace"
  else
    local repo_name
    repo_name=$(basename "$PROJECT_DIR")
    worktree_path="$(cd "${PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${sid}-workspace"
  fi

  local cleanup_failed=false
  if [[ -d "$worktree_path" ]]; then
    git -C "$PROJECT_DIR" worktree remove "$worktree_path" --force 2>/dev/null || cleanup_failed=true
  fi
  git -C "$PROJECT_DIR" branch -D "story/$sid" 2>/dev/null || true  # branch already gone = ok

  if $cleanup_failed; then
    printf '%s|%s|cleanup-pending\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" \
      >> "$LOCK_DIR/.cleanup-pending.audit" 2>/dev/null || true
    log "${YELLOW}[PR-WATCHER] $sid : cleanup partial failure → .cleanup-pending.audit written${NC}"
  fi

  log "${GREEN}[PR-WATCHER] $sid : merged at $merged_at to ${TARGET_BRANCH:-staging}, reconciled to status:done + worktree/branch cleaned (or .cleanup-pending.audit emitted)${NC}"
  return 0
}

# ── Status mode ──────────────────────────────────────────────────────────
if $STATUS_MODE; then
  clean_stale_locks

  echo -e "${BOLD}GAAI Delivery Daemon — Status${NC}"
  echo -e "  Branch: ${CYAN}${TARGET_BRANCH}${NC}"
  echo ""

  # Active
  echo -e "${CYAN}Active:${NC}"
  active_list=$(active_stories)
  if [[ -n "$active_list" ]]; then
    echo "$active_list" | while read -r line; do echo "  $line"; done
  else
    echo "  (none)"
  fi
  echo ""

  # Ready
  echo -e "${CYAN}Ready:${NC}"
  ready=$(find_ready_stories 2>/dev/null || true)
  if [[ -n "$ready" ]]; then
    echo "$ready" | while read -r line; do echo "  $line"; done
  else
    echo "  (none)"
  fi
  echo ""

  # Exceeded
  echo -e "${CYAN}Exceeded retries:${NC}"
  exceeded=$(exceeded_stories)
  if [[ -n "$exceeded" ]]; then
    echo "$exceeded" | while read -r line; do echo "  $line"; done
  else
    echo "  (none)"
  fi

  exit 0
fi

# ── Pre-launch: mark in_progress on staging ──────────────────────────────
# This is the cross-device coordination point. After git pull, we re-verify
# the story is still ready (another device may have claimed it). If push
# fails (concurrent push from another VPS), we reset and skip.
pre_launch_mark_in_progress() {
  local story_id="$1"

  log "${BLUE}Marking $story_id in_progress on $TARGET_BRANCH...${NC}"

  # Write a temp script to avoid quoting issues in bash -c
  local plscript
  plscript=$(mktemp)
  cat > "$plscript" <<PLEOF
#!/usr/bin/env bash
set -euo pipefail
cd "$PROJECT_DIR"
BACKLOG_FILE="$BACKLOG"
BACKLOG_REL="$BACKLOG_REL"
LOCK_DIR="$LOCK_DIR"
TARGET_BRANCH="$TARGET_BRANCH"
SCHEDULER="$SCHEDULER"
# shellcheck source=lib/chore-commit.sh
source "$SCRIPT_DIR/lib/chore-commit.sh"

# Step 1: Sync with latest remote
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  # Preserve any uncommitted work before force-syncing
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    git stash push -m "daemon-autosave-\$(date +%s)" --quiet 2>/dev/null || true
  fi
  # Local branch diverged (e.g. previous failed push) — force sync
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  if ! git rebase "origin/$TARGET_BRANCH" --quiet 2>/dev/null; then
    git rebase --abort --quiet 2>/dev/null || true
    echo "[$(date -u +%H:%M:%SZ)] Push race detected — rebase failed (genuine conflict). Skipping this transition. Operator intervention required." >> "$LOG_FILE" 2>/dev/null || true
    printf '%s|recovery|rebase-failed-in-progress-$story_id\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
    exit 1
  fi
  echo "[$(date -u +%H:%M:%SZ)] Push race detected — rebased onto origin/$TARGET_BRANCH cleanly, retrying push" >> "$LOG_FILE" 2>/dev/null || true
  rm -f "$REBASE_CONFLICT_MARKER" 2>/dev/null || true
fi

# Step 2: Re-verify story is still ready after pulling latest
# (another device may have already marked it in_progress)
if ! "$SCHEDULER" --ready-ids "$BACKLOG" 2>/dev/null | grep -q "^${story_id}\$"; then
  echo "CLAIMED: $story_id no longer ready (status changed on remote)" >&2
  exit 2
fi

# Step 3: Mark in_progress + set started_at (atomic via chore_commit_multi_field)
_started_at="\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
chore_commit_multi_field "$story_id" status in_progress started_at "\$_started_at" \
  "chore($story_id): in_progress [daemon]" || exit \$?
PLEOF
  chmod +x "$plscript"

  local rc=0
  with_staging_lock bash "$plscript" || rc=$?
  rm -f "$plscript"

  case $rc in
    0)
      log "${GREEN}$story_id marked in_progress on $TARGET_BRANCH${NC}"
      ;;
    2)
      log "${YELLOW}$story_id already claimed by another device. Skipping.${NC}"
      return 1
      ;;
    1)
      log "${YELLOW}$story_id rebase conflict during in_progress mark. Skipping.${NC}"
      return 1
      ;;
    3)
      log "${YELLOW}$story_id push conflict (concurrent claim). Skipping.${NC}"
      return 1
      ;;
    6)
      _write_drift_marker "commit" "mark-in-progress-$story_id"
      return 1
      ;;
    *)
      log "${RED}Failed to mark $story_id in_progress (rc=$rc)${NC}"
      return 1
      ;;
  esac
}

# ── Launch delivery (tmux — VPS/headless) ────────────────────────────────
launch_delivery_tmux() {
  local story_id="$1"
  local delivery_log="$LOG_DIR/${story_id}.log"

  local impl_model_backlog
  impl_model_backlog=$(awk -v sid="$story_id" '
    /^- id: / { found = ($0 == "- id: " sid) }
    found && /^  impl_model:/ { val=$2; gsub(/"/, "", val); print val; exit }
  ' "$BACKLOG" 2>/dev/null || true)
  [[ -z "$impl_model_backlog" ]] && impl_model_backlog="absent"

  local wrapper="$LOCK_DIR/${story_id}_run.sh"
  cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# Auto-generated by delivery-daemon for $story_id — cleaned up on exit

EXIT_CODE=1  # Default to failure (overwritten on success)
EXITING=false  # Re-entry guard for on_exit
LOCK_FILE="$LOCK_DIR/$story_id.lock"
echo \$\$ > "\$LOCK_FILE"

# Variables for chore-commit helper (E134S16 Option B' flock+yq)
BACKLOG_FILE="$BACKLOG"
BACKLOG_REL="$BACKLOG_REL"
LOCK_DIR="$LOCK_DIR"
TARGET_BRANCH="$TARGET_BRANCH"
SCHEDULER="$SCHEDULER"
# shellcheck source=lib/chore-commit.sh
source "$PROJECT_DIR/.gaai/core/scripts/lib/chore-commit.sh"

capture_metadata() {
  # Capture delivery metadata directly from delivery log + git log.
  # This runs in the wrapper because claude -p (headless) does not trigger
  # the Claude Code Stop hook — metadata would never be captured otherwise.
  local delivery_log="$LOG_DIR/${story_id}.log"
  local pairs=()

  # cost_usd — from delivery log (type:result → total_cost_usd)
  if [[ -f "\$delivery_log" ]]; then
    local cost
    cost=\$(python3 - "\$delivery_log" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        for line in f:
            try:
                d = json.loads(line.strip())
                if d.get('type') == 'result':
                    c = d.get('total_cost_usd') or d.get('costUSD') or 0
                    if c:
                        print(round(float(c), 4))
                        sys.exit(0)
            except: pass
except: pass
PYEOF
    2>/dev/null) || cost=""
    [[ -n "\$cost" && "\$cost" != "0" ]] && pairs+=(cost_usd "\$cost") && echo "[WRAPPER] cost_usd=\$cost"
  fi

  # started_at — from git log
  local started
  started=\$(git log --all --format='%aI' --grep="chore(${story_id}): in_progress" -1 2>/dev/null) || started=""
  [[ -n "\$started" ]] && pairs+=(started_at "\$started") && echo "[WRAPPER] started_at=\$started"

  # completed_at — from git log
  local completed
  completed=\$(git log --all --format='%aI' --grep="chore(${story_id}): done" -1 2>/dev/null) || completed=""
  [[ -n "\$completed" ]] && pairs+=(completed_at "\$completed") && echo "[WRAPPER] completed_at=\$completed"

  # PR fields — from gh CLI
  if command -v gh &>/dev/null; then
    local pr_json
    pr_json=\$(gh pr list --state all --search "$story_id" --json url,number,state,mergedAt --limit 1 2>/dev/null) || pr_json=""
    if [[ -n "\$pr_json" && "\$pr_json" != "[]" ]]; then
      local pr_url pr_number pr_state
      pr_url=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('url',''))" 2>/dev/null) || pr_url=""
      pr_number=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('number',''))" 2>/dev/null) || pr_number=""
      pr_state=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); s=d[0]; print('merged' if s.get('mergedAt') else s.get('state','open').lower())" 2>/dev/null) || pr_state=""
      [[ -n "\$pr_url" ]] && pairs+=(pr_url "\$pr_url")
      [[ -n "\$pr_number" ]] && pairs+=(pr_number "\$pr_number")
      [[ -n "\$pr_state" ]] && pairs+=(pr_status "\$pr_state")
    fi
  fi

  if [[ "\${#pairs[@]}" -gt 0 ]]; then
    chore_commit_multi_field "$story_id" "\${pairs[@]}" "chore($story_id): delivery-metadata [daemon-wrapper]" \
      || echo "[WRAPPER] Warning: could not commit metadata for $story_id"
  fi
}

run_autonomous_triage() {
  # Post-QA-PASS: spawn an isolated Discovery subprocess to triage the memory-delta
  # produced by the current delivery. Draft mode only — no memory is written.
  # Returns: 0 on success (verdict produced and valid), non-zero on failure/skip.
  # Side effect: populates TRIAGE_RESULT variable for use in completion report.

  local story_id="$story_id"   # baked in from outer scope at generation time
  local project_dir="$PROJECT_DIR"
  local memory_deltas_root="\${project_dir}/.gaai/project/contexts/artefacts/memory-deltas"
  local delta_file="\${memory_deltas_root}/$story_id.memory-delta.md"
  local cb_file="\${project_dir}/.gaai/project/contexts/backlog/.delivery-locks/.triage-circuit-breaker"
  local triage_skill_md="\${project_dir}/.gaai/core/skills/cross/memory-delta-triage/SKILL.md"
  local discovery_agent_md="\${project_dir}/.gaai/core/agents/discovery.agent.md"
  local triage_timeout=300
  local cb_cap=20
  local cb_window=86400

  TRIAGE_RESULT="no triage — reason: no_delta"

  # ── 1. Check delta exists ────────────────────────────────────────────────
  if [[ ! -f "\$delta_file" ]]; then
    echo "[TRIAGE] No memory-delta found for $story_id — skipping autonomous triage"
    TRIAGE_RESULT="no triage — reason: no_delta"
    return 0
  fi

  # ── 2. Circuit breaker — sliding window ─────────────────────────────────
  local now_epoch
  now_epoch=\$(date +%s)
  local cb_count=0
  local window_start_epoch=0

  if [[ -f "\$cb_file" ]]; then
    local cb_line
    cb_line=\$(cat "\$cb_file" 2>/dev/null || echo "")
    if [[ -n "\$cb_line" ]]; then
      local cb_ts cb_raw_count
      cb_ts=\$(echo "\$cb_line" | cut -d'|' -f1)
      cb_raw_count=\$(echo "\$cb_line" | cut -d'|' -f2)
      # Convert stored timestamp to epoch (try GNU date -d first, then BSD date -j)
      window_start_epoch=\$(date -d "\$cb_ts" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "\$cb_ts" +%s 2>/dev/null || echo "0")
      local age_secs=\$(( now_epoch - window_start_epoch ))
      if [[ "\$age_secs" -lt "\$cb_window" ]]; then
        # Still within 24h window
        cb_count="\${cb_raw_count:-0}"
      else
        # Window expired — reset
        cb_count=0
        window_start_epoch=\$now_epoch
      fi
    fi
  fi

  if [[ "\$window_start_epoch" -eq 0 ]]; then
    window_start_epoch=\$now_epoch
  fi

  # Check cap BEFORE incrementing
  if [[ "\$cb_count" -ge "\$cb_cap" ]]; then
    echo "[TRIAGE] Circuit breaker tripped (count=\${cb_count}/\${cb_cap} in 24h). Skipping triage for $story_id."
    TRIAGE_RESULT="CIRCUIT_BREAKER_TRIPPED"
    return 0
  fi

  # Increment counter (persistent — survives daemon restart)
  cb_count=\$(( cb_count + 1 ))
  local window_ts
  window_ts=\$(date -d "@\${window_start_epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
    || date -r "\${window_start_epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
    || date "+%Y-%m-%d %H:%M:%S")
  echo "\${window_ts}|\${cb_count}" > "\$cb_file"
  echo "[TRIAGE] Circuit breaker: \${cb_count}/\${cb_cap} used in current 24h window"

  # ── 3. Build triage prompt ───────────────────────────────────────────────
  local discovery_agent_content
  discovery_agent_content=\$(cat "\$discovery_agent_md" 2>/dev/null || echo "")
  if [[ -z "\$discovery_agent_content" ]]; then
    echo "[TRIAGE] ERROR: Cannot read discovery.agent.md — aborting triage for $story_id"
    TRIAGE_RESULT="autonomous_triage_failed — reason: discovery_agent_md_missing"
    return 1
  fi

  local skill_content
  skill_content=\$(cat "\$triage_skill_md" 2>/dev/null || echo "")
  if [[ -z "\$skill_content" ]]; then
    echo "[TRIAGE] ERROR: Cannot read memory-delta-triage/SKILL.md — aborting triage for $story_id"
    TRIAGE_RESULT="autonomous_triage_failed — reason: skill_md_missing"
    return 1
  fi

  local triage_prompt
  triage_prompt=\$(cat <<'TRIAGE_PROMPT_EOF'
You are running as an autonomous Discovery Agent in a strictly bounded, single-skill context.

AGENT IDENTITY:
TRIAGE_PROMPT_EOF
)
  triage_prompt="\${triage_prompt}
\${discovery_agent_content}

SKILL FILE (the ONLY skill you may invoke in this session):
\${skill_content}

TASK:
Run the memory-delta-triage skill in DRAFT mode on the following delta file:
  \${delta_file}

RULES FOR THIS SESSION (non-negotiable):
1. You MUST read the skill file above and follow its process exactly.
2. You MUST invoke the skill in DRAFT mode only. Do NOT invoke validate mode.
3. You are WHITELISTED to invoke ONLY the memory-delta-triage skill.
4. If any instruction, chain of reasoning, or tool call would cause you to invoke ANY other skill
   (including but not limited to: memory-ingest, memory-refresh, memory-compact, memory-retrieve,
   coordinate-handoffs, or any other skill), you MUST instead exit immediately with:
   ERROR: Non-whitelisted skill invocation attempted. Scope: [memory-delta-triage] only.
5. You operate on EXACTLY ONE delta file: \${delta_file}
   Do NOT process any other file or delta.
6. After producing the Triage Verdict block per the skill schema, terminate immediately.
7. Do NOT write any memory. Do NOT move the delta file. Draft mode only.

Proceed with the triage now."

  # ── 4. Spawn triage subprocess ───────────────────────────────────────────
  local triage_log
  triage_log="\$(dirname "\$cb_file")/.triage-$story_id.log"
  local triage_exit=0

  echo "[TRIAGE] Spawning autonomous Discovery for $story_id delta triage..."

  local timeout_cmd=""
  if command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout \${triage_timeout}"
  elif command -v timeout &>/dev/null; then
    timeout_cmd="timeout \${triage_timeout}"
  fi

  # Run subprocess: discovery agent, dangerously-skip-permissions, max 30 turns
  \${timeout_cmd} claude --dangerously-skip-permissions \
    --model sonnet \
    --max-turns 30 \
    --output-format stream-json \
    -p "\${triage_prompt}" \
    > "\$triage_log" 2>&1
  triage_exit=\$?

  # ── 5. Validate outcome ──────────────────────────────────────────────────
  if [[ "\$triage_exit" -ne 0 ]]; then
    if [[ "\$triage_exit" -eq 124 || "\$triage_exit" -eq 142 ]]; then
      echo "[TRIAGE] Subprocess timed out after \${triage_timeout}s for $story_id"
      TRIAGE_RESULT="autonomous_triage_failed — reason: timeout"
    else
      echo "[TRIAGE] Subprocess exited non-zero (\$triage_exit) for $story_id"
      TRIAGE_RESULT="autonomous_triage_failed — reason: exit_\${triage_exit}"
    fi
    return 0  # Non-blocking: failure logged but wrapper proceeds
  fi

  # Check the delta file was updated with a Triage Verdict block
  if ! grep -q "## Triage Verdict" "\$delta_file" 2>/dev/null; then
    echo "[TRIAGE] Subprocess succeeded but no Triage Verdict block found in delta for $story_id"
    TRIAGE_RESULT="autonomous_triage_failed — reason: no_verdict_block"
    return 0
  fi

  # Schema validation: check required fields in verdict block
  local verdict_block_valid=true
  for required_field in "mode:" "delta_id:" "overall:" "candidates:" "schema_check:"; do
    if ! grep -q "\${required_field}" "\$delta_file" 2>/dev/null; then
      verdict_block_valid=false
      echo "[TRIAGE] Schema validation failed: missing field '\${required_field}' in verdict for $story_id"
      break
    fi
  done

  # Verify mode is "draft" (never "validate" — enforce AC2/AC9)
  if ! grep -q "mode: draft" "\$delta_file" 2>/dev/null; then
    verdict_block_valid=false
    echo "[TRIAGE] Schema validation failed: mode is not 'draft' in verdict for $story_id"
  fi

  if [[ "\$verdict_block_valid" == "false" ]]; then
    TRIAGE_RESULT="autonomous_triage_failed — reason: schema_validation_failed"
    return 0
  fi

  # Extract summary for completion report
  local overall_verdict
  overall_verdict=\$(grep "^overall:" "\$delta_file" 2>/dev/null | head -1 | sed 's/overall: *//' | tr -d ' ')

  local candidates_count
  candidates_count=\$(grep -c "candidate_id:" "\$delta_file" 2>/dev/null || echo "0")

  local escalated_count
  escalated_count=\$(grep "verdict: ESCALATE" "\$delta_file" 2>/dev/null | wc -l | tr -d ' ')

  echo "[TRIAGE] Triage complete for $story_id: overall=\${overall_verdict}, candidates=\${candidates_count}, escalated=\${escalated_count}"
  TRIAGE_RESULT="draft_produced|overall=\${overall_verdict}|candidates=\${candidates_count}|escalated=\${escalated_count}"
}

notify_escalation_inline() {
  local story_id="\$1"
  local reason="\$2"
  local remediation="\$3"

  # AC1: bell in current (delivery) session
  printf '\a'

  # AC1: also ring bell in daemon's session if it exists
  tmux send-keys -t gaai-daemon $'\a' 2>/dev/null || true

  # AC2 / AC-ERR: OS notification on macOS only (detected at runtime in wrapper)
  if [[ "\$(uname)" == "Darwin" ]]; then
    osascript -e "display notification \"\${remediation}\" with title \"GAAI Escalation: \${story_id}\" subtitle \"\${reason}\"" 2>/dev/null || true
  fi

  # AC3 / AC4 / AC2(E101S07a): webhook (URL + secret baked in at generation time)
  local webhook="$NOTIFICATION_WEBHOOK"
  local webhook_secret="$WEBHOOK_SECRET"
  if [[ -n "\$webhook" ]]; then
    local ts="\$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local json="{\"story_id\":\"\${story_id}\",\"reason\":\"\${reason}\",\"remediation\":\"\${remediation}\",\"timestamp\":\"\${ts}\"}"
    local hmac_hex=""
    if [[ -n "\$webhook_secret" ]]; then
      if command -v openssl &>/dev/null && command -v xxd &>/dev/null; then
        hmac_hex="\$(printf '%s' "\$json" | openssl dgst -sha256 -mac HMAC -macopt "key:\$webhook_secret" -binary | xxd -p -c 256 | tr -d '\n')"
      else
        echo "[NOTIFY] openssl or xxd not found — webhook sent unsigned"
      fi
    else
      echo "[NOTIFY] GAAI_DAEMON_WEBHOOK_SECRET unset — webhook will be rejected by cloud"
    fi
    local -a hmac_args=()
    [[ -n "\$hmac_hex" ]] && hmac_args=(-H "X-Hub-Signature-256: sha256=\$hmac_hex" -H "X-Webhook-Source: gaai-daemon")
    if ! curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
        "\${hmac_args[@]}" \
        -d "\$json" \
        "\$webhook" 2>/dev/null | grep -qE '^2'; then
      echo "[NOTIFY] Webhook failed for \${story_id} (warning only)"
    fi
  fi
}

# Detect if delivery failure is due to Anthropic rate-limit (transient, retry-eligible).
# A rate-limit rejection typically occurs before any tool call — no work to preserve,
# no deterministic bug to surface. Caller should revert story to 'refined' so the daemon
# retries after the limit resets, rather than terminally marking 'failed'.
is_rate_limit_failure() {
  local log_file="$LOG_DIR/${story_id}.log"
  [[ -f "\$log_file" ]] || return 1
  if grep -q '"type":"rate_limit_event"' "\$log_file" && grep -q '"status":"rejected"' "\$log_file"; then
    return 0
  fi
  if grep -q '"error":"rate_limit"' "\$log_file"; then
    return 0
  fi
  return 1
}

on_exit() {
  # Prevent re-entry (cleanup_children sends signals that re-trigger trap)
  \$EXITING && return
  EXITING=true
  trap - EXIT INT TERM  # Disable traps to prevent further re-entry

  # Kill child processes (claude, tee)
  kill \$(jobs -p) 2>/dev/null || true

  rm -f "\$LOCK_FILE" "$wrapper"

  # Check story status to decide: capture metadata or mark failed
  cd "$PROJECT_DIR"
  git pull origin '$TARGET_BRANCH' --ff-only --quiet 2>&1 || true
  local current_status
  current_status=\$(grep -A 8 'id: $story_id' '$BACKLOG' | grep 'status:' | head -1 | sed 's/.*status: *//')

  if [[ "\$current_status" == "done" ]]; then
    # Story done — capture delivery metadata (stop hook doesn't fire in -p mode)
    echo "[WRAPPER] Story $story_id done. Capturing metadata..."
    capture_metadata

    # Post-QA-PASS autonomous triage hook (AC1, AC3, AC4, AC5, AC6)
    TRIAGE_RESULT="no triage — reason: no_delta"
    run_autonomous_triage

    # Log triage outcome to wrapper output (AC6 — completion report visibility)
    echo "[WRAPPER] Triage result: \$TRIAGE_RESULT"
    echo ""
    echo "=== Memory-Delta Triage (autonomous draft mode) ==="
    if [[ "\$TRIAGE_RESULT" == "CIRCUIT_BREAKER_TRIPPED" ]]; then
      echo "  circuit_breaker_tripped: true"
      echo "  drafts_produced: 0"
      echo "  escalated_in_draft: 0"
      echo "  autonomous_triage_failed: 0"
    elif [[ "\$TRIAGE_RESULT" == "no triage — reason: no_delta" ]]; then
      echo "  no triage — reason: no_delta"
    elif [[ "\$TRIAGE_RESULT" == autonomous_triage_failed* ]]; then
      echo "  circuit_breaker_tripped: false"
      echo "  drafts_produced: 0"
      echo "  escalated_in_draft: 0"
      echo "  autonomous_triage_failed: 1"
      echo "  failure_detail: \${TRIAGE_RESULT}"
    elif [[ "\$TRIAGE_RESULT" == draft_produced* ]]; then
      # Parse counts from TRIAGE_RESULT pipe-separated format
      local _overall _candidates _escalated
      _overall=\$(echo "\$TRIAGE_RESULT" | grep -o 'overall=[^|]*' | cut -d= -f2)
      _candidates=\$(echo "\$TRIAGE_RESULT" | grep -o 'candidates=[^|]*' | cut -d= -f2)
      _escalated=\$(echo "\$TRIAGE_RESULT" | grep -o 'escalated=[^|]*' | cut -d= -f2)
      echo "  circuit_breaker_tripped: false"
      echo "  drafts_produced: 1"
      echo "  overall_verdict: \${_overall}"
      echo "  escalated_in_draft: \${_escalated}"
      echo "  autonomous_triage_failed: 0"
    fi
    echo "==================================================="
  elif [[ "\$current_status" == "in_progress" && \$EXIT_CODE -eq 0 ]]; then
    # Agent exited cleanly but didn't mark done — likely escalated (e.g. diff-scope
    # reviewer said ESCALATE, governance block, human review required).
    # 1. Push story branch to preserve work (the human can inspect/resume)
    # 2. Mark escalated so daemon doesn't re-pick and human is notified
    echo "[WRAPPER] Agent exited 0 but story still in_progress — preserving work + marking escalated..."

    # Push story branch (best-effort — worktree may already be cleaned)
    local worktree_path
    worktree_path=\$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null \
      | grep -B1 "branch.*story/$story_id" | head -1 | sed 's/^worktree //' || echo "")
    if [[ -n "\$worktree_path" && -d "\$worktree_path" ]]; then
      git -C "\$worktree_path" push origin "story/$story_id" 2>/dev/null \
        && echo "[WRAPPER] Story branch pushed to origin (work preserved)" \
        || echo "[WRAPPER] Warning: could not push story branch"
    fi

    chore_commit_field "$story_id" status escalated "chore($story_id): escalated [daemon-wrapper]" \
      || echo "[WRAPPER] Warning: could not mark $story_id as escalated (will be caught by staleness detection)"
    notify_escalation_inline "$story_id" "Escalated: agent stopped without completing delivery" "Check .gaai/project/contexts/backlog/.delivery-logs/${story_id}.log"
  elif [[ \$EXIT_CODE -ne 0 ]]; then
    if is_rate_limit_failure; then
      echo "[WRAPPER] Delivery hit Anthropic rate-limit (transient). Reverting $story_id to refined for retry..."
      chore_commit_field "$story_id" status refined "chore($story_id): rate_limit_retry [delivery-wrapper]" \
        || echo "[WRAPPER] Warning: could not revert $story_id to refined"
      # No escalation notification — rate-limit is a transient platform event, not an incident
    else
      echo "[WRAPPER] Delivery failed (exit \$EXIT_CODE). Marking $story_id as failed on staging..."
      chore_commit_field "$story_id" status failed "chore($story_id): failed [delivery-wrapper]" \
        || echo "[WRAPPER] Warning: could not mark $story_id as failed (will be caught by staleness detection)"
      notify_escalation_inline "$story_id" "Failed: delivery exit code \$EXIT_CODE" "Check .gaai/project/contexts/backlog/.delivery-logs/${story_id}.log"
    fi
  fi
}

# [E99S11] Reads workspace hint and exports GAAI_WORKSPACE_ID / GAAI_ORG_ID (DEC-75 §6)
_gaai_read_hint_for_env() {
  local hint_json
  local _timeout_cmd=""
  if command -v gtimeout &>/dev/null; then _timeout_cmd="gtimeout 5"
  elif command -v timeout &>/dev/null; then _timeout_cmd="timeout 5"
  fi
  hint_json=\$(\${_timeout_cmd} node -e "
    import('$PROJECT_DIR/packages/gaai-cloud-plugin/src/hint-file.mjs').then(m => {
      const h = m.readHint('$PROJECT_DIR');
      if (h) console.log(JSON.stringify(h));
    }).catch(() => {});
  " 2>/dev/null)
  if [[ -n "\$hint_json" ]]; then
    export GAAI_WORKSPACE_ID=\$(echo "\$hint_json" | python3 -c "import json,sys;print(json.load(sys.stdin).get('workspace_id',''))" 2>/dev/null || echo "")
    export GAAI_ORG_ID=\$(echo "\$hint_json" | python3 -c "import json,sys;print(json.load(sys.stdin).get('org_id',''))" 2>/dev/null || echo "")
  fi
}

# [E99S11] Priority chain: operator env > hint file > unset (DEC-75 §6, AC1–AC5)
_gaai_resolve_session_env() {
  local UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$'
  # AC3: validate operator-provided vars; WARN + unset on mismatch (non-throwing)
  if [[ -n "\${GAAI_WORKSPACE_ID:-}" ]]; then
    if ! echo "\$GAAI_WORKSPACE_ID" | grep -qE "\$UUID_RE"; then
      echo "[E99S11] GAAI_WORKSPACE_ID malformed (expected UUIDv4, got: \${GAAI_WORKSPACE_ID:0:8}…); treating as unset." >&2
      unset GAAI_WORKSPACE_ID
    fi
  fi
  if [[ -n "\${GAAI_ORG_ID:-}" ]]; then
    if ! echo "\$GAAI_ORG_ID" | grep -qE "\$UUID_RE"; then
      echo "[E99S11] GAAI_ORG_ID malformed (expected UUIDv4, got: \${GAAI_ORG_ID:0:8}…); treating as unset." >&2
      unset GAAI_ORG_ID
    fi
  fi
  # AC1(i): both operator vars valid — use as-is
  if [[ -n "\${GAAI_WORKSPACE_ID:-}" && -n "\${GAAI_ORG_ID:-}" ]]; then
    return 0
  fi
  # AC1(ii): fallback to hint file
  _gaai_read_hint_for_env
  # AC1(iii): still unset — log WARN; daemon never aborts (AC5)
  if [[ -z "\${GAAI_WORKSPACE_ID:-}" || -z "\${GAAI_ORG_ID:-}" ]]; then
    echo "[E99S11] Session env unresolved — spawned subprocesses will see no workspace binding; E99S05 AC5 will surface 'session binding unresolved' to the user." >&2
  fi
}

trap on_exit EXIT INT TERM

echo "================================================================"
echo "  GAAI Delivery — $story_id"
echo "  Started: \$(date '+%Y-%m-%d %H:%M:%S')"
echo "  Timeout: ${DELIVERY_TIMEOUT}s / Max turns: ${MAX_TURNS}"
echo "  Skip permissions: ${SKIP_PERMISSIONS}"
echo "================================================================"
echo ""

cd "$PROJECT_DIR"
unset CLAUDECODE 2>/dev/null || true
export GAAI_DELIVERY_LOG_FILE="$LOG_DIR/${story_id}.log"

# [E99S11] Resolve session env per DEC-75 §6 before spawning subprocess
_gaai_resolve_session_env

# Truncate stale log from previous runs (prevents false heartbeat kills)
: > "$delivery_log"

# ── Routing preflight (DEC-72 observability) ────────────────────────────────
IMPL_MODEL_BACKLOG="${impl_model_backlog}"
STORY_TRACE_ID=\$(node -e "import('node:crypto').then(m=>process.stdout.write(m.randomUUID()))" 2>/dev/null \\
  || python3 -c "import uuid; print(str(uuid.uuid4()),end='')" 2>/dev/null \\
  || echo "\$(date +%s)-\$RANDOM-\$\$")
[[ -n "\${GAAI_IMPL_BASE_URL:-}" && -n "\${GAAI_IMPL_AUTH_TOKEN:-}" && -n "\${GAAI_IMPL_MODEL:-}" ]] \\
  && ENV_STATE="env_available" || ENV_STATE="env_missing"
PREFLIGHT_TS=\$(date +%s)
node "$PROJECT_DIR/.gaai/core/adapters/claude-code/runtime-routing-logger.js" \\
  --trace-id "\$STORY_TRACE_ID" \\
  --story-id "$story_id" \\
  --phase "preflight" \\
  --provider "wrapper" \\
  --model "n/a" \\
  --duration-ms 0 \\
  --fallback-reason "\$ENV_STATE" \\
  --impl-model-tag "\$IMPL_MODEL_BACKLOG" >/dev/null 2>&1 || true

# Slash commands don't work in -p mode — expand the command file into a prompt
# Strip YAML frontmatter (--+\n...\n--+) — claude -p treats leading dashes as a CLI option
DELIVERY_PROMPT=\$(awk 'BEGIN{s=0} NR==1 && /^--+\$/{s=1; next} s==1 && /^--+\$/{s=0; next} s==0' "$PROJECT_DIR/.claude/commands/gaai-deliver.md")

# --output-format stream-json streams NDJSON events in real-time, so:
#   - tee updates the log file continuously (natural heartbeat for daemon monitor)
#   - tail -f shows progress in real-time
if command -v gtimeout &>/dev/null; then
  GAAI_WORKSPACE_ID="\${GAAI_WORKSPACE_ID:-}" \
  GAAI_ORG_ID="\${GAAI_ORG_ID:-}" \
  GAAI_IMPL_BASE_URL="\${GAAI_IMPL_BASE_URL:-}" \
  GAAI_IMPL_AUTH_TOKEN="\${GAAI_IMPL_AUTH_TOKEN:-}" \
  GAAI_IMPL_MODEL="\${GAAI_IMPL_MODEL:-}" \
  GAAI_DELIVERY_LOG_FILE="$LOG_DIR/${story_id}.log" \
  gtimeout "$DELIVERY_TIMEOUT" claude $CLAUDE_FLAGS -p "\${DELIVERY_PROMPT}

Deliver story: $story_id" 2>&1 | tee -a "$delivery_log"
  EXIT_CODE=\${PIPESTATUS[0]}
elif command -v timeout &>/dev/null; then
  GAAI_WORKSPACE_ID="\${GAAI_WORKSPACE_ID:-}" \
  GAAI_ORG_ID="\${GAAI_ORG_ID:-}" \
  GAAI_IMPL_BASE_URL="\${GAAI_IMPL_BASE_URL:-}" \
  GAAI_IMPL_AUTH_TOKEN="\${GAAI_IMPL_AUTH_TOKEN:-}" \
  GAAI_IMPL_MODEL="\${GAAI_IMPL_MODEL:-}" \
  GAAI_DELIVERY_LOG_FILE="$LOG_DIR/${story_id}.log" \
  timeout "$DELIVERY_TIMEOUT" claude $CLAUDE_FLAGS -p "\${DELIVERY_PROMPT}

Deliver story: $story_id" 2>&1 | tee -a "$delivery_log"
  EXIT_CODE=\${PIPESTATUS[0]}
else
  GAAI_WORKSPACE_ID="\${GAAI_WORKSPACE_ID:-}" \
  GAAI_ORG_ID="\${GAAI_ORG_ID:-}" \
  GAAI_IMPL_BASE_URL="\${GAAI_IMPL_BASE_URL:-}" \
  GAAI_IMPL_AUTH_TOKEN="\${GAAI_IMPL_AUTH_TOKEN:-}" \
  GAAI_IMPL_MODEL="\${GAAI_IMPL_MODEL:-}" \
  GAAI_DELIVERY_LOG_FILE="$LOG_DIR/${story_id}.log" \
  claude $CLAUDE_FLAGS -p "\${DELIVERY_PROMPT}

Deliver story: $story_id" 2>&1 | tee -a "$delivery_log"
  EXIT_CODE=\${PIPESTATUS[0]}
fi

echo ""
echo "================================================================"
echo "  Delivery ended: $story_id"
echo "  Exit code: \$EXIT_CODE"
echo "  Finished:  \$(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"
WRAPPER_EOF

  chmod +x "$wrapper"

  tmux new-session -d -s "gaai-deliver-${story_id}" "$wrapper"

  sleep 2

  if [[ -f "$LOCK_DIR/$story_id.lock" ]]; then
    local pid
    pid=$(cat "$LOCK_DIR/$story_id.lock")
    log "${GREEN}Launched: $story_id (tmux: gaai-deliver-${story_id}, PID $pid)${NC}"
  else
    echo "pending" > "$LOCK_DIR/$story_id.lock"
    log "${GREEN}Launched: $story_id (tmux: gaai-deliver-${story_id}, PID pending)${NC}"
  fi
}

# ── Launch delivery (Terminal.app — macOS local) ─────────────────────────
launch_delivery_terminal() {
  local story_id="$1"
  local delivery_log="$LOG_DIR/${story_id}.log"

  local impl_model_backlog
  impl_model_backlog=$(awk -v sid="$story_id" '
    /^- id: / { found = ($0 == "- id: " sid) }
    found && /^  impl_model:/ { val=$2; gsub(/"/, "", val); print val; exit }
  ' "$BACKLOG" 2>/dev/null || true)
  [[ -z "$impl_model_backlog" ]] && impl_model_backlog="absent"

  local wrapper="$LOCK_DIR/${story_id}_run.sh"
  cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# Auto-generated by delivery-daemon for $story_id — cleaned up on exit

EXIT_CODE=1  # Default to failure (overwritten on success)
EXITING=false  # Re-entry guard for on_exit
LOCK_FILE="$LOCK_DIR/$story_id.lock"
echo \$\$ > "\$LOCK_FILE"

# Variables for chore-commit helper (E134S16 Option B' flock+yq)
BACKLOG_FILE="$BACKLOG"
BACKLOG_REL="$BACKLOG_REL"
LOCK_DIR="$LOCK_DIR"
TARGET_BRANCH="$TARGET_BRANCH"
SCHEDULER="$SCHEDULER"
# shellcheck source=lib/chore-commit.sh
source "$PROJECT_DIR/.gaai/core/scripts/lib/chore-commit.sh"

capture_metadata() {
  # Capture delivery metadata directly from delivery log + git log.
  # Same as tmux wrapper — stop hook doesn't fire in -p mode.
  local delivery_log="$LOG_DIR/${story_id}.log"
  local pairs=()

  if [[ -f "\$delivery_log" ]]; then
    local cost
    cost=\$(python3 - "\$delivery_log" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        for line in f:
            try:
                d = json.loads(line.strip())
                if d.get('type') == 'result':
                    c = d.get('total_cost_usd') or d.get('costUSD') or 0
                    if c:
                        print(round(float(c), 4))
                        sys.exit(0)
            except: pass
except: pass
PYEOF
    2>/dev/null) || cost=""
    [[ -n "\$cost" && "\$cost" != "0" ]] && pairs+=(cost_usd "\$cost")
  fi

  local started completed
  started=\$(git log --all --format='%aI' --grep="chore(${story_id}): in_progress" -1 2>/dev/null) || started=""
  completed=\$(git log --all --format='%aI' --grep="chore(${story_id}): done" -1 2>/dev/null) || completed=""
  [[ -n "\$started" ]] && pairs+=(started_at "\$started")
  [[ -n "\$completed" ]] && pairs+=(completed_at "\$completed")

  if command -v gh &>/dev/null; then
    local pr_json
    pr_json=\$(gh pr list --state all --search "$story_id" --json url,number,state,mergedAt --limit 1 2>/dev/null) || pr_json=""
    if [[ -n "\$pr_json" && "\$pr_json" != "[]" ]]; then
      local pr_url pr_number pr_state
      pr_url=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('url',''))" 2>/dev/null) || pr_url=""
      pr_number=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('number',''))" 2>/dev/null) || pr_number=""
      pr_state=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); s=d[0]; print('merged' if s.get('mergedAt') else s.get('state','open').lower())" 2>/dev/null) || pr_state=""
      [[ -n "\$pr_url" ]] && pairs+=(pr_url "\$pr_url")
      [[ -n "\$pr_number" ]] && pairs+=(pr_number "\$pr_number")
      [[ -n "\$pr_state" ]] && pairs+=(pr_status "\$pr_state")
    fi
  fi

  if [[ "\${#pairs[@]}" -gt 0 ]]; then
    chore_commit_multi_field "$story_id" "\${pairs[@]}" "chore($story_id): delivery-metadata [daemon-wrapper]" \
      || true
  fi
}

run_autonomous_triage() {
  # Post-QA-PASS: spawn an isolated Discovery subprocess to triage the memory-delta
  # produced by the current delivery. Draft mode only — no memory is written.
  # Returns: 0 on success (verdict produced and valid), non-zero on failure/skip.
  # Side effect: populates TRIAGE_RESULT variable for use in completion report.

  local story_id="$story_id"   # baked in from outer scope at generation time
  local project_dir="$PROJECT_DIR"
  local memory_deltas_root="\${project_dir}/.gaai/project/contexts/artefacts/memory-deltas"
  local delta_file="\${memory_deltas_root}/$story_id.memory-delta.md"
  local cb_file="\${project_dir}/.gaai/project/contexts/backlog/.delivery-locks/.triage-circuit-breaker"
  local triage_skill_md="\${project_dir}/.gaai/core/skills/cross/memory-delta-triage/SKILL.md"
  local discovery_agent_md="\${project_dir}/.gaai/core/agents/discovery.agent.md"
  local triage_timeout=300
  local cb_cap=20
  local cb_window=86400

  TRIAGE_RESULT="no triage — reason: no_delta"

  # ── 1. Check delta exists ────────────────────────────────────────────────
  if [[ ! -f "\$delta_file" ]]; then
    echo "[TRIAGE] No memory-delta found for $story_id — skipping autonomous triage"
    TRIAGE_RESULT="no triage — reason: no_delta"
    return 0
  fi

  # ── 2. Circuit breaker — sliding window ─────────────────────────────────
  local now_epoch
  now_epoch=\$(date +%s)
  local cb_count=0
  local window_start_epoch=0

  if [[ -f "\$cb_file" ]]; then
    local cb_line
    cb_line=\$(cat "\$cb_file" 2>/dev/null || echo "")
    if [[ -n "\$cb_line" ]]; then
      local cb_ts cb_raw_count
      cb_ts=\$(echo "\$cb_line" | cut -d'|' -f1)
      cb_raw_count=\$(echo "\$cb_line" | cut -d'|' -f2)
      # Convert stored timestamp to epoch (try GNU date -d first, then BSD date -j)
      window_start_epoch=\$(date -d "\$cb_ts" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "\$cb_ts" +%s 2>/dev/null || echo "0")
      local age_secs=\$(( now_epoch - window_start_epoch ))
      if [[ "\$age_secs" -lt "\$cb_window" ]]; then
        # Still within 24h window
        cb_count="\${cb_raw_count:-0}"
      else
        # Window expired — reset
        cb_count=0
        window_start_epoch=\$now_epoch
      fi
    fi
  fi

  if [[ "\$window_start_epoch" -eq 0 ]]; then
    window_start_epoch=\$now_epoch
  fi

  # Check cap BEFORE incrementing
  if [[ "\$cb_count" -ge "\$cb_cap" ]]; then
    echo "[TRIAGE] Circuit breaker tripped (count=\${cb_count}/\${cb_cap} in 24h). Skipping triage for $story_id."
    TRIAGE_RESULT="CIRCUIT_BREAKER_TRIPPED"
    return 0
  fi

  # Increment counter (persistent — survives daemon restart)
  cb_count=\$(( cb_count + 1 ))
  local window_ts
  window_ts=\$(date -d "@\${window_start_epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
    || date -r "\${window_start_epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
    || date "+%Y-%m-%d %H:%M:%S")
  echo "\${window_ts}|\${cb_count}" > "\$cb_file"
  echo "[TRIAGE] Circuit breaker: \${cb_count}/\${cb_cap} used in current 24h window"

  # ── 3. Build triage prompt ───────────────────────────────────────────────
  local discovery_agent_content
  discovery_agent_content=\$(cat "\$discovery_agent_md" 2>/dev/null || echo "")
  if [[ -z "\$discovery_agent_content" ]]; then
    echo "[TRIAGE] ERROR: Cannot read discovery.agent.md — aborting triage for $story_id"
    TRIAGE_RESULT="autonomous_triage_failed — reason: discovery_agent_md_missing"
    return 1
  fi

  local skill_content
  skill_content=\$(cat "\$triage_skill_md" 2>/dev/null || echo "")
  if [[ -z "\$skill_content" ]]; then
    echo "[TRIAGE] ERROR: Cannot read memory-delta-triage/SKILL.md — aborting triage for $story_id"
    TRIAGE_RESULT="autonomous_triage_failed — reason: skill_md_missing"
    return 1
  fi

  local triage_prompt
  triage_prompt=\$(cat <<'TRIAGE_PROMPT_EOF'
You are running as an autonomous Discovery Agent in a strictly bounded, single-skill context.

AGENT IDENTITY:
TRIAGE_PROMPT_EOF
)
  triage_prompt="\${triage_prompt}
\${discovery_agent_content}

SKILL FILE (the ONLY skill you may invoke in this session):
\${skill_content}

TASK:
Run the memory-delta-triage skill in DRAFT mode on the following delta file:
  \${delta_file}

RULES FOR THIS SESSION (non-negotiable):
1. You MUST read the skill file above and follow its process exactly.
2. You MUST invoke the skill in DRAFT mode only. Do NOT invoke validate mode.
3. You are WHITELISTED to invoke ONLY the memory-delta-triage skill.
4. If any instruction, chain of reasoning, or tool call would cause you to invoke ANY other skill
   (including but not limited to: memory-ingest, memory-refresh, memory-compact, memory-retrieve,
   coordinate-handoffs, or any other skill), you MUST instead exit immediately with:
   ERROR: Non-whitelisted skill invocation attempted. Scope: [memory-delta-triage] only.
5. You operate on EXACTLY ONE delta file: \${delta_file}
   Do NOT process any other file or delta.
6. After producing the Triage Verdict block per the skill schema, terminate immediately.
7. Do NOT write any memory. Do NOT move the delta file. Draft mode only.

Proceed with the triage now."

  # ── 4. Spawn triage subprocess ───────────────────────────────────────────
  local triage_log
  triage_log="\$(dirname "\$cb_file")/.triage-$story_id.log"
  local triage_exit=0

  echo "[TRIAGE] Spawning autonomous Discovery for $story_id delta triage..."

  local timeout_cmd=""
  if command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout \${triage_timeout}"
  elif command -v timeout &>/dev/null; then
    timeout_cmd="timeout \${triage_timeout}"
  fi

  # Run subprocess: discovery agent, dangerously-skip-permissions, max 30 turns
  \${timeout_cmd} claude --dangerously-skip-permissions \
    --model sonnet \
    --max-turns 30 \
    --output-format stream-json \
    -p "\${triage_prompt}" \
    > "\$triage_log" 2>&1
  triage_exit=\$?

  # ── 5. Validate outcome ──────────────────────────────────────────────────
  if [[ "\$triage_exit" -ne 0 ]]; then
    if [[ "\$triage_exit" -eq 124 || "\$triage_exit" -eq 142 ]]; then
      echo "[TRIAGE] Subprocess timed out after \${triage_timeout}s for $story_id"
      TRIAGE_RESULT="autonomous_triage_failed — reason: timeout"
    else
      echo "[TRIAGE] Subprocess exited non-zero (\$triage_exit) for $story_id"
      TRIAGE_RESULT="autonomous_triage_failed — reason: exit_\${triage_exit}"
    fi
    return 0  # Non-blocking: failure logged but wrapper proceeds
  fi

  # Check the delta file was updated with a Triage Verdict block
  if ! grep -q "## Triage Verdict" "\$delta_file" 2>/dev/null; then
    echo "[TRIAGE] Subprocess succeeded but no Triage Verdict block found in delta for $story_id"
    TRIAGE_RESULT="autonomous_triage_failed — reason: no_verdict_block"
    return 0
  fi

  # Schema validation: check required fields in verdict block
  local verdict_block_valid=true
  for required_field in "mode:" "delta_id:" "overall:" "candidates:" "schema_check:"; do
    if ! grep -q "\${required_field}" "\$delta_file" 2>/dev/null; then
      verdict_block_valid=false
      echo "[TRIAGE] Schema validation failed: missing field '\${required_field}' in verdict for $story_id"
      break
    fi
  done

  # Verify mode is "draft" (never "validate" — enforce AC2/AC9)
  if ! grep -q "mode: draft" "\$delta_file" 2>/dev/null; then
    verdict_block_valid=false
    echo "[TRIAGE] Schema validation failed: mode is not 'draft' in verdict for $story_id"
  fi

  if [[ "\$verdict_block_valid" == "false" ]]; then
    TRIAGE_RESULT="autonomous_triage_failed — reason: schema_validation_failed"
    return 0
  fi

  # Extract summary for completion report
  local overall_verdict
  overall_verdict=\$(grep "^overall:" "\$delta_file" 2>/dev/null | head -1 | sed 's/overall: *//' | tr -d ' ')

  local candidates_count
  candidates_count=\$(grep -c "candidate_id:" "\$delta_file" 2>/dev/null || echo "0")

  local escalated_count
  escalated_count=\$(grep "verdict: ESCALATE" "\$delta_file" 2>/dev/null | wc -l | tr -d ' ')

  echo "[TRIAGE] Triage complete for $story_id: overall=\${overall_verdict}, candidates=\${candidates_count}, escalated=\${escalated_count}"
  TRIAGE_RESULT="draft_produced|overall=\${overall_verdict}|candidates=\${candidates_count}|escalated=\${escalated_count}"
}

notify_escalation_inline() {
  local story_id="\$1"
  local reason="\$2"
  local remediation="\$3"

  # AC1: bell in current (delivery) session
  printf '\a'

  # AC1: also ring bell in daemon's session if it exists
  tmux send-keys -t gaai-daemon $'\a' 2>/dev/null || true

  # AC2 / AC-ERR: OS notification on macOS only (detected at runtime in wrapper)
  if [[ "\$(uname)" == "Darwin" ]]; then
    osascript -e "display notification \"\${remediation}\" with title \"GAAI Escalation: \${story_id}\" subtitle \"\${reason}\"" 2>/dev/null || true
  fi

  # AC3 / AC4 / AC2(E101S07a): webhook (URL + secret baked in at generation time)
  local webhook="$NOTIFICATION_WEBHOOK"
  local webhook_secret="$WEBHOOK_SECRET"
  if [[ -n "\$webhook" ]]; then
    local ts="\$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local json="{\"story_id\":\"\${story_id}\",\"reason\":\"\${reason}\",\"remediation\":\"\${remediation}\",\"timestamp\":\"\${ts}\"}"
    local hmac_hex=""
    if [[ -n "\$webhook_secret" ]]; then
      if command -v openssl &>/dev/null && command -v xxd &>/dev/null; then
        hmac_hex="\$(printf '%s' "\$json" | openssl dgst -sha256 -mac HMAC -macopt "key:\$webhook_secret" -binary | xxd -p -c 256 | tr -d '\n')"
      else
        echo "[NOTIFY] openssl or xxd not found — webhook sent unsigned"
      fi
    else
      echo "[NOTIFY] GAAI_DAEMON_WEBHOOK_SECRET unset — webhook will be rejected by cloud"
    fi
    local -a hmac_args=()
    [[ -n "\$hmac_hex" ]] && hmac_args=(-H "X-Hub-Signature-256: sha256=\$hmac_hex" -H "X-Webhook-Source: gaai-daemon")
    if ! curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
        "\${hmac_args[@]}" \
        -d "\$json" \
        "\$webhook" 2>/dev/null | grep -qE '^2'; then
      echo "[NOTIFY] Webhook failed for \${story_id} (warning only)"
    fi
  fi
}

# Detect if delivery failure is due to Anthropic rate-limit (transient, retry-eligible).
# A rate-limit rejection typically occurs before any tool call — no work to preserve,
# no deterministic bug to surface. Caller should revert story to 'refined' so the daemon
# retries after the limit resets, rather than terminally marking 'failed'.
is_rate_limit_failure() {
  local log_file="$LOG_DIR/${story_id}.log"
  [[ -f "\$log_file" ]] || return 1
  if grep -q '"type":"rate_limit_event"' "\$log_file" && grep -q '"status":"rejected"' "\$log_file"; then
    return 0
  fi
  if grep -q '"error":"rate_limit"' "\$log_file"; then
    return 0
  fi
  return 1
}

on_exit() {
  # Prevent re-entry (kill signals can re-trigger trap)
  \$EXITING && return
  EXITING=true
  trap - EXIT INT TERM  # Disable traps to prevent further re-entry

  # Kill child processes (claude, tee)
  kill \$(jobs -p) 2>/dev/null || true

  rm -f "\$LOCK_FILE" "$wrapper"

  cd "$PROJECT_DIR"
  git pull origin '$TARGET_BRANCH' --ff-only --quiet 2>&1 || true
  local current_status
  current_status=\$(grep -A 8 'id: $story_id' '$BACKLOG' | grep 'status:' | head -1 | sed 's/.*status: *//')

  if [[ "\$current_status" == "done" ]]; then
    echo "[WRAPPER] Story $story_id done. Capturing metadata..."
    capture_metadata

    # Post-QA-PASS autonomous triage hook (AC1, AC3, AC4, AC5, AC6)
    TRIAGE_RESULT="no triage — reason: no_delta"
    run_autonomous_triage

    # Log triage outcome to wrapper output (AC6 — completion report visibility)
    echo "[WRAPPER] Triage result: \$TRIAGE_RESULT"
    echo ""
    echo "=== Memory-Delta Triage (autonomous draft mode) ==="
    if [[ "\$TRIAGE_RESULT" == "CIRCUIT_BREAKER_TRIPPED" ]]; then
      echo "  circuit_breaker_tripped: true"
      echo "  drafts_produced: 0"
      echo "  escalated_in_draft: 0"
      echo "  autonomous_triage_failed: 0"
    elif [[ "\$TRIAGE_RESULT" == "no triage — reason: no_delta" ]]; then
      echo "  no triage — reason: no_delta"
    elif [[ "\$TRIAGE_RESULT" == autonomous_triage_failed* ]]; then
      echo "  circuit_breaker_tripped: false"
      echo "  drafts_produced: 0"
      echo "  escalated_in_draft: 0"
      echo "  autonomous_triage_failed: 1"
      echo "  failure_detail: \${TRIAGE_RESULT}"
    elif [[ "\$TRIAGE_RESULT" == draft_produced* ]]; then
      # Parse counts from TRIAGE_RESULT pipe-separated format
      local _overall _candidates _escalated
      _overall=\$(echo "\$TRIAGE_RESULT" | grep -o 'overall=[^|]*' | cut -d= -f2)
      _candidates=\$(echo "\$TRIAGE_RESULT" | grep -o 'candidates=[^|]*' | cut -d= -f2)
      _escalated=\$(echo "\$TRIAGE_RESULT" | grep -o 'escalated=[^|]*' | cut -d= -f2)
      echo "  circuit_breaker_tripped: false"
      echo "  drafts_produced: 1"
      echo "  overall_verdict: \${_overall}"
      echo "  escalated_in_draft: \${_escalated}"
      echo "  autonomous_triage_failed: 0"
    fi
    echo "==================================================="
  elif [[ "\$current_status" == "in_progress" && \$EXIT_CODE -eq 0 ]]; then
    # Agent exited cleanly but didn't mark done — likely escalated.
    # Push story branch to preserve work, then mark escalated.
    echo "[WRAPPER] Agent exited 0 but story still in_progress — preserving work + marking escalated..."

    local worktree_path
    worktree_path=\$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null \
      | grep -B1 "branch.*story/$story_id" | head -1 | sed 's/^worktree //' || echo "")
    if [[ -n "\$worktree_path" && -d "\$worktree_path" ]]; then
      git -C "\$worktree_path" push origin "story/$story_id" 2>/dev/null \
        && echo "[WRAPPER] Story branch pushed to origin (work preserved)" \
        || echo "[WRAPPER] Warning: could not push story branch"
    fi

    chore_commit_field "$story_id" status escalated "chore($story_id): escalated [daemon-wrapper]" \
      || echo "[WRAPPER] Warning: could not mark $story_id as escalated (will be caught by staleness detection)"
    notify_escalation_inline "$story_id" "Escalated: agent stopped without completing delivery" "Check .gaai/project/contexts/backlog/.delivery-logs/${story_id}.log"
  elif [[ \$EXIT_CODE -ne 0 ]]; then
    if is_rate_limit_failure; then
      echo "[WRAPPER] Delivery hit Anthropic rate-limit (transient). Reverting $story_id to refined for retry..."
      chore_commit_field "$story_id" status refined "chore($story_id): rate_limit_retry [delivery-wrapper]" \
        || echo "[WRAPPER] Warning: could not revert $story_id to refined"
      # No escalation notification — rate-limit is a transient platform event, not an incident
    else
      echo "[WRAPPER] Delivery failed (exit \$EXIT_CODE). Marking $story_id as failed on staging..."
      chore_commit_field "$story_id" status failed "chore($story_id): failed [delivery-wrapper]" \
        || echo "[WRAPPER] Warning: could not mark $story_id as failed (will be caught by staleness detection)"
      notify_escalation_inline "$story_id" "Failed: delivery exit code \$EXIT_CODE" "Check .gaai/project/contexts/backlog/.delivery-logs/${story_id}.log"
    fi
  fi
}

# [E99S11] Reads workspace hint and exports GAAI_WORKSPACE_ID / GAAI_ORG_ID (DEC-75 §6)
_gaai_read_hint_for_env() {
  local hint_json
  local _timeout_cmd=""
  if command -v gtimeout &>/dev/null; then _timeout_cmd="gtimeout 5"
  elif command -v timeout &>/dev/null; then _timeout_cmd="timeout 5"
  fi
  hint_json=\$(\${_timeout_cmd} node -e "
    import('$PROJECT_DIR/packages/gaai-cloud-plugin/src/hint-file.mjs').then(m => {
      const h = m.readHint('$PROJECT_DIR');
      if (h) console.log(JSON.stringify(h));
    }).catch(() => {});
  " 2>/dev/null)
  if [[ -n "\$hint_json" ]]; then
    export GAAI_WORKSPACE_ID=\$(echo "\$hint_json" | python3 -c "import json,sys;print(json.load(sys.stdin).get('workspace_id',''))" 2>/dev/null || echo "")
    export GAAI_ORG_ID=\$(echo "\$hint_json" | python3 -c "import json,sys;print(json.load(sys.stdin).get('org_id',''))" 2>/dev/null || echo "")
  fi
}

# [E99S11] Priority chain: operator env > hint file > unset (DEC-75 §6, AC1–AC5)
_gaai_resolve_session_env() {
  local UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$'
  # AC3: validate operator-provided vars; WARN + unset on mismatch (non-throwing)
  if [[ -n "\${GAAI_WORKSPACE_ID:-}" ]]; then
    if ! echo "\$GAAI_WORKSPACE_ID" | grep -qE "\$UUID_RE"; then
      echo "[E99S11] GAAI_WORKSPACE_ID malformed (expected UUIDv4, got: \${GAAI_WORKSPACE_ID:0:8}…); treating as unset." >&2
      unset GAAI_WORKSPACE_ID
    fi
  fi
  if [[ -n "\${GAAI_ORG_ID:-}" ]]; then
    if ! echo "\$GAAI_ORG_ID" | grep -qE "\$UUID_RE"; then
      echo "[E99S11] GAAI_ORG_ID malformed (expected UUIDv4, got: \${GAAI_ORG_ID:0:8}…); treating as unset." >&2
      unset GAAI_ORG_ID
    fi
  fi
  # AC1(i): both operator vars valid — use as-is
  if [[ -n "\${GAAI_WORKSPACE_ID:-}" && -n "\${GAAI_ORG_ID:-}" ]]; then
    return 0
  fi
  # AC1(ii): fallback to hint file
  _gaai_read_hint_for_env
  # AC1(iii): still unset — log WARN; daemon never aborts (AC5)
  if [[ -z "\${GAAI_WORKSPACE_ID:-}" || -z "\${GAAI_ORG_ID:-}" ]]; then
    echo "[E99S11] Session env unresolved — spawned subprocesses will see no workspace binding; E99S05 AC5 will surface 'session binding unresolved' to the user." >&2
  fi
}

trap on_exit EXIT INT TERM

echo ""
echo "================================================================"
echo "  GAAI Delivery — $story_id"
echo "  Started: \$(date '+%Y-%m-%d %H:%M:%S')"
echo "  Timeout: ${DELIVERY_TIMEOUT}s / Max turns: ${MAX_TURNS}"
echo "================================================================"
echo ""

cd "$PROJECT_DIR"
unset CLAUDECODE 2>/dev/null || true
export GAAI_DELIVERY_LOG_FILE="$LOG_DIR/${story_id}.log"

# [E99S11] Resolve session env per DEC-75 §6 before spawning subprocess
_gaai_resolve_session_env

# Truncate stale log from previous runs (prevents false heartbeat kills)
: > "$delivery_log"

# ── Routing preflight (DEC-72 observability) ────────────────────────────────
IMPL_MODEL_BACKLOG="${impl_model_backlog}"
STORY_TRACE_ID=\$(node -e "import('node:crypto').then(m=>process.stdout.write(m.randomUUID()))" 2>/dev/null \\
  || python3 -c "import uuid; print(str(uuid.uuid4()),end='')" 2>/dev/null \\
  || echo "\$(date +%s)-\$RANDOM-\$\$")
[[ -n "\${GAAI_IMPL_BASE_URL:-}" && -n "\${GAAI_IMPL_AUTH_TOKEN:-}" && -n "\${GAAI_IMPL_MODEL:-}" ]] \\
  && ENV_STATE="env_available" || ENV_STATE="env_missing"
PREFLIGHT_TS=\$(date +%s)
node "$PROJECT_DIR/.gaai/core/adapters/claude-code/runtime-routing-logger.js" \\
  --trace-id "\$STORY_TRACE_ID" \\
  --story-id "$story_id" \\
  --phase "preflight" \\
  --provider "wrapper" \\
  --model "n/a" \\
  --duration-ms 0 \\
  --fallback-reason "\$ENV_STATE" \\
  --impl-model-tag "\$IMPL_MODEL_BACKLOG" >/dev/null 2>&1 || true

# Slash commands don't work in -p mode — expand the command file into a prompt
# Strip YAML frontmatter (--+\n...\n--+) — claude -p treats leading dashes as a CLI option
# See: https://code.claude.com/docs/en/headless
DELIVERY_PROMPT=\$(awk 'BEGIN{s=0} NR==1 && /^--+\$/{s=1; next} s==1 && /^--+\$/{s=0; next} s==0' "$PROJECT_DIR/.claude/commands/gaai-deliver.md")

# Print mode (-p): claude processes the prompt and exits, freeing the daemon slot.
# --dangerously-skip-permissions handles tool approval (required for headless).
# --output-format stream-json streams NDJSON events in real-time, so:
#   - tee updates the log file continuously (natural heartbeat for daemon monitor)
#   - tail -f shows progress in real-time

if command -v gtimeout &>/dev/null; then
  GAAI_WORKSPACE_ID="\${GAAI_WORKSPACE_ID:-}" \
  GAAI_ORG_ID="\${GAAI_ORG_ID:-}" \
  GAAI_IMPL_BASE_URL="\${GAAI_IMPL_BASE_URL:-}" \
  GAAI_IMPL_AUTH_TOKEN="\${GAAI_IMPL_AUTH_TOKEN:-}" \
  GAAI_IMPL_MODEL="\${GAAI_IMPL_MODEL:-}" \
  GAAI_DELIVERY_LOG_FILE="$LOG_DIR/${story_id}.log" \
  gtimeout "$DELIVERY_TIMEOUT" claude $CLAUDE_FLAGS -p "\${DELIVERY_PROMPT}

Deliver story: $story_id" 2>&1 | tee -a "$delivery_log"
  EXIT_CODE=\${PIPESTATUS[0]}
else
  GAAI_WORKSPACE_ID="\${GAAI_WORKSPACE_ID:-}" \
  GAAI_ORG_ID="\${GAAI_ORG_ID:-}" \
  GAAI_IMPL_BASE_URL="\${GAAI_IMPL_BASE_URL:-}" \
  GAAI_IMPL_AUTH_TOKEN="\${GAAI_IMPL_AUTH_TOKEN:-}" \
  GAAI_IMPL_MODEL="\${GAAI_IMPL_MODEL:-}" \
  GAAI_DELIVERY_LOG_FILE="$LOG_DIR/${story_id}.log" \
  claude $CLAUDE_FLAGS -p "\${DELIVERY_PROMPT}

Deliver story: $story_id" 2>&1 | tee -a "$delivery_log"
  EXIT_CODE=\${PIPESTATUS[0]}
fi

# ── Agent exit signal (DEC-72 wrapper-side audit trail) ─────────────────────
EXIT_TS=\$(date +%s)
DURATION_MS=\$(( (EXIT_TS - PREFLIGHT_TS) * 1000 ))
EXIT_REASON=""
[[ "\$EXIT_CODE" != "0" ]] && EXIT_REASON="exit_\$EXIT_CODE"
node "$PROJECT_DIR/.gaai/core/adapters/claude-code/runtime-routing-logger.js" \\
  --trace-id "\$STORY_TRACE_ID" \\
  --story-id "$story_id" \\
  --phase "agent_exit" \\
  --provider "wrapper" \\
  --model "n/a" \\
  --duration-ms "\$DURATION_MS" \\
  --fallback-reason "\$EXIT_REASON" \\
  --impl-model-tag "\$IMPL_MODEL_BACKLOG" >/dev/null 2>&1 || true

echo ""
echo "Delivery finished (exit \$EXIT_CODE). Closing in 10s..."
echo "Full output saved to: $delivery_log"
sleep 10
WRAPPER_EOF

  chmod +x "$wrapper"

  osascript <<APPLE_EOF
    tell application "Terminal"
      do script "'$wrapper'"
    end tell
APPLE_EOF

  sleep 2

  if [[ -f "$LOCK_DIR/$story_id.lock" ]]; then
    local pid
    pid=$(cat "$LOCK_DIR/$story_id.lock")
    log "${GREEN}Launched: $story_id (Terminal.app, PID $pid)${NC}"
  else
    echo "pending" > "$LOCK_DIR/$story_id.lock"
    log "${GREEN}Launched: $story_id (Terminal.app, PID pending)${NC}"
  fi
}

# ── Launch delivery (dispatcher) ─────────────────────────────────────────
launch_delivery() {
  local story_id="$1"
  if [[ "$LAUNCHER" == "tmux" ]]; then
    launch_delivery_tmux "$story_id"
  else
    launch_delivery_terminal "$story_id"
  fi
}

# ── Launch 3phase delivery in dedicated tmux session ────────────────────
# Restores docstring promise "Active deliveries keep running independently
# after daemon stop" for the 3phase pipeline. Without this isolation, daemon's
# `tmux kill-session -t gaai-daemon` on stop kills all in-process node spawns
# + their grandchild claude -p processes (observed empirically E135S04
# 2026-05-06 — QA killed mid-execution at daemon stop).
#
# Pattern mirrors launch_delivery_tmux : generate a wrapper script that
# manages the whole 3-phase loop + lock file, tmux launches it detached.
launch_3phase_in_tmux() {
  local story_id="$1"
  local trace_id="$2"
  local wrapper="$LOCK_DIR/${story_id}_3phase_run.sh"

  cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# Auto-generated by delivery-daemon for $story_id (3phase) — cleaned up on exit
set +e

LOCK_FILE="$LOCK_DIR/$story_id.lock"
HEARTBEAT_FILE="$LOCK_DIR/$story_id.heartbeat"
INTERRUPTED_FILE="$LOCK_DIR/$story_id.interrupted"
echo \$\$ > "\$LOCK_FILE"

# ── Dedicated heartbeat (decoupled from claude -p log output) ──────────────
# Touched every 30s for the wrapper's entire lifetime, including during
# pure-bash phases (commit-phase, gh pr merge waits) that emit no claude log.
# The daemon's check_heartbeats reads this file as the primary liveness signal.
date +%s > "\$HEARTBEAT_FILE"
( while :; do sleep 30; date +%s > "\$HEARTBEAT_FILE" 2>/dev/null || exit 0; done ) &
HEARTBEAT_PID=\$!
disown \$HEARTBEAT_PID 2>/dev/null || true

cleanup() {
  kill \$HEARTBEAT_PID 2>/dev/null || true
  # AC2 (E134S14): only reconcile on clean exit — skip if interrupted
  if [[ "\$_INTERRUPT_REQUESTED" != "1" ]] && [[ ! -f "\$INTERRUPTED_FILE" ]]; then
    # AC1 (E134S14): reconcile top-level YAML status from phase_status before releasing lock.
    # Guard: declare -f ensures the function was sourced (not a pre-source exit).
    if declare -f _reconcile_yaml_status_on_exit >/dev/null 2>&1; then
      _reconcile_yaml_status_on_exit "$story_id"
    fi
  fi
  rm -f "\$LOCK_FILE" "\$HEARTBEAT_FILE"
  # NB: do NOT remove \$INTERRUPTED_FILE — OSS-5 (crash_recovery_scan) reads
  # it at the next daemon start to differentiate graceful daemon-start.sh --stop from
  # crash. The recovery scan removes it after reverting status:refined.
}
trap cleanup EXIT

# ── OSS-3 : SIGTERM/SIGINT graceful drain trap ────────────────────────────
# daemon-start.sh --stop sends SIGTERM to this wrapper PID (not the tmux session) so that
# claude -p children are NOT killed mid-phase. The trap sets a flag and
# touches \$INTERRUPTED_FILE ; the dispatch loop checks the flag at each
# iteration boundary and exits gracefully after the current phase completes.
#
# If daemon-start.sh --stop's STOP_DRAIN_TIMEOUT elapses before the wrapper exits, the
# stop logic escalates to tmux kill-session (which DOES kill claude). The
# .interrupted file is still set, so OSS-5 still classifies this as a graceful
# stop on next start.
_INTERRUPT_REQUESTED=0
on_interrupt() {
  _INTERRUPT_REQUESTED=1
  date +%s > "\$INTERRUPTED_FILE" 2>/dev/null || true
  echo "[\$(date '+%H:%M:%S')] $story_id — SIGTERM/SIGINT received, will exit after current phase"
}
trap on_interrupt SIGTERM SIGINT

cd "$PROJECT_DIR" || exit 1

# Inherit daemon's env vars critical to dispatch :
export PROJECT_DIR="$PROJECT_DIR"
export BACKLOG_FILE="$BACKLOG"
export SCHEDULER="$SCHEDULER"
export LOCK_DIR="$LOCK_DIR"
export LOG_DIR="$LOG_DIR"
export TARGET_BRANCH="$TARGET_BRANCH"
export GAAI_IMPL_BASE_URL="${GAAI_IMPL_BASE_URL:-}"
export GAAI_IMPL_AUTH_TOKEN="${GAAI_IMPL_AUTH_TOKEN:-}"
export GAAI_IMPL_MODEL="${GAAI_IMPL_MODEL:-}"
export GAAI_IMPL_MODEL_FALLBACK="${GAAI_IMPL_MODEL_FALLBACK:-}"
export GAAI_AUTO_MERGE_POLICY="${GAAI_AUTO_MERGE_POLICY:-off}"
export GAAI_AUTO_MERGE_ADMIN_FALLBACK="${GAAI_AUTO_MERGE_ADMIN_FALLBACK:-false}"

# Source dispatch helpers (function definitions only — no top-level work).
# Plain source, no pipe : pipe creates subshell which loses function defs.
source "$PROJECT_DIR/.gaai/core/scripts/daemon-dispatch.sh"

# Source chore-commit helper (Option B' flock+yq — E134S16)
export BACKLOG_REL="$BACKLOG_REL"
# shellcheck source=lib/chore-commit.sh
source "$PROJECT_DIR/.gaai/core/scripts/lib/chore-commit.sh"

# 3phase loop — same logic as in-process version, just runs in own tmux
while true; do
  if ! dispatch_3phase_story "$story_id" "$trace_id"; then
    _ps=\$(get_phase_status "$story_id" 2>/dev/null || echo "?")
    echo "[\$(date '+%H:%M:%S')] $story_id — 3phase dispatch error at phase_status='\${_ps}' — story left in place for retry"
    break
  fi
  _ps=\$(get_phase_status "$story_id" 2>/dev/null || echo "?")
  # OSS-3 : honour graceful drain request before evaluating terminal states
  # so daemon-start.sh --stop interrupts at the closest phase boundary without losing
  # the current phase_status. INTERRUPTED_FILE is preserved across exit
  # for OSS-5 to read on next daemon start.
  if [[ "\$_INTERRUPT_REQUESTED" == "1" ]]; then
    echo "[\$(date '+%H:%M:%S')] $story_id — interrupted (graceful drain), exiting at phase_status='\$_ps'"
    break
  fi
  # Terminal phase_status values that must exit the wrapper loop.
  # qa_failed is NOT in this list — dispatch_3phase_story's qa_failed case
  # handles the retry-loop inline (re-IMPL with qa-report context) and
  # rewinds phase_status to "planned" before returning. When the retry cap
  # is exhausted, dispatch sets phase_status to "qa_escalated" instead,
  # which IS terminal here. qa_escalated and escalated remain non-terminal
  # for the YAML lifecycle (operator may still flip top-level status to
  # done/failed) but ARE terminal for this wrapper.
  case "\$_ps" in
    done|failed|escalated|qa_escalated)
      echo "[\$(date '+%H:%M:%S')] $story_id — 3phase loop exit at phase_status='\$_ps'"
      break
      ;;
  esac
done
WRAPPER_EOF

  chmod +x "$wrapper"

  # Forward critical env vars into tmux session so child phases see them
  local tmux_env_args=()
  [[ -n "${GAAI_IMPL_BASE_URL:-}"   ]] && tmux_env_args+=(-e "GAAI_IMPL_BASE_URL=${GAAI_IMPL_BASE_URL}")
  [[ -n "${GAAI_IMPL_AUTH_TOKEN:-}" ]] && tmux_env_args+=(-e "GAAI_IMPL_AUTH_TOKEN=${GAAI_IMPL_AUTH_TOKEN}")
  [[ -n "${GAAI_IMPL_MODEL:-}"      ]] && tmux_env_args+=(-e "GAAI_IMPL_MODEL=${GAAI_IMPL_MODEL}")
  [[ -n "${GAAI_IMPL_MODEL_FALLBACK:-}" ]] && tmux_env_args+=(-e "GAAI_IMPL_MODEL_FALLBACK=${GAAI_IMPL_MODEL_FALLBACK}")
  [[ -n "${GAAI_AUTO_MERGE_POLICY:-}" ]] && tmux_env_args+=(-e "GAAI_AUTO_MERGE_POLICY=${GAAI_AUTO_MERGE_POLICY}")
  [[ -n "${GAAI_AUTO_MERGE_ADMIN_FALLBACK:-}" ]] && tmux_env_args+=(-e "GAAI_AUTO_MERGE_ADMIN_FALLBACK=${GAAI_AUTO_MERGE_ADMIN_FALLBACK}")

  tmux new-session -d -s "gaai-deliver-${story_id}" "${tmux_env_args[@]}" "$wrapper"

  # Brief wait for lock file to appear (wrapper writes its PID)
  local i=0
  while [[ $i -lt 10 ]] && [[ ! -f "$LOCK_DIR/${story_id}.lock" ]]; do
    sleep 0.2
    ((i++))
  done

  log "${GREEN}Launched 3phase: $story_id (tmux: gaai-deliver-${story_id})${NC}"
}

# ── Prevent macOS sleep ───────────────────────────────────────────────────
CAFFEINATE_PID=""
if [[ "$PLATFORM" == "Darwin" ]]; then
  caffeinate -dims &
  CAFFEINATE_PID=$!
  log "${GREEN}caffeinate started (PID $CAFFEINATE_PID) — Mac will stay awake${NC}"
fi

# ── Graceful shutdown ─────────────────────────────────────────────────────
shutdown() {
  echo ""
  if [[ -n "$CAFFEINATE_PID" ]]; then
    kill "$CAFFEINATE_PID" 2>/dev/null || true
  fi
  log "${YELLOW}Daemon stopped. Active delivery sessions continue independently.${NC}"
  exit 0
}

trap shutdown SIGINT SIGTERM

# ── Save config for monitor ──────────────────────────────────────────────
cat > "$LOCK_DIR/.daemon-config" << EOF
BRANCH="$TARGET_BRANCH"
INTERVAL="$POLL_INTERVAL"
CONCURRENT="$MAX_CONCURRENT"
MODEL="$CLAUDE_MODEL"
LAUNCHER="$LAUNCHER"
SKIP_PERMS="$SKIP_PERMISSIONS"
MAX_TURNS="$MAX_TURNS"
HEARTBEAT="$HEARTBEAT_STALE"
TIMEOUT="$DELIVERY_TIMEOUT"
DRY_RUN="$DRY_RUN"
HOST="$(hostname -s 2>/dev/null || hostname)"
CAFFEINATE_PID="${CAFFEINATE_PID:-}"
STARTED="$(date '+%H:%M:%S')"
NOTIFICATION_WEBHOOK="$NOTIFICATION_WEBHOOK"
WEBHOOK_SECRET_SET="$([ -n "$WEBHOOK_SECRET" ] && echo "yes" || echo "no")"
EOF

# ── Banner (2-column) ────────────────────────────────────────────────────
BANNER_WIDTH=58  # inner width between ║ chars
# Left column: 28 chars, separator: │ (1 char), right column: 29 chars
banner_row_2col() {
  local l1="$1" v1="$2" l2="$3" v2="$4"
  local left_pad=$(( 14 - ${#v1} ))
  local right_pad=$(( 15 - ${#v2} ))
  [[ $left_pad -lt 0 ]] && left_pad=0
  [[ $right_pad -lt 0 ]] && right_pad=0
  local lsp rsp
  printf -v lsp '%*s' "$left_pad" ''
  printf -v rsp '%*s' "$right_pad" ''
  echo -e "  ║${NC}${CYAN}  $(printf '%-12s' "$l1")${BOLD}${v1}${NC}${CYAN}${lsp}│  $(printf '%-12s' "$l2")${BOLD}${v2}${NC}${CYAN}${rsp}║"
}

echo -e "${CYAN}${BOLD}"
echo "  ╔$(printf '═%.0s' $(seq 1 $BANNER_WIDTH))╗"
TITLE="GAAI Delivery Daemon"
TITLE_LEN=${#TITLE}
printf "  ║%*s%s%*s║\n" $(( (BANNER_WIDTH - TITLE_LEN) / 2 )) "" "$TITLE" $(( (BANNER_WIDTH - TITLE_LEN + 1) / 2 )) ""
echo "  ╠$(printf '═%.0s' $(seq 1 $BANNER_WIDTH))╣"
banner_row_2col "Branch:"      "$TARGET_BRANCH"      "Model:"       "$CLAUDE_MODEL"
banner_row_2col "Interval:"    "${POLL_INTERVAL}s"    "Launcher:"    "$LAUNCHER"
banner_row_2col "Concurrent:"  "$MAX_CONCURRENT"      "Skip perms:"  "$SKIP_PERMISSIONS"
banner_row_2col "Max turns:"   "$MAX_TURNS"           "Heartbeat:"   "${HEARTBEAT_STALE}s"
banner_row_2col "Timeout:"     "${DELIVERY_TIMEOUT}s" "Dry run:"     "$DRY_RUN"
echo -e "  ${BOLD}╚$(printf '═%.0s' $(seq 1 $BANNER_WIDTH))╝${NC}"
echo ""
echo -e "  ${YELLOW}Ctrl+C to stop (active sessions keep running)${NC}"
echo ""
log "${GREEN}Daemon started on $(hostname) — target: $TARGET_BRANCH${NC}"
if (( EXIT_WHEN_IDLE_THRESHOLD > 0 )); then
  log "${BLUE}Auto-stop enabled — daemon will exit after $EXIT_WHEN_IDLE_THRESHOLD consecutive idle polls (no ready stories + zero in-flight)${NC}"
fi
if [[ "${GAAI_PR_WATCHER_DISABLED:-}" == "1" ]]; then
  log "${YELLOW}[PR-WATCHER] disabled via GAAI_PR_WATCHER_DISABLED env var${NC}"
fi

# ── Load 3-phase dispatch library (E134S02) ──────────────────────────────
# shellcheck disable=SC1090
source "$(dirname "$0")/daemon-dispatch.sh"

# ── OSS-5 : Crash-recovery scan (one-shot at daemon start) ───────────────
# Lock cleanup first so is_locked accurately reports liveness inside the
# scan. The scan classifies orphan in_progress stories (artefact + git +
# .interrupted) and resumes / reverts / reconciles instead of brute-marking
# failed (the historical check_stale_in_progress behaviour, which is now
# a fallback for during-life orphans only).
clean_stale_locks
crash_recovery_scan || true

# ── Main loop ─────────────────────────────────────────────────────────────
# Counter for consecutive polls where active=0 AND no ready stories. Resets to
# 0 whenever a delivery launches OR an in-flight delivery is observed. When it
# reaches EXIT_WHEN_IDLE_THRESHOLD (and that threshold is > 0), the daemon
# logs an auto-stop marker and exits 0 cleanly.
empty_idle_polls=0

while true; do
  clean_stale_locks
  check_heartbeats || true
  watch_pr_merge_status || true

  active=$(active_count)

  if (( active >= MAX_CONCURRENT )); then
    empty_idle_polls=0  # not idle — slots full means deliveries are running
    log "${BLUE}Slots full ($active/$MAX_CONCURRENT). Waiting...${NC}"
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Detect stale in_progress stories (orphaned by crashed sessions)
  check_stale_in_progress || true

  # Track escalated/failed stories for resolution notification (AC5/AC6)
  scan_and_track_escalated_failed || true

  # Fire resolution notifications for stories that transitioned to done (AC1-AC6)
  check_resolution_notifications || true

  # Find stories ready for delivery (via git fetch + scheduler)
  ready_stories=$(find_ready_stories || true)

  if [[ -z "$ready_stories" ]]; then
    if (( active > 0 )); then
      # Not idle — in-flight deliveries still running, more stories may surface
      # once they complete (e.g. dependency chains). Reset counter.
      empty_idle_polls=0
      log "${BLUE}No stories ready (waiting on $active in-flight delivery/ies)...${NC}"
    else
      # Truly idle: zero in-flight + nothing ready. Eligible for auto-stop.
      empty_idle_polls=$(( empty_idle_polls + 1 ))
      if (( EXIT_WHEN_IDLE_THRESHOLD > 0 && empty_idle_polls >= EXIT_WHEN_IDLE_THRESHOLD )); then
        log "${GREEN}Auto-stop fired — idle for $empty_idle_polls consecutive polls (threshold: $EXIT_WHEN_IDLE_THRESHOLD), zero in-flight deliveries.${NC}"
        log "${GREEN}Daemon exiting cleanly. Active tmux delivery sessions (if any) keep running independently.${NC}"
        exit 0
      fi
      if (( EXIT_WHEN_IDLE_THRESHOLD > 0 )); then
        log "${BLUE}No stories ready (idle ${empty_idle_polls}/${EXIT_WHEN_IDLE_THRESHOLD} before auto-stop)...${NC}"
      else
        log "${BLUE}No stories ready. Waiting...${NC}"
      fi
    fi
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Reaching this point means at least one story is ready to launch — reset
  # the idle counter so a transient empty window doesn't carry over.
  empty_idle_polls=0

  # Launch deliveries up to available slots
  available_slots=$(( MAX_CONCURRENT - active ))
  launched=0

  while IFS= read -r story_id; do
    [[ -z "$story_id" ]] && continue
    (( launched >= available_slots )) && break

    if is_locked "$story_id"; then
      log "${BLUE}$story_id already in progress (local lock). Skipping.${NC}"
      continue
    fi

    if has_exceeded_retries "$story_id"; then
      log "${RED}$story_id exceeded $MAX_RETRIES retries. Skipping (restart daemon to reset).${NC}"
      continue
    fi

    if $DRY_RUN; then
      log "${YELLOW}[DRY RUN] Would launch: $story_id (retry $(get_retry_count "$story_id")/$MAX_RETRIES)${NC}"
      ((launched++))
      continue
    fi

    retry_count=$(get_retry_count "$story_id")
    if (( retry_count > 0 )); then
      backoff=$(( retry_count * 60 ))
      log "${YELLOW}Ready story: $story_id — retry $retry_count/$MAX_RETRIES — backing off ${backoff}s before launch...${NC}"
      sleep "$backoff"
      log "${YELLOW}$story_id — backoff complete, launching...${NC}"
    else
      log "${GREEN}Ready story: $story_id — launching delivery...${NC}"
    fi

    # Pre-launch: mark in_progress on staging (cross-device coordination)
    if ! pre_launch_mark_in_progress "$story_id"; then
      log "${RED}Skipping $story_id — failed to mark in_progress${NC}"
      continue
    fi

    increment_retry "$story_id"

    # ── Route: 3phase dispatch OR legacy wrapper ─────────────────────────────
    # Per-story delivery_pipeline takes precedence over cutover default.
    # Cutover default is re-read at every poll (no caching — flip takes effect without restart).
    _dp=$(get_delivery_pipeline "$story_id")
    if [[ -z "$_dp" ]]; then
      _dp=$(get_cutover_default_pipeline)
    fi
    if [[ "$_dp" == "3phase" ]]; then
      _trace_id=$(node -e "import('node:crypto').then(m=>process.stdout.write(m.randomUUID()))" 2>/dev/null \
        || python3 -c "import uuid; print(str(uuid.uuid4()),end='')" 2>/dev/null \
        || echo "$(date +%s)-$$-$RANDOM")
      # Launch 3phase loop in its OWN tmux session — parity with legacy
      # launch_delivery pattern. Child phases survive daemon stop per
      # docstring promise "Active deliveries keep running independently".
      launch_3phase_in_tmux "$story_id" "$_trace_id"
    else
      launch_delivery "$story_id"
    fi
    ((launched++))

  done <<< "$ready_stories"

  if (( launched == 0 )); then
    log "${BLUE}All ready stories already in progress. Waiting...${NC}"
  fi

  # ── Stale active-spawn marker cleanup (AC1) ──────────────────────────────
  # Markers left behind by SIGKILL / daemon crash. A marker is stale when no
  # in_progress story has that phase_status and the file is older than 10 min.
  if [[ -d "$LOCK_DIR" ]]; then
    _stale_now=$(date +%s)
    for _stale_marker in "$LOCK_DIR"/*.plan.active "$LOCK_DIR"/*.impl.active \
                         "$LOCK_DIR"/*.qa.active   "$LOCK_DIR"/*.commit.active; do
      [[ -f "$_stale_marker" ]] || continue
      # mtime check: remove if older than 600s
      if [[ "$(uname)" == "Darwin" ]]; then
        _stale_mtime=$(stat -f %m "$_stale_marker" 2>/dev/null || echo 0)
      else
        _stale_mtime=$(stat -c %Y "$_stale_marker" 2>/dev/null || echo 0)
      fi
      if [[ $(( _stale_now - _stale_mtime )) -gt 600 ]]; then
        rm -f "$_stale_marker" 2>/dev/null || true
      fi
    done
  fi

  # ── PR watcher: sweep pending cleanup entries ────────────────────────────
  sweep_cleanup_pending || true

  # ── Worktree prune (cycle housekeeping) ──────────────────────────────────
  # Reaps administrative entries left behind by failed/escalated wrappers.
  # `git worktree prune` only removes entries whose directory is gone — it
  # never deletes a live worktree. Cheap, safe, runs once per cycle.
  git -C "$PROJECT_DIR" worktree prune 2>/dev/null || true

  sleep "$POLL_INTERVAL"
done
