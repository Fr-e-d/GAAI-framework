#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# GAAI Daemon Launcher — unified start/stop/status wrapper
# ═══════════════════════════════════════════════════════════════════════════
#
# Description:
#   Simple wrapper around delivery-daemon.sh that handles platform
#   detection, PID management, and daemon lifecycle.
#
# Usage:
#   daemon-start.sh [options]          Start the daemon
#   daemon-start.sh --stop             Graceful shutdown (drains in-flight wrappers)
#   daemon-start.sh --stop --no-drain  Stop daemon, leave wrappers running
#   daemon-start.sh --status           Live monitoring dashboard (tmux) or static status
#   daemon-start.sh --monitor          Alias for --status
#   daemon-start.sh --restart          Stop + start
#
# Options (passed through to delivery-daemon.sh):
#   --max-concurrent N     Parallel delivery slots (default: 3)
#   --interval N           Poll interval in seconds (default: 30)
#   --exit-when-idle [N]   Auto-stop daemon after N consecutive idle polls
#                          (no ready stories + zero in-flight). N optional,
#                          default 5. Useful for one-shot batches that should
#                          drain the backlog and then exit cleanly.
#   --dry-run              Show what would launch, don't execute
#
# Stop options:
#   --no-drain             Skip wrapper drain (legacy behaviour ; in-flight
#                          deliveries continue independently after daemon
#                          exits). Default is graceful drain : SIGTERM
#                          wrappers via lock files, wait STOP_DRAIN_TIMEOUT
#                          (default 600s, override via GAAI_STOP_DRAIN_TIMEOUT),
#                          then SIGTERM tmux sessions, +30s grace, SIGKILL.
#
# Exit codes:
#   0 — success
#   1 — error (daemon already running, not found, etc.)
# ═══════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GAAI_DIR="$(cd "$CORE_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$GAAI_DIR/.." && pwd)"

# ── Platform guard ────────────────────────────────────────────────────
case "$(uname -s)" in
  Darwin|Linux) ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "ERROR: Native Windows is not supported. Use WSL instead."
    exit 1
    ;;
esac

DAEMON_SCRIPT="$SCRIPT_DIR/delivery-daemon.sh"
MONITOR_TOP="$SCRIPT_DIR/daemon-monitor-top.sh"
MONITOR_TAIL="$SCRIPT_DIR/daemon-monitor-tail.sh"
LOCK_DIR="$GAAI_DIR/project/contexts/backlog/.delivery-locks"
PID_FILE="$LOCK_DIR/.daemon.pid"
LOG_FILE="$GAAI_DIR/project/contexts/backlog/.delivery-daemon.log"
LOG_DIR="$GAAI_DIR/project/contexts/backlog/.delivery-logs"

# OSS-3 : drain timeout for /gaai:stop graceful shutdown. Wrappers may be in
# the middle of a long phase (impl up to 90 min per OSS-7 timeout) ; the drain
# is a best-effort grace period after which we escalate to tmux kill-session.
STOP_DRAIN_TIMEOUT="${GAAI_STOP_DRAIN_TIMEOUT:-600}"

# ── Helpers ───────────────────────────────────────────────────────────────

daemon_is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

get_pid() {
  [[ -f "$PID_FILE" ]] && cat "$PID_FILE" || echo ""
}

# ── Parse action ──────────────────────────────────────────────────────────

ACTION="start"
NO_DRAIN=false
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start)    ACTION="start";   shift ;;
    --stop)     ACTION="stop";    shift ;;
    --status)   ACTION="status";  shift ;;
    --monitor)  ACTION="status";  shift ;;
    --restart)  ACTION="restart"; shift ;;
    --no-drain) NO_DRAIN=true;    shift ;;
    *)          PASSTHROUGH_ARGS+=("$1"); shift ;;
  esac
done

# ── Auto-launch monitoring terminal ────────────────────────────────────────

_launch_monitor() {
  local daemon_start_path="$SCRIPT_DIR/daemon-start.sh"

  case "$(uname -s)" in
    Darwin)
      # Uses `open -a Terminal` (LaunchServices) instead of osascript Apple
      # Events, which requires explicit Automation permission that headless
      # contexts (like Claude Code) typically lack.
      local monitor_cmd="$SCRIPT_DIR/open-monitor.command"
      open -a Terminal "$monitor_cmd" 2>/dev/null \
        && echo "  Monitor: opened in new Terminal.app window" \
        || echo "  Monitor: bash $daemon_start_path --status"
      ;;
    *)
      # On Linux: create the monitor tmux session detached (user can attach)
      if command -v tmux &>/dev/null; then
        bash "$daemon_start_path" --status &
        disown 2>/dev/null || true
        echo "  Monitor: tmux attach -t gaai-monitor"
      else
        echo "  Monitor: bash $daemon_start_path --status"
      fi
      ;;
  esac
}

# ── Actions ───────────────────────────────────────────────────────────────

# OSS-3 : enumerate live wrapper PIDs from $LOCK_DIR/*.lock files.
# Returns lines "<sid>|<pid>". Skips placeholder ("pending") locks and dead PIDs.
_list_live_wrappers() {
  local lock pid sid
  [[ -d "$LOCK_DIR" ]] || return 0
  for lock in "$LOCK_DIR"/*.lock; do
    [[ -f "$lock" ]] || continue
    pid=$(head -1 "$lock" 2>/dev/null || echo "")
    [[ -z "$pid" || "$pid" == "pending" ]] && continue
    kill -0 "$pid" 2>/dev/null || continue
    sid=$(basename "$lock" .lock)
    echo "${sid}|${pid}"
  done
}

# OSS-3 : graceful drain of in-flight wrappers.
#   1. SIGTERM each wrapper PID (NOT the tmux session — the wrapper's trap
#      sets _INTERRUPT_REQUESTED and lets claude -p finish current phase).
#   2. Poll for lock files to disappear (wrapper exit) up to STOP_DRAIN_TIMEOUT.
#   3. For wrappers still alive after timeout, SIGTERM their tmux sessions
#      (kills claude -p too), grace 30s, then SIGKILL.
_drain_wrappers() {
  local entries
  entries=$(_list_live_wrappers)
  if [[ -z "$entries" ]]; then
    echo "  No live wrappers to drain."
    return 0
  fi

  local count
  count=$(echo "$entries" | wc -l | tr -d ' ')
  echo "Draining $count in-flight wrapper(s) — SIGTERM, will wait up to ${STOP_DRAIN_TIMEOUT}s for graceful exit..."

  # Phase 1 : SIGTERM each wrapper PID directly (not the tmux session).
  while IFS='|' read -r sid pid; do
    [[ -z "$sid" || -z "$pid" ]] && continue
    echo "  SIGTERM $sid (PID $pid)"
    kill -TERM "$pid" 2>/dev/null || true
  done <<< "$entries"

  # Phase 2 : poll for wrapper exits up to STOP_DRAIN_TIMEOUT.
  local waited=0 step=5
  while (( waited < STOP_DRAIN_TIMEOUT )); do
    local remaining
    remaining=$(_list_live_wrappers)
    if [[ -z "$remaining" ]]; then
      echo "  All wrappers exited cleanly after ${waited}s."
      return 0
    fi
    sleep "$step"
    waited=$(( waited + step ))
  done

  # Phase 3 : escalate — SIGTERM tmux sessions of wrappers still alive.
  echo "  Drain timeout (${STOP_DRAIN_TIMEOUT}s) reached. Escalating to tmux kill-session..."
  local stragglers
  stragglers=$(_list_live_wrappers)
  while IFS='|' read -r sid pid; do
    [[ -z "$sid" || -z "$pid" ]] && continue
    if command -v tmux &>/dev/null && tmux has-session -t "gaai-deliver-${sid}" 2>/dev/null; then
      echo "  tmux kill-session gaai-deliver-${sid} (PID $pid)"
      tmux kill-session -t "gaai-deliver-${sid}" 2>/dev/null || true
    else
      echo "  SIGTERM PID $pid (no tmux session for $sid)"
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done <<< "$stragglers"

  # Phase 4 : grace then SIGKILL anything still alive.
  sleep 30
  local final
  final=$(_list_live_wrappers)
  if [[ -n "$final" ]]; then
    while IFS='|' read -r sid pid; do
      [[ -z "$sid" || -z "$pid" ]] && continue
      echo "  SIGKILL $sid (PID $pid)"
      kill -KILL "$pid" 2>/dev/null || true
    done <<< "$final"
  fi
}

do_stop() {
  if ! daemon_is_running; then
    echo "No daemon running."
    [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
    # Still drain stale wrappers (daemon dead, wrappers may have survived).
    if ! $NO_DRAIN; then
      _drain_wrappers
    fi
    return 0
  fi

  local pid
  pid=$(get_pid)

  # OSS-3 : drain in-flight wrappers BEFORE stopping the daemon. The daemon
  # itself only manages dispatch ; wrappers run independently in their own
  # tmux sessions and survive a daemon kill. Default behaviour drains them
  # gracefully ; --no-drain preserves the legacy "wrappers continue
  # independently" behaviour.
  if ! $NO_DRAIN; then
    _drain_wrappers
  else
    echo "Skipping wrapper drain (--no-drain) — in-flight deliveries continue independently."
  fi

  echo "Stopping daemon (PID $pid)..."
  kill "$pid" 2>/dev/null || true

  # Wait up to 10 seconds for graceful shutdown
  local waited=0
  while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 10 ]]; do
    sleep 1
    waited=$((waited + 1))
  done

  if kill -0 "$pid" 2>/dev/null; then
    echo "Force-killing daemon (PID $pid)..."
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "$PID_FILE"

  # Kill the monitoring session if it exists
  if command -v tmux &>/dev/null && tmux has-session -t gaai-monitor 2>/dev/null; then
    tmux kill-session -t gaai-monitor 2>/dev/null || true
    echo "  Monitor session (gaai-monitor) closed."
  fi

  # Kill the daemon tmux session if it's still around
  if command -v tmux &>/dev/null && tmux has-session -t gaai-daemon 2>/dev/null; then
    tmux kill-session -t gaai-daemon 2>/dev/null || true
  fi

  # Truncate daemon log to avoid unbounded growth
  [[ -f "$LOG_FILE" ]] && : > "$LOG_FILE"

  echo "✅ Daemon stopped. Log truncated."
}

do_status() {
  if ! daemon_is_running; then
    echo "⏹  Daemon is not running."
    [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE" || true
    return 0
  fi

  local pid
  pid=$(get_pid)

  # If tmux is available and we're in a real terminal, launch live dashboard
  if command -v tmux &>/dev/null && [[ -t 1 ]]; then
    local monitor_session="gaai-monitor"

    # If monitor already exists, just attach
    if tmux has-session -t "$monitor_session" 2>/dev/null; then
      exec tmux attach -t "$monitor_session"
    fi

    local config_file="$GAAI_DIR/project/contexts/backlog/.delivery-locks/.daemon-config"
    mkdir -p "$LOG_DIR"

    # Top pane: fixed banner (from config) + scrolling daemon logs
    tmux new-session -d -s "$monitor_session" \
      "bash '$MONITOR_TOP' '$config_file' '$LOG_FILE'"

    # Bottom pane: active deliveries summary (60% height — fits title + 3 concurrent slots)
    tmux split-window -t "${monitor_session}:0" -v -p 60 \
      "bash '$MONITOR_TAIL' '$LOG_DIR'"

    # Enable mouse mode (allows scroll in panes when content exceeds pane height)
    tmux set-option -t "$monitor_session" mouse on

    # Status bar
    tmux set-option -t "$monitor_session" status-style "bg=colour236,fg=colour248"
    tmux set-option -t "$monitor_session" status-left-length 40
    tmux set-option -t "$monitor_session" status-left "#[fg=colour214,bold] GAAI Delivery Monitor "
    tmux set-option -t "$monitor_session" status-right "#[fg=colour248] Ctrl+C to exit │ %H:%M "
    tmux set-option -t "$monitor_session" status-right-length 40
    tmux set-window-option -t "$monitor_session" window-status-format ""
    tmux set-window-option -t "$monitor_session" window-status-current-format ""
    tmux select-pane -t "${monitor_session}:0.0"

    exec tmux attach -t "$monitor_session"
  else
    # Fallback: static status (no tmux or non-interactive)
    echo "✅ Daemon is running (PID $pid)"
    echo "   Log: $LOG_FILE"
    echo ""
    if [[ -f "$DAEMON_SCRIPT" ]]; then
      bash "$DAEMON_SCRIPT" --status 2>/dev/null || true
    fi
  fi
}

do_start() {
  # Pre-flight checks
  if daemon_is_running; then
    local pid
    pid=$(get_pid)
    echo "❌ Daemon is already running (PID $pid)."
    echo "   Use --restart to restart, or --stop first."
    exit 1
  fi

  if [[ ! -f "$DAEMON_SCRIPT" ]]; then
    echo "❌ delivery-daemon.sh not found at $DAEMON_SCRIPT"
    echo "   Run daemon-setup.sh first."
    exit 1
  fi

  # Clean stale PID file
  [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"

  # Ensure log directory exists
  mkdir -p "$(dirname "$LOG_FILE")"

  echo "Starting GAAI Delivery Daemon..."
  echo "  Log: $LOG_FILE"

  # Platform detection: prefer tmux, fallback to nohup
  if command -v tmux &>/dev/null; then
    # Build tmux command string (args are simple flags, safe to join)
    local daemon_cmd="bash '${DAEMON_SCRIPT}' ${PASSTHROUGH_ARGS[*]+${PASSTHROUGH_ARGS[*]}}"
    # Forward GAAI_IMPL_* env vars into tmux session (tmux strips parent env by default).
    # Required for daemon-dispatch.sh resolveMode() to route Impl phase to secondary (GLM).
    # Plan + QA stay on primary (Sonnet) regardless ; only Impl reads these vars.
    local tmux_env_args=()
    [[ -n "${GAAI_IMPL_BASE_URL:-}"   ]] && tmux_env_args+=(-e "GAAI_IMPL_BASE_URL=${GAAI_IMPL_BASE_URL}")
    [[ -n "${GAAI_IMPL_AUTH_TOKEN:-}" ]] && tmux_env_args+=(-e "GAAI_IMPL_AUTH_TOKEN=${GAAI_IMPL_AUTH_TOKEN}")
    [[ -n "${GAAI_IMPL_MODEL:-}"      ]] && tmux_env_args+=(-e "GAAI_IMPL_MODEL=${GAAI_IMPL_MODEL}")
    [[ -n "${GAAI_IMPL_MODEL_FALLBACK:-}" ]] && tmux_env_args+=(-e "GAAI_IMPL_MODEL_FALLBACK=${GAAI_IMPL_MODEL_FALLBACK}")
    # Auto-merge policy (DEC-76 v4 §11) — values : on / staging_only / off (default off)
    [[ -n "${GAAI_AUTO_MERGE_POLICY:-}" ]] && tmux_env_args+=(-e "GAAI_AUTO_MERGE_POLICY=${GAAI_AUTO_MERGE_POLICY}")
    # Admin fallback (free-tier opt-in) — when --auto fails branch_protection_missing,
    # fall back to gh pr merge --admin --squash. Trust-arc opt-in, default off.
    [[ -n "${GAAI_AUTO_MERGE_ADMIN_FALLBACK:-}" ]] && tmux_env_args+=(-e "GAAI_AUTO_MERGE_ADMIN_FALLBACK=${GAAI_AUTO_MERGE_ADMIN_FALLBACK}")
    tmux new-session -d -s gaai-daemon "${tmux_env_args[@]}" "$daemon_cmd"

    # Give it a moment to start, then grab the PID
    sleep 1
    local tmux_pid
    tmux_pid=$(tmux list-panes -t gaai-daemon -F '#{pane_pid}' 2>/dev/null | head -1 || echo "")

    if [[ -n "$tmux_pid" ]]; then
      echo "$tmux_pid" > "$PID_FILE"
      echo "  PID: $tmux_pid (tmux session: gaai-daemon)"
      echo ""
      echo "✅ Daemon started."
      echo ""
      echo "  Stop:    bash .gaai/core/scripts/daemon-start.sh --stop"

      # Auto-launch monitoring in a new terminal
      _launch_monitor
    else
      echo "⚠️  tmux session created but could not read PID."
      echo "  Check:   tmux attach -t gaai-daemon"
    fi
  else
    # Fallback: nohup
    nohup bash "$DAEMON_SCRIPT" ${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"} >> "$LOG_FILE" 2>&1 &
    local bg_pid=$!
    echo "$bg_pid" > "$PID_FILE"
    echo "  PID: $bg_pid (nohup)"
    echo ""
    echo "✅ Daemon started."
    echo ""
    echo "  Logs:    tail -f $LOG_FILE"
    echo "  Status:  bash .gaai/core/scripts/daemon-start.sh --status"
    echo "  Stop:    bash .gaai/core/scripts/daemon-start.sh --stop"
  fi
}

# ── Dispatch ──────────────────────────────────────────────────────────────

case "$ACTION" in
  start)   do_start   ;;
  stop)    do_stop    ;;
  status)  do_status  ;;
  restart) do_stop; do_start ;;
esac
