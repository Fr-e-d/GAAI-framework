#!/usr/bin/env bash
# reconcile-pr-number.test.sh — regression guard for the pr_number-unbound bug.
#
# _reconcile_merged_pr() used to read an ambient global `pr_number` in its
# chore-commit branch, but only 2 of its 5 callers set that global. The other
# three paths (pr-watcher, stale-check, drift-recovery) therefore hit
# "pr_number: unbound variable" under `set -u`, aborting the reconcile so a
# merged story was never marked done (it looped in_progress every scan).
#
# Fix: pr_number is a function parameter ($3) with an empty default, so the
# status reconcile ALWAYS lands regardless of caller.
#
# This test is self-contained (it does NOT depend on the awk-in-heredoc function
# extraction used by pr-watcher.test.sh) and calls _reconcile_merged_pr directly,
# forcing the chore-commit branch (the crash site), under `set -u`.
#
# Usage: bash .gaai/core/scripts/tests/reconcile-pr-number.test.sh
set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/../delivery-daemon.sh"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"
CHORE_LIB="$SCRIPT_DIR/../lib/chore-commit.sh"
BACKLOG_LIB="$SCRIPT_DIR/../lib/backlog-yaml.sh"

RUN=$(mktemp -d)
cleanup() { rm -rf "$RUN"; }
trap cleanup EXIT

# lib/chore-commit.sh must sit next to the runner so the function's
# BASH_SOURCE-relative lookup finds it and takes the chore-commit branch.
mkdir -p "$RUN/lib"
cp "$CHORE_LIB" "$RUN/lib/chore-commit.sh"
cp "$BACKLOG_LIB" "$RUN/lib/backlog-yaml.sh"

# temp git repo (bare remote + clone on staging) with one merged-but-unreconciled story
PROJ="$RUN/proj"; REMOTE="$RUN/proj_remote.git"
git init --bare "$REMOTE" -q
git clone "$REMOTE" "$PROJ" -q
git -C "$PROJ" config user.email t@gaai.local; git -C "$PROJ" config user.name "GAAI Test"
git -C "$PROJ" checkout -b staging -q 2>/dev/null || git -C "$PROJ" checkout staging -q
mkdir -p "$PROJ/.gaai/project/contexts/backlog"
cat > "$PROJ/.gaai/project/contexts/backlog/active.backlog.yaml" <<YAML
items:
- id: RECON-01
  status: in_progress
  phase_status: qa_passed
  pr_url: https://github.com/org/repo/pull/42
  delivery_pipeline: 3phase
  started_at: "2026-07-18T08:00:00Z"
YAML
git -C "$PROJ" add .; git -C "$PROJ" commit -m init -q; git -C "$PROJ" push -u origin staging -q

# runner: defines minimal env + stubs, sources the watcher functions, calls the
# reconcile directly with the 3-arg signature the fixed pr-watcher uses.
cat > "$RUN/runner.sh" <<RUNNER
#!/usr/bin/env bash
set -uo pipefail
PROJECT_DIR="$PROJ"
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG="\$PROJECT_DIR/\$BACKLOG_REL"
BACKLOG_FILE="\$BACKLOG"
LOCK_DIR="$RUN/locks"; mkdir -p "\$LOCK_DIR"
SCHEDULER="$SCHEDULER"
TARGET_BRANCH="staging"
DRY_RUN=false
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
log(){ :; }
with_staging_lock(){ "\$@"; }
export LOCK_DIR BACKLOG BACKLOG_FILE BACKLOG_REL TARGET_BRANCH SCHEDULER
eval "\$(awk '
  /^_merged_pr_started_at\(\)|^_merged_pr_is_current_cycle\(\)|^_reconcile_merged_pr\(\)/{p=1; depth=0}
  p { print
    for (i=1;i<=length(\$0);i++){c=substr(\$0,i,1); if(c=="{")depth++; if(c=="}")depth--}
    if (p && depth==0 && NR>1){p=0}
  }' "$DAEMON")"
_reconcile_merged_pr RECON-01 "2026-07-18T10:00:00Z" 42 "2026-07-18T09:00:00Z"
RUNNER
chmod +x "$RUN/runner.sh"

ERRLOG="$RUN/stderr.log"
bash "$RUN/runner.sh" 2>"$ERRLOG" || true

FINAL=$(git -C "$PROJ" show origin/staging:.gaai/project/contexts/backlog/active.backlog.yaml 2>/dev/null \
  | grep -m1 'status:' | awk '{print $2}')

echo "=== reconcile lands done without unbound pr_number ==="
if grep -q 'unbound' "$ERRLOG"; then
  fail "reconcile emitted an unbound-variable error: $(grep -m1 unbound "$ERRLOG")"
else
  pass "no unbound-variable error during reconcile"
fi
if [[ "$FINAL" == "done" ]]; then
  pass "merged story reconciled to status:done"
else
  fail "expected status:done, got '${FINAL:-<none>}' — $(tail -1 "$ERRLOG" 2>/dev/null)"
fi

echo ""
echo "  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
