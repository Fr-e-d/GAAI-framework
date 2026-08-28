#!/usr/bin/env bash
# Forward-only classifier and immutable-context contract tests.

set -uo pipefail

TEST_BASH="${GAAI_TEST_BASH:-${BASH:-/bin/bash}}"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSIFIER="$SCRIPT_DIR/../lib/stuck-classifier.sh"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gaai-forward-classifier-XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
chmod 700 "$SANDBOX"

printf 'INTERPRETER outer=%s inner=%s version=%s\n' \
  "${BASH:-unknown}" "$TEST_BASH" "$BASH_VERSION"
# shellcheck source=../lib/stuck-classifier.sh
source "$CLASSIFIER"

SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
NOW=1787666400

write_snapshot() {
  local path="$1" status="$2" phase="$3" started="$4"
  {
    echo 'items:'
    echo '- id: TST-FWD'
    echo "  status: $status"
    echo "  phase_status: $phase"
    echo "  started_at: $started"
  } > "$path"
  chmod 600 "$path"
}

blob_for() { git hash-object -- "$1"; }

classify() {
  local path="$1" scope="$2" integrity="$3" plan="$4"
  forward_classify_snapshot TST-FWD "$path" "$SOURCE_SHA" \
    "$(blob_for "$path")" "$scope" "$integrity" "$plan" "$NOW"
}

expect_action() {
  local label="$1" expected_action="$2" expected_reason="$3"
  shift 3
  local output rc=0
  output=$("$@") || rc=$?
  if [[ "$rc" -eq 0 && "${output%%$'\t'*}" == "$expected_action" \
      && "$output" == "$expected_action"$'\t'"$expected_reason"$'\t'* ]]; then
    pass "$label"
  else
    fail "$label (rc=$rc output=$output)"
  fi
}

expect_rejected() {
  local label="$1"
  shift
  if "$@" >"$SANDBOX/rejected.out" 2>"$SANDBOX/rejected.err"; then
    fail "$label"
  elif [[ ! -s "$SANDBOX/rejected.out" && ! -s "$SANDBOX/rejected.err" ]]; then
    pass "$label"
  else
    fail "$label leaked candidate/path/content evidence"
  fi
}

echo "Forward classifier lifecycle matrix"
SNAP="$SANDBOX/snapshot.yaml"
write_snapshot "$SNAP" refined not_started null
expect_action "refined first claim accepts absent_new" claim_candidate ready \
  classify "$SNAP" main absent_new false
expect_action "recovery never treats refined row as a claim" no_effect not_actionable \
  classify "$SNAP" recovery verified false

for CASE in \
  'not_started true resume resumable' \
  'planned true resume resumable' \
  'planned false forward_fail required_plan_absent' \
  'implemented true resume resumable' \
  'qa_failed true resume resumable' \
  'qa_passed true resume resumable' \
  'failed true forward_terminal terminal_projection' \
  'escalated true forward_terminal terminal_projection' \
  'qa_escalated true forward_terminal terminal_projection' \
  'done true hold_downstream merge_terminal_owned' \
  'commit_stalled true hold_operator policy_stall'
do
  set -- $CASE
  write_snapshot "$SNAP" in_progress "$1" '"2026-08-25T10:00:00Z"'
  expect_action "in_progress/$1 closes as $3" "$3" "$4" \
    classify "$SNAP" recovery verified "$2"
done

for PHASE in failed escalated qa_escalated done commit_stalled; do
  write_snapshot "$SNAP" in_progress "$PHASE" '"2026-08-25T10:00:00Z"'
  case "$PHASE" in
    failed|escalated|qa_escalated) TERMINAL_ACTION=forward_terminal; TERMINAL_REASON=terminal_projection ;;
    done) TERMINAL_ACTION=hold_downstream; TERMINAL_REASON=merge_terminal_owned ;;
    commit_stalled) TERMINAL_ACTION=hold_operator; TERMINAL_REASON=policy_stall ;;
  esac
  for INTEGRITY in verified recoverable unrecoverable unknown absent_new; do
    expect_action "$PHASE is closed independently of $INTEGRITY integrity" \
      "$TERMINAL_ACTION" "$TERMINAL_REASON" \
      classify "$SNAP" recovery "$INTEGRITY" true
  done
done

write_snapshot "$SNAP" in_progress implemented '"2026-08-25T10:00:00Z"'
expect_action "confirmed unrecoverable fails forward" forward_fail worktree_unrecoverable \
  classify "$SNAP" recovery unrecoverable true
expect_action "unknown integrity blocks" block_integrity integrity_unverified \
  classify "$SNAP" recovery unknown true
expect_action "recoverable is not provisional authority" block_integrity integrity_unverified \
  classify "$SNAP" recovery recoverable true
expect_action "bound first-claim absence is valid only at postclaim" resume resumable \
  classify "$SNAP" postclaim absent_new true

echo "Pinned bytes and record validation"
EXPECTED_BLOB=$(blob_for "$SNAP")
printf '\n# changed\n' >> "$SNAP"
expect_rejected "changed bytes cannot match the pinned blob" \
  forward_classify_snapshot TST-FWD "$SNAP" "$SOURCE_SHA" "$EXPECTED_BLOB" \
    recovery verified true "$NOW"

write_snapshot "$SNAP" in_progress implemented '"2026-08-25T10:00:00Z"'
LINK="$SANDBOX/snapshot-link.yaml"
ln -s "$SNAP" "$LINK"
expect_rejected "symlink snapshot is rejected" \
  forward_classify_snapshot TST-FWD "$LINK" "$SOURCE_SHA" "$(blob_for "$SNAP")" \
    recovery verified true "$NOW"
chmod 644 "$SNAP"
expect_rejected "non-private snapshot is rejected" \
  forward_classify_snapshot TST-FWD "$SNAP" "$SOURCE_SHA" "$(blob_for "$SNAP")" \
    recovery verified true "$NOW"
chmod 600 "$SNAP"

cat >> "$SNAP" <<'YAML'
- id: TST-FWD
  status: in_progress
  phase_status: implemented
  started_at: "2026-08-25T10:00:00Z"
YAML
expect_rejected "duplicate Story is rejected" classify "$SNAP" recovery verified true

cat > "$SNAP" <<'YAML'
items:
- id: TST-FWD
  status: in_progress
  status: failed
  phase_status: implemented
  started_at: "2026-08-25T10:00:00Z"
YAML
chmod 600 "$SNAP"
expect_rejected "duplicate governed field is rejected" classify "$SNAP" recovery verified true

write_snapshot "$SNAP" in_progress implemented null
expect_action "missing started_at blocks" block_invalid_record invalid_started_at \
  classify "$SNAP" recovery verified true
write_snapshot "$SNAP" in_progress implemented '"2026-08-25T10:00:00+00:00"'
expect_action "normalized but non-canonical time blocks" block_invalid_record invalid_started_at \
  classify "$SNAP" recovery verified true
write_snapshot "$SNAP" in_progress implemented '"2026-08-25T14:00:01Z"'
expect_action "future time blocks" block_invalid_record invalid_started_at \
  classify "$SNAP" recovery verified true
write_snapshot "$SNAP" in_progress worktree_recovery_failed '"2026-08-25T10:00:00Z"'
expect_action "unratified lifecycle value blocks" block_invalid_record invalid_lifecycle \
  classify "$SNAP" recovery verified true

echo "Descriptor/path replacement is rejected"
write_snapshot "$SNAP" in_progress implemented '"2026-08-25T10:00:00Z"'
RACE_SITE="$SANDBOX/race-site"
mkdir "$RACE_SITE"
cat > "$RACE_SITE/sitecustomize.py" <<'PY'
import os

_real_open = os.open
_target = os.environ.get("GAAI_RACE_TARGET")
_replacement = os.environ.get("GAAI_RACE_REPLACEMENT")
_done = False

def race_open(path, flags, mode=0o777, *, dir_fd=None):
    global _done
    if dir_fd is None:
        fd = _real_open(path, flags, mode)
    else:
        fd = _real_open(path, flags, mode, dir_fd=dir_fd)
    if not _done and path == _target and flags & os.O_RDONLY == os.O_RDONLY:
        _done = True
        os.replace(_replacement, _target)
    return fd

os.open = race_open
PY
cp "$SNAP" "$SANDBOX/replacement.yaml"
chmod 600 "$SANDBOX/replacement.yaml"
RACE_BLOB=$(blob_for "$SNAP")
if PYTHONPATH="$RACE_SITE" GAAI_RACE_TARGET="$SNAP" \
    GAAI_RACE_REPLACEMENT="$SANDBOX/replacement.yaml" \
    forward_classify_snapshot TST-FWD "$SNAP" "$SOURCE_SHA" "$RACE_BLOB" \
      recovery verified true "$NOW" >"$SANDBOX/race.out" 2>"$SANDBOX/race.err"; then
  fail "path replacement after open was accepted"
elif [[ ! -s "$SANDBOX/race.out" && ! -s "$SANDBOX/race.err" ]]; then
  pass "path replacement after open is rejected"
else
  fail "path replacement rejection leaked evidence"
fi

echo "Immutable recovery contexts"
CTX_DIR="$SANDBOX/contexts"
mkdir "$CTX_DIR"
chmod 700 "$CTX_DIR"
CTX="$CTX_DIR/TST-FWD.json"
HEX40=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
HEX64=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
STALL_EVENT_DIGEST=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
STALL_STATE_DIGEST=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
if forward_context_install "$CTX" TST-FWD "$SOURCE_SHA" "$HEX40" "$HEX64" \
    none none none none none none verified resume resumable none; then
  pass "successor context records explicit retained absence"
else
  fail "valid successor context was rejected"
fi
CTX_ROW=$(forward_context_read "$CTX" 2>/dev/null || true)
CTX_DIGEST="${CTX_ROW##*$'\t'}"
if [[ "$CTX_ROW" == TST-FWD$'\t'*$'\tnone\tnone\tnone\tnone\tnone\tnone\tverified\tresume\tresumable\tnone\t'* ]]; then
  pass "context reader returns closed typed facts"
else
  fail "context reader returned an unexpected schema"
fi
STALL_CTX="$CTX_DIR/commit-stalled.json"
if forward_context_install "$STALL_CTX" TST-FWD "$SOURCE_SHA" "$HEX40" "$HEX64" \
    none none none none "$STALL_EVENT_DIGEST" "$STALL_STATE_DIGEST" \
    verified forward_commit_stall stall_pending phase_status=commit_stalled \
    && STALL_ROW=$(forward_context_read "$STALL_CTX" 2>/dev/null) \
    && [[ "$STALL_ROW" == TST-FWD$'\t'*$'\t'"$STALL_EVENT_DIGEST"$'\t'"$STALL_STATE_DIGEST"$'\tverified\tforward_commit_stall\tstall_pending\tphase_status=commit_stalled\t'* ]]; then
  pass "commit retry guard binds the exact forward commit-stall action"
else
  fail "valid forward commit-stall context was rejected"
fi
expect_rejected "hold_operator cannot carry a commit-stalled intention" \
  forward_context_install "$CTX_DIR/invalid-hold-intention.json" TST-FWD \
    "$SOURCE_SHA" "$HEX40" "$HEX64" none none none none \
    "$STALL_EVENT_DIGEST" "$STALL_STATE_DIGEST" verified hold_operator \
    policy_stall phase_status=commit_stalled
chmod 777 "$CTX_DIR"
expect_rejected "context read rejects a permission-widened parent" \
  forward_context_read "$CTX"
chmod 700 "$CTX_DIR"
REAL_PARENT="$SANDBOX/real-parent"
LINK_PARENT="$SANDBOX/link-parent"
mkdir "$REAL_PARENT"
chmod 700 "$REAL_PARENT"
forward_context_install "$REAL_PARENT/linked.json" TST-FWD "$SOURCE_SHA" "$HEX40" \
  "$HEX64" none none none none none none verified resume resumable none
ln -s "$REAL_PARENT" "$LINK_PARENT"
expect_rejected "context read rejects a symlinked parent" \
  forward_context_read "$LINK_PARENT/linked.json"
expect_rejected "immutable context cannot be rewritten" \
  forward_context_install "$CTX" TST-FWD "$SOURCE_SHA" "$HEX40" "$HEX64" \
    none none none none none none verified resume resumable none

RETAINED="$CTX_DIR/retained.json"
if forward_context_install "$RETAINED" TST-FWD "$SOURCE_SHA" "$HEX40" "$HEX64" \
    retained "$HEX64" "$HEX40" "$HEX64" none none verified forward_fail \
    required_plan_absent phase_status=failed,status=failed; then
  pass "retained context requires actual token/source/record digests"
else
  fail "valid retained context was rejected"
fi
expect_rejected "fabricated retained identity is rejected" \
  forward_context_install "$CTX_DIR/fabricated.json" TST-FWD "$SOURCE_SHA" "$HEX40" \
    "$HEX64" retained none "$HEX40" "$HEX64" none none verified forward_fail \
    required_plan_absent phase_status=failed,status=failed

echo "Context parent identity is bound before installation"
PARENT_RACE="$SANDBOX/parent-race"
PARENT_OLD="$SANDBOX/parent-old"
mkdir "$PARENT_RACE"
chmod 700 "$PARENT_RACE"
PARENT_SITE="$SANDBOX/parent-site"
mkdir "$PARENT_SITE"
cat > "$PARENT_SITE/sitecustomize.py" <<'PY'
import os

_real_open = os.open
_real_rename = os.rename
_real_mkdir = os.mkdir
_target = os.environ["GAAI_PARENT_TARGET"]
_old = os.environ["GAAI_PARENT_OLD"]
_done = False

def race_open(path, flags, mode=0o777, *, dir_fd=None):
    global _done
    if not _done and dir_fd is None and path == _target:
        _done = True
        _real_rename(_target, _old)
        _real_mkdir(_target, 0o777)
        os.chmod(_target, 0o777)
    if dir_fd is None:
        return _real_open(path, flags, mode)
    return _real_open(path, flags, mode, dir_fd=dir_fd)

os.open = race_open
PY
PARENT_RC=0
PYTHONPATH="$PARENT_SITE" GAAI_PARENT_TARGET="$PARENT_RACE" \
  GAAI_PARENT_OLD="$PARENT_OLD" \
  forward_context_install "$PARENT_RACE/raced.json" TST-FWD "$SOURCE_SHA" \
    "$HEX40" "$HEX64" none none none none none none verified resume resumable none \
    >"$SANDBOX/parent.out" 2>"$SANDBOX/parent.err" || PARENT_RC=$?
if [[ "$PARENT_RC" -ne 0 && ! -e "$PARENT_RACE/raced.json" \
    && ! -s "$SANDBOX/parent.out" && ! -s "$SANDBOX/parent.err" ]]; then
  pass "parent replacement or permission widening is rejected before context creation"
else
  fail "context install accepted a replaced or permissive parent"
fi

SHORT_DIR="$SANDBOX/short-write"
mkdir "$SHORT_DIR"
chmod 700 "$SHORT_DIR"
SHORT_SITE="$SANDBOX/short-site"
mkdir "$SHORT_SITE"
cat > "$SHORT_SITE/sitecustomize.py" <<'PY'
import os

_real_write = os.write

def short_write(fd, data):
    return _real_write(fd, data[:max(1, len(data) // 2)])

os.write = short_write
PY
if PYTHONPATH="$SHORT_SITE" forward_context_install "$SHORT_DIR/context.json" \
    TST-FWD "$SOURCE_SHA" "$HEX40" "$HEX64" none none none none none none verified \
    resume resumable none \
    && forward_context_read "$SHORT_DIR/context.json" >/dev/null 2>&1; then
  pass "short writes are completed before context publication"
else
  fail "short write produced missing or truncated context"
fi
ZERO_DIR="$SANDBOX/zero-write"
mkdir "$ZERO_DIR"
chmod 700 "$ZERO_DIR"
ZERO_SITE="$SANDBOX/zero-site"
mkdir "$ZERO_SITE"
cat > "$ZERO_SITE/sitecustomize.py" <<'PY'
import os
os.write = lambda fd, data: 0
PY
expect_rejected "zero-byte write cannot publish a partial context" \
  env PYTHONPATH="$ZERO_SITE" "$TEST_BASH" -c \
    'source "$1"; forward_context_install "$2" TST-FWD "$3" "$4" "$5" none none none none none none verified resume resumable none' \
    _ "$CLASSIFIER" "$ZERO_DIR/context.json" "$SOURCE_SHA" "$HEX40" "$HEX64"
if [[ -e "$ZERO_DIR/context.json" ]]; then
  fail "zero-byte write left a published context"
else
  pass "zero-byte write leaves no published context"
fi

expect_rejected "contradictory action/reason/intention is rejected at install" \
  forward_context_install "$CTX_DIR/contradictory.json" TST-FWD "$SOURCE_SHA" \
    "$HEX40" "$HEX64" none none none none none none verified resume ready status=failed

TAMPER="$CTX_DIR/tamper.json"
cp "$CTX" "$TAMPER"
python3 - "$TAMPER" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="ascii") as handle:
    obj = json.load(handle)
obj["action"] = "attacker_action"
with open(path, "w", encoding="ascii") as handle:
    json.dump(obj, handle)
PY
chmod 600 "$TAMPER"
expect_rejected "semantic action tamper is rejected at read" forward_context_read "$TAMPER"

VERSION="$CTX_DIR/version.json"
cp "$CTX" "$VERSION"
python3 - "$VERSION" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="ascii") as handle:
    obj = json.load(handle)
obj["schema_version"] = "9.9.9"
with open(path, "w", encoding="ascii") as handle:
    json.dump(obj, handle)
PY
chmod 600 "$VERSION"
expect_rejected "unknown context schema version is rejected" forward_context_read "$VERSION"

TRUNCATED="$CTX_DIR/truncated.json"
printf '{"schema_version":"1.0.0"' > "$TRUNCATED"
chmod 600 "$TRUNCATED"
expect_rejected "truncated context is rejected" forward_context_read "$TRUNCATED"

python3 - "$CTX" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="ascii") as handle:
    obj = json.load(handle)
obj["extra"] = "not-allowed"
with open(path, "w", encoding="ascii") as handle:
    json.dump(obj, handle)
PY
chmod 600 "$CTX"
expect_rejected "extra context keys are rejected" forward_context_read "$CTX"
expect_rejected "context removal requires exact bytes digest" \
  forward_context_remove "$RETAINED" "$HEX64"
RETAINED_ROW=$(forward_context_read "$RETAINED")
RETAINED_DIGEST="${RETAINED_ROW##*$'\t'}"
if forward_context_remove "$RETAINED" "$RETAINED_DIGEST" && [[ ! -e "$RETAINED" ]]; then
  pass "exact immutable context is durably retired"
else
  fail "exact immutable context could not be retired"
fi

CHMOD_REMOVE_DIR="$SANDBOX/chmod-remove"
mkdir "$CHMOD_REMOVE_DIR"
chmod 700 "$CHMOD_REMOVE_DIR"
CHMOD_REMOVE_CTX="$CHMOD_REMOVE_DIR/context.json"
forward_context_install "$CHMOD_REMOVE_CTX" TST-FWD "$SOURCE_SHA" "$HEX40" "$HEX64" \
  none none none none none none verified resume resumable none
CHMOD_REMOVE_ROW=$(forward_context_read "$CHMOD_REMOVE_CTX")
CHMOD_REMOVE_DIGEST="${CHMOD_REMOVE_ROW##*$'\t'}"
CHMOD_SITE="$SANDBOX/chmod-site"
mkdir "$CHMOD_SITE"
cat > "$CHMOD_SITE/sitecustomize.py" <<'PY'
import os

_real_open = os.open
_target = os.environ["GAAI_CHMOD_PARENT"]
_done = False

def chmod_open(path, flags, mode=0o777, *, dir_fd=None):
    global _done
    if not _done and dir_fd is None and path == _target:
        _done = True
        os.chmod(_target, 0o777)
    if dir_fd is None:
        return _real_open(path, flags, mode)
    return _real_open(path, flags, mode, dir_fd=dir_fd)

os.open = chmod_open
PY
CHMOD_REMOVE_RC=0
PYTHONPATH="$CHMOD_SITE" GAAI_CHMOD_PARENT="$CHMOD_REMOVE_DIR" \
  forward_context_remove "$CHMOD_REMOVE_CTX" "$CHMOD_REMOVE_DIGEST" \
    >"$SANDBOX/chmod-remove.out" 2>"$SANDBOX/chmod-remove.err" || CHMOD_REMOVE_RC=$?
if [[ "$CHMOD_REMOVE_RC" -ne 0 && -f "$CHMOD_REMOVE_CTX" \
    && ! -s "$SANDBOX/chmod-remove.out" && ! -s "$SANDBOX/chmod-remove.err" ]]; then
  pass "retirement rejects in-place parent permission widening and preserves context"
else
  fail "retirement accepted widened parent permissions or lost context"
fi

echo "Context retirement preserves a raced successor"
RACE_CONTEXT="$CTX_DIR/race-context.json"
RACE_SUCCESSOR="$CTX_DIR/race-successor.json"
forward_context_install "$RACE_CONTEXT" TST-FWD "$SOURCE_SHA" "$HEX40" "$HEX64" \
  none none none none none none verified resume resumable none
forward_context_install "$RACE_SUCCESSOR" TST-FWD "$SOURCE_SHA" "$HEX40" "$HEX64" \
  none none none none none none verified no_effect not_actionable none
RACE_CONTEXT_ROW=$(forward_context_read "$RACE_CONTEXT")
RACE_CONTEXT_DIGEST="${RACE_CONTEXT_ROW##*$'\t'}"
RACE_SUCCESSOR_DIGEST=$(shasum -a 256 "$RACE_SUCCESSOR" | awk '{print $1}')
REMOVE_SITE="$SANDBOX/remove-site"
mkdir "$REMOVE_SITE"
cat > "$REMOVE_SITE/sitecustomize.py" <<'PY'
import os

_real_rename = os.rename
_real_replace = os.replace
_target = os.environ["GAAI_REMOVE_TARGET"]
_successor = os.environ["GAAI_REMOVE_SUCCESSOR"]
_done = False

def race_rename(src, dst, *args, **kwargs):
    global _done
    if not _done and str(dst).endswith(".retire"):
        _done = True
        _real_replace(_successor, _target)
    return _real_rename(src, dst, *args, **kwargs)

os.rename = race_rename
PY
REMOVE_RC=0
PYTHONPATH="$REMOVE_SITE" GAAI_REMOVE_TARGET="$RACE_CONTEXT" \
  GAAI_REMOVE_SUCCESSOR="$RACE_SUCCESSOR" \
  forward_context_remove "$RACE_CONTEXT" "$RACE_CONTEXT_DIGEST" \
    >"$SANDBOX/remove-race.out" 2>"$SANDBOX/remove-race.err" || REMOVE_RC=$?
AFTER_SUCCESSOR_DIGEST=$(shasum -a 256 "$RACE_CONTEXT" 2>/dev/null | awk '{print $1}')
if [[ "$REMOVE_RC" -ne 0 && "$AFTER_SUCCESSOR_DIGEST" == "$RACE_SUCCESSOR_DIGEST" \
    && ! -s "$SANDBOX/remove-race.out" && ! -s "$SANDBOX/remove-race.err" ]]; then
  pass "retirement race rejects and preserves the successor inode bytes"
else
  fail "retirement race deleted or changed the successor"
fi

echo "Side-effect and privacy census"
if ! find "$SANDBOX" -type f -name 'incident-*' | grep -q . \
    && ! rg -n 'incident|phantom|_recovery_revert_refined|git log|git diff' \
      "$CLASSIFIER" >/dev/null 2>&1; then
  pass "classification has no incident, history, phantom-delete or reverse action path"
else
  fail "legacy classifier evidence/action remains"
fi

echo ""
echo "Classifier results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
