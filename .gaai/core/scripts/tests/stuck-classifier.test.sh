#!/usr/bin/env bash
# stuck-classifier.test.sh — regression tests for classify_stuck_story() (E160S04)
#
# T1: stale_race_residual class → auto-recovery invoked + incident report written (rc=0)
# T2: worktree_corruption_suspected class (phantom_deletes>100) → escalation with incident report (rc=1)
# T3: pr_creation_silent_failure class → escalation (rc=1)
# T4: unknown class → escalation with full evidence in incident body (rc=1)
# T5: orphan_lock_classified (S02 marker present) → no-op skip (rc=2, no actions invoked)
#
# Usage: bash .gaai/core/scripts/tests/stuck-classifier.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSIFIER_LIB="$SCRIPT_DIR/../lib/stuck-classifier.sh"

FIXTURE_DIR="/tmp/gaai-stuck-classifier-test-$$"
mkdir -p "$FIXTURE_DIR"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── Git repo helper ─────────────────────────────────────────────────────────────
setup_git_repo() {
  local project_dir="$1" yaml_content="$2"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  mkdir -p "$project_dir/.gaai/project/contexts/backlog"
  printf '%s\n' "$yaml_content" > "$project_dir/.gaai/project/contexts/backlog/active.backlog.yaml"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push origin HEAD -q
}

# ── Build test harness helper ───────────────────────────────────────────────────
# Writes a self-contained bash script to $1 that:
#   - Sets required env vars from fixture paths embedded at write time
#   - Defines stub functions (log, notify_escalation, _recovery_revert_refined, etc.)
#   - Sources the classifier lib
#   - Calls classify_stuck_story with $SID and $PHASE_STATUS from harness env
build_base_harness() {
  local harness="$1"
  local project_dir="$2"
  local lock_dir="$3"
  local log_dir="$4"
  local gaai_project_dir="$5"
  local backlog_file="$6"

  cat > "$harness" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail

PROJECT_DIR="$project_dir"
LOCK_DIR="$lock_dir"
LOG_DIR="$log_dir"
GAAI_PROJECT_DIR="$gaai_project_dir"
BACKLOG="$backlog_file"
TARGET_BRANCH="main"
GAAI_STUCK_CLASSIFY_TIMEOUT_SEC=5
NOTIFY_CALLED=0
REVERT_CALLED=0
RECOVER_WT_CALLED=0

log() { printf '[LOG] %s\n' "\$*" >&2; }

notify_escalation() {
  NOTIFY_CALLED=\$(( NOTIFY_CALLED + 1 ))
}

_recovery_revert_refined() {
  REVERT_CALLED=\$(( REVERT_CALLED + 1 ))
  return 0
}

_recovery_resolve_worktree() {
  echo "${FIXTURE_DIR}/\$1-worktree"
}

# NOTE: _recover_worktree_safe_base is intentionally NOT defined here.
# Tests that need it defined will append a definition after this base.

HARNESS
}

# ═══════════════════════════════════════════════════════════════════════════════
# T1 — stale_race_residual: terminal phase_status, no markers → auto-recovery
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: stale_race_residual — auto-recovery invoked + incident report written ==="

T1_SID="T1-STALE"
T1_PROJ="$FIXTURE_DIR/t1-project"
T1_LOCKS="$FIXTURE_DIR/t1-locks"
T1_LOGS="$FIXTURE_DIR/t1-logs"
T1_GAAI_PROJ="$FIXTURE_DIR/t1-gaai-project"
T1_YAML="- id: ${T1_SID}
  status: in_progress
  phase_status: failed
  delivery_pipeline: 3phase"

mkdir -p "$T1_LOCKS" "$T1_LOGS" "$T1_GAAI_PROJ/contexts/artefacts/incidents"
setup_git_repo "$T1_PROJ" "$T1_YAML"

T1_BACKLOG="$T1_PROJ/.gaai/project/contexts/backlog/active.backlog.yaml"
T1_HARNESS=$(mktemp /tmp/gaai-t1-harness-XXXXXX.sh)
build_base_harness "$T1_HARNESS" "$T1_PROJ" "$T1_LOCKS" "$T1_LOGS" "$T1_GAAI_PROJ" "$T1_BACKLOG"
cat >> "$T1_HARNESS" <<T1APPEND

source "$CLASSIFIER_LIB"

classify_stuck_story "$T1_SID" "failed"
T1_RC=\$?

printf 'RC=%s\n' "\$T1_RC"
printf 'REVERT_CALLED=%s\n' "\$REVERT_CALLED"
printf 'NOTIFY_CALLED=%s\n' "\$NOTIFY_CALLED"

# Find incident file
T1_INCIDENT=\$(ls -t "${T1_GAAI_PROJ}/contexts/artefacts/incidents/incident-${T1_SID}-"*.md 2>/dev/null | head -1 || true)
printf 'INCIDENT_EXISTS=%s\n' "\$([ -n "\$T1_INCIDENT" ] && [ -f "\$T1_INCIDENT" ] && echo yes || echo no)"
if [ -f "\$T1_INCIDENT" ]; then
  printf 'INCIDENT_CLASS=%s\n' "\$(grep -m1 '^class:' "\$T1_INCIDENT" | awk '{print \$2}' || true)"
  printf 'INCIDENT_OUTCOME=%s\n' "\$(grep -m1 '^auto_recovery_outcome:' "\$T1_INCIDENT" | sed 's/.*: *//;s/\"//g' || true)"
fi
T1APPEND

chmod +x "$T1_HARNESS"
T1_OUT=$(bash "$T1_HARNESS" 2>/dev/null)
rm -f "$T1_HARNESS"

T1_RC=$(echo "$T1_OUT" | grep '^RC=' | cut -d= -f2)
T1_REVERT=$(echo "$T1_OUT" | grep '^REVERT_CALLED=' | cut -d= -f2)
T1_NOTIFY=$(echo "$T1_OUT" | grep '^NOTIFY_CALLED=' | cut -d= -f2)
T1_INC_EXISTS=$(echo "$T1_OUT" | grep '^INCIDENT_EXISTS=' | cut -d= -f2)
T1_INC_CLASS=$(echo "$T1_OUT" | grep '^INCIDENT_CLASS=' | cut -d= -f2)
T1_INC_OUTCOME=$(echo "$T1_OUT" | grep '^INCIDENT_OUTCOME=' | cut -d= -f2)

if [[ "$T1_RC" == "0" ]]; then
  pass "T1: classify_stuck_story returned 0 (auto-recovered)"
else
  fail "T1: expected rc=0, got rc=${T1_RC:-?}"
fi

if [[ "$T1_REVERT" == "1" ]]; then
  pass "T1: _recovery_revert_refined called once"
else
  fail "T1: expected REVERT_CALLED=1, got ${T1_REVERT:-0}"
fi

if [[ "$T1_NOTIFY" == "0" ]]; then
  pass "T1: notify_escalation NOT called (no escalation on success)"
else
  fail "T1: expected NOTIFY_CALLED=0, got ${T1_NOTIFY:-?}"
fi

if [[ "$T1_INC_EXISTS" == "yes" ]]; then
  pass "T1: incident report file written"
else
  fail "T1: incident report file not found"
fi

if [[ "$T1_INC_CLASS" == "stale_race_residual" ]]; then
  pass "T1: incident report class=stale_race_residual"
else
  fail "T1: expected class=stale_race_residual, got '${T1_INC_CLASS:-?}'"
fi

if [[ "$T1_INC_OUTCOME" == "success" ]]; then
  pass "T1: incident report auto_recovery_outcome=success"
else
  fail "T1: expected auto_recovery_outcome=success, got '${T1_INC_OUTCOME:-?}'"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T2 — worktree_corruption_suspected: phantom_deletes>100 → escalation
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: worktree_corruption_suspected — escalation with incident report path ==="

T2_SID="T2-CORRUPT"
T2_PROJ="$FIXTURE_DIR/t2-project"
T2_REMOTE="${T2_PROJ}_remote.git"
T2_LOCKS="$FIXTURE_DIR/t2-locks"
T2_LOGS="$FIXTURE_DIR/t2-logs"
T2_GAAI_PROJ="$FIXTURE_DIR/t2-gaai-project"
T2_YAML="- id: ${T2_SID}
  status: in_progress
  phase_status: something_odd
  delivery_pipeline: 3phase"

mkdir -p "$T2_LOCKS" "$T2_LOGS" "$T2_GAAI_PROJ/contexts/artefacts/incidents"

# Set up git repo with 102 files on main, all deleted on story branch
rm -rf "$T2_PROJ" "$T2_REMOTE"
git init --bare "$T2_REMOTE" -q
git clone "$T2_REMOTE" "$T2_PROJ" -q
git -C "$T2_PROJ" config user.email "test@gaai.local"
git -C "$T2_PROJ" config user.name "GAAI Test"
mkdir -p "$T2_PROJ/.gaai/project/contexts/backlog"
printf '%s\n' "$T2_YAML" > "$T2_PROJ/.gaai/project/contexts/backlog/active.backlog.yaml"
for i in $(seq 1 102); do printf 'file%s\n' "$i" > "$T2_PROJ/testfile_${i}.txt"; done
git -C "$T2_PROJ" add -A
git -C "$T2_PROJ" commit -q -m "initial-with-102-files"
git -C "$T2_PROJ" push -q origin HEAD:main
# Story branch deletes all 102 test files
git -C "$T2_PROJ" checkout -q -b "story/${T2_SID}"
for i in $(seq 1 102); do git -C "$T2_PROJ" rm -q "testfile_${i}.txt"; done
git -C "$T2_PROJ" commit -q -m "delete files"
git -C "$T2_PROJ" push -q origin "story/${T2_SID}"
git -C "$T2_PROJ" checkout -q main

T2_BACKLOG="$T2_PROJ/.gaai/project/contexts/backlog/active.backlog.yaml"
T2_HARNESS=$(mktemp /tmp/gaai-t2-harness-XXXXXX.sh)
build_base_harness "$T2_HARNESS" "$T2_PROJ" "$T2_LOCKS" "$T2_LOGS" "$T2_GAAI_PROJ" "$T2_BACKLOG"
cat >> "$T2_HARNESS" <<T2APPEND
# _recover_worktree_safe_base intentionally NOT defined — test escalation path

source "$CLASSIFIER_LIB"

classify_stuck_story "$T2_SID" "something_odd"
T2_RC=\$?

printf 'RC=%s\n' "\$T2_RC"
printf 'NOTIFY_CALLED=%s\n' "\$NOTIFY_CALLED"
printf 'REVERT_CALLED=%s\n' "\$REVERT_CALLED"

T2_INCIDENT=\$(ls -t "${T2_GAAI_PROJ}/contexts/artefacts/incidents/incident-${T2_SID}-"*.md 2>/dev/null | head -1 || true)
printf 'INCIDENT_EXISTS=%s\n' "\$([ -n "\$T2_INCIDENT" ] && [ -f "\$T2_INCIDENT" ] && echo yes || echo no)"
if [ -f "\$T2_INCIDENT" ]; then
  printf 'INCIDENT_CLASS=%s\n' "\$(grep -m1 '^class:' "\$T2_INCIDENT" | awk '{print \$2}' || true)"
  printf 'INCIDENT_RECOVERY=%s\n' "\$(grep -m1 '^recovery_applicable:' "\$T2_INCIDENT" | awk '{print \$2}' || true)"
fi
T2APPEND

chmod +x "$T2_HARNESS"
T2_OUT=$(bash "$T2_HARNESS" 2>/dev/null)
rm -f "$T2_HARNESS"

T2_RC=$(echo "$T2_OUT" | grep '^RC=' | cut -d= -f2)
T2_NOTIFY=$(echo "$T2_OUT" | grep '^NOTIFY_CALLED=' | cut -d= -f2)
T2_REVERT=$(echo "$T2_OUT" | grep '^REVERT_CALLED=' | cut -d= -f2)
T2_INC_EXISTS=$(echo "$T2_OUT" | grep '^INCIDENT_EXISTS=' | cut -d= -f2)
T2_INC_CLASS=$(echo "$T2_OUT" | grep '^INCIDENT_CLASS=' | cut -d= -f2)
T2_INC_RECOVERY=$(echo "$T2_OUT" | grep '^INCIDENT_RECOVERY=' | cut -d= -f2)

if [[ "$T2_RC" == "1" ]]; then
  pass "T2: classify_stuck_story returned 1 (escalated)"
else
  fail "T2: expected rc=1, got rc=${T2_RC:-?}"
fi

if [[ "$T2_NOTIFY" == "1" ]]; then
  pass "T2: notify_escalation called"
else
  fail "T2: expected NOTIFY_CALLED=1, got ${T2_NOTIFY:-0}"
fi

if [[ "$T2_REVERT" == "0" ]]; then
  pass "T2: _recovery_revert_refined NOT called"
else
  fail "T2: expected REVERT_CALLED=0, got ${T2_REVERT:-?}"
fi

if [[ "$T2_INC_EXISTS" == "yes" ]]; then
  pass "T2: incident report file written"
else
  fail "T2: incident report file not found"
fi

if [[ "$T2_INC_CLASS" == "worktree_corruption_suspected" ]]; then
  pass "T2: incident report class=worktree_corruption_suspected"
else
  fail "T2: expected class=worktree_corruption_suspected, got '${T2_INC_CLASS:-?}'"
fi

if [[ "$T2_INC_RECOVERY" == "false" ]]; then
  pass "T2: recovery_applicable=false (worktree-recovery helper not available)"
else
  fail "T2: expected recovery_applicable=false, got '${T2_INC_RECOVERY:-?}'"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T3 — pr_creation_silent_failure: all artefacts present, no pr_url → escalation
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: pr_creation_silent_failure — escalation with incident report ==="

T3_SID="T3-PRFAIL"
T3_PROJ="$FIXTURE_DIR/t3-project"
T3_LOCKS="$FIXTURE_DIR/t3-locks"
T3_LOGS="$FIXTURE_DIR/t3-logs"
T3_GAAI_PROJ="$FIXTURE_DIR/t3-gaai-project"
T3_WORKTREE="$FIXTURE_DIR/${T3_SID}-worktree"
T3_YAML="- id: ${T3_SID}
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase"

mkdir -p "$T3_LOCKS" "$T3_LOGS" "$T3_GAAI_PROJ/contexts/artefacts/incidents"
# Create artefact files that trigger pr_creation_silent_failure heuristic
mkdir -p "$T3_WORKTREE/.gaai/project/contexts/artefacts/impl-reports"
mkdir -p "$T3_WORKTREE/.gaai/project/contexts/artefacts/qa-reports"
touch "$T3_WORKTREE/.gaai/project/contexts/artefacts/impl-reports/${T3_SID}.impl-report.md"
touch "$T3_WORKTREE/.gaai/project/contexts/artefacts/qa-reports/${T3_SID}.qa-report.md"
touch "$T3_LOGS/${T3_SID}.deploy.log"
setup_git_repo "$T3_PROJ" "$T3_YAML"

T3_BACKLOG="$T3_PROJ/.gaai/project/contexts/backlog/active.backlog.yaml"
T3_HARNESS=$(mktemp /tmp/gaai-t3-harness-XXXXXX.sh)
build_base_harness "$T3_HARNESS" "$T3_PROJ" "$T3_LOCKS" "$T3_LOGS" "$T3_GAAI_PROJ" "$T3_BACKLOG"
cat >> "$T3_HARNESS" <<T3APPEND

source "$CLASSIFIER_LIB"

classify_stuck_story "$T3_SID" "qa_passed"
T3_RC=\$?

printf 'RC=%s\n' "\$T3_RC"
printf 'NOTIFY_CALLED=%s\n' "\$NOTIFY_CALLED"

T3_INCIDENT=\$(ls -t "${T3_GAAI_PROJ}/contexts/artefacts/incidents/incident-${T3_SID}-"*.md 2>/dev/null | head -1 || true)
printf 'INCIDENT_EXISTS=%s\n' "\$([ -n "\$T3_INCIDENT" ] && [ -f "\$T3_INCIDENT" ] && echo yes || echo no)"
if [ -f "\$T3_INCIDENT" ]; then
  printf 'INCIDENT_CLASS=%s\n' "\$(grep -m1 '^class:' "\$T3_INCIDENT" | awk '{print \$2}' || true)"
  printf 'INCIDENT_RECOVERY=%s\n' "\$(grep -m1 '^recovery_applicable:' "\$T3_INCIDENT" | awk '{print \$2}' || true)"
fi
T3APPEND

chmod +x "$T3_HARNESS"
T3_OUT=$(bash "$T3_HARNESS" 2>/dev/null)
rm -f "$T3_HARNESS"

T3_RC=$(echo "$T3_OUT" | grep '^RC=' | cut -d= -f2)
T3_NOTIFY=$(echo "$T3_OUT" | grep '^NOTIFY_CALLED=' | cut -d= -f2)
T3_INC_EXISTS=$(echo "$T3_OUT" | grep '^INCIDENT_EXISTS=' | cut -d= -f2)
T3_INC_CLASS=$(echo "$T3_OUT" | grep '^INCIDENT_CLASS=' | cut -d= -f2)
T3_INC_RECOVERY=$(echo "$T3_OUT" | grep '^INCIDENT_RECOVERY=' | cut -d= -f2)

if [[ "$T3_RC" == "1" ]]; then
  pass "T3: classify_stuck_story returned 1 (escalated)"
else
  fail "T3: expected rc=1, got rc=${T3_RC:-?}"
fi

if [[ "$T3_NOTIFY" == "1" ]]; then
  pass "T3: notify_escalation called"
else
  fail "T3: expected NOTIFY_CALLED=1, got ${T3_NOTIFY:-0}"
fi

if [[ "$T3_INC_EXISTS" == "yes" ]]; then
  pass "T3: incident report file written"
else
  fail "T3: incident report file not found"
fi

if [[ "$T3_INC_CLASS" == "pr_creation_silent_failure" ]]; then
  pass "T3: incident report class=pr_creation_silent_failure"
else
  fail "T3: expected class=pr_creation_silent_failure, got '${T3_INC_CLASS:-?}'"
fi

if [[ "$T3_INC_RECOVERY" == "false" ]]; then
  pass "T3: recovery_applicable=false"
else
  fail "T3: expected recovery_applicable=false, got '${T3_INC_RECOVERY:-?}'"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T4 — unknown class: no heuristic matches → escalation with full evidence body
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: unknown class — escalation with evidence sections in incident body ==="

T4_SID="T4-UNK"
T4_PROJ="$FIXTURE_DIR/t4-project"
T4_LOCKS="$FIXTURE_DIR/t4-locks"
T4_LOGS="$FIXTURE_DIR/t4-logs"
T4_GAAI_PROJ="$FIXTURE_DIR/t4-gaai-project"
T4_YAML="- id: ${T4_SID}
  status: in_progress
  phase_status: bizarre_custom_value
  delivery_pipeline: 3phase"

mkdir -p "$T4_LOCKS" "$T4_LOGS" "$T4_GAAI_PROJ/contexts/artefacts/incidents"
setup_git_repo "$T4_PROJ" "$T4_YAML"

T4_BACKLOG="$T4_PROJ/.gaai/project/contexts/backlog/active.backlog.yaml"
T4_HARNESS=$(mktemp /tmp/gaai-t4-harness-XXXXXX.sh)
build_base_harness "$T4_HARNESS" "$T4_PROJ" "$T4_LOCKS" "$T4_LOGS" "$T4_GAAI_PROJ" "$T4_BACKLOG"
cat >> "$T4_HARNESS" <<T4APPEND

source "$CLASSIFIER_LIB"

classify_stuck_story "$T4_SID" "bizarre_custom_value"
T4_RC=\$?

printf 'RC=%s\n' "\$T4_RC"
printf 'NOTIFY_CALLED=%s\n' "\$NOTIFY_CALLED"

T4_INCIDENT=\$(ls -t "${T4_GAAI_PROJ}/contexts/artefacts/incidents/incident-${T4_SID}-"*.md 2>/dev/null | head -1 || true)
printf 'INCIDENT_EXISTS=%s\n' "\$([ -n "\$T4_INCIDENT" ] && [ -f "\$T4_INCIDENT" ] && echo yes || echo no)"
if [ -f "\$T4_INCIDENT" ]; then
  printf 'INCIDENT_CLASS=%s\n' "\$(grep -m1 '^class:' "\$T4_INCIDENT" | awk '{print \$2}' || true)"
  printf 'HAS_EVIDENCE=%s\n' "\$(grep -c '## Evidence Collected' "\$T4_INCIDENT" 2>/dev/null || true)"
  printf 'HAS_RATIONALE=%s\n' "\$(grep -c '## Classification Rationale' "\$T4_INCIDENT" 2>/dev/null || true)"
fi
T4APPEND

chmod +x "$T4_HARNESS"
T4_OUT=$(bash "$T4_HARNESS" 2>/dev/null)
rm -f "$T4_HARNESS"

T4_RC=$(echo "$T4_OUT" | grep '^RC=' | cut -d= -f2)
T4_NOTIFY=$(echo "$T4_OUT" | grep '^NOTIFY_CALLED=' | cut -d= -f2)
T4_INC_EXISTS=$(echo "$T4_OUT" | grep '^INCIDENT_EXISTS=' | cut -d= -f2)
T4_INC_CLASS=$(echo "$T4_OUT" | grep '^INCIDENT_CLASS=' | cut -d= -f2)
T4_HAS_EVIDENCE=$(echo "$T4_OUT" | grep '^HAS_EVIDENCE=' | cut -d= -f2)
T4_HAS_RATIONALE=$(echo "$T4_OUT" | grep '^HAS_RATIONALE=' | cut -d= -f2)

if [[ "$T4_RC" == "1" ]]; then
  pass "T4: classify_stuck_story returned 1 (escalated)"
else
  fail "T4: expected rc=1, got rc=${T4_RC:-?}"
fi

if [[ "$T4_NOTIFY" == "1" ]]; then
  pass "T4: notify_escalation called"
else
  fail "T4: expected NOTIFY_CALLED=1, got ${T4_NOTIFY:-0}"
fi

if [[ "$T4_INC_EXISTS" == "yes" ]]; then
  pass "T4: incident report file written"
else
  fail "T4: incident report file not found"
fi

if [[ "$T4_INC_CLASS" == "unknown" ]]; then
  pass "T4: incident report class=unknown"
else
  fail "T4: expected class=unknown, got '${T4_INC_CLASS:-?}'"
fi

if [[ "${T4_HAS_EVIDENCE:-0}" -ge "1" ]]; then
  pass "T4: incident report contains ## Evidence Collected section"
else
  fail "T4: incident report missing ## Evidence Collected section"
fi

if [[ "${T4_HAS_RATIONALE:-0}" -ge "1" ]]; then
  pass "T4: incident report contains ## Classification Rationale section"
else
  fail "T4: incident report missing ## Classification Rationale section"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T5 — orphan_lock_classified: S02 marker present → no-op skip, no side effects
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: orphan_lock_classified — no-op skip (backward-compat) ==="

T5_SID="T5-COMPAT"
T5_PROJ="$FIXTURE_DIR/t5-project"
T5_LOCKS="$FIXTURE_DIR/t5-locks"
T5_LOGS="$FIXTURE_DIR/t5-logs"
T5_GAAI_PROJ="$FIXTURE_DIR/t5-gaai-project"
T5_YAML="- id: ${T5_SID}
  status: in_progress
  phase_status: not_started
  delivery_pipeline: 3phase"

mkdir -p "$T5_LOCKS" "$T5_LOGS" "$T5_GAAI_PROJ/contexts/artefacts/incidents"
setup_git_repo "$T5_PROJ" "$T5_YAML"
# Place S02 orphan-classified marker
touch "$T5_LOCKS/${T5_SID}.orphan-classified"

T5_BACKLOG="$T5_PROJ/.gaai/project/contexts/backlog/active.backlog.yaml"
T5_HARNESS=$(mktemp /tmp/gaai-t5-harness-XXXXXX.sh)
build_base_harness "$T5_HARNESS" "$T5_PROJ" "$T5_LOCKS" "$T5_LOGS" "$T5_GAAI_PROJ" "$T5_BACKLOG"
cat >> "$T5_HARNESS" <<T5APPEND

source "$CLASSIFIER_LIB"

classify_stuck_story "$T5_SID" "not_started"
T5_RC=\$?

printf 'RC=%s\n' "\$T5_RC"
printf 'REVERT_CALLED=%s\n' "\$REVERT_CALLED"
printf 'NOTIFY_CALLED=%s\n' "\$NOTIFY_CALLED"

T5_INCIDENT=\$(ls -t "${T5_GAAI_PROJ}/contexts/artefacts/incidents/incident-${T5_SID}-"*.md 2>/dev/null | head -1 || true)
printf 'INCIDENT_EXISTS=%s\n' "\$([ -n "\$T5_INCIDENT" ] && [ -f "\$T5_INCIDENT" ] && echo yes || echo no)"
T5APPEND

chmod +x "$T5_HARNESS"
T5_OUT=$(bash "$T5_HARNESS" 2>/dev/null)
rm -f "$T5_HARNESS"

T5_RC=$(echo "$T5_OUT" | grep '^RC=' | cut -d= -f2)
T5_REVERT=$(echo "$T5_OUT" | grep '^REVERT_CALLED=' | cut -d= -f2)
T5_NOTIFY=$(echo "$T5_OUT" | grep '^NOTIFY_CALLED=' | cut -d= -f2)
T5_INC_EXISTS=$(echo "$T5_OUT" | grep '^INCIDENT_EXISTS=' | cut -d= -f2)

if [[ "$T5_RC" == "2" ]]; then
  pass "T5: classify_stuck_story returned 2 (no-op skip)"
else
  fail "T5: expected rc=2, got rc=${T5_RC:-?}"
fi

if [[ "$T5_REVERT" == "0" ]]; then
  pass "T5: _recovery_revert_refined NOT called (no double-handling)"
else
  fail "T5: expected REVERT_CALLED=0, got ${T5_REVERT:-?}"
fi

if [[ "$T5_NOTIFY" == "0" ]]; then
  pass "T5: notify_escalation NOT called"
else
  fail "T5: expected NOTIFY_CALLED=0, got ${T5_NOTIFY:-?}"
fi

if [[ "$T5_INC_EXISTS" == "no" ]]; then
  pass "T5: no incident report written for no-op class"
else
  fail "T5: incident report was unexpectedly written for no-op class"
fi

# ─── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
