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
#
# Environment overrides:
#   GAAI_POLL_INTERVAL=15            poll every 15s
#   GAAI_MAX_CONCURRENT=2            allow 2 parallel deliveries
#   GAAI_TARGET_BRANCH=staging       target branch (default: staging)
#   GAAI_DELIVERY_TIMEOUT=14400      hard kill timeout in seconds (default: 4h, last resort)
#   GAAI_MAX_TURNS=200               max claude tool-call turns per delivery (primary safety)
#   GAAI_HEARTBEAT_STALE=900         seconds without log output before killing (default: 15min)
#   GAAI_CLAUDE_MODEL=sonnet         claude model to use (default: sonnet)
#   GAAI_STALENESS_THRESHOLD=15000   seconds before orphan in_progress is stale (default: timeout+10min)
#   GAAI_SKIP_PERMISSIONS=true       force --dangerously-skip-permissions
#   GAAI_SKIP_PERMISSIONS=false      force interactive mode (even on VPS)
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
DELIVERY_TIMEOUT="${GAAI_DELIVERY_TIMEOUT:-14400}"   # 4h hard kill (last resort)
MAX_TURNS="${GAAI_MAX_TURNS:-200}"                    # primary safety net
CLAUDE_MODEL="${GAAI_CLAUDE_MODEL:-sonnet}"           # model (sonnet = cost-effective)
HEARTBEAT_STALE="${GAAI_HEARTBEAT_STALE:-1800}"       # 30min no output = stuck (allows long MCP calls like deep research)
STALENESS_THRESHOLD="${GAAI_STALENESS_THRESHOLD:-}"   # auto-computed below
DRY_RUN=false
STATUS_MODE=false

BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="$PROJECT_DIR/$BACKLOG_REL"
SCHEDULER="$SCRIPT_DIR/backlog-scheduler.sh"
LOCK_DIR="$GAAI_PROJECT_DIR/contexts/backlog/.delivery-locks"
LOG_DIR="$GAAI_PROJECT_DIR/contexts/backlog/.delivery-logs"
STAGING_LOCK="$LOCK_DIR/.staging.lock"
RETRY_FILE="$LOCK_DIR/.retry-counts"
RESOLUTION_TRACKING="$LOCK_DIR/.resolution-tracking"
LOG_FILE="$GAAI_PROJECT_DIR/contexts/backlog/.delivery-daemon.log"
MAX_RETRIES=3
NOTIFICATION_WEBHOOK="${GAAI_NOTIFICATION_WEBHOOK:-}"

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

  # AC3 / AC4: webhook POST (best-effort, never blocks daemon)
  if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local json="{\"story_id\":\"${story_id}\",\"reason\":\"${reason}\",\"remediation\":\"${remediation}\",\"timestamp\":\"${ts}\"}"
    if ! curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
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

  # AC3 / AC4: webhook POST (best-effort, never blocks daemon)
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
    if ! curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
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
        status = stripped.split(':', 1)[1].strip()
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
# Claude generates output continuously when working. The tee command in the
# wrapper writes to a per-delivery log file. If the log file hasn't been
# updated in HEARTBEAT_STALE seconds, the session is stuck (event loop
# blocked, network hang, etc.). The daemon sends SIGTERM, then SIGKILL.
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

    # Grace period: skip heartbeat for recently-launched sessions
    # Prevents stale log files from previous runs triggering immediate kills
    local lock_age=$(( now - $(file_mtime "$lock") ))
    if (( lock_age < HEARTBEAT_STALE )); then
      continue
    fi

    # Check delivery log heartbeat
    local logfile="$LOG_DIR/${sid}.log"
    if [[ ! -f "$logfile" ]]; then
      # No log yet — check lock file age instead (session just started?)
      local lock_age=$(( now - $(file_mtime "$lock") ))
      if (( lock_age > HEARTBEAT_STALE )); then
        log "${RED}HEARTBEAT: $sid has no log file after ${lock_age}s — killing PID $pid${NC}"
        kill -TERM "$pid" 2>/dev/null || true
      fi
      continue
    fi

    local log_mtime log_age
    log_mtime=$(file_mtime "$logfile")
    log_age=$(( now - log_mtime ))

    if (( log_age > HEARTBEAT_STALE )); then
      log "${RED}HEARTBEAT: $sid — no output for $(( log_age / 60 ))min — sending SIGTERM to PID $pid${NC}"
      kill -TERM "$pid" 2>/dev/null || true

      # Give 30s for graceful shutdown (wrapper trap → mark failed → cleanup)
      sleep 30

      if kill -0 "$pid" 2>/dev/null; then
        log "${RED}HEARTBEAT: $sid — SIGKILL PID $pid (did not respond to SIGTERM)${NC}"
        kill -KILL "$pid" 2>/dev/null || true
      fi
    fi
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
        status = stripped.split(":", 1)[1].strip()
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
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  # Preserve any uncommitted work before force-syncing
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    git stash push -m "daemon-autosave-$(date +%s)" --quiet 2>/dev/null || true
  fi
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  git reset --hard "origin/$TARGET_BRANCH" --quiet 2>/dev/null
fi
"$SCHEDULER" --set-status "$sid" failed "$BACKLOG"
git add "$BACKLOG_REL"
git commit -m "chore($sid): failed [daemon-staleness]" --quiet
git push origin "$TARGET_BRANCH" --quiet 2>&1
RSTEOF
      chmod +x "$reset_script"
      if with_staging_lock bash "$reset_script" 2>/dev/null; then
        log "${GREEN}$sid marked as failed (stale recovery)${NC}"
        notify_escalation "$sid" "Stale: stuck in_progress for ${age_min}min" "Run: git log --oneline origin/staging | grep $sid — then reset manually or re-refine"
        track_for_resolution "$sid" "failed"
      else
        log "${RED}Could not mark $sid as failed — manual intervention needed${NC}"
      fi
      rm -f "$reset_script"
    fi
  done <<< "$in_progress_ids"
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

# Step 1: Sync with latest remote
if ! git pull origin "$TARGET_BRANCH" --ff-only --quiet 2>&1; then
  # Preserve any uncommitted work before force-syncing
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    git stash push -m "daemon-autosave-$(date +%s)" --quiet 2>/dev/null || true
  fi
  # Local branch diverged (e.g. previous failed push) — force sync
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  git reset --hard "origin/$TARGET_BRANCH" --quiet 2>/dev/null
fi

# Step 2: Re-verify story is still ready after pulling latest
# (another device may have already marked it in_progress)
if ! "$SCHEDULER" --ready-ids "$BACKLOG" 2>/dev/null | grep -q "^${story_id}\$"; then
  echo "CLAIMED: $story_id no longer ready (status changed on remote)" >&2
  exit 2
fi

# Step 3: Mark in_progress locally + set started_at
"$SCHEDULER" --set-status "$story_id" in_progress "$BACKLOG"
"$SCHEDULER" --set-field "$story_id" started_at "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BACKLOG"

# YAML safety check — abort if backlog is corrupted (prevents committing broken YAML)
if ! python3 -c "import yaml; yaml.safe_load(open('$BACKLOG'))" 2>/dev/null; then
  echo "YAML_BROKEN: backlog YAML is invalid after status update — aborting" >&2
  git checkout -- "$BACKLOG_REL" 2>/dev/null || true
  exit 4
fi

git add "$BACKLOG_REL"
git commit -m "chore($story_id): in_progress [daemon]" --quiet

# Step 4: Push — this is the atomic coordination point
# If another VPS pushes between our pull and push, this fails (non-fast-forward)
if ! git push origin "$TARGET_BRANCH" --quiet 2>&1; then
  # Preserve any uncommitted work before force-syncing
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    git stash push -m "daemon-autosave-$(date +%s)" --quiet 2>/dev/null || true
  fi
  # Concurrent push detected — reset local to match remote and abort
  git fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null || true
  git reset --hard "origin/$TARGET_BRANCH" --quiet 2>/dev/null
  echo "PUSH_CONFLICT: concurrent claim on $story_id" >&2
  exit 3
fi
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
    3)
      log "${YELLOW}$story_id push conflict (concurrent claim). Skipping.${NC}"
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

  local wrapper="$LOCK_DIR/${story_id}_run.sh"
  cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# Auto-generated by delivery-daemon for $story_id — cleaned up on exit

EXIT_CODE=1  # Default to failure (overwritten on success)
EXITING=false  # Re-entry guard for on_exit
LOCK_FILE="$LOCK_DIR/$story_id.lock"
echo \$\$ > "\$LOCK_FILE"

capture_metadata() {
  # Capture delivery metadata directly from delivery log + git log.
  # This runs in the wrapper because claude -p (headless) does not trigger
  # the Claude Code Stop hook — metadata would never be captured otherwise.
  local delivery_log="$LOG_DIR/${story_id}.log"
  local fields_updated=0

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
    if [[ -n "\$cost" && "\$cost" != "0" ]]; then
      "$SCHEDULER" --set-field "$story_id" cost_usd "\$cost" "$BACKLOG" 2>/dev/null && {
        fields_updated=1
        echo "[WRAPPER] cost_usd=\$cost"
      }
    fi
  fi

  # started_at — from git log
  local started
  started=\$(git log --all --format='%aI' --grep="chore(${story_id}): in_progress" -1 2>/dev/null) || started=""
  if [[ -n "\$started" ]]; then
    "$SCHEDULER" --set-field "$story_id" started_at "\$started" "$BACKLOG" 2>/dev/null && {
      fields_updated=1
      echo "[WRAPPER] started_at=\$started"
    }
  fi

  # completed_at — from git log
  local completed
  completed=\$(git log --all --format='%aI' --grep="chore(${story_id}): done" -1 2>/dev/null) || completed=""
  if [[ -n "\$completed" ]]; then
    "$SCHEDULER" --set-field "$story_id" completed_at "\$completed" "$BACKLOG" 2>/dev/null && {
      fields_updated=1
      echo "[WRAPPER] completed_at=\$completed"
    }
  fi

  # PR fields — from gh CLI
  if command -v gh &>/dev/null; then
    local pr_json
    pr_json=\$(gh pr list --state all --search "$story_id" --json url,number,state,mergedAt --limit 1 2>/dev/null) || pr_json=""
    if [[ -n "\$pr_json" && "\$pr_json" != "[]" ]]; then
      local pr_url pr_number pr_state
      pr_url=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('url',''))" 2>/dev/null) || pr_url=""
      pr_number=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('number',''))" 2>/dev/null) || pr_number=""
      pr_state=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); s=d[0]; print('merged' if s.get('mergedAt') else s.get('state','open').lower())" 2>/dev/null) || pr_state=""
      [[ -n "\$pr_url" ]] && "$SCHEDULER" --set-field "$story_id" pr_url "\$pr_url" "$BACKLOG" 2>/dev/null && fields_updated=1
      [[ -n "\$pr_number" ]] && "$SCHEDULER" --set-field "$story_id" pr_number "\$pr_number" "$BACKLOG" 2>/dev/null && fields_updated=1
      [[ -n "\$pr_state" ]] && "$SCHEDULER" --set-field "$story_id" pr_status "\$pr_state" "$BACKLOG" 2>/dev/null && fields_updated=1
    fi
  fi

  # Commit + push if any field was updated
  if [[ "\$fields_updated" -eq 1 ]]; then
    (
      git add "$BACKLOG_REL" 2>/dev/null || exit 1
      git diff --cached --quiet 2>/dev/null && exit 0
      git commit -m "chore($story_id): delivery-metadata [daemon-wrapper]" --quiet 2>/dev/null || exit 1
      git push origin '$TARGET_BRANCH' --quiet 2>/dev/null || true
      echo "[WRAPPER] delivery metadata committed for $story_id"
    ) || echo "[WRAPPER] Warning: could not commit metadata for $story_id"
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

  # AC3 / AC4: webhook (URL baked in at generation time from NOTIFICATION_WEBHOOK)
  local webhook="$NOTIFICATION_WEBHOOK"
  if [[ -n "\$webhook" ]]; then
    local ts="\$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local json="{\"story_id\":\"\${story_id}\",\"reason\":\"\${reason}\",\"remediation\":\"\${remediation}\",\"timestamp\":\"\${ts}\"}"
    if ! curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
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

    (
      if command -v flock &>/dev/null; then
        flock "$STAGING_LOCK" bash -c "
          '$SCHEDULER' --set-status '$story_id' escalated '$BACKLOG' 2>/dev/null || true
          git add '$BACKLOG_REL' 2>/dev/null
          git commit -m 'chore($story_id): escalated [daemon-wrapper]' --quiet 2>/dev/null
          git push origin '$TARGET_BRANCH' --quiet 2>&1
        "
      else
        '$SCHEDULER' --set-status '$story_id' escalated '$BACKLOG' 2>/dev/null || true
        git add '$BACKLOG_REL' 2>/dev/null
        git commit -m 'chore($story_id): escalated [daemon-wrapper]' --quiet 2>/dev/null
        git push origin '$TARGET_BRANCH' --quiet 2>&1 || true
      fi
    ) || echo "[WRAPPER] Warning: could not mark $story_id as escalated (will be caught by staleness detection)"
    notify_escalation_inline "$story_id" "Escalated: agent stopped without completing delivery" "Check .gaai/project/contexts/backlog/.delivery-logs/${story_id}.log"
  elif [[ \$EXIT_CODE -ne 0 ]]; then
    if is_rate_limit_failure; then
      echo "[WRAPPER] Delivery hit Anthropic rate-limit (transient). Reverting $story_id to refined for retry..."
      (
        if command -v flock &>/dev/null; then
          flock "$STAGING_LOCK" bash -c "
            '$SCHEDULER' --set-status '$story_id' refined '$BACKLOG' 2>/dev/null || true
            git add '$BACKLOG_REL' 2>/dev/null
            git commit -m 'chore($story_id): rate_limit_retry [delivery-wrapper]' --quiet 2>/dev/null
            git push origin '$TARGET_BRANCH' --quiet 2>&1
          "
        else
          '$SCHEDULER' --set-status '$story_id' refined '$BACKLOG' 2>/dev/null || true
          git add '$BACKLOG_REL' 2>/dev/null
          git commit -m 'chore($story_id): rate_limit_retry [delivery-wrapper]' --quiet 2>/dev/null
          git push origin '$TARGET_BRANCH' --quiet 2>&1 || true
        fi
      ) || echo "[WRAPPER] Warning: could not revert $story_id to refined"
      # No escalation notification — rate-limit is a transient platform event, not an incident
    else
      echo "[WRAPPER] Delivery failed (exit \$EXIT_CODE). Marking $story_id as failed on staging..."
      (
        if command -v flock &>/dev/null; then
          flock "$STAGING_LOCK" bash -c "
            '$SCHEDULER' --set-status '$story_id' failed '$BACKLOG' 2>/dev/null || true
            git add '$BACKLOG_REL' 2>/dev/null
            git commit -m 'chore($story_id): failed [delivery-wrapper]' --quiet 2>/dev/null
            git push origin '$TARGET_BRANCH' --quiet 2>&1
          "
        else
          '$SCHEDULER' --set-status '$story_id' failed '$BACKLOG' 2>/dev/null || true
          git add '$BACKLOG_REL' 2>/dev/null
          git commit -m 'chore($story_id): failed [delivery-wrapper]' --quiet 2>/dev/null
          git push origin '$TARGET_BRANCH' --quiet 2>&1 || true
        fi
      ) || echo "[WRAPPER] Warning: could not mark $story_id as failed (will be caught by staleness detection)"
      notify_escalation_inline "$story_id" "Failed: delivery exit code \$EXIT_CODE" "Check .gaai/project/contexts/backlog/.delivery-logs/${story_id}.log"
    fi
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

# Truncate stale log from previous runs (prevents false heartbeat kills)
: > "$delivery_log"

# Slash commands don't work in -p mode — expand the command file into a prompt
# Strip YAML frontmatter (--+\n...\n--+) — claude -p treats leading dashes as a CLI option
DELIVERY_PROMPT=\$(awk 'BEGIN{s=0} NR==1 && /^--+\$/{s=1; next} s==1 && /^--+\$/{s=0; next} s==0' "$PROJECT_DIR/.claude/commands/gaai-deliver.md")

# --output-format stream-json streams NDJSON events in real-time, so:
#   - tee updates the log file continuously (natural heartbeat for daemon monitor)
#   - tail -f shows progress in real-time
if command -v gtimeout &>/dev/null; then
  gtimeout "$DELIVERY_TIMEOUT" claude $CLAUDE_FLAGS -p "\${DELIVERY_PROMPT}

Deliver story: $story_id" 2>&1 | tee -a "$delivery_log"
  EXIT_CODE=\${PIPESTATUS[0]}
elif command -v timeout &>/dev/null; then
  timeout "$DELIVERY_TIMEOUT" claude $CLAUDE_FLAGS -p "\${DELIVERY_PROMPT}

Deliver story: $story_id" 2>&1 | tee -a "$delivery_log"
  EXIT_CODE=\${PIPESTATUS[0]}
else
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

  local wrapper="$LOCK_DIR/${story_id}_run.sh"
  cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# Auto-generated by delivery-daemon for $story_id — cleaned up on exit

EXIT_CODE=1  # Default to failure (overwritten on success)
EXITING=false  # Re-entry guard for on_exit
LOCK_FILE="$LOCK_DIR/$story_id.lock"
echo \$\$ > "\$LOCK_FILE"

capture_metadata() {
  # Capture delivery metadata directly from delivery log + git log.
  # Same as tmux wrapper — stop hook doesn't fire in -p mode.
  local delivery_log="$LOG_DIR/${story_id}.log"
  local fields_updated=0

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
    if [[ -n "\$cost" && "\$cost" != "0" ]]; then
      "$SCHEDULER" --set-field "$story_id" cost_usd "\$cost" "$BACKLOG" 2>/dev/null && fields_updated=1
    fi
  fi

  local started completed
  started=\$(git log --all --format='%aI' --grep="chore(${story_id}): in_progress" -1 2>/dev/null) || started=""
  completed=\$(git log --all --format='%aI' --grep="chore(${story_id}): done" -1 2>/dev/null) || completed=""
  [[ -n "\$started" ]] && "$SCHEDULER" --set-field "$story_id" started_at "\$started" "$BACKLOG" 2>/dev/null && fields_updated=1
  [[ -n "\$completed" ]] && "$SCHEDULER" --set-field "$story_id" completed_at "\$completed" "$BACKLOG" 2>/dev/null && fields_updated=1

  if command -v gh &>/dev/null; then
    local pr_json
    pr_json=\$(gh pr list --state all --search "$story_id" --json url,number,state,mergedAt --limit 1 2>/dev/null) || pr_json=""
    if [[ -n "\$pr_json" && "\$pr_json" != "[]" ]]; then
      local pr_url pr_number pr_state
      pr_url=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('url',''))" 2>/dev/null) || pr_url=""
      pr_number=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('number',''))" 2>/dev/null) || pr_number=""
      pr_state=\$(echo "\$pr_json" | python3 -c "import json,sys; d=json.load(sys.stdin); s=d[0]; print('merged' if s.get('mergedAt') else s.get('state','open').lower())" 2>/dev/null) || pr_state=""
      [[ -n "\$pr_url" ]] && "$SCHEDULER" --set-field "$story_id" pr_url "\$pr_url" "$BACKLOG" 2>/dev/null && fields_updated=1
      [[ -n "\$pr_number" ]] && "$SCHEDULER" --set-field "$story_id" pr_number "\$pr_number" "$BACKLOG" 2>/dev/null && fields_updated=1
      [[ -n "\$pr_state" ]] && "$SCHEDULER" --set-field "$story_id" pr_status "\$pr_state" "$BACKLOG" 2>/dev/null && fields_updated=1
    fi
  fi

  if [[ "\$fields_updated" -eq 1 ]]; then
    (
      git add "$BACKLOG_REL" 2>/dev/null || exit 1
      git diff --cached --quiet 2>/dev/null && exit 0
      git commit -m "chore($story_id): delivery-metadata [daemon-wrapper]" --quiet 2>/dev/null || exit 1
      git push origin '$TARGET_BRANCH' --quiet 2>/dev/null || true
    ) || true
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

  # AC3 / AC4: webhook (URL baked in at generation time from NOTIFICATION_WEBHOOK)
  local webhook="$NOTIFICATION_WEBHOOK"
  if [[ -n "\$webhook" ]]; then
    local ts="\$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local json="{\"story_id\":\"\${story_id}\",\"reason\":\"\${reason}\",\"remediation\":\"\${remediation}\",\"timestamp\":\"\${ts}\"}"
    if ! curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
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

    (
      '$SCHEDULER' --set-status '$story_id' escalated '$BACKLOG' 2>/dev/null || true
      git add '$BACKLOG_REL' 2>/dev/null
      git commit -m 'chore($story_id): escalated [daemon-wrapper]' --quiet 2>/dev/null
      git push origin '$TARGET_BRANCH' --quiet 2>&1 || true
    ) || echo "[WRAPPER] Warning: could not mark $story_id as escalated"
    notify_escalation_inline "$story_id" "Escalated: agent stopped without completing delivery" "Check .gaai/project/contexts/backlog/.delivery-logs/${story_id}.log"
  elif [[ \$EXIT_CODE -ne 0 ]]; then
    if is_rate_limit_failure; then
      echo "[WRAPPER] Delivery hit Anthropic rate-limit (transient). Reverting $story_id to refined for retry..."
      (
        '$SCHEDULER' --set-status '$story_id' refined '$BACKLOG' 2>/dev/null || true
        git add '$BACKLOG_REL' 2>/dev/null
        git commit -m 'chore($story_id): rate_limit_retry [delivery-wrapper]' --quiet 2>/dev/null
        git push origin '$TARGET_BRANCH' --quiet 2>&1 || true
      ) || echo "[WRAPPER] Warning: could not revert $story_id to refined"
      # No escalation notification — rate-limit is a transient platform event, not an incident
    else
      echo "[WRAPPER] Delivery failed (exit \$EXIT_CODE). Marking $story_id as failed on staging..."
      (
        '$SCHEDULER' --set-status '$story_id' failed '$BACKLOG' 2>/dev/null || true
        git add '$BACKLOG_REL' 2>/dev/null
        git commit -m 'chore($story_id): failed [delivery-wrapper]' --quiet 2>/dev/null
        git push origin '$TARGET_BRANCH' --quiet 2>&1 || true
      ) || echo "[WRAPPER] Warning: could not mark $story_id as failed"
      notify_escalation_inline "$story_id" "Failed: delivery exit code \$EXIT_CODE" "Check .gaai/project/contexts/backlog/.delivery-logs/${story_id}.log"
    fi
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

# Truncate stale log from previous runs (prevents false heartbeat kills)
: > "$delivery_log"

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
  gtimeout "$DELIVERY_TIMEOUT" claude $CLAUDE_FLAGS -p "\${DELIVERY_PROMPT}

Deliver story: $story_id" 2>&1 | tee -a "$delivery_log"
  EXIT_CODE=\${PIPESTATUS[0]}
else
  claude $CLAUDE_FLAGS -p "\${DELIVERY_PROMPT}

Deliver story: $story_id" 2>&1 | tee -a "$delivery_log"
  EXIT_CODE=\${PIPESTATUS[0]}
fi

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

# ── Main loop ─────────────────────────────────────────────────────────────
while true; do
  clean_stale_locks
  check_heartbeats || true

  active=$(active_count)

  if (( active >= MAX_CONCURRENT )); then
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
    log "${BLUE}No stories ready. Waiting...${NC}"
    sleep "$POLL_INTERVAL"
    continue
  fi

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
    launch_delivery "$story_id"
    ((launched++))

  done <<< "$ready_stories"

  if (( launched == 0 )); then
    log "${BLUE}All ready stories already in progress. Waiting...${NC}"
  fi

  sleep "$POLL_INTERVAL"
done
