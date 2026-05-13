#!/usr/bin/env bash
# gaai-cutover.sh — Operator CLI for delivery pipeline cutover
#
# Usage:
#   gaai-cutover.sh --status
#   gaai-cutover.sh --check-ready
#   gaai-cutover.sh --to {legacy|3phase} [--force]
#   gaai-cutover.sh --force-unlock
#
# Subcommands:
#   --status          Show current cutover_state from active.backlog.yaml
#   --check-ready     Run readiness check: classify mid-flight stories by
#                     (delivery_pipeline, phase_status) tuple. Exit 0 if all clear.
#   --to {legacy|3phase}
#                     Flip the default_pipeline. Runs --check-ready first.
#                     Blocked if any mid-flight stories exist unless --force.
#   --to {legacy|3phase} --force
#                     Flip despite mid-flight stories. Sets forced: true in state
#                     and routing.jsonl. Prints warning for each blocked story.
#   --force-unlock    Remove orphan .cutover-in-progress.lock file after stale PID.
#
# Exit codes:
#   0 — success
#   1 — blocked (mid-flight stories, or usage error)
#   2 — malformed YAML or I/O error
#   3 — lock timeout
set -euo pipefail

# ── Resolve paths ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GAAI_CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PROJECT_DIR="$(cd "$GAAI_CORE_DIR/../.." && pwd -P)"

LOCAL_DIR="$PROJECT_DIR/.gaai/local"
CUTOVER_LOCK="$LOCAL_DIR/.cutover-in-progress.lock"
DISPATCH_LIB="$SCRIPT_DIR/daemon-dispatch.sh"

# Allow external override of BACKLOG_FILE (for tests)
BACKLOG_FILE="${BACKLOG_FILE:-$PROJECT_DIR/.gaai/project/contexts/backlog/active.backlog.yaml}"

# Colors (suppressed if not a terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; NC=''
fi

# ── Argument parsing ───────────────────────────────────────────────────────
CMD=""
TARGET_PIPELINE=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)       CMD="status";        shift ;;
    --check-ready)  CMD="check-ready";   shift ;;
    --force-unlock) CMD="force-unlock";  shift ;;
    --force)        FORCE=true;          shift ;;
    --to)
      CMD="flip"
      TARGET_PIPELINE="${2:-}"
      if [[ "$TARGET_PIPELINE" != "legacy" && "$TARGET_PIPELINE" != "3phase" ]]; then
        echo -e "${RED}Error: --to requires 'legacy' or '3phase', got '${TARGET_PIPELINE}'${NC}" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo -e "${RED}Unknown argument: $1${NC}" >&2
      echo "Usage: $0 {--status|--check-ready|--to {legacy|3phase} [--force]|--force-unlock}" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$CMD" ]]; then
  echo -e "${RED}Error: a subcommand is required${NC}" >&2
  echo "Usage: $0 {--status|--check-ready|--to {legacy|3phase} [--force]|--force-unlock}" >&2
  exit 1
fi

# ── Helpers ────────────────────────────────────────────────────────────────

# Require python3 (consistent with backlog-scheduler.sh dependency)
if ! command -v python3 &>/dev/null; then
  echo -e "${RED}Error: python3 is required${NC}" >&2
  exit 2
fi

# Require BACKLOG_FILE
if [[ ! -f "$BACKLOG_FILE" ]]; then
  echo -e "${RED}Error: backlog file not found: $BACKLOG_FILE${NC}" >&2
  exit 2
fi

# Validate YAML is parseable
validate_yaml() {
  python3 -c "
import sys
try:
    import yaml
    with open(sys.argv[1]) as f:
        yaml.safe_load(f)
except ImportError:
    pass  # pyyaml not available, skip
except Exception as e:
    print(f'YAML error: {e}', file=sys.stderr)
    sys.exit(1)
" "$BACKLOG_FILE" 2>&1 || return 1
}

# Read current cutover_state section (returns defaults if absent)
read_cutover_state() {
  python3 -c "
import sys, re
try:
    import yaml
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f)
    state = doc.get('cutover_state') if isinstance(doc, dict) else None
    if state is None:
        state = {}
except ImportError:
    # fallback: line scan
    state = {}
    with open(sys.argv[1]) as f:
        in_section = False
        for line in f:
            if re.match(r'^cutover_state:\s*$', line):
                in_section = True
                continue
            if in_section and line and not line[0].isspace():
                break
            if in_section and line.strip():
                m = re.match(r'\s+(\w+):\s*(.*)', line)
                if m:
                    state[m.group(1)] = m.group(2).strip().strip('\"')
def _str(v, default='null'):
    if v is None:
        return 'null'
    return str(v)

print(_str(state.get('default_pipeline'), 'legacy') or 'legacy')
print(_str(state.get('last_flip_at')))
print(_str(state.get('last_flip_by')))
print(str(state.get('last_flip_forced', False)).lower())
print(_str(state.get('last_flip_pre_in_progress_count'), '0') or '0')
" "$BACKLOG_FILE"
}

# Atomically write the cutover_state section to BACKLOG_FILE.
# Args: default_pipeline last_flip_at last_flip_by last_flip_forced pre_in_progress_count
write_cutover_state() {
  local new_pipeline="$1" flip_at="$2" flip_by="$3" flip_forced="$4" pre_count="$5"

  python3 -c "
import sys, re

new_pipeline = sys.argv[1]
flip_at      = sys.argv[2]
flip_by      = sys.argv[3]
flip_forced  = sys.argv[4]  # 'true' or 'false'
pre_count    = sys.argv[5]

file_path = sys.argv[6]

with open(file_path, 'r') as f:
    content = f.read()

new_section = (
    'cutover_state:\n'
    f'  default_pipeline: {new_pipeline}\n'
    f'  last_flip_at: {flip_at}\n'
    f'  last_flip_by: {flip_by}\n'
    f'  last_flip_forced: {flip_forced}\n'
    f'  last_flip_pre_in_progress_count: {pre_count}\n'
)

# Replace existing section or prepend before 'items:'
if re.search(r'^cutover_state:', content, re.MULTILINE):
    # Replace the section: everything from 'cutover_state:' up to the next
    # top-level key (line starting with a non-space, non-dash char, or 'items:')
    content = re.sub(
        r'^cutover_state:.*?(?=^[a-zA-Z\-])',
        new_section,
        content,
        flags=re.MULTILINE | re.DOTALL
    )
else:
    # Prepend before 'items:' line
    content = re.sub(r'^(items:)', new_section + r'\1', content, flags=re.MULTILINE)

with open(file_path, 'w') as f:
    f.write(content)
" "$new_pipeline" "$flip_at" "$flip_by" "$flip_forced" "$pre_count" "$BACKLOG_FILE"
}

# Classify all non-terminal items and detect blockers.
# Outputs lines: BLOCKED|STALLED|OK <story_id> <reason>
# Returns 0 if no blockers, 1 if any BLOCKED items exist.
check_readiness() {
  local file_path="$1"
  python3 -c "
import sys, re

file_path = sys.argv[1]

with open(file_path) as f:
    content = f.read()

# Parse items list
items = []
current = {}
for line in content.splitlines():
    stripped = line.strip()
    if stripped.startswith('- id:'):
        if current:
            items.append(current)
        current = {'id': stripped.split(':', 1)[1].strip()}
    elif current:
        if stripped.startswith('status:'):
            current['status'] = stripped.split(':', 1)[1].strip()
        elif stripped.startswith('delivery_pipeline:'):
            current['delivery_pipeline'] = stripped.split(':', 1)[1].strip()
        elif stripped.startswith('phase_status:'):
            current['phase_status'] = stripped.split(':', 1)[1].strip()
if current:
    items.append(current)

has_blocked = False
for item in items:
    sid      = item.get('id', '')
    status   = item.get('status', '')
    pipeline = item.get('delivery_pipeline', '')
    ps       = item.get('phase_status', '')

    # Only non-terminal items matter
    if status not in ('in_progress', 'refined'):
        continue

    # Classification per AC2 tuple (delivery_pipeline, phase_status)
    if pipeline == 'legacy' and status == 'in_progress':
        # legacy in_progress: always block (phase_status irrelevant for legacy)
        print(f'BLOCKED {sid} legacy story in_progress')
        has_blocked = True
    elif pipeline == '3phase':
        if ps in ('planned', 'impl_done', 'qa_passed'):
            print(f'BLOCKED {sid} 3phase story mid-pipeline at {ps}')
            has_blocked = True
        elif ps in ('qa_failed', 'qa_escalated', 'failed'):
            print(f'STALLED {sid} stalled at {ps} — flip allowed with warning')
        # not_started and other states: no block (story not yet dispatched)
    # status==refined: not yet in_progress, not a blocker

sys.exit(1 if has_blocked else 0)
" "$file_path"
}

# Count in-progress stories
count_in_progress() {
  python3 -c "
import sys
file_path = sys.argv[1]
count = 0
with open(file_path) as f:
    cur_status = ''
    for line in f:
        stripped = line.strip()
        if stripped.startswith('- id:'):
            cur_status = ''
        elif stripped.startswith('status:'):
            cur_status = stripped.split(':', 1)[1].strip()
            if cur_status == 'in_progress':
                count += 1
print(count)
" "$BACKLOG_FILE"
}

# Detect operator identity (git user.name or whoami)
get_operator_id() {
  git -C "$PROJECT_DIR" config user.name 2>/dev/null \
    || git config user.name 2>/dev/null \
    || whoami 2>/dev/null \
    || echo "unknown"
}

# Generate a trace_id
generate_trace_id() {
  node -e "import('node:crypto').then(m=>process.stdout.write(m.randomUUID()))" 2>/dev/null \
    || python3 -c "import uuid; print(str(uuid.uuid4()),end='')" 2>/dev/null \
    || echo "$(date +%s)-cutover-$$"
}

# Source dispatch library for _emit_cutover_routing_record (requires PROJECT_DIR + BACKLOG_FILE)
source_dispatch_lib() {
  if [[ -f "$DISPATCH_LIB" ]]; then
    # shellcheck disable=SC1090
    source "$DISPATCH_LIB"
  else
    echo -e "${YELLOW}Warning: dispatch library not found at $DISPATCH_LIB — routing record will be skipped${NC}" >&2
  fi
}

# ── Portable flock wrapper ─────────────────────────────────────────────────
with_cutover_lock() {
  local rc
  mkdir -p "$LOCAL_DIR"
  if command -v flock &>/dev/null; then
    # Linux: fd-based flock (supports bash function calls)
    exec 9>"$CUTOVER_LOCK"
    if ! flock -w 5 9; then
      echo -e "${RED}Error: cutover lock timeout after 5s — another flip is in progress${NC}" >&2
      echo "If this is a stale lock, run: $0 --force-unlock" >&2
      exec 9>&-
      exit 3
    fi
    "$@"
    rc=$?
    exec 9>&-
    return $rc
  else
    # macOS: mkdir-based atomic lock with stale-PID recovery
    local lockdir="${CUTOVER_LOCK}.d"
    local waited=0
    while ! mkdir "$lockdir" 2>/dev/null; do
      local lpid
      lpid=$(cat "${CUTOVER_LOCK}.pid" 2>/dev/null || echo "")
      if [[ -n "$lpid" ]] && ! kill -0 "$lpid" 2>/dev/null; then
        rmdir "$lockdir" 2>/dev/null || true
        rm -f "${CUTOVER_LOCK}.pid" 2>/dev/null || true
        continue
      fi
      sleep 1
      ((waited++))
      if (( waited >= 5 )); then
        echo -e "${RED}Error: cutover lock timeout after 5s${NC}" >&2
        echo "If this is a stale lock, run: $0 --force-unlock" >&2
        exit 3
      fi
    done
    echo "$$" > "${CUTOVER_LOCK}.pid"
    "$@"
    rc=$?
    rmdir "$lockdir" 2>/dev/null || true
    rm -f "${CUTOVER_LOCK}.pid" 2>/dev/null || true
    return $rc
  fi
}

# ── Subcommand: --status ───────────────────────────────────────────────────
cmd_status() {
  if ! validate_yaml; then
    echo -e "${RED}Error: active.backlog.yaml is malformed${NC}" >&2
    exit 2
  fi

  local state_lines
  state_lines=$(read_cutover_state)
  local cur_pipeline last_at last_by last_forced last_count
  cur_pipeline=$(echo "$state_lines" | sed -n '1p')
  last_at=$(echo "$state_lines"      | sed -n '2p')
  last_by=$(echo "$state_lines"      | sed -n '3p')
  last_forced=$(echo "$state_lines"  | sed -n '4p')
  last_count=$(echo "$state_lines"   | sed -n '5p')

  echo -e "${BOLD}GAAI Delivery Pipeline Cutover — Status${NC}"
  echo ""
  echo -e "  Current default pipeline: ${CYAN}${cur_pipeline}${NC}"
  echo -e "  Last flip at:             ${last_at}"
  echo -e "  Last flip by:             ${last_by}"
  echo -e "  Last flip forced:         ${last_forced}"
  echo -e "  Pre-flip in_progress:     ${last_count}"

  # Show daemon running status
  local daemon_pid
  daemon_pid=$(pgrep -f 'delivery-daemon.sh' 2>/dev/null | head -1 || echo "")
  echo ""
  if [[ -n "$daemon_pid" ]]; then
    echo -e "  Daemon running: ${GREEN}yes (PID ${daemon_pid})${NC}"
    echo -e "  ${YELLOW}Note: daemon will pick up cutover on next poll — no restart needed${NC}"
  else
    echo -e "  Daemon running: ${YELLOW}no${NC}"
  fi
}

# ── Subcommand: --check-ready ──────────────────────────────────────────────
cmd_check_ready() {
  if ! validate_yaml; then
    echo -e "${RED}Error: active.backlog.yaml is malformed${NC}" >&2
    exit 2
  fi

  echo -e "${BOLD}Readiness check${NC}"
  echo ""

  local check_output
  local check_rc=0
  check_output=$(check_readiness "$BACKLOG_FILE") || check_rc=$?

  if [[ -n "$check_output" ]]; then
    while IFS= read -r line; do
      local verdict="${line%% *}"
      local rest="${line#* }"
      if [[ "$verdict" == "BLOCKED" ]]; then
        echo -e "  ${RED}BLOCKED${NC} $rest"
      elif [[ "$verdict" == "STALLED" ]]; then
        echo -e "  ${YELLOW}STALLED${NC} $rest"
      fi
    done <<< "$check_output"
    echo ""
  fi

  if [[ $check_rc -eq 0 ]]; then
    echo -e "  ${GREEN}All clear — no mid-flight stories${NC}"
    return 0
  else
    echo -e "  ${RED}Flip blocked — resolve mid-flight stories or use --force${NC}"
    return 1
  fi
}

# ── Subcommand: --to {pipeline} [--force] ─────────────────────────────────
cmd_flip() {
  local target="$TARGET_PIPELINE"

  if ! validate_yaml; then
    echo -e "${RED}Error: active.backlog.yaml is malformed${NC}" >&2
    exit 2
  fi

  # Read current pipeline
  local cur_pipeline
  cur_pipeline=$(read_cutover_state | sed -n '1p')

  if [[ "$cur_pipeline" == "$target" ]]; then
    echo -e "${YELLOW}Already on pipeline '${target}' — no flip needed${NC}"
    exit 0
  fi

  # Run readiness check (capture output + rc)
  local check_output check_rc=0
  check_output=$(check_readiness "$BACKLOG_FILE") || check_rc=$?

  local has_stalled=false has_blocked=false
  if [[ -n "$check_output" ]]; then
    while IFS= read -r line; do
      local verdict="${line%% *}"
      if [[ "$verdict" == "BLOCKED" ]]; then has_blocked=true; fi
      if [[ "$verdict" == "STALLED" ]]; then has_stalled=true; fi
    done <<< "$check_output"
  fi

  if $has_blocked && ! $FORCE; then
    echo -e "${RED}Flip blocked — mid-flight stories detected:${NC}"
    while IFS= read -r line; do
      local verdict="${line%% *}" rest="${line#* }"
      if [[ "$verdict" == "BLOCKED" ]]; then
        echo -e "  ${RED}BLOCKED${NC} $rest"
      fi
    done <<< "$check_output"
    echo ""
    echo "Resolve these stories or use --force to override"
    exit 1
  fi

  if $has_stalled; then
    echo -e "${YELLOW}Warning: stalled stories detected (flip will proceed):${NC}"
    while IFS= read -r line; do
      local verdict="${line%% *}" rest="${line#* }"
      if [[ "$verdict" == "STALLED" ]]; then
        echo -e "  ${YELLOW}STALLED${NC} $rest"
      fi
    done <<< "$check_output"
    echo ""
  fi

  if $has_blocked && $FORCE; then
    echo -e "${YELLOW}Warning: --force bypassing mid-flight stories:${NC}"
    while IFS= read -r line; do
      local verdict="${line%% *}" rest="${line#* }"
      if [[ "$verdict" == "BLOCKED" ]]; then
        echo -e "  ${YELLOW}FORCED THROUGH${NC} $rest"
      fi
    done <<< "$check_output"
    echo ""
  fi

  # Count pre-flip in_progress
  local pre_count
  pre_count=$(count_in_progress)

  # Operator + trace
  local operator_id trace_id flip_at forced_str
  operator_id=$(get_operator_id)
  trace_id=$(generate_trace_id)
  flip_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if $FORCE; then
    forced_str="true"
  else
    forced_str="false"
  fi

  echo -e "Flipping pipeline: ${CYAN}${cur_pipeline}${NC} → ${GREEN}${target}${NC}"
  echo -e "  operator: ${operator_id}"
  echo -e "  forced:   ${forced_str}"
  echo -e "  pre-flip in_progress count: ${pre_count}"
  echo ""

  # Acquire lock and perform atomic write
  with_cutover_lock write_cutover_state "$target" "$flip_at" "$operator_id" "$forced_str" "$pre_count"

  echo -e "${GREEN}Cutover complete — active.backlog.yaml updated${NC}"
  echo ""

  # Emit audit record (best-effort)
  source_dispatch_lib
  if declare -f _emit_cutover_routing_record &>/dev/null; then
    _emit_cutover_routing_record \
      "$trace_id" "$cur_pipeline" "$target" "$forced_str" \
      "$operator_id" "$pre_count" || true
    echo -e "Audit record written to runtime-routing.jsonl (phase: cutover)"
  else
    echo -e "${YELLOW}Warning: dispatch library unavailable — routing record skipped${NC}"
  fi

  # Human-readable log line
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S UTC')
  echo ""
  echo -e "[${ts}] CUTOVER: ${cur_pipeline} → ${target} | forced=${forced_str} | operator=${operator_id} | pre_in_progress=${pre_count}"

  # Daemon notification
  local daemon_pid
  daemon_pid=$(pgrep -f 'delivery-daemon.sh' 2>/dev/null | head -1 || echo "")
  echo ""
  if [[ -n "$daemon_pid" ]]; then
    echo -e "${GREEN}Daemon running (PID ${daemon_pid}) — will pick up new pipeline on next poll${NC}"
    echo -e "${CYAN}No daemon restart required (no-caching design — AC4)${NC}"
  else
    echo -e "${YELLOW}Daemon not running — start it to begin delivering with pipeline '${target}'${NC}"
  fi
}

# ── Subcommand: --force-unlock ─────────────────────────────────────────────
cmd_force_unlock() {
  local removed=false

  # Linux (flock-based): the lock is the regular file $CUTOVER_LOCK itself
  if [[ -f "$CUTOVER_LOCK" ]]; then
    rm -f "$CUTOVER_LOCK"
    echo -e "${GREEN}Removed lockfile: ${CUTOVER_LOCK}${NC}"
    removed=true
  fi

  # macOS (mkdir-based): the lock is a directory
  if [[ -d "${CUTOVER_LOCK}.d" ]]; then
    local lpid
    lpid=$(cat "${CUTOVER_LOCK}.pid" 2>/dev/null || echo "")
    if [[ -n "$lpid" ]] && kill -0 "$lpid" 2>/dev/null; then
      echo -e "${RED}Error: PID ${lpid} is still alive — lock is not stale${NC}" >&2
      exit 1
    fi
    rmdir "${CUTOVER_LOCK}.d" 2>/dev/null || true
    rm -f "${CUTOVER_LOCK}.pid" 2>/dev/null || true
    echo -e "${GREEN}Removed stale macOS lock: ${CUTOVER_LOCK}.d${NC}"
    removed=true
  fi

  if ! $removed; then
    echo -e "${YELLOW}No cutover lock found — nothing to remove${NC}"
  fi
}

# ── Dispatch ───────────────────────────────────────────────────────────────
case "$CMD" in
  status)       cmd_status     ;;
  check-ready)  cmd_check_ready ;;
  flip)         cmd_flip       ;;
  force-unlock) cmd_force_unlock ;;
esac
