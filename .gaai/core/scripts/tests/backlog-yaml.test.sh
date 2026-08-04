#!/usr/bin/env bash
# backlog-yaml.test.sh — tests for lib/backlog-yaml.sh
#
# Exercises yq-present and yq-absent (Python fallback) paths against
# a fixture YAML containing quoted and unquoted status/phase_status variants.
#
# Usage: bash .gaai/core/scripts/tests/backlog-yaml.test.sh
# Exit 0 = all pass. Exit 1 = at least one failure.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
LIB="$SCRIPT_DIR/../lib/backlog-yaml.sh"

_TMPDIR="${TMPDIR:-/tmp}"
_TMPDIR="${_TMPDIR%/}"

FIXTURE="${_TMPDIR}/backlog-yaml.test.yaml"

# Bin directory used by T6 to make yq genuinely unresolvable — see T6.
YQLESS_BIN="${_TMPDIR}/backlog-yaml.test.yqless-bin"

cleanup() {
  rm -f "$FIXTURE"
  rm -rf "$YQLESS_BIN"
}
trap cleanup EXIT

cat > "$FIXTURE" << 'YAML_EOF'
items:
- id: TST-STATUS-UNQUOTED
  status: done
  phase_status: not_started
- id: TST-STATUS-SINGLE-QUOTED
  status: 'in_progress'
  phase_status: 'planned'
- id: TST-STATUS-DOUBLE-QUOTED
  status: "refined"
  phase_status: "impl_done"
- id: TST-STATUS-TRAILING-COMMENT
  status: done  # this is a comment
  phase_status: done
- id: TST-IN-PROGRESS-A
  status: in_progress
  phase_status: planned
- id: TST-IN-PROGRESS-B
  status: 'in_progress'
  phase_status: qa_failed
YAML_EOF

# ── Helper: run assertion in subshell, call pass/fail in main shell ─────
# Usage: assert "description" command [args...]
# The command must exit 0 on success.
assert() {
  local desc="$1"; shift
  if "$@" &>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

# ── T1-T5, T9, T10: yq-present path ─────────────────────────────────────

# Source lib for yq-present tests (main shell, then run tests in subshells)
(
  source "$LIB"

  # T1
  r=$(backlog_status "TST-STATUS-UNQUOTED" "$FIXTURE")
  [[ "$r" == "done" ]]
) && pass "T1 yq-present: backlog_status unquoted → done" || fail "T1 yq-present: backlog_status unquoted"

(
  source "$LIB"
  r=$(backlog_status "TST-STATUS-SINGLE-QUOTED" "$FIXTURE")
  [[ "$r" == "in_progress" ]]
) && pass "T2 yq-present: backlog_status single-quoted → in_progress" || fail "T2 yq-present: backlog_status single-quoted"

(
  source "$LIB"
  r=$(backlog_phase_status "TST-STATUS-DOUBLE-QUOTED" "$FIXTURE")
  [[ "$r" == "impl_done" ]]
) && pass "T3 yq-present: backlog_phase_status double-quoted → impl_done" || fail "T3 yq-present: backlog_phase_status double-quoted"

(
  source "$LIB"
  r=$(backlog_status "TST-STATUS-TRAILING-COMMENT" "$FIXTURE")
  [[ "$r" == "done" ]]
) && pass "T4 yq-present: backlog_status trailing comment → done" || fail "T4 yq-present: backlog_status trailing comment"

(
  source "$LIB"
  r=$(backlog_in_progress_ids "$FIXTURE")
  echo "$r" | grep -q "TST-IN-PROGRESS-A" && echo "$r" | grep -q "TST-IN-PROGRESS-B"
) && pass "T5 yq-present: backlog_in_progress_ids → both A and B found" || fail "T5 yq-present: backlog_in_progress_ids"

(
  source "$LIB"
  backlog_status "NONEXISTENT" "$FIXTURE"
  exit $?
) ; ec=$?
[[ $ec -eq 1 ]] && pass "T9 yq-present: nonexistent ID → exit 1" || fail "T9 yq-present: nonexistent ID exit code (got $ec)"

(
  source "$LIB"
  backlog_status "TST-STATUS-UNQUOTED" "/nonexistent/path.yaml"
  exit $?
) ; ec=$?
[[ $ec -eq 2 ]] && pass "T10 yq-present: unreadable file → exit 2" || fail "T10 yq-present: unreadable file exit code (got $ec)"

# ── T6-T8: yq-absent path (Python fallback) ─────────────────────────────

# T6: yq-absent advisory warning.
#
# PATH is narrowed to a fixture bin directory holding nothing but a python3
# symlink — the Python fallback's sole external dependency — so `command -v yq`
# genuinely resolves nothing, wherever the host happens to install yq.
#
# The previous form narrowed PATH to "/usr/bin:/bin:/usr/sbin:/sbin" on the
# assumption that this hides yq. That only holds where yq sits outside those
# directories (Homebrew's /opt/homebrew/bin on macOS). GitHub's ubuntu runners
# ship mikefarah yq at /usr/bin/yq, which the narrowed PATH still resolved, so
# the lib reported yq-present, emitted no advisory, and the assertion failed —
# passing on every developer's Mac and failing in CI.
mkdir -p "$YQLESS_BIN"
ln -sf "$(command -v python3)" "$YQLESS_BIN/python3"

output=$(
  export PATH="$YQLESS_BIN"
  unset _BACKLOG_YQ_AVAILABLE
  source "$LIB"
  backlog_status "TST-STATUS-UNQUOTED" "$FIXTURE" 2>&1 >/dev/null
)
echo "$output" | grep -q "yq unavailable" \
  && pass "T6 yq-absent: advisory warning logged" \
  || fail "T6 yq-absent: advisory warning (got '$output')"

# T7: backlog_status single-quoted via Python fallback
(
  source "$LIB"
  _BACKLOG_YQ_AVAILABLE="no"
  r=$(backlog_status "TST-STATUS-SINGLE-QUOTED" "$FIXTURE")
  [[ "$r" == "in_progress" ]]
) && pass "T7 yq-absent: backlog_status single-quoted → in_progress" || fail "T7 yq-absent: backlog_status single-quoted"

# T8: backlog_in_progress_ids via Python fallback
(
  source "$LIB"
  _BACKLOG_YQ_AVAILABLE="no"
  r=$(backlog_in_progress_ids "$FIXTURE")
  echo "$r" | grep -q "TST-IN-PROGRESS-A" && echo "$r" | grep -q "TST-IN-PROGRESS-B"
) && pass "T8 yq-absent: backlog_in_progress_ids → both A and B found" || fail "T8 yq-absent: backlog_in_progress_ids"

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
