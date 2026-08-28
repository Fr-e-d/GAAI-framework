#!/usr/bin/env bash
# Target-object and CWD-independence matrix for forward recovery.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
DAEMON="$ROOT/.gaai/core/scripts/delivery-daemon.sh"
CLASSIFIER="$ROOT/.gaai/core/scripts/lib/stuck-classifier.sh"
TEST_BASH="${GAAI_TEST_BASH:-$BASH}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gaai-forward-order.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
pass(){ PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
expect(){ local n="$1"; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }

current=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$BASH")
selected=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$TEST_BASH")
printf 'interpreter=%s version=%s\n' "$current" "$BASH_VERSION"
expect "exact selected interpreter" test "$current" = "$selected"

HARNESS="$TMP/harness.sh"
awk '/^_forward_sha256\(\)/{on=1} /^exceeded_stories\(\)/{on=0} on{print}' "$DAEMON" > "$HARNESS"
source "$CLASSIFIER"
source "$HARNESS"

LOCK_DIR="$TMP/locks"; mkdir -p "$LOCK_DIR"; chmod 700 "$LOCK_DIR"
PROJECT_DIR="$TMP/repo"; REPO_ROOT="$PROJECT_DIR"
TARGET_BRANCH=staging
BACKLOG_REL=".gaai/project/contexts/backlog/active.backlog.yaml"
BACKLOG_FILE="$PROJECT_DIR/$BACKLOG_REL"
BACKLOG="$BACKLOG_FILE"
GAAI_WORKTREES_BASE="$TMP/worktrees"; mkdir -p "$GAAI_WORKTREES_BASE"
git init --bare "$TMP/origin.git" >/dev/null
git init "$PROJECT_DIR" >/dev/null
git -C "$PROJECT_DIR" config user.email test@example.invalid
git -C "$PROJECT_DIR" config user.name test
git -C "$PROJECT_DIR" remote add origin "$TMP/origin.git"
git -C "$PROJECT_DIR" remote set-url --push origin "$TMP/origin.git"
[[ "$(git -C "$PROJECT_DIR" remote get-url --push origin)" == "$TMP/origin.git" ]] || exit 1
mkdir -p "$(dirname "$BACKLOG_FILE")"
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)

write_order() {
  local first="$1" second="$2"
  {
    printf 'items:\n'
    for sid in "$first" "$second"; do
      printf -- '- id: %s\n' "$sid"
      printf '  status: in_progress\n'
      printf '  phase_status: implemented\n'
      printf '  started_at: "%s"\n' "$started"
    done
  } > "$BACKLOG_FILE"
  git -C "$PROJECT_DIR" add "$BACKLOG_REL"
  git -C "$PROJECT_DIR" commit -m "order $first $second" >/dev/null
  git -C "$PROJECT_DIR" push -f origin HEAD:staging >/dev/null
}
write_order EORDERA EORDERB

_forward_classify EORDERA recovery verified false || exit 1
action1="$_FORWARD_ACTION:$_FORWARD_REASON"
source1="$_FORWARD_SOURCE"
blob1="$_FORWARD_BLOB"
record1="$_FORWARD_RECORD_DIGEST"
rm -f "$_FORWARD_SNAPSHOT"

old_pwd=$PWD
cd /
_forward_classify EORDERA recovery verified false || exit 1
cd "$old_pwd"
expect "wrong CWD cannot change action" test "$_FORWARD_ACTION:$_FORWARD_REASON" = "$action1"
expect "wrong CWD cannot change source" test "$_FORWARD_SOURCE" = "$source1"
expect "wrong CWD cannot change blob" test "$_FORWARD_BLOB" = "$blob1"
expect "wrong CWD cannot change record digest" test "$_FORWARD_RECORD_DIGEST" = "$record1"

context=$(_forward_context_path EORDERA)
row=$(_forward_bind_context "$context" EORDERA "$_FORWARD_SOURCE" "$_FORWARD_BLOB" \
  "$_FORWARD_RECORD_DIGEST" none none none none none none \
  verified resume resumable none) || exit 1
context_digest=${row##*$'\t'}
expect "context read returns installed digest" test "$(forward_context_read "$context" | awk -F '\t' '{print $NF}')" = "$context_digest"
rm -f "$_FORWARD_SNAPSHOT"

write_order EORDERB EORDERA
_forward_classify EORDERA recovery verified false || exit 1
expect "semantic action survives Story reorder" test "$_FORWARD_ACTION:$_FORWARD_REASON" = "$action1"
if [[ "$_FORWARD_SOURCE" != "$source1" && "$_FORWARD_BLOB" != "$blob1" \
    && "$_FORWARD_RECORD_DIGEST" != "$record1" ]]; then
  pass "remote reorder creates a distinct pinned identity"
else
  fail "remote reorder creates a distinct pinned identity"
fi
if _forward_bind_context "$context" EORDERA "$_FORWARD_SOURCE" "$_FORWARD_BLOB" \
    "$_FORWARD_RECORD_DIGEST" none none none none none none \
    verified resume resumable none >/dev/null; then
  fail "old context cannot be adopted by advanced target"
else
  pass "old context cannot be adopted by advanced target"
fi
expect "advanced-target mismatch preserves old context" test "$(forward_context_read "$context" | awk -F '\t' '{print $NF}')" = "$context_digest"
rm -f "$_FORWARD_SNAPSHOT"
expect "exact context retirement succeeds" forward_context_remove "$context" "$context_digest"

python3 - "$DAEMON" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
one = text.index('_forward_project "$sid" "$_FORWARD_SOURCE"')
post = text.index('_forward_classify "$sid" recovery', one)
verify = text.index('_lifecycle_snapshot_matches "$_FORWARD_SNAPSHOT"', post)
if not one < post < verify:
    raise SystemExit(1)
relaunch = text.index('_forward_relaunch()')
last = text.index('_forward_classify "$sid" recovery', relaunch)
spawn = text.index('launch_3phase_in_tmux "$sid"', last)
if not relaunch < last < spawn:
    raise SystemExit(1)
PY
expect "projection and relaunch both have fresh reclassification barriers" test "$?" -eq 0

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
