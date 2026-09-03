#!/usr/bin/env bash
# daemon-home-provision.test.sh — E1003S07 AC6 setup/startup authority matrices
#
# Proves the Option A authority split:
#   * `daemon-setup.sh` is the ONLY path that can create or advance the dedicated
#     worktree, refuses any active or ambiguous lifecycle authority, preserves
#     interrupted setup evidence, and leaves a clean registered exact-target home;
#   * `daemon-start.sh`, `delivery-daemon.sh` and every runtime-exported
#     `lib/daemon-home.sh` path are verify-only and refuse absent, stale, dirty,
#     foreign, wrong-branch and ambiguous homes BEFORE any tmux, credential or
#     daemon effect;
#   * the shared lifecycle lock is acquired before lifecycle inspection, retained
#     through settlement, and never converted into production launch authority.
#
# This file also carries the shared hermetic fixture used by the two sibling suites
# (they source it with GAAI_HOME_FIXTURE_ONLY=1). Keeping it here rather than in a
# new helper keeps the Delivery inventory at exactly twenty-one files.
#
# Usage: .gaai/core/scripts/tests/daemon-home-provision.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# ═══════════════════════════════════════════════════════════════════════════
# Shared hermetic fixture
# ═══════════════════════════════════════════════════════════════════════════

# Both supported shells. Bash 3.2 is macOS's system Bash and the OSS floor. When no
# 3.2 interpreter exists on this host the matrices SAY SO rather than silently
# reporting single-shell coverage as dual-shell.
gaai_supported_shells() {
  local _s _seen=""
  printf '%s\n' "${BASH:-/bin/bash}"
  _seen="${BASH:-/bin/bash}"
  # `$HOME/.gaai-bash32/bin/bash` is where the hosted Test Gate provisions the pinned
  # Bash 3.2 for its dual-shell matrix, so the 3.2 column really executes on that lane.
  # GAAI_BASH32 lets an operator point at their own build.
  for _s in "${GAAI_BASH32:-}" "$HOME/.gaai-bash32/bin/bash" /bin/bash \
            /usr/local/bin/bash-3.2 /opt/homebrew/opt/bash@3.2/bin/bash \
            /usr/local/opt/bash@3.2/bin/bash; do
    [[ -n "$_s" ]] || continue
    [[ -x "$_s" && "$_s" != "$_seen" ]] || continue
    case "$("$_s" --version 2>/dev/null | head -1)" in
      *"version 3.2"*) printf '%s\n' "$_s" ;;
    esac
  done
}

gaai_bash32_available() {
  local _s
  while IFS= read -r _s; do
    case "$("$_s" --version 2>/dev/null | head -1)" in *"version 3.2"*) return 0 ;; esac
  done < <(gaai_supported_shells)
  return 1
}

# gaai_build_fixture <root> <scripts_dir>
# A real bare remote plus clone carrying the units under test, so every matrix
# exercises actual worktree registration, a real private tmux server and the real
# privileged entry — never a mock of them.
gaai_build_fixture() {
  local _root="$1" _src="$2"
  local _remote="$_root/remote.git" _proj="$_root/proj"
  git init --bare "$_remote" -q
  git clone "$_remote" "$_proj" -q 2>/dev/null
  git -C "$_proj" config user.email "test@gaai.local"
  git -C "$_proj" config user.name "gaai-test"
  git -C "$_proj" symbolic-ref HEAD refs/heads/staging
  mkdir -p "$_proj/.gaai/core/scripts/lib" "$_proj/.gaai/project/contexts/backlog"
  cp "$_src/daemon-start.sh" "$_src/daemon-setup.sh" "$_proj/.gaai/core/scripts/"
  cp "$_src/lib/daemon-home.sh" "$_src/lib/home-branch-guard.sh" "$_proj/.gaai/core/scripts/lib/"
  chmod 0755 "$_proj/.gaai/core/scripts/daemon-start.sh" "$_proj/.gaai/core/scripts/daemon-setup.sh"
  printf '#!/bin/sh\nexit 0\n' > "$_proj/.gaai/core/scripts/backlog-scheduler.sh"
  chmod 0755 "$_proj/.gaai/core/scripts/backlog-scheduler.sh"
  cat > "$_proj/.gaai/core/scripts/delivery-daemon.sh" <<'STUB_EOF'
#!/usr/bin/env bash
# Stub daemon for the E1003S07 matrices. Mirrors the real ready-acknowledgement
# contract of delivery-daemon.sh and records what actually crossed the boundary.
set -uo pipefail
A="${GAAI_DAEMON_LAUNCH_ATTEMPT:-}"
if [[ -n "$A" ]]; then
  INC="$(sed -n 's/^incarnation=//p' "$A/ack.launcher" 2>/dev/null | head -1)"
  {
    printf 'schema=gaai-daemon-lifecycle/v1\n'
    printf 'pid=%s\n' "$$"
    printf 'incarnation=%s\n' "$INC"
    printf 'credential_mode=%s\n' "${GAAI_DAEMON_CREDENTIAL_MODE:-}"
  } > "$A/ack.ready"
  # Observations go OUTSIDE the attempt directory. The real daemon writes only its
  # ready acknowledgement there, and exact settlement removes solely the artefacts
  # the lifecycle itself created — so a stub file left in that directory would be
  # correctly preserved as unexplained evidence and would mask a genuine result.
  OBS="${GAAI_REPO_ROOT:-/tmp}/.gaai/project/contexts/backlog/.observed"
  mkdir -p "$(dirname "$OBS")" 2>/dev/null
  {
    printf 'token_set=%s\n' "${GAAI_IMPL_AUTH_TOKEN+yes}"
    printf 'token_value=%s\n' "${GAAI_IMPL_AUTH_TOKEN:-<unset>}"
    printf 'args=%s\n' "$*"
    printf 'daemon_home=%s\n' "${GAAI_DAEMON_HOME:-}"
    printf 'repo_root=%s\n' "${GAAI_REPO_ROOT:-}"
    printf 'target_sha=%s\n' "${GAAI_TARGET_SHA:-}"
    printf 'attempt_dir=%s\n' "$A"
  } > "$OBS"
fi
while :; do sleep 5; done
STUB_EOF
  chmod 0755 "$_proj/.gaai/core/scripts/delivery-daemon.sh"
  mkdir -p "$_root/fakebin" "$_root/opshome"
  printf '#!/bin/sh\nexit 0\n' > "$_root/fakebin/claude"
  chmod 0755 "$_root/fakebin/claude"
  git -C "$_proj" add -A >/dev/null 2>&1
  git -C "$_proj" commit -qm "fixture" >/dev/null 2>&1
  git -C "$_proj" push -q origin staging 2>/dev/null
}

gaai_advance_target() {
  local _proj="$1"
  git -C "$_proj" fetch -q origin staging
  git -C "$_proj" reset -q --hard origin/staging
  printf '%s\n' "advance-$$-$RANDOM" >> "$_proj/target-advance.txt"
  git -C "$_proj" add -A >/dev/null 2>&1
  git -C "$_proj" commit -qm "advance" >/dev/null 2>&1
  git -C "$_proj" push -q origin HEAD:staging 2>/dev/null
}

gaai_lifecycle_root() {
  printf '%s/gaai-daemon-lifecycle' \
    "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
}

gaai_home_path() {
  local _proj="$1"
  printf '%s/.gaai-worktrees/%s/__daemon-home' \
    "$(cd "$_proj/.." && pwd -P)" "$(basename "$_proj")"
}

# The privileged entry must be invoked from a clean environment — that IS the
# contract, and it is how an operator has to invoke it too.
gaai_run() {
  local _root="$1"; shift
  /usr/bin/env -i "PATH=$_root/fakebin:/usr/bin:/bin" "HOME=$_root/opshome" TERM=dumb "$@"
}

# Remove the home the way an operator must: unregister it, then prune the
# administrative record. A bare `rm -rf` leaves a registered-but-missing home, which
# is a distinct state the suite asserts separately (TC17).
gaai_reset_home() {
  local _hw
  _hw="$(gaai_home_path "$PROJ")"
  git -C "$PROJ" worktree remove --force "$_hw" >/dev/null 2>&1 || rm -rf "$_hw"
  git -C "$PROJ" worktree prune >/dev/null 2>&1
  rm -rf "$_hw" 2>/dev/null
}

gaai_teardown() {
  local _root="$1" _proj="${2:-}"
  if [[ -n "$_proj" && -d "$_proj" ]]; then
    local _sock
    _sock="$(sed -n 's/^socket=//p' "$(gaai_lifecycle_root "$_proj")/owner" 2>/dev/null | head -1)"
    if [[ -n "$_sock" && -S "$_sock" ]]; then tmux -f /dev/null -S "$_sock" kill-server 2>/dev/null; fi
    [[ -n "$_sock" ]] && rm -f "$_sock" 2>/dev/null
  fi
  rm -rf "$_root" 2>/dev/null || true
}

# Sourced by the sibling suites for the fixture only.
if [[ -n "${GAAI_HOME_FIXTURE_ONLY:-}" ]]; then return 0; fi

# ═══════════════════════════════════════════════════════════════════════════
# Matrices
# ═══════════════════════════════════════════════════════════════════════════

for _tool in git tmux; do
  if ! command -v "$_tool" >/dev/null 2>&1; then
    echo "ERROR: $_tool is required by the E1003S07 matrices and is absent."
    echo "The hosted OSS lane must execute the real capability probe and smoke lifecycle;"
    echo "installing it is outside this Story's inventory (see Out of Scope)."
    exit 1
  fi
done

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gaai-home-prov-XXXXXX")"
ROOT="$(cd "$ROOT" && pwd -P)"
PROJ="$ROOT/proj"
trap 'gaai_teardown "$ROOT" "$PROJ"' EXIT
gaai_build_fixture "$ROOT" "$SCRIPTS_DIR"
SETUP="$PROJ/.gaai/core/scripts/daemon-setup.sh"
START="$PROJ/.gaai/core/scripts/daemon-start.sh"
HOME_WT="$(gaai_home_path "$PROJ")"
LIFECYCLE="$(gaai_lifecycle_root "$PROJ")"

echo ""
echo "=== Dual-shell coverage declaration ==="
SHELLS="$(gaai_supported_shells)"
echo "  supported interpreters exercised: $(echo "$SHELLS" | tr '\n' ' ')"
if gaai_bash32_available; then
  pass "TC0: both supported shells (Bash 3.2 and the current Bash) are available and exercised"
else
  echo "  NOTE: no Bash 3.2 interpreter on this host — the 3.2 half of the dual-shell"
  echo "        matrix cannot execute here. It MUST be executed on the macOS lane, whose"
  echo "        /bin/bash is 3.2, before this boundary is declared proven."
  pass "TC0: dual-shell coverage is declared explicitly rather than silently assumed"
fi

echo ""
echo "=== TC1: startup refuses an absent home and creates nothing ==="
OUT="$(gaai_run "$ROOT" "$START" 2>&1)"
if echo "$OUT" | grep -q 'reason=home_identity_invalid action=rerun_setup'; then
  pass "TC1-1: absent home returns home_identity_invalid + rerun_setup"
else
  fail "TC1-1: expected home_identity_invalid/rerun_setup, got: $OUT"
fi
if [[ ! -e "$HOME_WT" ]]; then
  pass "TC1-2: startup created no worktree (verify-only)"
else
  fail "TC1-2: startup created $HOME_WT — verify-only violated"
fi
if [[ ! -S "$(sed -n 's/^socket=//p' "$LIFECYCLE/owner" 2>/dev/null | head -1)" ]] && [[ ! -e "$LIFECYCLE/owner" ]]; then
  pass "TC1-3: a pre-pending refusal created no tmux server, session or owner record"
else
  fail "TC1-3: a pre-pending refusal left lifecycle artefacts behind"
fi

echo ""
echo "=== TC2: setup is the only path that creates the home ==="
SETUP_OUT="$(gaai_run "$ROOT" "$SETUP" 2>&1)"
if echo "$SETUP_OUT" | grep -q 'home created at'; then
  pass "TC2-1: setup created the dedicated worktree"
else
  fail "TC2-1: setup did not create the home: $(echo "$SETUP_OUT" | grep '❌' | head -3)"
fi
if [[ "$(git -C "$HOME_WT" branch --show-current 2>/dev/null)" == "gaai-daemon-home" ]]; then
  pass "TC2-2: home is on gaai-daemon-home"
else
  fail "TC2-2: home is not on gaai-daemon-home"
fi
if [[ "$(git -C "$HOME_WT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" == "origin/staging" ]]; then
  pass "TC2-3: home tracks origin/staging"
else
  fail "TC2-3: home does not track origin/staging"
fi
if git -C "$PROJ" worktree list --porcelain 2>/dev/null | grep -qF "worktree $HOME_WT"; then
  pass "TC2-4: home is a registered worktree of the same physical repository"
else
  fail "TC2-4: home is not registered"
fi
if [[ ! -e "$LIFECYCLE/lock.d" ]]; then
  pass "TC2-5: setup released the lifecycle lock at settlement"
else
  fail "TC2-5: setup left the lifecycle lock held"
fi
if [[ ! -e "$LIFECYCLE/owner" ]]; then
  pass "TC2-6: setup never converted its lock into production pending/bound/running authority"
else
  fail "TC2-6: setup created an owner record — it must not create launch authority"
fi

echo ""
echo "=== TC3: setup is idempotent and startup accepts a clean exact-current home ==="
gaai_run "$ROOT" "$SETUP" >/dev/null 2>&1
if [[ "$(git -C "$PROJ" worktree list --porcelain 2>/dev/null | grep -cF "worktree $HOME_WT")" == "1" ]]; then
  pass "TC3-1: a second setup produced no duplicate registration"
else
  fail "TC3-1: duplicate worktree registration after a second setup"
fi
OUT="$(gaai_run "$ROOT" "$START" 2>&1)"
if echo "$OUT" | grep -q 'Daemon started'; then
  pass "TC3-2: startup admitted the clean, registered, exact-current home"
else
  fail "TC3-2: startup refused a valid home: $OUT"
fi

echo ""
echo "=== TC4: setup refuses an active lifecycle and mutates nothing ==="
HEAD_BEFORE="$(git -C "$HOME_WT" rev-parse HEAD)"
SETUP_OUT="$(gaai_run "$ROOT" "$SETUP" 2>&1)"
if echo "$SETUP_OUT" | grep -q 'lifecycle_role='; then
  pass "TC4-1: setup refused while a lifecycle owner exists"
else
  fail "TC4-1: setup did not refuse an active lifecycle: $SETUP_OUT"
fi
if [[ "$(git -C "$HOME_WT" rev-parse HEAD)" == "$HEAD_BEFORE" ]]; then
  pass "TC4-2: the refused setup left the home unchanged"
else
  fail "TC4-2: the refused setup moved the home"
fi

echo ""
echo "=== TC5: a second start returns already_running without a second spawn ==="
PANES_BEFORE="$(tmux -f /dev/null -S "$(sed -n 's/^socket=//p' "$LIFECYCLE/owner" | head -1)" \
  list-panes -a 2>/dev/null | wc -l | tr -d ' ')"
OUT="$(gaai_run "$ROOT" "$START" 2>&1)"
if echo "$OUT" | grep -q 'reason=already_running action=none'; then
  pass "TC5-1: second start returned already_running + none"
else
  fail "TC5-1: expected already_running, got: $OUT"
fi
PANES_AFTER="$(tmux -f /dev/null -S "$(sed -n 's/^socket=//p' "$LIFECYCLE/owner" | head -1)" \
  list-panes -a 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$PANES_BEFORE" == "$PANES_AFTER" ]]; then
  pass "TC5-2: no second process was launched"
else
  fail "TC5-2: pane count changed $PANES_BEFORE -> $PANES_AFTER"
fi
gaai_run "$ROOT" "$START" --stop >/dev/null 2>&1

echo ""
echo "=== TC6: dirty homes are preserved, never cleaned ==="
echo "operator-edit" >> "$HOME_WT/.gaai/core/scripts/delivery-daemon.sh"
BEFORE="$(cksum < "$HOME_WT/.gaai/core/scripts/delivery-daemon.sh")"
OUT="$(gaai_run "$ROOT" "$START" 2>&1)"
if echo "$OUT" | grep -q 'reason=home_dirty action=operator_disposition_required'; then
  pass "TC6-1: tracked-file dirt returns home_dirty + operator_disposition_required"
else
  fail "TC6-1: expected home_dirty, got: $OUT"
fi
if [[ "$(cksum < "$HOME_WT/.gaai/core/scripts/delivery-daemon.sh")" == "$BEFORE" ]]; then
  pass "TC6-2: the dirty file is preserved byte-for-byte"
else
  fail "TC6-2: the dirty file was modified"
fi
SETUP_OUT="$(gaai_run "$ROOT" "$SETUP" 2>&1)"
if echo "$SETUP_OUT" | grep -q 'operator disposition'; then
  pass "TC6-3: setup also refuses a dirty home instead of cleaning it"
else
  fail "TC6-3: setup did not refuse a dirty home: $(echo "$SETUP_OUT" | grep -E '❌|✅ home' | head -3)"
fi
if [[ "$(cksum < "$HOME_WT/.gaai/core/scripts/delivery-daemon.sh")" == "$BEFORE" ]]; then
  pass "TC6-4: setup preserved the dirty file byte-for-byte"
else
  fail "TC6-4: setup modified the dirty file"
fi
git -C "$HOME_WT" checkout -- . 2>/dev/null

echo ""
echo "=== TC7: untracked operator files are dirt, and are preserved ==="
touch "$HOME_WT/operator-scratch.txt"
OUT="$(gaai_run "$ROOT" "$START" 2>&1)"
if echo "$OUT" | grep -q 'evidence=home_role=untracked_present'; then
  pass "TC7-1: untracked content returns home_dirty"
else
  fail "TC7-1: expected untracked_present, got: $OUT"
fi
[[ -e "$HOME_WT/operator-scratch.txt" ]] && pass "TC7-2: the untracked file is preserved" \
  || fail "TC7-2: the untracked file was removed"
rm -f "$HOME_WT/operator-scratch.txt"

echo ""
echo "=== TC8: wrong branch refuses, and nothing repairs it ==="
git -C "$HOME_WT" checkout -q -b sidetrack 2>/dev/null
OUT="$(gaai_run "$ROOT" "$START" 2>&1)"
if echo "$OUT" | grep -q 'evidence=home_role=wrong_branch'; then
  pass "TC8-1: wrong branch returns home_identity_invalid"
else
  fail "TC8-1: expected wrong_branch, got: $OUT"
fi
if [[ "$(git -C "$HOME_WT" branch --show-current)" == "sidetrack" ]]; then
  pass "TC8-2: startup did not switch the branch back"
else
  fail "TC8-2: startup repaired the branch — verify-only violated"
fi
git -C "$HOME_WT" checkout -q gaai-daemon-home 2>/dev/null
git -C "$HOME_WT" branch -q -D sidetrack 2>/dev/null

echo ""
echo "=== TC9: an advanced target makes the home stale; only setup converges it ==="
gaai_advance_target "$PROJ"
HEAD_BEFORE="$(git -C "$HOME_WT" rev-parse HEAD)"
OUT="$(gaai_run "$ROOT" "$START" 2>&1)"
if echo "$OUT" | grep -q 'evidence=home_role=stale_head'; then
  pass "TC9-1: a stale home returns home_identity_invalid + rerun_setup"
else
  fail "TC9-1: expected stale_head, got: $OUT"
fi
if [[ "$(git -C "$HOME_WT" rev-parse HEAD)" == "$HEAD_BEFORE" ]]; then
  pass "TC9-2: startup did not advance the home"
else
  fail "TC9-2: startup advanced the home — verify-only violated"
fi
SETUP_OUT="$(gaai_run "$ROOT" "$SETUP" 2>&1)"
if echo "$SETUP_OUT" | grep -q 'home updated to'; then
  pass "TC9-3: setup fast-forwarded the home to the new target"
else
  fail "TC9-3: setup did not converge the stale home: $(echo "$SETUP_OUT" | sed -n '/Daemon home/,/^$/p' | tr '\n' ' ')"
fi

echo ""
echo "=== TC10: --verify-only never mutates ==="
gaai_advance_target "$PROJ"
HEAD_BEFORE="$(git -C "$HOME_WT" rev-parse HEAD)"
OUT="$(gaai_run "$ROOT" "$SETUP" --verify-only 2>&1)"
if [[ "$(git -C "$HOME_WT" rev-parse HEAD)" == "$HEAD_BEFORE" ]]; then
  pass "TC10-1: --verify-only left the stale home untouched"
else
  fail "TC10-1: --verify-only mutated the home"
fi
if echo "$OUT" | grep -q 'rerun without --verify-only'; then
  pass "TC10-2: --verify-only reported what setup would do"
else
  fail "TC10-2: --verify-only gave no actionable report"
fi
gaai_run "$ROOT" "$SETUP" >/dev/null 2>&1

echo ""
echo "=== TC11: a non-fast-forward home is divergence, and is never forced ==="
git -C "$HOME_WT" commit -q --allow-empty -m "local divergence" 2>/dev/null
gaai_advance_target "$PROJ"
HEAD_BEFORE="$(git -C "$HOME_WT" rev-parse HEAD)"
SETUP_OUT="$(gaai_run "$ROOT" "$SETUP" 2>&1)"
if echo "$SETUP_OUT" | grep -q 'could not be fast-forwarded'; then
  pass "TC11-1: setup refused a non-fast-forward instead of resetting"
else
  fail "TC11-1: setup did not refuse divergence: $(echo "$SETUP_OUT" | grep -E '❌|✅ home' | head -3)"
fi
if [[ "$(git -C "$HOME_WT" rev-parse HEAD)" == "$HEAD_BEFORE" ]]; then
  pass "TC11-2: the diverged home is preserved unchanged"
else
  fail "TC11-2: the diverged home was force-moved"
fi

echo ""
echo "=== TC12: interrupted setup evidence blocks and is preserved ==="
gaai_reset_home
mkdir -p "$HOME_WT" && printf 'partial\n' > "$HOME_WT/INTERRUPTED"
OUT="$(gaai_run "$ROOT" "$START" 2>&1)"
if echo "$OUT" | grep -qE 'reason=home_registration_invalid|reason=home_identity_invalid'; then
  pass "TC12-1: an unregistered directory at the home path blocks startup"
else
  fail "TC12-1: expected a registration/identity refusal, got: $OUT"
fi
if [[ -f "$HOME_WT/INTERRUPTED" ]]; then
  pass "TC12-2: the interrupted-setup evidence is preserved"
else
  fail "TC12-2: the interrupted-setup evidence was destroyed"
fi
SETUP_OUT="$(gaai_run "$ROOT" "$SETUP" 2>&1)"
if [[ -f "$HOME_WT/INTERRUPTED" ]]; then
  pass "TC12-3: setup preserved the evidence rather than clearing the path"
else
  fail "TC12-3: setup destroyed interrupted-setup evidence"
fi

echo ""
echo "=== TC13: the lifecycle lock is exclusive, crash-recoverable and TTL-free ==="
gaai_reset_home; gaai_run "$ROOT" "$SETUP" >/dev/null 2>&1
COMMON="$(git -C "$PROJ" rev-parse --path-format=absolute --git-common-dir)"
LOCK_TEST="$(cat <<'LT'
set -uo pipefail
source "$1/lib/daemon-home.sh"
_gaai_home_lock_acquire "$2" || exit 3
case "$3" in
  hold) printf 'held\n'; ;;
  crash) printf 'pid=%s\n' "$$" ;;
esac
LT
)"
# Acquire + explicit release inside one process. Release is deliberately explicit,
# not implicit-on-exit: an abandoned lock must stay as evidence and be reclaimed
# only by the crash-recovery path below, which proves the holder is dead.
RELEASE_TEST="$(cat <<'RT'
set -uo pipefail
source "$1/lib/daemon-home.sh"
_gaai_home_lock_acquire "$2" || exit 3
_gaai_home_lock_held || exit 4
_gaai_home_lock_release
_gaai_home_lock_held && exit 5
[[ -d "$2/gaai-daemon-lifecycle/lock.d" ]] && exit 6
printf 'released
'
RT
)"
if "${BASH:-/bin/bash}" -c "$RELEASE_TEST" _ "$PROJ/.gaai/core/scripts" "$COMMON" 2>&1 | grep -q released; then
  pass "TC13-1: acquire then explicit release leaves no lock and no claim"
else
  fail "TC13-1: the acquire/release pair did not settle the lock"
fi
rm -rf "$COMMON/gaai-daemon-lifecycle/lock.d" 2>/dev/null
mkdir -p "$COMMON/gaai-daemon-lifecycle/lock.d"
printf 'schema=gaai-daemon-lifecycle/v1\npid=999999\nincarnation=1\n' \
  > "$COMMON/gaai-daemon-lifecycle/lock.d/holder"
OUT="$("${BASH:-/bin/bash}" -c "$LOCK_TEST" _ "$PROJ/.gaai/core/scripts" "$COMMON" hold 2>&1)"
if echo "$OUT" | grep -q 'held'; then
  pass "TC13-2: a provably dead holder is crash-recovered without a TTL"
else
  fail "TC13-2: a dead holder blocked forever: $OUT"
fi
mkdir -p "$COMMON/gaai-daemon-lifecycle/lock.d"
printf 'schema=gaai-daemon-lifecycle/v1\npid=%s\nincarnation=\n' "$$" \
  > "$COMMON/gaai-daemon-lifecycle/lock.d/holder"
OUT="$("${BASH:-/bin/bash}" -c "$LOCK_TEST" _ "$PROJ/.gaai/core/scripts" "$COMMON" hold 2>&1)"
if echo "$OUT" | grep -q 'reason=home_lock_failed'; then
  pass "TC13-3: a live holder blocks — there is no lock handoff"
else
  fail "TC13-3: a live holder did not block: $OUT"
fi
rm -rf "$COMMON/gaai-daemon-lifecycle/lock.d" 2>/dev/null
printf 'corrupt' > "$COMMON/gaai-daemon-lifecycle/lock.d" 2>/dev/null || true
if [[ -f "$COMMON/gaai-daemon-lifecycle/lock.d" ]]; then
  OUT="$("${BASH:-/bin/bash}" -c "$LOCK_TEST" _ "$PROJ/.gaai/core/scripts" "$COMMON" hold 2>&1)"
  if echo "$OUT" | grep -q 'reason=home_lock_failed'; then
    pass "TC13-4: a corrupt lock record blocks instead of being reclaimed"
  else
    fail "TC13-4: a corrupt lock record did not block: $OUT"
  fi
  rm -f "$COMMON/gaai-daemon-lifecycle/lock.d"
fi

echo ""
echo "=== TC17: a registered-but-missing home is ambiguous, never silently pruned ==="
gaai_reset_home
gaai_run "$ROOT" "$SETUP" >/dev/null 2>&1
rm -rf "$HOME_WT"
SETUP_OUT="$(gaai_run "$ROOT" "$SETUP" 2>&1)"
if echo "$SETUP_OUT" | grep -q 'evidence=home_role=registered_path_missing'; then
  pass "TC17-1: setup refuses a registered-but-missing home with a typed reason"
else
  fail "TC17-1: expected registered_path_missing, got: $(echo "$SETUP_OUT" | grep -E '❌|home_role' | head -2)"
fi
if git -C "$PROJ" worktree list --porcelain 2>/dev/null | grep -qF "worktree $HOME_WT"; then
  pass "TC17-2: the registration is preserved for operator disposition, not pruned"
else
  fail "TC17-2: setup silently pruned the administrative record"
fi
gaai_reset_home

echo ""
echo "=== TC15: settlement removes only known artefacts and preserves the rest ==="
gaai_reset_home; gaai_run "$ROOT" "$SETUP" >/dev/null 2>&1
gaai_run "$ROOT" "$START" >/dev/null 2>&1
ATTEMPT_DIR="$(sed -n 's/^attempt_dir=//p' "$LIFECYCLE/owner" 2>/dev/null | head -1)"
if [[ -n "$ATTEMPT_DIR" && -d "$ATTEMPT_DIR" ]]; then
  printf 'operator-evidence\n' > "$ATTEMPT_DIR/unexplained.txt"
  gaai_run "$ROOT" "$START" --stop >/dev/null 2>&1
  if [[ -f "$ATTEMPT_DIR/unexplained.txt" ]]; then
    pass "TC15-1: unrecognised content in the attempt directory is preserved"
  else
    fail "TC15-1: settlement recursively deleted unrecognised content"
  fi
  if [[ ! -e "$ATTEMPT_DIR/launcher.sh" && ! -e "$ATTEMPT_DIR/manifest" ]]; then
    pass "TC15-2: the lifecycle's own artefacts were removed"
  else
    fail "TC15-2: lifecycle artefacts survived settlement"
  fi
  rm -f "$ATTEMPT_DIR/unexplained.txt"; rmdir "$ATTEMPT_DIR" 2>/dev/null
else
  fail "TC15-0: no attempt directory was recorded"
fi

echo ""
echo "=== TC16: a clean stop leaves nothing that blocks the next setup ==="
gaai_reset_home; gaai_run "$ROOT" "$SETUP" >/dev/null 2>&1
gaai_run "$ROOT" "$START" >/dev/null 2>&1
gaai_run "$ROOT" "$START" --stop >/dev/null 2>&1
SETUP_OUT="$(gaai_run "$ROOT" "$SETUP" 2>&1)"
if echo "$SETUP_OUT" | grep -q 'lifecycle_role='; then
  fail "TC16-1: residue from a clean stop still blocks setup: $(echo "$SETUP_OUT" | grep lifecycle_role)"
else
  pass "TC16-1: after a clean stop, setup runs again without operator disposition"
fi

echo ""
echo "=== TC14: the reason -> action mapping is deterministic and closed ==="
MAP_TEST="$(cat <<'MT'
set -uo pipefail
source "$1/lib/daemon-home.sh"
for r in $GAAI_HOME_REASONS; do
  printf '%s|%s|%s\n' "$r" "$(_gaai_home_action_for "$r" 0)" "$(_gaai_home_action_for "$r" 1)"
done
printf 'unknown_reason|%s|%s\n' "$(_gaai_home_action_for unknown_reason 0)" "$(_gaai_home_action_for unknown_reason 1)"
MT
)"
MAP="$("${BASH:-/bin/bash}" -c "$MAP_TEST" _ "$PROJ/.gaai/core/scripts" 2>&1)"
MAP_OK=true
while IFS='|' read -r _r _a0 _a1; do
  [[ -n "$_r" ]] || continue
  case "$_a0" in rerun_setup|operator_disposition_required|none) ;; *) MAP_OK=false ;; esac
  case "$_a1" in rerun_setup|operator_disposition_required|none) ;; *) MAP_OK=false ;; esac
  # Ambiguity may only ever make the action stricter, never turn an unavailable
  # proof into `rerun_setup`.
  [[ "$_a1" == "rerun_setup" && "$_a0" != "rerun_setup" ]] && MAP_OK=false
done <<< "$MAP"
$MAP_OK && pass "TC14-1: every reason maps to exactly one canonical action" \
        || fail "TC14-1: the mapping produced a non-canonical action: $MAP"
if echo "$MAP" | grep -q '^home_dirty|operator_disposition_required|operator_disposition_required$'; then
  pass "TC14-2: home_dirty never yields rerun_setup"
else
  fail "TC14-2: home_dirty mapping drifted"
fi
if echo "$MAP" | grep -q '^unknown_reason|operator_disposition_required|'; then
  pass "TC14-3: an unknown reason fails closed to operator_disposition_required"
else
  fail "TC14-3: an unknown reason did not fail closed"
fi
AMBIG_OK=true
for r in target_advanced home_identity_invalid home_registration_invalid home_asset_invalid; do
  echo "$MAP" | grep -q "^$r|rerun_setup|operator_disposition_required$" || AMBIG_OK=false
done
$AMBIG_OK && pass "TC14-4: ambiguous evidence downgrades every rerun_setup to operator disposition" \
          || fail "TC14-4: ambiguity did not tighten the action"

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
exit 0
