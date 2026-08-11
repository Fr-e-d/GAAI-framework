#!/usr/bin/env bash
# ci-merge-test-gate.test.sh
#
# _run_merge_test_gate (lib/test-gate.sh): gates the MERGE step (post-push,
# post-PR-create) on the GitHub Actions test-gate.yml conclusion for the
# pushed commit's PR, falling back to the existing local differential gate
# (_run_deterministic_test_gate, unmodified) when the CI result cannot be
# observed. Unit-level: calls _run_merge_test_gate directly (not through the
# full handle_commit_phase) — the full-flow interaction with push/PR-create
# is already covered by the four existing handle_commit_phase suites
# (commit-pr-state.test.sh, daemon-state-machine.test.sh,
# governance-files-excluded.test.sh, triage-3phase-hook.test.sh), whose fixtures'
# origin/staging...HEAD diff is
# confined to .gaai/** (out of the CI workflow's workers/**/packages/**
# path scope) and so take the T1-style immediate-fallback branch.
#
# T1 (out-of-scope diff → immediate local fallback, AC4): diff confined to
#     .gaai/** — zero gh calls, scope pre-check short-circuits before any
#     network call.
# T2 (in-scope + CI pass, AC1): the exact-SHA Test Gate workflow run is
#     completed/success — CI path used, not fallback.
# T3 (in-scope + CI fail, AC3): the exact-SHA workflow run completes failure — same
#     terminal shape as the local gate's own new-failure path
#     (phase_status=failed, notify_escalation_inline, TEST_GATE_BLOCKED).
# T4 (in-scope + CI timeout → local fallback, AC2+AC4): no workflow run
#     becomes decisive — bounded wait resolves promptly (asserted via
#     wall-clock), falls back to local gate.
# T5 (in-scope + repeated gh API error → local fallback, AC4): gh api
#     fails/produces malformed output on every poll — 3 consecutive bad
#     polls trip the api_error fallback (distinct reason from T4's timeout).
# T6 (dynamic-job race regression): an in-progress workflow observation followed
#     by completed/failure must block; the first partial observation cannot pass.
# T7 (head moved): a successful run for the pushed SHA cannot authorize a PR
#     whose current head changed before the verdict was consumed.
# T8 (invalid/slow settings): poll_interval=0 is defaulted safely and a hung API
#     call is killed inside the real wall-clock deadline — no busy/infinite wait.
# T9 (second-call timeout): a completed run followed by a hung PR-head lookup
#     remains bounded and falls back safely instead of authorizing the merge.
# T10 (failure precedence): a known exact-SHA failure blocks even when PR-head
#     lookup is unavailable; it can never be downgraded to local fallback.
# T11/T12 (cancellation): same-head cancellation is non-decisive and falls back
#     on timeout, while cancellation caused by a superseding head blocks as moved.
# T13 (materialize sub-budget + default, AC1+AC5+AC6): GAAI_CI_TEST_GATE_TIMEOUT_SEC
#     left unset (exercises the 2700s default) with a permanently-"missing" run —
#     the much shorter materialize sub-budget fires first, returning
#     "unavailable:no_run" well inside it rather than waiting out the full budget.
# T14 (timeout classification, AC3): a run observed in_progress on every poll —
#     materialize sub-budget is satisfied immediately, the full (short, pinned)
#     budget then expires and reports "unavailable:timeout" with the
#     still-in-progress detail, distinct from T13's no_run detail.
#
# Run: bash .gaai/core/scripts/tests/ci-merge-test-gate.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BACKLOG_FILE="/tmp/gaai-ci-merge-test-backlog.yaml"
SCHEDULER="$(which true)"
export PROJECT_DIR BACKLOG_FILE SCHEDULER

# Source daemon-dispatch.sh — pulls in the modified lib/test-gate.sh
# transitively (same convention as test-gate.test.sh).
source "$SCRIPT_DIR/../daemon-dispatch.sh" 2>/dev/null || true

log() { :; }
CYAN=""; YELLOW=""; NC=""

# ── Fixture sandbox ─────────────────────────────────────────────────────────
SANDBOX="$(mktemp -d /tmp/gaai-ci-merge-test-XXXXXX)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

SCHEDULER_CALLS_LOG="$SANDBOX/scheduler-calls.log"
NOTIFY_CALLS_LOG="$SANDBOX/notify-calls.log"
GH_CALL_LOG="$SANDBOX/gh-calls.log"
GH_API_CALL_COUNT_FILE="$SANDBOX/gh-api-call-count"
GH_RUN_LINES_FILE="$SANDBOX/gh-run-lines"
: > "$SCHEDULER_CALLS_LOG"
: > "$NOTIFY_CALLS_LOG"
: > "$GH_CALL_LOG"
printf '0\n' > "$GH_API_CALL_COUNT_FILE"
: > "$GH_RUN_LINES_FILE"
export GH_CALL_LOG GH_API_CALL_COUNT_FILE GH_RUN_LINES_FILE

STUB_BIN="$SANDBOX/bin"
mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/scheduler-stub.sh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$SCHEDULER_CALLS_LOG"
exit 0
EOF
chmod +x "$STUB_BIN/scheduler-stub.sh"
SCHEDULER="$STUB_BIN/scheduler-stub.sh"

notify_escalation_inline() {
  echo "$1|$2|$3" >> "$NOTIFY_CALLS_LOG"
  return 0
}

# ── gh stub ──────────────────────────────────────────────────────────────────
# `gh api` returns one pre-rendered workflow-run observation per invocation;
# `gh pr view` returns the current PR head used by the post-completion guard.
# Files provide cross-process state because the production helper deliberately
# runs each CLI call in a watchdog-controlled background process.
cat > "$STUB_BIN/gh" <<'GHEOF'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_CALL_LOG"
if [[ "${1:-}" == "api" ]]; then
  [[ -n "${GH_API_HANG_SEC:-}" ]] && exec sleep "$GH_API_HANG_SEC"
  if [[ -n "${GH_API_EXIT:-}" ]]; then
    exit "$GH_API_EXIT"
  fi
  count=$(cat "$GH_API_CALL_COUNT_FILE" 2>/dev/null || echo 0)
  count=$(( count + 1 ))
  printf '%s\n' "$count" > "$GH_API_CALL_COUNT_FILE"
  line=$(sed -n "${count}p" "$GH_RUN_LINES_FILE" 2>/dev/null)
  [[ -z "$line" ]] && line=$(tail -1 "$GH_RUN_LINES_FILE" 2>/dev/null)
  printf '%s\n' "${line:-missing}"
  exit 0
fi
if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  [[ -n "${GH_PR_VIEW_HANG_SEC:-}" ]] && exec sleep "$GH_PR_VIEW_HANG_SEC"
  printf '%s\n' "${GH_PR_HEAD_SHA:-missing}"
  exit 0
fi
exit 0
GHEOF
chmod +x "$STUB_BIN/gh"
PATH="$STUB_BIN:$PATH"

set_gh_run_lines() {
  : > "$GH_RUN_LINES_FILE"
  local line
  for line in "$@"; do
    printf '%s\n' "$line" >> "$GH_RUN_LINES_FILE"
  done
  printf '0\n' > "$GH_API_CALL_COUNT_FILE"
}

TARGET_BRANCH="staging"
export TARGET_BRANCH

# setup_repo <tag> <touch_path> — baseline commit on staging (pushed +
# fetched), then a story commit on story/<tag> touching exactly
# <touch_path>. No package.json anywhere in the fixture: the local gate
# always resolves PASS via its own "diff touches no known test-mapped source
# root" short-circuit — this file exercises the NEW scope/poll/orchestration
# logic, not the local gate's test-running mechanics (already covered by
# test-gate.test.sh's T1-T3).
setup_repo() {
  local tag="$1" touch_path="$2"
  local remote="$SANDBOX/${tag}-remote.git"
  local repo="$SANDBOX/${tag}-repo"

  git init --quiet --bare "$remote"
  git init --quiet "$repo"
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  git -C "$repo" checkout -q -b staging

  echo baseline > "$repo/baseline.txt"
  git -C "$repo" add -A && git -C "$repo" commit -q -m baseline
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -q origin staging
  git -C "$repo" fetch -q origin staging

  git -C "$repo" checkout -q -b "story/${tag}"
  mkdir -p "$(dirname "${repo}/${touch_path}")"
  echo touched > "${repo}/${touch_path}"
  git -C "$repo" add -A && git -C "$repo" commit -q -m "story ${tag}"

  echo "$repo"
}

PR_URL="https://github.com/test/repo/pull/1"

echo ""
echo "=== ci-merge-test-gate: CI-delegated merge gate ==="
echo ""

# ── T1: out-of-scope diff → immediate local fallback (AC4) ──────────────────
echo "--- T1: out-of-scope diff (.gaai/**) ---"
REPO_T1="$(setup_repo T1 ".gaai/some-note.md")"
HEAD_T1=$(git -C "$REPO_T1" rev-parse HEAD)
QA_T1="$SANDBOX/T1.qa-report.md"
OUT_T1="$SANDBOX/T1.out.log"
: > "$GH_CALL_LOG"
_run_merge_test_gate "T1" "$REPO_T1" "$QA_T1" "$PR_URL" "$HEAD_T1" > "$OUT_T1" 2>&1
RC_T1=$?

[[ "$RC_T1" -eq 0 ]] && pass "T1: returns 0 (local fallback PASS)" || fail "T1: expected rc=0, got ${RC_T1}"
[[ ! -s "$GH_CALL_LOG" ]] \
  && pass "T1: zero gh calls (scope pre-check short-circuited)" \
  || fail "T1: unexpected gh call(s): $(cat "$GH_CALL_LOG")"
grep -q "TEST_GATE_CI_UNAVAILABLE_FALLBACK" "$OUT_T1" \
  && pass "T1: fallback marker present (AC5)" \
  || fail "T1: fallback marker missing from output"
grep -q "path_scope_excluded" "$OUT_T1" \
  && pass "T1: fallback reason=path_scope_excluded" \
  || fail "T1: expected reason=path_scope_excluded in output"

# ── T2: in-scope + CI pass (AC1) ─────────────────────────────────────────────
echo "--- T2: in-scope diff, CI pass ---"
REPO_T2="$(setup_repo T2 "workers/fake-pkg/file.txt")"
HEAD_T2=$(git -C "$REPO_T2" rev-parse HEAD)
QA_T2="$SANDBOX/T2.qa-report.md"
OUT_T2="$SANDBOX/T2.out.log"
: > "$GH_CALL_LOG"
set_gh_run_lines "completed"$'\t'"success"$'\t'"$HEAD_T2"
export GH_PR_HEAD_SHA="$HEAD_T2"
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=5
unset GH_API_EXIT GH_API_HANG_SEC
_run_merge_test_gate "T2" "$REPO_T2" "$QA_T2" "$PR_URL" "$HEAD_T2" > "$OUT_T2" 2>&1
RC_T2=$?
unset GAAI_CI_TEST_GATE_TIMEOUT_SEC

[[ "$RC_T2" -eq 0 ]] && pass "T2: returns 0 (CI pass)" || fail "T2: expected rc=0, got ${RC_T2}"
grep -q "gh api.*head_sha=${HEAD_T2}" "$GH_CALL_LOG" \
  && pass "T2: workflow-run API was pinned to the pushed SHA" \
  || fail "T2: exact-SHA workflow-run API call missing"
grep -q "starting differential test gate" "$OUT_T2" \
  && fail "T2: local gate ran — CI path should have been decisive, not fallback" \
  || pass "T2: local gate did NOT run (CI path used)"
grep -q "^- Verdict: PASS$" "$QA_T2" \
  && pass "T2: qa-report has PASS verdict" \
  || fail "T2: qa-report missing PASS verdict"
grep -q "CI:${PR_URL}@${HEAD_T2}" "$QA_T2" \
  && pass "T2: qa-report references the PR URL and exact SHA" \
  || fail "T2: qa-report does not reference the exact CI identity"

# ── T3: in-scope + CI fail (AC3) ─────────────────────────────────────────────
echo "--- T3: in-scope diff, CI fail ---"
REPO_T3="$(setup_repo T3 "workers/fake-pkg/file.txt")"
HEAD_T3=$(git -C "$REPO_T3" rev-parse HEAD)
QA_T3="$SANDBOX/T3.qa-report.md"
OUT_T3="$SANDBOX/T3.out.log"
: > "$GH_CALL_LOG"
: > "$SCHEDULER_CALLS_LOG"
: > "$NOTIFY_CALLS_LOG"
set_gh_run_lines "completed"$'\t'"failure"$'\t'"$HEAD_T3"
export GH_PR_HEAD_SHA="$HEAD_T3"
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=5
unset GH_API_EXIT GH_API_HANG_SEC
_run_merge_test_gate "T3" "$REPO_T3" "$QA_T3" "$PR_URL" "$HEAD_T3" > "$OUT_T3" 2>&1
RC_T3=$?
unset GAAI_CI_TEST_GATE_TIMEOUT_SEC

[[ "$RC_T3" -eq 1 ]] && pass "T3: returns 1 (CI fail blocks)" || fail "T3: expected rc=1, got ${RC_T3}"
grep -q -- "--set-phase-status T3 failed" "$SCHEDULER_CALLS_LOG" \
  && pass "T3: scheduler --set-phase-status T3 failed recorded" \
  || fail "T3: scheduler was not told to set phase_status failed"
grep -q "test_gate_ci_failure" "$NOTIFY_CALLS_LOG" \
  && pass "T3: notify_escalation_inline recorded reason=test_gate_ci_failure" \
  || fail "T3: notify_escalation_inline reason missing"
grep -q "\[class=TEST_GATE_BLOCKED\]" "$OUT_T3" \
  && pass "T3: TEST_GATE_BLOCKED class marker present (AC3 parity)" \
  || fail "T3: TEST_GATE_BLOCKED class marker missing"

# ── T4: in-scope + CI timeout → local fallback (AC2 + AC4) ──────────────────
echo "--- T4: in-scope diff, CI never decisive (timeout) ---"
REPO_T4="$(setup_repo T4 "workers/fake-pkg/file.txt")"
HEAD_T4=$(git -C "$REPO_T4" rev-parse HEAD)
QA_T4="$SANDBOX/T4.qa-report.md"
OUT_T4="$SANDBOX/T4.out.log"
: > "$GH_CALL_LOG"
set_gh_run_lines "missing"
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=2
export GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC=1
export GAAI_CI_TEST_GATE_API_TIMEOUT_SEC=1
unset GH_API_EXIT GH_API_HANG_SEC

_t4_start=$(date +%s)
_run_merge_test_gate "T4" "$REPO_T4" "$QA_T4" "$PR_URL" "$HEAD_T4" > "$OUT_T4" 2>&1
RC_T4=$?
_t4_end=$(date +%s)
_t4_elapsed=$(( _t4_end - _t4_start ))

[[ "$RC_T4" -eq 0 ]] && pass "T4: returns 0 (local fallback PASS, not a hang/timeout-124)" || fail "T4: expected rc=0, got ${RC_T4} (elapsed=${_t4_elapsed}s)"
[[ "$_t4_elapsed" -lt 10 ]] \
  && pass "T4: resolved within bound (${_t4_elapsed}s < 10s) — frees the slot promptly" \
  || fail "T4: took ${_t4_elapsed}s — did not resolve promptly"
grep -q "TEST_GATE_CI_UNAVAILABLE_FALLBACK" "$OUT_T4" \
  && pass "T4: fallback marker present (AC5)" \
  || fail "T4: fallback marker missing from output"
grep -q "unavailable (timeout)" "$OUT_T4" \
  && pass "T4: fallback reason=timeout" \
  || fail "T4: expected reason=timeout in output"

unset GAAI_CI_TEST_GATE_TIMEOUT_SEC GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC GAAI_CI_TEST_GATE_API_TIMEOUT_SEC

# ── T5: in-scope + repeated gh API error → local fallback (AC4) ─────────────
echo "--- T5: in-scope diff, gh api fails repeatedly ---"
REPO_T5="$(setup_repo T5 "workers/fake-pkg/file.txt")"
HEAD_T5=$(git -C "$REPO_T5" rev-parse HEAD)
QA_T5="$SANDBOX/T5.qa-report.md"
OUT_T5="$SANDBOX/T5.out.log"
: > "$GH_CALL_LOG"
set_gh_run_lines "missing"
export GH_API_EXIT=1
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=10
export GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC=1
export GAAI_CI_TEST_GATE_API_TIMEOUT_SEC=1

_t5_start=$(date +%s)
_run_merge_test_gate "T5" "$REPO_T5" "$QA_T5" "$PR_URL" "$HEAD_T5" > "$OUT_T5" 2>&1
RC_T5=$?
_t5_end=$(date +%s)
_t5_elapsed=$(( _t5_end - _t5_start ))

[[ "$RC_T5" -eq 0 ]] && pass "T5: returns 0 (local fallback PASS)" || fail "T5: expected rc=0, got ${RC_T5} (elapsed=${_t5_elapsed}s)"
[[ "$_t5_elapsed" -lt 10 ]] \
  && pass "T5: resolved before the timeout bound (${_t5_elapsed}s, api-error streak trips first)" \
  || fail "T5: took ${_t5_elapsed}s — api-error streak did not trip before timeout"
grep -q "unavailable (api_error)" "$OUT_T5" \
  && pass "T5: fallback reason=api_error (distinct from T4's timeout)" \
  || fail "T5: expected reason=api_error in output"

unset GH_API_EXIT GAAI_CI_TEST_GATE_TIMEOUT_SEC GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC GAAI_CI_TEST_GATE_API_TIMEOUT_SEC

# ── T6: dynamic matrix materialisation race cannot pass early ───────────────
echo "--- T6: in-progress workflow followed by completed failure ---"
REPO_T6="$(setup_repo T6 "workers/fake-pkg/file.txt")"
HEAD_T6=$(git -C "$REPO_T6" rev-parse HEAD)
QA_T6="$SANDBOX/T6.qa-report.md"
OUT_T6="$SANDBOX/T6.out.log"
: > "$GH_CALL_LOG"
: > "$SCHEDULER_CALLS_LOG"
set_gh_run_lines \
  "in_progress"$'\t'"pending"$'\t'"$HEAD_T6" \
  "completed"$'\t'"failure"$'\t'"$HEAD_T6"
export GH_PR_HEAD_SHA="$HEAD_T6"
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=5
export GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC=1
export GAAI_CI_TEST_GATE_API_TIMEOUT_SEC=1
unset GH_API_EXIT GH_API_HANG_SEC

_run_merge_test_gate "T6" "$REPO_T6" "$QA_T6" "$PR_URL" "$HEAD_T6" > "$OUT_T6" 2>&1
RC_T6=$?
T6_API_CALLS=$(cat "$GH_API_CALL_COUNT_FILE")

[[ "$RC_T6" -eq 1 ]] \
  && pass "T6: completed failure blocks after the in-progress observation" \
  || fail "T6: expected rc=1, got ${RC_T6}"
[[ "$T6_API_CALLS" -ge 2 ]] \
  && pass "T6: poll waited for a completed aggregate workflow verdict" \
  || fail "T6: returned after only ${T6_API_CALLS} workflow observation(s)"
grep -q "starting differential test gate" "$OUT_T6" \
  && fail "T6: local gate ran despite a decisive completed CI failure" \
  || pass "T6: decisive CI failure did not use local fallback"
grep -q -- "--set-phase-status T6 failed" "$SCHEDULER_CALLS_LOG" \
  && pass "T6: scheduler recorded the blocked verdict" \
  || fail "T6: scheduler failure transition missing"

unset GAAI_CI_TEST_GATE_TIMEOUT_SEC GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC GAAI_CI_TEST_GATE_API_TIMEOUT_SEC

# ── T7: successful old-SHA run cannot authorize a moved PR head ─────────────
echo "--- T7: PR head moves after the tested push ---"
REPO_T7="$(setup_repo T7 "workers/fake-pkg/file.txt")"
HEAD_T7=$(git -C "$REPO_T7" rev-parse HEAD)
QA_T7="$SANDBOX/T7.qa-report.md"
OUT_T7="$SANDBOX/T7.out.log"
: > "$SCHEDULER_CALLS_LOG"
: > "$NOTIFY_CALLS_LOG"
set_gh_run_lines "completed"$'\t'"success"$'\t'"$HEAD_T7"
export GH_PR_HEAD_SHA="$(printf '%040d' 1)"
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=5
unset GH_API_EXIT GH_API_HANG_SEC

_run_merge_test_gate "T7" "$REPO_T7" "$QA_T7" "$PR_URL" "$HEAD_T7" > "$OUT_T7" 2>&1
RC_T7=$?
unset GAAI_CI_TEST_GATE_TIMEOUT_SEC

[[ "$RC_T7" -eq 1 ]] && pass "T7: moved PR head blocks" || fail "T7: expected rc=1, got ${RC_T7}"
grep -q "test_gate_head_moved" "$NOTIFY_CALLS_LOG" \
  && pass "T7: moved-head escalation reason recorded" \
  || fail "T7: moved-head escalation reason missing"
grep -q "\[class=TEST_GATE_BLOCKED\]" "$OUT_T7" \
  && pass "T7: TEST_GATE_BLOCKED marker present" \
  || fail "T7: TEST_GATE_BLOCKED marker missing"
grep -q "PR head moved" "$QA_T7" \
  && pass "T7: QA audit trail records the moved head" \
  || fail "T7: QA audit trail missing moved-head reason"

# ── T8: invalid interval + hung API remain wall-clock bounded ───────────────
echo "--- T8: invalid poll interval and hung API call ---"
REPO_T8="$(setup_repo T8 "workers/fake-pkg/file.txt")"
HEAD_T8=$(git -C "$REPO_T8" rev-parse HEAD)
QA_T8="$SANDBOX/T8.qa-report.md"
OUT_T8="$SANDBOX/T8.out.log"
set_gh_run_lines "missing"
export GH_API_HANG_SEC=30
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=3
export GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC=0
export GAAI_CI_TEST_GATE_API_TIMEOUT_SEC=1
unset GH_API_EXIT

_t8_start=$(date +%s)
_run_merge_test_gate "T8" "$REPO_T8" "$QA_T8" "$PR_URL" "$HEAD_T8" > "$OUT_T8" 2>&1
RC_T8=$?
_t8_end=$(date +%s)
_t8_elapsed=$(( _t8_end - _t8_start ))

[[ "$RC_T8" -eq 0 ]] \
  && pass "T8: bounded timeout falls back to the local PASS path" \
  || fail "T8: expected rc=0, got ${RC_T8}"
[[ "$_t8_elapsed" -lt 8 ]] \
  && pass "T8: hung API call stayed inside the wall-clock bound (${_t8_elapsed}s)" \
  || fail "T8: hung API call exceeded the bound (${_t8_elapsed}s)"
grep -q "invalid GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC='0'" "$OUT_T8" \
  && pass "T8: zero poll interval was rejected and defaulted" \
  || fail "T8: invalid poll interval warning missing"
grep -q "TEST_GATE_CI_UNAVAILABLE_FALLBACK" "$OUT_T8" \
  && pass "T8: timeout still uses the fail-safe fallback marker" \
  || fail "T8: fail-safe fallback marker missing"

unset GH_API_HANG_SEC GH_PR_HEAD_SHA GAAI_CI_TEST_GATE_TIMEOUT_SEC \
  GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC GAAI_CI_TEST_GATE_API_TIMEOUT_SEC

# ── T9: PR-head lookup also obeys the shared wall-clock bound ───────────────
echo "--- T9: hung PR-head lookup ---"
REPO_T9="$(setup_repo T9 "workers/fake-pkg/file.txt")"
HEAD_T9=$(git -C "$REPO_T9" rev-parse HEAD)
QA_T9="$SANDBOX/T9.qa-report.md"
OUT_T9="$SANDBOX/T9.out.log"
set_gh_run_lines "completed"$'\t'"success"$'\t'"$HEAD_T9"
export GH_PR_VIEW_HANG_SEC=30
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=3
export GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC=1
export GAAI_CI_TEST_GATE_API_TIMEOUT_SEC=1
unset GH_API_EXIT GH_API_HANG_SEC

_t9_start=$(date +%s)
_run_merge_test_gate "T9" "$REPO_T9" "$QA_T9" "$PR_URL" "$HEAD_T9" > "$OUT_T9" 2>&1
RC_T9=$?
_t9_end=$(date +%s)
_t9_elapsed=$(( _t9_end - _t9_start ))

[[ "$RC_T9" -eq 0 ]] \
  && pass "T9: unavailable PR-head lookup falls back to the local PASS path" \
  || fail "T9: expected rc=0, got ${RC_T9}"
[[ "$_t9_elapsed" -lt 6 ]] \
  && pass "T9: PR-head lookup stayed inside the wall-clock bound (${_t9_elapsed}s)" \
  || fail "T9: PR-head lookup exceeded the bound (${_t9_elapsed}s)"
grep -q "TEST_GATE_CI_UNAVAILABLE_FALLBACK" "$OUT_T9" \
  && pass "T9: unavailable head verification uses the fail-safe fallback" \
  || fail "T9: fail-safe fallback marker missing"

unset GH_PR_VIEW_HANG_SEC GAAI_CI_TEST_GATE_TIMEOUT_SEC \
  GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC GAAI_CI_TEST_GATE_API_TIMEOUT_SEC

# ── T10: decisive CI failure does not depend on PR-head availability ────────
echo "--- T10: CI failure with unavailable PR-head lookup ---"
REPO_T10="$(setup_repo T10 "workers/fake-pkg/file.txt")"
HEAD_T10=$(git -C "$REPO_T10" rev-parse HEAD)
QA_T10="$SANDBOX/T10.qa-report.md"
OUT_T10="$SANDBOX/T10.out.log"
: > "$GH_CALL_LOG"
: > "$SCHEDULER_CALLS_LOG"
set_gh_run_lines "completed"$'\t'"failure"$'\t'"$HEAD_T10"
export GH_PR_VIEW_HANG_SEC=30
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=5
export GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC=1
export GAAI_CI_TEST_GATE_API_TIMEOUT_SEC=1

_run_merge_test_gate "T10" "$REPO_T10" "$QA_T10" "$PR_URL" "$HEAD_T10" > "$OUT_T10" 2>&1
RC_T10=$?

[[ "$RC_T10" -eq 1 ]] \
  && pass "T10: exact-SHA CI failure remains blocking" \
  || fail "T10: expected rc=1, got ${RC_T10}"
grep -q "gh pr view" "$GH_CALL_LOG" \
  && fail "T10: failure verdict unnecessarily depended on PR-head lookup" \
  || pass "T10: failure verdict did not call PR-head lookup"
grep -q "starting differential test gate" "$OUT_T10" \
  && fail "T10: known failure was downgraded to local fallback" \
  || pass "T10: known failure never entered local fallback"

unset GH_PR_VIEW_HANG_SEC GAAI_CI_TEST_GATE_TIMEOUT_SEC \
  GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC GAAI_CI_TEST_GATE_API_TIMEOUT_SEC

# ── T11: same-head cancellation remains non-decisive ───────────────────────
echo "--- T11: same-head cancelled run ---"
REPO_T11="$(setup_repo T11 "workers/fake-pkg/file.txt")"
HEAD_T11=$(git -C "$REPO_T11" rev-parse HEAD)
QA_T11="$SANDBOX/T11.qa-report.md"
OUT_T11="$SANDBOX/T11.out.log"
set_gh_run_lines "completed"$'\t'"cancelled"$'\t'"$HEAD_T11"
export GH_PR_HEAD_SHA="$HEAD_T11"
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=2
export GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC=1
export GAAI_CI_TEST_GATE_API_TIMEOUT_SEC=1

_run_merge_test_gate "T11" "$REPO_T11" "$QA_T11" "$PR_URL" "$HEAD_T11" > "$OUT_T11" 2>&1
RC_T11=$?

[[ "$RC_T11" -eq 0 ]] \
  && pass "T11: same-head cancellation uses bounded local fallback" \
  || fail "T11: expected rc=0, got ${RC_T11}"
grep -q "unavailable (timeout)" "$OUT_T11" \
  && pass "T11: cancellation stayed non-decisive until timeout" \
  || fail "T11: cancellation was misclassified as a failure"

unset GAAI_CI_TEST_GATE_TIMEOUT_SEC GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC \
  GAAI_CI_TEST_GATE_API_TIMEOUT_SEC

# ── T12: cancellation after a superseding push reports moved head ──────────
echo "--- T12: cancelled run after superseding push ---"
REPO_T12="$(setup_repo T12 "workers/fake-pkg/file.txt")"
HEAD_T12=$(git -C "$REPO_T12" rev-parse HEAD)
QA_T12="$SANDBOX/T12.qa-report.md"
OUT_T12="$SANDBOX/T12.out.log"
: > "$NOTIFY_CALLS_LOG"
set_gh_run_lines "completed"$'\t'"cancelled"$'\t'"$HEAD_T12"
export GH_PR_HEAD_SHA="$(printf '%040d' 2)"
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=5

_run_merge_test_gate "T12" "$REPO_T12" "$QA_T12" "$PR_URL" "$HEAD_T12" > "$OUT_T12" 2>&1
RC_T12=$?
unset GAAI_CI_TEST_GATE_TIMEOUT_SEC

[[ "$RC_T12" -eq 1 ]] \
  && pass "T12: superseding push blocks the cancelled old head" \
  || fail "T12: expected rc=1, got ${RC_T12}"
grep -q "test_gate_head_moved" "$NOTIFY_CALLS_LOG" \
  && pass "T12: superseded cancellation records the moved-head reason" \
  || fail "T12: moved-head escalation reason missing"

unset GH_PR_HEAD_SHA

# ── T13: materialize sub-budget fast-fail + unset-default resolution (AC1+AC5+AC6) ─
echo "--- T13: no run ever materialises, default budget unset ---"
REPO_T13="$(setup_repo T13 "workers/fake-pkg/file.txt")"
HEAD_T13=$(git -C "$REPO_T13" rev-parse HEAD)
QA_T13="$SANDBOX/T13.qa-report.md"
OUT_T13="$SANDBOX/T13.out.log"
: > "$GH_CALL_LOG"
set_gh_run_lines "missing"
unset GAAI_CI_TEST_GATE_TIMEOUT_SEC
export GAAI_CI_TEST_GATE_MATERIALIZE_SEC=1
export GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC=1
export GAAI_CI_TEST_GATE_API_TIMEOUT_SEC=1
unset GH_API_EXIT GH_API_HANG_SEC

_t13_start=$(date +%s)
_run_merge_test_gate "T13" "$REPO_T13" "$QA_T13" "$PR_URL" "$HEAD_T13" > "$OUT_T13" 2>&1
RC_T13=$?
_t13_end=$(date +%s)
_t13_elapsed=$(( _t13_end - _t13_start ))

[[ "$RC_T13" -eq 0 ]] && pass "T13: returns 0 (local fallback PASS)" || fail "T13: expected rc=0, got ${RC_T13}"
[[ "$_t13_elapsed" -lt 10 ]] \
  && pass "T13: no_run resolved well inside the materialize sub-budget (${_t13_elapsed}s < 10s)" \
  || fail "T13: took ${_t13_elapsed}s — materialize sub-budget did not fast-fail"
grep -q "unavailable (no_run)" "$OUT_T13" \
  && pass "T13: fallback reason=no_run (distinct token, AC6)" \
  || fail "T13: expected reason=no_run in output"
grep -q "no CI run observed for this SHA" "$OUT_T13" \
  && pass "T13: no_run detail present (AC3)" \
  || fail "T13: no_run detail missing from output"
grep -q '/2700s)' "$OUT_T13" \
  && pass "T13: progress line reflects the unset-default full budget of 2700s (AC1+AC5)" \
  || fail "T13: progress line does not show the 2700s default"

unset GAAI_CI_TEST_GATE_MATERIALIZE_SEC GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC GAAI_CI_TEST_GATE_API_TIMEOUT_SEC

# ── T14: run observed but never decisive → timeout classification (AC3) ─────
echo "--- T14: run observed in_progress throughout, budget exhausts ---"
REPO_T14="$(setup_repo T14 "workers/fake-pkg/file.txt")"
HEAD_T14=$(git -C "$REPO_T14" rev-parse HEAD)
QA_T14="$SANDBOX/T14.qa-report.md"
OUT_T14="$SANDBOX/T14.out.log"
: > "$GH_CALL_LOG"
set_gh_run_lines "in_progress"$'\t'"pending"$'\t'"$HEAD_T14"
export GAAI_CI_TEST_GATE_TIMEOUT_SEC=2
export GAAI_CI_TEST_GATE_MATERIALIZE_SEC=1
export GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC=1
export GAAI_CI_TEST_GATE_API_TIMEOUT_SEC=1
unset GH_API_EXIT GH_API_HANG_SEC

_run_merge_test_gate "T14" "$REPO_T14" "$QA_T14" "$PR_URL" "$HEAD_T14" > "$OUT_T14" 2>&1
RC_T14=$?

[[ "$RC_T14" -eq 0 ]] && pass "T14: returns 0 (local fallback PASS)" || fail "T14: expected rc=0, got ${RC_T14}"
grep -q "unavailable (timeout)" "$OUT_T14" \
  && pass "T14: fallback reason=timeout (verdict shape unchanged)" \
  || fail "T14: expected reason=timeout in output"
grep -q "CI run observed but still in progress at cutoff" "$OUT_T14" \
  && pass "T14: timeout detail present (AC3's second class)" \
  || fail "T14: timeout detail missing from output"

unset GAAI_CI_TEST_GATE_TIMEOUT_SEC GAAI_CI_TEST_GATE_MATERIALIZE_SEC \
  GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC GAAI_CI_TEST_GATE_API_TIMEOUT_SEC

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "  ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[[ "$FAIL_COUNT" -eq 0 ]]
