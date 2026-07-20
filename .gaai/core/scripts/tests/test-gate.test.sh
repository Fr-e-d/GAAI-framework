#!/usr/bin/env bash
# ── test-gate.test.sh ──────────────────────────────────────────────────────
# _run_deterministic_test_gate: differential test gate at the commit-phase
# transition (E1058S03). Only a test that PASSES on the origin/staging
# baseline and FAILS on the story's HEAD is a blocking regression.
#
# Builds a real git fixture per scenario (bare remote + repo, no `git
# worktree add` needed — a plain repo satisfies the gate's `git -C
# <worktree_path>` contract just as well). `pnpm` is stubbed on PATH (reads
# scripts.test:ci/scripts.test from package.json via node, then execs it) so
# the test never needs a real pnpm/vitest install — the fake test runner
# itself is a self-contained bash script gated by a git-tracked marker file,
# so pass/fail state differs deterministically between the baseline commit
# and the story commit.
#
# T1 (new-failure → blocked): baseline passes, story breaks it.
# T2 (no-new-failure → pass): baseline passes, story touches the package but
#     the test still passes.
# T3 (pre-existing-baseline-red → not blocked): baseline ALREADY fails,
#     story doesn't fix it (core AC1 differential guarantee).
# All three also assert the worktree ends back on the story branch (not left
# detached) — the Step 4.5 restore invariant.
#
# Run: bash .gaai/core/scripts/tests/test-gate.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BACKLOG_FILE="/tmp/gaai-testgate-test-backlog.yaml"
SCHEDULER="$(which true)"
export PROJECT_DIR BACKLOG_FILE SCHEDULER

# Source the library under test (defines _run_deterministic_test_gate).
# Tolerate the best-effort sub-source of worktree-integrity.sh exactly as
# the daemon does.
source "$SCRIPT_DIR/../daemon-dispatch.sh" 2>/dev/null || true

log() { :; }
CYAN=""; YELLOW=""; NC=""

# ── Fixture sandbox ─────────────────────────────────────────────────────────
SANDBOX="$(mktemp -d /tmp/gaai-testgate-XXXXXX)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

SCHEDULER_CALLS_LOG="$SANDBOX/scheduler-calls.log"
NOTIFY_CALLS_LOG="$SANDBOX/notify-calls.log"
: > "$SCHEDULER_CALLS_LOG"
: > "$NOTIFY_CALLS_LOG"

# Real SCHEDULER stub (this file calls it directly, not via `declare -F`, so
# it must be an executable on PATH/absolute path — matches the daemon's real
# `"$SCHEDULER" --set-phase-status ...` invocation contract).
STUB_BIN="$SANDBOX/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/scheduler-stub.sh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$SCHEDULER_CALLS_LOG"
exit 0
EOF
chmod +x "$STUB_BIN/scheduler-stub.sh"
SCHEDULER="$STUB_BIN/scheduler-stub.sh"

# notify_escalation_inline is checked via `declare -F` (a shell function),
# not looked up on PATH — define it directly in this process.
notify_escalation_inline() {
  echo "$1|$2|$3" >> "$NOTIFY_CALLS_LOG"
  return 0
}

# ── Stub pnpm on PATH (git/node stay real) ──────────────────────────────────
# Mimics `pnpm -C <dir> run <script>`: resolve scripts[<script>] from
# <dir>/package.json via node, then exec it with cwd=<dir>. No real pnpm
# install needed, and the underlying fake test runner is plain bash (AC6).
cat > "$STUB_BIN/pnpm" <<'EOF'
#!/usr/bin/env bash
dir=""; script=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) shift; dir="$1" ;;
    run) shift; script="$1" ;;
  esac
  shift
done
cmd=$(node -e "
try {
  const p = require(process.argv[1] + '/package.json');
  process.stdout.write((p.scripts && p.scripts[process.argv[2]]) || '');
} catch (e) {}
" "$dir" "$script" 2>/dev/null)
[[ -z "$cmd" ]] && { echo "stub-pnpm: no script '$script' in $dir" >&2; exit 1; }
( cd "$dir" && eval "$cmd" )
exit $?
EOF
chmod +x "$STUB_BIN/pnpm"
PATH="$STUB_BIN:$PATH"

# ── Fake test runner (self-contained bash, no node_modules) ─────────────────
FAKE_RUNNER='#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="pass"
[[ -f "$DIR/.expected-status" ]] && STATUS="$(cat "$DIR/.expected-status")"
if [[ "$STATUS" == "fail" ]]; then
  cat > "$DIR/test-results.xml" <<XML
<testsuite>
  <testcase classname="fixture" name="the_test">
    <failure message="boom"/>
  </testcase>
</testsuite>
XML
  exit 1
else
  cat > "$DIR/test-results.xml" <<XML
<testsuite>
  <testcase classname="fixture" name="the_test"/>
</testsuite>
XML
  exit 0
fi
'

# setup_scenario <tag> <baseline_status> <story_status> <touch_unrelated 0|1>
# Returns the repo path on stdout. Baseline commit lands on `staging` +
# origin; story commit is a child on `story/<tag>`, left checked out (as a
# real daemon worktree would be, post-commit-phase, pre-push).
setup_scenario() {
  local tag="$1" baseline_status="$2" story_status="$3" touch_unrelated="$4"
  local remote="$SANDBOX/${tag}-remote.git"
  local repo="$SANDBOX/${tag}-repo"

  git init --quiet --bare "$remote"
  git init --quiet "$repo"
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  git -C "$repo" checkout -q -b staging

  printf '{"name":"fixture-root","packageManager":"pnpm@0.0.0-test"}\n' > "$repo/package.json"
  mkdir -p "$repo/pkg"
  printf '{"name":"fixture-pkg","scripts":{"test:ci":"bash run-fake-tests.sh"}}\n' > "$repo/pkg/package.json"
  printf '%s' "$FAKE_RUNNER" > "$repo/pkg/run-fake-tests.sh"
  printf '%s' "$baseline_status" > "$repo/pkg/.expected-status"

  git -C "$repo" add -A && git -C "$repo" commit -q -m baseline
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -q origin staging
  git -C "$repo" fetch -q origin staging

  git -C "$repo" checkout -q -b "story/${tag}"
  if [[ "$touch_unrelated" == "1" ]]; then
    printf '\n# touched by %s\n' "$tag" >> "$repo/pkg/run-fake-tests.sh"
  fi
  printf '%s' "$story_status" > "$repo/pkg/.expected-status"
  git -C "$repo" add -A && git -C "$repo" commit -q -m "story ${tag}"

  echo "$repo"
}

TARGET_BRANCH="staging"
export TARGET_BRANCH

# ── T1: new-failure → blocked ────────────────────────────────────────────────
REPO_T1="$(setup_scenario T1 pass fail 0)"
QA_T1="$SANDBOX/T1.qa-report.md"
_run_deterministic_test_gate "T1" "$REPO_T1" "$QA_T1"
RC_T1=$?

[[ "$RC_T1" -eq 1 ]] && pass "T1: gate returns 1 (blocked)" || fail "T1: expected rc=1, got ${RC_T1}"
grep -q -- "--set-phase-status T1 failed" "$SCHEDULER_CALLS_LOG" \
  && pass "T1: scheduler --set-phase-status T1 failed recorded" \
  || fail "T1: scheduler was not told to set phase_status failed"
grep -q "^- Verdict: BLOCKED$" "$QA_T1" \
  && pass "T1: qa-report has BLOCKED verdict" \
  || fail "T1: qa-report missing BLOCKED verdict"
grep -q "fixture::the_test" "$QA_T1" \
  && pass "T1: qa-report names the failing unit" \
  || fail "T1: qa-report does not name the failing testcase"
[[ "$(git -C "$REPO_T1" rev-parse --abbrev-ref HEAD)" == "story/T1" ]] \
  && pass "T1: worktree restored to story/T1 (not left detached)" \
  || fail "T1: worktree not restored to story branch"

# ── T2: no-new-failure → pass ────────────────────────────────────────────────
REPO_T2="$(setup_scenario T2 pass pass 1)"
QA_T2="$SANDBOX/T2.qa-report.md"
_run_deterministic_test_gate "T2" "$REPO_T2" "$QA_T2"
RC_T2=$?

[[ "$RC_T2" -eq 0 ]] && pass "T2: gate returns 0 (not blocked)" || fail "T2: expected rc=0, got ${RC_T2}"
grep -q -- "--set-phase-status T2 failed" "$SCHEDULER_CALLS_LOG" \
  && fail "T2: scheduler was incorrectly told to set phase_status failed" \
  || pass "T2: scheduler NOT told to fail"
grep -q "^- Verdict: PASS$" "$QA_T2" \
  && pass "T2: qa-report has PASS verdict" \
  || fail "T2: qa-report missing PASS verdict"
[[ "$(git -C "$REPO_T2" rev-parse --abbrev-ref HEAD)" == "story/T2" ]] \
  && pass "T2: worktree restored to story/T2 (not left detached)" \
  || fail "T2: worktree not restored to story branch"

# ── T3: pre-existing-baseline-red → not blocked (core AC1 guarantee) ────────
REPO_T3="$(setup_scenario T3 fail fail 1)"
QA_T3="$SANDBOX/T3.qa-report.md"
_run_deterministic_test_gate "T3" "$REPO_T3" "$QA_T3"
RC_T3=$?

[[ "$RC_T3" -eq 0 ]] && pass "T3: gate returns 0 (not blocked despite red HEAD)" || fail "T3: expected rc=0, got ${RC_T3}"
grep -q -- "--set-phase-status T3 failed" "$SCHEDULER_CALLS_LOG" \
  && fail "T3: scheduler was incorrectly told to set phase_status failed" \
  || pass "T3: scheduler NOT told to fail (pre-existing red is non-blocking)"
grep -q "^- Verdict: PASS$" "$QA_T3" \
  && pass "T3: qa-report has PASS verdict" \
  || fail "T3: qa-report missing PASS verdict"
grep -q "Pre-existing baseline failures" "$QA_T3" \
  && pass "T3: qa-report records the pre-existing failure for audit" \
  || fail "T3: qa-report does not record the pre-existing baseline failure"
[[ "$(git -C "$REPO_T3" rev-parse --abbrev-ref HEAD)" == "story/T3" ]] \
  && pass "T3: worktree restored to story/T3 (not left detached)" \
  || fail "T3: worktree not restored to story branch"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "  ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[[ "$FAIL_COUNT" -eq 0 ]]
