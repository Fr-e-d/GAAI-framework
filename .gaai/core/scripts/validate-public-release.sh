#!/usr/bin/env bash
set -uo pipefail

############################################################
# Validate Public Release — GAAI
#
# Description:
#   Single deterministic entrypoint for public-release validation.
#   Runs, in fixed order: (1) health-check, (2) artefact-sync,
#   (3) every hermetic shell test discovered under
#   scripts/tests/*.sh, (4) every hermetic Node test discovered
#   under adapters/**/__tests__/*.test.js. Discovery is filesystem-
#   driven — no manifest, no expected count, no test framework.
#   Fails fast: the first failing check stops the run, preserves
#   its output and original exit code/signal, and reports the
#   next unstarted phase (and, if already discovered, the next
#   test path that would have run).
#
# Usage:
#   ./scripts/validate-public-release.sh [--core-dir <path>] [--project-dir <path>]
#
# Exit codes:
#   0 — all phases passed
#   non-zero — the failing phase's/test's original exit code
#              (or 128+signal if a test was killed by a signal)
############################################################

CORE_DIR=""
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --core-dir)    CORE_DIR="$2";    shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    *) >&2 echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Auto-detect if not specified (same convention as health-check.sh)
if [[ -z "$CORE_DIR" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
if [[ -z "$PROJECT_DIR" ]]; then
  if [[ -d "$CORE_DIR/../project" ]]; then
    PROJECT_DIR="$CORE_DIR/../project"
  else
    PROJECT_DIR="$CORE_DIR"  # v1.x flat layout
  fi
fi

TESTS_DIR="$CORE_DIR/scripts/tests"
ADAPTERS_DIR="$CORE_DIR/adapters"

echo ""
echo "GAAI Public Release Validation"
echo "  core:    $CORE_DIR"
echo "  project: $PROJECT_DIR"
echo "================================"

# Prints the fail-fast diagnostic block required by AC3/AC6: the exact
# path (if any) + reason, the next unstarted phase, and — only when
# discovery for the CURRENT phase already ran — the next test path that
# would have executed had the run continued.
fail_phase() {
  local phase="$1" reason="$2" next_phase="$3" next_path="${4:-}"
  echo ""
  echo "❌ FAILED: phase '$phase' — $reason"
  echo "   next unstarted phase: $next_phase"
  if [[ -n "$next_path" ]]; then
    echo "   next test path (not run): $next_path"
  fi
}

# Renders a raw exit status as either "exit N" or "terminated by signal N"
# (bash reports a signal-killed child as exit status 128+N).
describe_status() {
  local rc="$1"
  if (( rc > 128 )); then
    echo "terminated by signal $((rc - 128))"
  else
    echo "exit $rc"
  fi
}

# ---------------------------------------------------------------------------
# Phase 1: health-check
# ---------------------------------------------------------------------------
echo ""
echo "[ Phase 1/4: health-check ]"
bash "$CORE_DIR/scripts/health-check.sh" --core-dir "$CORE_DIR" --project-dir "$PROJECT_DIR"
rc=$?
if [[ $rc -ne 0 ]]; then
  fail_phase "health-check" "$(describe_status "$rc")" "artefact-sync"
  exit "$rc"
fi

# ---------------------------------------------------------------------------
# Phase 2: artefact-sync
# ---------------------------------------------------------------------------
echo ""
echo "[ Phase 2/4: artefact-sync ]"
bash "$CORE_DIR/scripts/artefact-sync.sh" --gaai-dir "$PROJECT_DIR"
rc=$?
if [[ $rc -ne 0 ]]; then
  fail_phase "artefact-sync" "$(describe_status "$rc")" "shell-tests"
  exit "$rc"
fi

# ---------------------------------------------------------------------------
# Phase 3: shell tests — every regular *.sh file immediately under
# scripts/tests/, lexical path order, run as executables.
# ---------------------------------------------------------------------------
echo ""
echo "[ Phase 3/4: shell tests ]"
FIND_OUT="$(mktemp)"
FIND_ERR="$(mktemp)"
find "$TESTS_DIR" -maxdepth 1 -type f -name '*.sh' >"$FIND_OUT" 2>"$FIND_ERR"
find_rc=$?
if [[ $find_rc -ne 0 ]]; then
  fail_phase "shell-tests" "cannot traverse/list $TESTS_DIR — $(cat "$FIND_ERR")" "node-tests"
  rm -f "$FIND_OUT" "$FIND_ERR"
  exit "$find_rc"
fi
sort "$FIND_OUT" -o "$FIND_OUT"
sort_rc=$?
if [[ $sort_rc -ne 0 ]]; then
  fail_phase "shell-tests" "cannot sort discovered test paths — $(describe_status "$sort_rc")" "node-tests"
  rm -f "$FIND_OUT" "$FIND_ERR"
  exit "$sort_rc"
fi
SHELL_TESTS=()
shell_total=0
while IFS= read -r path; do
  SHELL_TESTS[$shell_total]="$path"
  shell_total=$((shell_total + 1))
done < "$FIND_OUT"
rm -f "$FIND_OUT" "$FIND_ERR"

for ((i = 0; i < shell_total; i++)); do
  path="${SHELL_TESTS[$i]}"
  next_path=""
  if (( i + 1 < shell_total )); then
    next_path="${SHELL_TESTS[$((i + 1))]}"
  fi

  if [[ ! -x "$path" ]]; then
    fail_phase "shell-tests" "$path — not executable" "node-tests" "$next_path"
    exit 1
  fi

  "$path"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    fail_phase "shell-tests" "$path — $(describe_status "$rc")" "node-tests" "$next_path"
    exit "$rc"
  fi
  echo "  ✅ $path"
done

# ---------------------------------------------------------------------------
# Phase 4: Node tests — every *.test.js file under adapters/**/__tests__/,
# lexical path order, invoked directly via `node "$path"`.
# ---------------------------------------------------------------------------
echo ""
echo "[ Phase 4/4: node tests ]"
FIND_OUT="$(mktemp)"
FIND_ERR="$(mktemp)"
find "$ADAPTERS_DIR" -type f -path '*/__tests__/*.test.js' >"$FIND_OUT" 2>"$FIND_ERR"
find_rc=$?
if [[ $find_rc -ne 0 ]]; then
  fail_phase "node-tests" "cannot traverse/list $ADAPTERS_DIR — $(cat "$FIND_ERR")" "(none — final phase)"
  rm -f "$FIND_OUT" "$FIND_ERR"
  exit "$find_rc"
fi
sort "$FIND_OUT" -o "$FIND_OUT"
sort_rc=$?
if [[ $sort_rc -ne 0 ]]; then
  fail_phase "node-tests" "cannot sort discovered test paths — $(describe_status "$sort_rc")" \
    "(none — final phase)"
  rm -f "$FIND_OUT" "$FIND_ERR"
  exit "$sort_rc"
fi
NODE_TESTS=()
node_total=0
while IFS= read -r path; do
  NODE_TESTS[$node_total]="$path"
  node_total=$((node_total + 1))
done < "$FIND_OUT"
rm -f "$FIND_OUT" "$FIND_ERR"

for ((i = 0; i < node_total; i++)); do
  path="${NODE_TESTS[$i]}"
  next_path=""
  if (( i + 1 < node_total )); then
    next_path="${NODE_TESTS[$((i + 1))]}"
  fi

  node "$path"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    fail_phase "node-tests" "$path — $(describe_status "$rc")" "(none — final phase)" "$next_path"
    exit "$rc"
  fi
  echo "  ✅ $path"
done

echo ""
echo "================================"
echo "✅ Public release validation PASSED (health-check, artefact-sync, $shell_total shell tests, $node_total node tests)"
exit 0
