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
#   daemon-start.sh --stop             Graceful shutdown
#   daemon-start.sh --status           Live monitoring dashboard (tmux) or static status
#   daemon-start.sh --monitor          Alias for --status
#   daemon-start.sh --restart          Stop + start
#
# Options (passed through to delivery-daemon.sh):
#   --max-concurrent N     Parallel delivery slots (default: 1)
#   --interval N           Poll interval in seconds (default: 30)
#   --dry-run              Show what would launch, don't execute
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
MONITOR_TAIL="$SCRIPT_DIR/daemon-monitor-tail.sh"
PID_FILE="$GAAI_DIR/project/contexts/backlog/.delivery-locks/.daemon.pid"
LOG_FILE="$GAAI_DIR/project/contexts/backlog/.delivery-daemon.log"
LOG_DIR="$GAAI_DIR/project/contexts/backlog/.delivery-logs"

# ── Helpers ───────────────────────────────────────────────────────────────

daemon_is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

get_pid() {
  [[ -f "$PID_FILE" ]] && cat "$PID_FILE" || echo ""
}

# ── Parse action ──────────────────────────────────────────────────────────

ACTION="start"
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop)    ACTION="stop";    shift ;;
    --status)  ACTION="status";  shift ;;
    --monitor) ACTION="status";  shift ;;
    --restart) ACTION="restart"; shift ;;
    *)         PASSTHROUGH_ARGS+=("$1"); shift ;;
  esac
done

# ── Actions ───────────────────────────────────────────────────────────────

do_stop() {
  if ! daemon_is_running; then
    echo "No daemon running."
    [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
    return 0
  fi

  local pid
  pid=$(get_pid)
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
  echo "✅ Daemon stopped."
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

    local daemon_snapshot="$LOG_DIR/.daemon-output.log"
    mkdir -p "$LOG_DIR"

    # Background: periodically capture visible daemon pane content (clean text, no escape sequences)
    (
      while tmux has-session -t gaai-daemon 2>/dev/null; do
        tmux capture-pane -t gaai-daemon -p -S -50 > "$daemon_snapshot.tmp" 2>/dev/null
        mv "$daemon_snapshot.tmp" "$daemon_snapshot"
        sleep 2
      done
    ) &
    local capture_pid=$!
    trap "kill $capture_pid 2>/dev/null" EXIT

    # Top pane: daemon output
    tmux new-session -d -s "$monitor_session" \
      "watch -t -n 2 cat '$daemon_snapshot'"

    # Bottom pane: active deliveries summary
    tmux split-window -t "${monitor_session}:0" -v -p 50 \
      "bash '$MONITOR_TAIL' '$LOG_DIR'"

    # Disable mouse mode (prevents escape sequences when moving mouse over terminal)
    tmux set-option -t "$monitor_session" mouse off

    # Status bar
    tmux set-option -t "$monitor_session" status-style "bg=colour236,fg=colour248"
    tmux set-option -t "$monitor_session" status-left "#[fg=colour214,bold] GAAI Monitor "
    tmux set-option -t "$monitor_session" status-right "#[fg=colour248] %H:%M "
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
    local daemon_cmd="bash '${DAEMON_SCRIPT}' ${PASSTHROUGH_ARGS[*]+${PASSTHROUGH_ARGS[*]}} 2>&1 | tee -a '${LOG_FILE}'"
    tmux new-session -d -s gaai-daemon "$daemon_cmd"

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
      echo "  Monitor: bash .gaai/core/scripts/daemon-start.sh --status"
      echo "  Stop:    bash .gaai/core/scripts/daemon-start.sh --stop"
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
