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
# T4 (worker setup): a direct /bin/sh child identifies each live worker;
#     identity/file/renice failures retain status and never run the command.
# T5 (concurrency): synchronized workers target distinct real parent PIDs.
# T1–T3 also assert the worktree ends back on the story branch (not left
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

# renice stub: the process's real PPID is the worker that invoked it. Every
# successful call proves the production -p target equals that PPID and differs
# from the test harness's ambient shell. Barrier mode keeps two workers live at
# once so their identities can be compared under each selected Bash.
RENICE_CALLS_LOG="$SANDBOX/renice-calls.log"
TEST_GATE_OUTER_PID="$$"
export RENICE_CALLS_LOG TEST_GATE_OUTER_PID
: > "$RENICE_CALLS_LOG"
cat > "$STUB_BIN/renice" <<'EOF'
#!/bin/sh
target=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-p" ]; then
    shift
    target="${1:-}"
  fi
  shift
done
printf '%s|%s|%s\n' "$target" "$PPID" "$TEST_GATE_OUTER_PID" >> "$RENICE_CALLS_LOG"
[ "$target" = "$PPID" ] || exit 91
[ "$target" != "$TEST_GATE_OUTER_PID" ] || exit 92
case "${TEST_GATE_RENICE_MODE:-pass}" in
  nonzero) exit "${TEST_GATE_RENICE_RC:-27}" ;;
  signal) kill -9 "$$"; exit 99 ;;
  barrier)
    : > "$TEST_GATE_RENICE_BARRIER_DIR/$PPID"
    while [ ! -f "$TEST_GATE_RENICE_BARRIER_DIR/release" ]; do
      sleep 0.01
    done
    ;;
esac
exit 0
EOF
chmod +x "$STUB_BIN/renice"

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

# ── T4: direct-child identity + fail-closed setup/scheduling ──────────────
IDENTITY_TMP="$SANDBOX/identity-tmp"
mkdir -p "$IDENTITY_TMP"

run_unit_probe() {
  local tag="$1" command_text="$2" probe_rc
  local unit="bash|${tag}|${command_text}"
  TMPDIR="$IDENTITY_TMP" _test_gate_run_units "$SANDBOX" "$unit" \
    > "$SANDBOX/${tag}.failures" 2> "$SANDBOX/${tag}.diagnostics"
  probe_rc=$?
  printf '%s\n' "$probe_rc" > "$SANDBOX/${tag}.rc"
  return 0
}

: > "$RENICE_CALLS_LOG"
HAPPY_MARKER="$SANDBOX/identity-happy-ran"
run_unit_probe identity-happy ": > '$HAPPY_MARKER'"
[[ -f "$HAPPY_MARKER" && ! -s "$SANDBOX/identity-happy.failures" ]] \
  && pass "T4: valid worker identity runs the unit without a failed label" \
  || fail "T4: valid worker identity did not run cleanly"
if awk -F'|' 'NF == 3 && $1 == $2 && $1 != $3 && $1 ~ /^[1-9][0-9]*$/ { ok++ } END { exit !(ok == 1) }' \
    "$RENICE_CALLS_LOG"; then
  pass "T4: fake renice target equals its real worker parent, not outer shell"
else
  fail "T4: renice target/parent mismatch: $(cat "$RENICE_CALLS_LOG" 2>/dev/null)"
fi
grep -q "unit=identity-happy type=bash starting" "$SANDBOX/identity-happy.diagnostics" \
  && grep -q "unit=identity-happy type=bash exit=0" "$SANDBOX/identity-happy.diagnostics" \
  && pass "T4: start and exit=0 diagnostics are retained" \
  || fail "T4: happy diagnostics missing"
[[ -z "$(find "$IDENTITY_TMP" -type f -print -quit)" ]] \
  && pass "T4: worker-owned identity file is removed after success" \
  || fail "T4: identity file leaked after success"

_TEST_GATE_WORKER_IDENTITY_PATH=""
TMPDIR="$IDENTITY_TMP" _test_gate_worker_identity_tempfile
real_identity_create_rc=$?
real_identity_path="$_TEST_GATE_WORKER_IDENTITY_PATH"
if [[ "$real_identity_create_rc" -eq 0 ]] \
    && _test_gate_private_tempfile_is_safe "$real_identity_path"; then
  pass "T4: real identity tempfile is regular, non-symlink, owned and private"
else
  fail "T4: real identity tempfile ownership/type/mode contract failed"
fi
[[ -n "$real_identity_path" ]] && _test_gate_worker_identity_cleanup "$real_identity_path"

multiline_identity="$IDENTITY_TMP/multiline-identity"
caller_fd_fixture="$IDENTITY_TMP/caller-fd"
printf '123\n456' > "$multiline_identity"
printf 'caller-fd-still-open\n' > "$caller_fd_fixture"
exec 9< "$caller_fd_fixture"
_test_gate_worker_identity_read "$multiline_identity"
multiline_read_rc=$?
caller_fd_line=""
IFS= read -r caller_fd_line <&9
caller_fd_rc=$?
exec 9<&-
rm -f "$multiline_identity" "$caller_fd_fixture"
if [[ "$multiline_read_rc" -ne 0 && "$caller_fd_rc" -eq 0 \
      && "$caller_fd_line" == "caller-fd-still-open" ]]; then
  pass "T4: real unterminated second identity line is rejected without clobbering caller fd 9"
else
  fail "T4: multiline identity or caller-fd preservation contract failed"
fi

assert_setup_failure() {
  local tag="$1" expected_rc="$2" expected_reason="$3" marker
  marker="$SANDBOX/${tag}-ran"
  if grep -qx "$tag" "$SANDBOX/${tag}.failures" \
      && grep -qx "$expected_rc" "$SANDBOX/${tag}.rc" \
      && grep -q "unit=${tag} type=bash exit=${expected_rc}" "$SANDBOX/${tag}.diagnostics" \
      && grep -q "unit setup failed: ${expected_reason}" "$SANDBOX/${tag}.diagnostics" \
      && [[ ! -e "$marker" ]]; then
    pass "T4: ${tag} is fail-closed with original exit=${expected_rc}"
  else
    fail "T4: ${tag} status/diagnostic/command guard mismatch"
  fi
}

(
  _test_gate_worker_identity_tempfile() { return 23; }
  run_unit_probe identity-create-failure ": > '$SANDBOX/identity-create-failure-ran'"
)
assert_setup_failure identity-create-failure 23 "identity temporary-file creation"

(
  _test_gate_worker_identity_write() { return 24; }
  run_unit_probe identity-write-failure ": > '$SANDBOX/identity-write-failure-ran'"
)
assert_setup_failure identity-write-failure 24 "worker identity write"

(
  _test_gate_worker_identity_read() { return 25; }
  run_unit_probe identity-read-failure ": > '$SANDBOX/identity-read-failure-ran'"
)
assert_setup_failure identity-read-failure 25 "worker identity read"

(
  _test_gate_worker_identity_read() {
    _TEST_GATE_WORKER_PID="not-a-pid"
    return 0
  }
  run_unit_probe identity-invalid ": > '$SANDBOX/identity-invalid-ran'"
)
assert_setup_failure identity-invalid 1 "worker identity validation"

(
  cleanup_calls=0
  _test_gate_worker_identity_cleanup() {
    cleanup_calls=$((cleanup_calls + 1))
    [[ "$cleanup_calls" -eq 1 ]] && return 26
    rm -f "$1"
  }
  run_unit_probe identity-cleanup-failure ": > '$SANDBOX/identity-cleanup-failure-ran'"
)
assert_setup_failure identity-cleanup-failure 26 "identity temporary-file cleanup"

(
  _test_gate_worker_infra_write() {
    printf '%s\n' corrupt > "$_TEST_GATE_INFRA_MARKER_PATH"
    return 29
  }
  TEST_GATE_RENICE_MODE=nonzero TEST_GATE_RENICE_RC=27 \
    run_unit_probe setup-and-marker-write-failure \
      ": > '$SANDBOX/setup-and-marker-write-failure-ran'"
)
assert_setup_failure setup-and-marker-write-failure 27 "worker scheduling"

(
  _test_gate_unit_infra_marker_read() { return 31; }
  TEST_GATE_RENICE_MODE=nonzero TEST_GATE_RENICE_RC=27 \
    run_unit_probe setup-and-marker-read-failure \
      ": > '$SANDBOX/setup-and-marker-read-failure-ran'"
)
assert_setup_failure setup-and-marker-read-failure 27 "worker scheduling"

(
  _test_gate_unit_infra_marker_cleanup() {
    rm -f "$1"
    return 30
  }
  run_unit_probe infra-marker-cleanup ": > '$SANDBOX/infra-marker-cleanup-ran'"
)
if grep -qx "30" "$SANDBOX/infra-marker-cleanup.rc" \
    && grep -qx "infra-marker-cleanup" "$SANDBOX/infra-marker-cleanup.failures" \
    && grep -q "unit setup failed: infrastructure result channel cleanup" \
      "$SANDBOX/infra-marker-cleanup.diagnostics" \
    && [[ -f "$SANDBOX/infra-marker-cleanup-ran" ]]; then
  pass "T4: infrastructure result-channel cleanup failure is authoritative"
else
  fail "T4: infrastructure result-channel cleanup failure was ignored"
fi

TEST_GATE_RENICE_MODE=nonzero TEST_GATE_RENICE_RC=27 \
  run_unit_probe renice-nonzero ": > '$SANDBOX/renice-nonzero-ran'"
assert_setup_failure renice-nonzero 27 "worker scheduling"

TEST_GATE_RENICE_MODE=signal \
  run_unit_probe renice-signal ": > '$SANDBOX/renice-signal-ran'"
assert_setup_failure renice-signal 137 "worker scheduling"

run_unit_probe ordinary-unit-failure "exit 3"
grep -qx "ordinary-unit-failure" "$SANDBOX/ordinary-unit-failure.failures" \
  && grep -q "unit=ordinary-unit-failure type=bash exit=3" "$SANDBOX/ordinary-unit-failure.diagnostics" \
  && pass "T4: ordinary unit rc=3 and failed label remain observable" \
  || fail "T4: ordinary unit failure propagation changed"

run_unit_probe ordinary-unit-signal "/bin/sh -c 'kill -9 \$\$'"
grep -qx "ordinary-unit-signal" "$SANDBOX/ordinary-unit-signal.failures" \
  && grep -q "unit=ordinary-unit-signal type=bash exit=137" "$SANDBOX/ordinary-unit-signal.diagnostics" \
  && pass "T4: ordinary unit signal 9 remains observable as exit=137" \
  || fail "T4: ordinary unit signal propagation changed"

STALE_JUNIT_DIR="$SANDBOX/stale-junit"
STALE_JUNIT_MARKER="$SANDBOX/stale-junit-command-ran"
mkdir -p "$STALE_JUNIT_DIR"
cat > "$STALE_JUNIT_DIR/test-results.xml" <<'EOF'
<testsuite>
  <testcase classname="stale" name="previous_pass"/>
</testsuite>
EOF
TEST_GATE_RENICE_MODE=nonzero TEST_GATE_RENICE_RC=27 \
  TMPDIR="$IDENTITY_TMP" _test_gate_run_units "$SANDBOX" \
    "junit|$STALE_JUNIT_DIR|: > '$STALE_JUNIT_MARKER'" \
    > "$SANDBOX/stale-junit.failures" 2> "$SANDBOX/stale-junit.diagnostics"
stale_junit_rc=$?
if [[ "$stale_junit_rc" -eq 27 && ! -e "$STALE_JUNIT_MARKER" ]] \
    && grep -qx "$STALE_JUNIT_DIR" "$SANDBOX/stale-junit.failures" \
    && grep -q "unit=$STALE_JUNIT_DIR type=junit exit=27" "$SANDBOX/stale-junit.diagnostics"; then
  pass "T4: setup rc=27 outranks a parseable stale JUnit PASS document"
else
  fail "T4: stale JUnit PASS swallowed or transformed setup infrastructure failure"
fi

TMPDIR="$IDENTITY_TMP" _test_gate_run_units "$SANDBOX" \
  "junit|$STALE_JUNIT_DIR|exit 3" \
  > "$SANDBOX/stale-junit-command.failures" 2> "$SANDBOX/stale-junit-command.diagnostics"
stale_junit_command_rc=$?
if [[ "$stale_junit_command_rc" -eq 0 ]] \
    && grep -qx "$STALE_JUNIT_DIR" "$SANDBOX/stale-junit-command.failures" \
    && grep -q "unit=$STALE_JUNIT_DIR type=junit exit=3" \
      "$SANDBOX/stale-junit-command.diagnostics"; then
  pass "T4: command rc=3 with parseable JUnit PASS retains a coarse failed label"
else
  fail "T4: parseable JUnit PASS swallowed an ordinary nonzero command result"
fi

MISSING_WORKTREE_MARKER="$SANDBOX/missing-worktree-command-ran"
TMPDIR="$IDENTITY_TMP" _test_gate_run_units "$SANDBOX/does-not-exist" \
  "bash|missing-worktree|: > '$MISSING_WORKTREE_MARKER'" \
  > "$SANDBOX/missing-worktree.failures" 2> "$SANDBOX/missing-worktree.diagnostics"
missing_worktree_rc=$?
if [[ "$missing_worktree_rc" -ne 0 && ! -e "$MISSING_WORKTREE_MARKER" ]] \
    && grep -qx "missing-worktree" "$SANDBOX/missing-worktree.failures" \
    && grep -q "unit setup failed: unit working directory" \
      "$SANDBOX/missing-worktree.diagnostics"; then
  pass "T4: working-directory setup failure uses infrastructure channel and blocks command"
else
  fail "T4: working-directory setup failure remained differential/ordinary"
fi

CAT_FAULT_BIN="$SANDBOX/cat-fault-bin"
REAL_CAT_PATH="$(PATH=/usr/bin:/bin command -v cat)"
mkdir -p "$CAT_FAULT_BIN"
cat > "$CAT_FAULT_BIN/cat" <<'EOF'
#!/bin/sh
"$REAL_CAT_PATH" >/dev/null
exit 29
EOF
chmod +x "$CAT_FAULT_BIN/cat"
export REAL_CAT_PATH

SINK_MARKER="$SANDBOX/diagnostic-sink-command-ran"
PATH="$CAT_FAULT_BIN:$PATH" run_unit_probe diagnostic-sink-failure ": > '$SINK_MARKER'"
if grep -qx "29" "$SANDBOX/diagnostic-sink-failure.rc" \
    && grep -qx "diagnostic-sink-failure" "$SANDBOX/diagnostic-sink-failure.failures" \
    && grep -q "unit setup failed: diagnostic streaming channel" \
      "$SANDBOX/diagnostic-sink-failure.diagnostics" \
    && [[ -e "$SINK_MARKER" ]]; then
  pass "T4: diagnostic sink rc=29 is authoritative infrastructure failure"
else
  fail "T4: diagnostic streaming sink failure was ignored"
fi

PATH="$CAT_FAULT_BIN:$PATH" TEST_GATE_RENICE_MODE=nonzero TEST_GATE_RENICE_RC=27 \
  run_unit_probe setup-and-sink-failure ": > '$SANDBOX/setup-and-sink-ran'"
if grep -qx "27" "$SANDBOX/setup-and-sink-failure.rc" \
    && grep -qx "setup-and-sink-failure" "$SANDBOX/setup-and-sink-failure.failures" \
    && [[ ! -e "$SANDBOX/setup-and-sink-ran" ]]; then
  pass "T4: prior setup rc=27 outranks later diagnostic sink rc=29"
else
  fail "T4: diagnostic sink failure overwrote prior setup status"
fi

[[ -z "$(find "$IDENTITY_TMP" -type f -print -quit)" ]] \
  && pass "T4: identity files are removed after all injected failure paths" \
  || fail "T4: identity file leaked after an injected failure"

MULTI_MARKER="$SANDBOX/multi-later-ran"
(
  fault_once="$SANDBOX/multi-identity-fault-once"
  _test_gate_worker_identity_tempfile() {
    if [[ ! -e "$fault_once" ]]; then
      : > "$fault_once"
      return 28
    fi
    _TEST_GATE_WORKER_IDENTITY_PATH=$(mktemp "${TMPDIR:-/tmp}/gaai-test-gate-worker.XXXXXX")
  }
  units="bash|multi-setup-failure|: > '$SANDBOX/multi-first-ran'"
  units="$units
bash|multi-later-pass|: > '$MULTI_MARKER'"
  TMPDIR="$IDENTITY_TMP" _test_gate_run_units "$SANDBOX" "$units" \
    > "$SANDBOX/multi.failures" 2> "$SANDBOX/multi.diagnostics"
  printf '%s\n' "$?" > "$SANDBOX/multi.rc"
)
grep -qx "multi-setup-failure" "$SANDBOX/multi.failures" \
  && grep -qx "28" "$SANDBOX/multi.rc" \
  && [[ "$(wc -l < "$SANDBOX/multi.failures" | tr -d ' ')" == "1" ]] \
  && [[ -f "$MULTI_MARKER" && ! -e "$SANDBOX/multi-first-ran" ]] \
  && pass "T4: setup failure is aggregated and later unit still runs" \
  || fail "T4: multi-unit aggregation semantics changed"

if grep -Eih '(credential|secret|authorization|bearer[[:space:]]|api[_ -]?key|https?://)' \
    "$SANDBOX"/*.diagnostics >/dev/null 2>&1; then
  fail "T4: setup diagnostics contain private/provider-specific text"
else
  pass "T4: setup diagnostics remain public-safe and provider-neutral"
fi

# ── T5: two synchronized workers receive distinct identities ────────────
: > "$RENICE_CALLS_LOG"
BARRIER_DIR="$SANDBOX/renice-barrier"
mkdir -p "$BARRIER_DIR"
TEST_GATE_RENICE_MODE=barrier TEST_GATE_RENICE_BARRIER_DIR="$BARRIER_DIR" \
  run_unit_probe concurrent-one ":" &
concurrent_one_pid=$!
TEST_GATE_RENICE_MODE=barrier TEST_GATE_RENICE_BARRIER_DIR="$BARRIER_DIR" \
  run_unit_probe concurrent-two ":" &
concurrent_two_pid=$!
( sleep 5; : > "$BARRIER_DIR/release" ) &
barrier_watchdog_pid=$!
while [[ "$(find "$BARRIER_DIR" -type f ! -name release | wc -l | tr -d ' ')" -lt 2 \
         && ! -f "$BARRIER_DIR/release" ]]; do
  sleep 0.01
done
: > "$BARRIER_DIR/release"
kill "$barrier_watchdog_pid" >/dev/null 2>&1 || true
wait "$barrier_watchdog_pid" 2>/dev/null || true
wait "$concurrent_one_pid"; concurrent_one_rc=$?
wait "$concurrent_two_pid"; concurrent_two_rc=$?
if [[ "$concurrent_one_rc" -eq 0 && "$concurrent_two_rc" -eq 0 ]] \
    && awk -F'|' '
      NF == 3 && $1 == $2 && $1 != $3 { seen[$1]=1; rows++ }
      END { for (pid in seen) unique++; exit !(rows == 2 && unique == 2) }
    ' "$RENICE_CALLS_LOG"; then
  pass "T5: synchronized workers target two distinct real parent PIDs"
else
  fail "T5: concurrent worker identities collided or mismatched: $(cat "$RENICE_CALLS_LOG" 2>/dev/null)"
fi

REAL_RENICE_PATH="$(PATH=/usr/bin:/bin command -v renice 2>/dev/null || true)"
REAL_PS_PATH="$(PATH=/usr/bin:/bin command -v ps 2>/dev/null || true)"
REAL_NICE_RESULT="$SANDBOX/real-nice-result"
REAL_NICE_ERROR="$SANDBOX/real-nice-error"
real_renice_rc=1
if [[ -n "$REAL_RENICE_PATH" && -n "$REAL_PS_PATH" ]]; then
  (
    TMPDIR="$IDENTITY_TMP" _test_gate_prepare_worker_identity || exit $?
    "$REAL_RENICE_PATH" -n 15 -p "$_TEST_GATE_WORKER_PID" \
      >/dev/null 2> "$REAL_NICE_ERROR" || exit $?
    /bin/sh -c '"$1" -o ni= -p "$$"' real-renice-child "$REAL_PS_PATH" \
      > "$REAL_NICE_RESULT"
  )
  real_renice_rc=$?
fi
real_child_niceness=""
[[ -f "$REAL_NICE_RESULT" ]] \
  && real_child_niceness="$(tr -d '[:space:]' < "$REAL_NICE_RESULT")"
if [[ "$real_renice_rc" -eq 0 && "$real_child_niceness" =~ ^[0-9]+$ \
      && "$real_child_niceness" -ge 15 ]]; then
  pass "T5: isolated real renice probe lowers worker priority and child inherits it"
elif [[ -n "$REAL_RENICE_PATH" && -s "$REAL_NICE_ERROR" ]]; then
  fail "T5: real renice inheritance UNVERIFIED: environment denied priority change"
else
  fail "T5: real renice inheritance probe unavailable/failed (rc=$real_renice_rc nice=${real_child_niceness:-missing})"
fi

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

# ── T6: identical HEAD/baseline infrastructure failure never PASSes ──────
REPO_T6="$(setup_scenario T6 pass pass 1)"
QA_T6="$SANDBOX/T6.qa-report.md"
: > "$RENICE_CALLS_LOG"
TEST_GATE_RENICE_MODE=nonzero TEST_GATE_RENICE_RC=27 \
  _run_deterministic_test_gate "T6" "$REPO_T6" "$QA_T6"
RC_T6=$?

[[ "$RC_T6" -eq 1 ]] \
  && pass "T6: identical HEAD/baseline infrastructure failure escalates" \
  || fail "T6: expected infrastructure escalation rc=1, got $RC_T6"
grep -q "^- Verdict: ESCALATED$" "$QA_T6" \
  && ! grep -q "^- Verdict: PASS$" "$QA_T6" \
  && pass "T6: qa-report records ESCALATED and never PASS" \
  || fail "T6: infrastructure failure report was missing or misleading"
grep -q "HEAD exit 27; baseline exit 27" "$QA_T6" \
  && pass "T6: both original infrastructure statuses are recorded" \
  || fail "T6: HEAD/baseline infrastructure statuses missing"
[[ ! -e "$REPO_T6/pkg/test-results.xml" ]] \
  && pass "T6: neither HEAD nor baseline unit command executed" \
  || fail "T6: a unit command ran despite infrastructure failure"
[[ "$(wc -l < "$RENICE_CALLS_LOG" | tr -d ' ')" == "2" ]] \
  && pass "T6: both HEAD and baseline setup paths were observed" \
  || fail "T6: expected two renice setup failures"
[[ "$(git -C "$REPO_T6" rev-parse --abbrev-ref HEAD)" == "story/T6" ]] \
  && pass "T6: worktree restored after baseline infrastructure failure" \
  || fail "T6: worktree not restored after infrastructure failure"

# ── T7: baseline infra failure remains restore-safe under true errexit ────
REPO_T7="$(setup_scenario T7 pass pass 1)"
QA_T7="$SANDBOX/T7.qa-report.md"
T7_EXIT_STATE="$SANDBOX/T7.exit-state"
(
  _test_gate_run_units() {
    if [[ "$(git -C "$1" rev-parse --abbrev-ref HEAD)" == "HEAD" ]]; then
      printf '%s\n' "baseline-infrastructure-failure"
      return 27
    fi
    return 0
  }
  record_t7_exit() {
    local run_rc=$?
    set +e
    printf '%s|%s\n' "$run_rc" \
      "$(git -C "$REPO_T7" rev-parse --abbrev-ref HEAD)" > "$T7_EXIT_STATE"
  }
  trap record_t7_exit EXIT
  set -e
  _run_deterministic_test_gate "T7" "$REPO_T7" "$QA_T7"
  printf '%s\n' "unexpected-return" >> "$T7_EXIT_STATE"
)
RC_T7=$?

[[ "$RC_T7" -eq 1 && "$(cat "$T7_EXIT_STATE")" == "1|story/T7" ]] \
  && pass "T7: true set -e preserves baseline-failure rc and restores branch" \
  || fail "T7: errexit escaped before restoration: $(cat "$T7_EXIT_STATE" 2>/dev/null)"
grep -q "^- Verdict: ESCALATED$" "$QA_T7" \
  && ! grep -q "^- Verdict: PASS$" "$QA_T7" \
  && grep -q "HEAD exit 0; baseline exit 27" "$QA_T7" \
  && pass "T7: true set -e baseline failure writes ESCALATED, never PASS" \
  || fail "T7: true set -e baseline failure report missing or misleading"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "  ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[[ "$FAIL_COUNT" -eq 0 ]]
