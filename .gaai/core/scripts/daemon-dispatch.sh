#!/usr/bin/env bash
# daemon-dispatch.sh — 3-phase dispatch library for delivery-daemon.sh (E134S02)
#
# Sourceable library. No top-level execution code.
# Caller must set before sourcing or calling any function:
#   BACKLOG_FILE  — absolute path to active.backlog.yaml
#   SCHEDULER     — absolute path to backlog-scheduler.sh
#   PROJECT_DIR   — repo root (for runtime-routing-logger.js)
# Optional:
#   GAAI_STUB_DELAY_S — seconds to sleep between stubs (default: 0)
#   ROUTING_LOG_PATH  — test-only override for --log-path (default: empty, uses logger default)

# ── Per-phase wall-clock timeouts (OSS-7) ────────────────────────────────
# Bound the lifetime of each phase to detect hangs that loop-breaker (which
# only fires on identical consecutive errors) cannot catch — silent network
# stalls, MCP server deadlocks, agent that produces output but never
# converges. Override via env when needed (longer impl on giant stories).
GAAI_TIMEOUT_PLAN_SEC="${GAAI_TIMEOUT_PLAN_SEC:-1800}"     # 30 min
GAAI_TIMEOUT_IMPL_SEC="${GAAI_TIMEOUT_IMPL_SEC:-5400}"     # 90 min
GAAI_TIMEOUT_QA_SEC="${GAAI_TIMEOUT_QA_SEC:-1800}"         # 30 min
GAAI_TIMEOUT_COMMIT_SEC="${GAAI_TIMEOUT_COMMIT_SEC:-600}"  # 10 min (commit-phase
                                                            # is bash-only; this
                                                            # is informational)
# Distinct exit code for wall-clock timeout (vs 124 loop-breaker).
GAAI_TIMEOUT_RC=137

# ── Per-phase agent turn caps ────────────────────────────────────────────
# QA carries the heaviest deterministic workload of the three phases
# (mandatory reads of story/epic/plan/impl-report + per-DEC reads + run the
# test suite + tsc/lint + qa-review + consistency-check), yet historically ran
# at --max-turns 30 — the lowest of the three (plan 60, impl 150). On large
# stories the QA agent exhausted 30 turns before writing a verdict, exited
# non-zero (error_max_turns), and the wrapper died at phase_status=implemented
# in an unbounded relaunch loop. Raise the default and make it overridable.
GAAI_QA_MAX_TURNS="${GAAI_QA_MAX_TURNS:-100}"

# Resolve the available timeout binary. Linux ships `timeout`, macOS coreutils
# ships `gtimeout`. Empty string when neither is present — callers must then
# fall back to the in-process watchdog.
_resolve_timeout_cmd() {
  if command -v timeout >/dev/null 2>&1; then
    echo "timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    echo "gtimeout"
  else
    echo ""
  fi
}

# ── Orphaned-process reaper (OSS — memory-leak guard) ────────────────────
# SIGKILL any process still rooted in a story's worktree. A delivery phase is a
# `claude -p` invocation; the agent routinely spawns heavy subprocess trees (test
# runners, dev/build servers, container runtimes — whatever the project's test and
# build commands invoke). Every phase-ending kill path signals only the claude PID,
# not its descendants, so a process whose own tool-call timeout detached it is left
# orphaned. Across phase timeouts and QA retries these long-lived workers accumulate
# until the daemon host runs out of memory. This reaps them by worktree path.
#
# SAFETY: the argument MUST be a non-empty `*-workspace` pattern. A bare `pkill -f ""`
# would match every process on the host — the guard makes that impossible. The match
# is a unique-per-story full-argv substring, so it never touches another story's tree.
# pkill is portable across macOS and Linux (setsid / kill-by-pgid is not). Best-effort.
#
# Args: $1 = worktree path or `<storyId>-workspace` pattern
_reap_worktree_orphans() {
  local pattern="${1:-}"
  [[ -n "$pattern" && "$pattern" == *-workspace ]] || return 0
  pkill -9 -f "$pattern" 2>/dev/null || true
}

# ── Orphaned-worktree reaper (OSS — disk-leak guard) ──────────────────────
# Enforces orchestration.rules.md §Branch Rules → Worktree lifecycle & cleanup:
# "Orphan reaping is eventually-consistent" + "Data-safety refusal" (the dirty
# guard below is that INVARIANT). This function is the mechanism; the rules file
# is the normative authority.
# Enumerate the worktree directories ACTUALLY ON DISK and remove any whose
# delivery has concluded. This closes the gap in reconcile_done_merged_worktrees(),
# which only iterates ACTIVE-backlog `done` ids and therefore never reclaims the
# worktree of an archived-done / escalated / failed / branch-deleted story. That
# gap is what silently accumulates abandoned worktrees (one observed run: 24
# orphans, ~31 GB, all belonging to stories no longer in the active backlog).
#
# Concluded = ANY authoritative integration signal, evaluated only AFTER the
# safety guards below all pass:
#   1. the story's PR (gh, by `--head story/<sid>`) is MERGED or CLOSED. GitHub
#      retains headRefName on merged/closed PRs, so this matches even after the
#      local branch was deleted — the branch-independent source of truth.
#   2. the worktree HEAD is already an ancestor of origin/<target> (work
#      integrated by a manual/no-PR flow).
#
# HARD SAFETY GUARDS (every one must pass before a removal is even considered):
#   - never PROJECT_DIR itself (realpath compare)
#   - never a live delivery: no `gaai-deliver-<sid>` tmux session AND no fresh
#     (<120s) heartbeat — a wrapper can run detached from any tmux
#   - never a dirty worktree (uncommitted/untracked content) — data safety
# `git worktree remove` deletes only the working dir; the branch ref survives, so
# committed work is never lost (only reclaimable disk is freed).
#
# Throttled to GAAI_WT_REAP_INTERVAL_SEC (default 1800s) so the per-worktree `gh`
# calls cannot run every poll cycle. Best-effort throughout; never aborts the loop.
#
# Requires (set by delivery-daemon.sh before sourcing): PROJECT_DIR, LOCK_DIR,
# TARGET_BRANCH (defaults to staging), and log(). Honors GAAI_WORKTREES_BASE.
reap_orphaned_worktrees() {
  local _now _last _interval _marker
  _interval="${GAAI_WT_REAP_INTERVAL_SEC:-1800}"
  _marker="${LOCK_DIR}/.wt-reap.last"
  _now=$(date +%s)
  _last=0
  [[ -f "$_marker" ]] && _last=$(cat "$_marker" 2>/dev/null || echo 0)
  [[ "$_last" =~ ^[0-9]+$ ]] || _last=0
  (( _now - _last < _interval )) && return 0
  echo "$_now" > "$_marker" 2>/dev/null || true

  # Resolve the worktree base dir (same formula as the dispatch path resolvers).
  local _base _repo_name
  if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
    _base="$GAAI_WORKTREES_BASE"
  else
    _repo_name=$(basename "${REPO_ROOT:-$PROJECT_DIR}")
    _base="$(cd "${REPO_ROOT:-$PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${_repo_name}"
  fi
  [[ -d "$_base" ]] || return 0

  local _target="${TARGET_BRANCH:-staging}"
  git -C "$PROJECT_DIR" fetch origin "$_target" --quiet 2>/dev/null || true

  local _proj_real
  _proj_real=$(realpath "${REPO_ROOT:-$PROJECT_DIR}" 2>/dev/null || echo "${REPO_ROOT:-$PROJECT_DIR}")

  local _wt _sid _wt_real _hb _hb_mtime _porcelain _rc
  local _pr_json _pr_state _concluded _reason
  for _wt in "$_base"/*-workspace; do
    [[ -d "$_wt" ]] || continue
    _sid=$(basename "$_wt"); _sid="${_sid%-workspace}"

    # Safety: never the main checkout.
    _wt_real=$(realpath "$_wt" 2>/dev/null || echo "$_wt")
    [[ "$_wt_real" == "$_proj_real" ]] && continue

    # Live guard 1: an active delivery owns a tmux session named for this story.
    tmux has-session -t "gaai-deliver-${_sid}" 2>/dev/null && continue

    # Live guard 2: a fresh heartbeat (<120s) means a detached wrapper is running.
    _hb="${LOCK_DIR}/${_sid}.heartbeat"
    if [[ -f "$_hb" ]]; then
      _hb_mtime=$(stat -f %m "$_hb" 2>/dev/null || stat -c %Y "$_hb" 2>/dev/null || echo 0)
      [[ "$_hb_mtime" =~ ^[0-9]+$ ]] || _hb_mtime=0
      (( _now - _hb_mtime < 120 )) && continue
    fi

    # Data safety: never remove a worktree with uncommitted/untracked content.
    _porcelain=$(git -C "$_wt" status --porcelain 2>/dev/null); _rc=$?
    { (( _rc != 0 )) || [[ -n "$_porcelain" ]]; } && continue

    # Integration signal 1: PR MERGED/CLOSED (branch-independent, authoritative).
    _concluded=0; _reason=""
    _pr_json=$(gh pr list --state all --head "story/${_sid}" --json state --limit 1 2>/dev/null || echo "")
    if [[ -n "$_pr_json" && "$_pr_json" != "[]" ]]; then
      _pr_state=$(printf '%s' "$_pr_json" | grep -oE '"state":"[A-Z]+"' | head -1 | cut -d'"' -f4)
      case "$_pr_state" in
        MERGED) _concluded=1; _reason="pr_merged" ;;
        CLOSED) _concluded=1; _reason="pr_closed" ;;
      esac
    fi
    # Integration signal 2: HEAD already integrated into origin/<target>.
    if (( _concluded == 0 )) && \
       git -C "$_wt" merge-base --is-ancestor HEAD "origin/${_target}" 2>/dev/null; then
      _concluded=1; _reason="head_integrated"
    fi
    (( _concluded == 0 )) && continue

    # Remove. --force: the branch ref still exists; the dir is clean (guarded above).
    if git -C "$PROJECT_DIR" worktree remove --force "$_wt" 2>/dev/null; then
      log "${CYAN:-}[WT-REAP] ${_sid}: removed ${_wt} (${_reason})${NC:-}"
      git -C "$PROJECT_DIR" branch -D "story/${_sid}" 2>/dev/null || true
    else
      log "${YELLOW:-}[WT-REAP] ${_sid}: remove failed ${_wt} (lock contention?) — retry next interval${NC:-}"
    fi
  done

  git -C "$PROJECT_DIR" worktree prune 2>/dev/null || true
}

# ── Worktree integrity helper ──────────────────────────────────
# Sourced here so dispatch's handle_commit_phase can run pre-push checks.
# PROJECT_DIR must be set by caller before sourcing (same requirement as SCHEDULER).
_DISPATCH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${_WORKTREE_INTEGRITY_SH_SOURCED:-}" ]] && \
  source "${_DISPATCH_SCRIPT_DIR}/lib/worktree-integrity.sh" 2>/dev/null && \
  _WORKTREE_INTEGRITY_SH_SOURCED=1

# ── Active-spawn marker directory (AC1) ──────────────────────────────────
# LOCK_DIR is set by delivery-daemon.sh before sourcing this library.
# Provide a fallback so this library is usable in tests without the full daemon env.
_marker_dir() {
  echo "${LOCK_DIR:-${PROJECT_DIR}/.gaai/project/contexts/backlog/.delivery-locks}"
}

_write_active_marker() {
  local story_id="$1" phase="$2"
  local mdir
  mdir=$(_marker_dir)
  mkdir -p "$mdir" 2>/dev/null || true
  touch "${mdir}/${story_id}.${phase}.active" 2>/dev/null || true
}

_remove_active_marker() {
  local story_id="$1" phase="$2"
  local mdir
  mdir=$(_marker_dir)
  rm -f "${mdir}/${story_id}.${phase}.active" 2>/dev/null || true
}

# ── Per-phase log rotation ────────────────────────────────────────────────
# Each phase's claude -p run writes to ${worktree}/.delivery-logs/{id}.{phase}.log
# via `tee -a`. On retry after a failed attempt (e.g., error_max_turns), the
# new run would otherwise APPEND to the prior session's log, producing :
#   - Inflated cumulative tool counts in the monitor (parser sees both runs)
#   - Confusing "session boundary" detection in forensic analysis
#
# Rotate the existing log to a timestamped suffix BEFORE the new claude -p
# starts. Forensic trail preserved (old log readable as <name>.YYYYMMDDTHHMMSS),
# new run starts with a fresh empty file.
#
# Flush-before-relaunch is simpler than scoping every parser to "current
# session only" via init-event offset detection.
_rotate_phase_log() {
  local log_path="$1"
  if [[ -f "$log_path" && -s "$log_path" ]]; then
    local rotated="${log_path}.$(date '+%Y%m%dT%H%M%S')"
    mv "$log_path" "$rotated" 2>/dev/null || true
  fi
}

# ── Worktree-scope audit (advisory soft gate) ────────────────────────────
# Runs daemon-worktree-audit.py against the per-phase JSONL log to detect
# Write/Edit/Bash tool calls that operate on absolute paths outside the
# worktree. Writes <log_path>.audit.json with a structured verdict. Advisory
# only — does NOT block phase completion. Output goes to daemon log via
# stderr so violations are visible to the operator without parsing JSON.
_run_worktree_audit() {
  local story_id="$1" phase="$2" log_path="$3" worktree_path="$4"
  local audit_script="${PROJECT_DIR}/.gaai/core/scripts/daemon-worktree-audit.py"
  [[ -f "$audit_script" ]] || return 0
  [[ -f "$log_path" ]] || return 0
  python3 "$audit_script" \
    --story-id "$story_id" \
    --phase "$phase" \
    --log-path "$log_path" \
    --worktree-path "$worktree_path" 2>&1 || true
}

# ── Tool-result error extractor (loop breaker support) ───────────────────
# Reads one JSONL line on stdin. If it's a user-message containing a
# tool_result with is_error:true, prints the first 200 chars of the error
# content to stdout. Otherwise prints nothing. Any parse failure is silent.
_extract_tool_error_content() {
  python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    msg = d.get('message') or {}
    if isinstance(msg, dict):
        for c in (msg.get('content') or []):
            if isinstance(c, dict) and c.get('type') == 'tool_result' and c.get('is_error'):
                v = c.get('content') or ''
                if isinstance(v, list):
                    v = ' '.join(x.get('text','') if isinstance(x, dict) else str(x) for x in v)
                print(str(v)[:200])
                break
except Exception:
    pass
" 2>/dev/null
}

# ── Loop-breaker wrapper around `claude -p` ──────────────────────────────
# Replaces the synchronous `claude -p ... | tee -a "$log_path"` pattern with
# a streaming reader that:
#   1. Tees every JSONL line to $log_path AND stdout (preserves tmux display
#      and forensic trail unchanged).
#   2. Watches for consecutive identical `is_error:true` tool_result content.
#   3. Kills claude -p if N (default 3) consecutive identical errors are
#      seen, preventing unbounded retry loops where the agent retries the
#      same blocked content forever, burning tokens without producing the
#      expected artefact.
#
# Why this exists: several upstream layers (Bash sandbox parser, tool
# permission system, MCP servers, etc.) can return deterministic
# content-based refusals on a tool call. When that happens, the agent has
# no signal that its current approach is structurally blocked, and
# typically retries the same shape — getting the same refusal — until
# --max-turns runs out. This watcher detects that pattern at the daemon
# level and aborts deterministically rather than relying on probabilistic
# agent self-correction.
#
# Args (positional):
#   $1 — story_id      (for log lines)
#   $2 — phase         (for log lines: plan|qa)
#   $3 — log_path      (per-phase JSONL log)
#   $4 — prompt_file   (stdin for claude)
#   $5 — worktree_path (cwd for claude — branch/path isolation per story)
#   $6+ — extra args passed to claude -p (model, max-turns, etc.)
#
# Env (optional):
#   GAAI_LOOP_BREAKER_THRESHOLD — N consecutive identical errors before kill
#                                  (default: 3)
#   GAAI_LOOP_BREAKER_DISABLE   — set to "1" to fully disable the breaker
#                                  (returns to the legacy `tee -a` pipeline)
#   GAAI_DAEMON_EXECUTOR        — claude|codex (default: claude)
#   GAAI_CODEX_SANDBOX          — codex exec sandbox (default: workspace-write)
#   GAAI_CODEX_MODEL            — optional codex model override
#   GAAI_CODEX_EPHEMERAL        — set to "0" to persist Codex sessions
#   GAAI_CODEX_IGNORE_USER_CONFIG — set to "1" to add --ignore-user-config
#
# Returns:
#   0   — agent exited cleanly
#   2   — worktree path missing or invalid
#   124 — loop breaker triggered (custom exit code, distinct from agent's)
#   <N> — agent's actual exit code on other failures
_run_claude_with_loop_breaker() {
  local story_id="$1" phase="$2" log_path="$3" prompt_file="$4" worktree_path="$5"
  shift 5
  local threshold="${GAAI_LOOP_BREAKER_THRESHOLD:-3}"
  local disabled="${GAAI_LOOP_BREAKER_DISABLE:-0}"
  local executor="${GAAI_DAEMON_EXECUTOR:-claude}"

  # Resolve per-phase wall-clock timeout. Caller may also pass GAAI_PHASE_TIMEOUT_SEC
  # to override; otherwise we look up the phase-specific default.
  local timeout_sec="${GAAI_PHASE_TIMEOUT_SEC:-}"
  if [[ -z "$timeout_sec" ]]; then
    case "$phase" in
      plan) timeout_sec="$GAAI_TIMEOUT_PLAN_SEC" ;;
      impl) timeout_sec="$GAAI_TIMEOUT_IMPL_SEC" ;;
      qa)   timeout_sec="$GAAI_TIMEOUT_QA_SEC" ;;
      *)    timeout_sec="$GAAI_TIMEOUT_PLAN_SEC" ;;
    esac
  fi

  # Worktree must exist — the agent is launched with cwd=$worktree_path so all
  # cwd-relative writes by the agent land in the per-story worktree branch.
  # Without this, agents writing relative paths pollute the parent repo.
  if [[ ! -d "$worktree_path" ]]; then
    echo "[ERROR] ${story_id} _run_claude_with_loop_breaker: worktree path does not exist: $worktree_path" >&2
    return 2
  fi

  local agent_cmd=()
  case "$executor" in
    claude)
      agent_cmd=(claude -p "$@")
      ;;
    codex)
      agent_cmd=(codex exec --json --sandbox "${GAAI_CODEX_SANDBOX:-workspace-write}" --cd "$worktree_path")
      [[ -n "${GAAI_CODEX_MODEL:-}" ]] && agent_cmd+=(--model "$GAAI_CODEX_MODEL")
      [[ "${GAAI_CODEX_EPHEMERAL:-1}" != "0" ]] && agent_cmd+=(--ephemeral)
      [[ "${GAAI_CODEX_IGNORE_USER_CONFIG:-0}" == "1" ]] && agent_cmd+=(--ignore-user-config)
      agent_cmd+=(-)
      ;;
    *)
      echo "[ERROR] ${story_id} _run_claude_with_loop_breaker: unsupported GAAI_DAEMON_EXECUTOR=${executor}" >&2
      return 2
      ;;
  esac

  # Bypass mode — original synchronous pipeline (escape hatch / debugging).
  # Subshell + exec replaces the subshell process with the agent after cd, so
  # $! reports the agent's PID and signals propagate correctly.
  if [[ "$disabled" == "1" ]]; then
    set -o pipefail
    local _to_cmd
    _to_cmd=$(_resolve_timeout_cmd)
    if [[ -n "$_to_cmd" ]]; then
      ( cd "$worktree_path" && exec "$_to_cmd" --kill-after=10s "${timeout_sec}s" "${agent_cmd[@]}" < "$prompt_file" 2>&1 ) | tee -a "$log_path"
    else
      ( cd "$worktree_path" && exec "${agent_cmd[@]}" < "$prompt_file" 2>&1 ) | tee -a "$log_path"
    fi
    local rc=${PIPESTATUS[0]}
    set +o pipefail
    # `timeout` exits 124 on SIGTERM, 137 on SIGKILL — translate both to our
    # canonical wall-clock RC. 124 collides with the loop-breaker code, but
    # the breaker path emits a synthetic JSONL marker and only triggers via
    # the streaming reader (not bypass mode), so a 124 here can only mean
    # `timeout` fired.
    if [[ "$rc" == "124" || "$rc" == "137" ]]; then
      echo "[TIMEOUT] ${story_id} phase=${phase}: ${executor} wall-clock timeout after ${timeout_sec}s (bypass mode)"
      return "$GAAI_TIMEOUT_RC"
    fi
    return "$rc"
  fi

  # Named fifo for agent → reader handoff
  local fifo
  fifo=$(mktemp -u "/tmp/gaai-agent-fifo-${story_id}-${phase}-XXXXXX")
  if ! mkfifo "$fifo" 2>/dev/null; then
    echo "[WARN] ${story_id} _run_claude_with_loop_breaker: mkfifo failed; falling back to plain pipeline"
    set -o pipefail
    ( cd "$worktree_path" && exec "${agent_cmd[@]}" < "$prompt_file" 2>&1 ) | tee -a "$log_path"
    local rc=${PIPESTATUS[0]}
    set +o pipefail
    return "$rc"
  fi

  # Spawn agent in background, redirecting stdout+stderr to fifo.
  # The subshell cd's into the worktree then exec replaces it with the agent,
  # so $! is the agent's PID and kill -TERM propagates correctly.
  ( cd "$worktree_path" && exec "${agent_cmd[@]}" < "$prompt_file" > "$fifo" 2>&1 ) &
  local agent_pid=$!

  # Write agent subprocess PID sidecar so the daemon hang-detector can kill the
  # agent instead of the wrapper, letting the wrapper's EXIT trap run cleanly.
  local _agent_pid_file
  _agent_pid_file="$(_marker_dir)/${story_id}.agent.pid"
  echo "$agent_pid" > "$_agent_pid_file" 2>/dev/null || true

  # Wall-clock watchdog: send SIGTERM after $timeout_sec, then SIGKILL after
  # an additional 10s grace. Decoupled from the loop-breaker — handles silent
  # hangs that emit no errors. The watchdog auto-exits via `kill -0` check
  # once the agent has ended cleanly, so we don't need to track it for cleanup.
  # Polling granularity = min(timeout/3, 5s) — keeps overshoot bounded for
  # short timeouts (tests, debug overrides) while staying cheap for long ones.
  local watchdog_pid=""
  if [[ -n "$timeout_sec" && "$timeout_sec" -gt 0 ]] 2>/dev/null; then
    local _poll_step=$(( timeout_sec / 3 ))
    (( _poll_step > 5 )) && _poll_step=5
    (( _poll_step < 1 )) && _poll_step=1
    (
      local _waited=0
      while (( _waited < timeout_sec )); do
        sleep "$_poll_step"
        kill -0 "$agent_pid" 2>/dev/null || exit 0
        _waited=$((_waited + _poll_step))
      done
      # Timeout reached — terminate the agent.
      printf '{"type":"system","subtype":"phase_timeout","story_id":"%s","phase":"%s","timeout_sec":%d,"timestamp":"%s"}\n' \
        "$story_id" "$phase" "$timeout_sec" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$log_path" 2>/dev/null || true
      kill -TERM "$agent_pid" 2>/dev/null || true
      sleep 10
      kill -0 "$agent_pid" 2>/dev/null && kill -KILL "$agent_pid" 2>/dev/null || true
    ) &
    watchdog_pid=$!
    disown "$watchdog_pid" 2>/dev/null || true
  fi

  # Stream reader: tee each line to log + watch for repeated tool errors
  local last_err="" err_count=0 breaker_triggered=0
  while IFS= read -r line; do
    printf '%s\n' "$line"
    printf '%s\n' "$line" >> "$log_path"
    if [[ "$line" == *'"is_error":true'* ]]; then
      local content
      content=$(printf '%s' "$line" | _extract_tool_error_content)
      if [[ -n "$content" ]]; then
        if [[ "$content" == "$last_err" ]]; then
          err_count=$((err_count + 1))
        else
          last_err="$content"
          err_count=1
        fi
        if [[ "$err_count" -ge "$threshold" ]]; then
          local err_short="${content:0:160}"
          local breaker_msg
          breaker_msg="[LOOP-BREAKER] ${story_id} phase=${phase}: killing agent_pid=${agent_pid} executor=${executor} after ${err_count} consecutive identical tool errors: ${err_short}"
          echo "$breaker_msg"
          # Synthetic JSONL marker so parsers/monitor see the event in-band
          local err_json
          err_json=$(printf '%s' "$err_short" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$err_short")
          printf '{"type":"system","subtype":"loop_breaker","story_id":"%s","phase":"%s","consecutive_errors":%d,"error_content":%s,"timestamp":"%s"}\n' \
            "$story_id" "$phase" "$err_count" "$err_json" \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$log_path"
          kill -TERM "$agent_pid" 2>/dev/null || true
          sleep 1
          kill -KILL "$agent_pid" 2>/dev/null || true
          breaker_triggered=1
          # Drain remaining output so fifo writer can close cleanly
          while IFS= read -r drain; do
            printf '%s\n' "$drain"
            printf '%s\n' "$drain" >> "$log_path"
          done
          break
        fi
      fi
    fi
  done < "$fifo"

  local agent_exit=0
  wait "$agent_pid" 2>/dev/null || agent_exit=$?

  # Cleanup: stop the watchdog (no-op if it already exited).
  if [[ -n "$watchdog_pid" ]]; then
    kill "$watchdog_pid" 2>/dev/null || true
  fi

  rm -f "$fifo"
  rm -f "$_agent_pid_file" 2>/dev/null || true

  # Reap orphaned descendants the agent left running in the worktree. The agent was
  # waited above, so any process still rooted in $worktree_path is an orphan — a
  # test runner, dev/build server, or worker pool the agent spawned and whose own
  # tool-call timeout detached rather than reaped. Every kill site that ends a phase
  # (the wall-clock watchdog, the loop-breaker, nested-claude-spawn, a normal exit
  # with leftovers) signals only the agent PID, not its tree; without this sweep
  # those long-lived workers accumulate across QA retries until the daemon host runs
  # out of memory. Running it here — once, after the phase, on every return path —
  # bounds the leak to a single phase.
  _reap_worktree_orphans "$worktree_path"

  if [[ "$breaker_triggered" == "1" ]]; then
    return 124
  fi
  # Translate SIGTERM/SIGKILL exit codes from the watchdog to our canonical
  # wall-clock timeout RC. Agents commonly exit 143 on SIGTERM, 137 on SIGKILL.
  if [[ "$agent_exit" == "143" || "$agent_exit" == "137" ]]; then
    return "$GAAI_TIMEOUT_RC"
  fi
  return "$agent_exit"
}

# ── Inline MCP workspace-scope helpers ───────────────────────────────────────

# Extracts the OAuth bearer token (without "Bearer " prefix) from a .mcp.json file.
# Args: $1 = path to .mcp.json
# Stdout: token string or empty
_extract_mcp_oauth_token() {
  local mcp_json="$1"
  [[ ! -f "$mcp_json" ]] && echo "" && return
  python3 - "$mcp_json" <<'PYEOF' 2>/dev/null || echo ""
import json, sys
try:
  d = json.load(open(sys.argv[1]))
  for s in d.get('mcpServers', {}).values():
    a = s.get('headers', {}).get('Authorization', '')
    if a.startswith('Bearer '):
      print(a[7:], end='')
      sys.exit(0)
except Exception: pass
print('', end='')
PYEOF
}

# Returns 0 (success) iff PROJECT_DIR/.mcp.json contains a GAAI MCP server entry
# (one of the canonical keys : "GAAI-cloud", "gaai-cloud", or "cloud" per the
# plugin's write-mcp-json.mjs amend-mode resolution order). Returns 1 otherwise
# (no .mcp.json, malformed JSON, or no GAAI key). Used by the workspace_scope
# guard in handle_{plan,impl,qa}_phase to avoid false-positive activation when
# .mcp.json exists for unrelated MCP servers (e.g. Paddle, Linear, GitHub).
_has_gaai_mcp_server() {
  local mcp_json="${PROJECT_DIR}/.mcp.json"
  [[ -f "$mcp_json" ]] || return 1
  python3 - "$mcp_json" <<'PYEOF' 2>/dev/null
import json, sys
try:
  d = json.load(open(sys.argv[1]))
  s = d.get('mcpServers', {})
  sys.exit(0 if any(k in s for k in ('GAAI-cloud', 'gaai-cloud', 'cloud')) else 1)
except Exception:
  sys.exit(1)
PYEOF
}

# Builds inline --mcp-config JSON for daemon-spawned claude -p processes.
# Passes X-GAAI-Workspace-Scope + X-GAAI-Session-Mode: autonomous headers.
# Args: $1 = workspace_id (UUID), $2 = oauth_token (raw, no "Bearer " prefix)
# Stdout: JSON string
_build_daemon_mcp_config() {
  local workspace_id="$1" oauth_token="$2"
  printf '{"mcpServers":{"GAAI-cloud":{"type":"http","url":"https://mcp.gaai.cloud/mcp","headers":{"Authorization":"Bearer %s","X-GAAI-Workspace-Scope":"%s","X-GAAI-Session-Mode":"autonomous"}}}}' \
    "$oauth_token" "$workspace_id"
}

# ── Field extractors (AC1 — verbatim per story AC1 specification) ─────────

get_phase_status() {
  local id="$1"
  awk -v id="$id" '
    $0 == "- id: " id { found=1; next }
    found && /^- id:/ { exit }
    found && /^[[:space:]]+phase_status:/ {
      gsub(/^[[:space:]]+phase_status:[[:space:]]*/, "")
      gsub(/[[:space:]]+#.*$/, "")  # strip YAML inline comment (defensive — `#` after whitespace)
      gsub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$BACKLOG_FILE"
}

get_delivery_pipeline() {
  local id="$1"
  awk -v id="$id" '
    $0 == "- id: " id { found=1; next }
    found && /^- id:/ { exit }
    found && /^[[:space:]]+delivery_pipeline:/ {
      gsub(/^[[:space:]]+delivery_pipeline:[[:space:]]*/, "")
      gsub(/[[:space:]]+#.*$/, "")  # strip YAML inline comment (defensive — `#` after whitespace)
      gsub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$BACKLOG_FILE"
}

# Helper: read impl_model_tag from backlog (returns "absent" if unset/missing)
get_impl_model_tag() {
  local id="$1"
  local val
  val=$(awk -v id="$id" '
    $0 == "- id: " id { found=1; next }
    found && /^- id:/ { exit }
    found && /^[[:space:]]+impl_model:/ {
      gsub(/^[[:space:]]+impl_model:[[:space:]]*/, "")
      gsub(/[[:space:]]+#.*$/, "")  # strip YAML inline comment (`#` preceded by whitespace)
      gsub(/[[:space:]]+#.*$/, "")  # strip YAML inline comment (defensive — `#` after whitespace)
      gsub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$BACKLOG_FILE" 2>/dev/null || true)
  echo "${val:-absent}"
}

# Helper: read tier from backlog YAML (returns "" if absent — caller must default)
get_story_tier() {
  local id="$1"
  awk -v id="$id" '
    $0 == "- id: " id { found=1; next }
    found && /^- id:/ { exit }
    found && /^[[:space:]]+tier:/ {
      gsub(/^[[:space:]]+tier:[[:space:]]*/, "")
      gsub(/[[:space:]]+#.*$/, "")  # strip YAML inline comment (defensive — `#` after whitespace)
      gsub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$BACKLOG_FILE" 2>/dev/null || true
}

# Helper: read story title from backlog YAML (returns "" if absent)
get_story_title() {
  local id="$1"
  awk -v id="$id" '
    $0 == "- id: " id { found=1; next }
    found && /^- id:/ { exit }
    found && /^[[:space:]]+title:/ {
      gsub(/^[[:space:]]+title:[[:space:]]*/, "")
      gsub(/[[:space:]]+#.*$/, "")  # strip YAML inline comment (defensive — `#` after whitespace)
      gsub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$BACKLOG_FILE"
}

# Helper: read related_decs from backlog YAML (returns space-sep list, "" if absent/empty)
get_related_decs() {
  local id="$1"
  awk -v id="$id" '
    $0 == "- id: " id { found=1; next }
    found && /^- id:/ { exit }
    found && /^[[:space:]]+related_decs:/ {
      gsub(/^[[:space:]]+related_decs:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      # Strip YAML list brackets and commas
      gsub(/^\[/, ""); gsub(/\]$/, ""); gsub(/,/, "")
      print
      exit
    }
  ' "$BACKLOG_FILE"
}

# ── Routing record helper ─────────────────────────────────────────────────
# Emits one JSONL record to runtime-routing.jsonl via runtime-routing-logger.js.
# Arguments: story_id trace_id phase provider fallback_reason
_emit_routing_record() {
  local story_id="$1" trace_id="$2" phase="$3" provider="$4" fallback_reason="$5"
  local impl_tag
  impl_tag=$(get_impl_model_tag "$story_id")

  local log_path_args=()
  if [[ -n "${ROUTING_LOG_PATH:-}" ]]; then
    log_path_args=(--log-path "$ROUTING_LOG_PATH")
  fi

  node "$PROJECT_DIR/.gaai/core/adapters/claude-code/runtime-routing-logger.js" \
    --trace-id  "$trace_id" \
    --story-id  "$story_id" \
    --phase     "$phase" \
    --provider  "$provider" \
    --model     "n/a" \
    --duration-ms 0 \
    --fallback-reason "$fallback_reason" \
    --impl-model-tag  "$impl_tag" \
    ${log_path_args[@]+"${log_path_args[@]}"} \
    2>/dev/null || _emit_routing_record_fallback "$trace_id" "$story_id" "$phase" "$provider" "n/a" "0" "$fallback_reason" "$impl_tag" "" "" ""
}

_emit_routing_record_fallback() {
  [[ -n "${ROUTING_LOG_PATH:-}" ]] || return 0
  local trace_id="$1" story_id="$2" phase="$3" provider="$4" model="$5" duration_ms="$6" fallback_reason="$7" impl_tag="$8" pipeline="${9:-}" pr_url="${10:-}" auto_merge_applied="${11:-}"
  TRACE_ID="$trace_id" STORY_ID="$story_id" PHASE="$phase" PROVIDER="$provider" MODEL="$model" DURATION_MS="$duration_ms" FALLBACK_REASON="$fallback_reason" IMPL_TAG="$impl_tag" PIPELINE="$pipeline" PR_URL="$pr_url" AUTO_MERGE_APPLIED="$auto_merge_applied" ROUTING_LOG_PATH="$ROUTING_LOG_PATH" \
    python3 - <<'PYEOF' 2>/dev/null || true
import json, os, time
record = {
  "trace_id": os.environ["TRACE_ID"],
  "story_id": os.environ["STORY_ID"],
  "phase": os.environ["PHASE"],
  "provider": os.environ["PROVIDER"],
  "model": os.environ["MODEL"],
  "duration_ms": int(os.environ.get("DURATION_MS") or 0),
  "fallback_reason": None if os.environ.get("FALLBACK_REASON") in ("", "null") else os.environ.get("FALLBACK_REASON"),
  "impl_model_tag": os.environ.get("IMPL_TAG") or "",
  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
if os.environ.get("PIPELINE"):
  record["pipeline"] = os.environ["PIPELINE"]
if os.environ.get("PR_URL"):
  record["pr_url"] = os.environ["PR_URL"]
if os.environ.get("AUTO_MERGE_APPLIED"):
  record["auto_merge_applied"] = os.environ["AUTO_MERGE_APPLIED"] == "true"
with open(os.environ["ROUTING_LOG_PATH"], "a", encoding="utf-8") as fh:
  fh.write(json.dumps(record, separators=(",", ":")) + "\n")
PYEOF
}

# ── Plan-phase routing record (adds --pipeline, real model, real duration) ──
# Arguments: story_id trace_id provider fallback_reason duration_ms
_emit_plan_routing_record() {
  local story_id="$1" trace_id="$2" provider="$3" fallback_reason="$4" duration_ms="$5"
  local impl_tag model_val
  impl_tag=$(get_impl_model_tag "$story_id")
  model_val="${CLAUDE_MODEL_PRIMARY:-claude-sonnet-5}"
  if [[ "${GAAI_DAEMON_EXECUTOR:-claude}" == "codex" ]]; then
    [[ "$provider" == "primary" ]] && provider="codex"
    model_val="${GAAI_CODEX_MODEL:-codex-default}"
  fi

  local log_path_args=()
  if [[ -n "${ROUTING_LOG_PATH:-}" ]]; then
    log_path_args=(--log-path "$ROUTING_LOG_PATH")
  fi

  node "$PROJECT_DIR/.gaai/core/adapters/claude-code/runtime-routing-logger.js" \
    --trace-id        "$trace_id" \
    --story-id        "$story_id" \
    --phase           "plan" \
    --provider        "$provider" \
    --model           "$model_val" \
    --duration-ms     "$duration_ms" \
    --fallback-reason "$fallback_reason" \
    --impl-model-tag  "$impl_tag" \
    --pipeline        "3phase" \
    ${log_path_args[@]+"${log_path_args[@]}"} \
    2>/dev/null || _emit_routing_record_fallback "$trace_id" "$story_id" "plan" "$provider" "$model_val" "$duration_ms" "$fallback_reason" "$impl_tag" "3phase" "" ""
}

# ── QA-phase routing record (adds --pipeline, real model, real duration, verdict) ──
# Arguments: story_id trace_id provider fallback_reason duration_ms
_emit_qa_routing_record() {
  local story_id="$1" trace_id="$2" provider="$3" fallback_reason="$4" duration_ms="$5"
  local impl_tag model_val
  impl_tag=$(get_impl_model_tag "$story_id")
  model_val="${CLAUDE_MODEL_PRIMARY:-claude-sonnet-5}"
  if [[ "${GAAI_DAEMON_EXECUTOR:-claude}" == "codex" ]]; then
    [[ "$provider" == "primary" ]] && provider="codex"
    model_val="${GAAI_CODEX_MODEL:-codex-default}"
  fi

  local log_path_args=()
  if [[ -n "${ROUTING_LOG_PATH:-}" ]]; then
    log_path_args=(--log-path "$ROUTING_LOG_PATH")
  fi

  node "$PROJECT_DIR/.gaai/core/adapters/claude-code/runtime-routing-logger.js" \
    --trace-id        "$trace_id" \
    --story-id        "$story_id" \
    --phase           "qa" \
    --provider        "$provider" \
    --model           "$model_val" \
    --duration-ms     "$duration_ms" \
    --fallback-reason "$fallback_reason" \
    --impl-model-tag  "$impl_tag" \
    --pipeline        "3phase" \
    ${log_path_args[@]+"${log_path_args[@]}"} \
    2>/dev/null || _emit_routing_record_fallback "$trace_id" "$story_id" "qa" "$provider" "$model_val" "$duration_ms" "$fallback_reason" "$impl_tag" "3phase" "" ""
}

# ── Commit-phase routing record (adds --pipeline, --pr-url, --auto-merge-applied) ──
# Arguments: story_id trace_id provider fallback_reason duration_ms pr_url auto_merge_applied
_emit_commit_routing_record() {
  local story_id="$1" trace_id="$2" provider="$3" fallback_reason="$4" duration_ms="$5"
  local pr_url="${6:-}" auto_merge_applied="${7:-false}"
  local impl_tag
  impl_tag=$(get_impl_model_tag "$story_id")

  local log_path_args=()
  if [[ -n "${ROUTING_LOG_PATH:-}" ]]; then
    log_path_args=(--log-path "$ROUTING_LOG_PATH")
  fi

  node "$PROJECT_DIR/.gaai/core/adapters/claude-code/runtime-routing-logger.js" \
    --trace-id           "$trace_id" \
    --story-id           "$story_id" \
    --phase              "commit" \
    --provider           "$provider" \
    --model              "n/a" \
    --duration-ms        "$duration_ms" \
    --fallback-reason    "$fallback_reason" \
    --impl-model-tag     "$impl_tag" \
    --pipeline           "3phase" \
    --pr-url             "$pr_url" \
    --auto-merge-applied "$auto_merge_applied" \
    ${log_path_args[@]+"${log_path_args[@]}"} \
    2>/dev/null || _emit_routing_record_fallback "$trace_id" "$story_id" "commit" "$provider" "n/a" "$duration_ms" "$fallback_reason" "$impl_tag" "3phase" "$pr_url" "$auto_merge_applied"
}

# ── Worktree dependency installer ──────────────────────────────────────────
# Ensures node_modules are populated before the PLAN phase agent spawns.
# Idempotent: checks the @cloudflare/workers-types marker dir (empirically
# verified path where pnpm installs this dep for workers/gaai-cloud/api).
# Called on EVERY handle_plan_phase entry (fresh + resumed worktrees).
ensure_wt_dependencies_installed() {
  local story_id="$1" trace_id="$2" worktree_path="$3"
  local timeout_s marker_dir ts t_start t_end duration_ms install_exit timeout_cmd

  timeout_s="${GAAI_PNPM_INSTALL_TIMEOUT:-120}"
  marker_dir="${worktree_path}/workers/gaai-cloud/api/node_modules/@cloudflare/workers-types"
  ts=$(date '+%H:%M:%S')

  if [[ -d "$marker_dir" ]]; then
    echo "[${ts}] ${story_id} ${trace_id} [wt-deps] wt_deps_check marker_present=true"
    return 0
  fi

  echo "[${ts}] ${story_id} ${trace_id} [wt-deps] wt_deps_check marker_present=false"
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} ${trace_id} [wt-deps] wt_deps_install_started timeout_s=${timeout_s}"

  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_start=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_start=$(( $(date +%s) * 1000 ))
  fi

  timeout_cmd=$(_resolve_timeout_cmd)
  install_exit=0
  if [[ -n "$timeout_cmd" ]]; then
    (cd "$worktree_path" && "$timeout_cmd" "$timeout_s" pnpm install --frozen-lockfile --silent) \
      || install_exit=$?
  else
    (cd "$worktree_path" && pnpm install --frozen-lockfile --silent) &
    local install_pid=$!
    local waited=0
    while kill -0 "$install_pid" 2>/dev/null; do
      if (( waited >= timeout_s )); then
        kill "$install_pid" 2>/dev/null || true
        wait "$install_pid" 2>/dev/null || true
        install_exit=124
        break
      fi
      sleep 1
      (( waited++ )) || true
    done
    if [[ $install_exit -eq 0 ]]; then
      wait "$install_pid" 2>/dev/null || install_exit=$?
    fi
  fi

  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_end=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_end=$(( $(date +%s) * 1000 ))
  fi
  duration_ms=$(( t_end - t_start ))
  ts=$(date '+%H:%M:%S')

  if [[ $install_exit -eq 0 ]]; then
    echo "[${ts}] ${story_id} ${trace_id} [wt-deps] wt_deps_install_completed duration_ms=${duration_ms}"
    return 0
  fi

  echo "[${ts}] ${story_id} ${trace_id} [wt-deps] wt_deps_install_failed duration_ms=${duration_ms} exit_code=${install_exit}"
  _emit_plan_routing_record "$story_id" "$trace_id" "error" "PNPM_INSTALL_FAILED" "${duration_ms}"
  return 1
}

# ── Worktree deps freshness guard ────────────────────────────────
# Compares pnpm-lock.yaml sha256 against a marker file in the worktree.
# On match → skip install (idempotent fast path).
# On mismatch / absent → pnpm install --frozen-lockfile + update marker.
_ensure_worktree_deps_fresh() {
  local story_id="$1" worktree_path="$2"
  local timeout_s marker_path lockfile_path current_hash stored_hash hash_short
  local timeout_cmd install_exit t_start_ms t_end_ms duration_s

  timeout_s="${GAAI_PNPM_INSTALL_TIMEOUT_SEC:-300}"
  marker_path="${worktree_path}/.gaai-pnpm-install-marker"
  lockfile_path="${worktree_path}/pnpm-lock.yaml"

  # No lockfile → nothing to guard (e.g. non-pnpm repo)
  [[ ! -f "$lockfile_path" ]] && return 0

  # Compute hash (sha256sum on Linux, shasum -a 256 on macOS)
  current_hash=$(sha256sum < "$lockfile_path" 2>/dev/null | awk '{print $1}')
  if [[ -z "$current_hash" ]]; then
    current_hash=$(shasum -a 256 < "$lockfile_path" 2>/dev/null | awk '{print $1}')
  fi
  # Hash tool unavailable → treat as fresh (no regression)
  [[ -z "$current_hash" ]] && return 0

  hash_short="${current_hash:0:8}"
  echo "[COMMIT-PHASE] ${story_id} : checking worktree deps freshness (lockfile hash=${hash_short})"

  stored_hash=""
  [[ -f "$marker_path" ]] && stored_hash=$(cat "$marker_path" 2>/dev/null)

  if [[ "$current_hash" == "$stored_hash" ]]; then
    echo "[COMMIT-PHASE] ${story_id} : worktree deps fresh (marker hash matches) — skipping install"
    return 0
  fi

  echo "[COMMIT-PHASE] ${story_id} : worktree deps stale or absent — running pnpm install --frozen-lockfile"

  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_start_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_start_ms=$(( $(date +%s) * 1000 ))
  fi

  timeout_cmd=$(_resolve_timeout_cmd)
  install_exit=0
  if [[ -n "$timeout_cmd" ]]; then
    (cd "$worktree_path" && "$timeout_cmd" "$timeout_s" pnpm install --frozen-lockfile) \
      || install_exit=$?
  else
    (cd "$worktree_path" && pnpm install --frozen-lockfile) &
    local install_pid=$!
    local waited=0
    while kill -0 "$install_pid" 2>/dev/null; do
      if (( waited >= timeout_s )); then
        kill "$install_pid" 2>/dev/null || true
        wait "$install_pid" 2>/dev/null || true
        install_exit=124
        break
      fi
      sleep 1
      (( waited++ )) || true
    done
    if [[ $install_exit -eq 0 ]]; then
      wait "$install_pid" 2>/dev/null || install_exit=$?
    fi
  fi

  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_end_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_end_ms=$(( $(date +%s) * 1000 ))
  fi
  duration_s=$(( (t_end_ms - t_start_ms) / 1000 ))

  if [[ $install_exit -eq 124 ]]; then
    echo "[COMMIT-PHASE] ${story_id} : pnpm install timed out after ${timeout_s}s — surfacing error to dispatch"
    return 1
  fi

  if [[ $install_exit -ne 0 ]]; then
    return 1
  fi

  # Success — write marker
  printf '%s\n' "$current_hash" > "$marker_path"
  echo "[COMMIT-PHASE] ${story_id} : pnpm install completed in ${duration_s}s, marker updated"
  return 0
}

# ── Phase handlers ────────────────────────────────────────────────────────

handle_plan_phase() {
  local story_id="$1" trace_id="$2"
  local ts t_start_ms t_end_ms duration_ms
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=plan starting"

  # ── Resolve worktree path (GAAI_WORKTREES_BASE override or default formula) ──
  # Aligned with handle_impl_phase + handle_qa_phase canonical formula.
  local worktree_path
  if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
    worktree_path="${GAAI_WORKTREES_BASE}/${story_id}-workspace"
  else
    local repo_name
    repo_name=$(basename "${REPO_ROOT:-$PROJECT_DIR}")
    worktree_path="$(cd "${REPO_ROOT:-$PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${story_id}-workspace"
  fi

  # ── Ensure worktree + story branch exist (idempotent) ─────────────────────
  # Plan is the first phase — worktree must be created here before plan agent
  # writes its execution-plan.md inside it. Subsequent phases (impl/qa/commit)
  # reuse the same worktree.
  if ! git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | grep -qE "^worktree ${worktree_path}$"; then
    # Create the story branch from the freshly-fetched REMOTE tip (origin/<branch>),
    # NOT the local `staging` ref. The local ref is never advanced during a long
    # daemon run (only origin/<branch> is fetched each poll), so branching from it
    # would cut every story from the daemon's startup-era snapshot — stories would
    # silently miss dependencies merged after the daemon started. Branching from
    # origin/<branch> means each new story starts from the latest merged tip.
    # (No checkout — main stays on the daemon-home branch per orchestration.rules.md INVARIANT.)
    local _base_branch="${TARGET_BRANCH:-staging}"
    git -C "$PROJECT_DIR" fetch origin "$_base_branch" --quiet 2>/dev/null || true
    if ! git -C "$PROJECT_DIR" rev-parse --verify "story/${story_id}" >/dev/null 2>&1; then
      if ! git -C "$PROJECT_DIR" branch "story/${story_id}" "origin/${_base_branch}" 2>/dev/null; then
        echo "[ERROR] ${story_id} handle_plan_phase: git branch story/${story_id} origin/${_base_branch} failed"
        _emit_plan_routing_record "$story_id" "$trace_id" "error" "WORKTREE_BRANCH_FAILED" "0"
        return 1
      fi
    fi
    mkdir -p "$(dirname "$worktree_path")"
    if ! git -C "$PROJECT_DIR" worktree add "$worktree_path" "story/${story_id}" 2>/dev/null; then
      echo "[ERROR] ${story_id} handle_plan_phase: git worktree add failed for $worktree_path"
      _emit_plan_routing_record "$story_id" "$trace_id" "error" "WORKTREE_CREATE_FAILED" "0"
      return 1
    fi
  fi

  # ── Ensure worktree node_modules are populated ───────────────────────────
  if ! ensure_wt_dependencies_installed "$story_id" "$trace_id" "$worktree_path"; then
    return 1
  fi

  # ── Inline MCP workspace scope for autonomous spawn ──────────────────────
  # AC5: Refuse spawn if GAAI Cloud configured but workspace_id is missing.
  if _has_gaai_mcp_server && [[ -z "${GAAI_WORKSPACE_ID:-}" ]]; then
    echo "[ERROR] workspace_scope required for autonomous spawn: Story ${story_id} missing workspace_id in backlog. Set GAAI_WORKSPACE_ID or add workspace_id to the story entry." >&2
    "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
    _emit_plan_routing_record "$story_id" "$trace_id" "error" "WORKSPACE_SCOPE_MISSING" "0"
    return 1
  fi
  # Build --mcp-config args (AC1-AC3). No filesystem .mcp.json copy needed (AC2).
  local _plan_oauth _plan_mcp_json _plan_mcp_args=()
  _plan_oauth=$(_extract_mcp_oauth_token "${PROJECT_DIR}/.mcp.json")
  if [[ -n "$_plan_oauth" && -n "${GAAI_WORKSPACE_ID:-}" ]]; then
    _plan_mcp_json=$(_build_daemon_mcp_config "${GAAI_WORKSPACE_ID}" "$_plan_oauth")
    _plan_mcp_args=(--mcp-config "$_plan_mcp_json")
    # AC4: spawn audit log
    echo "[$(date '+%H:%M:%S')] ${story_id} plan-spawn: workspace_id=${GAAI_WORKSPACE_ID} session_mode=autonomous"
  fi
  # Legacy warning: detect worktree .mcp.json with deprecated X-GAAI-WorkspaceBinding header
  if grep -q 'X-GAAI-WorkspaceBinding' "${worktree_path}/.mcp.json" 2>/dev/null; then
    echo "[WARN] ${story_id}: legacy X-GAAI-WorkspaceBinding in worktree .mcp.json — header is deprecated, inline --mcp-config is authoritative (informational)"
  fi

  # ── Resolve artefact paths ────────────────────────────────────────────────
  local story_path plan_path epic_path log_path
  story_path="${worktree_path}/.gaai/project/contexts/artefacts/stories/${story_id}.story.md"
  plan_path="${worktree_path}/.gaai/project/contexts/artefacts/plans/${story_id}.execution-plan.md"
  log_path="${worktree_path}/.delivery-logs/${story_id}.plan.log"

  # Rotate prior session's log on retry (preserves forensic trail).
  _rotate_phase_log "$log_path"

  # Resolve epic_id from story frontmatter; empty string if missing
  local epic_id
  epic_id=$(grep -m1 '^epic:' "$story_path" 2>/dev/null | sed 's/^epic:[[:space:]]*//' | tr -d '"' || true)
  if [[ -n "$epic_id" ]]; then
    epic_path="${worktree_path}/.gaai/project/contexts/artefacts/epics/${epic_id}.epic.md"
  else
    epic_path=""
  fi

  # Ensure output directories exist
  mkdir -p "$(dirname "$log_path")"
  mkdir -p "$(dirname "$plan_path")"

  # ── Build prompt from planning.daemon-prompt.md (AC1) ─────────────────────
  local prompt_file agent_prompt_src
  agent_prompt_src="${PROJECT_DIR}/.gaai/core/agents/sub-agents/planning.daemon-prompt.md"

  if [[ ! -f "$agent_prompt_src" ]]; then
    echo "[ERROR] ${story_id} handle_plan_phase: planning.daemon-prompt.md not found at $agent_prompt_src"
    _emit_plan_routing_record "$story_id" "$trace_id" "error" "PLAN_PHASE_FAILED" "0"
    return 1
  fi

  prompt_file=$(mktemp "/tmp/gaai-plan-prompt-${story_id}-XXXXXX")
  cat "$agent_prompt_src" > "$prompt_file"

  # ── Cross-cycle qa-report injection: PLAN route (replan routing contract) ────
  # Appends prior qa-report + prior artefacts + delta-aware marker framing to
  # the PLAN prompt when GAAI_QA_INJECT_PHASE=plan (ESCALATE or FAIL+replan_required=true).
  if [[ "${GAAI_QA_INJECT_PHASE:-}" == "plan" && -n "${GAAI_QA_REPORT_PATH:-}" && -s "${GAAI_QA_REPORT_PATH}" ]]; then
    local _cc_qa_content _cc_qa_bytes _cc_plan_content _cc_plan_bytes _cc_impl_content _cc_impl_bytes
    local _cc_plan_avail=true _cc_impl_avail=true
    _cc_qa_bytes=$(wc -c < "$GAAI_QA_REPORT_PATH" 2>/dev/null || echo 0)
    if (( _cc_qa_bytes > 51200 )); then
      _cc_qa_content="$(head -c 51200 "$GAAI_QA_REPORT_PATH" 2>/dev/null)

(... truncated at 50KB, full content at ${GAAI_QA_REPORT_PATH})"
    else
      _cc_qa_content="$(cat "$GAAI_QA_REPORT_PATH" 2>/dev/null || echo "(not available)")"
    fi

    local _cc_plan_path="${GAAI_WORKTREE_PATH:-${worktree_path}}/.gaai/project/contexts/artefacts/plans/${story_id}.execution-plan.md"
    if [[ -s "$_cc_plan_path" ]]; then
      _cc_plan_bytes=$(wc -c < "$_cc_plan_path" 2>/dev/null || echo 0)
      if (( _cc_plan_bytes > 51200 )); then
        _cc_plan_content="$(head -c 51200 "$_cc_plan_path" 2>/dev/null)

(... truncated at 50KB, full content at ${_cc_plan_path})"
      else
        _cc_plan_content="$(cat "$_cc_plan_path" 2>/dev/null || echo "(not available)")"
      fi
    else
      local _cc_plan_git
      _cc_plan_git=$(git -C "${GAAI_WORKTREE_PATH:-${worktree_path}}" show "story/${story_id}:.gaai/project/contexts/artefacts/plans/${story_id}.execution-plan.md" 2>/dev/null || true)
      if [[ -n "$_cc_plan_git" ]]; then
        _cc_plan_content="$_cc_plan_git"
        _cc_plan_bytes=$(printf '%s' "$_cc_plan_git" | wc -c)
      else
        _cc_plan_content="(prior execution-plan not available — produce a fresh plan informed by qa-report only)"
        _cc_plan_bytes=0
        _cc_plan_avail=false
      fi
    fi

    local _cc_impl_path="${GAAI_WORKTREE_PATH:-${worktree_path}}/.gaai/project/contexts/artefacts/impl-reports/${story_id}.impl-report.md"
    if [[ -s "$_cc_impl_path" ]]; then
      _cc_impl_bytes=$(wc -c < "$_cc_impl_path" 2>/dev/null || echo 0)
      if (( _cc_impl_bytes > 51200 )); then
        _cc_impl_content="$(head -c 51200 "$_cc_impl_path" 2>/dev/null)

(... truncated at 50KB, full content at ${_cc_impl_path})"
      else
        _cc_impl_content="$(cat "$_cc_impl_path" 2>/dev/null || echo "(not available)")"
      fi
    else
      local _cc_impl_git
      _cc_impl_git=$(git -C "${GAAI_WORKTREE_PATH:-${worktree_path}}" show "story/${story_id}:.gaai/project/contexts/artefacts/impl-reports/${story_id}.impl-report.md" 2>/dev/null || true)
      if [[ -n "$_cc_impl_git" ]]; then
        _cc_impl_content="$_cc_impl_git"
        _cc_impl_bytes=$(printf '%s' "$_cc_impl_git" | wc -c)
      else
        _cc_impl_content="(prior impl-report not available)"
        _cc_impl_bytes=0
        _cc_impl_avail=false
      fi
    fi

    # Append prior-findings block (best-effort — non-fatal on write failure).
    # Use printf '%s' to avoid shell interpolation of qa-report content containing $var.
    if {
      printf '\n## Prior cycle QA findings\n\n%s\n' "$_cc_qa_content"
      printf '\n## Prior execution-plan\n\n%s\n' "$_cc_plan_content"
      printf '\n## Prior impl-report\n\n%s\n' "$_cc_impl_content"
      printf '%s\n' '
## Delta-aware planning instruction

You are re-planning after a prior cycle that partially implemented this story.
The qa-report above identifies what failed. Mark each step in your plan with
EXACTLY ONE of the following markers:

  ✓ KEEP    — Prior step implemented correctly and qa-report verified the AC.
               Do NOT touch those files. Assert they are unchanged.
  ↻ REVISE  — Prior step was implemented but the qa-report identified a defect.
               Specify the corrective action in one line.
  + NEW     — Additional step required (gap found during re-plan).
               Implement from scratch.

Justify each marker in one line. Err toward REVISE over KEEP when uncertain.'
    } >> "$prompt_file" 2>/dev/null; then
      local _cc_plan_log="${_cc_plan_bytes}B" _cc_impl_log="${_cc_impl_bytes}B"
      [[ "$_cc_plan_avail" == "false" ]] && _cc_plan_log="missing"
      [[ "$_cc_impl_avail" == "false" ]] && _cc_impl_log="missing"
      echo "[CROSS-CYCLE-QA-PLAN-APPEND] ${story_id}: delta-block appended (qa=${_cc_qa_bytes}B plan=${_cc_plan_log} impl=${_cc_impl_log})"
    else
      echo "[WARN] [CROSS-CYCLE-QA-PLAN-APPEND] ${story_id}: append failed — proceeding without prior-findings block"
    fi
  fi

  # ── Spawn claude -p (AC1) ─────────────────────────────────────────────────
  # Duration measurement (AC4) — bash 5+ EPOCHREALTIME (microseconds); fallback date +%s
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_start_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_start_ms=$(( $(date +%s) * 1000 ))
  fi

  local claude_exit
  GAAI_STORY_ID="$story_id" \
  GAAI_WORKTREE_PATH="$worktree_path" \
  GAAI_STORY_PATH="$story_path" \
  GAAI_PLAN_PATH="$plan_path" \
  GAAI_EPIC_PATH="$epic_path" \
  GAAI_DELIVERY_LOG_FILE="$log_path" \
  GAAI_WORKSPACE_ID="${GAAI_WORKSPACE_ID:-}" \
  GAAI_ORG_ID="${GAAI_ORG_ID:-}" \
    _run_claude_with_loop_breaker \
      "$story_id" "plan" "$log_path" "$prompt_file" "$worktree_path" \
      --model sonnet \
      --max-turns 60 \
      --output-format stream-json \
      --verbose \
      --dangerously-skip-permissions \
      ${_plan_mcp_args[@]+"${_plan_mcp_args[@]}"}
  claude_exit=$?

  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_end_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_end_ms=$(( $(date +%s) * 1000 ))
  fi
  duration_ms=$(( t_end_ms - t_start_ms ))

  rm -f "$prompt_file"

  # ── Validate output (AC4 guard) ───────────────────────────────────────────
  if [[ "$claude_exit" -eq 124 ]]; then
    echo "[ERROR] ${story_id} handle_plan_phase: loop breaker triggered (claude killed after consecutive identical tool errors)"
    _emit_plan_routing_record "$story_id" "$trace_id" "error" "PLAN_PHASE_LOOP_BREAKER" "$duration_ms"
    return 1
  fi
  if [[ "$claude_exit" -ne 0 ]]; then
    echo "[ERROR] ${story_id} handle_plan_phase: claude -p exited $claude_exit"
    _emit_plan_routing_record "$story_id" "$trace_id" "error" "PLAN_PHASE_FAILED" "$duration_ms"
    return 1
  fi

  # ── Filename-variation tolerance (LLM compliance defense) ────────────────
  # The Plan agent prompt instructs the agent to write to $GAAI_PLAN_PATH
  # (= ${story_id}.execution-plan.md). If the agent writes to a sibling
  # filename instead (most commonly ${story_id}.plan.md), the file IS valid
  # but the canonical path is missing. Auto-rename rather than fail — this
  # converts a probabilistic LLM-compliance failure into a deterministic
  # rename op + warning.
  if [[ ! -s "$plan_path" ]]; then
    local _plan_dir _alt_plan
    _plan_dir=$(dirname "$plan_path")
    _alt_plan="${_plan_dir}/${story_id}.plan.md"
    if [[ -s "$_alt_plan" ]]; then
      echo "[WARN] ${story_id} handle_plan_phase: plan written to ${_alt_plan} instead of canonical ${plan_path} — auto-renaming"
      mv "$_alt_plan" "$plan_path" 2>/dev/null || {
        echo "[ERROR] ${story_id} handle_plan_phase: rename ${_alt_plan} → ${plan_path} failed"
        _emit_plan_routing_record "$story_id" "$trace_id" "error" "NO_ARTEFACT" "$duration_ms"
        return 1
      }
    else
      echo "[ERROR] ${story_id} handle_plan_phase: plan file missing or empty at $plan_path"
      _emit_plan_routing_record "$story_id" "$trace_id" "error" "NO_ARTEFACT" "$duration_ms"
      return 1
    fi
  fi

  if ! grep -q '^## ' "$plan_path"; then
    echo "[ERROR] ${story_id} handle_plan_phase: plan file has no '## ' heading"
    _emit_plan_routing_record "$story_id" "$trace_id" "error" "PARSE_ERROR" "$duration_ms"
    return 1
  fi

  # ── Advance phase_status: not_started → planned (AC4) ────────────────────
  if ! "$SCHEDULER" --set-phase-status "$story_id" planned "$BACKLOG_FILE" 2>/dev/null; then
    echo "[ERROR] ${story_id} handle_plan_phase: --set-phase-status planned failed"
    _emit_plan_routing_record "$story_id" "$trace_id" "error" "SCHEDULER_FAILURE" "$duration_ms"
    return 1
  fi

  # ── Emit success routing record (AC4) ────────────────────────────────────
  _emit_plan_routing_record "$story_id" "$trace_id" "primary" "null" "$duration_ms"

  # ── Post-PLAN env cleanup: unconditional when phase=plan ─────────────────
  if [[ "${GAAI_QA_INJECT_PHASE:-}" == "plan" ]]; then
    unset GAAI_QA_INJECT_PHASE GAAI_QA_REPORT_PATH 2>/dev/null || true
    echo "[CROSS-CYCLE-QA-UNSET] ${story_id}: phase=plan complete — env cleared before IMPL spawn"
  fi

  # ── Worktree-scope audit (advisory) ──────────────────────────────────────
  _run_worktree_audit "$story_id" "plan" "$log_path" "$worktree_path"

  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=plan DONE (${duration_ms}ms)"
  return 0
}

handle_impl_phase() {
  local story_id="$1" trace_id="$2"
  local ts
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=impl starting"

  # ── Resolve worktree path (GAAI_WORKTREES_BASE override or default formula) ──
  local worktree_path
  if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
    worktree_path="${GAAI_WORKTREES_BASE}/${story_id}-workspace"
  else
    local repo_name
    repo_name=$(basename "${REPO_ROOT:-$PROJECT_DIR}")
    worktree_path="$(cd "${REPO_ROOT:-$PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${story_id}-workspace"
  fi

  # ── Inline MCP workspace scope for autonomous spawn ──────────────────────
  if _has_gaai_mcp_server && [[ -z "${GAAI_WORKSPACE_ID:-}" ]]; then
    echo "[ERROR] workspace_scope required for autonomous spawn: Story ${story_id} missing workspace_id in backlog. Set GAAI_WORKSPACE_ID or add workspace_id to the story entry." >&2
    "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
    return 1
  fi
  local _impl_oauth _impl_mcp_json _impl_mcp_extra=()
  _impl_oauth=$(_extract_mcp_oauth_token "${PROJECT_DIR}/.mcp.json")
  if [[ -n "$_impl_oauth" && -n "${GAAI_WORKSPACE_ID:-}" ]]; then
    _impl_mcp_json=$(_build_daemon_mcp_config "${GAAI_WORKSPACE_ID}" "$_impl_oauth")
    _impl_mcp_extra=(--extra-arg --mcp-config --extra-arg "$_impl_mcp_json")
    # AC4: spawn audit log
    echo "[$(date '+%H:%M:%S')] ${story_id} impl-spawn: workspace_id=${GAAI_WORKSPACE_ID} session_mode=autonomous"
  fi
  if grep -q 'X-GAAI-WorkspaceBinding' "${worktree_path}/.mcp.json" 2>/dev/null; then
    echo "[WARN] ${story_id}: legacy X-GAAI-WorkspaceBinding in worktree .mcp.json — header is deprecated, inline --mcp-config is authoritative (informational)"
  fi

  # ── Resolve artefact paths ────────────────────────────────────────────────
  local story_path plan_path impl_report_path log_path
  story_path="${worktree_path}/.gaai/project/contexts/artefacts/stories/${story_id}.story.md"
  plan_path="${worktree_path}/.gaai/project/contexts/artefacts/plans/${story_id}.execution-plan.md"
  impl_report_path="${worktree_path}/.gaai/project/contexts/artefacts/impl-reports/${story_id}.impl-report.md"
  log_path="${worktree_path}/.delivery-logs/${story_id}.impl.log"

  # Rotate prior session's log on retry (preserves forensic trail).
  _rotate_phase_log "$log_path"

  # ── Validate required files ───────────────────────────────────────────────
  if [[ ! -f "$story_path" ]]; then
    echo "[ERROR] ${story_id} handle_impl_phase: story file not found: $story_path"
    return 1
  fi
  if [[ ! -f "$plan_path" ]]; then
    echo "[ERROR] ${story_id} handle_impl_phase: plan file not found: $plan_path"
    return 1
  fi

  # ── Build impl prompt via daemon-prompt-construct.sh ─────────────────────
  local prompt_construct_script
  prompt_construct_script="${PROJECT_DIR}/.gaai/core/scripts/daemon-prompt-construct.sh"
  if [[ ! -f "$prompt_construct_script" ]]; then
    echo "[ERROR] ${story_id} handle_impl_phase: daemon-prompt-construct.sh not found"
    return 1
  fi

  local epic_id epic_path
  epic_id=$(grep -m1 '^epic:' "$story_path" 2>/dev/null | sed 's/^epic:[[:space:]]*//' | tr -d '"' || true)
  if [[ -n "$epic_id" ]]; then
    epic_path="${worktree_path}/.gaai/project/contexts/artefacts/epics/${epic_id}.epic.md"
  else
    epic_path=""
  fi

  # ── Get impl_model_tag from backlog (needed BEFORE prompt construction
  #    so SECONDARY_ROUTE can be pre-computed and the R1-R6 context
  #    discipline preamble injected when the secondary path will be taken) ─
  local impl_tag
  impl_tag=$(get_impl_model_tag "$story_id")

  # ── DEC-94 — Tier-aware default impl_model coercion ───────────────────────
  # When impl_model is absent (no story-level opt-in/out), default routing
  # is secondary (per DEC-93 reversal commit 38e6b3f5) for cost optimization.
  # BUT Tier 2 stories on secondary structurally die at 167K compact threshold
  # (cumulative input grows past 0.83 × GLM 200K window in ~16 events).
  # Doctrine PAT-STORY-SCOPE-DISCIPLINE-001 + empirical evidence (E135S02
  # 2026-05-06 cascade-to-Sonnet at event 51 after 3 compacts).
  #
  # Tier-aware default : tier ≥ 2 + absent tag → coerce to primary. Operators
  # who explicitly opt-in `impl_model: secondary` for a Tier 2 story still
  # hit the hard-gate (commit 443d5ad1) — that's intentional, forces them
  # to either decompose to Tier 1 or switch to primary.
  if [[ "$impl_tag" == "absent" ]]; then
    local _tier
    _tier=$(get_story_tier "$story_id")
    if [[ "$_tier" =~ ^[0-9]+$ ]] && (( _tier >= 2 )); then
      impl_tag="primary"
      echo "[INFO] ${story_id} handle_impl_phase: tier ${_tier} + absent tag → coerced to primary (DEC-94)"
    fi
  fi

  # ── Pre-compute SECONDARY_ROUTE — parity with nested-claude-spawn.js
  #    resolveMode(). Must be done BEFORE the prompt is built. Without this,
  #    secondary-route spawns (e.g. GLM) start without the R1-R6 notes-file
  #    discipline and routinely hit rapid_refill_breaker (Claude Code's
  #    internal safety brake on ≥3 consecutive autocompactions) before they
  #    can converge on writing impl-report.md.
  local _impl_route="primary"
  if [[ "$impl_tag" != "primary" ]]; then
    if [[ -n "${GAAI_IMPL_BASE_URL:-}" \
       && -n "${GAAI_IMPL_AUTH_TOKEN:-}" \
       && -n "${GAAI_IMPL_MODEL:-}" ]]; then
      _impl_route="secondary"
    fi
  fi
  local _secondary_route_flag="false"
  [[ "$_impl_route" == "secondary" ]] && _secondary_route_flag="true"

  # ── HARD GATE — Tier 2 stories MUST NOT run on secondary route ─────────────
  # Per PAT-STORY-SCOPE-DISCIPLINE-001 + empirical evidence (E135S02 2026-05-06
  # — Tier 2 secondary triggered 3 compacts in 47 events then cascaded to
  # in-process Sonnet fallback, masking the real failure as "fb=-" in routing
  # log). Tier 2 stories cumulative input crosses 167K threshold (= 0.83 ×
  # GLM 200K window) within ~16 events, regardless of R1-R7 directive
  # compliance. The fix is upstream story scope (decompose to Tier 1) or
  # opt-out to primary explicitly. Daemon refuses the dispatch with a clear
  # error so the operator sees the structural mismatch immediately.
  # ── Tier 2 + secondary hard-gate REMOVED ─────────────────────────────────
  # Previously this block refused dispatch for Tier 2 stories on the secondary
  # route, raising TIER2_SECONDARY_REJECTED. Empirically this defensive gate
  # produced more harm than benefit in practice :
  #   - Multiple ghost-state stuck stories in backlog (status=in_progress with
  #     no active markers + no tmux + no lock files) when wrappers exited via
  #     this branch on transient parser/config issues.
  #   - Cascading mis-attribution of failures that were actually parser bugs
  #     (YAML inline-comment leak in get_impl_model_tag — fixed separately).
  #   - Operator friction : forced to chase down each rejection even when the
  #     story was correctly authored.
  # The authoring-layer doctrine ("primary always pre-PMF unless explicit
  # secondary opt-in") plus the tier-aware default coercion (Tier 2+ absent →
  # primary) are sufficient at story-creation time. If a Tier 2 story is
  # explicitly opted in to secondary by an operator, that's a deliberate
  # choice — let it run, observe the outcome, learn from data. Removing the
  # gate trades probabilistic cost exposure for deterministic governability.

  local prompt_content
  if ! prompt_content=$(
    GAAI_STORY_ID="$story_id" \
    GAAI_STORY_PATH="$story_path" \
    GAAI_PLAN_PATH="$plan_path" \
    GAAI_EPIC_PATH="${epic_path:-}" \
    GAAI_WORKSPACE_PATH="$worktree_path" \
    SECONDARY_ROUTE="$_secondary_route_flag" \
    PROJECT_DIR="$PROJECT_DIR" \
    bash "$prompt_construct_script" 2>/dev/null
  ); then
    echo "[ERROR] ${story_id} handle_impl_phase: daemon-prompt-construct.sh failed"
    return 1
  fi

  # ── Ensure output dirs exist ──────────────────────────────────────────────
  mkdir -p "$(dirname "$impl_report_path")"
  mkdir -p "$(dirname "$log_path")"

  # ── Write prompt to temp file ─────────────────────────────────────────────
  local prompt_file
  prompt_file=$(mktemp "/tmp/gaai-impl-prompt-${story_id}-XXXXXX")
  printf '%s' "$prompt_content" > "$prompt_file"

  if [[ "${GAAI_DAEMON_EXECUTOR:-claude}" == "codex" ]]; then
    local codex_exit t_start_ms t_end_ms duration_ms
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
      t_start_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
    else
      t_start_ms=$(( $(date +%s) * 1000 ))
    fi

    GAAI_STORY_ID="$story_id" \
    GAAI_WORKTREE_PATH="$worktree_path" \
    GAAI_STORY_PATH="$story_path" \
    GAAI_PLAN_PATH="$plan_path" \
    GAAI_IMPL_REPORT_PATH="$impl_report_path" \
    GAAI_EPIC_PATH="${epic_path:-}" \
    GAAI_DELIVERY_LOG_FILE="$log_path" \
      _run_claude_with_loop_breaker \
        "$story_id" "impl" "$log_path" "$prompt_file" "$worktree_path"
    codex_exit=$?

    if [[ -n "${EPOCHREALTIME:-}" ]]; then
      t_end_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
    else
      t_end_ms=$(( $(date +%s) * 1000 ))
    fi
    duration_ms=$(( t_end_ms - t_start_ms ))
    rm -f "$prompt_file"

    if [[ "$codex_exit" -eq 124 ]]; then
      echo "[ERROR] ${story_id} handle_impl_phase: loop breaker triggered (codex killed after consecutive identical tool errors)"
      _emit_routing_record "$story_id" "$trace_id" "impl" "error" "IMPL_LOOP_BREAKER"
      return 1
    fi
    if [[ "$codex_exit" -ne 0 ]]; then
      echo "[ERROR] ${story_id} handle_impl_phase: codex exec exited $codex_exit"
      _emit_routing_record "$story_id" "$trace_id" "impl" "error" "IMPL_PHASE_FAILED"
      return 1
    fi
    if [[ ! -s "$impl_report_path" ]]; then
      echo "[ERROR] ${story_id} handle_impl_phase: impl-report.md missing or empty at $impl_report_path"
      _emit_routing_record "$story_id" "$trace_id" "impl" "error" "NO_ARTEFACT"
      return 1
    fi
    if ! "$SCHEDULER" --set-phase-status "$story_id" implemented "$BACKLOG_FILE" 2>/dev/null; then
      echo "[ERROR] ${story_id} handle_impl_phase: --set-phase-status implemented failed"
      _emit_routing_record "$story_id" "$trace_id" "impl" "error" "SCHEDULER_FAILURE"
      return 1
    fi

    _emit_routing_record "$story_id" "$trace_id" "impl" "codex" "null"
    _run_worktree_audit "$story_id" "impl" "$log_path" "$worktree_path"
    ts=$(date '+%H:%M:%S')
    echo "[${ts}] ${story_id} phase=impl DONE"
    return 0
  fi

  # ── Invoke nested-claude-spawn.js flag-CLI (AC1 — always exits 0) ────────
  local spawn_script
  spawn_script="${PROJECT_DIR}/.gaai/core/adapters/claude-code/nested-claude-spawn.js"

  # Wall-clock timeout (OSS-7): bound impl phase to GAAI_TIMEOUT_IMPL_SEC so a
  # silent hang in the node spawner doesn't pin a wrapper indefinitely. Use the
  # `timeout` binary when available; otherwise rely on internal backoff.
  local _impl_to_cmd
  _impl_to_cmd=$(_resolve_timeout_cmd)
  local _impl_to_prefix=()
  if [[ -n "$_impl_to_cmd" ]]; then
    _impl_to_prefix=("$_impl_to_cmd" "--kill-after=15s" "${GAAI_TIMEOUT_IMPL_SEC}s")
  fi

  local spawn_output spawn_rc
  spawn_output=$(
    GAAI_STORY_ID="$story_id" \
    GAAI_WORKTREE_PATH="$worktree_path" \
    GAAI_EPIC_PATH="${epic_path:-}" \
    GAAI_WORKSPACE_ID="${GAAI_WORKSPACE_ID:-}" \
    GAAI_ORG_ID="${GAAI_ORG_ID:-}" \
      ${_impl_to_prefix[@]+"${_impl_to_prefix[@]}"} node "$spawn_script" \
        --story-id       "$story_id" \
        --report-path    "$impl_report_path" \
        --prompt-file    "$prompt_file" \
        --impl-model-tag "$impl_tag" \
        --log-file       "$log_path" \
        --worktree-path  "$worktree_path" \
        ${_impl_mcp_extra[@]+"${_impl_mcp_extra[@]}"} \
        2>>"$log_path"
  )
  spawn_rc=$?
  if [[ "$spawn_rc" == "124" || "$spawn_rc" == "137" ]]; then
    echo "[TIMEOUT] ${story_id} handle_impl_phase: nested-claude-spawn wall-clock timeout after ${GAAI_TIMEOUT_IMPL_SEC}s"
    printf '{"type":"system","subtype":"phase_timeout","story_id":"%s","phase":"impl","timeout_sec":%d,"timestamp":"%s"}\n' \
      "$story_id" "$GAAI_TIMEOUT_IMPL_SEC" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$log_path" 2>/dev/null || true
    rm -f "$prompt_file"
    return 1
  fi

  rm -f "$prompt_file"

  # ── Parse JSON result — nested-claude-spawn.js emits log lines then multi-line JSON ──
  local parsed_json
  parsed_json=$(printf '%s\n' "$spawn_output" | python3 -c "
import sys, json
data = sys.stdin.read()
d = None
# Primary: find last JSON block starting on its own line (JSON.stringify output)
idx = data.rfind('\n{')
if idx >= 0:
    try: d = json.loads(data[idx + 1:])
    except Exception: pass
# Fallback: single-line JSON (legacy compact format)
if d is None:
    for l in reversed(data.splitlines()):
        l = l.strip()
        if not l: continue
        try: d = json.loads(l); break
        except Exception: continue
if d is not None:
    print(str(d.get('success', False)) + '|' + str(d.get('error_reason') or 'null'))
" 2>/dev/null || echo "False|PARSE_ERROR")

  local result_success="${parsed_json%%|*}"
  local result_error="${parsed_json#*|}"

  # ── JSON-driven outcome dispatch (AC4 — daemon does NOT duplicate-emit routing record) ──
  if [[ "$result_success" == "True" ]] && [[ -s "$impl_report_path" ]]; then
    if ! "$SCHEDULER" --set-phase-status "$story_id" implemented "$BACKLOG_FILE" 2>/dev/null; then
      echo "[ERROR] ${story_id} handle_impl_phase: --set-phase-status implemented failed"
      return 1
    fi
    # Worktree-scope audit (advisory)
    _run_worktree_audit "$story_id" "impl" "$log_path" "$worktree_path"
    ts=$(date '+%H:%M:%S')
    echo "[${ts}] ${story_id} phase=impl DONE"
    return 0
  else
    if [[ "$result_success" != "True" ]]; then
      echo "[ERROR] ${story_id} handle_impl_phase: impl failed: ${result_error}"
    else
      echo "[ERROR] ${story_id} handle_impl_phase: impl-report.md missing or empty at $impl_report_path"
    fi
    return 1
  fi
}

handle_qa_phase() {
  local story_id="$1" trace_id="$2"
  local ts t_start_ms t_end_ms duration_ms
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=qa starting"

  # ── Resolve worktree path ─────────────────────────────────────────────────
  local worktree_path
  if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
    worktree_path="${GAAI_WORKTREES_BASE}/${story_id}-workspace"
  else
    local repo_name
    repo_name=$(basename "${REPO_ROOT:-$PROJECT_DIR}")
    worktree_path="$(cd "${REPO_ROOT:-$PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${story_id}-workspace"
  fi

  # ── Inline MCP workspace scope for autonomous spawn ──────────────────────
  if _has_gaai_mcp_server && [[ -z "${GAAI_WORKSPACE_ID:-}" ]]; then
    echo "[ERROR] workspace_scope required for autonomous spawn: Story ${story_id} missing workspace_id in backlog. Set GAAI_WORKSPACE_ID or add workspace_id to the story entry." >&2
    "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "WORKSPACE_SCOPE_MISSING" "0"
    return 1
  fi
  local _qa_oauth _qa_mcp_json _qa_mcp_args=()
  _qa_oauth=$(_extract_mcp_oauth_token "${PROJECT_DIR}/.mcp.json")
  if [[ -n "$_qa_oauth" && -n "${GAAI_WORKSPACE_ID:-}" ]]; then
    _qa_mcp_json=$(_build_daemon_mcp_config "${GAAI_WORKSPACE_ID}" "$_qa_oauth")
    _qa_mcp_args=(--mcp-config "$_qa_mcp_json")
    # AC4: spawn audit log
    echo "[$(date '+%H:%M:%S')] ${story_id} qa-spawn: workspace_id=${GAAI_WORKSPACE_ID} session_mode=autonomous"
  fi
  if grep -q 'X-GAAI-WorkspaceBinding' "${worktree_path}/.mcp.json" 2>/dev/null; then
    echo "[WARN] ${story_id}: legacy X-GAAI-WorkspaceBinding in worktree .mcp.json — header is deprecated, inline --mcp-config is authoritative (informational)"
  fi

  # ── Resolve artefact paths (AC2) ──────────────────────────────────────────
  local story_path plan_path impl_report_path qa_report_path memory_delta_path log_path
  story_path="${worktree_path}/.gaai/project/contexts/artefacts/stories/${story_id}.story.md"
  plan_path="${worktree_path}/.gaai/project/contexts/artefacts/plans/${story_id}.execution-plan.md"
  impl_report_path="${worktree_path}/.gaai/project/contexts/artefacts/impl-reports/${story_id}.impl-report.md"
  qa_report_path="${worktree_path}/.gaai/project/contexts/artefacts/qa-reports/${story_id}.qa-report.md"
  memory_delta_path="${worktree_path}/.gaai/project/contexts/artefacts/memory-deltas/${story_id}.memory-delta.md"
  log_path="${worktree_path}/.delivery-logs/${story_id}.qa.log"

  # Rotate prior session's log on retry (preserves forensic trail).
  _rotate_phase_log "$log_path"

  # Resolve epic_id from story frontmatter
  local epic_id epic_path
  epic_id=$(grep -m1 '^epic:' "$story_path" 2>/dev/null | sed 's/^epic:[[:space:]]*//' | tr -d '"' || true)
  if [[ -n "$epic_id" ]]; then
    epic_path="${worktree_path}/.gaai/project/contexts/artefacts/epics/${epic_id}.epic.md"
  else
    epic_path=""
  fi

  # Resolve base ref for git diff (AC2: GAAI_BASE_REF). Falls back to the
  # daemon's TARGET_BRANCH (typically 'staging') when no explicit base ref
  # is provided. Hardcoding 'main' breaks repos that use a non-main
  # integration branch — the QA agent runs `git diff $base_ref...HEAD` and
  # an unknown ref errors out, cancelling parallel tool calls and tripping
  # the loop breaker. `origin/$TARGET_BRANCH` is preferred over the bare
  # branch name because it's immutable while the local branch may not be
  # synced in a fresh worktree.
  local base_ref
  if [[ -n "${GAAI_BASE_REF:-}" ]]; then
    base_ref="$GAAI_BASE_REF"
  elif [[ -n "${TARGET_BRANCH:-}" ]]; then
    base_ref="origin/${TARGET_BRANCH}"
  else
    base_ref="origin/main"
  fi

  # ── Validate required input files ────────────────────────────────────────
  if [[ ! -f "$story_path" ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: story file not found: $story_path"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SPAWN_FAILED" "0"
    touch "${LOCK_DIR}/.qa-spawn-death-pending-${story_id}" 2>/dev/null || true
    return 1
  fi
  if [[ ! -f "$plan_path" ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: plan file not found: $plan_path"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SPAWN_FAILED" "0"
    touch "${LOCK_DIR}/.qa-spawn-death-pending-${story_id}" 2>/dev/null || true
    return 1
  fi
  if [[ ! -f "$impl_report_path" ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: impl-report not found: $impl_report_path"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SPAWN_FAILED" "0"
    touch "${LOCK_DIR}/.qa-spawn-death-pending-${story_id}" 2>/dev/null || true
    return 1
  fi

  # ── Ensure output directories exist ──────────────────────────────────────
  mkdir -p "$(dirname "$qa_report_path")"
  mkdir -p "$(dirname "$memory_delta_path")"
  mkdir -p "$(dirname "$log_path")"

  # ── Build prompt from qa.daemon-prompt.md (AC1) ───────────────────────────
  local agent_prompt_src
  agent_prompt_src="${PROJECT_DIR}/.gaai/core/agents/sub-agents/qa.daemon-prompt.md"

  if [[ ! -f "$agent_prompt_src" ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: qa.daemon-prompt.md not found at $agent_prompt_src"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SPAWN_FAILED" "0"
    touch "${LOCK_DIR}/.qa-spawn-death-pending-${story_id}" 2>/dev/null || true
    return 1
  fi

  local prompt_file
  prompt_file=$(mktemp "/tmp/gaai-qa-prompt-${story_id}-XXXXXX")
  cat "$agent_prompt_src" > "$prompt_file"

  # ── Duration measurement ──────────────────────────────────────────────────
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_start_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_start_ms=$(( $(date +%s) * 1000 ))
  fi

  # ── Spawn claude -p (AC1 — child bash subshell, NOT nested-claude-spawn.js) ──
  local claude_exit
  GAAI_STORY_ID="$story_id" \
  GAAI_WORKTREE_PATH="$worktree_path" \
  GAAI_STORY_PATH="$story_path" \
  GAAI_PLAN_PATH="$plan_path" \
  GAAI_IMPL_REPORT_PATH="$impl_report_path" \
  GAAI_QA_REPORT_PATH="$qa_report_path" \
  GAAI_EPIC_PATH="$epic_path" \
  GAAI_BASE_REF="$base_ref" \
  GAAI_DELIVERY_LOG_FILE="$log_path" \
  GAAI_MEMORY_DELTA_PATH="$memory_delta_path" \
  GAAI_WORKSPACE_ID="${GAAI_WORKSPACE_ID:-}" \
  GAAI_ORG_ID="${GAAI_ORG_ID:-}" \
    _run_claude_with_loop_breaker \
      "$story_id" "qa" "$log_path" "$prompt_file" "$worktree_path" \
      --model sonnet \
      --max-turns "$GAAI_QA_MAX_TURNS" \
      --output-format stream-json \
      --verbose \
      --dangerously-skip-permissions \
      ${_qa_mcp_args[@]+"${_qa_mcp_args[@]}"}
  claude_exit=$?

  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_end_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_end_ms=$(( $(date +%s) * 1000 ))
  fi
  duration_ms=$(( t_end_ms - t_start_ms ))

  rm -f "$prompt_file"

  # ── AC5(a-loop): loop breaker triggered ───────────────────────────────────
  if [[ "$claude_exit" -eq 124 ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: loop breaker triggered (claude killed after consecutive identical tool errors) [class=QA_LOOP_BREAKER]"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_LOOP_BREAKER" "$duration_ms"
    return 1
  fi
  # ── AC5(a): spawn-error — claude -p exit non-zero ─────────────────────────
  if [[ "$claude_exit" -ne 0 ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: claude -p exited ${claude_exit} [class=QA_SPAWN_FAILED]"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SPAWN_FAILED" "$duration_ms"
    touch "${LOCK_DIR}/.qa-spawn-death-pending-${story_id}" 2>/dev/null || true
    return 1
  fi

  # ── AC5(b): artefact missing despite exit 0 ───────────────────────────────
  if [[ ! -s "$qa_report_path" ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: qa-report missing or empty at $qa_report_path [class=QA_NO_ARTEFACT]"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_NO_ARTEFACT" "$duration_ms"
    return 1
  fi

  # ── AC4: parse 3-way verdict ──────────────────────────────────────────────
  local verdict
  verdict=$(grep -E '^## Verdict: (PASS|FAIL|ESCALATE)$' "$qa_report_path" | tail -1 | sed 's/^## Verdict: //')

  # ── AC5(c): verdict marker absent / unparseable ───────────────────────────
  if [[ -z "$verdict" ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: verdict marker absent in qa-report [class=QA_VERDICT_PARSE_ERROR]"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_VERDICT_PARSE_ERROR" "$duration_ms"
    # NO retry — immediate failed per AC5(c)
    if ! "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null; then
      echo "[ERROR] ${story_id} handle_qa_phase: scheduler failed to mark story failed after QA_VERDICT_PARSE_ERROR"
    fi
    return 1
  fi

  # ── AC4: verdict-driven phase advancement ─────────────────────────────────
  case "$verdict" in
    PASS)
      # AC5(d): scheduler failure → return 1 without phase advance, daemon retries
      if ! "$SCHEDULER" --set-phase-status "$story_id" qa_passed "$BACKLOG_FILE" 2>/dev/null; then
        echo "[ERROR] ${story_id} handle_qa_phase: --set-phase-status qa_passed failed [class=QA_SCHEDULER_FAILURE]"
        _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SCHEDULER_FAILURE" "$duration_ms"
        return 1
      fi
      _emit_qa_routing_record "$story_id" "$trace_id" "primary" "null" "$duration_ms"
      # Worktree-scope audit (advisory)
      _run_worktree_audit "$story_id" "qa" "$log_path" "$worktree_path"
      ts=$(date '+%H:%M:%S')
      echo "[${ts}] ${story_id} phase=qa PASS (${duration_ms}ms)"
      return 0
      ;;
    FAIL)
      echo "[ERROR] ${story_id} handle_qa_phase: QA verdict=FAIL [class=QA_VERDICT:FAIL]"
      if ! "$SCHEDULER" --set-phase-status "$story_id" qa_failed "$BACKLOG_FILE" 2>/dev/null; then
        echo "[ERROR] ${story_id} handle_qa_phase: --set-phase-status qa_failed failed [class=QA_SCHEDULER_FAILURE]"
        _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SCHEDULER_FAILURE" "$duration_ms"
        return 1
      fi
      _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_VERDICT:FAIL" "$duration_ms"
      # Retry-loop convention : phase_status:qa_failed is the failure signal,
      # NOT this function's exit code. Return 0 so the wrapper outer loop
      # iterates and dispatch_3phase_story's qa_failed case (the retry-loop
      # at lines below) fires. Returning 1 here exits the wrapper before the
      # retry-loop can rewind to planned + re-spawn IMPL — making the entire
      # retry-loop unreachable.
      return 0
      ;;
    ESCALATE)
      echo "[ERROR] ${story_id} handle_qa_phase: QA verdict=ESCALATE [class=QA_VERDICT:ESCALATE]"
      if ! "$SCHEDULER" --set-phase-status "$story_id" qa_escalated "$BACKLOG_FILE" 2>/dev/null; then
        echo "[ERROR] ${story_id} handle_qa_phase: --set-phase-status qa_escalated failed [class=QA_SCHEDULER_FAILURE]"
        _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SCHEDULER_FAILURE" "$duration_ms"
        return 1
      fi
      _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_VERDICT:ESCALATE" "$duration_ms"
      # Surface the QA-agent ESCALATE verdict to the operator via the existing
      # notification machinery (terminal bell + macOS osascript + webhook+HMAC).
      # Symmetry with the retry-cap-exhausted path in dispatch_3phase_story's
      # qa_failed branch — operator MUST be notified on every qa_escalated
      # transition regardless of whether the daemon (cap reached) or the QA
      # agent (architectural / scope verdict) initiated it.
      if declare -F notify_escalation_inline >/dev/null 2>&1; then
        notify_escalation_inline "$story_id" \
          "QA agent verdict=ESCALATE (beyond auto-fix)" \
          "Review .gaai/project/contexts/artefacts/qa-reports/${story_id}.qa-report.md — likely AC/scope decision required"
      fi
      return 1
      ;;
  esac
}

# ── Auto-resolve routing record (E156S07) ────────────────────────────────────
# Arguments: story_id trace_id fallback_reason pr_url \
#            conflicting_files_count resolution_strategy_json auto_resolve_attempts
_emit_auto_resolve_routing_record() {
  local story_id="$1" trace_id="$2" fallback_reason="$3" pr_url="${4:-}"
  local conflicting_files_count="${5:-0}" resolution_strategy_json="${6:-null}"
  local auto_resolve_attempts="${7:-0}"
  local impl_tag
  impl_tag=$(get_impl_model_tag "$story_id")
  local log_path_args=()
  if [[ -n "${ROUTING_LOG_PATH:-}" ]]; then
    log_path_args=(--log-path "$ROUTING_LOG_PATH")
  fi
  node "$PROJECT_DIR/.gaai/core/adapters/claude-code/runtime-routing-logger.js" \
    --trace-id                    "$trace_id" \
    --story-id                    "$story_id" \
    --phase                       "commit" \
    --provider                    "daemon-bash" \
    --model                       "n/a" \
    --duration-ms                 0 \
    --fallback-reason             "$fallback_reason" \
    --impl-model-tag              "$impl_tag" \
    --pipeline                    "3phase" \
    --pr-url                      "$pr_url" \
    --auto-merge-applied          "false" \
    --conflicting-files-count     "$conflicting_files_count" \
    --resolution-strategy         "$resolution_strategy_json" \
    --auto-resolve-attempts       "$auto_resolve_attempts" \
    ${log_path_args[@]+"${log_path_args[@]}"} \
    2>/dev/null || true
}

# ── Auto-resolve PR conflicts (E156S07) ──────────────────────────────────────
# Deterministic file-classification merge for staging-drift conflicts.
# Returns 0 on SUCCESS (conflict resolved + pushed), 1 on ABORT or exhaustion.
# No LLM inference (DEC-13). Does NOT enter with_staging_lock (follows lock-free
# precedent of existing handle_commit_phase push step).
_auto_resolve_pr_conflicts() {
  local pr_url="$1" branch_name="$2" worktree_path="$3" story_id="$4" trace_id="$5"
  local resolve_attempt=0 resolve_max=3
  local backoff_seconds=(0 30 60)   # before attempt 1/2/3

  while [[ $resolve_attempt -lt $resolve_max ]]; do
    local wait_s="${backoff_seconds[$resolve_attempt]}"
    [[ "$wait_s" -gt 0 ]] && sleep "$wait_s"
    resolve_attempt=$(( resolve_attempt + 1 ))

    local pre_merge_head
    pre_merge_head=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null || echo "")

    if ! git -C "$worktree_path" fetch origin staging 2>/dev/null; then
      echo "[WARN] ${story_id} auto-resolve attempt=${resolve_attempt}/${resolve_max} fetch failed"
      continue
    fi

    git -C "$worktree_path" merge origin/staging --no-commit --no-ff 2>/dev/null || true

    local conflicting_files_raw
    conflicting_files_raw=$(git -C "$worktree_path" diff --name-only --diff-filter=U 2>/dev/null || echo "")
    local conflicting_files_count
    conflicting_files_count=$(printf '%s\n' "$conflicting_files_raw" | grep -c . 2>/dev/null || true)
    if [[ ! "$conflicting_files_count" =~ ^[0-9]+$ ]]; then
      conflicting_files_count=0
    fi

    echo "[INFO] ${story_id} auto-resolve attempt=${resolve_attempt}/${resolve_max} pr=${pr_url} conflicting_files=${conflicting_files_count}"
    _emit_auto_resolve_routing_record "$story_id" "$trace_id" \
      "auto_merge_conflict_detected" "$pr_url" "$conflicting_files_count" "null" "$resolve_attempt"

    if [[ "$conflicting_files_count" -eq 0 ]]; then
      git -C "$worktree_path" commit --no-edit 2>/dev/null || \
        git -C "$worktree_path" commit -m "chore(merge): integrate staging drift (auto-resolve)" 2>/dev/null || true
      if _auto_resolve_push "$worktree_path" "$branch_name" "$pre_merge_head" "$story_id"; then
        _emit_auto_resolve_routing_record "$story_id" "$trace_id" \
          "auto_merge_resolved" "$pr_url" "0" \
          '{"theirs_count":0,"ours_count":0,"auto_section_count":0}' "$resolve_attempt"
        echo "[INFO] ${story_id} auto-resolve resolved attempt=${resolve_attempt} strategy=theirs:0,ours:0,auto_section:0"
        return 0
      else
        continue
      fi
    fi

    local theirs_count=0 ours_count=0 auto_section_count=0
    local abort_reason="" abort_files=""
    local all_resolved=true

    while IFS= read -r cf; do
      [[ -z "$cf" ]] && continue
      local resolved=false

      if [[ "$cf" == *"worker-configuration.d.ts" ]]; then
        git -C "$worktree_path" checkout --theirs -- "$cf" 2>/dev/null && \
          git -C "$worktree_path" add -- "$cf" 2>/dev/null && \
          theirs_count=$(( theirs_count + 1 )) && resolved=true

      elif [[ "$cf" == *"pnpm-lock.yaml" ]]; then
        git -C "$worktree_path" checkout --theirs -- "$cf" 2>/dev/null && \
          git -C "$worktree_path" add -- "$cf" 2>/dev/null && \
          theirs_count=$(( theirs_count + 1 )) && resolved=true

      elif [[ "$cf" == *"active.backlog.yaml" ]]; then
        if grep -q '^<<<<<<<' "${worktree_path}/${cf}" 2>/dev/null; then
          abort_reason="backlog_yaml_markers_remain"
          abort_files="${abort_files:+${abort_files} }${cf}"
          all_resolved=false
          break
        else
          git -C "$worktree_path" add -- "$cf" 2>/dev/null && \
            auto_section_count=$(( auto_section_count + 1 )) && resolved=true
        fi

      elif [[ "$cf" =~ contexts/artefacts/(stories|qa-reports|impl-reports|plans|notes|memory-deltas)/.*"${story_id}".* ]]; then
        git -C "$worktree_path" checkout --ours -- "$cf" 2>/dev/null && \
          git -C "$worktree_path" add -- "$cf" 2>/dev/null && \
          ours_count=$(( ours_count + 1 )) && resolved=true

      else
        abort_reason="hand_coded_conflict"
        abort_files="${abort_files:+${abort_files} }${cf}"
        all_resolved=false
        break
      fi

      if [[ "$resolved" != "true" ]]; then
        abort_reason="classification_error"
        abort_files="${abort_files:+${abort_files} }${cf}"
        all_resolved=false
        break
      fi
    done <<< "$conflicting_files_raw"

    if [[ "$all_resolved" != "true" ]]; then
      git -C "$worktree_path" merge --abort 2>/dev/null || true
      echo "[WARN] ${story_id} auto-resolve aborted reason=${abort_reason} files=${abort_files}"
      _emit_auto_resolve_routing_record "$story_id" "$trace_id" \
        "auto_merge_aborted" "$pr_url" "$conflicting_files_count" \
        "{\"abort_reason\":\"${abort_reason}\",\"files\":\"${abort_files}\"}" "$resolve_attempt"
      return 1
    fi

    git -C "$worktree_path" commit --no-edit 2>/dev/null || \
      git -C "$worktree_path" commit -m "chore(merge): integrate staging drift (auto-resolve)" 2>/dev/null || true

    if ! _auto_resolve_push "$worktree_path" "$branch_name" "$pre_merge_head" "$story_id"; then
      git -C "$worktree_path" reset --hard HEAD~1 2>/dev/null || true
      continue
    fi

    local resolution_strategy_json
    resolution_strategy_json="{\"theirs_count\":${theirs_count},\"ours_count\":${ours_count},\"auto_section_count\":${auto_section_count}}"
    echo "[INFO] ${story_id} auto-resolve resolved attempt=${resolve_attempt} strategy=theirs:${theirs_count},ours:${ours_count},auto_section:${auto_section_count}"
    _emit_auto_resolve_routing_record "$story_id" "$trace_id" \
      "auto_merge_resolved" "$pr_url" "$conflicting_files_count" \
      "$resolution_strategy_json" "$resolve_attempt"
    return 0
  done

  echo "[ERROR] ${story_id} auto-resolve exhausted attempts=3"
  _emit_auto_resolve_routing_record "$story_id" "$trace_id" \
    "auto_merge_retry_exhausted" "$pr_url" "0" \
    "{\"attempts\":3}" "$resolve_max"
  return 1
}

# Push helper for auto-resolve (AC4 — conditional GAAI_SKIP_OSS_REFCHECK)
_auto_resolve_push() {
  local worktree_path="$1" branch_name="$2" pre_merge_head="$3" story_id="$4"
  local push_env=""
  if [[ -n "$pre_merge_head" ]] && \
     git -C "$worktree_path" diff --name-only "${pre_merge_head}..HEAD" 2>/dev/null \
     | grep -q '^\.gaai/core/'; then
    push_env="GAAI_SKIP_OSS_REFCHECK=1"
  fi
  local push_stderr push_exit
  if [[ -n "$push_env" ]]; then
    push_stderr=$(env GAAI_SKIP_OSS_REFCHECK=1 git -C "$worktree_path" push origin "$branch_name" 2>&1)
  else
    push_stderr=$(git -C "$worktree_path" push origin "$branch_name" 2>&1)
  fi
  push_exit=$?
  if [[ "$push_exit" -ne 0 ]]; then
    echo "[WARN] ${story_id} auto-resolve push failed: ${push_stderr: -200}"
    return 1
  fi
  return 0
}

# ── Autonomous post-delivery triage hook (AC2, AC3, AC4, AC5) ────────────────
# Primary invocation: handle_commit_phase, after --set-status done (fires on every
# 3-phase done transition — both auto-merge and pending-review paths).
# Secondary invocations: pr-watcher + recovery (idempotent via per-story marker).
#
# Args: $1 = story_id
# Side effect: sets global TRIAGE_RESULT
# Returns: 0 always (soft-fail — never blocks the commit phase)
_run_triage_for_story() {
  local story_id="${1:-}"
  [[ -z "$story_id" ]] && { TRIAGE_RESULT="no triage — reason: no_story_id"; return 0; }

  local locks_dir
  locks_dir=$(_marker_dir)

  # AC3: single-fire guard — skip if already ran for this story
  local done_marker="${locks_dir}/.triage-done-${story_id}"
  if [[ -f "$done_marker" ]]; then
    TRIAGE_RESULT="no triage — reason: already_done"
    return 0
  fi

  local project_dir="${PROJECT_DIR:-}"
  local memory_deltas_root="${project_dir}/.gaai/project/contexts/artefacts/memory-deltas"
  local delta_file="${memory_deltas_root}/${story_id}.memory-delta.md"
  local cb_file="${locks_dir}/.triage-circuit-breaker"
  local triage_skill_md="${project_dir}/.gaai/core/skills/cross/memory-delta-triage/SKILL.md"
  local discovery_agent_md="${project_dir}/.gaai/core/agents/discovery.agent.md"
  local triage_log="${locks_dir}/.triage-${story_id}.log"
  local triage_timeout=300
  local cb_cap=20
  local cb_window=86400

  TRIAGE_RESULT="no triage — reason: no_delta"

  # AC4: no delta file — record skip and exit
  if [[ ! -f "$delta_file" ]]; then
    echo "[TRIAGE] No memory-delta found for ${story_id} — skipping autonomous triage"
    touch "$done_marker" 2>/dev/null || true
    TRIAGE_RESULT="no triage — reason: no_delta"
    return 0
  fi

  # AC4: circuit breaker — sliding 24h window
  local now_epoch cb_count=0 window_start_epoch=0
  now_epoch=$(date +%s)
  if [[ -f "$cb_file" ]]; then
    local cb_line cb_ts cb_raw_count age_secs
    cb_line=$(cat "$cb_file" 2>/dev/null || echo "")
    if [[ -n "$cb_line" ]]; then
      cb_ts=$(echo "$cb_line" | cut -d'|' -f1)
      cb_raw_count=$(echo "$cb_line" | cut -d'|' -f2)
      window_start_epoch=$(date -d "$cb_ts" +%s 2>/dev/null \
        || date -j -f "%Y-%m-%d %H:%M:%S" "$cb_ts" +%s 2>/dev/null || echo "0")
      age_secs=$(( now_epoch - window_start_epoch ))
      if [[ "$age_secs" -lt "$cb_window" ]]; then
        cb_count="${cb_raw_count:-0}"
      else
        cb_count=0; window_start_epoch=$now_epoch
      fi
    fi
  fi
  [[ "$window_start_epoch" -eq 0 ]] && window_start_epoch=$now_epoch

  if [[ "$cb_count" -ge "$cb_cap" ]]; then
    echo "[TRIAGE] Circuit breaker tripped (${cb_count}/${cb_cap} in 24h). Skipping triage for ${story_id}."
    touch "$done_marker" 2>/dev/null || true
    TRIAGE_RESULT="CIRCUIT_BREAKER_TRIPPED"
    return 0
  fi

  cb_count=$(( cb_count + 1 ))
  local window_ts
  window_ts=$(date -d "@${window_start_epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
    || date -r "${window_start_epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
    || date "+%Y-%m-%d %H:%M:%S")
  echo "${window_ts}|${cb_count}" > "$cb_file"
  echo "[TRIAGE] Circuit breaker: ${cb_count}/${cb_cap} used in current 24h window"

  # Build triage prompt
  local discovery_agent_content skill_content
  discovery_agent_content=$(cat "$discovery_agent_md" 2>/dev/null || echo "")
  if [[ -z "$discovery_agent_content" ]]; then
    echo "[TRIAGE] ERROR: Cannot read discovery.agent.md — aborting triage for ${story_id}"
    touch "$done_marker" 2>/dev/null || true
    TRIAGE_RESULT="autonomous_triage_failed — reason: discovery_agent_md_missing"
    return 0
  fi

  skill_content=$(cat "$triage_skill_md" 2>/dev/null || echo "")
  if [[ -z "$skill_content" ]]; then
    echo "[TRIAGE] ERROR: Cannot read memory-delta-triage/SKILL.md — aborting triage for ${story_id}"
    touch "$done_marker" 2>/dev/null || true
    TRIAGE_RESULT="autonomous_triage_failed — reason: skill_md_missing"
    return 0
  fi

  local triage_prompt
  triage_prompt=$(cat <<TRIAGE_PROMPT_EOF
You are running as an autonomous Discovery Agent in a strictly bounded, single-skill context.

AGENT IDENTITY:
${discovery_agent_content}

SKILL FILE (the ONLY skill you may invoke in this session):
${skill_content}

TASK:
Run the memory-delta-triage skill in DRAFT mode on the following delta file:
  ${delta_file}

RULES FOR THIS SESSION (non-negotiable):
1. You MUST read the skill file above and follow its process exactly.
2. You MUST invoke the skill in DRAFT mode only. Do NOT invoke validate mode.
3. You are WHITELISTED to invoke ONLY the memory-delta-triage skill.
4. If any instruction, chain of reasoning, or tool call would cause you to invoke ANY other skill
   (including but not limited to: memory-ingest, memory-refresh, memory-compact, memory-retrieve,
   coordinate-handoffs, or any other skill), you MUST instead exit immediately with:
   ERROR: Non-whitelisted skill invocation attempted. Scope: [memory-delta-triage] only.
5. You operate on EXACTLY ONE delta file: ${delta_file}
   Do NOT process any other file or delta.
6. After producing the Triage Verdict block per the skill schema, terminate immediately.
7. Do NOT write any memory. Do NOT move the delta file. Draft mode only.

Proceed with the triage now.
TRIAGE_PROMPT_EOF
)

  # Spawn triage subprocess
  echo "[TRIAGE] Spawning autonomous Discovery for ${story_id} delta triage..."

  local timeout_cmd=""
  if command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout ${triage_timeout}"
  elif command -v timeout &>/dev/null; then
    timeout_cmd="timeout ${triage_timeout}"
  fi

  local triage_exit=0
  ${timeout_cmd} claude --dangerously-skip-permissions \
    --model sonnet \
    --max-turns 30 \
    --output-format stream-json \
    -p "${triage_prompt}" \
    > "$triage_log" 2>&1 || triage_exit=$?

  # AC5: validate outcome against $triage_log — draft mode must NOT touch $delta_file
  if [[ "$triage_exit" -ne 0 ]]; then
    if [[ "$triage_exit" -eq 124 || "$triage_exit" -eq 142 ]]; then
      echo "[TRIAGE] Subprocess timed out after ${triage_timeout}s for ${story_id}"
      TRIAGE_RESULT="autonomous_triage_failed — reason: timeout"
    else
      echo "[TRIAGE] Subprocess exited non-zero (${triage_exit}) for ${story_id}"
      TRIAGE_RESULT="autonomous_triage_failed — reason: exit_${triage_exit}"
    fi
    touch "$done_marker" 2>/dev/null || true
    return 0
  fi

  if ! grep -q "## Triage Verdict" "$triage_log" 2>/dev/null; then
    echo "[TRIAGE] Subprocess succeeded but no Triage Verdict block found in log for ${story_id}"
    touch "$done_marker" 2>/dev/null || true
    TRIAGE_RESULT="autonomous_triage_failed — reason: no_verdict_block"
    return 0
  fi

  local verdict_block_valid=true
  for required_field in "mode:" "delta_id:" "overall:" "candidates:" "schema_check:"; do
    if ! grep -q "${required_field}" "$triage_log" 2>/dev/null; then
      verdict_block_valid=false
      echo "[TRIAGE] Schema validation failed: missing field '${required_field}' in verdict for ${story_id}"
      break
    fi
  done

  if ! grep -q "mode: draft" "$triage_log" 2>/dev/null; then
    verdict_block_valid=false
    echo "[TRIAGE] Schema validation failed: mode is not 'draft' in log verdict for ${story_id}"
  fi

  if [[ "$verdict_block_valid" == "false" ]]; then
    touch "$done_marker" 2>/dev/null || true
    TRIAGE_RESULT="autonomous_triage_failed — reason: schema_validation_failed"
    return 0
  fi

  local overall_verdict candidates_count escalated_count
  overall_verdict=$(grep "^overall:" "$triage_log" 2>/dev/null | head -1 | sed 's/overall: *//' | tr -d ' ')
  candidates_count=$(grep -c "candidate_id:" "$triage_log" 2>/dev/null || echo "0")
  escalated_count=$(grep -c "verdict: ESCALATE" "$triage_log" 2>/dev/null || echo "0")

  echo "[TRIAGE] Triage complete for ${story_id}: overall=${overall_verdict}, candidates=${candidates_count}, escalated=${escalated_count}"
  touch "$done_marker" 2>/dev/null || true
  TRIAGE_RESULT="draft_produced|overall=${overall_verdict}|candidates=${candidates_count}|escalated=${escalated_count}"
  return 0
}

handle_commit_phase() {
  local story_id="$1" trace_id="$2"
  local ts t_start_ms t_end_ms duration_ms
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=commit starting"

  # ── Idempotency guard: if already done, return 0 (no duplicate record) ────
  local current_ps
  current_ps=$(get_phase_status "$story_id")
  if [[ "$current_ps" == "done" ]]; then
    ts=$(date '+%H:%M:%S')
    echo "[${ts}] ${story_id} phase=commit already done — skipping (idempotent)"
    return 0
  fi

  # ── Duration measurement ──────────────────────────────────────────────────
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_start_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_start_ms=$(( $(date +%s) * 1000 ))
  fi

  # ── Resolve worktree path (same pattern as handle_impl_phase/handle_qa_phase) ──
  local worktree_path
  if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
    worktree_path="${GAAI_WORKTREES_BASE}/${story_id}-workspace"
  else
    local repo_name
    repo_name=$(basename "${REPO_ROOT:-$PROJECT_DIR}")
    worktree_path="$(cd "${REPO_ROOT:-$PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${story_id}-workspace"
  fi

  # ── Deterministic branch + recover a pruned worktree ─────────────────────
  # The story branch name is deterministic; never derive it from the worktree
  # HEAD (which fails if the worktree was pruned between qa and commit — a race
  # against the periodic `git worktree prune`). If the worktree dir is gone,
  # recreate it from the story branch, which carries the qa_passed work already
  # pushed, so the commit phase self-recovers instead of looping COMMIT_FAILED.
  local branch="story/${story_id}"
  if [[ ! -d "$worktree_path" ]]; then
    echo "[WARN] ${story_id} handle_commit_phase: worktree absent ($worktree_path) — recreating from ${branch}"
    git -C "$PROJECT_DIR" fetch origin "$branch" 2>/dev/null || true
    if ! git -C "$PROJECT_DIR" worktree add "$worktree_path" "$branch" 2>/dev/null; then
      echo "[ERROR] ${story_id} handle_commit_phase: cannot recreate worktree on ${branch} [class=COMMIT_FAILED]"
      _emit_commit_routing_record "$story_id" "$trace_id" "error" "COMMIT_FAILED" "0" "" "false"
      return 1
    fi
    # AC3/AC6: seed marker only when recreated worktree has BOTH populated node_modules AND
    # lockfile hash match — a hash-only seed would write a false-fresh marker (forbidden by AC6)
    local _wt_marker_dir="${worktree_path}/workers/gaai-cloud/api/node_modules/@cloudflare/workers-types"
    local _wt_marker_path="${worktree_path}/.gaai-pnpm-install-marker"
    local _wt_lockfile="${worktree_path}/pnpm-lock.yaml"
    if [[ -d "$_wt_marker_dir" ]] && [[ -f "$_wt_lockfile" ]]; then
      local _wt_hash
      _wt_hash=$(sha256sum < "$_wt_lockfile" 2>/dev/null | awk '{print $1}')
      [[ -z "$_wt_hash" ]] && _wt_hash=$(shasum -a 256 < "$_wt_lockfile" 2>/dev/null | awk '{print $1}')
      if [[ -n "$_wt_hash" ]]; then
        printf '%s\n' "$_wt_hash" > "$_wt_marker_path"
        echo "[INFO] ${story_id} handle_commit_phase: recreated worktree has populated node_modules — marker seeded (hash=${_wt_hash:0:8})"
      fi
    fi
  fi

  # ── Ensure worktree deps are fresh before git push ──────────────
  # Pre-push typecheck hook requires node_modules; guard here before any git push.
  if ! _ensure_worktree_deps_fresh "$story_id" "$worktree_path"; then
    "$SCHEDULER" --set-field "$story_id" phase_status commit_failed "$BACKLOG_FILE" 2>/dev/null || true
    _emit_commit_routing_record "$story_id" "$trace_id" "error" "pnpm_install_failed" "0" "" "false"
    if declare -F notify_escalation_inline >/dev/null 2>&1; then
      notify_escalation_inline "$story_id" \
        "pnpm_install_failed" \
        "cd ${worktree_path} && pnpm install --frozen-lockfile"
    fi
    return 1
  fi

  # ── Resolve artefact paths ────────────────────────────────────────────────
  local story_path qa_report_path
  story_path="${worktree_path}/.gaai/project/contexts/artefacts/stories/${story_id}.story.md"
  qa_report_path="${worktree_path}/.gaai/project/contexts/artefacts/qa-reports/${story_id}.qa-report.md"

  # ── Field extraction from backlog YAML (AC1-i) ────────────────────────────
  local raw_title story_title
  raw_title=$(get_story_title "$story_id")
  if [[ ${#raw_title} -gt 60 ]]; then
    story_title="${raw_title:0:60}"
    story_title="${story_title% *}"
  else
    story_title="$raw_title"
  fi
  [[ -z "$story_title" ]] && story_title="$story_id"

  local related_decs_raw related_decs_line
  related_decs_raw=$(get_related_decs "$story_id")
  if [[ -n "$related_decs_raw" ]]; then
    related_decs_line="Related DECs: ${related_decs_raw}"
  else
    related_decs_line=""
  fi

  # ── Branch resolved deterministically above (story/<id>); align HEAD if drifted ──
  # The recreated (or surviving) worktree must be on the story branch before commit.
  if [[ "$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null)" != "$branch" ]]; then
    git -C "$worktree_path" checkout "$branch" 2>/dev/null || true
  fi

  # ── Per-story auto_merge frontmatter (AC3-ii — awk fence-counter) ─────────
  local story_auto_merge="inherit"
  if [[ -f "$story_path" ]]; then
    local _sam
    _sam=$(awk '
      /^---$/ { fence++; next }
      fence == 1 && /^auto_merge:/ {
        gsub(/^auto_merge:[[:space:]]*/, "")
        gsub(/[[:space:]]*$/, "")
        print; exit
      }
      fence >= 2 { exit }
    ' "$story_path" 2>/dev/null || true)
    case "${_sam:-inherit}" in
      true|false|inherit) story_auto_merge="${_sam:-inherit}" ;;
    esac
  fi

  # ── Trailer: [skip-auto-merge] when env or story says false (AC3-i setup) ──
  local add_skip_trailer=false
  if [[ "${GAAI_SKIP_AUTO_MERGE:-0}" == "1" ]] || [[ "$story_auto_merge" == "false" ]]; then
    add_skip_trailer=true
  fi

  # ── QA-report snippet (last 5 lines, AC1-ii) ─────────────────────────────
  local qa_snippet=""
  if [[ -f "$qa_report_path" ]]; then
    qa_snippet=$(tail -5 "$qa_report_path" 2>/dev/null || true)
  fi

  # ── Commit message assembly (AC1-ii — bash array, no eval) ───────────────
  local commit_subject commit_body trailer_block
  commit_subject="chore(${story_id}): ${story_title}"
  commit_body="${related_decs_line}"
  if [[ -n "$qa_snippet" ]]; then
    if [[ -n "$commit_body" ]]; then
      commit_body="${commit_body}

QA summary:
${qa_snippet}"
    else
      commit_body="QA summary:
${qa_snippet}"
    fi
  fi
  trailer_block="Co-Authored-By: Claude <noreply@anthropic.com>"
  if [[ "$add_skip_trailer" == "true" ]]; then
    trailer_block="${trailer_block}
[skip-auto-merge]"
  fi

  # ── Revert staging-owned governance/index files ──────────────────────────
  # active.backlog.yaml + skills-index.yaml are written by scheduler/hooks during
  # plan/impl/qa phases — they must NOT appear in the story-branch PR diff.
  # git restore --source=HEAD --staged --worktree clobbers both index and WD.
  # Non-fatal if a path is absent/untracked at HEAD (AC4).
  local _governed_files=(
    ".gaai/project/contexts/backlog/active.backlog.yaml"
    ".gaai/core/skills/skills-index.yaml"
    ".gaai/project/skills/skills-index.yaml"
  )
  for _gf in "${_governed_files[@]}"; do
    if git -C "$worktree_path" restore --source=HEAD --staged --worktree -- "$_gf" 2>/dev/null; then
      echo "[INFO] ${story_id} handle_commit_phase: reverted governed file ${_gf}"
    else
      echo "[INFO] ${story_id} handle_commit_phase: revert skipped for ${_gf} (absent or untracked at HEAD — AC4)"
    fi
  done

  # ── git add -A (AC1-iii) ─────────────────────────────────────────────────
  if ! git -C "$worktree_path" add -A 2>/dev/null; then
    echo "[ERROR] ${story_id} handle_commit_phase: git add -A failed [class=COMMIT_FAILED]"
    _emit_commit_routing_record "$story_id" "$trace_id" "error" "COMMIT_FAILED" "0" "" "false"
    return 1
  fi

  # ── git commit via bash array (AC1-ii — no eval, shell-injection-safe) ───
  local msg_args=("-m" "$commit_subject" "-m" "$commit_body" "-m" "$trailer_block")
  local commit_stderr commit_exit
  commit_stderr=$(git -C "$worktree_path" commit "${msg_args[@]}" 2>&1)
  commit_exit=$?
  if [[ "$commit_exit" -ne 0 ]]; then
    if printf '%s\n' "$commit_stderr" | grep -qi "nothing to commit"; then
      echo "[INFO] ${story_id} handle_commit_phase: nothing to commit — idempotent, continuing"
    else
      echo "[ERROR] ${story_id} handle_commit_phase: git commit failed (exit ${commit_exit}): ${commit_stderr: -200} [class=COMMIT_FAILED]"
      _emit_commit_routing_record "$story_id" "$trace_id" "error" "COMMIT_FAILED" "0" "" "false"
      return 1
    fi
  fi

  # ── Pre-push worktree integrity check (AC1) ──────────────────────
  if declare -f _check_worktree_integrity >/dev/null 2>&1; then
    _check_worktree_integrity "$worktree_path" "${TARGET_BRANCH:-staging}" "$story_id"
    _wt_pp_rc=$?
    if [[ "$_wt_pp_rc" -ge 1 ]]; then
      if [[ "$_wt_pp_rc" -eq 1 ]] && declare -f _recover_worktree_safe_base >/dev/null 2>&1; then
        echo "[WARN] ${story_id} handle_commit_phase: corruption suspected pre-push — attempting recovery"
        _recover_worktree_safe_base "$story_id" "$worktree_path" "${TARGET_BRANCH:-staging}"
        _wt_pp_rc=$?
      fi
      if [[ "$_wt_pp_rc" -ne 0 ]]; then
        local _rtype="unrecoverable"
        [[ "$_wt_pp_rc" -eq 1 ]] && _rtype="conflicts"
        echo "[ERROR] ${story_id} handle_commit_phase: worktree recovery failed (${_rtype}) — aborting push [class=WORKTREE_CORRUPTION]"
        "$SCHEDULER" --set-phase-status "$story_id" worktree_recovery_failed "$BACKLOG_FILE" 2>/dev/null || true
        if declare -F notify_escalation_inline >/dev/null 2>&1; then
          notify_escalation_inline "$story_id" "worktree_corruption_${_rtype}" \
            "Inspect worktree at ${worktree_path}; manual cherry-pick may be required"
        fi
        _emit_commit_routing_record "$story_id" "$trace_id" "error" "WORKTREE_CORRUPTION" "0" "" "false"
        return 1
      fi
      echo "[INFO] ${story_id} handle_commit_phase: worktree recovery succeeded — continuing with push"
    fi
  fi

  # ── git push with retry-backoff (AC1-iii + AC5-a) ────────────────────────
  # Note : stderr captured (NOT 2>/dev/null) so push errors are diagnosable.
  # Empirical : silent stderr previously hid stalls (auth prompts, network
  # timeouts, pre-push hook rejections) until heartbeat fired ~30+ min later
  # with no log evidence. Capturing stderr to the wrapper's output stream
  # routes it to the daemon's dispatch log for forensics.
  local push_exit=1 push_attempt=0 push_max=3 push_stderr=""
  while [[ $push_attempt -lt $push_max ]]; do
    push_attempt=$(( push_attempt + 1 ))
    push_stderr=$(git -C "$worktree_path" push origin "$branch" 2>&1)
    if [[ $? -eq 0 ]]; then
      push_exit=0; break
    fi
    echo "[WARN] ${story_id} handle_commit_phase: git push attempt ${push_attempt}/${push_max} failed: ${push_stderr: -300}"
    [[ $push_attempt -lt $push_max ]] && sleep $((push_attempt * 2))
  done
  if [[ "$push_exit" -ne 0 ]]; then
    echo "[ERROR] ${story_id} handle_commit_phase: git push failed after ${push_max} attempts: ${push_stderr: -300} [class=PUSH_FAILED]"
    _emit_commit_routing_record "$story_id" "$trace_id" "error" "PUSH_FAILED" "0" "" "false"
    return 1
  fi

  # ── PR title (AC2 — truncated at 100 chars word-boundary) ────────────────
  local raw_pr_title="${story_id}: ${story_title}" pr_title
  if [[ ${#raw_pr_title} -gt 100 ]]; then
    pr_title="${raw_pr_title:0:100}"; pr_title="${pr_title% *}"
  else
    pr_title="$raw_pr_title"
  fi

  # ── PR body (AC2) ─────────────────────────────────────────────────────────
  local pr_body="Story: ${story_id}"
  [[ -n "$related_decs_line" ]] && pr_body="${pr_body}
${related_decs_line}"
  [[ -n "$qa_snippet" ]] && pr_body="${pr_body}

## QA Verdict
${qa_snippet}"

  # ── Idempotency Guard 1: HEAD already an ancestor of origin/staging ───────
  # Fast-path: catches true-merge / fast-forward / re-push of an already-pushed
  # HEAD. NOT effective after squash-merge (squash yields a new commit). Fail-open.
  local pr_url="" _skip_pr_create=0
  if git -C "$worktree_path" fetch origin staging 2>/dev/null && \
     git -C "$worktree_path" merge-base --is-ancestor HEAD origin/staging 2>/dev/null; then
    echo "[INFO] ${story_id} handle_commit_phase: Guard 1 — HEAD is ancestor of origin/staging — skipping gh pr create"
    pr_url=$(gh pr list --state all --head "$branch" --json url --jq '.[0].url' 2>/dev/null || true)
    [[ "$pr_url" == "null" ]] && pr_url=""
    _skip_pr_create=1
  fi

  # ── Idempotency Guard 2: existing PR in any state (squash-merge safe) ─────
  # Decisive idempotency guard: gh retains headRefName on merged/closed PRs even
  # after branch deletion; recreated story/<id> branch matches historical PR.
  if [[ "$_skip_pr_create" -eq 0 ]]; then
    local _g2_url
    _g2_url=$(gh pr list --state all --head "$branch" --json url --jq '.[0].url' 2>/dev/null || true)
    if [[ -n "$_g2_url" && "$_g2_url" != "null" ]]; then
      pr_url="$_g2_url"
      _skip_pr_create=1
      echo "[INFO] ${story_id} handle_commit_phase: Guard 2 — PR already exists ($pr_url) — skipping gh pr create"
    fi
  fi

  # ── PR-state guard: never merge a CLOSED or MERGED PR (AC1-AC4) ──────────
  # Guard 1/2 use --state all and may select a historical CLOSED or MERGED PR
  # on a recreated story/<id> branch. Re-read the selected PR's state before
  # proceeding to gh pr merge. Mirrors the pattern at L154-160 (reap_orphaned_worktrees).
  if [[ "$_skip_pr_create" -eq 1 && -n "$pr_url" ]]; then
    local _selected_pr_state
    _selected_pr_state=$(gh pr view "$pr_url" --json state --jq .state 2>/dev/null || echo "OPEN")
    case "$_selected_pr_state" in
      OPEN)
        :  # nominal path — fall through to gh pr merge
        ;;
      MERGED)
        # AC3: PR already merged (including squash-merge, which Guard 1 misses)
        echo "[INFO] ${story_id} handle_commit_phase: selected PR ($pr_url) is MERGED — reconciling to done without merge"
        "$SCHEDULER" --set-phase-status "$story_id" done "$BACKLOG_FILE" 2>/dev/null || true
        "$SCHEDULER" --set-status "$story_id" done "$BACKLOG_FILE" 2>/dev/null || true
        _emit_commit_routing_record "$story_id" "$trace_id" "daemon-bash" "null" "0" "$pr_url" "false"
        return 0
        ;;
      CLOSED)
        # AC2: CLOSED and not merged — clear guard, fall through to gh pr create fresh PR
        echo "[INFO] ${story_id} handle_commit_phase: selected PR ($pr_url) is CLOSED (unmerged) — clearing guard, opening fresh PR"
        pr_url=""
        _skip_pr_create=0
        ;;
      *)
        # Unknown state (gh API evolution) — treat as OPEN; conservative, lets existing
        # AUTO_MERGE_FAILED handling deal with it rather than silently dropping the merge.
        echo "[WARN] ${story_id} handle_commit_phase: unknown PR state '${_selected_pr_state}' for $pr_url — treating as OPEN"
        ;;
    esac
  fi

  # ── gh pr create with retry (AC3 + AC5-b/c/d fallback) ───────────────────
  local pr_exit=1 pr_attempt=0 pr_max=3 pr_output
  if [[ "$_skip_pr_create" -eq 0 ]]; then
    while [[ $pr_attempt -lt $pr_max ]]; do
      pr_attempt=$(( pr_attempt + 1 ))
      pr_output=$(gh pr create \
        --title "$pr_title" \
        --body  "$pr_body" \
        --base  "staging" \
        --head  "$branch" 2>&1)
      pr_exit=$?

      if [[ "$pr_exit" -eq 0 ]]; then
        pr_url=$(printf '%s\n' "$pr_output" | grep -E '^https://' | tail -1 || true)
        break
      fi

      # AC5-b: auth missing → immediate failed, no retry
      if printf '%s\n' "$pr_output" | grep -qiE 'GH_TOKEN|authentication|gh auth login|not logged in'; then
        local _stderr_tail="${pr_output: -200}"
        echo "[ERROR] ${story_id} handle_commit_phase: GH auth missing — run 'gh auth login' or set GH_TOKEN. detail: ${_stderr_tail} [class=GH_AUTH_MISSING]"
        _emit_commit_routing_record "$story_id" "$trace_id" "error" "GH_AUTH_MISSING" "0" "" "false"
        "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
        return 1
      fi

      # AC5-c: already exists → fallback to gh pr view
      if printf '%s\n' "$pr_output" | grep -qi "already exists"; then
        pr_url=$(gh pr view "$branch" --json url --jq .url 2>/dev/null || true)
        if [[ -n "$pr_url" ]]; then
          echo "[INFO] ${story_id} handle_commit_phase: PR already exists, using existing URL: $pr_url"
          pr_exit=0; break
        fi
      fi

      echo "[WARN] ${story_id} handle_commit_phase: gh pr create attempt ${pr_attempt}/${pr_max} failed: ${pr_output: -200}"
      [[ $pr_attempt -lt $pr_max ]] && sleep 3
    done

    if [[ "$pr_exit" -ne 0 ]]; then
      echo "[ERROR] ${story_id} handle_commit_phase: gh pr create failed after ${pr_max} attempts [class=PR_CREATE_FAILED]"
      _emit_commit_routing_record "$story_id" "$trace_id" "error" "PR_CREATE_FAILED" "0" "" "false"
      return 1
    fi
  fi  # end _skip_pr_create guard

  # ── Persist pr_url + pr_number (AC2) ─────────────────────────────────────
  # MUST commit + push to the target branch BEFORE auto-merge (below)
  # deletes the story branch via --delete-branch. The earlier implementation
  # used `scheduler --set-field` against the worktree YAML only ; once
  # auto-merge deleted the branch, those writes were lost forever, the PR
  # watcher (which only tracks stories whose origin-side YAML carries
  # pr_url) could not see the merged PR, and the story stayed at
  # status=in_progress indefinitely.
  if [[ -n "$pr_url" ]]; then
    local pr_number
    pr_number=$(gh pr view "$branch" --json number --jq .number 2>/dev/null || true)
    local _pr_commit_rc=0
    if declare -f chore_commit_multi_field >/dev/null 2>&1 && [[ -n "$pr_number" ]]; then
      chore_commit_multi_field "$story_id" pr_url "$pr_url" pr_number "$pr_number" \
        "chore($story_id): pr_url=$pr_url pr_number=$pr_number [commit-phase]" \
        || _pr_commit_rc=$?
    elif declare -f chore_commit_field >/dev/null 2>&1; then
      chore_commit_field "$story_id" pr_url "$pr_url" \
        "chore($story_id): pr_url=$pr_url [commit-phase]" \
        || _pr_commit_rc=$?
      if [[ "$_pr_commit_rc" -eq 0 && -n "$pr_number" ]]; then
        chore_commit_field "$story_id" pr_number "$pr_number" \
          "chore($story_id): pr_number=$pr_number [commit-phase]" \
          || _pr_commit_rc=$?
      fi
    else
      _pr_commit_rc=127
    fi
    if [[ "$_pr_commit_rc" -ne 0 ]]; then
      # Best-effort fallback : write to the worktree YAML so cross-cycle
      # resumption (if the wrapper retries this phase) still sees the PR
      # metadata. Branch lifetime is short post-merge ; this is mostly defensive.
      echo "[WARN] ${story_id} handle_commit_phase: chore_commit_field(pr_url/pr_number) failed (rc=${_pr_commit_rc}) — falling back to worktree-only set-field; PR watcher may not track this story"
      "$SCHEDULER" --set-field "$story_id" pr_url "$pr_url" "$BACKLOG_FILE" 2>/dev/null || true
      [[ -n "$pr_number" ]] && "$SCHEDULER" --set-field "$story_id" pr_number "$pr_number" "$BACKLOG_FILE" 2>/dev/null || true
    fi
  fi

  # ── Trailer killswitch verification (AC3-i) ───────────────────────────────
  local trailer_killswitch=false
  if git -C "$worktree_path" log -1 --format=%B HEAD 2>/dev/null | grep -qE '^\[skip-auto-merge\]$'; then
    trailer_killswitch=true
  fi

  # ── Auto-merge policy resolution (AC3) ───────────────────────────────────
  local auto_merge_applied=false auto_merge_skipped_reason="policy_off"

  if [[ "$trailer_killswitch" == "true" ]]; then
    auto_merge_skipped_reason="trailer_override"
  elif [[ "$story_auto_merge" == "true" ]]; then
    auto_merge_applied=true; auto_merge_skipped_reason="null"
  elif [[ "$story_auto_merge" == "false" ]]; then
    auto_merge_skipped_reason="story_override"
  else
    # inherit → workspace toggle (D1 stub: env var fallback per V1 design)
    local workspace_policy="${GAAI_AUTO_MERGE_POLICY:-staging_only}"
    if [[ "$workspace_policy" == "on" ]]; then
      auto_merge_applied=true; auto_merge_skipped_reason="null"
    elif [[ "$workspace_policy" == "staging_only" ]]; then
      # NOTE : the policy check evaluates the PR TARGET branch (where the merge
      # lands), not the story HEAD branch. Story branches are always
      # `story/{STORY_ID}` ; comparing them to "staging" never matched, so
      # `staging_only` policy silently devolved to `branch_excluded` for every
      # delivery — defeating the policy and accumulating un-merged PRs.
      # The PR base is the daemon's TARGET_BRANCH (`--base $TARGET_BRANCH` at
      # gh-pr-create), which defaults to "staging".
      local _target="${TARGET_BRANCH:-staging}"
      if [[ "$_target" == "staging" ]]; then
        auto_merge_applied=true; auto_merge_skipped_reason="null"
      else
        auto_merge_skipped_reason="branch_excluded"
      fi
    else
      auto_merge_skipped_reason="policy_off"
    fi
  fi

  # ── Apply auto-merge if resolved (AC3) ───────────────────────────────────
  if [[ "$auto_merge_applied" == "true" ]] && [[ -n "$pr_url" ]]; then
    local merge_exit=1 merge_attempt=0 merge_max=3 merge_stderr
    while [[ $merge_attempt -lt $merge_max ]]; do
      merge_attempt=$(( merge_attempt + 1 ))
      merge_stderr=$(gh pr merge --auto --squash --delete-branch "$pr_url" 2>&1)
      merge_exit=$?
      if [[ "$merge_exit" -eq 0 ]]; then
        # AC5-e: verify autoMergeRequest actually queued
        local merge_check
        merge_check=$(gh pr view "$pr_url" --json autoMergeRequest --jq .autoMergeRequest 2>/dev/null || echo "null")
        if [[ "$merge_check" == "null" ]]; then
          # Free-tier fallback (opt-in) : branch protection unavailable → use --admin
          # GAAI_AUTO_MERGE_ADMIN_FALLBACK=true bypasses GitHub-side checks but
          # daemon QA phase still validates ACs. Trust-arc opt-in, default off.
          if [[ "${GAAI_AUTO_MERGE_ADMIN_FALLBACK:-false}" == "true" ]]; then
            echo "[INFO] ${story_id} handle_commit_phase: branch protection unavailable, attempting admin fallback merge"
            local admin_stderr admin_exit
            admin_stderr=$(gh pr merge --admin --squash --delete-branch "$pr_url" 2>&1)
            admin_exit=$?
            if [[ "$admin_exit" -eq 0 ]]; then
              echo "[INFO] ${story_id} handle_commit_phase: admin fallback merge succeeded"
              auto_merge_skipped_reason="null"
              # auto_merge_applied stays true
            else
              echo "[WARN] ${story_id} handle_commit_phase: admin fallback merge failed: ${admin_stderr: -200}"
              auto_merge_applied=false; auto_merge_skipped_reason="admin_fallback_failed"
            fi
          else
            echo "[WARN] ${story_id} handle_commit_phase: auto-merge requested but branch protection not configured — PR remains manual [auto_merge_skipped_reason=branch_protection_missing]"
            auto_merge_applied=false; auto_merge_skipped_reason="branch_protection_missing"
          fi
        fi
        break
      fi
      # AC5-g: "already enabled" is idempotent success
      if printf '%s\n' "$merge_stderr" | grep -qi "already enabled\|already queued"; then
        merge_exit=0; break
      fi
      echo "[WARN] ${story_id} handle_commit_phase: gh pr merge --auto attempt ${merge_attempt}/${merge_max} failed: ${merge_stderr: -200}"
      [[ $merge_attempt -lt $merge_max ]] && sleep 3
    done
    if [[ "$merge_exit" -ne 0 ]]; then
      # ── Benign-failure guard (faux AUTO_MERGE_FAILED) ──────────────────────
      # `gh pr merge --auto --squash --delete-branch` deletes the LOCAL branch
      # after the merge/queue step. The story branch (`story/{id}`) is still held
      # by this delivery's worktree, so `git branch -D` fails with
      # "cannot delete branch '...' used by worktree" and gh returns non-zero —
      # even though the PR merged (or auto-merge is queued) server-side. The
      # un-deleted local branch is harmless (worktree GC removes it later). Before
      # escalating, re-read the true PR state: if it is already MERGED, or
      # auto-merge is queued, the merge succeeded — treat as success. This mirrors
      # the happy-path contract above where a queued autoMergeRequest counts as done.
      if [[ -n "$pr_url" ]]; then
        local _bf_state _bf_automerge
        _bf_state=$(gh pr view "$pr_url" --json state --jq .state 2>/dev/null || echo "")
        _bf_automerge=$(gh pr view "$pr_url" --json autoMergeRequest --jq .autoMergeRequest 2>/dev/null || echo "null")
        if [[ "$_bf_state" == "MERGED" || "$_bf_automerge" != "null" ]]; then
          echo "[INFO] ${story_id} handle_commit_phase: gh pr merge returned non-zero only at local branch-delete (branch held by worktree); PR state=${_bf_state:-unknown}, auto-merge queued=$([[ "$_bf_automerge" != "null" ]] && echo yes || echo no) — treating as merged success"
          merge_exit=0
        fi
      fi
    fi
    if [[ "$merge_exit" -ne 0 ]]; then
      # Probe for CONFLICTING/DIRTY — attempt deterministic auto-resolve before escalating
      if [[ -n "$pr_url" ]] && gh pr view "$pr_url" --json mergeable,mergeStateStatus 2>/dev/null \
           | grep -qE '"mergeable":"CONFLICTING"|"mergeStateStatus":"DIRTY"'; then
        if _auto_resolve_pr_conflicts "$pr_url" "$branch" "$worktree_path" "$story_id" "$trace_id"; then
          # Resolved: one more gh pr merge --auto attempt (DEC-76 §11 gates remain active)
          local resolve_merge_out resolve_merge_exit
          resolve_merge_out=$(gh pr merge --auto --squash --delete-branch "$pr_url" 2>&1)
          resolve_merge_exit=$?
          if [[ "$resolve_merge_exit" -eq 0 ]] || \
             printf '%s\n' "$resolve_merge_out" | grep -qi "already enabled\|already queued"; then
            merge_exit=0  # fall through to post-merge path below
          else
            echo "[ERROR] ${story_id} handle_commit_phase: gh pr merge --auto failed after resolve: ${resolve_merge_out: -200} [class=AUTO_MERGE_FAILED]"
            _emit_commit_routing_record "$story_id" "$trace_id" "error" "AUTO_MERGE_FAILED" "0" "$pr_url" "false"
            "$SCHEDULER" --set-phase-status "$story_id" escalated "$BACKLOG_FILE" 2>/dev/null || true
            return 1
          fi
        else
          # auto-resolve aborted or exhausted: escalate (NOT failed)
          "$SCHEDULER" --set-phase-status "$story_id" escalated "$BACKLOG_FILE" 2>/dev/null || true
          return 1
        fi
      fi
      if [[ "$merge_exit" -ne 0 ]]; then
        # Non-conflict failure (network, rate-limit, branch-protection) — original path unchanged
        echo "[ERROR] ${story_id} handle_commit_phase: gh pr merge --auto failed after ${merge_max} attempts [class=AUTO_MERGE_FAILED]"
        _emit_commit_routing_record "$story_id" "$trace_id" "error" "AUTO_MERGE_FAILED" "0" "$pr_url" "false"
        "$SCHEDULER" --set-phase-status "$story_id" escalated "$BACKLOG_FILE" 2>/dev/null || true
        return 1
      fi
    fi
  fi

  # ── Persist pr_status (AC3) ───────────────────────────────────────────────
  local pr_status_val
  [[ "$auto_merge_applied" == "true" ]] && pr_status_val="merged" || pr_status_val="pending_review"
  "$SCHEDULER" --set-field "$story_id" pr_status "$pr_status_val" "$BACKLOG_FILE" 2>/dev/null || true

  # ── Audit gate: advance phase_status qa_passed → done ────────────────────
  if ! "$SCHEDULER" --set-phase-status "$story_id" done "$BACKLOG_FILE" 2>/dev/null; then
    echo "[ERROR] ${story_id} handle_commit_phase: --set-phase-status done failed [class=SCHEDULER_FAILURE]"
    _emit_commit_routing_record "$story_id" "$trace_id" "error" "SCHEDULER_FAILURE" "0" "$pr_url" "$auto_merge_applied"
    return 1
  fi

  # ── Honest top-level status: phase_status:done MUST coincide with status:done.
  # Without this, the story stays status:in_progress in the YAML even though the
  # 3-phase pipeline is terminal — daemon-staleness then misclassifies it as a
  # stuck delivery on the next cycle. Soft-fail (|| true) because the
  # phase_status flip already constitutes the audit gate; if status flip fails,
  # the post-delivery hook can still reconcile.
  if ! "$SCHEDULER" --set-status "$story_id" done "$BACKLOG_FILE" 2>/dev/null; then
    echo "[WARN] ${story_id} handle_commit_phase: --set-status done failed (phase_status already done; reconcile via post-delivery hook)"
  fi

  # ── Post-delivery autonomous triage (AC2, AC3, AC4, AC5) ─────────────────
  # Primary hook: fires unconditionally on both auto-merge and pending-review paths.
  # Secondary hooks in pr-watcher + recovery are idempotent via per-story marker.
  TRIAGE_RESULT="no triage — reason: no_delta"
  _run_triage_for_story "$story_id" || true
  echo "[TRIAGE] ${story_id} result: ${TRIAGE_RESULT}"

  # ── Worktree cleanup post-merge: only when PR actually merged. ────────────
  # Pending-review PRs keep the worktree alive so manual review/edits can land.
  if [[ "$auto_merge_applied" == "true" && -d "$worktree_path" ]]; then
    if git -C "$PROJECT_DIR" worktree remove --force "$worktree_path" 2>/dev/null; then
      echo "[INFO] ${story_id} handle_commit_phase: worktree removed post-merge ($worktree_path)"
    else
      echo "[WARN] ${story_id} handle_commit_phase: worktree remove failed (will be pruned next cycle)"
    fi
    git -C "$PROJECT_DIR" worktree prune 2>/dev/null || true
  fi

  # ── Duration end ─────────────────────────────────────────────────────────
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_end_ms=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
  else
    t_end_ms=$(( $(date +%s) * 1000 ))
  fi
  duration_ms=$(( t_end_ms - t_start_ms ))

  # ── Emit success routing record ────────────────────────────────────────────
  _emit_commit_routing_record "$story_id" "$trace_id" "daemon-bash" "null" "$duration_ms" "$pr_url" "$auto_merge_applied"

  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=commit DONE (${duration_ms}ms) pr=${pr_url:-none} auto_merge=${auto_merge_applied}"
  return 0
}

# ── Main dispatcher (AC1 + AC6) ───────────────────────────────────────────
#
# Called by delivery-daemon.sh main loop for stories with delivery_pipeline=3phase.
# Reads phase_status, routes to the appropriate handler for ONE phase, then returns.
# The caller loops until phase_status is done/failed/escalated.
#
# Arguments: story_id [trace_id]
# Returns: 0 on success, 1 on dispatch error (logs [ERROR] per AC6)
dispatch_3phase_story() {
  local story_id="$1"
  local trace_id="${2:-$(python3 -c 'import uuid; print(str(uuid.uuid4()))' 2>/dev/null || echo "stub-$(date +%s)-$$")}"

  # Read phase_status (AC1 — awk extractor)
  local ps
  ps=$(get_phase_status "$story_id")

  if [[ -z "$ps" ]]; then
    # AC6(i): log ERROR
    echo "[ERROR] ${story_id} dispatch_3phase_story: phase_status field missing or empty"
    # AC6(iv): emit error routing record
    _emit_routing_record "$story_id" "$trace_id" "plan" "error" "phase_status_missing"
    # AC6(ii): return non-zero (caller loop will break)
    return 1
  fi

  case "$ps" in
    not_started)
      _write_active_marker "$story_id" "plan"
      handle_plan_phase "$story_id" "$trace_id"
      local _plan_rc=$?
      _remove_active_marker "$story_id" "plan"
      [[ $_plan_rc -ne 0 ]] && return 1
      ;;
    planned)
      _write_active_marker "$story_id" "impl"
      handle_impl_phase "$story_id" "$trace_id"
      local _impl_rc=$?
      _remove_active_marker "$story_id" "impl"
      [[ $_impl_rc -ne 0 ]] && return 1
      ;;
    implemented)
      _write_active_marker "$story_id" "qa"
      handle_qa_phase "$story_id" "$trace_id"
      local _qa_rc=$?
      _remove_active_marker "$story_id" "qa"
      [[ $_qa_rc -ne 0 ]] && return 1
      ;;
    qa_passed)
      _write_active_marker "$story_id" "commit"
      handle_commit_phase "$story_id" "$trace_id"
      local _commit_rc=$?
      _remove_active_marker "$story_id" "commit"
      [[ $_commit_rc -ne 0 ]] && return 1
      ;;
    qa_failed)
      # ── Retry-loop : QA FAIL → re-IMPL with qa-report context ────────────
      # When QA verdict is FAIL, the canonical flow is to re-spawn IMPL with
      # the qa-report findings as additional context, up to GAAI_QA_RETRY_MAX
      # total IMPL+QA cycles. If the retry cap is exhausted, escalate to
      # qa_escalated for human triage. Without this block, the wrapper exits
      # at qa_failed and the story ghosts in_progress until daemon restart
      # (the main poll loop ignores in_progress ; recovery at restart just
      # re-spawns the wrapper which would re-hit the same terminal state).
      #
      # The QA retry counter is stored per-story at
      # ${LOCK_DIR}/.qa-retries-${story_id} as a single integer line. It is
      # intentionally distinct from the daemon main-loop's wrapper-launch
      # retry counter — this counter tracks IMPL+QA cycles within a single
      # story's lifetime, persists across wrapper relaunches, and is cleaned
      # up on terminal transitions (qa_escalated branch here ; done/failed
      # branches in _reconcile_yaml_status_on_exit).
      #
      # The qa-report path is exported as GAAI_QA_REPORT_PATH so the impl
      # prompt construction helper injects the prior QA findings into the
      # next IMPL claude-p invocation as fix-this-please context.
      local _qa_retry_file _qa_retry_count _qa_retry_max
      _qa_retry_file="${LOCK_DIR}/.qa-retries-${story_id}"
      _qa_retry_count=0
      if [[ -f "$_qa_retry_file" ]]; then
        _qa_retry_count=$(cat "$_qa_retry_file" 2>/dev/null || echo 0)
        [[ "$_qa_retry_count" =~ ^[0-9]+$ ]] || _qa_retry_count=0
      fi
      _qa_retry_max="${GAAI_QA_RETRY_MAX:-3}"
      if (( _qa_retry_count >= _qa_retry_max )); then
        echo "[$(date '+%H:%M:%S')] ${story_id} dispatch: QA retry cap reached (${_qa_retry_count}/${_qa_retry_max}) — escalating qa_failed -> qa_escalated"
        if "$SCHEDULER" --set-phase-status "$story_id" qa_escalated "$BACKLOG_FILE" 2>/dev/null; then
          _emit_routing_record "$story_id" "$trace_id" "qa" "error" "QA_RETRY_EXHAUSTED" 2>/dev/null || true
        else
          echo "[ERROR] ${story_id} dispatch: scheduler --set-phase-status qa_escalated failed"
        fi
        # Wire the escalation to the existing notification machinery (terminal bell +
        # macOS osascript + webhook+HMAC). Helper is best-effort, never blocks.
        if declare -F notify_escalation_inline >/dev/null 2>&1; then
          notify_escalation_inline "$story_id" \
            "QA retry cap reached (${_qa_retry_count}/${_qa_retry_max})" \
            "Review .gaai/project/contexts/artefacts/qa-reports/${story_id}.qa-report.md and either fix manually or re-refine the story"
        fi
        rm -f "$_qa_retry_file" 2>/dev/null || true
        # Cross-cycle outcome metric — emit when escalated after cross-cycle route
        if [[ -n "${GAAI_QA_INJECT_PHASE_SNAPSHOT:-}" ]]; then
          local _cc_cycle_n=${_qa_retry_count:-0}
          local _cc_outcome_json="{\"sid\":\"${story_id}\",\"cycle_n\":${_cc_cycle_n},\"routed_phase\":\"${GAAI_QA_INJECT_PHASE_SNAPSHOT}\",\"outcome\":\"qa_escalated\",\"marker_honor_rate\":$(_compute_marker_honor_rate "$story_id" "${GAAI_WORKTREE_PATH:-${worktree_path}}" "${GAAI_QA_INJECT_PHASE_SNAPSHOT}")}"
          printf '%s\n' "$_cc_outcome_json" >> "${LOG_DIR}/cross-cycle-outcomes.jsonl" 2>/dev/null || true
        fi
        return 0
      fi
      # Increment counter via atomic temp-rename (no sed dependency, no shared helper).
      _qa_retry_count=$((_qa_retry_count + 1))
      local _qa_retry_tmp="${_qa_retry_file}.tmp.$$"
      printf '%s\n' "$_qa_retry_count" > "$_qa_retry_tmp" 2>/dev/null \
        && mv "$_qa_retry_tmp" "$_qa_retry_file" 2>/dev/null \
        || rm -f "$_qa_retry_tmp" 2>/dev/null
      # Resolve worktree path (mirrors handle_impl_phase formula).
      local _wt_path _wt_parent _wt_repo
      if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
        _wt_path="${GAAI_WORKTREES_BASE}/${story_id}-workspace"
      else
        _wt_repo=$(basename "${REPO_ROOT:-$PROJECT_DIR}")
        if _wt_parent=$(cd "${REPO_ROOT:-$PROJECT_DIR}/.." 2>/dev/null && pwd); then
          _wt_path="${_wt_parent}/.gaai-worktrees/${_wt_repo}/${story_id}-workspace"
        else
          echo "[ERROR] ${story_id} dispatch: cannot resolve worktree parent dir for qa-report path — retry aborted"
          return 1
        fi
      fi
      export GAAI_QA_REPORT_PATH="${_wt_path}/.gaai/project/contexts/artefacts/qa-reports/${story_id}.qa-report.md"
      # Emit retry routing record BEFORE rewinding phase_status so the qa_failed
      # state itself is preserved in the routing trace for forensic post-mortem.
      _emit_routing_record "$story_id" "$trace_id" "qa" "retry" "QA_RETRY_${_qa_retry_count}" 2>/dev/null || true
      # Rewind phase_status to planned so the next outer-loop iteration calls
      # handle_impl_phase. The IMPL prompt will pick up the qa-report via
      # GAAI_QA_REPORT_PATH (read by daemon-prompt-construct.sh).
      if ! "$SCHEDULER" --set-phase-status "$story_id" planned "$BACKLOG_FILE" 2>/dev/null; then
        echo "[ERROR] ${story_id} dispatch: scheduler --set-phase-status planned failed during retry"
        unset GAAI_QA_REPORT_PATH
        return 1
      fi
      echo "[$(date '+%H:%M:%S')] ${story_id} dispatch: QA FAIL — retry ${_qa_retry_count}/${_qa_retry_max} (IMPL will re-spawn with qa-report context: ${GAAI_QA_REPORT_PATH})"
      return 0
      ;;
    commit_failed)
      _write_active_marker "$story_id" "commit"
      handle_commit_phase "$story_id" "$trace_id"
      local _commit_rc=$?
      _remove_active_marker "$story_id" "commit"
      [[ $_commit_rc -ne 0 ]] && return 1
      ;;
    done|failed|escalated|qa_escalated)
      return 0
      ;;
    *)
      echo "[ERROR] ${story_id} dispatch_3phase_story: invalid phase_status='${ps}' — known values: not_started planned implemented qa_passed qa_failed qa_escalated commit_failed done failed escalated worktree_recovery_failed[intermediate]"
      _emit_routing_record "$story_id" "$trace_id" "plan" "error" "invalid_phase_status:${ps}"
      return 1
      ;;
  esac

  return 0
}

# Compute marker_honor_rate from KEEP-marked steps vs actual touched paths.
# Returns: JSON number (0.0-1.0), or null for IMPL route / no KEEP steps / not computable.
# Usage: _compute_marker_honor_rate <story_id> <worktree_path> <routed_phase>
_compute_marker_honor_rate() {
  local sid="$1" wt="$2" routed_phase="$3"

  # IMPL route — not applicable
  [[ "$routed_phase" != "plan" ]] && { printf 'null'; return 0; }

  local plan_path="${wt}/.gaai/project/contexts/artefacts/plans/${sid}.execution-plan.md"
  [[ ! -s "$plan_path" ]] && { printf 'null'; return 0; }

  # Extract file paths associated with KEEP steps (lines following ✓ KEEP markers)
  local keep_paths
  keep_paths=$(grep -A3 '✓ KEEP' "$plan_path" 2>/dev/null \
    | grep -oE '[A-Za-z0-9_/.-]+\.(sh|ts|js|md|yaml|yml|json|astro)' 2>/dev/null \
    | sort -u || true)
  [[ -z "$keep_paths" ]] && { printf 'null'; return 0; }

  # Get touched paths in worktree (HEAD vs base branch)
  local base_ref
  base_ref=$(git -C "$wt" rev-parse --verify origin/staging 2>/dev/null || echo "")
  if [[ -z "$base_ref" ]]; then
    base_ref=$(git -C "$wt" merge-base HEAD "$(git -C "$wt" rev-parse --verify main 2>/dev/null || echo HEAD)" 2>/dev/null || echo "")
  fi
  [[ -z "$base_ref" ]] && { printf 'null'; return 0; }

  local touched_paths
  touched_paths=$(git -C "$wt" diff --name-only "${base_ref}...HEAD" 2>/dev/null | sort -u || true)
  [[ -z "$touched_paths" ]] && { printf 'null'; return 0; }

  # Count KEEP paths that were NOT touched (honored = not modified)
  local total_keep=0 honored=0
  for kp in $keep_paths; do
    total_keep=$((total_keep + 1))
    if ! printf '%s\n' "$touched_paths" | grep -qx "$kp" 2>/dev/null; then
      honored=$((honored + 1))
    fi
  done

  (( total_keep == 0 )) && { printf 'null'; return 0; }

  # honor_rate = fraction of KEEP paths that were honored (not touched)
  # Using integer arithmetic: (honored * 100) / total_keep → divide by 100
  local rate_x100=$(( (honored * 100) / total_keep ))
  if (( rate_x100 == 100 )); then
    printf '1.0'
  elif (( rate_x100 == 0 )); then
    printf '0.0'
  else
    printf '0.%02d' "$(( rate_x100 % 100 ))"
  fi
}

# @see DEC-88 §3 (phase_status semantics — 3-phase pipeline owns phase_status transitions)
# @see E134S12 (chore-commit purity dependency — drift detection guard re-used, not re-implemented)
_reconcile_yaml_status_on_exit() {
  local story_id="$1"

  # Null-guards: all required exports must be set by the wrapper
  [[ -z "${BACKLOG_FILE:-}" || -z "${PROJECT_DIR:-}" || -z "${SCHEDULER:-}" || -z "${LOCK_DIR:-}" ]] && return 0

  # AC1: Create reconcile-in-progress marker before any YAML read or chore-commit.
  # Daemon's check_stale_in_progress honors this marker to skip staleness verdict during reconcile.
  # AC3: Fail-safe — if touch fails (disk full, read-only LOCK_DIR), log warning and
  # proceed without race protection. Degradation = same behavior as pre-feature. No crash.
  local _rip_marker="${LOCK_DIR}/${story_id}.reconcile-in-progress"
  if ! touch "$_rip_marker" 2>/dev/null; then
    echo "[WRAPPER-RECONCILE] $story_id : warning — could not create reconcile-in-progress marker (touch failed) — proceeding without race protection"
  fi

  local phase_status target_status current_status

  phase_status=$(get_phase_status "$story_id" 2>/dev/null)

  # ── Plan-block detection (defense in depth) ─────────────────────────────
  # Plan agent writes {id}.plan-blocked.md to the worktree and exits
  # non-zero when scope-discipline thresholds are exceeded. The wrapper's
  # main dispatch loop returns early before the `--set-phase-status planned`
  # call, so phase_status remains "not_started". Without this pre-check, the
  # case statement below would no-op and the story ghosts as in_progress.
  #
  # Maps to target_status="failed" — already in the case table, OSS-clean,
  # no new state semantics introduced. Operator inspects {id}.plan-blocked.md
  # (preserved in artefacts) to drive decomposition before re-refining.
  #
  # Stale-marker guard: only fire when phase_status is unset / not_started
  # AND no canonical execution-plan.md exists. A successful PLAN would have
  # produced execution-plan.md and advanced phase_status to "planned"; if
  # either is present, plan-blocked.md is from a prior attempt and stale.
  local _worktree_path _plan_blocked_path _exec_plan_path _repo_name _parent_dir
  if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
    _worktree_path="${GAAI_WORKTREES_BASE}/${story_id}-workspace"
  else
    _repo_name=$(basename "${REPO_ROOT:-$PROJECT_DIR}")
    if _parent_dir=$(cd "${REPO_ROOT:-$PROJECT_DIR}/.." 2>/dev/null && pwd); then
      _worktree_path="${_parent_dir}/.gaai-worktrees/${_repo_name}/${story_id}-workspace"
    else
      _worktree_path=""
    fi
  fi
  _plan_blocked_path="${_worktree_path}/.gaai/project/contexts/artefacts/plans/${story_id}.plan-blocked.md"
  _exec_plan_path="${_worktree_path}/.gaai/project/contexts/artefacts/plans/${story_id}.execution-plan.md"

  if [[ -n "$_worktree_path" && -f "$_plan_blocked_path" \
        && ( -z "$phase_status" || "$phase_status" == "not_started" ) \
        && ! -f "$_exec_plan_path" ]]; then
    target_status="failed"
    phase_status="plan-blocked"  # for the final log line only
    echo "[WRAPPER-RECONCILE] $story_id : plan-blocked.md detected — reconciling status=failed (operator must decompose per plan-blocked.md inventory before re-refining)"
  else
    # Map phase_status → target top-level status
    case "$phase_status" in
      done)         target_status="done" ;;
      failed)       target_status="failed" ;;
      escalated)    target_status="escalated" ;;
      qa_escalated) target_status="escalated" ;;
      qa_failed)
        # No-op: retry-loop owns this transition
        rm -f "$_rip_marker" 2>/dev/null || true
        return 0
        ;;
      commit_failed)
        # No-op: commit-phase retry path — story stays in_progress
        return 0
        ;;
      *)
        # Unknown or empty phase_status — no-op
        rm -f "$_rip_marker" 2>/dev/null || true
        return 0
        ;;
    esac
  fi

  # Derive paths from exported env (no new exports needed)
  local backlog_rel staging_lock drift_marker
  backlog_rel="${BACKLOG_FILE#${PROJECT_DIR}/}"
  staging_lock="${LOCK_DIR}/.staging.lock"
  drift_marker="${LOCK_DIR}/.drift-detected.audit"

  # Idempotent guard: read current top-level status
  current_status=$(awk -v id="$story_id" '
    $0 == "- id: " id { found=1; next }
    found && /^- id:/ { exit }
    found && /^[[:space:]]+status:/ {
      gsub(/^[[:space:]]+status:[[:space:]]*/, "")
      gsub(/[[:space:]]+#.*$/, "")
      gsub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      print; exit
    }
  ' "$BACKLOG_FILE" 2>/dev/null)

  if [[ "$current_status" == "$target_status" ]]; then
    echo "[WRAPPER-RECONCILE] $story_id : status already $target_status — no-op"
    rm -f "$_rip_marker" 2>/dev/null || true
    return 0
  fi

  cd "$PROJECT_DIR" || return 0

  # Sync with remote (mirrors _recovery_set_status pattern)
  if ! git pull origin "${TARGET_BRANCH:-staging}" --ff-only --quiet 2>/dev/null; then
    git fetch origin "${TARGET_BRANCH:-staging}" --quiet 2>/dev/null || true
    git reset --hard "origin/${TARGET_BRANCH:-staging}" --quiet 2>/dev/null || true
  fi

  # AC1/AC3: commit accumulated drift (same model as chore-commit pre-mark sweep).
  # Write drift-marker only on genuine commit/rebase failure (rc=6), not on every diff.
  if ! git diff --quiet HEAD -- "$backlog_rel" 2>/dev/null; then
    local _drift_rc=0
    _commit_accumulated_backlog_drift "$story_id" "$backlog_rel" "${TARGET_BRANCH:-staging}" "wrapper-reconcile" \
      || _drift_rc=$?
    if [[ "$_drift_rc" -ne 0 ]]; then
      echo "[WRAPPER-RECONCILE] $story_id : drift commit failed (rc=$_drift_rc) — writing drift-marker, daemon will retry"
      printf '%s|commit|wrapper-reconcile-drift-%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$story_id" \
        > "$drift_marker" 2>/dev/null || true
      rm -f "$_rip_marker" 2>/dev/null || true
      return 0
    fi
    echo "[WRAPPER-RECONCILE] $story_id : committed accumulated backlog drift — continuing reconcile"
  fi

  # Update YAML status field
  if ! "$SCHEDULER" --set-status "$story_id" "$target_status" "$BACKLOG_FILE" 2>/dev/null; then
    echo "[WRAPPER-RECONCILE] $story_id : scheduler --set-status failed — daemon will reconcile"
    rm -f "$_rip_marker" 2>/dev/null || true
    return 0
  fi

  git add "$backlog_rel"

  # Idempotent: skip if nothing staged
  if git diff --cached --quiet 2>/dev/null; then
    rm -f "$_rip_marker" 2>/dev/null || true
    return 0
  fi

  # Commit (with flock on Linux; direct on macOS where flock is unavailable)
  local commit_rc=0
  if command -v flock &>/dev/null; then
    flock "$staging_lock" git commit -m "chore($story_id): $target_status [wrapper-reconcile]" --quiet 2>/dev/null \
      || commit_rc=$?
  else
    git commit -m "chore($story_id): $target_status [wrapper-reconcile]" --quiet 2>/dev/null \
      || commit_rc=$?
  fi

  if [[ $commit_rc -ne 0 ]]; then
    echo "[WRAPPER-RECONCILE] $story_id : commit failed (rc=$commit_rc) — daemon will reconcile"
    rm -f "$_rip_marker" 2>/dev/null || true
    return 0
  fi

  git push origin "HEAD:${TARGET_BRANCH:-staging}" --quiet 2>/dev/null || true
  echo "[WRAPPER-RECONCILE] $story_id : reconciled status=$target_status from phase_status=$phase_status"

  # Cleanup QA retry counter on terminal transitions — escalated already
  # cleaned in dispatch's cap-reached branch ; this handles done / failed
  # so stale counter files don't accumulate when a story finishes through
  # the happy path or a non-QA failure mode.
  case "$target_status" in
    done|failed|escalated)
      # Read counter before cleanup so cycle_n captures actual retry count
      local _cc_cycle_n=0
      if [[ -f "${LOCK_DIR}/.qa-retries-${story_id}" ]]; then
        _cc_cycle_n=$(cat "${LOCK_DIR}/.qa-retries-${story_id}" 2>/dev/null || echo 0)
      fi
      rm -f "${LOCK_DIR}/.qa-retries-${story_id}" 2>/dev/null || true
      # Cross-cycle outcome metric — emit on terminal transition after cross-cycle route
      if [[ -n "${GAAI_QA_INJECT_PHASE_SNAPSHOT:-}" ]]; then
        local _cc_outcome_json="{\"sid\":\"${story_id}\",\"cycle_n\":${_cc_cycle_n},\"routed_phase\":\"${GAAI_QA_INJECT_PHASE_SNAPSHOT}\",\"outcome\":\"${target_status}\",\"marker_honor_rate\":$(_compute_marker_honor_rate "$story_id" "${GAAI_WORKTREE_PATH:-${worktree_path}}" "${GAAI_QA_INJECT_PHASE_SNAPSHOT}")}"
        printf '%s\n' "$_cc_outcome_json" >> "${LOG_DIR}/cross-cycle-outcomes.jsonl" 2>/dev/null || true
      fi
      ;;
  esac

  rm -f "$_rip_marker" 2>/dev/null || true
}
