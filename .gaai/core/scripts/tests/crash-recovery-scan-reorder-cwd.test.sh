#!/usr/bin/env bash
# crash-recovery-scan-reorder-cwd.test.sh — regression tests for the
# crash-recovery-scan reorder + cwd fix.
#
# Covers three independent defects in crash_recovery_scan/_recovery_revert_refined:
#   AC2  — the is_locked() live-wrapper check now runs BEFORE the drift-defer
#          branch, so a live wrapper is never misreported as "relaunch deferred".
#   AC3/AC5 — the generic drift-commit call now cd's into $PROJECT_DIR before
#          committing, so a dead not_started story's accumulated daemon-home
#          drift is actually committed (and the story actually reverts to
#          refined) instead of being silently no-op'd by whatever directory
#          the daemon process happened to be running from.
#   AC6  — _recovery_revert_refined's retry-counter purge is gated on the
#          death reason, so repeated recovery-death reverts accumulate the
#          retry counter toward MAX_RETRIES instead of resetting to 1 forever.
#
# Usage: bash .gaai/core/scripts/tests/crash-recovery-scan-reorder-cwd.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../delivery-daemon.sh"
DAEMON_SCRIPT_DIR="$(cd "$(dirname "$DAEMON")" && pwd)"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"

FIXTURE_DIR="/tmp/gaai-crash-recovery-reorder-cwd-test-$$"
mkdir -p "$FIXTURE_DIR"
cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── Git repo helper (mirrors crash-recovery.test.sh) ──────────────────────────
setup_git_repo() {
  local project_dir="$1" content="$2"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  # -b main is explicit on purpose: these fixtures push to and read from
  # origin/main, but a bare init otherwise takes the branch name from the
  # host's init.defaultBranch. Developers who set it to main saw this pass
  # while CI runners, which keep git's built-in default, produced a repo with
  # no main ref at all — every fixture push then failed with "couldn't find
  # remote ref main" and the code under test never ran.
  git init --bare -b main "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  mkdir -p "$project_dir/.gaai/project/contexts/backlog"
  printf '%s\n' "$content" > "$project_dir/.gaai/project/contexts/backlog/active.backlog.yaml"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push origin HEAD -q
}

# ═══════════════════════════════════════════════════════════════════════════
# AC2 — is_locked runs before the drift-defer branch: a live wrapper is never
# drift-deferred (would previously log "relaunch deferred to next scan").
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC2: is_locked runs before drift-defer — live wrapper never drift-deferred ==="

L_DIR="$FIXTURE_DIR/live-project"
L_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
L_STORY="TST-RC-LIVE"
L_LOCK_DIR="$FIXTURE_DIR/live-locks"
L_LOG="$FIXTURE_DIR/live-daemon.log"
mkdir -p "$L_LOCK_DIR"
touch "$L_LOG"

L_HEAD_YAML="items:
- id: $L_STORY
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase"
setup_git_repo "$L_DIR" "$L_HEAD_YAML"

# Working-tree phase_status drift AND a live lock file — pre-fix, the ordering
# would still reach the drift-defer branch first and log the misleading
# "relaunch deferred" line even though the wrapper is healthy.
L_WT_YAML="items:
- id: $L_STORY
  status: in_progress
  phase_status: implemented
  delivery_pipeline: 3phase"
printf '%s\n' "$L_WT_YAML" > "$L_DIR/$L_BACKLOG_REL"
echo "12345" > "$L_LOCK_DIR/${L_STORY}.lock"

L_HARNESS=$(mktemp /tmp/rc-reorder-live-harness-XXXXXX.sh)
cat > "$L_HARNESS" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="$L_DIR"
BACKLOG_REL="$L_BACKLOG_REL"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$L_LOCK_DIR"
LOG_DIR="$FIXTURE_DIR/live-logs"
DRIFT_MARKER="\$LOCK_DIR/.drift-detected.audit"
LOG_FILE="$L_LOG"
TARGET_BRANCH="main"
DRY_RUN=false
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

mkdir -p "\$LOG_DIR" "\$LOCK_DIR"

log() {
  local msg="[\$(date '+%H:%M:%S')] \$*"
  echo -e "\$msg" | sed "s/\\\033\[[0-9;]*m//g" >> "\$LOG_FILE"
}

is_locked() { [[ -f "\$LOCK_DIR/\$1.lock" ]]; }
get_retry_count() { echo 0; }
increment_retry() { return 0; }

fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/main:\$BACKLOG_REL" 2>/dev/null \
    || git -C "\$PROJECT_DIR" show "HEAD:\$BACKLOG_REL" 2>/dev/null \
    || cat "\$BACKLOG"
}

_recovery_resolve_worktree() { echo "/nonexistent/\$1-workspace"; }
_recovery_relaunch() { return 0; }
_recovery_set_status() { return 0; }
_recovery_revert_refined() { echo "REVERT_CALLED" >> "$FIXTURE_DIR/live-revert-called"; return 0; }
_commit_accumulated_backlog_drift() { echo "DRIFT_COMMIT_CALLED" >> "$FIXTURE_DIR/live-drift-called"; return 0; }

source "$SCRIPT_DIR/../lib/backlog-yaml.sh" 2>/dev/null || true

eval "\$(awk '
  /^_write_drift_marker\(\)/{p=1; depth=0}
  /^_clear_drift_marker_if_clean\(\)/{p=1; depth=0}
  /^crash_recovery_scan\(\)/{p=1; depth=0}
  p {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == "{") depth++
      if (c == "}") depth--
    }
    if (p && depth == 0 && NR > 1) { p=0 }
  }
' "$DAEMON" 2>/dev/null)"

crash_recovery_scan
HARNESS
chmod +x "$L_HARNESS"
bash "$L_HARNESS" 2>/dev/null
rm -f "$L_HARNESS"

echo "T1: live-wrapper log line present"
if grep -q "live wrapper detected" "$L_LOG" 2>/dev/null; then
  pass "T1: 'live wrapper detected' logged"
else
  fail "T1: 'live wrapper detected' NOT found — log: $(cat "$L_LOG" 2>/dev/null | tr '\n' '|')"
fi

echo "T2: drift-defer log lines absent (is_locked short-circuits before the drift branch)"
if grep -qE "committed accumulated backlog drift|drift commit failed" "$L_LOG" 2>/dev/null; then
  fail "T2: drift-defer log line found despite live wrapper — reorder regression"
else
  pass "T2: no drift-defer log line for a live wrapper"
fi

echo "T3: _commit_accumulated_backlog_drift never invoked for a live wrapper"
if [[ -f "$FIXTURE_DIR/live-drift-called" ]]; then
  fail "T3: drift-commit helper was called despite live wrapper"
else
  pass "T3: drift-commit helper not called"
fi

echo "T4: _recovery_revert_refined never invoked for a live wrapper"
if [[ -f "$FIXTURE_DIR/live-revert-called" ]]; then
  fail "T4: revert-refined was called despite live wrapper"
else
  pass "T4: revert-refined not called"
fi

# ═══════════════════════════════════════════════════════════════════════════
# AC3/AC5 — real-cwd regression: the daemon process cwd is NOT $PROJECT_DIR
# (reproducing the real launch condition) and a dead not_started story has
# accumulated daemon-home-only backlog drift. The scan must actually commit
# that drift (against $PROJECT_DIR, not the caller's actual cwd) AND revert
# the story to refined. A "wrong cwd" second clone — identical to origin, so
# a bare `git diff` run from inside it is clean — reproduces the silent-
# success early-return the pre-fix helper takes (not a hard git error).
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC3/AC5: crash-recovery-scan reorder + cwd fix (real cwd-bug regression) ==="

CWD_STORY="TST-RC-CWD"
CWD_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
CWD_HOME_DIR="$FIXTURE_DIR/cwd-daemon-home"
CWD_WRONG_DIR="$FIXTURE_DIR/cwd-wrong-cwd"
CWD_LOCK_DIR="$FIXTURE_DIR/cwd-locks"
CWD_LOG="$FIXTURE_DIR/cwd-daemon.log"
mkdir -p "$CWD_LOCK_DIR"
touch "$CWD_LOG"

# origin: in_progress, no phase_status field yet (backlog_phase_status → "")
CWD_HEAD_YAML="items:
- id: $CWD_STORY
  status: in_progress
  delivery_pipeline: 3phase"
setup_git_repo "$CWD_HOME_DIR" "$CWD_HEAD_YAML"

# The "wrong cwd" clone — a second, untouched clone of the same remote. It
# matches HEAD exactly, so `git diff --quiet HEAD -- <rel>` run from inside
# it is clean (the silent-success early-return this bug hides behind).
git clone "${CWD_HOME_DIR}_remote.git" "$CWD_WRONG_DIR" -q
git -C "$CWD_WRONG_DIR" config user.email "test@gaai.local"
git -C "$CWD_WRONG_DIR" config user.name "GAAI Test"

# Daemon-home working-tree drift: the wrapper's first local-only write
# (phase_status: not_started), uncommitted — this is the drift the recovery
# scan is supposed to commit for real.
CWD_WT_YAML="items:
- id: $CWD_STORY
  status: in_progress
  phase_status: not_started
  delivery_pipeline: 3phase"
printf '%s\n' "$CWD_WT_YAML" > "$CWD_HOME_DIR/$CWD_BACKLOG_REL"

if git -C "$CWD_HOME_DIR" diff --quiet HEAD -- "$CWD_BACKLOG_REL"; then
  fail "AC5-precondition: expected daemon-home WT diff, found none — test setup broken"
else
  pass "AC5-precondition: daemon-home WT has uncommitted phase_status drift"
fi
if git -C "$CWD_WRONG_DIR" diff --quiet HEAD -- "$CWD_BACKLOG_REL"; then
  pass "AC5-precondition: wrong-cwd clone matches origin exactly (clean diff)"
else
  fail "AC5-precondition: wrong-cwd clone unexpectedly dirty — test setup broken"
fi

# No lock file for this sid (dead wrapper). No .interrupted / .agent-hang.marker
# (rules out graceful-stop and crash-drift-signature branches, isolating the
# generic drift-commit path this story fixes).
CWD_HARNESS=$(mktemp /tmp/rc-reorder-cwd-harness-XXXXXX.sh)
cat > "$CWD_HARNESS" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
# The daemon process's actual OS cwd is the WRONG clone, never \$PROJECT_DIR —
# this is the real launch condition the story's root-cause analysis describes.
cd "$CWD_WRONG_DIR"

PROJECT_DIR="$CWD_HOME_DIR"
BACKLOG_REL="$CWD_BACKLOG_REL"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$CWD_LOCK_DIR"
LOG_DIR="$FIXTURE_DIR/cwd-logs"
DRIFT_MARKER="\$LOCK_DIR/.drift-detected.audit"
REBASE_CONFLICT_MARKER="\$LOCK_DIR/.rebase-conflict.audit"
LOG_FILE="$CWD_LOG"
RETRY_FILE="\$LOCK_DIR/.retry-counts"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
SCRIPT_DIR="$DAEMON_SCRIPT_DIR"
DRY_RUN=false
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

mkdir -p "\$LOG_DIR" "\$LOCK_DIR"

log() {
  local msg="[\$(date '+%H:%M:%S')] \$*"
  echo -e "\$msg" | sed "s/\\\033\[[0-9;]*m//g" >> "\$LOG_FILE"
}

is_locked() { [[ -f "\$LOCK_DIR/\$1.lock" ]]; }
get_retry_count() { echo 0; }
increment_retry() { return 0; }
with_staging_lock() { "\$@"; }
_recovery_resolve_worktree() { echo "/nonexistent/\$1-workspace"; }
_recovery_relaunch() { return 0; }
_recovery_set_status() { return 0; }
notify_escalation_inline() { return 0; }

PLATFORM="\$(uname)"
sed_inplace() {
  if [[ "\$PLATFORM" == "Darwin" ]]; then sed -i '' "\$@"; else sed -i "\$@"; fi
}

# Deterministic no-network gh() stub — shadows any real gh binary (bash
# resolves functions before PATH) so the merged-PR guards always see "no PR".
gh() { return 1; }

fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/main:\$BACKLOG_REL" 2>/dev/null \
    || git -C "\$PROJECT_DIR" show "HEAD:\$BACKLOG_REL" 2>/dev/null \
    || cat "\$BACKLOG"
}

source "$SCRIPT_DIR/../lib/backlog-yaml.sh" 2>/dev/null || true
source "$DAEMON_SCRIPT_DIR/lib/chore-commit.sh"

eval "\$(awk '
  /^_write_drift_marker\(\)/{p=1; depth=0}
  /^_clear_drift_marker_if_clean\(\)/{p=1; depth=0}
  /^_recovery_revert_refined\(\)/{p=1; depth=0}
  /^crash_recovery_scan\(\)/{p=1; depth=0}
  p {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == "{") depth++
      if (c == "}") depth--
    }
    if (p && depth == 0 && NR > 1) { p=0 }
  }
' "$DAEMON" 2>/dev/null)"

crash_recovery_scan
HARNESS
chmod +x "$CWD_HARNESS"
bash "$CWD_HARNESS" 2>/dev/null
rm -f "$CWD_HARNESS"

echo "T5: daemon-home working tree is clean after the scan (drift actually committed)"
if git -C "$CWD_HOME_DIR" diff --quiet HEAD -- "$CWD_BACKLOG_REL" 2>/dev/null; then
  pass "T5: daemon-home WT clean — drift was committed against \$PROJECT_DIR, not the wrong cwd"
else
  fail "T5: daemon-home WT still dirty — drift commit ran against the wrong cwd (pre-fix behavior)"
fi

# T5b pins the cwd fix specifically. _recovery_revert_refined's own chore-commit
# path independently re-sweeps any leftover uncommitted drift as a "pre-mark"
# commit (correctly cd'd, since that path already worked before this story) —
# so T5/T6 alone would still pass even if the scan-level call above silently
# no-op'd against the wrong cwd and left the sweep to that downstream safety
# net. Assert the scan-level commit — subject-tagged "[recovery-scan <sid>]",
# distinct from the downstream "[pre-mark <sid>]" tag — actually landed, so a
# future regression that reintroduces the missing-cd bug fails T5b even though
# T5/T6 would not catch it.
echo "T5b: the scan-level drift commit itself landed (not just the downstream pre-mark sweep)"
# Captured into a variable before grep (not piped directly): under `set -o
# pipefail`, `grep -q` exits as soon as it finds a match, SIGPIPEs the
# upstream `git log`, and pipefail then reports the pipeline's status as
# git's SIGPIPE death — not grep's success — producing a false FAIL here.
CWD_ALL_LOG=$(git -C "$CWD_HOME_DIR" log --oneline --all 2>/dev/null)
if printf '%s\n' "$CWD_ALL_LOG" | grep -qF "[recovery-scan $CWD_STORY]"; then
  pass "T5b: '[recovery-scan $CWD_STORY]' commit found — the scan-level call committed the drift itself"
else
  fail "T5b: no '[recovery-scan $CWD_STORY]' commit found — the scan-level drift-commit call never actually ran against \$PROJECT_DIR (silently masked by the downstream pre-mark sweep)"
fi

echo "T6: story reverted to refined on origin (became re-dispatchable)"
CWD_ORIGIN_STATUS=$(git -C "$CWD_HOME_DIR" show "origin/main:$CWD_BACKLOG_REL" 2>/dev/null \
  | grep -A2 "id: $CWD_STORY" | grep "status:" | head -1 | sed 's/.*status: *//' | tr -d '"\r' || echo "")
if [[ "$CWD_ORIGIN_STATUS" == "refined" ]]; then
  pass "T6: origin status=refined for $CWD_STORY"
else
  fail "T6: origin status='$CWD_ORIGIN_STATUS' (expected refined) — story never self-healed"
fi

echo "T7: log distinguishes the drift-committed outcome from a generic defer"
if grep -q "evaluating phase_status" "$CWD_LOG" 2>/dev/null; then
  pass "T7: 'evaluating phase_status' fallthrough logged (not a blind defer)"
else
  fail "T7: expected 'evaluating phase_status' log line not found — log: $(cat "$CWD_LOG" 2>/dev/null | tr '\n' '|')"
fi

echo "T8: revert log line present (phase_status=not_started path reached)"
if grep -q "revert refined + retry" "$CWD_LOG" 2>/dev/null; then
  pass "T8: not_started revert path reached after drift fallthrough"
else
  fail "T8: not_started revert path never reached — log: $(cat "$CWD_LOG" 2>/dev/null | tr '\n' '|')"
fi

# ═══════════════════════════════════════════════════════════════════════════
# AC6 — retry-counter accumulates across recovery-death reverts instead of
# resetting to 1 on every revert (which produced an invisible infinite
# revert→redispatch→die loop).
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "=== AC6: retry-counter accumulates across death reverts, resets on graceful stop ==="

R_STORY="TST-RC-RETRY"
R_BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
R_DIR="$FIXTURE_DIR/retry-project"
R_LOCK_DIR="$FIXTURE_DIR/retry-locks"
mkdir -p "$R_LOCK_DIR"

R_HEAD_YAML="items:
- id: $R_STORY
  status: in_progress
  phase_status: not_started
  delivery_pipeline: 3phase"
setup_git_repo "$R_DIR" "$R_HEAD_YAML"

run_revert() {
  local reset_phase="$1" reason="$2"
  local h
  h=$(mktemp /tmp/rc-reorder-retry-harness-XXXXXX.sh)
  cat > "$h" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="$R_DIR"
BACKLOG_REL="$R_BACKLOG_REL"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$R_LOCK_DIR"
LOG_FILE="$FIXTURE_DIR/retry-daemon.log"
REBASE_CONFLICT_MARKER="\$LOCK_DIR/.rebase-conflict.audit"
RETRY_FILE="\$LOCK_DIR/.retry-counts"
TARGET_BRANCH="main"
SCHEDULER="$SCHEDULER"
SCRIPT_DIR="$DAEMON_SCRIPT_DIR"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''

with_staging_lock() { "\$@"; }
_recovery_resolve_worktree() { echo "/nonexistent/\$1-workspace"; }

PLATFORM="\$(uname)"
sed_inplace() {
  if [[ "\$PLATFORM" == "Darwin" ]]; then sed -i '' "\$@"; else sed -i "\$@"; fi
}

source "$DAEMON_SCRIPT_DIR/lib/chore-commit.sh"

eval "\$(awk '
  /^_write_drift_marker\(\)/{p=1; depth=0}
  /^_recovery_revert_refined\(\)/{p=1; depth=0}
  /^get_retry_count\(\)/{p=1; depth=0}
  /^increment_retry\(\)/{p=1; depth=0}
  p {
    print
    for (i=1; i<=length(\$0); i++) {
      c = substr(\$0, i, 1)
      if (c == "{") depth++
      if (c == "}") depth--
    }
    if (p && depth == 0 && NR > 1) { p=0 }
  }
' "$DAEMON" 2>/dev/null)"

_recovery_revert_refined "$R_STORY" "$reset_phase" "$reason" || exit \$?
# Mirror the real call sites: increment_retry only follows a death revert
# (not_started/planned "no-progress"|"missing-plan" cases). The graceful
# .interrupted stop path never calls increment_retry.
if [[ "$reason" == "no-progress" || "$reason" == "missing-plan" ]]; then
  increment_retry "$R_STORY"
fi
HARNESS
  chmod +x "$h"
  local rc=0
  bash "$h" 2>/dev/null || rc=$?
  rm -f "$h"
  return $rc
}

read_retry_count() {
  grep "^${R_STORY}=" "$R_LOCK_DIR/.retry-counts" 2>/dev/null | cut -d= -f2 || echo ""
}

# Revert 1: death revert (no-progress) — counter should read 1, not be purged.
run_revert "false" "no-progress"
RC1=$(read_retry_count)
echo "T9: after 1st death revert (no-progress), retry counter = 1"
if [[ "$RC1" == "1" ]]; then
  pass "T9: retry counter = 1"
else
  fail "T9: retry counter = '$RC1' (expected 1)"
fi

# Revert 2: another death revert — counter should accumulate to 2 (not reset).
run_revert "false" "no-progress"
RC2=$(read_retry_count)
echo "T10: after 2nd death revert (no-progress), retry counter = 2 (accumulated, not reset)"
if [[ "$RC2" == "2" ]]; then
  pass "T10: retry counter = 2"
else
  fail "T10: retry counter = '$RC2' (expected 2 — purge-on-every-revert regression)"
fi

# Revert 3: mixed reason (missing-plan) — shares the same counter key, must
# still accumulate (sibling missing-plan revert covered by the same gate).
run_revert "true" "missing-plan"
RC3=$(read_retry_count)
echo "T11: after 3rd death revert (missing-plan, mixed reason), retry counter = 3"
if [[ "$RC3" == "3" ]]; then
  pass "T11: retry counter = 3 (mixed no-progress/missing-plan sequence accumulates)"
else
  fail "T11: retry counter = '$RC3' (expected 3)"
fi

# Revert 4: graceful operator stop — retry counter MUST reset (this is not a
# death; existing "interrupted" reset-to-zero behavior must be preserved).
run_revert "false" "interrupted"
RC4=$(read_retry_count)
echo "T12: after graceful-stop revert (interrupted), retry counter purged (reset)"
if [[ -z "$RC4" ]]; then
  pass "T12: retry counter absent/purged after interrupted revert"
else
  fail "T12: retry counter = '$RC4' (expected purged/absent — interrupted must still reset)"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "═══════════════════════════════════════════"

[[ "$FAIL_COUNT" -eq 0 ]]
