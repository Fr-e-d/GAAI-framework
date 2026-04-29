#!/usr/bin/env bash
# Helper: continuously shows human-readable status of active deliveries
# Parses stream-json NDJSON logs into readable summaries via jq

LOG_DIR="${1:-.gaai/project/contexts/backlog/.delivery-logs}"
PROJECT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
BACKLOG="$PROJECT_DIR/.gaai/project/contexts/backlog/active.backlog.yaml"

HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

# ANSI colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

format_duration() {
  local seconds="$1"
  if [[ $seconds -lt 60 ]]; then
    echo "${seconds}s"
  elif [[ $seconds -lt 3600 ]]; then
    echo "$(( seconds / 60 ))m$(( seconds % 60 ))s"
  else
    echo "$(( seconds / 3600 ))h$(( (seconds % 3600) / 60 ))m"
  fi
}

health_color() {
  local age_s="$1"
  if [[ $age_s -lt 30 ]]; then
    echo "$GREEN"
  elif [[ $age_s -lt 120 ]]; then
    echo "$YELLOW"
  else
    echo "$RED"
  fi
}

# Pass-through model id, filtering out sentinel values (n/a / null / empty)
# so callers can omit the field cleanly. Real model strings render as-is
# (claude-sonnet-4-6, glm-5.1, ...).
format_model() {
  case "$1" in
    n/a|null|"") echo "" ;;
    *)           echo "$1" ;;
  esac
}

parse_log() {
  local log_file="$1"
  local story_id="$2"

  if [[ ! -f "$log_file" ]]; then
    echo -e "  ${DIM}(log not yet created)${NC}"
    return
  fi

  local size
  size=$(wc -c < "$log_file" | tr -d ' ')
  if [[ "$size" -eq 0 ]]; then
    echo -e "  ${DIM}(waiting for output...)${NC}"
    return
  fi

  # ── Log age & health ──
  local mod_time now age_s age_label color
  if [[ "$(uname)" == "Darwin" ]]; then
    mod_time=$(stat -f %m "$log_file" 2>/dev/null || echo 0)
  else
    mod_time=$(stat -c %Y "$log_file" 2>/dev/null || echo 0)
  fi
  now=$(date +%s)
  age_s=$(( now - mod_time ))
  age_label=$(format_duration $age_s)
  color=$(health_color $age_s)

  # ── Duration (time since delivery started) ──
  local started_at duration_label=""
  started_at=$(grep -A 5 "id: $story_id" "$BACKLOG" 2>/dev/null | grep 'started_at:' | head -1 | sed 's/.*started_at: *"//;s/".*//' || true)
  if [[ -n "$started_at" ]]; then
    local start_epoch
    if [[ "$(uname)" == "Darwin" ]]; then
      start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || echo 0)
    else
      start_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo 0)
    fi
    if [[ "$start_epoch" -gt 0 ]]; then
      duration_label=$(format_duration $(( now - start_epoch )))
    fi
  fi

  # ── Tool call count ──
  local tool_count=0
  if $HAS_JQ; then
    tool_count=$(jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")' "$log_file" 2>/dev/null | wc -l | tr -d ' ')
  else
    tool_count=$(grep -c '"type":"tool_use"' "$log_file" 2>/dev/null || echo 0)
  fi

  # ── Last activity (single line — whichever of main or sub-agent was most recent) ──
  # Sub-agent origin = either (a) Task tool sub-agent: same session, parent_tool_use_id != null,
  # or (b) nested `claude -p` (Implement Agent via nested-claude-spawn.js --log-file):
  #         DIFFERENT session_id than the root delivery session.
  # Root session_id = first session_id seen in the log (init event).
  local last_event="" last_origin="" last_text="" last_model="" root_sid=""
  local phase_label="" phase_origin=""
  if $HAS_JQ; then
    root_sid=$(head -5 "$log_file" 2>/dev/null \
      | jq -r '.session_id // empty' 2>/dev/null \
      | head -1 || true)
    last_event=$(tail -500 "$log_file" 2>/dev/null \
      | jq -r --arg root_sid "$root_sid" '
        def clean: tostring | gsub("\n"; " ") | gsub("  +"; " ");
        def arg:
          if .name == "Bash" then (.input.command // "" | clean)
          elif .name == "Grep" then (.input.pattern // "" | clean)
          elif (.name == "Read" or .name == "Edit" or .name == "Write" or .name == "NotebookEdit") then ((.input.file_path // "" | clean) | split("/") | .[-1] // "")
          elif .name == "Task" then (.input.description // "" | clean)
          elif .name == "TodoWrite" then "(todos updated)"
          else ((.input.description // .input.file_path // .input.command // .input.query // "") | clean) end;
        . as $m |
        (if (($m.parent_tool_use_id // null) == null) and (($m.session_id // "") == $root_sid) then "MAIN" else "SUB" end) as $origin |
        (($m.message.model // "") | tostring) as $model |
        if ($m.type=="system" and $m.subtype=="task_progress") then
          $origin + "\t" + ($m.description // "") + "\t"
        elif $m.type=="assistant" then
          $m.message.content[]? | select(.type=="tool_use") | $origin + "\t" + .name + " " + arg + "\t" + $model
        else empty end' 2>/dev/null \
      | tail -1 || true)
    # Three tab-separated fields: origin <TAB> text <TAB> model
    last_origin=$(printf '%s' "$last_event" | awk -F'\t' '{print $1}')
    last_text=$(printf   '%s' "$last_event" | awk -F'\t' '{print $2}')
    last_model=$(printf  '%s' "$last_event" | awk -F'\t' '{print $3}')

    # ── Phase detection ──
    # Walk recent events, classify each Bash command / Write target into a phase tag,
    # keep the LAST non-empty classification — that's the current phase.
    # Origin is captured from the same event so we can show e.g. "IMPL (sub)" when
    # the nested claude -p subprocess is the most recent actor.
    local phase_event
    phase_event=$(tail -1500 "$log_file" 2>/dev/null \
      | jq -r --arg root_sid "$root_sid" '
        def signal:
          if .name == "Bash" then (.input.command // "" | tostring)
          elif (.name == "Write" or .name == "Edit") then (.input.file_path // "" | tostring)
          else "" end;
        def classify($s):
          if   ($s | test("gh pr merge"))                          then "DONE"
          elif ($s | test("Mark Story done|chore.*: done"))        then "DONE"
          elif ($s | test("ci-watch-and-fix|gh pr checks|ci_watch")) then "CI"
          elif ($s | test("gh pr create"))                         then "PR"
          elif ($s | test("--phase qa"))                           then "QA→PR"
          elif ($s | test("qa-report\\.md"))                       then "QA"
          elif ($s | test("--phase impl"))                         then "IMPL→QA"
          # Match only actual node invocations of the nested wrapper, NOT mentions
          # in research / grep / cat / vim. False positive observed on E131S04
          # where the agent was studying the module file itself.
          # Post-E131S02: the module is always invoked for Tier 2 (routing is not
          # opt-in from the agent). IMPL(nested) fires while the subprocess runs.
          # After the module returns, the agent collects impl-report.md — the Read
          # event matches the pattern below (rank 4, same as IMPL(nested)) and
          # stable-sort tail-1 advances the display to IMPL regardless of provider
          # (primary opt-out and universal-fallback both resolve to IMPL this way).
          # The IMPL(nested) signal remains useful for the legacy-degenerate case:
          # if the wrapper crashes before agent spawn, IMPL(nested) is never seen
          # and the operator observes WORKING — a valid anomaly signal. (E131S06)
          elif ($s | test("node[^|]+nested-claude-spawn\\.js"))    then "IMPL(nested)"
          elif ($s | test("impl-report\\.md"))                     then "IMPL"
          elif ($s | test("--phase plan"))                         then "PLAN→IMPL"
          elif ($s | test("execution-plan\\.md"))                  then "PLAN"
          elif ($s | test("git worktree add|Mark in_progress|in_progress \\[delivery\\]|routing-logger.*preflight")) then "PREFLIGHT"
          # Catch-all for non-specific Bash commands / Write/Edit file_paths after
          # PREFLIGHT — visible signal that the agent is actively working even when
          # no phase-specific marker fires (typical for Tier 1 MicroDelivery, where
          # plan+impl+qa run in a single sub-agent and produce no execution-plan.md).
          # More-specific phases above (PLAN/IMPL/QA/PR/CI/DONE) still take priority.
          elif ($s | test(".+"))                                   then "WORKING"
          else "" end;
        . as $m |
        # Monotone state machine — every event emits its phase rank as the FIRST
        # column. We then sort by rank in bash and take the highest one observed
        # in the recent window. This prevents WORKING (rank 2) from overriding
        # PLAN/IMPL/QA (rank 3-5) when the agent does generic Bash/Edit between
        # the artefact-write events that mark phase transitions. PREFLIGHT (rank 1)
        # similarly cannot regress once a higher phase has been observed.
        def rank_of($p):
          if   $p == "DONE"                          then 8
          elif $p == "CI"                            then 7
          elif $p == "PR"                            then 6
          elif ($p | startswith("QA"))               then 5
          elif ($p | startswith("IMPL"))             then 4
          elif ($p | startswith("PLAN"))             then 3
          elif $p == "WORKING"                       then 2
          elif $p == "PREFLIGHT"                     then 1
          else 0 end;
        (if (($m.parent_tool_use_id // null) == null) and (($m.session_id // "") == $root_sid) then "main" else "sub" end) as $origin |
        if $m.type=="assistant" then
          $m.message.content[]? | select(.type=="tool_use")
            | classify(signal) as $p
            | select($p != "")
            | (rank_of($p) | tostring) + "\t" + $p + "\t" + $origin
        else empty end' 2>/dev/null \
      | sort -t$'\t' -k1n -s \
      | tail -1 || true)
    # Three tab-separated fields: rank <TAB> phase_label <TAB> origin
    phase_label=$(printf  '%s' "$phase_event" | awk -F'\t' '{print $2}')
    phase_origin=$(printf '%s' "$phase_event" | awk -F'\t' '{print $3}')
    [[ "$phase_label" == "$phase_origin" ]] && phase_origin=""
  else
    last_text=$(tail -200 "$log_file" 2>/dev/null \
      | grep -o '"type":"tool_use"[^}]*"name":"[^"]*"' \
      | tail -1 \
      | sed 's/.*"name":"\([^"]*\)".*/\1/' 2>/dev/null || true)
    last_origin="MAIN"
  fi

  # ── Cost ──
  local cost=""
  if $HAS_JQ; then
    cost=$(tail -100 "$log_file" 2>/dev/null \
      | jq -r 'select(.costUSD) | .costUSD' 2>/dev/null \
      | tail -1 || true)
  fi

  # ── Output ──
  local health_icon
  if [[ $age_s -lt 30 ]]; then health_icon="●"
  elif [[ $age_s -lt 120 ]]; then health_icon="◐"
  else health_icon="○"
  fi

  echo -e "  ${color}${health_icon}${NC} ${tool_count} tools | Last update: ${color}${age_label} ago${NC}${duration_label:+ | Running: ${duration_label}}${cost:+ | \$${cost}}"

  # Phase line — coarse-grained pipeline position, derived from log signals.
  # Tags ending with "→X" mean "phase X just completed, next phase starting".
  if [[ -n "$phase_label" ]]; then
    local phase_icon="◆" phase_color="$YELLOW"
    case "$phase_label" in
      PREFLIGHT)    phase_icon="⚙️" ; phase_color="$DIM"    ;;
      WORKING)      phase_icon="🚧"; phase_color="$YELLOW" ;;
      PLAN|PLAN→*)  phase_icon="📋"; phase_color="$YELLOW" ;;
      IMPL|IMPL→*|"IMPL(nested)") phase_icon="🛠" ; phase_color="$YELLOW" ;;
      QA|QA→*)      phase_icon="🧪"; phase_color="$YELLOW" ;;
      PR)           phase_icon="🚀"; phase_color="$GREEN"  ;;
      CI)           phase_icon="🤖"; phase_color="$GREEN"  ;;
      DONE)         phase_icon="✅"; phase_color="$GREEN"  ;;
    esac
    # Only annotate when the most-recent phase signal came from a sub-agent /
    # nested claude session — main is the implicit default and would just add noise.
    local origin_suffix=""
    [[ "$phase_origin" == "sub" ]] && origin_suffix=" (sub)"
    # Append the model from the most recent tool_use event so the operator sees
    # which provider is doing the work right now (claude-sonnet-4-6, glm-5.1,
    # claude-haiku-4-5-…, …). When the source event came from a SUB origin —
    # either a Task tool sub-agent (typically Haiku by Claude Code default) or
    # a nested-claude-spawn subprocess (typically the routing-secondary provider)
    # — annotate explicitly so the operator understands why a smaller/different
    # model may flash by even when the orchestrator itself runs on Sonnet/Opus.
    local model_label model_suffix=""
    model_label=$(format_model "$last_model")
    if [[ -n "$model_label" ]]; then
      if [[ "$last_origin" == "SUB" ]]; then
        model_suffix=" | model: ${model_label} (sub)"
      else
        model_suffix=" | model: ${model_label}"
      fi
    fi
    # Two spaces between icon and label — many emojis (🛠 in particular) render
    # as a single column on some terminals and the visual gap looks squished.
    printf '  %bPhase: %b%s  %s%s%b%b%s%b\n' "$DIM" "$phase_color" "$phase_icon" "$phase_label" "$origin_suffix" "$NC" "$DIM" "$model_suffix" "$NC"
  fi

  # Single activity line — prefix switches based on origin (main delivery vs nested sub-agent).
  # printf %s keeps literal "\n" in Bash commands literal (echo -e would interpret them).
  if [[ -n "$last_text" ]]; then
    if [[ "$last_origin" == "SUB" ]]; then
      printf '  %b↳ %s%b\n' "$DIM" "$last_text" "$NC"
    else
      printf '  %b→ %s%b\n' "$DIM" "$last_text" "$NC"
    fi
  fi
}

while true; do
  clear
  # In tmux: clear scrollback left by `clear` so prior refresh doesn't ghost below
  [[ -n "${TMUX:-}" ]] && tmux clear-history 2>/dev/null || true
  echo "═══ Active Deliveries (refreshes every 5s) ═══"
  echo ""

  # Find active tmux delivery sessions
  active_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | grep '^gaai-deliver-' \
    | sed 's/gaai-deliver-//' || true)

  if [[ -z "$active_sessions" ]]; then
    echo -e "  ${DIM}No active deliveries. Use /gaai-discover to create stories for the backlog.${NC}"
    sleep 5
    continue
  fi

  for story_id in $active_sessions; do
    log_file="$LOG_DIR/${story_id}.log"
    echo "── $story_id ──"
    parse_log "$log_file" "$story_id"
    echo ""
  done

  sleep 5
done
