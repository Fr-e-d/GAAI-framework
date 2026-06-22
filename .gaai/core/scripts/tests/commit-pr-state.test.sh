#!/usr/bin/env bash
# commit-pr-state.test.sh — AC5 regression for E222S02
#
# Asserts that handle_commit_phase guards the merge path by re-reading the
# selected PR's state (via `gh pr view --json state`) before calling
# `gh pr merge --auto`, when Guard 1 or 2 has selected a PR via --state all.
#
# T1: CLOSED PR selected by Guard 2 → gh pr create is called (fresh PR), gh pr
#     merge is NOT called with the closed URL (AC2)
# T2: MERGED PR selected by Guard 2 → phase_status reconciled to done, gh pr
#     merge NOT called (AC3)
# T3: OPEN PR selected by Guard 2   → gh pr merge IS called normally (AC1, regression)
#
# Run: bash .gaai/core/scripts/tests/commit-pr-state.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
SCHEDULER="$SCRIPTS/backlog-scheduler.sh"
DISPATCH="$SCRIPTS/daemon-dispatch.sh"

SANDBOX="$(mktemp -d /tmp/gaai-pr-state-test-XXXXXX)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# ── Shared git fixture ────────────────────────────────────────────────────────
REMOTE="$SANDBOX/remote.git"
PROJ="$SANDBOX/project"
WT_BASE="$SANDBOX/worktrees"
LOCK_DIR="$SANDBOX/locks"
STUB_BIN="$SANDBOX/bin"
GH_CALL_LOG="$SANDBOX/gh-calls.log"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG_FILE="$PROJ/$BACKLOG_REL"

mkdir -p "$WT_BASE" "$LOCK_DIR" "$STUB_BIN"
: > "$GH_CALL_LOG"

git init --quiet --bare "$REMOTE"
git init --quiet "$PROJ"
git -C "$PROJ" config user.email t@t.t
git -C "$PROJ" config user.name "GAAI Test"
git -C "$PROJ" checkout -q -b staging
echo seed > "$PROJ/seed.txt"
mkdir -p "$(dirname "$BACKLOG_FILE")"
git -C "$PROJ" add -A
git -C "$PROJ" commit -q -m "initial"
git -C "$PROJ" remote add origin "$REMOTE"
git -C "$PROJ" push -q origin staging

# Helper: create story branch with one commit diverged from staging and push it.
# Does NOT pre-create a worktree — handle_commit_phase self-heals if the worktree
# dir is absent, so no worktree add is needed here (and it avoids the "branch already
# checked out in main repo" error that git raises when the branch is still active).
setup_story() {
  local sid="$1"
  git -C "$PROJ" checkout -q staging
  git -C "$PROJ" checkout -q -b "story/$sid"
  echo "$sid" > "$PROJ/${sid}.txt"
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m "impl($sid): work"
  git -C "$PROJ" push -q origin "story/$sid"
  git -C "$PROJ" checkout -q staging
}

# Helper: write a minimal backlog entry (phase_status=qa_passed) and push to staging
write_backlog() {
  local sid="$1"
  cat > "$BACKLOG_FILE" <<YAML
items:
- id: ${sid}
  status: in_progress
  phase_status: qa_passed
  delivery_pipeline: 3phase
YAML
  git -C "$PROJ" add "$BACKLOG_REL"
  git -C "$PROJ" commit -q -m "backlog(${sid}): test fixture"
  git -C "$PROJ" push -q origin staging
  git -C "$PROJ" fetch -q origin staging
}

# ── gh stub ──────────────────────────────────────────────────────────────────
# Uses env vars to control what each call returns; records every call to GH_CALL_LOG.
#   GH_PR_STALE_URL   — URL returned for `gh pr list` (Guard 2 hit)
#   GH_PR_STATE       — state returned for `gh pr view <url> --json state`
#   GH_PR_NUMBER      — number returned for `gh pr view <branch> --json number`
#   GH_PR_FRESH_URL   — URL returned by `gh pr create`
#   GH_AUTOMERGE_RESP — response for `gh pr view --json autoMergeRequest`
cat > "$STUB_BIN/gh" <<'GHEOF'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_CALL_LOG"
subcmd="${1:-}"; shift
case "$subcmd" in
  pr)
    action="${1:-}"; shift
    case "$action" in
      list)
        echo "${GH_PR_STALE_URL:-}"
        ;;
      view)
        _target="${1:-}"; shift
        _args="$*"
        if   [[ "$_args" == *"--json state"* ]];            then echo "${GH_PR_STATE:-OPEN}"
        elif [[ "$_args" == *"--json number"* ]];           then echo "${GH_PR_NUMBER:-99}"
        elif [[ "$_args" == *"--json autoMergeRequest"* ]]; then echo "${GH_AUTOMERGE_RESP:-null}"
        elif [[ "$_args" == *"--json mergeable"* ]];        then echo '{"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}'
        elif [[ "$_args" == *"--json url"* ]];              then echo "${GH_PR_STALE_URL:-}"
        else echo '{}'
        fi
        ;;
      create)
        echo "${GH_PR_FRESH_URL:-https://github.com/test/repo/pull/100}"
        exit 0
        ;;
      merge)
        exit 0
        ;;
    esac
    ;;
esac
GHEOF
chmod +x "$STUB_BIN/gh"

# Stub node to suppress routing-record emission
cat > "$STUB_BIN/node" <<'NODEEOF'
#!/usr/bin/env bash
exit 0
NODEEOF
chmod +x "$STUB_BIN/node"

export PATH="$STUB_BIN:$PATH"
export GH_CALL_LOG

# ── Source daemon-dispatch.sh with minimal required env ──────────────────────
export PROJECT_DIR="$PROJ"
export BACKLOG_FILE
export GAAI_WORKTREES_BASE="$WT_BASE"
export TARGET_BRANCH="staging"
export SCHEDULER
export LOCK_DIR

source "$DISPATCH" 2>/dev/null || true

# Override heavy dependencies that are not relevant to the PR-state guard
log()                          { :; }
CYAN="" YELLOW="" NC="" RED="" GREEN="" BOLD=""
_ensure_worktree_deps_fresh()  { return 0; }
_check_worktree_integrity()    { return 0; }
_recover_worktree_safe_base()  { return 1; }
chore_commit_field()           { return 0; }
chore_commit_multi_field()     { return 0; }
notify_escalation_inline()     { return 0; }
_run_triage_for_story()        { return 0; }
_emit_commit_routing_record()  { return 0; }

echo ""
echo "=== commit-pr-state: AC5 — PR-state guard in handle_commit_phase ==="
echo ""

# ────────────────────────────────────────────────────────────────────────────
# T1: CLOSED PR selected → gh pr create called, gh pr merge NOT called
# ────────────────────────────────────────────────────────────────────────────
echo "--- T1: CLOSED PR ---"
SID1="TST-PCS01"
setup_story "$SID1"
write_backlog "$SID1"

STALE_T1="https://github.com/test/repo/pull/97"
export GH_PR_STALE_URL="$STALE_T1"
export GH_PR_STATE="CLOSED"
export GH_PR_FRESH_URL="https://github.com/test/repo/pull/100"
export GH_PR_NUMBER="100"
export GAAI_AUTO_MERGE_POLICY="off"
: > "$GH_CALL_LOG"

set +e
handle_commit_phase "$SID1" "trace-t1"
set -e

echo "T1a: gh pr create called (fresh PR opened after CLOSED guard)"
if grep -q "gh pr create" "$GH_CALL_LOG"; then
  pass "T1a: gh pr create was called"
else
  fail "T1a: gh pr create NOT called — CLOSED guard did not clear _skip_pr_create"
fi

echo "T1b: gh pr merge NOT called with the closed URL"
if grep "gh pr merge" "$GH_CALL_LOG" 2>/dev/null | grep -q "$STALE_T1"; then
  fail "T1b: gh pr merge was called with closed URL ($STALE_T1)"
else
  pass "T1b: gh pr merge NOT called with closed URL"
fi

# ────────────────────────────────────────────────────────────────────────────
# T2: MERGED PR selected → reconcile to done, gh pr merge NOT called
# ────────────────────────────────────────────────────────────────────────────
echo "--- T2: MERGED PR ---"
SID2="TST-PCS02"
setup_story "$SID2"
write_backlog "$SID2"

STALE_T2="https://github.com/test/repo/pull/98"
export GH_PR_STALE_URL="$STALE_T2"
export GH_PR_STATE="MERGED"
export GAAI_AUTO_MERGE_POLICY="off"
: > "$GH_CALL_LOG"

set +e
handle_commit_phase "$SID2" "trace-t2"
set -e

echo "T2a: gh pr merge NOT called for MERGED PR"
if grep -q "gh pr merge" "$GH_CALL_LOG" 2>/dev/null; then
  fail "T2a: gh pr merge was called even though selected PR is MERGED"
else
  pass "T2a: gh pr merge NOT called"
fi

echo "T2b: phase_status=done after MERGED reconcile"
T2_PHASE=$(grep -A 10 "id: ${SID2}" "$BACKLOG_FILE" | grep "phase_status:" | head -1 | awk '{print $2}')
if [[ "$T2_PHASE" == "done" ]]; then
  pass "T2b: phase_status=done (MERGED early-exit reconciled correctly)"
else
  fail "T2b: phase_status='${T2_PHASE}' (expected done)"
fi

# ────────────────────────────────────────────────────────────────────────────
# T3: OPEN PR selected → gh pr merge IS called (regression — happy path unchanged)
# ────────────────────────────────────────────────────────────────────────────
echo "--- T3: OPEN PR ---"
SID3="TST-PCS03"
setup_story "$SID3"
write_backlog "$SID3"

OPEN_URL_T3="https://github.com/test/repo/pull/99"
export GH_PR_STALE_URL="$OPEN_URL_T3"
export GH_PR_STATE="OPEN"
export GH_PR_NUMBER="99"
export GH_AUTOMERGE_RESP='{"mergeType":"SQUASH"}'
export GAAI_AUTO_MERGE_POLICY="on"
: > "$GH_CALL_LOG"

set +e
handle_commit_phase "$SID3" "trace-t3"
set -e

echo "T3a: gh pr merge called with the OPEN URL (happy path unchanged)"
if grep "gh pr merge" "$GH_CALL_LOG" 2>/dev/null | grep -q "$OPEN_URL_T3"; then
  pass "T3a: gh pr merge called with OPEN URL"
else
  fail "T3a: gh pr merge NOT called with OPEN URL — regression in happy path"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "FAILURES: $FAIL_COUNT"
  exit 1
fi
