#!/usr/bin/env bash
# tests-executable-bit-guard.test.sh — contract test for
# hooks/pre-push.d/17-tests-executable-bit.sh
#
# The guard blocks a push when a scripts/tests/*.sh is staged at mode 100644,
# because validate-public-release.sh invokes those files as executables and
# fails the whole shell-tests phase on discovery when one is not.
#
# Hermetic: builds a throwaway git repo, never touches the host repo.
#
# Usage: bash .gaai/core/scripts/tests/tests-executable-bit-guard.test.sh
# Exit 0 = all pass.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GUARD="$SCRIPT_DIR/../../hooks/pre-push.d/17-tests-executable-bit.sh"

_TMPDIR="${TMPDIR:-/tmp}"; _TMPDIR="${_TMPDIR%/}"
FIXTURE="${_TMPDIR}/gaai-execbit-guard-test-$$"
cleanup() { rm -rf "$FIXTURE"; }
trap cleanup EXIT

echo "=== executable-bit guard ==="

if [[ ! -x "$GUARD" ]]; then
  fail "T0: guard not found or not executable at $GUARD"
  echo ""; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi
pass "T0: guard present and executable"

# ── fixture: a repo with the same tests/ layout ───────────────────────────────
mkdir -p "$FIXTURE/.gaai/core/scripts/tests"
git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" config user.email "test@gaai.local"
git -C "$FIXTURE" config user.name "GAAI Test"

printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE/.gaai/core/scripts/tests/ok.test.sh"
chmod +x "$FIXTURE/.gaai/core/scripts/tests/ok.test.sh"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit -q -m "initial"

run_guard() { ( cd "$FIXTURE" && "$GUARD" </dev/null >/dev/null 2>&1 ); echo $?; }

# T1: every test executable → allow
[[ "$(run_guard)" -eq 0 ]] \
  && pass "T1: all-executable tree exits 0" \
  || fail "T1: all-executable tree should exit 0"

# T2: a test staged at 100644 → block
printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE/.gaai/core/scripts/tests/bad.test.sh"
git -C "$FIXTURE" add .gaai/core/scripts/tests/bad.test.sh
git -C "$FIXTURE" update-index --chmod=-x .gaai/core/scripts/tests/bad.test.sh
[[ "$(run_guard)" -eq 1 ]] \
  && pass "T2: non-executable staged test exits 1" \
  || fail "T2: non-executable staged test should exit 1"

# T3: the message names the offending file
out=$( cd "$FIXTURE" && "$GUARD" </dev/null 2>&1 >/dev/null )
echo "$out" | grep -q "bad.test.sh" \
  && pass "T3: diagnostic names the offending file" \
  || fail "T3: diagnostic does not name the offending file (got: $out)"

# T4: index mode is authoritative, not the filesystem bit
chmod +x "$FIXTURE/.gaai/core/scripts/tests/bad.test.sh"
[[ "$(run_guard)" -eq 1 ]] \
  && pass "T4: still blocks when executable on disk but staged 100644" \
  || fail "T4: should read the index, not the filesystem"

# T5: fixing the index mode unblocks
git -C "$FIXTURE" update-index --chmod=+x .gaai/core/scripts/tests/bad.test.sh
[[ "$(run_guard)" -eq 0 ]] \
  && pass "T5: exits 0 once the index mode is corrected" \
  || fail "T5: should exit 0 after update-index --chmod=+x"

# T6: non-test files in the tree are out of scope
printf 'not a test\n' > "$FIXTURE/.gaai/core/scripts/tests/README.md"
git -C "$FIXTURE" add .gaai/core/scripts/tests/README.md
[[ "$(run_guard)" -eq 0 ]] \
  && pass "T6: non-*.sh files are ignored" \
  || fail "T6: non-*.sh files must not trip the guard"

# T7: a repo without the tests directory is a no-op
BARE="${FIXTURE}-bare"; mkdir -p "$BARE"; git -C "$BARE" init -q -b main
rc=$( cd "$BARE" && "$GUARD" </dev/null >/dev/null 2>&1; echo $? )
rm -rf "$BARE"
[[ "$rc" -eq 0 ]] \
  && pass "T7: repo without scripts/tests/ exits 0" \
  || fail "T7: repo without scripts/tests/ should exit 0 (got $rc)"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
