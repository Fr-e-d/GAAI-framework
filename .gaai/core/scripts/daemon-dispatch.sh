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

# ── Field extractors (AC1 — verbatim per story AC1 specification) ─────────

get_phase_status() {
  local id="$1"
  awk -v id="$id" '
    $0 == "- id: " id { found=1; next }
    found && /^- id:/ { exit }
    found && /^[[:space:]]+phase_status:/ {
      gsub(/^[[:space:]]+phase_status:[[:space:]]*/, "")
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
      gsub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$BACKLOG_FILE" 2>/dev/null || true)
  echo "${val:-absent}"
}

# Helper: read story title from backlog YAML (returns "" if absent)
get_story_title() {
  local id="$1"
  awk -v id="$id" '
    $0 == "- id: " id { found=1; next }
    found && /^- id:/ { exit }
    found && /^[[:space:]]+title:/ {
      gsub(/^[[:space:]]+title:[[:space:]]*/, "")
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
    2>/dev/null || true
}

# ── Plan-phase routing record (adds --pipeline, real model, real duration) ──
# Arguments: story_id trace_id provider fallback_reason duration_ms
_emit_plan_routing_record() {
  local story_id="$1" trace_id="$2" provider="$3" fallback_reason="$4" duration_ms="$5"
  local impl_tag model_val
  impl_tag=$(get_impl_model_tag "$story_id")
  model_val="${CLAUDE_MODEL_PRIMARY:-claude-sonnet-4-6}"

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
    2>/dev/null || true
}

# ── QA-phase routing record (adds --pipeline, real model, real duration, verdict) ──
# Arguments: story_id trace_id provider fallback_reason duration_ms
_emit_qa_routing_record() {
  local story_id="$1" trace_id="$2" provider="$3" fallback_reason="$4" duration_ms="$5"
  local impl_tag model_val
  impl_tag=$(get_impl_model_tag "$story_id")
  model_val="${CLAUDE_MODEL_PRIMARY:-claude-sonnet-4-6}"

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
    2>/dev/null || true
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
    2>/dev/null || true
}

# ── Cutover default pipeline reader (AC4) ────────────────────────────────
# Reads cutover_state.default_pipeline from the top-level section in BACKLOG_FILE.
# Returns "legacy" if the section is absent (safe default — no-op for existing deploys).
# Re-reads the file on every call (no caching — flip takes effect on next poll without daemon restart).
get_cutover_default_pipeline() {
  local val
  val=$(awk '
    /^cutover_state:[[:space:]]*$/ { in_section=1; next }
    in_section && /^[^[:space:]]/ { exit }
    in_section && /^[[:space:]]+default_pipeline:/ {
      gsub(/^[[:space:]]+default_pipeline:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$BACKLOG_FILE" 2>/dev/null || true)
  echo "${val:-legacy}"
}

# ── Cutover routing record (AC3) ─────────────────────────────────────────
# Emits one JSONL record with phase: cutover + cutover-specific telemetry.
# Arguments: trace_id cutover_from cutover_to forced operator_id pre_flip_count
# Best-effort: audit emit failure warns but does NOT abort the flip.
# Cohort exclusion contract: WHERE phase != 'cutover' in pipeline cohort statistics.
_emit_cutover_routing_record() {
  local trace_id="$1" cutover_from="$2" cutover_to="$3" forced="$4"
  local operator_id="$5" pre_flip_count="$6"

  local log_path_args=()
  if [[ -n "${ROUTING_LOG_PATH:-}" ]]; then
    log_path_args=(--log-path "$ROUTING_LOG_PATH")
  fi

  node "$PROJECT_DIR/.gaai/core/adapters/claude-code/runtime-routing-logger.js" \
    --trace-id                    "$trace_id" \
    --story-id                    "cutover" \
    --phase                       "cutover" \
    --provider                    "daemon-bash" \
    --model                       "n/a" \
    --duration-ms                 0 \
    --fallback-reason             "null" \
    --impl-model-tag              "n/a" \
    --pipeline                    "cutover" \
    --cutover-from                "$cutover_from" \
    --cutover-to                  "$cutover_to" \
    --forced                      "$forced" \
    --operator-id                 "$operator_id" \
    --pre-flip-in-progress-count  "$pre_flip_count" \
    ${log_path_args[@]+"${log_path_args[@]}"} \
    2>/dev/null || true
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
    repo_name=$(basename "$PROJECT_DIR")
    worktree_path="$(cd "${PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${story_id}-workspace"
  fi

  # ── Ensure worktree + story branch exist (idempotent) ─────────────────────
  # Plan is the first phase — worktree must be created here before plan agent
  # writes its execution-plan.md inside it. Subsequent phases (impl/qa/commit)
  # reuse the same worktree.
  if ! git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | grep -qE "^worktree ${worktree_path}$"; then
    # Create story branch from staging if it doesn't exist yet (no checkout — main stays on staging per orchestration.rules.md INVARIANT)
    if ! git -C "$PROJECT_DIR" rev-parse --verify "story/${story_id}" >/dev/null 2>&1; then
      if ! git -C "$PROJECT_DIR" branch "story/${story_id}" staging 2>/dev/null; then
        echo "[ERROR] ${story_id} handle_plan_phase: git branch story/${story_id} staging failed"
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

  # ── Resolve artefact paths ────────────────────────────────────────────────
  local story_path plan_path epic_path log_path
  story_path="${worktree_path}/.gaai/project/contexts/artefacts/stories/${story_id}.story.md"
  plan_path="${worktree_path}/.gaai/project/contexts/artefacts/plans/${story_id}.execution-plan.md"
  log_path="${worktree_path}/.delivery-logs/${story_id}.plan.log"

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

  prompt_file=$(mktemp "/tmp/gaai-plan-prompt-${story_id}-XXXXXX.md")
  cat "$agent_prompt_src" > "$prompt_file"

  # ── Spawn claude -p (AC1) ─────────────────────────────────────────────────
  # Duration measurement (AC4) — bash 5+ EPOCHREALTIME (microseconds); fallback date +%s
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_start_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
  else
    t_start_ms=$(( $(date +%s) * 1000 ))
  fi

  local claude_exit
  set -o pipefail
  GAAI_STORY_ID="$story_id" \
  GAAI_WORKTREE_PATH="$worktree_path" \
  GAAI_STORY_PATH="$story_path" \
  GAAI_PLAN_PATH="$plan_path" \
  GAAI_EPIC_PATH="$epic_path" \
  GAAI_DELIVERY_LOG_FILE="$log_path" \
  GAAI_WORKSPACE_ID="${GAAI_WORKSPACE_ID:-}" \
  GAAI_ORG_ID="${GAAI_ORG_ID:-}" \
    claude -p \
      --model sonnet \
      --max-turns 60 \
      --output-format stream-json \
      --verbose \
      < "$prompt_file" 2>&1 | tee -a "$log_path"
  claude_exit=${PIPESTATUS[0]}
  set +o pipefail

  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_end_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
  else
    t_end_ms=$(( $(date +%s) * 1000 ))
  fi
  duration_ms=$(( t_end_ms - t_start_ms ))

  rm -f "$prompt_file"

  # ── Validate output (AC4 guard) ───────────────────────────────────────────
  if [[ "$claude_exit" -ne 0 ]]; then
    echo "[ERROR] ${story_id} handle_plan_phase: claude -p exited $claude_exit"
    _emit_plan_routing_record "$story_id" "$trace_id" "error" "PLAN_PHASE_FAILED" "$duration_ms"
    return 1
  fi

  if [[ ! -s "$plan_path" ]]; then
    echo "[ERROR] ${story_id} handle_plan_phase: plan file missing or empty at $plan_path"
    _emit_plan_routing_record "$story_id" "$trace_id" "error" "NO_ARTEFACT" "$duration_ms"
    return 1
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
    repo_name=$(basename "$PROJECT_DIR")
    worktree_path="$(cd "${PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${story_id}-workspace"
  fi

  # ── Resolve artefact paths ────────────────────────────────────────────────
  local story_path plan_path impl_report_path log_path
  story_path="${worktree_path}/.gaai/project/contexts/artefacts/stories/${story_id}.story.md"
  plan_path="${worktree_path}/.gaai/project/contexts/artefacts/plans/${story_id}.execution-plan.md"
  impl_report_path="${worktree_path}/.gaai/project/contexts/artefacts/impl-reports/${story_id}.impl-report.md"
  log_path="${worktree_path}/.delivery-logs/${story_id}.impl.log"

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

  local prompt_content
  if ! prompt_content=$(
    GAAI_STORY_ID="$story_id" \
    GAAI_STORY_PATH="$story_path" \
    GAAI_PLAN_PATH="$plan_path" \
    GAAI_EPIC_PATH="${epic_path:-}" \
    GAAI_WORKSPACE_PATH="$worktree_path" \
    SECONDARY_ROUTE="${SECONDARY_ROUTE:-false}" \
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
  prompt_file=$(mktemp "/tmp/gaai-impl-prompt-${story_id}-XXXXXX.md")
  printf '%s' "$prompt_content" > "$prompt_file"

  # ── Get impl_model_tag from backlog ───────────────────────────────────────
  local impl_tag
  impl_tag=$(get_impl_model_tag "$story_id")

  # ── Invoke nested-claude-spawn.js flag-CLI (AC1 — always exits 0) ────────
  local spawn_script
  spawn_script="${PROJECT_DIR}/.gaai/core/adapters/claude-code/nested-claude-spawn.js"

  local spawn_output
  spawn_output=$(
    GAAI_STORY_ID="$story_id" \
    GAAI_WORKTREE_PATH="$worktree_path" \
    GAAI_EPIC_PATH="${epic_path:-}" \
    GAAI_WORKSPACE_ID="${GAAI_WORKSPACE_ID:-}" \
    GAAI_ORG_ID="${GAAI_ORG_ID:-}" \
      node "$spawn_script" \
        --story-id       "$story_id" \
        --report-path    "$impl_report_path" \
        --prompt-file    "$prompt_file" \
        --impl-model-tag "$impl_tag" \
        --log-file       "$log_path" \
        2>>"$log_path" || true
  )

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
    repo_name=$(basename "$PROJECT_DIR")
    worktree_path="$(cd "${PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${story_id}-workspace"
  fi

  # ── Resolve artefact paths (AC2) ──────────────────────────────────────────
  local story_path plan_path impl_report_path qa_report_path memory_delta_path log_path
  story_path="${worktree_path}/.gaai/project/contexts/artefacts/stories/${story_id}.story.md"
  plan_path="${worktree_path}/.gaai/project/contexts/artefacts/plans/${story_id}.execution-plan.md"
  impl_report_path="${worktree_path}/.gaai/project/contexts/artefacts/impl-reports/${story_id}.impl-report.md"
  qa_report_path="${worktree_path}/.gaai/project/contexts/artefacts/qa-reports/${story_id}.qa-report.md"
  memory_delta_path="${worktree_path}/.gaai/project/contexts/artefacts/memory-deltas/${story_id}.memory-delta.md"
  log_path="${worktree_path}/.delivery-logs/${story_id}.qa.log"

  # Resolve epic_id from story frontmatter
  local epic_id epic_path
  epic_id=$(grep -m1 '^epic:' "$story_path" 2>/dev/null | sed 's/^epic:[[:space:]]*//' | tr -d '"' || true)
  if [[ -n "$epic_id" ]]; then
    epic_path="${worktree_path}/.gaai/project/contexts/artefacts/epics/${epic_id}.epic.md"
  else
    epic_path=""
  fi

  # Resolve base ref for git diff (AC2: GAAI_BASE_REF)
  local base_ref
  base_ref="${GAAI_BASE_REF:-main}"

  # ── Validate required input files ────────────────────────────────────────
  if [[ ! -f "$story_path" ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: story file not found: $story_path"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SPAWN_FAILED" "0"
    return 1
  fi
  if [[ ! -f "$plan_path" ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: plan file not found: $plan_path"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SPAWN_FAILED" "0"
    return 1
  fi
  if [[ ! -f "$impl_report_path" ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: impl-report not found: $impl_report_path"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SPAWN_FAILED" "0"
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
    return 1
  fi

  local prompt_file
  prompt_file=$(mktemp "/tmp/gaai-qa-prompt-${story_id}-XXXXXX.md")
  cat "$agent_prompt_src" > "$prompt_file"

  # ── Duration measurement ──────────────────────────────────────────────────
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_start_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
  else
    t_start_ms=$(( $(date +%s) * 1000 ))
  fi

  # ── Spawn claude -p (AC1 — child bash subshell, NOT nested-claude-spawn.js) ──
  local claude_exit
  set -o pipefail
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
    claude -p \
      --model sonnet \
      --max-turns 30 \
      --output-format stream-json \
      --verbose \
      < "$prompt_file" 2>&1 | tee -a "$log_path"
  claude_exit=${PIPESTATUS[0]}
  set +o pipefail

  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_end_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
  else
    t_end_ms=$(( $(date +%s) * 1000 ))
  fi
  duration_ms=$(( t_end_ms - t_start_ms ))

  rm -f "$prompt_file"

  # ── AC5(a): spawn-error — claude -p exit non-zero ─────────────────────────
  if [[ "$claude_exit" -ne 0 ]]; then
    echo "[ERROR] ${story_id} handle_qa_phase: claude -p exited ${claude_exit} [class=QA_SPAWN_FAILED]"
    _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SPAWN_FAILED" "$duration_ms"
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
      return 1
      ;;
    ESCALATE)
      echo "[ERROR] ${story_id} handle_qa_phase: QA verdict=ESCALATE [class=QA_VERDICT:ESCALATE]"
      if ! "$SCHEDULER" --set-phase-status "$story_id" qa_escalated "$BACKLOG_FILE" 2>/dev/null; then
        echo "[ERROR] ${story_id} handle_qa_phase: --set-phase-status qa_escalated failed [class=QA_SCHEDULER_FAILURE]"
        _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_SCHEDULER_FAILURE" "$duration_ms"
        return 1
      fi
      _emit_qa_routing_record "$story_id" "$trace_id" "error" "QA_VERDICT:ESCALATE" "$duration_ms"
      return 1
      ;;
  esac
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
    t_start_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
  else
    t_start_ms=$(( $(date +%s) * 1000 ))
  fi

  # ── Resolve worktree path (same pattern as handle_impl_phase/handle_qa_phase) ──
  local worktree_path
  if [[ -n "${GAAI_WORKTREES_BASE:-}" ]]; then
    worktree_path="${GAAI_WORKTREES_BASE}/${story_id}-workspace"
  else
    local repo_name
    repo_name=$(basename "$PROJECT_DIR")
    worktree_path="$(cd "${PROJECT_DIR}/.." && pwd)/.gaai-worktrees/${repo_name}/${story_id}-workspace"
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

  # ── Resolve branch name in worktree ──────────────────────────────────────
  local branch
  branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ -z "$branch" ]] || [[ "$branch" == "HEAD" ]]; then
    echo "[ERROR] ${story_id} handle_commit_phase: cannot resolve branch in $worktree_path (got '${branch}') [class=COMMIT_FAILED]"
    _emit_commit_routing_record "$story_id" "$trace_id" "error" "COMMIT_FAILED" "0" "" "false"
    return 1
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

  # ── git push with retry-backoff (AC1-iii + AC5-a) ────────────────────────
  local push_exit=1 push_attempt=0 push_max=3
  while [[ $push_attempt -lt $push_max ]]; do
    push_attempt=$(( push_attempt + 1 ))
    if git -C "$worktree_path" push origin "$branch" 2>/dev/null; then
      push_exit=0; break
    fi
    echo "[WARN] ${story_id} handle_commit_phase: git push attempt ${push_attempt}/${push_max} failed"
    [[ $push_attempt -lt $push_max ]] && sleep $((push_attempt * 2))
  done
  if [[ "$push_exit" -ne 0 ]]; then
    echo "[ERROR] ${story_id} handle_commit_phase: git push failed after ${push_max} attempts [class=PUSH_FAILED]"
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

  # ── gh pr create with retry (AC2 + AC5-b/c/d) ────────────────────────────
  local pr_url="" pr_exit=1 pr_attempt=0 pr_max=3 pr_output
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

  # ── Persist pr_url + pr_number (AC2) ─────────────────────────────────────
  if [[ -n "$pr_url" ]]; then
    "$SCHEDULER" --set-field "$story_id" pr_url "$pr_url" "$BACKLOG_FILE" 2>/dev/null || true
    local pr_number
    pr_number=$(gh pr view "$branch" --json number --jq .number 2>/dev/null || true)
    [[ -n "$pr_number" ]] && "$SCHEDULER" --set-field "$story_id" pr_number "$pr_number" "$BACKLOG_FILE" 2>/dev/null || true
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
    local workspace_policy="${GAAI_AUTO_MERGE_POLICY:-off}"
    if [[ "$workspace_policy" == "on" ]]; then
      auto_merge_applied=true; auto_merge_skipped_reason="null"
    elif [[ "$workspace_policy" == "staging_only" ]]; then
      if [[ "$branch" == "staging" ]]; then
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
      merge_stderr=$(gh pr merge --auto --squash "$pr_url" 2>&1)
      merge_exit=$?
      if [[ "$merge_exit" -eq 0 ]]; then
        # AC5-e: verify autoMergeRequest actually queued
        local merge_check
        merge_check=$(gh pr view "$pr_url" --json autoMergeRequest --jq .autoMergeRequest 2>/dev/null || echo "null")
        if [[ "$merge_check" == "null" ]]; then
          echo "[WARN] ${story_id} handle_commit_phase: auto-merge requested but branch protection not configured — PR remains manual [auto_merge_skipped_reason=branch_protection_missing]"
          auto_merge_applied=false; auto_merge_skipped_reason="branch_protection_missing"
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
      echo "[ERROR] ${story_id} handle_commit_phase: gh pr merge --auto failed after ${merge_max} attempts [class=AUTO_MERGE_FAILED]"
      _emit_commit_routing_record "$story_id" "$trace_id" "error" "AUTO_MERGE_FAILED" "0" "$pr_url" "false"
      return 1
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

  # ── Duration end ─────────────────────────────────────────────────────────
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    t_end_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
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
    done|failed|escalated|qa_failed|qa_escalated)
      return 0
      ;;
    *)
      echo "[ERROR] ${story_id} dispatch_3phase_story: invalid phase_status='${ps}' — known values: not_started planned implemented qa_passed qa_failed qa_escalated done failed escalated"
      _emit_routing_record "$story_id" "$trace_id" "plan" "error" "invalid_phase_status:${ps}"
      return 1
      ;;
  esac

  return 0
}
