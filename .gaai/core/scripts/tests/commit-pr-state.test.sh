#!/usr/bin/env bash
# commit-pr-state.test.sh — AC5 regression for E222S02
#
# Asserts that handle_commit_phase guards the merge path by re-reading the
# selected PR's state (via `gh pr view --json state`) before calling the
# head-matched direct merge, when Guard 1 or 2 selected a PR via --state all.
#
# T1: CLOSED PR selected by Guard 2 → gh pr create is called (fresh PR), gh pr
#     merge is NOT called with the closed URL (AC2)
# T2: MERGED PR selected by Guard 2 → phase_status reconciled to done, gh pr
#     merge NOT called (AC3)
# T3: OPEN PR selected by Guard 2   → exact-SHA REST merge is called normally
# T4: merge API transport fails after the exact tested head merged → success
# T5: PR head moves during merge → TEST_GATE_BLOCKED / failed, never escalated
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
#   GH_PR_STATE_AFTER_MERGE — optional state after the stub observes a merge call
#   GH_PR_NUMBER      — number returned for `gh pr view <branch> --json number`
#   GH_BRANCH_PR_NUMBER / GH_URL_PR_NUMBER — optional divergent lookup results
#   GH_PR_HEAD_SHA    — head SHA returned for `gh pr view <url> --json headRefOid`
#   GH_PR_HEAD_SHA_AFTER_MERGE — optional head after the stub observes a merge call
#   GH_PR_FRESH_URL   — URL returned by `gh pr create`
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
        _merge_seen=false
        grep -qE "gh api --method PUT .*pulls/[0-9]+/merge|gh pr merge" "$GH_CALL_LOG" 2>/dev/null && _merge_seen=true
        if   [[ "$_args" == *"--json state,headRefOid"* ]]; then
          _state="${GH_PR_STATE:-OPEN}"
          _head="${GH_PR_HEAD_SHA:-missing}"
          [[ "$_merge_seen" == "true" && -n "${GH_PR_STATE_AFTER_MERGE:-}" ]] && _state="$GH_PR_STATE_AFTER_MERGE"
          [[ "$_merge_seen" == "true" && -n "${GH_PR_HEAD_SHA_AFTER_MERGE:-}" ]] && _head="$GH_PR_HEAD_SHA_AFTER_MERGE"
          printf '%s\t%s\n' "$_state" "$_head"
        elif [[ "$_args" == *"--json state"* ]];            then
          if [[ "$_merge_seen" == "true" && -n "${GH_PR_STATE_AFTER_MERGE:-}" ]]; then
            echo "$GH_PR_STATE_AFTER_MERGE"
          else
            echo "${GH_PR_STATE:-OPEN}"
          fi
        elif [[ "$_args" == *"--json number"* ]];           then
          if [[ "$_target" == http* ]]; then
            echo "${GH_URL_PR_NUMBER:-${GH_PR_NUMBER:-99}}"
          else
            echo "${GH_BRANCH_PR_NUMBER:-${GH_PR_NUMBER:-99}}"
          fi
        elif [[ "$_args" == *"--json headRefOid"* ]];       then
          if [[ "$_merge_seen" == "true" && -n "${GH_PR_HEAD_SHA_AFTER_MERGE:-}" ]]; then
            echo "$GH_PR_HEAD_SHA_AFTER_MERGE"
          else
            echo "${GH_PR_HEAD_SHA:-missing}"
          fi
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
        # Admin-fallback behavior can be controlled separately when exercised.
        [[ -n "${GH_MERGE_STDERR:-}" ]] && echo "${GH_MERGE_STDERR}" >&2
        exit "${GH_MERGE_EXIT:-0}"
        ;;
    esac
    ;;
  api)
    [[ -n "${GH_MERGE_STDERR:-}" ]] && echo "${GH_MERGE_STDERR}" >&2
    [[ -z "${GH_MERGE_EXIT:-}" ]] && echo "${GH_MERGE_API_RESP:-true}"
    exit "${GH_MERGE_EXIT:-0}"
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
# T1: CLOSED PR selected → gh pr create called, merge endpoint NOT called
# ────────────────────────────────────────────────────────────────────────────
echo "--- T1: CLOSED PR ---"
SID1="TST-PCS01"
setup_story "$SID1"
write_backlog "$SID1"
export GH_PR_HEAD_SHA="$(git -C "$PROJ" rev-parse "story/$SID1")"

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

echo "T1b: merge endpoint NOT called for the closed PR"
if grep -qE "gh api --method PUT .*pulls/97/merge|gh pr merge.*${STALE_T1}" "$GH_CALL_LOG"; then
  fail "T1b: merge was attempted for closed PR ($STALE_T1)"
else
  pass "T1b: no merge attempted for closed PR"
fi

# ────────────────────────────────────────────────────────────────────────────
# T2: MERGED PR selected → reconcile to done, merge endpoint NOT called
# ────────────────────────────────────────────────────────────────────────────
echo "--- T2: MERGED PR ---"
SID2="TST-PCS02"
setup_story "$SID2"
write_backlog "$SID2"
export GH_PR_HEAD_SHA="$(git -C "$PROJ" rev-parse "story/$SID2")"

STALE_T2="https://github.com/test/repo/pull/98"
export GH_PR_STALE_URL="$STALE_T2"
export GH_PR_STATE="MERGED"
export GAAI_AUTO_MERGE_POLICY="off"
: > "$GH_CALL_LOG"

set +e
handle_commit_phase "$SID2" "trace-t2"
set -e

echo "T2a: merge endpoint NOT called for MERGED PR"
if grep -qE "gh api --method PUT .*pulls/98/merge|gh pr merge" "$GH_CALL_LOG"; then
  fail "T2a: merge was called even though selected PR is MERGED"
else
  pass "T2a: merge endpoint NOT called"
fi

echo "T2b: phase_status=done after MERGED reconcile"
T2_PHASE=$(grep -A 10 "id: ${SID2}" "$BACKLOG_FILE" | grep "phase_status:" | head -1 | awk '{print $2}')
if [[ "$T2_PHASE" == "done" ]]; then
  pass "T2b: phase_status=done (MERGED early-exit reconciled correctly)"
else
  fail "T2b: phase_status='${T2_PHASE}' (expected done)"
fi

# ────────────────────────────────────────────────────────────────────────────
# T3: OPEN PR selected → exact-head merge endpoint is called
# ────────────────────────────────────────────────────────────────────────────
echo "--- T3: OPEN PR ---"
SID3="TST-PCS03"
setup_story "$SID3"
write_backlog "$SID3"
export GH_PR_HEAD_SHA="$(git -C "$PROJ" rev-parse "story/$SID3")"

OPEN_URL_T3="https://github.com/test/repo/pull/99"
export GH_PR_STALE_URL="$OPEN_URL_T3"
export GH_PR_STATE="OPEN"
export GH_PR_STATE_AFTER_MERGE="MERGED"
export GH_PR_NUMBER="99"
export GH_BRANCH_PR_NUMBER="777"  # sibling PR for the same branch, different base
export GH_URL_PR_NUMBER="99"      # exact selected/gated PR
export GAAI_AUTO_MERGE_POLICY="on"
: > "$GH_CALL_LOG"

set +e
handle_commit_phase "$SID3" "trace-t3"
set -e

echo "T3a: direct REST merge called for the selected PR"
if grep -q "gh api --method PUT repos/{owner}/{repo}/pulls/99/merge" "$GH_CALL_LOG"; then
  pass "T3a: exact PR merge API called"
else
  fail "T3a: exact PR merge API was not called"
fi

echo "T3b: merge API pins the expected head SHA"
if grep "gh api --method PUT" "$GH_CALL_LOG" 2>/dev/null | grep -q -- "sha=$GH_PR_HEAD_SHA"; then
  pass "T3b: merge API sends the exact sha precondition"
else
  fail "T3b: merge API did not pin the expected head SHA"
fi

echo "T3c: normal merge path never enables persistent auto-merge"
if grep "gh pr merge" "$GH_CALL_LOG" 2>/dev/null | grep -q -- "--auto"; then
  fail "T3c: gh pr merge still uses --auto"
else
  pass "T3c: no --auto request was made"
fi

echo "T3d: sibling PR discovered by branch lookup is never merged"
if grep -q "pulls/777/merge" "$GH_CALL_LOG"; then
  fail "T3d: merge targeted sibling branch PR #777"
else
  pass "T3d: merge remained bound to selected URL's PR #99"
fi

unset GH_PR_STATE_AFTER_MERGE
unset GH_BRANCH_PR_NUMBER GH_URL_PR_NUMBER

# ────────────────────────────────────────────────────────────────────────────
# T4: the merge API's transport reports failure after the server merged the
#     exact tested head. Durable verification MUST treat this as success.
# ────────────────────────────────────────────────────────────────────────────
echo "--- T4: merge response fails after the expected head merged ---"
SID4="TST-PCS04"
setup_story "$SID4"
write_backlog "$SID4"
export GH_PR_HEAD_SHA="$(git -C "$PROJ" rev-parse "story/$SID4")"

OPEN_URL_T4="https://github.com/test/repo/pull/104"
export GH_PR_STALE_URL="$OPEN_URL_T4"
export GH_PR_STATE="OPEN"                       # PR is open at the pre-merge guard
export GH_PR_STATE_AFTER_MERGE="MERGED"         # server merged before local cleanup failed
export GH_PR_NUMBER="104"
export GAAI_AUTO_MERGE_POLICY="on"
export GH_MERGE_EXIT="1"                         # gh returns non-zero...
export GH_MERGE_STDERR="transport closed after server accepted merge"
: > "$GH_CALL_LOG"

set +e
handle_commit_phase "$SID4" "trace-t4"
T4_RC=$?
set -e

echo "T4a: handle_commit_phase returns 0 (not escalated)"
if [[ "$T4_RC" -eq 0 ]]; then
  pass "T4a: handle_commit_phase returned 0"
else
  fail "T4a: handle_commit_phase returned $T4_RC (durable merged state ignored)"
fi

echo "T4b: phase_status=done (merge treated as success, not escalated)"
T4_PHASE=$(grep -A 10 "id: ${SID4}" "$BACKLOG_FILE" | grep "phase_status:" | head -1 | awk '{print $2}')
if [[ "$T4_PHASE" == "done" ]]; then
  pass "T4b: phase_status=done"
else
  fail "T4b: phase_status='${T4_PHASE}' (expected done — durable merge verification failed)"
fi

echo "T4c: merge API WAS attempted"
if grep -q "gh api --method PUT" "$GH_CALL_LOG" 2>/dev/null; then
  pass "T4c: merge API attempted"
else
  fail "T4c: merge API NOT attempted"
fi

unset GH_MERGE_EXIT GH_MERGE_STDERR GH_PR_STATE_AFTER_MERGE

# ────────────────────────────────────────────────────────────────────────────
# T5: head changes after the gate but before the merge can land. This is a
#     TEST_GATE_BLOCKED failure, not a generic auto-merge escalation.
# ────────────────────────────────────────────────────────────────────────────
echo "--- T5: PR head moves during exact-head merge ---"
SID5="TST-PCS05"
setup_story "$SID5"
write_backlog "$SID5"
export GH_PR_HEAD_SHA="$(git -C "$PROJ" rev-parse "story/$SID5")"

OPEN_URL_T5="https://github.com/test/repo/pull/105"
export GH_PR_STALE_URL="$OPEN_URL_T5"
export GH_PR_STATE="OPEN"
export GH_PR_STATE_AFTER_MERGE="OPEN"
export GH_PR_HEAD_SHA_AFTER_MERGE="$(printf '%040d' 3)"
export GH_PR_NUMBER="105"
export GH_MERGE_EXIT="1"
export GH_MERGE_STDERR="head sha does not match"
export GAAI_AUTO_MERGE_POLICY="on"
: > "$GH_CALL_LOG"

set +e
handle_commit_phase "$SID5" "trace-t5"
T5_RC=$?
set -e

echo "T5a: moved head blocks the commit phase"
if [[ "$T5_RC" -ne 0 ]]; then
  pass "T5a: handle_commit_phase returned non-zero"
else
  fail "T5a: moved PR head was authorized"
fi

echo "T5b: moved head uses failed phase_status, not generic escalation"
T5_PHASE=$(grep -A 10 "id: ${SID5}" "$BACKLOG_FILE" | grep "phase_status:" | head -1 | awk '{print $2}')
if [[ "$T5_PHASE" == "failed" ]]; then
  pass "T5b: phase_status=failed (TEST_GATE_BLOCKED semantics)"
else
  fail "T5b: phase_status='${T5_PHASE}' (expected failed)"
fi

unset GH_MERGE_EXIT GH_MERGE_STDERR GH_PR_STATE_AFTER_MERGE \
  GH_PR_HEAD_SHA_AFTER_MERGE

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
