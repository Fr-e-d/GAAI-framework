#!/usr/bin/env bash
# lib/stuck-classifier.sh — structured failure classifier for stuck stories (E160S04)
#
# classify_stuck_story <sid> [<current_phase_status>]
#   Returns:
#     0 = auto-recovery action taken and succeeded
#     1 = escalation fired (incident report written with path in remediation hint)
#     2 = no-op (already classified by S02/S03, or prior successful recovery)
#
# Env vars (provided by sourcing daemon):
#   PROJECT_DIR, GAAI_PROJECT_DIR, LOCK_DIR, LOG_DIR, TARGET_BRANCH, BACKLOG
#   GAAI_STUCK_CLASSIFY_TIMEOUT_SEC  (default 10)
#   GAAI_STUCK_CLASSIFY_DELETIONS_MAX (default 100)
#
# Functions required from daemon scope:
#   log, notify_escalation, _recovery_revert_refined, _recovery_resolve_worktree
#   _recover_worktree_safe_base (optional — checked via declare -F)

[[ -n "${_STUCK_CLASSIFIER_SH_SOURCED:-}" ]] && return 0
_STUCK_CLASSIFIER_SH_SOURCED=1

# Portable timeout: uses `timeout` (Linux/GNU), `gtimeout` (macOS brew), or runs directly.
_classify_run_timed() {
  local _secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_secs" "$@"
  else
    "$@"
  fi
}

classify_stuck_story() {
  local sid="$1"
  local current_ps="${2:-}"

  local _classify_timeout="${GAAI_STUCK_CLASSIFY_TIMEOUT_SEC:-10}"
  local _phantom_threshold="${GAAI_STUCK_CLASSIFY_DELETIONS_MAX:-100}"
  local _ps_key="${current_ps:-empty}"

  local _gaai_project="${GAAI_PROJECT_DIR:-${PROJECT_DIR}/.gaai/project}"
  local incidents_dir="${_gaai_project}/contexts/artefacts/incidents"

  local utc_ts utc_ts_filename
  utc_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  utc_ts_filename=$(date -u +%Y%m%dT%H%M%SZ)
  local incident_file="${incidents_dir}/incident-${sid}-${utc_ts_filename}.md"

  # ── Section A: Idempotence check ────────────────────────────────────────────
  # If a prior successful recovery for this story+phase_status exists, skip.
  local _prior_report
  _prior_report=$(ls -t "${incidents_dir}/incident-${sid}-"*.md 2>/dev/null | head -1 || true)
  if [[ -n "$_prior_report" && -f "$_prior_report" ]]; then
    local _prior_outcome _prior_ps
    _prior_outcome=$(grep -m1 "^auto_recovery_outcome:" "$_prior_report" 2>/dev/null \
      | sed 's/^auto_recovery_outcome: *//;s/"//g' | tr -d '[:space:]' || true)
    _prior_ps=$(grep -m1 "^phase_status_at_classification:" "$_prior_report" 2>/dev/null \
      | sed 's/^phase_status_at_classification: *//;s/"//g' | tr -d '[:space:]' || true)
    if [[ "$_prior_outcome" == "success" ]] && [[ "$_prior_ps" == "$_ps_key" ]]; then
      log "[STUCK-CLASSIFY] $sid : prior successful recovery found (phase_status=${_ps_key}, outcome=success) — skip (no-op)"
      return 2
    fi
  fi

  mkdir -p "$incidents_dir"

  # ── Section B: Evidence collection ──────────────────────────────────────────
  local worktree_path
  worktree_path=$(_recovery_resolve_worktree "$sid")

  # Branch commits (story branch vs TARGET_BRANCH on remote; fall back to local refs)
  local branch_commits branch_commit_count
  branch_commits=$(_classify_run_timed "$_classify_timeout" \
    git -C "$PROJECT_DIR" log "origin/${TARGET_BRANCH}..origin/story/${sid}" --oneline 2>/dev/null \
    || _classify_run_timed "$_classify_timeout" \
       git -C "$PROJECT_DIR" log "${TARGET_BRANCH}..story/${sid}" --oneline 2>/dev/null \
    || true)
  branch_commit_count=$(echo "$branch_commits" | grep -c . 2>/dev/null || echo 0)
  [[ -z "$branch_commits" ]] && branch_commit_count=0

  # Phantom deletes: files removed on story branch vs TARGET_BRANCH
  # Falls back to local branch refs if remote tracking refs are absent.
  local phantom_deletes=0
  local _pd_out
  _pd_out=$(_classify_run_timed "$_classify_timeout" \
    git -C "$PROJECT_DIR" diff --name-only --diff-filter=D \
    "origin/${TARGET_BRANCH}...origin/story/${sid}" 2>/dev/null \
    || _classify_run_timed "$_classify_timeout" \
       git -C "$PROJECT_DIR" diff --name-only --diff-filter=D \
       "${TARGET_BRANCH}...story/${sid}" 2>/dev/null \
    || echo "")
  if [[ -n "$_pd_out" ]]; then
    phantom_deletes=$(echo "$_pd_out" | wc -l | tr -d ' ' || echo 0)
  fi

  # Artefact presence (on worktree filesystem)
  local plan_file notes_file impl_report qa_report deploy_log
  plan_file="${worktree_path}/.gaai/project/contexts/artefacts/plans/${sid}.execution-plan.md"
  notes_file="${worktree_path}/.gaai/project/contexts/artefacts/notes/${sid}.notes.md"
  impl_report="${worktree_path}/.gaai/project/contexts/artefacts/impl-reports/${sid}.impl-report.md"
  qa_report="${worktree_path}/.gaai/project/contexts/artefacts/qa-reports/${sid}.qa-report.md"
  [[ ! -f "$qa_report" ]] && \
    qa_report="${worktree_path}/.gaai/project/contexts/artefacts/reports/${sid}.qa-report.md"
  deploy_log="${LOG_DIR}/${sid}.deploy.log"

  local artefacts_present=()
  [[ -f "$plan_file" ]]   && artefacts_present+=("plan")
  [[ -f "$notes_file" ]]  && artefacts_present+=("notes")
  [[ -f "$impl_report" ]] && artefacts_present+=("impl-report")
  [[ -f "$qa_report" ]]   && artefacts_present+=("qa-report")
  [[ -f "$deploy_log" ]]  && artefacts_present+=("deploy-log")
  local artefacts_str
  if [[ ${#artefacts_present[@]} -gt 0 ]]; then
    artefacts_str=$(IFS=,; echo "${artefacts_present[*]}")
  else
    artefacts_str="none"
  fi

  # Lock markers
  local marker_reconcile marker_interrupted marker_commit_pending marker_orphan
  marker_reconcile="$LOCK_DIR/${sid}.reconcile-in-progress"
  marker_interrupted="$LOCK_DIR/${sid}.interrupted"
  marker_commit_pending="$LOCK_DIR/${sid}.commit-pending"
  marker_orphan="$LOCK_DIR/${sid}.orphan-classified"

  local markers_present=()
  [[ -f "$marker_reconcile" ]]    && markers_present+=("reconcile-in-progress")
  [[ -f "$marker_interrupted" ]]  && markers_present+=("interrupted")
  [[ -f "$marker_commit_pending" ]] && markers_present+=("commit-pending")
  [[ -f "$marker_orphan" ]]       && markers_present+=("orphan-classified")
  local markers_str
  if [[ ${#markers_present[@]} -gt 0 ]]; then
    markers_str=$(IFS=,; echo "${markers_present[*]}")
  else
    markers_str="none"
  fi

  # Log tail (last 50 lines)
  local log_tail_content="(unavailable: no log file)"
  local log_file_path="${LOG_DIR}/${sid}.log"
  if [[ -f "$log_file_path" ]]; then
    log_tail_content=$(tail -50 "$log_file_path" 2>/dev/null || echo "(unavailable: read error)")
  fi

  log "[STUCK-CLASSIFY] $sid : classifying — phase_status=${current_ps:-empty} branch_commits=${branch_commit_count} artefacts=${artefacts_str}"

  # ── Section C: Classification taxonomy ──────────────────────────────────────
  # Evaluated top-to-bottom; first match wins.
  local class="unknown"
  local recovery_applicable="false"
  local auto_action="none"
  local class_rationale="No specific heuristic matched — classified as unknown."

  # 1. stale_race_residual
  if [[ "$current_ps" =~ ^(done|failed|escalated|qa_escalated)$ ]] \
     && [[ "$markers_str" == "none" ]]; then
    class="stale_race_residual"
    recovery_applicable="true"
    auto_action="_recovery_revert_refined"
    class_rationale="Terminal phase_status '${current_ps}' with status=in_progress and no markers present. E160S01 should have resolved this at-source; classifier is second-layer defense."

  # 2. orphan_lock_classified — E160S02 already handled
  elif [[ -f "$marker_orphan" ]]; then
    class="orphan_lock_classified"
    recovery_applicable="true"
    auto_action="no_op"
    class_rationale="E160S02 orphan-classified marker present — S02 already processed this orphan. No additional action needed."

  # 3. pnpm_install_failed — E160S03 escalation path owns recovery
  elif [[ "$current_ps" == "commit_failed" ]]; then
    class="pnpm_install_failed"
    recovery_applicable="true"
    auto_action="no_op"
    class_rationale="phase_status=commit_failed set by E160S03 when pnpm install fails pre-commit. S03 escalation path owns recovery."

  # 4. worktree_corruption_suspected
  elif (( phantom_deletes > _phantom_threshold )) || \
       { [[ -d "${worktree_path}/.git" ]] && \
         _classify_run_timed "$_classify_timeout" git -C "$worktree_path" fsck --no-progress 2>&1 \
           | grep -q "error:" 2>/dev/null; }; then
    class="worktree_corruption_suspected"
    if declare -F _recover_worktree_safe_base >/dev/null 2>&1; then
      recovery_applicable="true"
      auto_action="_recover_worktree_safe_base"
    else
      recovery_applicable="false"
      auto_action="none"
    fi
    local _s05_available
    _s05_available=$(declare -F _recover_worktree_safe_base >/dev/null 2>&1 && echo yes || echo no)
    class_rationale="Phantom deletes=${phantom_deletes} (threshold=${_phantom_threshold}) or git fsck error on worktree. E160S05 helper availability: ${_s05_available}."

  # 5. qa_failed_orphan — retry cap exhausted per E159S01
  elif [[ -f "$qa_report" ]] \
       && echo "$log_tail_content" | grep -qE "(retry_cap_exhausted|max_retries.*exceeded|ESCALATE.*retry)" 2>/dev/null; then
    class="qa_failed_orphan"
    recovery_applicable="true"
    auto_action="notify_escalation"
    class_rationale="qa-report present and log tail contains retry-cap-exhausted signal. E159S01 escalation path owns final disposition."

  # 6. pr_creation_silent_failure
  elif [[ -f "$deploy_log" ]] && [[ -f "$impl_report" ]] && [[ -f "$qa_report" ]] \
       && [[ "$current_ps" =~ ^(implemented|qa_passed)$ ]] \
       && ! grep -A10 "id: ${sid}" "$BACKLOG" 2>/dev/null | grep -q "pr_url:"; then
    class="pr_creation_silent_failure"
    recovery_applicable="false"
    auto_action="none"
    class_rationale="All delivery artefacts present (impl-report, qa-report, deploy-log) with phase_status=${current_ps} but no pr_url in backlog. PR creation likely failed silently."

  # 7. unknown (catch-all)
  else
    class="unknown"
    recovery_applicable="false"
    auto_action="none"
    class_rationale="No specific heuristic matched — classified as unknown."
  fi

  log "[STUCK-CLASSIFY] $sid : class=${class} recovery_applicable=${recovery_applicable} auto_action=${auto_action}"

  # ── Section D: Auto-action execution (BEFORE incident report write — AC2) ──
  local auto_recovery_outcome="n_a"
  local _action_rc=0

  case "$auto_action" in
    no_op)
      # S02/S03 already handled — return 2 immediately (no report written for no-op classes)
      return 2
      ;;

    _recovery_revert_refined)
      if _recovery_revert_refined "$sid" false "stale-race-residual"; then
        auto_recovery_outcome="success"
        log "[STUCK-CLASSIFY] $sid : auto-recovery success — _recovery_revert_refined completed"
      else
        auto_recovery_outcome="failed"
        _action_rc=1
        log "[STUCK-CLASSIFY] $sid : auto-recovery failed — _recovery_revert_refined returned non-zero"
      fi
      ;;

    _recover_worktree_safe_base)
      if _recover_worktree_safe_base "$sid" "$worktree_path" "$TARGET_BRANCH"; then
        auto_recovery_outcome="success"
        log "[STUCK-CLASSIFY] $sid : auto-recovery success — _recover_worktree_safe_base completed"
      else
        auto_recovery_outcome="failed"
        _action_rc=1
        log "[STUCK-CLASSIFY] $sid : auto-recovery failed — _recover_worktree_safe_base returned non-zero"
      fi
      ;;

    notify_escalation|none)
      # Escalation fires after report write
      auto_recovery_outcome="n_a"
      _action_rc=1
      ;;
  esac

  # ── Section E: Incident report write (write-once after action, AC2) ─────────
  local action_summary
  if [[ "$auto_recovery_outcome" == "success" ]]; then
    action_summary="Auto-action: ${auto_action} — outcome: success."
  else
    action_summary="Manual review required. Inspect the evidence above and the story branch: git log origin/${TARGET_BRANCH}..origin/story/${sid} --oneline; incident report: ${incident_file}"
  fi

  mkdir -p "$incidents_dir"
  {
    printf '%s\n'   "---"
    printf '%s\n'   "classified_at: \"${utc_ts}\""
    printf '%s\n'   "story_id: \"${sid}\""
    printf '%s\n'   "phase_status_at_classification: \"${_ps_key}\""
    printf '%s\n'   "class: ${class}"
    printf '%s\n'   "recovery_applicable: ${recovery_applicable}"
    printf '%s\n'   "auto_action_taken: \"${auto_action}\""
    printf '%s\n'   "auto_recovery_outcome: \"${auto_recovery_outcome}\""
    printf '%s\n\n' "---"
    printf '%s\n\n' "## Evidence Collected"
    printf '%s\n'   "- phase_status: ${current_ps:-empty}"
    printf '%s\n'   "- branch_commits: ${branch_commit_count} commits"
    printf '%s\n'   "- phantom_deletes: ${phantom_deletes}"
    printf '%s\n'   "- artefacts_present: [${artefacts_str}]"
    printf '%s\n'   "- markers: [${markers_str}]"
    printf '%s\n\n' "- log_tail: (last 50 lines)"
    printf '%s\n'   '```'
    printf '%s\n'   "$log_tail_content"
    printf '%s\n\n' '```'
    printf '%s\n\n' "## Classification Rationale"
    printf '%s\n\n' "$class_rationale"
    printf '%s\n\n' "## Action Taken or Recommended"
    printf '%s\n'   "$action_summary"
  } > "$incident_file"

  # ── Section F: Return value + escalation ────────────────────────────────────
  if [[ "$auto_recovery_outcome" == "success" ]]; then
    return 0
  else
    notify_escalation "$sid" "stuck-classified-${class}" "${incident_file}"
    log "[STUCK-CLASSIFY] $sid : escalated with incident report ${incident_file}"
    return 1
  fi
}
