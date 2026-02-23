#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# GAAI Delivery Daemon
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
#   .gaai/scripts/delivery-daemon.sh                     # defaults: 30s, 1 slot
#   .gaai/scripts/delivery-daemon.sh --interval 15       # poll every 15s
#   .gaai/scripts/delivery-daemon.sh --max-concurrent 2  # parallel deliveries
#   .gaai/scripts/delivery-daemon.sh --dry-run           # show what would launch
#   .gaai/scripts/delivery-daemon.sh --status            # show active/ready/exceeded
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
#   cp .env.example .dev.vars               # secrets (staging only)
#
# Required: suppress the --dangerously-skip-permissions warning dialog:
#   mkdir -p ~/.claude && cat > ~/.claude/settings.json << 'EOF'
#   { "skipDangerousModePermissionPrompt": true }
#   EOF
#
# Run daemon:
#   tmux new-session -d -s gaai-daemon '.gaai/scripts/delivery-daemon.sh --max-concurrent 3'
#   tmux attach -t gaai-daemon
#
# Observability:
#   .gaai/scripts/delivery-daemon.sh --status
#   tail -f .gaai/.delivery-logs/E06S11.log
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

# ── Resolve project root ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Configuration ─────────────────────────────────────────────────────────
POLL_INTERVAL="${GAAI_POLL_INTERVAL:-30}"
MAX_CONCURRENT="${GAAI_MAX_CONCURRENT:-1}"
TARGET_BRANCH="${GAAI_TARGET_BRANCH:-staging}"
DELIVERY_TIMEOUT="${GAAI_DELIVERY_TIMEOUT:-14400}"   # 4h hard kill (last resort)
MAX_TURNS="${GAAI_MAX_TURNS:-200}"                    # primary safety net
CLAUDE_MODEL="${GAAI_CLAUDE_MODEL:-sonnet}"           # model (sonnet = cost-effective)
HEARTBEAT_STALE="${GAAI_HEARTBEAT_STALE:-900}"        # 15min no output = stuck
STALENESS_THRESHOLD="${GAAI_STALENESS_THRESHOLD:-}"   # auto-computed below
DRY_RUN=false
STATUS_MODE=false

BACKLOG_REL=".gaai/contexts/backlog/active.backlog.yaml"
BACKLOG="$PROJECT_DIR/$BACKLOG_REL"
SCHEDULER="$SCRIPT_DIR/backlog-scheduler.sh"
LOCK_DIR="$PROJECT_DIR/.gaai/.delivery-locks"
LOG_DIR="$PROJECT_DIR/.gaai/.delivery-logs"
STAGING_LOCK="$LOCK_DIR/.staging.lock"
RETRY_FILE="$LOCK_DIR/.retry-counts"
LOG_FILE="$PROJECT_DIR/.gaai/.delivery-daemon.log"
MAX_RETRIES=3

# Staleness: stories in_progress for longer than this are considered orphaned
# Default: delivery timeout + 10 min buffer
if [[ -z "$STALENESS_THRESHOLD" ]]; then
  STALENESS_THRESHOLD=$(( DELIVERY_TIMEOUT + 600 ))
fi

# ── Platform detection ──────────────────────────────────────────────────
PLATFORM="$(uname)"

# --dangerously-skip-permissions: required for -p mode (headless).
# Without it, permission prompts hang forever since there's no interactive input.
# Override with GAAI_SKIP_PERMISSIONS=false to force interactive (not recommended for -p).
if [[ -n "${GAAI_SKIP_PERMISSIONS:-}" ]]; then
  SKIP_PERMISSIONS="$GAAI_SKIP_PERMISSIONS"
else
  SKIP_PERMISSIONS=true
fi

# Launcher: Terminal.app on macOS, tmux on Linux/VPS
if [[ "$PLATFORM" == "Darwin" ]] && command -v osascript &>/dev/null; then
  LAUNCHER="terminal-app"
else
  LAUNCHER="tmux"
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

# ── Parse CLI args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)       POLL_INTERVAL="$2"; shift 2 ;;
    --max-concurrent) MAX_CONCURRENT="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --status)         STATUS_MODE=true; shift ;;
    --help|-h)
      sed -n '/^# Description:/,/^# ═══.*═══$/p' "$0" | head -n -1
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
  echo -e "$msg" | sed 's/\x1B\[[0-9;]*m//g' >> "$LOG_FILE"
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

# Step 3: Mark in_progress locally
"$SCHEDULER" --set-status "$story_id" in_progress "$BACKLOG"
git add "$BACKLOG_REL"
git commit -m "chore($story_id): in_progress [daemon]" --quiet

# Step 4: Push — this is the atomic coordination point
# If another VPS pushes between our pull and push, this fails (non-fast-forward)
if ! git push origin "$TARGET_BRANCH" --quiet 2>&1; then
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

on_exit() {
  # Prevent re-entry (cleanup_children sends signals that re-trigger trap)
  \$EXITING && return
  EXITING=true
  trap - EXIT INT TERM  # Disable traps to prevent further re-entry

  # Kill child processes (claude, tee)
  kill \$(jobs -p) 2>/dev/null || true

  rm -f "\$LOCK_FILE" "$wrapper"
  if [[ \$EXIT_CODE -ne 0 ]]; then
    # Check if the delivery already marked the story as done
    cd "$PROJECT_DIR"
    git pull origin '$TARGET_BRANCH' --ff-only --quiet 2>&1 || true
    local current_status
    current_status=\$(grep -A 8 'id: $story_id' '$BACKLOG' | grep 'status:' | head -1 | sed 's/.*status: *//')
    if [[ "\$current_status" == "done" ]]; then
      echo "[WRAPPER] Story $story_id already done — ignoring non-zero exit code (\$EXIT_CODE)."
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
DELIVERY_PROMPT=\$(cat "$PROJECT_DIR/.claude/commands/gaai-deliver.md")

# --output-format stream-json streams NDJSON events in real-time, so:
#   - tee updates the log file continuously (natural heartbeat for daemon monitor)
#   - tail -f shows progress in real-time
if command -v timeout &>/dev/null; then
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

on_exit() {
  # Prevent re-entry (kill signals can re-trigger trap)
  \$EXITING && return
  EXITING=true
  trap - EXIT INT TERM  # Disable traps to prevent further re-entry

  # Kill child processes (claude, tee)
  kill \$(jobs -p) 2>/dev/null || true

  rm -f "\$LOCK_FILE" "$wrapper"
  if [[ \$EXIT_CODE -ne 0 ]]; then
    # Check if the delivery already marked the story as done
    # (interactive mode: user closes terminal after successful delivery → non-zero exit)
    cd "$PROJECT_DIR"
    git pull origin '$TARGET_BRANCH' --ff-only --quiet 2>&1 || true
    local current_status
    current_status=\$(grep -A 8 'id: $story_id' '$BACKLOG' | grep 'status:' | head -1 | sed 's/.*status: *//')
    if [[ "\$current_status" == "done" ]]; then
      echo "[WRAPPER] Story $story_id already done — ignoring non-zero exit code (\$EXIT_CODE)."
    else
      echo "[WRAPPER] Delivery failed (exit \$EXIT_CODE). Marking $story_id as failed on staging..."
      (
        '$SCHEDULER' --set-status '$story_id' failed '$BACKLOG' 2>/dev/null || true
        git add '$BACKLOG_REL' 2>/dev/null
        git commit -m 'chore($story_id): failed [delivery-wrapper]' --quiet 2>/dev/null
        git push origin '$TARGET_BRANCH' --quiet 2>&1 || true
      ) || echo "[WRAPPER] Warning: could not mark $story_id as failed"
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
# See: https://code.claude.com/docs/en/headless
DELIVERY_PROMPT=\$(cat "$PROJECT_DIR/.claude/commands/gaai-deliver.md")

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
      activate
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

# ── Graceful shutdown ─────────────────────────────────────────────────────
shutdown() {
  echo ""
  log "${YELLOW}Daemon stopped. Active delivery sessions continue independently.${NC}"
  exit 0
}

trap shutdown SIGINT SIGTERM

# ── Banner ────────────────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║              GAAI Delivery Daemon                       ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
echo -e "  ║${NC}${CYAN}  Branch:         ${BOLD}${TARGET_BRANCH}${NC}${CYAN}                               ║"
echo -e "  ║${NC}${CYAN}  Poll interval:  ${BOLD}${POLL_INTERVAL}s${NC}${CYAN}                                 ║"
echo -e "  ║${NC}${CYAN}  Max concurrent: ${BOLD}${MAX_CONCURRENT}${NC}${CYAN}                                  ║"
echo -e "  ║${NC}${CYAN}  Model:          ${BOLD}${CLAUDE_MODEL}${NC}${CYAN}                             ║"
echo -e "  ║${NC}${CYAN}  Launcher:       ${BOLD}${LAUNCHER}${NC}${CYAN}                           ║"
echo -e "  ║${NC}${CYAN}  Skip perms:     ${BOLD}${SKIP_PERMISSIONS}${NC}${CYAN}                              ║"
echo -e "  ║${NC}${CYAN}  Max turns:      ${BOLD}${MAX_TURNS}${NC}${CYAN}                                ║"
echo -e "  ║${NC}${CYAN}  Heartbeat:      ${BOLD}${HEARTBEAT_STALE}s${NC}${CYAN}                               ║"
echo -e "  ║${NC}${CYAN}  Hard timeout:   ${BOLD}${DELIVERY_TIMEOUT}s${NC}${CYAN}                             ║"
echo -e "  ║${NC}${CYAN}  Dry run:        ${BOLD}${DRY_RUN}${NC}${CYAN}                              ║"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
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
      log "${YELLOW}Ready story: $story_id — retry $retry_count/$MAX_RETRIES — launching...${NC}"
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
