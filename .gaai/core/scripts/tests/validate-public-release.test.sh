#!/usr/bin/env bash
# ── validate-public-release.test.sh ─────────────────────────────────────────
# Hermetic contract test for validate-public-release.sh (E1095S01).
#
# Builds throwaway mktemp -d sandboxes containing a minimal-but-passing
# `.gaai/core` (satisfies health-check.sh) and `.gaai/project` (satisfies
# artefact-sync.sh), copies the real health-check.sh / artefact-sync.sh /
# validate-public-release.sh into the sandbox core, then plants fixture
# shell/Node tests and invokes the entrypoint as a real subprocess (never
# sourced — the ordering/fail-fast guarantees are process-level).
#
# Covers AC2 (discovery exactly-once, lexical/empty corpora, non-test files ignored, exit 0 only
# when everything passes), AC3 (failing test / non-executable / Node
# failure / traversal-failure diagnostics), AC6 (fail-fast determinism:
# first failure stops the run, reports next unstarted phase + next known
# test path, no later check executes), and binds the copied validator to the
# exact Bash interpreter that launched this contract test.
#
# Run: bash .gaai/core/scripts/tests/validate-public-release.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_CORE="$(cd "$SCRIPT_DIR/../.." && pwd)"   # .../.gaai/core
unset VALIDATOR_INTERPRETER_LOG

declare -a TMP_DIRS=()
cleanup_all() {
  local d
  for d in "${TMP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup_all EXIT

# Builds a sandbox .gaai/core that health-check.sh reports PASSED on, with
# the real gate scripts under test copied in (so validate-public-release.sh
# invokes the *shipped* health-check.sh / artefact-sync.sh, not a stub).
build_passing_core() {
  local core="$1"
  mkdir -p "$core"/agents "$core"/skills "$core"/contexts/rules "$core"/workflows \
           "$core"/scripts/tests "$core"/compat "$core"/adapters
  : > "$core/GAAI.md"
  : > "$core/README.md"
  : > "$core/QUICK-REFERENCE.md"
  echo "1.0.0" > "$core/VERSION"
  : > "$core/agents/discovery.agent.md"
  : > "$core/agents/bootstrap.agent.md"
  for r in orchestration skills artefacts backlog memory context-discovery; do
    : > "$core/contexts/rules/$r.rules.md"
  done
  cp "$REAL_CORE/scripts/health-check.sh" "$core/scripts/health-check.sh"
  cp "$REAL_CORE/scripts/artefact-sync.sh" "$core/scripts/artefact-sync.sh"
  cp "$REAL_CORE/scripts/validate-public-release.sh" "$core/scripts/validate-public-release.sh"
  chmod +x "$core/scripts/health-check.sh" "$core/scripts/artefact-sync.sh" "$core/scripts/validate-public-release.sh"
}

# Builds a sandbox .gaai/project that artefact-sync.sh reports PASSED on.
build_passing_project() {
  local proj="$1"
  mkdir -p "$proj"/contexts/memory "$proj"/contexts/backlog "$proj"/contexts/artefacts
  for f in active blocked _template; do
    echo "items: []" > "$proj/contexts/backlog/$f.backlog.yaml"
  done
}

new_sandbox() {
  local tmp; tmp="$(mktemp -d)"
  TMP_DIRS+=("$tmp")
  echo "$tmp"
}

# The copied production entrypoint must run through this test's exact current
# interpreter. Calling it via its shebang would allow PATH to select a different
# Bash and turn the dual-shell matrix into a false positive.
run_validator() {
  local core="$1" proj="$2"
  if [[ -n "${VALIDATOR_INTERPRETER_LOG:-}" ]]; then
    "$BASH" -c '
      printf "%s|%s\n" "$BASH" "$BASH_VERSION" >> "$VALIDATOR_INTERPRETER_LOG"
      exec "$BASH" "$@"
    ' validator-interpreter-probe "$core/scripts/validate-public-release.sh" \
      --core-dir "$core" --project-dir "$proj"
    return $?
  fi
  "$BASH" "$core/scripts/validate-public-release.sh" \
    --core-dir "$core" --project-dir "$proj"
}

# ---------------------------------------------------------------------------
# K/L — explicit empty corpora + proof that the copied validator is bound to
# the exact Bash interpreter running this test.
# ---------------------------------------------------------------------------
scenario_empty_corpora_and_interpreter_binding() {
  local tmp core proj out rc interpreter_log expected actual
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"

  interpreter_log="$tmp/interpreter.log"
  : > "$interpreter_log"
  out="$(
    export VALIDATOR_INTERPRETER_LOG="$interpreter_log"
    run_validator "$core" "$proj" 2>&1
  )"; rc=$?
  [[ "$rc" -eq 0 ]] \
    && pass "K: empty shell and Node corpora exit 0 under current Bash" \
    || fail "K: empty corpora expected exit 0, got $rc — $out"
  echo "$out" | grep -q "0 shell tests, 0 node tests" \
    && pass "K: empty corpus final counts remain 0/0" \
    || fail "K: empty corpus final counts missing — $out"

  expected="$BASH|$BASH_VERSION"
  actual="$(cat "$interpreter_log" 2>/dev/null)"
  [[ "$actual" == "$expected" ]] \
    && pass "L: copied validator executed through exact current \$BASH ($BASH_VERSION)" \
    || fail "L: validator interpreter mismatch: expected '$expected', got '$actual'"
}

# ---------------------------------------------------------------------------
# A/B — happy path: exactly-once discovery, non-matching entries ignored.
# ---------------------------------------------------------------------------
scenario_happy_path_and_discovery() {
  local tmp core proj marker out rc lines
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"

  marker="$tmp/marker.txt"; : > "$marker"
  export MARKER_FILE="$marker"

  cat > "$core/scripts/tests/aaa-fixture.sh" <<'EOF'
#!/usr/bin/env bash
echo "shell:aaa" >> "$MARKER_FILE"
exit 0
EOF
  chmod +x "$core/scripts/tests/aaa-fixture.sh"

  mkdir -p "$core/adapters/demo/__tests__"
  cat > "$core/adapters/demo/__tests__/aaa.test.js" <<'EOF'
require("fs").appendFileSync(process.env.MARKER_FILE, "node:aaa\n");
process.exit(0);
EOF

  # Poison / decoy entries — must never execute:
  # subdir under scripts/tests/ (excluded by -maxdepth 1)
  mkdir -p "$core/scripts/tests/helpers"
  cat > "$core/scripts/tests/helpers/poison.sh" <<'EOF'
#!/usr/bin/env bash
echo "shell:poison-subdir" >> "$MARKER_FILE"
exit 0
EOF
  chmod +x "$core/scripts/tests/helpers/poison.sh"
  # non-.sh file directly under scripts/tests/
  echo "not a test" > "$core/scripts/tests/notes.md"
  # .js file under adapters/ but NOT inside __tests__/ (excluded by path pattern)
  cat > "$core/adapters/demo/helper.fixture.js" <<'EOF'
require("fs").appendFileSync(process.env.MARKER_FILE, "node:poison-not-in-tests-dir\n");
EOF
  # non-.test.js file inside __tests__/ (excluded by name pattern)
  echo "not a test" > "$core/adapters/demo/__tests__/readme.md"

  out="$(run_validator "$core" "$proj" 2>&1)"; rc=$?

  [[ $rc -eq 0 ]] && pass "A: happy path exits 0" || fail "A: happy path expected exit 0, got $rc — $out"
  if grep -qx "shell:aaa" "$marker" 2>/dev/null && grep -qx "node:aaa" "$marker" 2>/dev/null; then
    pass "A: both real fixtures executed"
  else
    fail "A: expected fixtures missing from marker: $(cat "$marker" 2>/dev/null)"
  fi
  lines=$(wc -l < "$marker" | tr -d ' ')
  [[ "$lines" == "2" ]] && pass "B: exactly 2 marker lines — decoys never ran, no double-count" \
    || fail "B: expected exactly 2 marker lines, got $lines: $(cat "$marker" 2>/dev/null)"

  unset MARKER_FILE
}

# ---------------------------------------------------------------------------
# C — AC3: non-executable matched shell test.
# ---------------------------------------------------------------------------
scenario_non_executable() {
  local tmp core proj marker out rc
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"

  marker="$tmp/marker.txt"; : > "$marker"
  export MARKER_FILE="$marker"

  cat > "$core/scripts/tests/broken.sh" <<'EOF'
#!/usr/bin/env bash
echo "shell:broken-should-not-run" >> "$MARKER_FILE"
exit 0
EOF
  chmod -x "$core/scripts/tests/broken.sh"

  mkdir -p "$core/adapters/demo/__tests__"
  cat > "$core/adapters/demo/__tests__/zzz.test.js" <<'EOF'
require("fs").appendFileSync(process.env.MARKER_FILE, "node:should-not-run\n");
process.exit(0);
EOF

  out="$(run_validator "$core" "$proj" 2>&1)"; rc=$?

  [[ $rc -ne 0 ]] && pass "C: non-executable fixture → non-zero exit" || fail "C: expected non-zero exit, got 0"
  if echo "$out" | grep -qF "$core/scripts/tests/broken.sh" && echo "$out" | grep -q "not executable"; then
    pass "C: exact path + 'not executable' reported"
  else
    fail "C: expected path + 'not executable' in output — got: $out"
  fi
  [[ ! -s "$marker" ]] && pass "C: no fixture executed (fail-fast before any test runs)" \
    || fail "C: marker unexpectedly non-empty: $(cat "$marker")"

  unset MARKER_FILE
}

# ---------------------------------------------------------------------------
# D — AC3 + AC6: shell test failure mid-phase; next-path + next-phase report.
# ---------------------------------------------------------------------------
scenario_shell_failure_fail_fast() {
  local tmp core proj marker out rc
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"

  marker="$tmp/marker.txt"; : > "$marker"
  export MARKER_FILE="$marker"

  cat > "$core/scripts/tests/a-pass.sh" <<'EOF'
#!/usr/bin/env bash
echo "shell:a-pass" >> "$MARKER_FILE"
exit 0
EOF
  cat > "$core/scripts/tests/b-fail.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  cat > "$core/scripts/tests/c-should-not-run.sh" <<'EOF'
#!/usr/bin/env bash
echo "shell:c-should-not-run" >> "$MARKER_FILE"
exit 0
EOF
  chmod +x "$core/scripts/tests/a-pass.sh" "$core/scripts/tests/b-fail.sh" "$core/scripts/tests/c-should-not-run.sh"

  mkdir -p "$core/adapters/demo/__tests__"
  cat > "$core/adapters/demo/__tests__/zzz.test.js" <<'EOF'
require("fs").appendFileSync(process.env.MARKER_FILE, "node:should-not-run\n");
process.exit(0);
EOF

  out="$(run_validator "$core" "$proj" 2>&1)"; rc=$?

  [[ $rc -eq 1 ]] && pass "D: b-fail.sh exit 1 propagates as entrypoint exit 1" || fail "D: expected exit 1, got $rc"
  if echo "$out" | grep -qF "$core/scripts/tests/b-fail.sh" && echo "$out" | grep -q "exit 1"; then
    pass "D: exact failing path + exit code reported"
  else
    fail "D: missing failing-path diagnostic — got: $out"
  fi
  echo "$out" | grep -qF "next test path (not run): $core/scripts/tests/c-should-not-run.sh" \
    && pass "D: next known test path (c-should-not-run.sh) reported" \
    || fail "D: next-test-path report missing/wrong — got: $out"
  echo "$out" | grep -q "next unstarted phase: node-tests" \
    && pass "D: next unstarted phase (node-tests) reported" \
    || fail "D: next-phase report missing/wrong — got: $out"
  if grep -qx "shell:a-pass" "$marker" 2>/dev/null && [[ "$(wc -l < "$marker" | tr -d ' ')" == "1" ]]; then
    pass "D: a-pass ran, c-should-not-run and node fixture never ran"
  else
    fail "D: unexpected marker content: $(cat "$marker" 2>/dev/null)"
  fi

  unset MARKER_FILE
}

# ---------------------------------------------------------------------------
# E — AC3: shell test killed by signal → reported as signal, not exit code.
# ---------------------------------------------------------------------------
scenario_shell_signal() {
  local tmp core proj out rc
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"

  cat > "$core/scripts/tests/self-kill.sh" <<'EOF'
#!/usr/bin/env bash
kill -9 $$
EOF
  chmod +x "$core/scripts/tests/self-kill.sh"

  out="$(run_validator "$core" "$proj" 2>&1)"; rc=$?

  [[ $rc -eq 137 ]] && pass "E: signal-killed fixture propagates rc=137 (128+9)" || fail "E: expected rc=137, got $rc"
  echo "$out" | grep -q "terminated by signal 9" \
    && pass "E: reported as 'terminated by signal 9', not a bogus exit code" \
    || fail "E: signal not reported correctly — got: $out"
}

# ---------------------------------------------------------------------------
# F — AC3: scripts/tests/ cannot be traversed/listed (permission denied).
# ---------------------------------------------------------------------------
scenario_tests_dir_unreadable() {
  local tmp core proj out rc
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"

  chmod 000 "$core/scripts/tests"
  out="$(run_validator "$core" "$proj" 2>&1)"; rc=$?
  chmod 755 "$core/scripts/tests"   # restore so sandbox cleanup can proceed

  [[ $rc -ne 0 ]] && pass "F: unreadable scripts/tests/ → non-zero exit" || fail "F: expected non-zero exit, got 0"
  if echo "$out" | grep -q "cannot traverse/list" && echo "$out" | grep -qF "$core/scripts/tests"; then
    pass "F: traversal-failure reason + directory path reported"
  else
    fail "F: expected traversal-failure diagnostic — got: $out"
  fi
}

# ---------------------------------------------------------------------------
# G — AC6: adapters/ missing entirely → node-tests traversal failure, final
# phase (no "next unstarted phase" to name).
# ---------------------------------------------------------------------------
scenario_adapters_dir_missing() {
  local tmp core proj out rc
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"
  rm -rf "$core/adapters"

  out="$(run_validator "$core" "$proj" 2>&1)"; rc=$?

  [[ $rc -ne 0 ]] && pass "G: missing adapters/ → non-zero exit" || fail "G: expected non-zero exit, got 0"
  if echo "$out" | grep -q "cannot traverse/list" && echo "$out" | grep -qF "$core/adapters"; then
    pass "G: adapters traversal-failure reason + path reported"
  else
    fail "G: expected traversal-failure diagnostic — got: $out"
  fi
}

# ---------------------------------------------------------------------------
# H — AC6: phase 1 (health-check) failure stops everything before phase 3/4
# even runs discovery; no phantom "next test path".
# ---------------------------------------------------------------------------
scenario_phase1_failure_stops_everything() {
  local tmp core proj marker out rc
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"
  rm -f "$core/VERSION"   # breaks health-check.sh's VERSION-exists check

  marker="$tmp/marker.txt"; : > "$marker"
  export MARKER_FILE="$marker"
  cat > "$core/scripts/tests/should-not-run.sh" <<'EOF'
#!/usr/bin/env bash
echo "shell:should-not-run" >> "$MARKER_FILE"
exit 0
EOF
  chmod +x "$core/scripts/tests/should-not-run.sh"

  out="$(run_validator "$core" "$proj" 2>&1)"; rc=$?

  [[ $rc -ne 0 ]] && pass "H: health-check failure → non-zero exit" || fail "H: expected non-zero exit, got 0"
  echo "$out" | grep -q "next unstarted phase: artefact-sync" \
    && pass "H: reports next unstarted phase artefact-sync" \
    || fail "H: missing next-phase report — got: $out"
  echo "$out" | grep -q "next test path" \
    && fail "H: unexpectedly reported a next test path (discovery never ran) — got: $out" \
    || pass "H: no phantom next-test-path (discovery correctly never ran)"
  [[ ! -s "$marker" ]] && pass "H: no shell test executed (fail-fast before phase 3)" \
    || fail "H: marker unexpectedly written: $(cat "$marker")"

  unset MARKER_FILE
}

# ---------------------------------------------------------------------------
# I — AC1: shell and Node fixtures execute in lexical path order.
# ---------------------------------------------------------------------------
scenario_lexical_order() {
  local tmp core proj marker n rc actual
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"

  marker="$tmp/marker.txt"; : > "$marker"
  export MARKER_FILE="$marker"
  for n in c b a; do
    cat > "$core/scripts/tests/${n}-fixture.sh" <<EOF
#!/usr/bin/env bash
echo "shell:${n}" >> "\$MARKER_FILE"
exit 0
EOF
    chmod +x "$core/scripts/tests/${n}-fixture.sh"
  done
  mkdir -p "$core/adapters/demo/__tests__"
  for n in c b a; do
    cat > "$core/adapters/demo/__tests__/${n}-fixture.test.js" <<EOF
require("fs").appendFileSync(process.env.MARKER_FILE, "node:${n}\\n");
process.exit(0);
EOF
  done

  run_validator "$core" "$proj" >/dev/null 2>&1
  rc=$?
  [[ $rc -eq 0 ]] || fail "I: expected clean pass, got exit $rc"
  actual="$(tr '\n' ',' < "$marker")"
  [[ "$actual" == "shell:a,shell:b,shell:c,node:a,node:b,node:c," ]] \
    && pass "I: shell and Node fixtures executed in lexical phase/path order" \
    || fail "I: expected lexical shell a,b,c then Node a,b,c — got: $actual"

  unset MARKER_FILE
}

# ---------------------------------------------------------------------------
# J — AC3 + AC6: Node invocation failure, exact exit code propagation, next
# known test path within the (final) node-tests phase.
# ---------------------------------------------------------------------------
scenario_node_failure_fail_fast() {
  local tmp core proj marker out rc
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"

  marker="$tmp/marker.txt"; : > "$marker"
  export MARKER_FILE="$marker"
  mkdir -p "$core/adapters/demo/__tests__"
  cat > "$core/adapters/demo/__tests__/a-pass.test.js" <<'EOF'
require("fs").appendFileSync(process.env.MARKER_FILE, "node:a-pass\n");
process.exit(0);
EOF
  cat > "$core/adapters/demo/__tests__/b-fail.test.js" <<'EOF'
process.exit(3);
EOF
  cat > "$core/adapters/demo/__tests__/c-should-not-run.test.js" <<'EOF'
require("fs").appendFileSync(process.env.MARKER_FILE, "node:c-should-not-run\n");
process.exit(0);
EOF

  out="$(run_validator "$core" "$proj" 2>&1)"; rc=$?

  [[ $rc -eq 3 ]] && pass "J: node fixture exit 3 propagates as entrypoint exit 3" || fail "J: expected exit 3, got $rc"
  if echo "$out" | grep -qF "$core/adapters/demo/__tests__/b-fail.test.js" && echo "$out" | grep -q "exit 3"; then
    pass "J: exact failing Node path + exit code reported"
  else
    fail "J: missing failing-path diagnostic — got: $out"
  fi
  echo "$out" | grep -qF "next test path (not run): $core/adapters/demo/__tests__/c-should-not-run.test.js" \
    && pass "J: next known test path (c-should-not-run.test.js) reported" \
    || fail "J: next-test-path report missing/wrong — got: $out"
  echo "$out" | grep -q "next unstarted phase: (none — final phase)" \
    && pass "J: final-phase 'no next phase' reported" \
    || fail "J: final-phase report missing/wrong — got: $out"
  if grep -qx "node:a-pass" "$marker" 2>/dev/null && [[ "$(wc -l < "$marker" | tr -d ' ')" == "1" ]]; then
    pass "J: a-pass ran, c-should-not-run never ran"
  else
    fail "J: unexpected marker content: $(cat "$marker" 2>/dev/null)"
  fi

  unset MARKER_FILE
}

# ---------------------------------------------------------------------------
# M — Node test killed by signal retains the signal-derived status.
# ---------------------------------------------------------------------------
scenario_node_signal() {
  local tmp core proj out rc path
  tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
  build_passing_core "$core"; build_passing_project "$proj"

  mkdir -p "$core/adapters/demo/__tests__"
  path="$core/adapters/demo/__tests__/self-kill.test.js"
  cat > "$path" <<'EOF'
process.kill(process.pid, "SIGKILL");
EOF

  out="$(run_validator "$core" "$proj" 2>&1)"; rc=$?
  [[ "$rc" -eq 137 ]] \
    && pass "M: signal-killed Node fixture propagates rc=137" \
    || fail "M: expected Node signal rc=137, got $rc"
  echo "$out" | grep -qF "$path" && echo "$out" | grep -q "terminated by signal 9" \
    && pass "M: Node signal diagnostic retains path and signal 9" \
    || fail "M: Node signal diagnostic missing/wrong — $out"
}

install_sort_fault_stub() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/sort" <<'EOF'
#!/bin/sh
input="${1:-}"
if [ -f "$input" ]; then
  case "${SORT_FAULT_MODE:-}" in
    shell)
      if grep -q '/scripts/tests/.*\.sh$' "$input"; then
        printf '%s\n' "$input" >> "$SORT_TARGET_LOG"
        exit 41
      fi
      ;;
    node)
      if grep -q '/adapters/.*/__tests__/.*\.test\.js$' "$input"; then
        printf '%s\n' "$input" >> "$SORT_TARGET_LOG"
        kill -9 "$$"
        exit 99
      fi
      ;;
  esac
fi
exec "$REAL_SORT_PATH" "$@"
EOF
  chmod +x "$bin_dir/sort"
}

# ---------------------------------------------------------------------------
# N/O — sort failures are phase infrastructure failures, preserve status or
# signal, clean discovery files and start no test in the affected/later phase.
# ---------------------------------------------------------------------------
scenario_sort_failures() {
  local mode tmp core proj marker out rc stub_bin sort_log sort_target
  local real_sort
  real_sort="$(PATH=/usr/bin:/bin command -v sort)"

  for mode in shell node; do
    tmp="$(new_sandbox)"; core="$tmp/core"; proj="$tmp/project"
    build_passing_core "$core"; build_passing_project "$proj"
    marker="$tmp/marker.txt"; : > "$marker"
    stub_bin="$tmp/bin"; sort_log="$tmp/sort-target.log"; : > "$sort_log"
    install_sort_fault_stub "$stub_bin"

    cat > "$core/scripts/tests/a-shell.sh" <<'EOF'
#!/usr/bin/env bash
echo "shell-ran" >> "$MARKER_FILE"
EOF
    chmod +x "$core/scripts/tests/a-shell.sh"
    mkdir -p "$core/adapters/demo/__tests__"
    cat > "$core/adapters/demo/__tests__/a-node.test.js" <<'EOF'
require("fs").appendFileSync(process.env.MARKER_FILE, "node-ran\n");
EOF

    out="$(
      export PATH="$stub_bin:$PATH" SORT_FAULT_MODE="$mode"
      export SORT_TARGET_LOG="$sort_log" REAL_SORT_PATH="$real_sort" MARKER_FILE="$marker"
      run_validator "$core" "$proj" 2>&1
    )"; rc=$?
    sort_target="$(cat "$sort_log" 2>/dev/null)"

    if [[ "$mode" == "shell" ]]; then
      [[ "$rc" -eq 41 ]] \
        && pass "N: shell discovery sort exit 41 propagates unchanged" \
        || fail "N: shell sort expected rc=41, got $rc"
      echo "$out" | grep -q "phase 'shell-tests'" \
        && echo "$out" | grep -q "cannot sort discovered test paths — exit 41" \
        && pass "N: shell sort failure has generic phase/status diagnostic" \
        || fail "N: shell sort diagnostic missing/wrong — $out"
      [[ ! -s "$marker" ]] \
        && pass "N: shell sort failure starts no shell or Node test" \
        || fail "N: a test ran after shell sort failure: $(cat "$marker")"
    else
      [[ "$rc" -eq 137 ]] \
        && pass "O: Node discovery sort signal 9 propagates as rc=137" \
        || fail "O: Node sort expected rc=137, got $rc"
      echo "$out" | grep -q "phase 'node-tests'" \
        && echo "$out" | grep -q "cannot sort discovered test paths — terminated by signal 9" \
        && pass "O: Node sort failure has generic phase/signal diagnostic" \
        || fail "O: Node sort diagnostic missing/wrong — $out"
      [[ "$(cat "$marker" 2>/dev/null)" == "shell-ran" ]] \
        && pass "O: Node sort failure starts no Node test or later work" \
        || fail "O: Node sort failure execution boundary changed: $(cat "$marker" 2>/dev/null)"
    fi

    [[ -n "$sort_target" && ! -e "$sort_target" ]] \
      && pass "${mode}: failed sort discovery tempfile is cleaned" \
      || fail "${mode}: failed sort discovery tempfile leaked or was not observed"
  done
}

# ---------------------------------------------------------------------------
echo "GAAI validate-public-release.sh — hermetic contract test"
echo "=========================================================="
echo ""
echo "=== K/L: empty corpora + exact current-Bash interpreter binding ==="
scenario_empty_corpora_and_interpreter_binding
echo ""
echo "=== A/B: happy path + exactly-once discovery (ignores non-matching entries) ==="
scenario_happy_path_and_discovery
echo ""
echo "=== C: non-executable matched shell test (AC3) ==="
scenario_non_executable
echo ""
echo "=== D: shell test failure — fail-fast + next-path/next-phase report (AC3+AC6) ==="
scenario_shell_failure_fail_fast
echo ""
echo "=== E: shell test killed by signal (AC3) ==="
scenario_shell_signal
echo ""
echo "=== F: scripts/tests/ unreadable — traversal failure (AC3) ==="
scenario_tests_dir_unreadable
echo ""
echo "=== G: adapters/ missing — traversal failure, final phase (AC3+AC6) ==="
scenario_adapters_dir_missing
echo ""
echo "=== H: phase 1 (health-check) failure stops everything (AC6) ==="
scenario_phase1_failure_stops_everything
echo ""
echo "=== I: lexical path ordering (AC1) ==="
scenario_lexical_order
echo ""
echo "=== J: Node invocation failure — fail-fast + next-path report (AC3+AC6) ==="
scenario_node_failure_fail_fast
echo ""
echo "=== M: Node test killed by signal (AC3) ==="
scenario_node_signal
echo ""
echo "=== N/O: shell and Node discovery sort failures ==="
scenario_sort_failures

echo ""
echo "=========================================================="
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "❌ validate-public-release.sh contract test FAILED"
  exit 1
else
  echo "✅ validate-public-release.sh contract test PASSED"
  exit 0
fi
