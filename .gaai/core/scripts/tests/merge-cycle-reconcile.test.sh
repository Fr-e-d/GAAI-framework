#!/usr/bin/env bash
# merge-cycle-reconcile.test.sh — regression guard: a merged PR on a reused
# story/<id> branch can complete only the delivery cycle that created it.
#
# Reproduces the false-completion class this guards against: a story is claimed for a new
# delivery cycle (started_at=T1); recovery finds the branch's PR from an
# EARLIER cycle, merged before T1, and would reconcile the story to done even
# though the acceptance criterion that motivated the new cycle was never
# implemented. Fix: `_merged_pr_is_current_cycle()` refuses any merged-PR
# candidate whose GitHub createdAt/mergedAt are not both strictly later than
# the current cycle's started_at, and every reconciliation entry path
# (PR watcher, stale guard, drift/qa_passed/not_started recovery) is routed
# through it before `_reconcile_merged_pr()` may mutate the backlog.
#
# PART 1 covers the ten reject reasons + equality + the current-cycle accept,
# exercised directly against the real extracted gate functions.
# PART 2 proves each of the five reconciliation entry paths refuses the
# reused-branch false completion (old PR created+merged before the new
# cycle began) without mutating the backlog.
# PART 3 proves the happy path still lands atomically with
# completed_at > started_at (AC4), through the real (unstubbed)
# _reconcile_merged_pr.
#
# Usage: bash .gaai/core/scripts/tests/merge-cycle-reconcile.test.sh
set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../delivery-daemon.sh"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"
CHORE_LIB="$SCRIPT_DIR/../lib/chore-commit.sh"

FIXTURE_DIR="/tmp/gaai-merge-cycle-reconcile-test-$$"
mkdir -p "$FIXTURE_DIR"
cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# ── Git repo helper — bare remote + clone on staging, one backlog commit ──────
setup_git_repo() {
  local project_dir="$1" content="$2"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  git -C "$project_dir" checkout -b staging -q 2>/dev/null || git -C "$project_dir" checkout staging -q
  local backlog_dir="$project_dir/.gaai/project/contexts/backlog"
  mkdir -p "$backlog_dir"
  printf '%s\n' "$content" > "$backlog_dir/active.backlog.yaml"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push -u origin staging -q
}

# ── Mock gh helper ─────────────────────────────────────────────────────────────
create_mock_gh() {
  local mock_dir="$1"
  mkdir -p "$mock_dir"
  # No brace default on MOCK_GH_RESPONSE (every caller exports it before
  # invoking): "${VAR:-{}}" has a bash parsing quirk that leaks a stray
  # trailing '}' onto the output when VAR IS set, corrupting the JSON for
  # any consumer (like python3's json.load) that doesn't tolerate trailing
  # data — jq happens to stream the value out before erroring, masking it.
  cat > "$mock_dir/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "${MOCK_GH_RESPONSE}"
exit "${MOCK_GH_EXIT:-0}"
MOCK_EOF
  chmod +x "$mock_dir/gh"
}

# ══════════════════════════════════════════════════════════════════════════════
# PART 1: gate reason-token matrix — direct calls to the real extracted
# _merged_pr_started_at + _merged_pr_is_current_cycle
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== PART 1: gate reason-token matrix ==="

P1_DIR="$FIXTURE_DIR/p1-project"
P1_YAML="- id: TST-VALID
  status: in_progress
  started_at: \"2030-03-10T22:50:32Z\"
- id: TST-MISSING
  status: in_progress
- id: TST-INVALID
  status: in_progress
  started_at: not-a-timestamp
- id: TST-NAIVE-START
  status: in_progress
  started_at: \"2030-03-10T22:50:32\"
- id: TST-DATE-START
  status: in_progress
  started_at: \"2030-03-10\"
- id: TST-OFFSET-START
  status: in_progress
  started_at: \"2030-03-10T22:50:32+01:60\""
setup_git_repo "$P1_DIR" "$P1_YAML"

P1_RUNNER="$FIXTURE_DIR/p1-runner.sh"
cat > "$P1_RUNNER" <<RUNNER
#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="$P1_DIR"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
TARGET_BRANCH="staging"
LOG_FILE="$FIXTURE_DIR/p1.log"
log() { echo "\$*" >> "\$LOG_FILE"; }

eval "\$(awk '
  /^_merged_pr_started_at\(\)/{p=1; depth=0}
  /^_merged_pr_is_current_cycle\(\)/{p=1; depth=0}
  p {
    print
    for (i=1;i<=length(\$0);i++){c=substr(\$0,i,1); if(c=="{")depth++; if(c=="}")depth--}
    if (p && depth==0 && NR>1){p=0}
  }
' "$DAEMON")"

check() {
  local sid="\$1" created="\$2" merged="\$3" expect_reason="\$4" tag="\$5"
  : > "\$LOG_FILE"
  _merged_pr_is_current_cycle "\$sid" "\$created" "\$merged" 1
  local rc=\$?
  local reason=none has_sid=no has_pr=no
  reason=\$(sed -n 's/.*reason=\([^)]*\)).*/\1/p' "\$LOG_FILE" | head -1)
  reason="\${reason:-none}"
  grep -q "\$sid" "\$LOG_FILE" 2>/dev/null && has_sid=yes
  grep -q 'PR #1' "\$LOG_FILE" 2>/dev/null && has_pr=yes
  local guard_lines
  guard_lines=\$(grep -c '\[CYCLE-GUARD\]' "\$LOG_FILE" 2>/dev/null || true)
  echo "RESULT \$tag rc=\$rc lines=\${guard_lines:-0} reason=\$reason expect=\$expect_reason sid=\$has_sid pr=\$has_pr"
}

# reason-token cases (AC1, AC3 precedence order)
check TST-MISSING     "2030-03-10T23:00:00Z"     "2030-03-10T23:30:00Z"     missing_started_at missing_started_at
check TST-INVALID     "2030-03-10T23:00:00Z"     "2030-03-10T23:30:00Z"     invalid_started_at invalid_started_at
check TST-NAIVE-START "2030-03-10T23:00:00Z"     "2030-03-10T23:30:00Z"     invalid_started_at naive_started_at
check TST-DATE-START  "2030-03-10T23:00:00Z"     "2030-03-10T23:30:00Z"     invalid_started_at date_only_started_at
check TST-OFFSET-START "2030-03-10T23:00:00Z"    "2030-03-10T23:30:00Z"     invalid_started_at invalid_offset_started_at
check TST-VALID       ""                         "2030-03-10T23:30:00Z"     missing_pr_created_at missing_pr_created_at
check TST-VALID       "-"                        "2030-03-10T23:30:00Z"     missing_pr_created_at sentinel_missing_pr_created_at
check TST-VALID       "garbage"                  "2030-03-10T23:30:00Z"     invalid_pr_created_at invalid_pr_created_at
check TST-VALID       "2030-03-10T23:00:00"      "2030-03-10T23:30:00Z"     invalid_pr_created_at naive_pr_created_at
check TST-VALID       "20300310T230000+00:00"    "2030-03-10T23:30:00Z"     invalid_pr_created_at basic_pr_created_at
check TST-VALID       "2030-03-10T23:00:00+01:60" "2030-03-10T23:30:00Z"    invalid_pr_created_at invalid_offset_pr_created_at
check TST-VALID       "2030-03-10T23:00:00-00:00" "2030-03-10T23:30:00Z"    invalid_pr_created_at unknown_offset_pr_created_at
check TST-VALID       "2030-03-03T21:00:00Z"     "2030-03-03T23:30:04Z"     pr_before_cycle old_closed
check TST-VALID       "2030-03-03T21:00:00Z"     "2030-03-11T09:00:00Z"     pr_before_cycle old_open_merged_late
check TST-VALID       "2030-03-10T23:50:32+01:00" "2030-03-11T00:00:00Z"    pr_not_after_cycle equal_created_offset
check TST-VALID       "2030-03-10T23:00:00Z"     ""                         missing_merged_at missing_merged_at
check TST-VALID       "2030-03-10T23:00:00Z"     "-"                        missing_merged_at sentinel_missing_merged_at
check TST-VALID       "2030-03-10T23:00:00Z"     "garbage"                   invalid_merged_at invalid_merged_at
check TST-VALID       "2030-03-10T23:00:00Z"     "2030-03-11T08:00:00"      invalid_merged_at naive_merged_at
check TST-VALID       "2030-03-10T23:00:00Z"     "2030-03-11T08:00:00+24:00" invalid_merged_at invalid_offset_merged_at
check TST-VALID       "2030-03-10T23:00:00Z"     "2030-03-11T08:00:00-00:00" invalid_merged_at unknown_offset_merged_at
check TST-VALID       "2030-03-10T23:00:00Z"     "2030-03-10T22:00:00Z"     merge_before_cycle merge_before_cycle
check TST-VALID       "2030-03-10T23:00:00Z"     "2030-03-10T23:50:32+01:00" merge_not_after_cycle equal_merged_offset
check TST-VALID       "2030-03-10T23:10:00.123Z" "2030-03-11T09:00:00+01:00" ok valid_fraction_offset
# Precedence collisions: the first applicable reason must win.
check TST-MISSING     ""                         "garbage"                   missing_started_at precedence_missing_start
check TST-INVALID     ""                         "garbage"                   invalid_started_at precedence_invalid_start
check TST-VALID       ""                         "garbage"                   missing_pr_created_at precedence_missing_created
check TST-VALID       "garbage"                  ""                          invalid_pr_created_at precedence_invalid_created
RUNNER
chmod +x "$P1_RUNNER"
P1_OUT=$(bash "$P1_RUNNER" 2>&1)

while IFS= read -r line; do
  [[ "$line" == RESULT* ]] || continue
  tag=$(printf '%s' "$line" | awk '{print $2}')
  rc=$(printf '%s' "$line" | sed -n 's/.*rc=\([0-9]*\).*/\1/p')
  lines=$(printf '%s' "$line" | sed -n 's/.*lines=\([0-9]*\).*/\1/p')
  reason=$(printf '%s\n' "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^reason=/){sub(/^reason=/,"",$i); print $i; exit}}')
  expect=$(printf '%s\n' "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^expect=/){sub(/^expect=/,"",$i); print $i; exit}}')
  has_sid=$(printf '%s\n' "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^sid=/){sub(/^sid=/,"",$i); print $i; exit}}')
  has_pr=$(printf '%s\n' "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^pr=/){sub(/^pr=/,"",$i); print $i; exit}}')
  case "$expect" in
    ok)
      if [[ "$rc" == "0" && "$lines" == "0" && "$reason" == "none" ]]; then
        pass "gate: $tag → rc=0, no CYCLE-GUARD log line (AC1, AC4)"
      else
        fail "gate: $tag expected rc=0/reason=none/0 log lines, got rc=$rc reason=$reason lines=$lines"
      fi
      ;;
    *)
      if [[ "$rc" == "1" && "$lines" == "1" && "$reason" == "$expect" && "$has_sid" == "yes" && "$has_pr" == "yes" ]]; then
        pass "gate: $tag → exact reason=$expect with Story+PR, one log line (AC1, AC3)"
      else
        fail "gate: $tag expected rc=1/reason=$expect/Story+PR/1 line, got rc=$rc reason=$reason sid=$has_sid pr=$has_pr lines=$lines"
      fi
      ;;
  esac
done <<< "$P1_OUT"

if ! printf '%s\n' "$P1_OUT" | grep -q "^RESULT"; then
  fail "PART 1: runner produced no RESULT lines — $(printf '%s' "$P1_OUT" | tail -5)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# PART 2: every reconciliation entry path refuses a reused-branch old PR
# (createdAt + mergedAt both before the new cycle's started_at — the
# reused-branch shape) without mutating the backlog.
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== PART 2: entry-path refusal on reused-branch old PR ==="

OLD_CREATED="2030-03-03T21:00:00Z"
OLD_MERGED="2030-03-03T23:30:04Z"
NEW_STARTED="2030-03-10T22:50:32Z"
LATE_MERGED="2030-03-11T09:00:00Z"

# --- Path E: PR watcher (watch_pr_merge_status) ---------------------------
E_DIR="$FIXTURE_DIR/e-project"
E_LOCK="$FIXTURE_DIR/e-locks"; mkdir -p "$E_LOCK"
E_LOG="$FIXTURE_DIR/e.log"; touch "$E_LOG"
E_MOCK="$FIXTURE_DIR/e-mock-gh"; create_mock_gh "$E_MOCK"
E_SID="TST-E01"
E_YAML="items:
- id: $E_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/701
  delivery_pipeline: 3phase
  started_at: \"$NEW_STARTED\""
setup_git_repo "$E_DIR" "$E_YAML"
export MOCK_GH_RESPONSE="{\"mergedAt\":\"$OLD_MERGED\",\"state\":\"MERGED\",\"baseRefName\":\"staging\",\"createdAt\":\"$OLD_CREATED\"}"
export MOCK_GH_EXIT=0

E_HARNESS="$FIXTURE_DIR/e-harness.sh"
cat > "$E_HARNESS" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
export PATH="$E_MOCK:\$PATH"
PROJECT_DIR="$E_DIR"
GAAI_PROJECT_DIR="$E_DIR/.gaai/project"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$E_LOCK"
LOG_FILE="$E_LOG"
TARGET_BRANCH="staging"
DRY_RUN=false
SCHEDULER="$SCHEDULER"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log() { echo "\$*" >> "\$LOG_FILE"; }
with_staging_lock() { "\$@"; }
_reconcile_merged_pr() { echo called > "$FIXTURE_DIR/e-reconcile-called"; return 0; }
_run_triage_for_story() { return 0; }
source "$SCRIPT_DIR/../lib/backlog-yaml.sh"
source "$SCRIPT_DIR/../lib/commit-retry-containment.sh"
set +e
eval "\$(awk '
  /^watch_pr_merge_status\(\)/{p=1; depth=0}
  /^_merged_pr_started_at\(\)/{p=1; depth=0}
  /^_merged_pr_is_current_cycle\(\)/{p=1; depth=0}
  p { print
    for (i=1;i<=length(\$0);i++){c=substr(\$0,i,1); if(c=="{")depth++; if(c=="}")depth--}
    if (p && depth==0 && NR>1){p=0}
  }
' "$DAEMON" 2>/dev/null)"
watch_pr_merge_status
HARNESS
chmod +x "$E_HARNESS"
bash "$E_HARNESS" 2>/dev/null

if [[ ! -f "$FIXTURE_DIR/e-reconcile-called" ]]; then
  pass "path E (PR watcher): reused-branch old PR did NOT trigger reconcile"
else
  fail "path E (PR watcher): reconcile was called on a pre-cycle merged PR"
fi
if grep -q '\[CYCLE-GUARD\].*reason=pr_before_cycle' "$E_LOG" 2>/dev/null; then
  pass "path E (PR watcher): CYCLE-GUARD reason=pr_before_cycle logged"
else
  fail "path E (PR watcher): expected CYCLE-GUARD pr_before_cycle log line, got: $(tail -5 "$E_LOG" 2>/dev/null)"
fi
E_STATUS=$(git -C "$E_DIR" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml 2>/dev/null | grep "status:" | head -1 | awk '{print $2}')
if [[ "$E_STATUS" == "in_progress" ]]; then
  pass "path E (PR watcher): origin backlog unchanged (still in_progress)"
else
  fail "path E (PR watcher): expected in_progress, got '$E_STATUS'"
fi

# --- Path A: stale guard (check_stale_in_progress) -------------------------
A_DIR="$FIXTURE_DIR/a-project"
A_LOCK="$FIXTURE_DIR/a-locks"; mkdir -p "$A_LOCK"
A_LOG="$FIXTURE_DIR/a.log"; touch "$A_LOG"
A_MOCK="$FIXTURE_DIR/a-mock-gh"; create_mock_gh "$A_MOCK"
A_SID="TST-A01"
A_YAML="items:
- id: $A_SID
  status: in_progress
  phase_status: planned
  started_at: \"$NEW_STARTED\""
setup_git_repo "$A_DIR" "$A_YAML"
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" \
  git -C "$A_DIR" commit --allow-empty -m "chore($A_SID): in_progress [daemon]" -q
git -C "$A_DIR" push origin HEAD -q
export MOCK_GH_RESPONSE="[{\"number\":701,\"mergedAt\":\"$OLD_MERGED\",\"state\":\"MERGED\",\"createdAt\":\"$OLD_CREATED\"}]"
export MOCK_GH_EXIT=0

A_HARNESS="$FIXTURE_DIR/a-harness.sh"
cat > "$A_HARNESS" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
export PATH="$A_MOCK:\$PATH"
PROJECT_DIR="$A_DIR"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$A_LOCK"
LOG_DIR="$A_LOCK/logs"
LOG_FILE="$A_LOG"
TARGET_BRANCH="staging"
SCHEDULER="$SCHEDULER"
DRY_RUN=false
STALENESS_THRESHOLD=0
SUSPEND_GRACE_UNTIL=0
GAAI_RECONCILE_GRACE_SEC=0
mkdir -p "\$LOG_DIR" "\$LOCK_DIR"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log() { echo "\$*" >> "\$LOG_FILE"; }
is_locked() { return 1; }
with_staging_lock() { "\$@"; }
notify_escalation() { return 0; }
track_for_resolution() { return 0; }
_write_drift_marker() { return 0; }
_reconcile_merged_pr() { echo called > "$FIXTURE_DIR/a-reconcile-called"; return 0; }
fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/staging:\$BACKLOG_REL" 2>/dev/null || cat "\$BACKLOG"
}
source "$SCRIPT_DIR/../lib/backlog-yaml.sh"
source "$SCRIPT_DIR/../lib/commit-retry-containment.sh"
_BACKLOG_YQ_AVAILABLE="no"
set +e
eval "\$(awk '
  /^_merged_pr_started_at\(\)/{p=1; depth=0}
  /^_merged_pr_is_current_cycle\(\)/{p=1; depth=0}
  /^check_stale_in_progress\(\)/{p=1; depth=0}
  p { print
    for (i=1;i<=length(\$0);i++){c=substr(\$0,i,1); if(c=="{")depth++; if(c=="}")depth--}
    if (p && depth==0 && NR>1){p=0}
  }
' "$DAEMON" 2>/dev/null)"
check_stale_in_progress
HARNESS
chmod +x "$A_HARNESS"
bash "$A_HARNESS" > /dev/null 2>&1

if [[ ! -f "$FIXTURE_DIR/a-reconcile-called" ]]; then
  pass "path A (stale guard): reused-branch old PR did NOT trigger reconcile"
else
  fail "path A (stale guard): reconcile was called on a pre-cycle merged PR"
fi
if grep -q '\[CYCLE-GUARD\].*reason=pr_before_cycle' "$A_LOG" 2>/dev/null; then
  pass "path A (stale guard): CYCLE-GUARD reason=pr_before_cycle logged"
else
  fail "path A (stale guard): expected CYCLE-GUARD pr_before_cycle log line, got: $(tail -5 "$A_LOG" 2>/dev/null)"
fi
A_STATUS=$(git -C "$A_DIR" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml 2>/dev/null | grep "status:" | head -1 | awk '{print $2}')
if [[ "$A_STATUS" != "done" ]]; then
  pass "path A (stale guard): origin backlog never reached done ('$A_STATUS' — existing fail-closed recovery may still run per AC3)"
else
  fail "path A (stale guard): origin backlog reached done — false completion"
fi

# Re-run paths E and A with the second false-completion shape: the PR was
# created before the cycle but merged after it began. Reusing the same harness
# ensures the real caller wiring — not only the direct gate — is exercised.
: > "$E_LOG"
rm -f "$FIXTURE_DIR/e-reconcile-called"
rm -f "$E_LOCK/.pr-watcher.last-poll"
export MOCK_GH_RESPONSE="{\"mergedAt\":\"$LATE_MERGED\",\"state\":\"MERGED\",\"baseRefName\":\"staging\",\"createdAt\":\"$OLD_CREATED\"}"
bash "$E_HARNESS" 2>/dev/null
if [[ ! -f "$FIXTURE_DIR/e-reconcile-called" ]] \
   && grep -q '\[CYCLE-GUARD\].*reason=pr_before_cycle' "$E_LOG" \
   && [[ "$(git -C "$E_DIR" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml | grep -m1 'status:' | awk '{print $2}')" == "in_progress" ]]; then
  pass "path E late-merge: createdAt-before-cycle candidate rejected without mutation"
else
  fail "path E late-merge: caller did not preserve current-cycle boundary"
fi

setup_git_repo "$A_DIR" "$A_YAML"
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" \
  git -C "$A_DIR" commit --allow-empty -m "chore($A_SID): in_progress [daemon]" -q
git -C "$A_DIR" push origin HEAD -q
: > "$A_LOG"
rm -f "$FIXTURE_DIR/a-reconcile-called"
export MOCK_GH_RESPONSE="[{\"number\":701,\"mergedAt\":\"$LATE_MERGED\",\"state\":\"MERGED\",\"createdAt\":\"$OLD_CREATED\"}]"
bash "$A_HARNESS" >/dev/null 2>&1
if [[ ! -f "$FIXTURE_DIR/a-reconcile-called" ]] \
   && grep -q '\[CYCLE-GUARD\].*reason=pr_before_cycle' "$A_LOG" \
   && [[ "$(git -C "$A_DIR" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml | grep -m1 'status:' | awk '{print $2}')" != "done" ]]; then
  pass "path A late-merge: createdAt-before-cycle candidate rejected without completion"
else
  fail "path A late-merge: stale guard accepted an earlier-cycle PR"
fi

# --- Paths B/C/D: crash_recovery_scan (drift, qa_passed, not_started) -----
# $5 (local_drift_status): when non-empty, the LOCAL working-tree backlog file
# is overwritten post-clone (uncommitted) with this status, diverging from
# origin — the genuine trigger for site B's "WT advanced past origin" branch
# (crash_recovery_scan compares backlog_status($BACKLOG) against origin's).
run_recovery_scan_case() {
  local label="$1" sid="$2" phase_status_line="$3" extra_yaml="$4" local_drift_status="${5:-}"
  local candidate_created="${6:-$OLD_CREATED}" candidate_merged="${7:-$OLD_MERGED}"
  local local_drift_phase="${8:-}" crash_marker="${9:-}"
  local dir="$FIXTURE_DIR/rs-$label-project"
  local lock="$FIXTURE_DIR/rs-$label-locks"; mkdir -p "$lock"
  local logf="$FIXTURE_DIR/rs-$label.log"; touch "$logf"
  local mockdir="$FIXTURE_DIR/rs-$label-mock-gh"; create_mock_gh "$mockdir"
  local yaml="items:
- id: $sid
  status: in_progress
$phase_status_line
$extra_yaml
  started_at: \"$NEW_STARTED\""
  setup_git_repo "$dir" "$yaml"
  [[ -n "$crash_marker" ]] && touch "$lock/${sid}.${crash_marker}"
  if [[ -n "$local_drift_status" || -n "$local_drift_phase" ]]; then
    local local_phase_status_line="$phase_status_line"
    [[ -n "$local_drift_phase" ]] && local_phase_status_line="  phase_status: $local_drift_phase"
    printf 'items:\n- id: %s\n  status: %s\n%s\n%s\n  started_at: "%s"\n' \
      "$sid" "${local_drift_status:-in_progress}" "$local_phase_status_line" "$extra_yaml" "$NEW_STARTED" \
      > "$dir/.gaai/project/contexts/backlog/active.backlog.yaml"
  fi
  export MOCK_GH_RESPONSE="[{\"number\":701,\"mergedAt\":\"$candidate_merged\",\"state\":\"MERGED\",\"createdAt\":\"$candidate_created\"}]"
  export MOCK_GH_EXIT=0

  local harness="$FIXTURE_DIR/rs-$label-harness.sh"
  cat > "$harness" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
export PATH="$mockdir:\$PATH"
PROJECT_DIR="$dir"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$lock"
LOG_DIR="$lock/logs"
LOG_FILE="$logf"
TARGET_BRANCH="staging"
SCHEDULER="$SCHEDULER"
DRY_RUN=false
mkdir -p "\$LOG_DIR" "\$LOCK_DIR"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log() { echo "\$*" >> "\$LOG_FILE"; }
with_staging_lock() { "\$@"; }
is_locked() { return 1; }
_reconcile_merged_pr() { echo called > "$FIXTURE_DIR/rs-$label-reconcile-called"; return 0; }
_recovery_resolve_worktree() { echo "/nonexistent/\${1}-workspace"; }
_recovery_relaunch() { return 0; }
_recovery_set_status() { return 0; }
_recovery_revert_refined() { echo called > "$FIXTURE_DIR/rs-$label-revert-called"; return 0; }
_recovery_reconcile_crash_drift() {
  echo called > "$FIXTURE_DIR/rs-$label-crash-reconcile-called"
  ( cd "\$PROJECT_DIR" && _commit_accumulated_backlog_drift "\$1" "\$BACKLOG_REL" "\$TARGET_BRANCH" "test-crash-drift" )
}
_write_drift_marker() { echo "\$*" > "$FIXTURE_DIR/rs-$label-drift-marker"; return 0; }
_clear_drift_marker_if_clean() { return 0; }
fetch_and_read_backlog() {
  git -C "\$PROJECT_DIR" show "origin/staging:\$BACKLOG_REL" 2>/dev/null || cat "\$BACKLOG"
}
source "$SCRIPT_DIR/../lib/backlog-yaml.sh"
source "$SCRIPT_DIR/../lib/commit-retry-containment.sh"
source "$CHORE_LIB"
set +e
eval "\$(awk '
  /^_merged_pr_started_at\(\)/{p=1; depth=0}
  /^_merged_pr_is_current_cycle\(\)/{p=1; depth=0}
  /^_recovery_commit_story_phase_drift\(\)/{p=1; depth=0}
  /^crash_recovery_scan\(\)/{p=1; depth=0}
  p { print
    for (i=1;i<=length(\$0);i++){c=substr(\$0,i,1); if(c=="{")depth++; if(c=="}")depth--}
    if (p && depth==0 && NR>1){p=0}
  }
' "$DAEMON" 2>/dev/null)"
crash_recovery_scan
HARNESS
  chmod +x "$harness"
  bash "$harness" > /dev/null 2>&1

  if [[ ! -f "$FIXTURE_DIR/rs-$label-reconcile-called" ]]; then
    pass "path (recovery-scan/$label): reused-branch old PR did NOT trigger reconcile"
  else
    fail "path (recovery-scan/$label): reconcile was called on a pre-cycle merged PR"
  fi
  if grep -q '\[CYCLE-GUARD\].*reason=pr_before_cycle' "$logf" 2>/dev/null; then
    pass "path (recovery-scan/$label): CYCLE-GUARD reason=pr_before_cycle logged"
  else
    fail "path (recovery-scan/$label): expected CYCLE-GUARD pr_before_cycle log line, got: $(tail -5 "$logf" 2>/dev/null)"
  fi
}

# Path B: working-tree drift (local WT status=done, origin still in_progress/
# qa_passed) — rejected PR evidence must quarantine, never commit local done.
run_recovery_scan_case "b-drift" "TST-B01" "  phase_status: qa_passed" "" "done"
if [[ "$(git -C "$FIXTURE_DIR/rs-b-drift-project" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml | grep -m1 'status:' | awk '{print $2}')" == "in_progress" ]]; then
  pass "path B (drift recovery): real drift helper did not push local status:done after rejection"
else
  fail "path B (drift recovery): origin changed after rejected PR evidence"
fi
if [[ -f "$FIXTURE_DIR/rs-b-drift-drift-marker" ]] && grep -q 'unverified-terminal-drift' "$FIXTURE_DIR/rs-b-drift-drift-marker"; then
  pass "path B (drift recovery): unverified terminal drift quarantined with marker"
else
  fail "path B (drift recovery): expected unverified-terminal-drift marker"
fi

# The same bypass can be encoded as status=in_progress/phase_status=done. The
# real drift helper must not publish that phase and let the later case branch
# promote status to done without accepted PR provenance.
run_recovery_scan_case "b-phase-drift" "TST-B03" "  phase_status: qa_passed" "" "" "$OLD_CREATED" "$OLD_MERGED" "done"
B_PHASE_REMOTE=$(git -C "$FIXTURE_DIR/rs-b-phase-drift-project" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml)
if [[ "$(printf '%s\n' "$B_PHASE_REMOTE" | grep -m1 'status:' | awk '{print $2}')" == "in_progress" ]] \
   && [[ "$(printf '%s\n' "$B_PHASE_REMOTE" | grep -m1 'phase_status:' | awk '{print $2}')" == "qa_passed" ]]; then
  pass "path B (phase drift): real helper left origin in_progress/qa_passed after rejection"
else
  fail "path B (phase drift): terminal phase drift reached origin after rejected PR evidence"
fi

# A crash marker must not make phase_status:done authoritative. The terminal
# guard has to run before _recovery_reconcile_crash_drift, not only in the
# ordinary drift branch.
run_recovery_scan_case "b-phase-drift-marker" "TST-B05" "  phase_status: qa_passed" "" "" "$OLD_CREATED" "$OLD_MERGED" "done" "interrupted"
B_MARKER_REMOTE=$(git -C "$FIXTURE_DIR/rs-b-phase-drift-marker-project" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml)
if [[ "$(printf '%s\n' "$B_MARKER_REMOTE" | grep -m1 'status:' | awk '{print $2}')" == "in_progress" ]] \
   && [[ "$(printf '%s\n' "$B_MARKER_REMOTE" | grep -m1 'phase_status:' | awk '{print $2}')" == "qa_passed" ]] \
   && [[ ! -f "$FIXTURE_DIR/rs-b-phase-drift-marker-crash-reconcile-called" ]] \
   && grep -q 'unverified-terminal-drift' "$FIXTURE_DIR/rs-b-phase-drift-marker-drift-marker"; then
  pass "path B crash-marker bypass: terminal phase refused before crash-drift publication"
else
  fail "path B crash-marker bypass: marker authorized terminal drift without current-cycle PR evidence"
fi

# The drift helper stages the complete backlog file. A benign non-terminal
# drift for Story A must not carry Story B's local terminal drift to origin.
X_DIR="$FIXTURE_DIR/cross-story-project"
X_LOCK="$FIXTURE_DIR/cross-story-locks"; mkdir -p "$X_LOCK"
X_LOG="$FIXTURE_DIR/cross-story.log"; touch "$X_LOG"
X_MOCK="$FIXTURE_DIR/cross-story-mock-gh"; create_mock_gh "$X_MOCK"
X_YAML="items:
- id: TST-XA
  status: in_progress
  phase_status: qa_passed
  started_at: \"$NEW_STARTED\"
- id: TST-XB
  status: in_progress
  phase_status: qa_passed
  started_at: \"$NEW_STARTED\""
setup_git_repo "$X_DIR" "$X_YAML"
cat > "$X_DIR/.gaai/project/contexts/backlog/active.backlog.yaml" <<XLOCAL
items:
- id: TST-XA
  status: in_progress
  phase_status: implemented
  started_at: "$NEW_STARTED"
- id: TST-XB
  status: in_progress
  phase_status: qa_passed
  started_at: "$NEW_STARTED"
XLOCAL
mkdir -p "$FIXTURE_DIR/lib"
cp "$SCRIPT_DIR/../lib/backlog-yaml.sh" "$FIXTURE_DIR/lib/backlog-yaml.sh"
X_SCHEDULER="$FIXTURE_DIR/cross-story-scheduler.sh"
cat > "$X_SCHEDULER" <<XSCHED
#!/usr/bin/env bash
# Inject the cross-Story terminal mutation after the isolated helper has read
# its fresh remote snapshot, at the exact point the old implementation staged
# the live shared backlog.
"$SCHEDULER" --set-field TST-XB phase_status done "$X_DIR/.gaai/project/contexts/backlog/active.backlog.yaml" >/dev/null
exec "$SCHEDULER" "\$@"
XSCHED
chmod +x "$X_SCHEDULER"
export MOCK_GH_RESPONSE="[{\"number\":702,\"mergedAt\":\"$OLD_MERGED\",\"state\":\"MERGED\",\"createdAt\":\"$OLD_CREATED\"}]"
export MOCK_GH_EXIT=0
X_HARNESS="$FIXTURE_DIR/cross-story-harness.sh"
cat > "$X_HARNESS" <<XHARNESS
#!/usr/bin/env bash
set -uo pipefail
export PATH="$X_MOCK:\$PATH"
PROJECT_DIR="$X_DIR"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$X_LOCK"
LOG_DIR="$X_LOCK/logs"
LOG_FILE="$X_LOG"
TARGET_BRANCH="staging"
SCHEDULER="$X_SCHEDULER"
DRY_RUN=false
mkdir -p "\$LOG_DIR"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log() { echo "\$*" >> "\$LOG_FILE"; }
with_staging_lock() { "\$@"; }
is_locked() { return 1; }
_reconcile_merged_pr() { return 0; }
_recovery_resolve_worktree() { echo "/nonexistent/\${1}-workspace"; }
_recovery_relaunch() { return 0; }
_recovery_set_status() { return 0; }
_recovery_revert_refined() { return 0; }
_recovery_reconcile_crash_drift() { return 0; }
_write_drift_marker() { echo "\$*" > "$FIXTURE_DIR/cross-story-drift-marker"; return 0; }
_clear_drift_marker_if_clean() { return 0; }
fetch_and_read_backlog() { git -C "\$PROJECT_DIR" show "origin/staging:\$BACKLOG_REL"; }
source "$SCRIPT_DIR/../lib/backlog-yaml.sh"
source "$SCRIPT_DIR/../lib/commit-retry-containment.sh"
source "$CHORE_LIB"
set +e
eval "\$(awk '
  /^_merged_pr_started_at\(\)/{p=1; depth=0}
  /^_merged_pr_is_current_cycle\(\)/{p=1; depth=0}
  /^_recovery_commit_story_phase_drift\(\)/{p=1; depth=0}
  /^crash_recovery_scan\(\)/{p=1; depth=0}
  p { print
    for (i=1;i<=length(\$0);i++){c=substr(\$0,i,1); if(c=="{")depth++; if(c=="}")depth--}
    if (p && depth==0 && NR>1){p=0}
  }
' "$DAEMON")"
crash_recovery_scan --only-sid TST-XA
XHARNESS
chmod +x "$X_HARNESS"
bash "$X_HARNESS" >/dev/null 2>&1
X_REMOTE=$(git -C "$X_DIR" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml)
X_REMOTE_PHASES=$(printf '%s\n' "$X_REMOTE" | awk '/phase_status:/{print $2}' | paste -sd ',' -)
X_LOCAL_PHASES=$(awk '/phase_status:/{print $2}' "$X_DIR/.gaai/project/contexts/backlog/active.backlog.yaml" | paste -sd ',' -)
if [[ "$X_REMOTE_PHASES" == "implemented,qa_passed" ]] \
   && [[ "$X_LOCAL_PHASES" == "implemented,done" ]]; then
  pass "path B cross-Story race: immutable isolated commit excludes concurrent terminal mutation"
else
  fail "path B cross-Story race: concurrent terminal mutation hitchhiked into origin"
fi

# Path C: qa_passed recovery
run_recovery_scan_case "c-qapass" "TST-C01" "  phase_status: qa_passed" ""

# Path D: not_started recovery
run_recovery_scan_case "d-notstarted" "TST-D01" "  phase_status: not_started" ""
if [[ -f "$FIXTURE_DIR/rs-d-notstarted-revert-called" ]]; then
  pass "path D (not_started recovery): gate rejection fell through to existing revert-refined path (AC3)"
else
  fail "path D (not_started recovery): revert-refined fallback was not reached after gate rejection"
fi

# The second false-completion shape: PR created before the cycle but merged
# after it began. Every recovery path must still reject on createdAt.
run_recovery_scan_case "b-drift-late" "TST-B02" "  phase_status: qa_passed" "" "done" "$OLD_CREATED" "$LATE_MERGED"
if [[ "$(git -C "$FIXTURE_DIR/rs-b-drift-late-project" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml | grep -m1 'status:' | awk '{print $2}')" == "in_progress" ]]; then
  pass "path B late-merge: origin stayed in_progress after createdAt rejection"
else
  fail "path B late-merge: origin changed after createdAt rejection"
fi
run_recovery_scan_case "b-phase-drift-late" "TST-B04" "  phase_status: qa_passed" "" "" "$OLD_CREATED" "$LATE_MERGED" "done"
B_PHASE_LATE_REMOTE=$(git -C "$FIXTURE_DIR/rs-b-phase-drift-late-project" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml)
if [[ "$(printf '%s\n' "$B_PHASE_LATE_REMOTE" | grep -m1 'status:' | awk '{print $2}')" == "in_progress" ]] \
   && [[ "$(printf '%s\n' "$B_PHASE_LATE_REMOTE" | grep -m1 'phase_status:' | awk '{print $2}')" == "qa_passed" ]]; then
  pass "path B late-merge (phase drift): origin stayed in_progress/qa_passed"
else
  fail "path B late-merge (phase drift): terminal phase drift reached origin"
fi
run_recovery_scan_case "c-qapass-late" "TST-C02" "  phase_status: qa_passed" "" "" "$OLD_CREATED" "$LATE_MERGED"
run_recovery_scan_case "d-notstarted-late" "TST-D02" "  phase_status: not_started" "" "" "$OLD_CREATED" "$LATE_MERGED"
if [[ -f "$FIXTURE_DIR/rs-d-notstarted-late-revert-called" ]]; then
  pass "path D late-merge: rejected candidate reached revert-refined recovery"
else
  fail "path D late-merge: revert-refined recovery was not reached"
fi

# --- Direct mutation-boundary refusal: real _reconcile_merged_pr, byte-identical origin
mkdir -p "$FIXTURE_DIR/lib"
cp "$SCRIPT_DIR/../lib/backlog-yaml.sh" "$FIXTURE_DIR/lib/backlog-yaml.sh"
R_DIR="$FIXTURE_DIR/direct-reject-project"
R_LOCK="$FIXTURE_DIR/direct-reject-locks"; mkdir -p "$R_LOCK"
R_LOG="$FIXTURE_DIR/direct-reject.log"; touch "$R_LOG"
R_SID="TST-R01"
R_YAML="items:
- id: $R_SID
  status: in_progress
  phase_status: qa_passed
  started_at: \"$NEW_STARTED\""
setup_git_repo "$R_DIR" "$R_YAML"
R_BEFORE_SHA=$(git -C "$R_DIR" rev-parse origin/staging)
R_BEFORE_BLOB=$(git -C "$R_DIR" rev-parse "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml")
R_RUNNER="$FIXTURE_DIR/direct-reject-runner.sh"
cat > "$R_RUNNER" <<RUNNER
#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="$R_DIR"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
LOCK_DIR="$R_LOCK"
LOG_FILE="$R_LOG"
TARGET_BRANCH="staging"
SCHEDULER="$SCHEDULER"
GAAI_WORKTREES_BASE="$FIXTURE_DIR/no-worktrees"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log() { echo "\$*" >> "\$LOG_FILE"; }
with_staging_lock() { "\$@"; }
_run_triage_for_story() { return 0; }
eval "\$(awk '
  /^_merged_pr_started_at\(\)/{p=1; depth=0}
  /^_merged_pr_is_current_cycle\(\)/{p=1; depth=0}
  /^_reconcile_merged_pr\(\)/{p=1; depth=0}
  p { print
    for (i=1;i<=length(\$0);i++){c=substr(\$0,i,1); if(c=="{")depth++; if(c=="}")depth--}
    if (p && depth==0 && NR>1){p=0}
  }
' "$DAEMON")"
_reconcile_merged_pr "$R_SID" "$OLD_MERGED" 701 "$OLD_CREATED"
RUNNER
chmod +x "$R_RUNNER"
bash "$R_RUNNER" >/dev/null 2>&1 || true
R_AFTER_SHA=$(git -C "$R_DIR" rev-parse origin/staging)
R_AFTER_BLOB=$(git -C "$R_DIR" rev-parse "origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml")
if [[ "$R_BEFORE_SHA" == "$R_AFTER_SHA" && "$R_BEFORE_BLOB" == "$R_AFTER_BLOB" ]] \
   && grep -q 'reason=pr_before_cycle' "$R_LOG"; then
  pass "mutation boundary: rejected direct reconcile leaves origin byte-identical"
else
  fail "mutation boundary: rejected direct reconcile changed origin or omitted reason"
fi

# --- Lock-boundary TOCTOU: a re-claim changes started_at before the locked body.
T_DIR="$FIXTURE_DIR/toctou-project"
T_CLAIM="$FIXTURE_DIR/toctou-claim"
T_LOCK="$FIXTURE_DIR/toctou-locks"; mkdir -p "$T_LOCK"
T_LOG="$FIXTURE_DIR/toctou.log"; touch "$T_LOG"
T_SID="TST-T01"
T_YAML="items:
- id: $T_SID
  status: in_progress
  phase_status: qa_passed
  started_at: \"2030-03-10T20:00:00Z\""
setup_git_repo "$T_DIR" "$T_YAML"
git clone "${T_DIR}_remote.git" "$T_CLAIM" -q
git -C "$T_CLAIM" config user.email test@gaai.local
git -C "$T_CLAIM" config user.name "GAAI Test"
git -C "$T_CLAIM" checkout staging -q
T_RUNNER="$FIXTURE_DIR/toctou-runner.sh"
cat > "$T_RUNNER" <<RUNNER
#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="$T_DIR"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
LOCK_DIR="$T_LOCK"
LOG_FILE="$T_LOG"
TARGET_BRANCH="staging"
SCHEDULER="$SCHEDULER"
GAAI_WORKTREES_BASE="$FIXTURE_DIR/no-worktrees"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log() { echo "\$*" >> "\$LOG_FILE"; }
with_staging_lock() {
  "$SCHEDULER" --set-field "$T_SID" started_at "2030-03-11T10:00:00Z" "$T_CLAIM/.gaai/project/contexts/backlog/active.backlog.yaml" >/dev/null
  git -C "$T_CLAIM" add .gaai/project/contexts/backlog/active.backlog.yaml
  git -C "$T_CLAIM" commit -q -m "chore: simulate re-claim"
  git -C "$T_CLAIM" push -q origin staging
  "\$@"
}
_run_triage_for_story() { return 0; }
eval "\$(awk '
  /^_merged_pr_started_at\(\)/{p=1; depth=0}
  /^_merged_pr_is_current_cycle\(\)/{p=1; depth=0}
  /^_reconcile_merged_pr\(\)/{p=1; depth=0}
  p { print
    for (i=1;i<=length(\$0);i++){c=substr(\$0,i,1); if(c=="{")depth++; if(c=="}")depth--}
    if (p && depth==0 && NR>1){p=0}
  }
' "$DAEMON")"
_reconcile_merged_pr "$T_SID" "2030-03-11T09:00:00Z" 702 "2030-03-10T23:00:00Z"
RUNNER
chmod +x "$T_RUNNER"
bash "$T_RUNNER" >/dev/null 2>&1 || true
T_REMOTE=$(git -C "$T_DIR" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml)
if [[ "$(printf '%s\n' "$T_REMOTE" | grep -m1 'status:' | awk '{print $2}')" == "in_progress" ]] \
   && grep -q 'reason=pr_before_cycle' "$T_LOG"; then
  pass "lock boundary: re-claim started_at is reloaded before mutation"
else
  fail "lock boundary: stale provenance verdict crossed a re-claim"
fi

# ══════════════════════════════════════════════════════════════════════════════
# PART 3: AC4 — current-cycle PR still reconciles atomically, completed_at > started_at
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== PART 3: current-cycle PR reconciles (AC4) ==="

P3_DIR="$FIXTURE_DIR/p3-project"
P3_SID="TST-P3"
P3_STARTED="2030-03-10T22:50:32Z"
P3_CREATED="2030-03-10T23:10:00Z"
P3_MERGED="2030-03-11T08:00:00Z"
P3_YAML="items:
- id: $P3_SID
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/900
  delivery_pipeline: 3phase
  started_at: \"$P3_STARTED\""
setup_git_repo "$P3_DIR" "$P3_YAML"
P3_BEFORE_COUNT=$(git -C "$P3_DIR" rev-list --count origin/staging)

P3_LIB_DIR="$FIXTURE_DIR/p3-lib"
mkdir -p "$P3_LIB_DIR/lib"
cp "$CHORE_LIB" "$P3_LIB_DIR/lib/chore-commit.sh"
mkdir -p "$FIXTURE_DIR/lib"
cp "$SCRIPT_DIR/../lib/backlog-yaml.sh" "$FIXTURE_DIR/lib/backlog-yaml.sh"

P3_RUNNER="$FIXTURE_DIR/p3-runner.sh"
cat > "$P3_RUNNER" <<RUNNER
#!/usr/bin/env bash
set -uo pipefail
cd "$P3_LIB_DIR"
PROJECT_DIR="$P3_DIR"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$FIXTURE_DIR/p3-locks"; mkdir -p "\$LOCK_DIR"
TARGET_BRANCH="staging"
SCHEDULER="$SCHEDULER"
GAAI_WORKTREES_BASE="$FIXTURE_DIR/p3-worktrees"
LOG_FILE="$FIXTURE_DIR/p3.log"
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log() { :; }
with_staging_lock() { "\$@"; }
declare -f _run_triage_for_story >/dev/null 2>&1 || _run_triage_for_story() { return 0; }
eval "\$(awk '
  /^_merged_pr_started_at\(\)/{p=1; depth=0}
  /^_merged_pr_is_current_cycle\(\)/{p=1; depth=0}
  /^_reconcile_merged_pr\(\)/{p=1; depth=0}
  p { print
    for (i=1;i<=length(\$0);i++){c=substr(\$0,i,1); if(c=="{")depth++; if(c=="}")depth--}
    if (p && depth==0 && NR>1){p=0}
  }
' "$DAEMON")"
_reconcile_merged_pr "$P3_SID" "$P3_MERGED" "900" "$P3_CREATED"
RUNNER
chmod +x "$P3_RUNNER"
bash "$P3_RUNNER" > /dev/null 2>&1
P3_AFTER_COUNT=$(git -C "$P3_DIR" rev-list --count origin/staging)

P3_BACKLOG=$(git -C "$P3_DIR" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml 2>/dev/null || echo "")
P3_STATUS=$(printf '%s\n' "$P3_BACKLOG" | grep -m1 "status:" | awk '{print $2}')
P3_PHASE=$(printf '%s\n' "$P3_BACKLOG" | grep -m1 "phase_status:" | awk '{print $2}')
P3_COMPLETED=$(printf '%s\n' "$P3_BACKLOG" | grep -m1 "completed_at:" | awk '{print $2}' | tr -d '"')

if [[ "$P3_STATUS" == "done" ]]; then
  pass "PART 3: current-cycle PR reconciled to status:done (AC4)"
else
  fail "PART 3: expected status:done, got '$P3_STATUS' — $(tail -1 "$FIXTURE_DIR/p3.log" 2>/dev/null)"
fi
if [[ "$P3_PHASE" == "done" ]]; then
  pass "PART 3: phase_status reconciled to done (AC4)"
else
  fail "PART 3: expected phase_status:done, got '$P3_PHASE'"
fi
if [[ "$P3_COMPLETED" == "$P3_MERGED" ]]; then
  pass "PART 3: completed_at == mergedAt (AC4)"
else
  fail "PART 3: expected completed_at=$P3_MERGED, got '$P3_COMPLETED'"
fi
if [[ "$P3_AFTER_COUNT" -eq $((P3_BEFORE_COUNT + 1)) ]]; then
  pass "PART 3: all three landed fields were published in one atomic commit"
else
  fail "PART 3: expected one reconcile commit, count moved $P3_BEFORE_COUNT → $P3_AFTER_COUNT"
fi
# completed_at ($P3_MERGED = 2030-03-11T08:00:00Z) > started_at ($P3_STARTED = 2030-03-10T22:50:32Z)
# lexicographic ISO-8601 comparison is valid here since both are same-format UTC instants.
if [[ "$P3_COMPLETED" > "$P3_STARTED" ]]; then
  pass "PART 3: completed_at > started_at (AC4 the core invariant this Story restores)"
else
  fail "PART 3: completed_at ($P3_COMPLETED) not later than started_at ($P3_STARTED)"
fi

# Idempotence: the already-done precheck runs under the lock and must not add
# another commit or partially rewrite the terminal row.
bash "$P3_RUNNER" > /dev/null 2>&1
P3_SECOND_COUNT=$(git -C "$P3_DIR" rev-list --count origin/staging)
if [[ "$P3_SECOND_COUNT" -eq "$P3_AFTER_COUNT" ]]; then
  pass "PART 3: repeated reconcile is idempotent (no second commit)"
else
  fail "PART 3: repeated reconcile created an extra commit"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RESULTS: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

[[ $FAIL_COUNT -eq 0 ]]
