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
    "${log_path_args[@]}" \
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
    "${log_path_args[@]}" \
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
    "${log_path_args[@]}" \
    2>/dev/null || true
}

# ── Phase handlers ────────────────────────────────────────────────────────

handle_plan_phase() {
  local story_id="$1" trace_id="$2"
  local ts t_start_ms t_end_ms duration_ms
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=plan starting"

  # ── Resolve env vars for context bundle (AC2) ─────────────────────────────
  local worktree_path story_path plan_path epic_path log_path
  worktree_path="${GAAI_WORKTREE_PATH:-}"
  if [[ -z "$worktree_path" ]]; then
    echo "[ERROR] ${story_id} handle_plan_phase: GAAI_WORKTREE_PATH not set"
    _emit_plan_routing_record "$story_id" "$trace_id" "error" "PLAN_PHASE_FAILED" "0"
    return 1
  fi

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
      --max-turns 20 \
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
  local ts
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=commit dispatched (stub)"

  # Emit routing record (AC4)
  _emit_routing_record "$story_id" "$trace_id" "commit" "stub" ""

  # Advance phase_status: qa_passed → done (stub — real commit/PR/merge is E134S06)
  if ! "$SCHEDULER" --set-phase-status "$story_id" done "$BACKLOG_FILE" 2>/dev/null; then
    echo "[ERROR] ${story_id} handle_commit_phase: --set-phase-status done failed"
    _emit_routing_record "$story_id" "$trace_id" "commit" "error" "set-phase-status-failed"
    return 1
  fi

  sleep "${GAAI_STUB_DELAY_S:-0}"
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
      handle_plan_phase   "$story_id" "$trace_id" || return 1
      ;;
    planned)
      handle_impl_phase   "$story_id" "$trace_id" || return 1
      ;;
    implemented)
      handle_qa_phase     "$story_id" "$trace_id" || return 1
      ;;
    qa_passed)
      handle_commit_phase "$story_id" "$trace_id" || return 1
      ;;
    done|failed|escalated|qa_failed|qa_escalated)
      # Terminal states — caller loop should stop. Not an error.
      return 0
      ;;
    *)
      # AC6(i)(ii)(iii)(iv): invalid phase_status
      echo "[ERROR] ${story_id} dispatch_3phase_story: invalid phase_status='${ps}' — known values: not_started planned implemented qa_passed qa_failed qa_escalated done failed escalated"
      _emit_routing_record "$story_id" "$trace_id" "plan" "error" "invalid_phase_status:${ps}"
      return 1
      ;;
  esac

  return 0
}
