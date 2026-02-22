#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# GAAI Delivery Daemon
# ═══════════════════════════════════════════════════════════════════════════
#
# Description:
#   Polls the active backlog and auto-launches Claude Code delivery sessions
#   for stories that are ready (status: refined, all dependencies done).
#   Prevents double-launching via PID-based lock files + retry tracking.
#
# Race condition protection:
#   The delivery agent works in a git worktree. The backlog on `production`
#   stays at `status: refined` until the merge. The daemon reads the backlog
#   from `git show production:...` (committed state) and uses PID-based lock
#   files to prevent double-launching the same story. A retry counter caps
#   re-launches at 3 per story to prevent infinite loops on failures.
#
# Usage:
#   ./delivery-daemon.sh                     # defaults: 30s poll, 1 slot
#   ./delivery-daemon.sh --interval 15       # poll every 15s
#   ./delivery-daemon.sh --max-concurrent 2  # allow 2 parallel deliveries
#   ./delivery-daemon.sh --dry-run           # show what would launch, don't launch
#
# Environment overrides:
#   GAAI_POLL_INTERVAL=15  ./delivery-daemon.sh
#   GAAI_MAX_CONCURRENT=2  ./delivery-daemon.sh
#
# Requirements:
#   - python3 (macOS built-in)
#   - claude CLI in PATH
#   - Terminal.app
#
# Exit codes:
#   0 — clean shutdown (Ctrl+C)
#   1 — missing dependency or config error
# ═══════════════════════════════════════════════════════════════════════════

# ── Configuration ─────────────────────────────────────────────────────────
POLL_INTERVAL="${GAAI_POLL_INTERVAL:-30}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAX_CONCURRENT="${GAAI_MAX_CONCURRENT:-1}"
DRY_RUN=false

BACKLOG_REL=".gaai/contexts/backlog/active.backlog.yaml"
BACKLOG="$PROJECT_DIR/$BACKLOG_REL"
LOCK_DIR="$PROJECT_DIR/.gaai/.delivery-locks"
RETRY_FILE="$LOCK_DIR/.retry-counts"
LOG_FILE="$PROJECT_DIR/.gaai/.delivery-daemon.log"
MAX_RETRIES=3
PRODUCTION_BRANCH="production"

# ── Parse CLI args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)    POLL_INTERVAL="$2"; shift 2 ;;
    --max-concurrent) MAX_CONCURRENT="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --help|-h)
      head -25 "$0" | tail -18
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

# ── Preflight checks ─────────────────────────────────────────────────────
mkdir -p "$LOCK_DIR"

if ! command -v python3 &>/dev/null; then
  echo -e "${RED}ERROR: python3 is required (should be built-in on macOS)${NC}"
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo -e "${RED}ERROR: claude CLI not found in PATH${NC}"
  echo "Install: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi

if [[ ! -f "$BACKLOG" ]]; then
  echo -e "${RED}ERROR: Backlog not found at $BACKLOG${NC}"
  exit 1
fi

# ── Embedded backlog parser (Python3, no dependencies) ────────────────────
# Reads the YAML backlog from git (committed state on production branch)
# and outputs ready story IDs (one per line).
# A story is ready when: status=refined AND all dependencies have status=done.
read_backlog_content() {
  # Primary: read committed state from production branch (avoids worktree drift)
  local content
  content=$(git -C "$PROJECT_DIR" show "${PRODUCTION_BRANCH}:${BACKLOG_REL}" 2>/dev/null) && {
    echo "$content"
    return
  }
  # Fallback: read from filesystem (e.g. if git is in a transient state)
  if [[ -f "$BACKLOG" ]]; then
    cat "$BACKLOG"
  fi
}

find_ready_stories() {
  local backlog_content
  backlog_content=$(read_backlog_content)
  [[ -z "$backlog_content" ]] && return

  echo "$backlog_content" | python3 -c '
import re, sys

def parse_backlog(lines):
    items = []
    current = None
    for line in lines:
        m = re.match(r"\s+-\s+id:\s+(\S+)", line)
        if m:
            if current:
                items.append(current)
            current = {"id": m.group(1), "status": "", "dependencies": []}
            continue
        if current is None:
            continue
        m = re.match(r"\s+status:\s+(\S+)", line)
        if m:
            current["status"] = m.group(1)
            continue
        m = re.match(r"\s+dependencies:\s+\[(.*?)\]", line)
        if m:
            deps_str = m.group(1).strip()
            if deps_str:
                current["dependencies"] = [d.strip() for d in deps_str.split(",")]
            continue
    if current:
        items.append(current)
    return items

lines = sys.stdin.readlines()
items = parse_backlog(lines)
done_ids = {i["id"] for i in items if i["status"] == "done"}

for item in items:
    if item["status"] == "refined":
        if all(dep in done_ids for dep in item["dependencies"]):
            print(item["id"])
'
}

# ── Lock management ──────────────────────────────────────────────────────
clean_stale_locks() {
  for lock in "$LOCK_DIR"/*.lock; do
    [[ -f "$lock" ]] || continue
    local pid
    pid=$(head -1 "$lock" 2>/dev/null || echo "")
    if [[ -z "$pid" || "$pid" == "pending" ]]; then
      # Placeholder lock older than 30s is stale
      local age
      age=$(( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || echo "0") ))
      if (( age > 30 )); then
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

active_count() {
  local count=0
  for lock in "$LOCK_DIR"/*.lock; do
    [[ -f "$lock" ]] || continue
    ((count++))
  done
  echo "$count"
}

is_locked() {
  [[ -f "$LOCK_DIR/$1.lock" ]]
}

# ── Retry tracking ────────────────────────────────────────────────────────
# Tracks how many times each story has been launched to prevent infinite loops.
# Resets when the daemon restarts (intentional — human restart = "try again").
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
  local current
  current=$(get_retry_count "$story_id")
  local next=$(( current + 1 ))
  if [[ -f "$RETRY_FILE" ]]; then
    # Update existing entry or append
    if grep -q "^${story_id}=" "$RETRY_FILE" 2>/dev/null; then
      sed -i '' "s/^${story_id}=.*/${story_id}=${next}/" "$RETRY_FILE"
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

# ── Logging ───────────────────────────────────────────────────────────────
log() {
  local msg="[$(date '+%H:%M:%S')] $*"
  echo -e "$msg"
  # Strip ANSI for log file
  echo -e "$msg" | sed 's/\x1B\[[0-9;]*m//g' >> "$LOG_FILE"
}

# ── Launch delivery in new Terminal.app window ────────────────────────────
launch_delivery() {
  local story_id="$1"

  # Create a self-contained wrapper script
  local wrapper="$LOCK_DIR/${story_id}_run.sh"
  cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# Auto-generated by delivery-daemon for $story_id — cleaned up after delivery

LOCK_FILE="$LOCK_DIR/$story_id.lock"
echo \$\$ > "\$LOCK_FILE"
trap 'rm -f "\$LOCK_FILE" "$wrapper"' EXIT INT TERM

printf '\n\033[1;36m'
echo "================================================================"
echo "  GAAI Delivery Daemon"
echo "  Story:   $story_id"
echo "  Started: \$(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"
printf '\033[0m\n'

cd "$PROJECT_DIR"
claude --dangerously-skip-permissions -p "/gaai-deliver $story_id"

EXIT_CODE=\$?

printf '\n\033[1;36m'
echo "================================================================"
echo "  Delivery session ended: $story_id"
echo "  Exit code: \$EXIT_CODE"
echo "  Finished:  \$(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"
printf '\033[0m\n'

echo "Press any key to close..."
read -rsn1
WRAPPER_EOF

  chmod +x "$wrapper"

  # Launch in a new Terminal.app window
  osascript <<APPLE_EOF
    tell application "Terminal"
      activate
      do script "'$wrapper'"
    end tell
APPLE_EOF

  # Brief pause to let the wrapper write its PID
  sleep 2

  if [[ -f "$LOCK_DIR/$story_id.lock" ]]; then
    local pid
    pid=$(cat "$LOCK_DIR/$story_id.lock")
    log "${GREEN}Launched: $story_id (PID $pid)${NC}"
  else
    # Wrapper hasn't written PID yet — create placeholder to prevent double-launch
    echo "pending" > "$LOCK_DIR/$story_id.lock"
    log "${GREEN}Launched: $story_id (PID pending)${NC}"
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
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║          GAAI Delivery Daemon                   ║"
echo "  ╠══════════════════════════════════════════════════╣"
echo -e "  ║${NC}${CYAN}  Poll interval:  ${BOLD}${POLL_INTERVAL}s${NC}${CYAN}                           ║"
echo -e "  ║${NC}${CYAN}  Max concurrent: ${BOLD}${MAX_CONCURRENT}${NC}${CYAN}                            ║"
echo -e "  ║${NC}${CYAN}  Dry run:        ${BOLD}${DRY_RUN}${NC}${CYAN}                        ║"
echo -e "  ║${NC}${CYAN}  Log:            ${BOLD}.gaai/.delivery-daemon.log${NC}${CYAN}    ║"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${YELLOW}Ctrl+C to stop (active sessions keep running)${NC}"
echo ""
log "${GREEN}Daemon started.${NC}"

# ── Main loop ─────────────────────────────────────────────────────────────
while true; do
  clean_stale_locks

  active=$(active_count)

  if (( active >= MAX_CONCURRENT )); then
    log "${BLUE}Slots full ($active/$MAX_CONCURRENT). Waiting...${NC}"
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Find stories ready for delivery
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
      log "${BLUE}$story_id already in progress. Skipping.${NC}"
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

    local retry_count
    retry_count=$(get_retry_count "$story_id")
    if (( retry_count > 0 )); then
      log "${YELLOW}Ready story: $story_id — retry $retry_count/$MAX_RETRIES — launching...${NC}"
    else
      log "${GREEN}Ready story: $story_id — launching delivery...${NC}"
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
