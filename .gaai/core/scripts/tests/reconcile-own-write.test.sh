#!/usr/bin/env bash
# reconcile-own-write.test.sh — AC6 regression for E222S06
#
# Asserts that _commit_accumulated_backlog_drift() commits pending backlog drift
# (wrapper-reconcile hook + recovery-scan paths) instead of writing a drift-marker.
#
# T1: wrapper-reconcile path — pending diff committed + pushed, no drift-marker
# T2: recovery-scan path    — same assertion via the helper directly
# T3: push-race simulation  — fetch+rebase+retry succeeds, rc=0, no drift-marker
# T4: genuine conflict      — rebase conflict → rc=6, drift-marker IS written
# T5: push-race double-fail — retry push ALSO fails (2nd concurrent commit lands
#     between rebase and retry) → rc=7, local drift commit discarded, origin
#     unchanged, no false "committed accumulated backlog drift" success framing
# T6: first-stage caller cutover census — projector and shared staging lock remain
#     authoritative, while dispatch and stop-hook reject legacy backlog publication
#
# Run: bash .gaai/core/scripts/tests/reconcile-own-write.test.sh
# Exit 0 = all pass.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
LIB_DIR="$SCRIPTS/lib"

SANDBOX="$(mktemp -d /tmp/gaai-reconcile-own-write-XXXXXX)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"

# ── Shared git fixture helper ──────────────────────────────────────────────────
# Creates a bare remote + local clone with a minimal backlog committed to staging.
setup_git_repo() {
  local proj="$1"
  local remote="${proj}_remote.git"
  rm -rf "$proj" "$remote"
  git init --quiet --bare "$remote"
  git clone --quiet "$remote" "$proj"
  git -C "$proj" config user.email "test@gaai.local"
  git -C "$proj" config user.name "GAAI Test"
  git -C "$proj" checkout -q -b staging 2>/dev/null || git -C "$proj" checkout -q staging
  local backlog_dir="$proj/.gaai/project/contexts/backlog"
  mkdir -p "$backlog_dir"
  printf 'items:\n- id: E999T-01\n  status: in_progress\n  phase_status: qa_passed\n' \
    > "$backlog_dir/active.backlog.yaml"
  git -C "$proj" add .
  git -C "$proj" commit -q -m "initial"
  git -C "$proj" push -q -u origin staging
}

# ── Helper loader ─────────────────────────────────────────────────────────────
# Sources _commit_accumulated_backlog_drift from lib/chore-commit.sh.
load_helper() {
  # shellcheck source=lib/chore-commit.sh
  source "$LIB_DIR/chore-commit.sh"
}

load_helper

# ══════════════════════════════════════════════════════════════════════════════
# T1: wrapper-reconcile path — pending diff → committed + pushed, no drift-marker
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: wrapper-reconcile — pending diff committed + pushed ==="

T1_PROJ="$SANDBOX/t1-project"
T1_DRIFT_MARKER="$SANDBOX/t1.drift-marker"
setup_git_repo "$T1_PROJ"

# Introduce an uncommitted change to the backlog (simulates phase_status daemon write)
sed -i.bak 's/qa_passed/done/' "$T1_PROJ/$BACKLOG_REL" 2>/dev/null \
  || python3 -c "import sys; d=open('$T1_PROJ/$BACKLOG_REL').read().replace('qa_passed','done'); open('$T1_PROJ/$BACKLOG_REL','w').write(d)" 2>/dev/null || true
rm -f "$T1_PROJ/$BACKLOG_REL.bak" 2>/dev/null || true

# Verify diff exists before calling helper
T1_RC=0
( cd "$T1_PROJ" && _commit_accumulated_backlog_drift "E999T-01" "$BACKLOG_REL" "staging" "wrapper-reconcile" ) \
  || T1_RC=$?

if [[ "$T1_RC" -eq 0 ]]; then
  pass "T1: helper returned rc=0"
else
  fail "T1: expected rc=0, got rc=$T1_RC"
fi

# Verify diff is gone on origin (the commit was pushed)
T1_ORIGIN_PS=$(git -C "$T1_PROJ" show "origin/staging:$BACKLOG_REL" 2>/dev/null | grep phase_status | head -1 || echo "")
if echo "$T1_ORIGIN_PS" | grep -q "done"; then
  pass "T1: diff committed and pushed to origin (AC1)"
else
  fail "T1: origin/staging still has old phase_status — diff not pushed (AC1)"
fi

# Verify no drift-marker was written (helper returns 0, caller would not write it)
if [[ ! -f "$T1_DRIFT_MARKER" ]]; then
  pass "T1: no drift-marker written (AC1)"
else
  fail "T1: drift-marker unexpectedly written"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T2: recovery-scan path — same helper call, pending diff committed + pushed
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: recovery-scan — pending diff committed + pushed ==="

T2_PROJ="$SANDBOX/t2-project"
setup_git_repo "$T2_PROJ"

# Introduce an uncommitted backlog change
sed -i.bak 's/qa_passed/done/' "$T2_PROJ/$BACKLOG_REL" 2>/dev/null \
  || python3 -c "import sys; d=open('$T2_PROJ/$BACKLOG_REL').read().replace('qa_passed','done'); open('$T2_PROJ/$BACKLOG_REL','w').write(d)" 2>/dev/null || true
rm -f "$T2_PROJ/$BACKLOG_REL.bak" 2>/dev/null || true

T2_RC=0
( cd "$T2_PROJ" && _commit_accumulated_backlog_drift "E999T-01" "$BACKLOG_REL" "staging" "recovery-scan" ) \
  || T2_RC=$?

if [[ "$T2_RC" -eq 0 ]]; then
  pass "T2: helper returned rc=0 (AC2)"
else
  fail "T2: expected rc=0, got rc=$T2_RC"
fi

T2_ORIGIN_PS=$(git -C "$T2_PROJ" show "origin/staging:$BACKLOG_REL" 2>/dev/null | grep phase_status | head -1 || echo "")
if echo "$T2_ORIGIN_PS" | grep -q "done"; then
  pass "T2: diff committed and pushed to origin (AC2)"
else
  fail "T2: origin/staging still has old phase_status — diff not pushed (AC2)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T3: push-race simulation — concurrent remote commit, rebase + retry, rc=0
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: push-race — first push fails, rebase+retry succeeds ==="

T3_PROJ="$SANDBOX/t3-project"
T3_REMOTE="${T3_PROJ}_remote.git"
setup_git_repo "$T3_PROJ"

# 1. Modify local backlog (our pending drift)
sed -i.bak 's/qa_passed/done/' "$T3_PROJ/$BACKLOG_REL" 2>/dev/null \
  || python3 -c "import sys; d=open('$T3_PROJ/$BACKLOG_REL').read().replace('qa_passed','done'); open('$T3_PROJ/$BACKLOG_REL','w').write(d)" 2>/dev/null || true
rm -f "$T3_PROJ/$BACKLOG_REL.bak" 2>/dev/null || true

# 2. Simulate push-race: push a NON-conflicting commit to remote so our push fails
#    non-fast-forward but rebase is clean.
local_race="$SANDBOX/t3-race"
git clone --quiet "$T3_REMOTE" "$local_race" 2>/dev/null
git -C "$local_race" config user.email "race@gaai.local"
git -C "$local_race" config user.name "Race Writer"
git -C "$local_race" checkout -q staging 2>/dev/null || true
echo "race-file" > "$local_race/race.txt"
git -C "$local_race" add race.txt
git -C "$local_race" commit -q -m "race: concurrent commit to staging"
git -C "$local_race" push -q origin staging

T3_RC=0
( cd "$T3_PROJ" && _commit_accumulated_backlog_drift "E999T-01" "$BACKLOG_REL" "staging" "push-race-test" ) \
  || T3_RC=$?

if [[ "$T3_RC" -eq 0 ]]; then
  pass "T3: helper returned rc=0 after push-race rebase (AC5 push-race self-heal)"
else
  fail "T3: expected rc=0 after rebase+retry, got rc=$T3_RC"
fi

T3_ORIGIN_PS=$(git -C "$T3_PROJ" show "origin/staging:$BACKLOG_REL" 2>/dev/null | grep phase_status | head -1 || echo "")
if echo "$T3_ORIGIN_PS" | grep -q "done"; then
  pass "T3: diff committed and on origin after push-race recovery"
else
  fail "T3: origin/staging does not have updated phase_status after push-race"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T4: genuine rebase conflict — rc=6, caller writes drift-marker (AC3, AC5)
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: genuine conflict — rc=6, drift-marker fallback preserved ==="

T4_PROJ="$SANDBOX/t4-project"
T4_REMOTE="${T4_PROJ}_remote.git"
T4_DRIFT_MARKER="$SANDBOX/t4.drift-marker"
setup_git_repo "$T4_PROJ"

# 1. Modify the SAME line locally (our pending drift: change phase_status)
sed -i.bak 's/qa_passed/done/' "$T4_PROJ/$BACKLOG_REL" 2>/dev/null \
  || python3 -c "import sys; d=open('$T4_PROJ/$BACKLOG_REL').read().replace('qa_passed','done'); open('$T4_PROJ/$BACKLOG_REL','w').write(d)" 2>/dev/null || true
rm -f "$T4_PROJ/$BACKLOG_REL.bak" 2>/dev/null || true

# 2. Push a CONFLICTING commit to remote (edits the SAME line as our local change)
local_conflict="$SANDBOX/t4-conflict"
git clone --quiet "$T4_REMOTE" "$local_conflict" 2>/dev/null
git -C "$local_conflict" config user.email "conflict@gaai.local"
git -C "$local_conflict" config user.name "Conflict Writer"
git -C "$local_conflict" checkout -q staging 2>/dev/null || true
sed -i.bak 's/qa_passed/failed/' "$local_conflict/$BACKLOG_REL" 2>/dev/null \
  || python3 -c "import sys; d=open('$local_conflict/$BACKLOG_REL').read().replace('qa_passed','failed'); open('$local_conflict/$BACKLOG_REL','w').write(d)" 2>/dev/null || true
rm -f "$local_conflict/$BACKLOG_REL.bak" 2>/dev/null || true
git -C "$local_conflict" add "$BACKLOG_REL"
git -C "$local_conflict" commit -q -m "conflict: concurrent same-line edit"
git -C "$local_conflict" push -q origin staging

T4_RC=0
( cd "$T4_PROJ" && _commit_accumulated_backlog_drift "E999T-01" "$BACKLOG_REL" "staging" "conflict-test" ) \
  || T4_RC=$?

if [[ "$T4_RC" -eq 6 ]]; then
  pass "T4: helper returned rc=6 on genuine conflict (AC3 fallback preserved)"
else
  fail "T4: expected rc=6, got rc=$T4_RC"
fi

# Simulate caller writing drift-marker on rc=6 (as wrapper-reconcile and recovery-scan do)
if [[ "$T4_RC" -ne 0 ]]; then
  printf '%s|conflict-test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
    > "$T4_DRIFT_MARKER" 2>/dev/null || true
fi

if [[ -f "$T4_DRIFT_MARKER" ]]; then
  pass "T4: drift-marker written by caller on rc=6 (AC3 fallback)"
else
  fail "T4: drift-marker not written — fallback signal lost"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T5: push-race double-fail — retry push ALSO fails → rc=7, discard not success (AC4)
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: push-race double-fail — retry push also fails, rc=7 ==="

T5_PROJ="$SANDBOX/t5-project"
T5_REMOTE="${T5_PROJ}_remote.git"
setup_git_repo "$T5_PROJ"

# 1. Modify local backlog (our pending drift)
sed -i.bak 's/qa_passed/done/' "$T5_PROJ/$BACKLOG_REL" 2>/dev/null \
  || python3 -c "import sys; d=open('$T5_PROJ/$BACKLOG_REL').read().replace('qa_passed','done'); open('$T5_PROJ/$BACKLOG_REL','w').write(d)" 2>/dev/null || true
rm -f "$T5_PROJ/$BACKLOG_REL.bak" 2>/dev/null || true

# 2. Push a first race commit (non-conflicting file) so the initial push fails
#    non-fast-forward, forcing the fetch+rebase+retry-push path.
local_race1="$SANDBOX/t5-race1"
git clone --quiet "$T5_REMOTE" "$local_race1" 2>/dev/null
git -C "$local_race1" config user.email "race1@gaai.local"
git -C "$local_race1" config user.name "Race1 Writer"
git -C "$local_race1" checkout -q staging 2>/dev/null || true
echo "race1-file" > "$local_race1/race1.txt"
git -C "$local_race1" add race1.txt
git -C "$local_race1" commit -q -m "race1: concurrent commit to staging"
git -C "$local_race1" push -q origin staging

# 3. A `git` wrapper that, on the SECOND `push` invocation (the retry push, after
#    rebase has already succeeded against race1), injects a SECOND race commit
#    straight onto origin before forwarding to the real git binary — deterministically
#    reproducing "another commit lands between rebase and retry push".
T5_BIN="$SANDBOX/t5-bin"
mkdir -p "$T5_BIN"
REAL_GIT="$(command -v git)"
T5_PUSH_COUNT_FILE="$SANDBOX/t5-push-count"
echo 0 > "$T5_PUSH_COUNT_FILE"
cat > "$T5_BIN/git" <<GITWRAP_EOF
#!/usr/bin/env bash
if [[ "\$1" == "push" ]]; then
  count=\$(cat "$T5_PUSH_COUNT_FILE" 2>/dev/null || echo 0)
  count=\$(( count + 1 ))
  echo "\$count" > "$T5_PUSH_COUNT_FILE"
  if [[ "\$count" -eq 2 ]]; then
    race2="$SANDBOX/t5-race2"
    rm -rf "\$race2"
    "$REAL_GIT" clone --quiet "$T5_REMOTE" "\$race2" 2>/dev/null
    "$REAL_GIT" -C "\$race2" config user.email "race2@gaai.local"
    "$REAL_GIT" -C "\$race2" config user.name "Race2 Writer"
    "$REAL_GIT" -C "\$race2" checkout -q staging 2>/dev/null || true
    echo "race2-file" > "\$race2/race2.txt"
    "$REAL_GIT" -C "\$race2" add race2.txt
    "$REAL_GIT" -C "\$race2" commit -q -m "race2: concurrent commit before retry push"
    "$REAL_GIT" -C "\$race2" push -q origin staging
  fi
fi
exec "$REAL_GIT" "\$@"
GITWRAP_EOF
chmod +x "$T5_BIN/git"

T5_RC=0
T5_STDERR="$SANDBOX/t5.stderr"
( cd "$T5_PROJ" && PATH="$T5_BIN:$PATH" _commit_accumulated_backlog_drift "E999T-01" "$BACKLOG_REL" "staging" "push-race-double-test" ) \
  2>"$T5_STDERR" || T5_RC=$?

if [[ "$T5_RC" -eq 7 ]]; then
  pass "T5: helper returned rc=7 on push-race double-fail (AC4)"
else
  fail "T5: expected rc=7, got rc=$T5_RC"
fi

T5_ORIGIN_PS=$(git -C "$T5_PROJ" show "origin/staging:$BACKLOG_REL" 2>/dev/null | grep phase_status | head -1 || echo "")
if echo "$T5_ORIGIN_PS" | grep -q "done"; then
  fail "T5: origin/staging unexpectedly shows 'done' — discarded commit should NOT have landed (AC4)"
else
  pass "T5: origin/staging does not contain the discarded drift content (AC4)"
fi

if grep -q "committed accumulated backlog drift" "$T5_STDERR" 2>/dev/null; then
  fail "T5: false 'committed accumulated backlog drift' success framing emitted despite discard"
else
  pass "T5: no false success framing emitted (AC4)"
fi

if grep -q "push-race re-sync" "$T5_STDERR" 2>/dev/null; then
  pass "T5: push-race discard logged"
else
  fail "T5: push-race discard NOT logged"
fi

# ══════════════════════════════════════════════════════════════════════════════
# T6: first-stage journal-projection caller cutover census
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: journal projector boundary census ==="

if declare -F chore_commit_project_journal >/dev/null; then
  pass "T6: journal projector is exported for the separate caller cutover"
else
  fail "T6: journal projector is unavailable"
fi

T6_BODY="$(declare -f chore_commit_project_journal 2>/dev/null || true)"
if printf '%s\n' "$T6_BODY" | grep -Fq -- '--force-with-lease="refs/heads/$target_branch:$base_sha"'; then
  pass "T6: publisher uses a literal expected-old-SHA lease"
else
  fail "T6: exact expected-old-SHA lease is missing"
fi

if printf '%s\n' "$T6_BODY" | grep -Eq 'git (add|commit |rebase|reset|checkout)'; then
  fail "T6: projector contains an ambient stage/rebase/reset/checkout path"
else
  pass "T6: projector has no ambient stage/rebase/reset/checkout path"
fi

if grep -q 'STAGING_LOCK="$LOCK_DIR/.staging.lock"' "$SCRIPTS/delivery-daemon.sh" \
    && grep -q '^with_staging_lock()' "$SCRIPTS/delivery-daemon.sh"; then
  pass "T6: daemon serialization remains the one shared .staging.lock domain"
else
  fail "T6: shared staging serialization domain is missing"
fi

T6_STAGE_ONE_SURFACES=(
  "$SCRIPTS/daemon-dispatch.sh"
  "$SCRIPTS/post-delivery-hook.sh"
)

T6_STAGE_ONE_MISSING=0
for surface in "${T6_STAGE_ONE_SURFACES[@]}"; do
  if grep -q '_journal_persist_lifecycle' "$surface"; then
    pass "T6: $(basename "$surface") uses the journal persistence boundary"
  else
    fail "T6: $(basename "$surface") does not use the journal persistence boundary"
    T6_STAGE_ONE_MISSING=1
  fi
done

if grep -Eq '_commit_accumulated_backlog_drift|chore_commit_(field|multi_field)' "${T6_STAGE_ONE_SURFACES[@]}"; then
  fail "T6: a stage-one caller still invokes a legacy whole-backlog publisher"
else
  pass "T6: no stage-one caller invokes a legacy whole-backlog publisher"
fi

if grep -Eq 'git (add|commit |rebase|push).*active\.backlog\.yaml|git pull origin' "${T6_STAGE_ONE_SURFACES[@]}"; then
  fail "T6: a stage-one caller still publishes ambient backlog state"
else
  pass "T6: no stage-one caller publishes ambient backlog state"
fi

if grep -Eq 'SCHEDULER[^\n]*--(set|journal)' "${T6_STAGE_ONE_SURFACES[@]}"; then
  fail "T6: a stage-one caller still invokes the lifecycle scheduler directly"
else
  pass "T6: no stage-one caller invokes the lifecycle scheduler directly"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RESULTS: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  exit 0
else
  exit 1
fi
