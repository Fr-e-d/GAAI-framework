#!/usr/bin/env bash
# daemon-coordination-home.test.sh — AC6 sandbox tests for E1003S03 + E1003S06
#
# Covers (E1003S03):
#   TC1: coordination push from gaai-daemon-home lands on origin/staging (AC6a)
#   TC2: dirty / branch-switched main checkout is INERT to daemon (AC6b — main-checkout-decoupled proof)
#   TC3: completeness backstop — zero coordination push sites lack HEAD: refspec (AC6c)
#   TC4: home is on gaai-daemon-home; main checkout's staging ref never modified (AC6d)
#
# Covers (E1003S06 — daemon-process provisioner loading):
#   TC5: _gaai_provision_daemon_home is defined in the daemon's OWN process, not inherited (AC1)
#   TC6: wrong-branch home is repaired at the current target tip via the in-process provisioner (AC2)
#   TC7: daemon startup fails closed, without leaking, when the capability is unavailable (AC3)
#   TC8: direct mode (GAAI_DAEMON_HOME unset) stays inert — no git side effects (AC4)
#   TC9: static neutrality guard rails — single SCRIPT_DIR-relative source, no product token (AC5)
#
# Usage: bash .gaai/core/scripts/tests/daemon-coordination-home.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
DAEMON_HOME_LIB="$SCRIPTS_DIR/lib/daemon-home.sh"

if [[ ! -f "$DAEMON_HOME_LIB" ]]; then
  echo "ERROR: daemon-home lib not found at $DAEMON_HOME_LIB"
  exit 1
fi

# Source the provisioner under test
# shellcheck source=../lib/daemon-home.sh
source "$DAEMON_HOME_LIB"

# Resolve to physical path — git canonicalises worktree paths via realpath()
# so /tmp (macOS symlink → /private/tmp) would cause grep mismatches.
_FIXTURE_RAW="/tmp/gaai-coord-home-test-$$"
mkdir -p "$_FIXTURE_RAW"
FIXTURE_DIR="$(cd "$_FIXTURE_RAW" && pwd -P 2>/dev/null || echo "$_FIXTURE_RAW")"

cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

# Sets up a bare remote + local clone with one commit on 'staging'.
# Clone's main checkout is left on 'staging'.
# The bare remote is at "${project_dir}_remote.git"; the clone's origin points there.
setup_git_repo() {
  local project_dir="$1"
  local remote_dir="${project_dir}_remote.git"
  rm -rf "$project_dir" "$remote_dir"
  git init --bare "$remote_dir" -q
  git clone "$remote_dir" "$project_dir" -q
  git -C "$project_dir" config user.email "test@gaai.local"
  git -C "$project_dir" config user.name "GAAI Test"
  git -C "$project_dir" checkout -b staging -q
  touch "$project_dir/.keep"
  git -C "$project_dir" add .
  git -C "$project_dir" commit -m "initial" -q
  git -C "$project_dir" push origin staging -q
}

# ═══════════════════════════════════════════════════════════════════════════════
# TC1: coordination push from gaai-daemon-home lands on origin/staging (AC6a)
# ═══════════════════════════════════════════════════════════════════════════════
# Structure: bare_remote ← origin ← main checkout (TC1_DIR) ← worktree (TC1_HOME)
# Push from home uses "push origin HEAD:staging" (same refspec as post-flip daemon).
# Verifies the bare remote's staging tip == home HEAD.
echo ""
echo "=== TC1: coordination push from gaai-daemon-home lands on origin/staging ==="

TC1_DIR="$FIXTURE_DIR/tc1-project"
TC1_HOME="$FIXTURE_DIR/tc1-home"
TC1_BARE="${TC1_DIR}_remote.git"
setup_git_repo "$TC1_DIR"

_gaai_provision_daemon_home "$TC1_HOME" "staging" "$TC1_DIR" >/dev/null 2>&1

# Make a coordination commit in the home (mirroring daemon chore-commit)
touch "$TC1_HOME/coord.txt"
git -C "$TC1_HOME" add coord.txt
git -C "$TC1_HOME" config user.email "test@gaai.local"
git -C "$TC1_HOME" config user.name "GAAI Test"
git -C "$TC1_HOME" commit -m "coord-commit-from-home" -q

TC1_HOME_HEAD="$(git -C "$TC1_HOME" rev-parse HEAD 2>/dev/null || echo "?")"

# Push via origin with explicit HEAD:staging refspec — the post-flip coordination pattern.
# The home is on gaai-daemon-home; "HEAD:staging" pushes HEAD to origin's staging ref.
TC1_PUSH_RC=0
git -C "$TC1_HOME" push origin "HEAD:staging" --quiet 2>/dev/null || TC1_PUSH_RC=$?

if [[ "$TC1_PUSH_RC" -eq 0 ]]; then
  pass "TC1-1: push from home with HEAD:staging refspec succeeded (rc=0)"
else
  fail "TC1-1: push from home with HEAD:staging failed (rc=$TC1_PUSH_RC)"
fi

# Verify bare remote's staging tip == home HEAD (push went to origin/staging correctly)
TC1_BARE_TIP="$(git -C "$TC1_BARE" rev-parse "staging" 2>/dev/null || echo "!")"
if [[ "$TC1_BARE_TIP" == "$TC1_HOME_HEAD" ]]; then
  pass "TC1-2: bare remote's staging tip == home HEAD after push ($TC1_HOME_HEAD)"
else
  fail "TC1-2: bare remote staging ($TC1_BARE_TIP) != home HEAD ($TC1_HOME_HEAD)"
fi

TC1_BRANCH_AFTER="$(git -C "$TC1_HOME" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC1_BRANCH_AFTER" == "gaai-daemon-home" ]]; then
  pass "TC1-3: home remains on gaai-daemon-home after push"
else
  fail "TC1-3: home is on '${TC1_BRANCH_AFTER:-<detached>}' after push (expected gaai-daemon-home)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC2: dirty / branch-switched main checkout is INERT (AC6b — main-checkout-decoupled proof)
# ═══════════════════════════════════════════════════════════════════════════════
# The daemon's home is a separate worktree sharing the same .git as the main checkout.
# When the home pushes to "origin HEAD:staging", it goes to the bare remote.
# The main checkout's LOCAL staging branch ref (refs/heads/staging) must NOT advance —
# only refs/remotes/origin/staging is updated by the push (tracking branch auto-update).
echo ""
echo "=== TC2: dirty / branch-switched main checkout is INERT to daemon coordination ==="

TC2_DIR="$FIXTURE_DIR/tc2-project"
TC2_HOME="$FIXTURE_DIR/tc2-home"
TC2_BARE="${TC2_DIR}_remote.git"
setup_git_repo "$TC2_DIR"

_gaai_provision_daemon_home "$TC2_HOME" "staging" "$TC2_DIR" >/dev/null 2>&1

# Record main checkout's LOCAL staging branch SHA before daemon coordination.
# This is refs/heads/staging in the shared .git, NOT refs/remotes/origin/staging.
TC2_LOCAL_STAGING_BEFORE="$(git -C "$TC2_DIR" rev-parse "staging" 2>/dev/null || echo "?")"

# Dirty the main checkout: checkout a new branch + leave uncommitted changes
git -C "$TC2_DIR" checkout -b "feature/dirty-interference" -q 2>/dev/null
echo "dirty" > "$TC2_DIR/dirty.txt"

# Make a coordination commit from the home and push to origin with HEAD:staging
touch "$TC2_HOME/daemon-op.txt"
git -C "$TC2_HOME" add daemon-op.txt
git -C "$TC2_HOME" config user.email "test@gaai.local"
git -C "$TC2_HOME" config user.name "GAAI Test"
git -C "$TC2_HOME" commit -m "chore(daemon): mark in_progress [from-home]" -q

TC2_HOME_HEAD="$(git -C "$TC2_HOME" rev-parse HEAD 2>/dev/null || echo "?")"

TC2_PUSH_RC=0
git -C "$TC2_HOME" push origin "HEAD:staging" --quiet 2>/dev/null || TC2_PUSH_RC=$?

if [[ "$TC2_PUSH_RC" -eq 0 ]]; then
  pass "TC2-1: coordination push succeeded despite dirty main checkout (rc=0)"
else
  fail "TC2-1: coordination push failed (rc=$TC2_PUSH_RC) — dirty main checkout interfered"
fi

TC2_MAIN_BRANCH_AFTER="$(git -C "$TC2_DIR" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC2_MAIN_BRANCH_AFTER" == "feature/dirty-interference" ]]; then
  pass "TC2-2: main checkout remains on 'feature/dirty-interference' (daemon did not touch it)"
else
  fail "TC2-2: main checkout moved to '$TC2_MAIN_BRANCH_AFTER' (daemon interfered)"
fi

# Local staging ref (refs/heads/staging) must be unchanged — push went to origin (bare),
# not to the main checkout's local branch.
TC2_LOCAL_STAGING_AFTER="$(git -C "$TC2_DIR" rev-parse "staging" 2>/dev/null || echo "?")"
if [[ "$TC2_LOCAL_STAGING_AFTER" == "$TC2_LOCAL_STAGING_BEFORE" ]]; then
  pass "TC2-3: main checkout's local staging ref unchanged (daemon coordination stayed in home)"
else
  fail "TC2-3: main checkout's local staging moved from $TC2_LOCAL_STAGING_BEFORE to $TC2_LOCAL_STAGING_AFTER (unexpected)"
fi

# Bare remote's staging must advance to home's commit
TC2_BARE_TIP="$(git -C "$TC2_BARE" rev-parse "staging" 2>/dev/null || echo "!")"
if [[ "$TC2_BARE_TIP" == "$TC2_HOME_HEAD" ]]; then
  pass "TC2-4: bare remote's staging advanced to home's commit ($TC2_HOME_HEAD)"
else
  fail "TC2-4: bare remote staging ($TC2_BARE_TIP) != home commit ($TC2_HOME_HEAD)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC3: completeness backstop — zero coordination push sites lack HEAD: refspec (AC6c)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC3: completeness backstop — zero coordination pushes lack HEAD: refspec ==="

TC3_PASS=1

for _script in \
    "$SCRIPTS_DIR/delivery-daemon.sh" \
    "$SCRIPTS_DIR/lib/chore-commit.sh" \
    "$SCRIPTS_DIR/daemon-dispatch.sh"; do

  if [[ ! -f "$_script" ]]; then
    fail "TC3: script not found at $_script"
    TC3_PASS=0
    continue
  fi

  # Grep for coordination push patterns without HEAD: prefix.
  # Excludes: story-branch pushes (story/), already-correct HEAD: refspecs, comment lines.
  _missing=$(grep -nE 'git push origin[[:space:]]+"?\$\{?(TARGET_BRANCH|target_branch)' "$_script" \
    | grep -v 'HEAD:' \
    | grep -v 'story/' \
    | grep -v '^[[:space:]]*#' || true)

  if [[ -z "$_missing" ]]; then
    pass "TC3: $(basename "$_script") — no unconverted coordination push sites"
  else
    fail "TC3: $(basename "$_script") has push sites missing HEAD: refspec:"
    echo "$_missing" | while IFS= read -r line; do echo "    $line"; done
    TC3_PASS=0
  fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# TC4: home is on gaai-daemon-home; main checkout's <target> ref unchanged (AC6d)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC4: home on gaai-daemon-home; main checkout's staging ref unchanged ==="

TC4_DIR="$FIXTURE_DIR/tc4-project"
TC4_HOME="$FIXTURE_DIR/tc4-home"
setup_git_repo "$TC4_DIR"

TC4_MAIN_STAGING_BEFORE="$(git -C "$TC4_DIR" rev-parse "staging" 2>/dev/null || echo "?")"

_gaai_provision_daemon_home "$TC4_HOME" "staging" "$TC4_DIR" >/dev/null 2>&1

TC4_HOME_BRANCH="$(git -C "$TC4_HOME" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC4_HOME_BRANCH" == "gaai-daemon-home" ]]; then
  pass "TC4-1: home is on 'gaai-daemon-home' branch after provisioning"
else
  fail "TC4-1: home is on '${TC4_HOME_BRANCH:-<detached>}' (expected gaai-daemon-home)"
fi

TC4_MAIN_STAGING_AFTER="$(git -C "$TC4_DIR" rev-parse "staging" 2>/dev/null || echo "?")"
if [[ "$TC4_MAIN_STAGING_AFTER" == "$TC4_MAIN_STAGING_BEFORE" ]]; then
  pass "TC4-2: main checkout's local 'staging' ref unchanged by provisioning ($TC4_MAIN_STAGING_AFTER)"
else
  fail "TC4-2: main checkout's 'staging' moved from $TC4_MAIN_STAGING_BEFORE to $TC4_MAIN_STAGING_AFTER (daemon modified it)"
fi

TC4_MAIN_BRANCH="$(git -C "$TC4_DIR" branch --show-current 2>/dev/null || echo "")"
if [[ "$TC4_MAIN_BRANCH" == "staging" ]]; then
  pass "TC4-3: main checkout remains on 'staging' (daemon never checked out its branch)"
else
  fail "TC4-3: main checkout is on '$TC4_MAIN_BRANCH' (expected staging)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Shared harness for E1003S06 TC5-TC9 — run the real delivery-daemon.sh standalone
# ═══════════════════════════════════════════════════════════════════════════════
DAEMON_SCRIPT="$SCRIPTS_DIR/delivery-daemon.sh"

# delivery-daemon.sh requires tmux (or osascript on Darwin) before arg parsing —
# stub tmux hermetically so the corpus runner doesn't need it installed.
TMUX_STUB_DIR="$FIXTURE_DIR/bin-stub"
mkdir -p "$TMUX_STUB_DIR"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMUX_STUB_DIR/tmux"
chmod +x "$TMUX_STUB_DIR/tmux"

# Builds a sandbox repo (bare remote + main checkout on staging) plus a private
# copy of .gaai/core/scripts, so delivery-daemon.sh can run as a standalone process.
setup_daemon_sandbox() {
  local project_dir="$1"
  setup_git_repo "$project_dir"
  mkdir -p "$project_dir/.gaai/core"
  cp -R "$SCRIPTS_DIR" "$project_dir/.gaai/core/scripts"
}

# Runs the sandboxed delivery-daemon.sh hermetically: strips ambient daemon-home
# env vars (proves nothing is inherited from the test's own process), stubs tmux,
# fixes the target branch. Caller redirects stdout/stderr as needed.
run_sandbox_daemon() {
  local project_dir="$1" mode="$2"
  env -u GAAI_DAEMON_HOME -u GAAI_REPO_ROOT -u _GAAI_DAEMON_HOME_SH_SOURCED \
    PATH="$TMUX_STUB_DIR:$PATH" GAAI_TARGET_BRANCH=staging \
    bash "$project_dir/.gaai/core/scripts/delivery-daemon.sh" "$mode"
}

# Extracts _per_cycle_home_branch_check's body from the real delivery-daemon.sh
# (pattern-matched, not line-numbered — survives unrelated reflow).
extract_home_branch_check() {
  awk '/^_per_cycle_home_branch_check\(\) \{/,/^\}/' "$DAEMON_SCRIPT"
}

_CHECK_FN="$(extract_home_branch_check)"
if [[ -n "$_CHECK_FN" ]] && grep -q '_gaai_provision_daemon_home' <<<"$_CHECK_FN"; then
  pass "TC-harness: _per_cycle_home_branch_check extraction is non-empty and calls the provisioner"
else
  fail "TC-harness: _per_cycle_home_branch_check extraction is empty or missing the provisioner call — TC6/TC8 cannot proceed reliably"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC5: _gaai_provision_daemon_home is defined in the daemon's OWN process (AC1)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC5: provisioner is loaded in the daemon's own process, not inherited ==="

TC5_DIR="$FIXTURE_DIR/tc5-project"
setup_daemon_sandbox "$TC5_DIR"

TC5_1_OUT=$(run_sandbox_daemon "$TC5_DIR" --help 2>&1)
TC5_1_RC=$?
if [[ "$TC5_1_RC" -eq 0 ]] && ! grep -q 'command not found' <<<"$TC5_1_OUT"; then
  pass "TC5-1: sandbox with the real lib — --help succeeds, no 'command not found'"
else
  fail "TC5-1: rc=$TC5_1_RC, output: $TC5_1_OUT"
fi

# Decisive: replace the sandbox lib with a stub that both defines the function
# AND touches a sentinel at SOURCE time (top-level, not inside the function).
# The sentinel existing after --help proves the daemon PROCESS itself sourced it.
TC5_SENTINEL="$FIXTURE_DIR/tc5-sentinel"
rm -f "$TC5_SENTINEL"
cat > "$TC5_DIR/.gaai/core/scripts/lib/daemon-home.sh" <<EOF
#!/usr/bin/env bash
touch "$TC5_SENTINEL"
_gaai_provision_daemon_home() { return 0; }
EOF
run_sandbox_daemon "$TC5_DIR" --help >/dev/null 2>&1
if [[ -f "$TC5_SENTINEL" ]]; then
  pass "TC5-2: sentinel written by the sandboxed lib exists — the daemon process itself sourced lib/daemon-home.sh"
else
  fail "TC5-2: sentinel absent — the daemon process did not source lib/daemon-home.sh itself"
fi

# Root-cause control: a bare child bash that sources nothing does not inherit
# the function — confirms functions do not cross the launcher→daemon process boundary.
if env -u _GAAI_DAEMON_HOME_SH_SOURCED bash -c 'declare -F _gaai_provision_daemon_home' >/dev/null 2>&1; then
  fail "TC5-3: _gaai_provision_daemon_home unexpectedly available in a bare child shell that sourced nothing"
else
  pass "TC5-3: a bare child bash without sourcing the helper does not have _gaai_provision_daemon_home (process boundary confirmed)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC6: wrong-branch home repaired at the current target tip via the check (AC2)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC6: wrong-branch home repair via _per_cycle_home_branch_check ==="

TC6_DIR="$FIXTURE_DIR/tc6-project"
TC6_HOME="$FIXTURE_DIR/tc6-home"
TC6_BARE="${TC6_DIR}_remote.git"
setup_git_repo "$TC6_DIR"

_gaai_provision_daemon_home "$TC6_HOME" "staging" "$TC6_DIR" >/dev/null 2>&1

# Advance the bare remote's staging by one commit since provisioning — the repair
# must land on this NEW tip, not the stale one captured at provisioning time.
echo "advance" > "$TC6_DIR/advance.txt"
git -C "$TC6_DIR" add advance.txt
git -C "$TC6_DIR" commit -m "advance-staging" -q
git -C "$TC6_DIR" push origin staging -q
TC6_NEW_TIP="$(git -C "$TC6_BARE" rev-parse staging 2>/dev/null || echo "?")"
TC6_MAIN_BRANCH_BEFORE="$(git -C "$TC6_DIR" branch --show-current 2>/dev/null || echo "")"
TC6_MAIN_STAGING_BEFORE="$(git -C "$TC6_DIR" rev-parse staging 2>/dev/null || echo "?")"

# Force the home onto a wrong branch (simulating the observed drift).
git -C "$TC6_HOME" checkout -B drifted -q

TC6_CHECK_SCRIPT="$FIXTURE_DIR/tc6-check.sh"
{
  echo '#!/usr/bin/env bash'
  echo "source \"$DAEMON_HOME_LIB\""
  echo 'log() { :; }'
  echo "$_CHECK_FN"
  echo '_per_cycle_home_branch_check'
} > "$TC6_CHECK_SCRIPT"

TC6_REPAIR_OUT=$(PROJECT_DIR="$TC6_HOME" REPO_ROOT="$TC6_DIR" TARGET_BRANCH=staging GAAI_DAEMON_HOME="$TC6_HOME" bash "$TC6_CHECK_SCRIPT" 2>&1)

TC6_HOME_BRANCH_AFTER="$(git -C "$TC6_HOME" branch --show-current 2>/dev/null || echo "")"
TC6_HOME_HEAD_AFTER="$(git -C "$TC6_HOME" rev-parse HEAD 2>/dev/null || echo "?")"
TC6_MAIN_BRANCH_AFTER="$(git -C "$TC6_DIR" branch --show-current 2>/dev/null || echo "")"
TC6_MAIN_STAGING_AFTER="$(git -C "$TC6_DIR" rev-parse staging 2>/dev/null || echo "?")"

[[ "$TC6_HOME_BRANCH_AFTER" == "gaai-daemon-home" ]] \
  && pass "TC6-1: drifted home is repaired back onto 'gaai-daemon-home'" \
  || fail "TC6-1: home is on '${TC6_HOME_BRANCH_AFTER:-<detached>}' (expected gaai-daemon-home)"

[[ "$TC6_HOME_HEAD_AFTER" == "$TC6_NEW_TIP" ]] \
  && pass "TC6-2: repaired home HEAD == the NEW origin/staging tip ($TC6_NEW_TIP)" \
  || fail "TC6-2: repaired home HEAD ($TC6_HOME_HEAD_AFTER) != new tip ($TC6_NEW_TIP)"

[[ "$TC6_MAIN_BRANCH_AFTER" == "$TC6_MAIN_BRANCH_BEFORE" ]] \
  && pass "TC6-3: main checkout's branch untouched by the repair ($TC6_MAIN_BRANCH_AFTER)" \
  || fail "TC6-3: main checkout branch changed from $TC6_MAIN_BRANCH_BEFORE to $TC6_MAIN_BRANCH_AFTER"

[[ "$TC6_MAIN_STAGING_AFTER" == "$TC6_MAIN_STAGING_BEFORE" ]] \
  && pass "TC6-4: main checkout's local staging ref untouched by the repair" \
  || fail "TC6-4: main checkout staging moved from $TC6_MAIN_STAGING_BEFORE to $TC6_MAIN_STAGING_AFTER"

! grep -q 'command not found' <<<"$TC6_REPAIR_OUT" \
  && pass "TC6-5: repair path produced no 'command not found'" \
  || fail "TC6-5: repair output contains 'command not found': $TC6_REPAIR_OUT"

# Sensitivity control (TC6-N): same check, WITHOUT sourcing the lib — reproduces
# the historical drift incident exactly, and the home must stay un-repaired.
git -C "$TC6_HOME" checkout -B drifted -q 2>/dev/null || true
TC6N_CHECK_SCRIPT="$FIXTURE_DIR/tc6n-check.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'log() { :; }'
  echo "$_CHECK_FN"
  echo '_per_cycle_home_branch_check'
} > "$TC6N_CHECK_SCRIPT"
TC6N_OUT=$(PROJECT_DIR="$TC6_HOME" REPO_ROOT="$TC6_DIR" TARGET_BRANCH=staging GAAI_DAEMON_HOME="$TC6_HOME" bash "$TC6N_CHECK_SCRIPT" 2>&1)
TC6N_HOME_BRANCH="$(git -C "$TC6_HOME" branch --show-current 2>/dev/null || echo "")"

grep -q '_gaai_provision_daemon_home: command not found' <<<"$TC6N_OUT" \
  && pass "TC6-N-1: without sourcing the lib, reproduces the incident ('command not found')" \
  || fail "TC6-N-1: expected 'command not found' without the lib sourced, got: $TC6N_OUT"

[[ "$TC6N_HOME_BRANCH" == "drifted" ]] \
  && pass "TC6-N-2: home stays on 'drifted' when the provisioner isn't callable (no silent repair)" \
  || fail "TC6-N-2: home moved to '$TC6N_HOME_BRANCH' without a callable provisioner"

# ═══════════════════════════════════════════════════════════════════════════════
# TC7: fail-closed startup when the capability is unavailable, without leaking (AC3)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC7: fail-closed on missing / non-defining / malformed helper ==="

TC7_DIR="$FIXTURE_DIR/tc7-project"
setup_daemon_sandbox "$TC7_DIR"
TC7_LIB="$TC7_DIR/.gaai/core/scripts/lib/daemon-home.sh"

# 7-1: lib absent entirely.
rm -f "$TC7_LIB"
TC7_1_OUT=$(run_sandbox_daemon "$TC7_DIR" --help 2>&1)
TC7_1_RC=$?
[[ "$TC7_1_RC" -ne 0 ]] \
  && pass "TC7-1: --help fails closed (rc=$TC7_1_RC) when lib/daemon-home.sh is absent" \
  || fail "TC7-1: --help returned rc=0 with the lib absent (G11 regression — the fix is not effective)"

# 7-2: diagnostic names the capability, leaks nothing sensitive.
if grep -q '_gaai_provision_daemon_home' <<<"$TC7_1_OUT" && grep -q 'daemon-home.sh' <<<"$TC7_1_OUT"; then
  pass "TC7-2a: diagnostic names the missing capability (_gaai_provision_daemon_home / daemon-home.sh)"
else
  fail "TC7-2a: diagnostic does not name the missing capability: $TC7_1_OUT"
fi
if grep -qE '://|git@|[A-Z]+[0-9]{3,}S[0-9]{2}' <<<"$TC7_1_OUT" || grep -qiE 'token|secret' <<<"$TC7_1_OUT"; then
  fail "TC7-2b: diagnostic leaks a URL/remote/story-id/credential-shaped token: $TC7_1_OUT"
else
  pass "TC7-2b: diagnostic leaks no URL, remote, story id, or credential-shaped content"
fi

# 7-3: helper present but sets the source guard without defining the function
# (covers "cannot define" — e.g. guard var pre-exported into the daemon's env).
cat > "$TC7_LIB" <<'EOF'
#!/usr/bin/env bash
_GAAI_DAEMON_HOME_SH_SOURCED=1
return 0
EOF
TC7_3_OUT=$(run_sandbox_daemon "$TC7_DIR" --help 2>&1)
TC7_3_RC=$?
[[ "$TC7_3_RC" -ne 0 ]] && grep -q '_gaai_provision_daemon_home' <<<"$TC7_3_OUT" \
  && pass "TC7-3: fails closed with the same diagnostic when the helper defines nothing (rc=$TC7_3_RC)" \
  || fail "TC7-3: rc=$TC7_3_RC, output: $TC7_3_OUT"

# 7-4: syntactically invalid helper — rc-only assertion (bash's own parse error
# is an acceptable deterministic abort per the Story's AC3 edge-case analysis).
printf '_gaai_provision_daemon_home() {\n  echo "unterminated\n' > "$TC7_LIB"
run_sandbox_daemon "$TC7_DIR" --help >/dev/null 2>&1
TC7_4_RC=$?
[[ "$TC7_4_RC" -ne 0 ]] \
  && pass "TC7-4: malformed helper aborts deterministically (rc=$TC7_4_RC)" \
  || fail "TC7-4: malformed helper did not abort (rc=0)"

# 7-5: mode-independence + no-loop — lib absent, both --help and --status hit the
# same fail-closed diagnostic, and neither ever reaches the per-cycle check or
# the started banner (i.e. abort happens before polling/coordination/spawn).
rm -f "$TC7_LIB"
TC7_5_HELP_OUT=$(run_sandbox_daemon "$TC7_DIR" --help 2>&1)
TC7_5_STATUS_OUT=$(run_sandbox_daemon "$TC7_DIR" --status 2>&1)

if grep -q '_gaai_provision_daemon_home' <<<"$TC7_5_HELP_OUT" && grep -q '_gaai_provision_daemon_home' <<<"$TC7_5_STATUS_OUT"; then
  pass "TC7-5a: diagnostic appears identically for both --help and --status modes"
else
  fail "TC7-5a: diagnostic missing for --help and/or --status"
fi
if grep -qE '\[HOME-INTEGRITY\]|Daemon started' <<<"$TC7_5_HELP_OUT$TC7_5_STATUS_OUT"; then
  fail "TC7-5b: daemon reached the per-cycle check or the started banner despite the missing capability"
else
  pass "TC7-5b: daemon aborts before [HOME-INTEGRITY] / 'Daemon started' in either mode — no repeated-loop is possible"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TC8: direct mode (GAAI_DAEMON_HOME unset) stays inert (AC4)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC8: direct mode is a no-op — no worktree/branch/ref side effects ==="

TC8_DIR="$FIXTURE_DIR/tc8-project"
setup_daemon_sandbox "$TC8_DIR"
echo "operator-wip" > "$TC8_DIR/uncommitted.txt"

TC8_WORKTREE_BEFORE="$(git -C "$TC8_DIR" worktree list --porcelain)"
TC8_BRANCH_BEFORE="$(git -C "$TC8_DIR" branch --show-current 2>/dev/null || echo "")"
TC8_STAGING_BEFORE="$(git -C "$TC8_DIR" rev-parse staging 2>/dev/null || echo "?")"
TC8_HOME_BRANCH_BEFORE="$(git -C "$TC8_DIR" branch --list gaai-daemon-home)"

TC8_HELP_RC=0
run_sandbox_daemon "$TC8_DIR" --help >/dev/null 2>&1 || TC8_HELP_RC=$?
[[ "$TC8_HELP_RC" -eq 0 ]] \
  && pass "TC8-1: --help succeeds with GAAI_DAEMON_HOME unset (direct mode, real lib intact)" \
  || fail "TC8-1: --help failed (rc=$TC8_HELP_RC) in direct mode with the real lib present"

TC8_CHECK_SCRIPT="$FIXTURE_DIR/tc8-check.sh"
{
  echo '#!/usr/bin/env bash'
  echo "source \"$DAEMON_HOME_LIB\""
  echo 'log() { :; }'
  echo "$_CHECK_FN"
  echo '_per_cycle_home_branch_check; echo "RC=$?"'
} > "$TC8_CHECK_SCRIPT"
TC8_CHECK_OUT=$(env -u GAAI_DAEMON_HOME PROJECT_DIR="$TC8_DIR" REPO_ROOT="$TC8_DIR" TARGET_BRANCH=staging bash "$TC8_CHECK_SCRIPT" 2>&1)
grep -q 'RC=0' <<<"$TC8_CHECK_OUT" \
  && pass "TC8-2: _per_cycle_home_branch_check is a no-op (rc=0) with GAAI_DAEMON_HOME unset" \
  || fail "TC8-2: unexpected output with GAAI_DAEMON_HOME unset: $TC8_CHECK_OUT"

TC8_WORKTREE_AFTER="$(git -C "$TC8_DIR" worktree list --porcelain)"
TC8_BRANCH_AFTER="$(git -C "$TC8_DIR" branch --show-current 2>/dev/null || echo "")"
TC8_STAGING_AFTER="$(git -C "$TC8_DIR" rev-parse staging 2>/dev/null || echo "?")"
TC8_HOME_BRANCH_AFTER="$(git -C "$TC8_DIR" branch --list gaai-daemon-home)"

[[ "$TC8_WORKTREE_AFTER" == "$TC8_WORKTREE_BEFORE" ]] \
  && pass "TC8-3: worktree list unchanged (no worktree created/removed)" \
  || fail "TC8-3: worktree list changed"
[[ "$TC8_BRANCH_AFTER" == "$TC8_BRANCH_BEFORE" && "$TC8_STAGING_AFTER" == "$TC8_STAGING_BEFORE" ]] \
  && pass "TC8-4: main checkout branch + local staging ref unchanged" \
  || fail "TC8-4: main checkout branch/ref changed (before: $TC8_BRANCH_BEFORE/$TC8_STAGING_BEFORE, after: $TC8_BRANCH_AFTER/$TC8_STAGING_AFTER)"
[[ -z "$TC8_HOME_BRANCH_BEFORE" && -z "$TC8_HOME_BRANCH_AFTER" ]] \
  && pass "TC8-5: no 'gaai-daemon-home' branch was ever created in direct mode" \
  || fail "TC8-5: a 'gaai-daemon-home' branch exists in direct mode"
[[ "$(cat "$TC8_DIR/uncommitted.txt" 2>/dev/null)" == "operator-wip" ]] \
  && pass "TC8-6: the operator's uncommitted file survives untouched (nothing was cleaned)" \
  || fail "TC8-6: the operator's uncommitted file was modified or removed"

# ═══════════════════════════════════════════════════════════════════════════════
# TC9: static neutrality/authority guard rails (AC5)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC9: AC5 static guard rails — single SCRIPT_DIR-relative source, no product token ==="

TC9_SOURCE_LINES=$(grep -cE '^[[:space:]]*source "\$SCRIPT_DIR/lib/daemon-home\.sh"' "$DAEMON_SCRIPT" || true)
[[ "$TC9_SOURCE_LINES" -eq 1 ]] \
  && pass "TC9-1: exactly one \$SCRIPT_DIR-relative lib/daemon-home.sh source line in delivery-daemon.sh" \
  || fail "TC9-1: expected exactly 1 source line, found $TC9_SOURCE_LINES"

TC9_BLOCK=$(awk '/^# daemon-start\.sh sources lib\/daemon-home\.sh too/,/^NOTIFICATION_WEBHOOK=/' "$DAEMON_SCRIPT" | sed '$d')
if [[ -z "$TC9_BLOCK" ]]; then
  fail "TC9-2: could not locate the daemon-home prelude block for static inspection"
elif grep -qiE 'gaai\.cloud|workers/|packages/|curl|http' <<<"$TC9_BLOCK"; then
  fail "TC9-2: prelude block contains a network/product token: $TC9_BLOCK"
else
  pass "TC9-2: prelude block introduces no network/product token"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "══════════════════════════════════════════════════"

exit "$FAIL_COUNT"
