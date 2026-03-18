#!/usr/bin/env bash
# Monitor top pane: fixed banner (always visible) + scrolling daemon logs below

CONFIG_FILE="${1:-.gaai/project/contexts/backlog/.delivery-locks/.daemon-config}"
LOG_FILE="${2:-.gaai/project/contexts/backlog/.delivery-daemon.log}"

# Colors
CYAN='\033[0;36m'
BOLD='\033[1m'
GREEN='\033[0;32m'
DIM='\033[2m'
NC='\033[0m'

render_banner() {
  # shellcheck disable=SC1090
  source "$CONFIG_FILE" 2>/dev/null || return

  # 2-column banner (28 │ 29 = 58 inner width)
  local W=58

  banner_row() {
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
  echo "  ╔$(printf '═%.0s' $(seq 1 $W))╗"
  local TITLE="GAAI Delivery Daemon"
  local TITLE_LEN=${#TITLE}
  printf "  ║%*s%s%*s║\n" $(( (W - TITLE_LEN) / 2 )) "" "$TITLE" $(( (W - TITLE_LEN + 1) / 2 )) ""
  echo "  ╠$(printf '═%.0s' $(seq 1 $W))╣"
  banner_row "Branch:"      "${BRANCH:-?}"      "Model:"       "${MODEL:-?}"
  banner_row "Interval:"    "${INTERVAL:-?}s"   "Launcher:"    "${LAUNCHER:-?}"
  banner_row "Concurrent:"  "${CONCURRENT:-?}"  "Skip perms:"  "${SKIP_PERMS:-?}"
  banner_row "Max turns:"   "${MAX_TURNS:-?}"   "Heartbeat:"   "${HEARTBEAT:-?}s"
  banner_row "Timeout:"     "${TIMEOUT:-?}s"    "Dry run:"     "${DRY_RUN:-?}"
  echo -e "  ${BOLD}╚$(printf '═%.0s' $(seq 1 $W))╝${NC}"
  echo ""
}

while true; do
  clear
  render_banner

  if [[ -f "$LOG_FILE" ]]; then
    # Calculate available lines for logs (banner takes ~11 lines)
    term_lines=$(tput lines 2>/dev/null || echo 24)
    log_lines=$(( term_lines - 12 ))
    [[ $log_lines -lt 5 ]] && log_lines=5
    tail -n "$log_lines" "$LOG_FILE"
  else
    echo -e "  ${DIM}(waiting for daemon log...)${NC}"
  fi

  sleep 2
done
