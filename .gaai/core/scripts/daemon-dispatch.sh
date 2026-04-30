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

# ── Stub phase handlers (AC3 + AC4) ──────────────────────────────────────

handle_plan_phase() {
  local story_id="$1" trace_id="$2"
  local ts
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=plan dispatched (stub)"

  # Emit routing record (AC4)
  _emit_routing_record "$story_id" "$trace_id" "plan" "stub" ""

  # Advance phase_status: not_started → planned (AC3)
  if ! "$SCHEDULER" --set-phase-status "$story_id" planned "$BACKLOG_FILE" 2>/dev/null; then
    echo "[ERROR] ${story_id} handle_plan_phase: --set-phase-status planned failed"
    _emit_routing_record "$story_id" "$trace_id" "plan" "error" "set-phase-status-failed"
    return 1
  fi

  sleep "${GAAI_STUB_DELAY_S:-0}"
  return 0
}

handle_impl_phase() {
  local story_id="$1" trace_id="$2"
  local ts
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=impl dispatched (stub)"

  # Emit routing record (AC4)
  _emit_routing_record "$story_id" "$trace_id" "impl" "stub" ""

  # Advance phase_status: planned → implemented (AC3)
  if ! "$SCHEDULER" --set-phase-status "$story_id" implemented "$BACKLOG_FILE" 2>/dev/null; then
    echo "[ERROR] ${story_id} handle_impl_phase: --set-phase-status implemented failed"
    _emit_routing_record "$story_id" "$trace_id" "impl" "error" "set-phase-status-failed"
    return 1
  fi

  sleep "${GAAI_STUB_DELAY_S:-0}"
  return 0
}

handle_qa_phase() {
  local story_id="$1" trace_id="$2"
  local ts
  ts=$(date '+%H:%M:%S')
  echo "[${ts}] ${story_id} phase=qa dispatched (stub)"

  # Emit routing record (AC4)
  _emit_routing_record "$story_id" "$trace_id" "qa" "stub" ""

  # Advance phase_status: implemented → qa_passed (AC3)
  if ! "$SCHEDULER" --set-phase-status "$story_id" qa_passed "$BACKLOG_FILE" 2>/dev/null; then
    echo "[ERROR] ${story_id} handle_qa_phase: --set-phase-status qa_passed failed"
    _emit_routing_record "$story_id" "$trace_id" "qa" "error" "set-phase-status-failed"
    return 1
  fi

  sleep "${GAAI_STUB_DELAY_S:-0}"
  return 0
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
    done|failed|escalated)
      # Terminal states — caller loop should stop. Not an error.
      return 0
      ;;
    *)
      # AC6(i)(ii)(iii)(iv): invalid phase_status
      echo "[ERROR] ${story_id} dispatch_3phase_story: invalid phase_status='${ps}' — known values: not_started planned implemented qa_passed done failed escalated"
      _emit_routing_record "$story_id" "$trace_id" "plan" "error" "invalid_phase_status:${ps}"
      return 1
      ;;
  esac

  return 0
}
