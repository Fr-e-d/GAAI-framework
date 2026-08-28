#!/usr/bin/env bash
# Descriptor-bound orphan-lock and fail-closed cycle matrix.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
DAEMON="$ROOT/.gaai/core/scripts/delivery-daemon.sh"
TEST_BASH="${GAAI_TEST_BASH:-$BASH}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gaai-orphan-forward.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
expect(){ local n="$1"; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }

current=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$BASH")
selected=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$TEST_BASH")
printf 'interpreter=%s version=%s\n' "$current" "$BASH_VERSION"
expect "exact selected interpreter" test "$current" = "$selected"

HARNESS="$TMP/harness.sh"
awk '/^active_count\(\)/{on=1} /^active_stories\(\)/{on=0} on{print}' "$DAEMON" > "$HARNESS"
awk '/^_forward_sha256\(\)/{on=1} /^exceeded_stories\(\)/{on=0} on{print}' "$DAEMON" >> "$HARNESS"
awk '/^cycle_orphan_lock_scan\(\)/{on=1} /^# ── Heartbeat monitoring/{on=0} on{print}' "$DAEMON" >> "$HARNESS"
source "$HARNESS"

LOCK_DIR="$TMP/locks"; mkdir -p "$LOCK_DIR"; chmod 700 "$LOCK_DIR"
ORPHAN_SCAN_MAX_DURATION_SEC=30
YELLOW=; NC=
log(){ :; }
_forward_evidence(){ :; }

printf '%s\n' "$$" > "$LOCK_DIR/ELIVE.lock"; chmod 600 "$LOCK_DIR/ELIVE.lock"
row=$(_forward_lock_state ELIVE); rc=$?
expect "live PID lock is retained and typed live" test "$rc:$row" = "0:live	$$"

dead=99999999
printf '%s\n' "$dead" > "$LOCK_DIR/EDEAD.lock"; chmod 600 "$LOCK_DIR/EDEAD.lock"
row=$(_forward_lock_state EDEAD); rc=$?
expect "dead PID lock is retained and typed dead" test "$rc:$row" = "0:dead	$dead"
expect "capacity counts only descriptor-verified live ownership" \
  test "$(active_count)" = 1
expect "capacity observation preserves dead evidence" test -e "$LOCK_DIR/EDEAD.lock"

chmod 644 "$LOCK_DIR/EDEAD.lock"
row=$(_forward_lock_state EDEAD); rc=$?
expect "non-private lock is unknown and blocking" test "$rc:${row%%$'\t'*}" = "1:unknown"
chmod 600 "$LOCK_DIR/EDEAD.lock"

if _forward_retire_dead_lock EDEAD 12345; then
  fail "wrong PID cannot retire lock"
else
  expect "wrong-PID failure preserves lock bytes" grep -qx "$dead" "$LOCK_DIR/EDEAD.lock"
fi
expect "exact dead PID retirement succeeds" _forward_retire_dead_lock EDEAD "$dead"
expect "exact retirement removes only selected lock" test ! -e "$LOCK_DIR/EDEAD.lock"
expect "live lock remains" test -e "$LOCK_DIR/ELIVE.lock"
live_identity_before=$(python3 - "$LOCK_DIR/ELIVE.lock" <<'PY'
import os, sys
entry = os.lstat(sys.argv[1])
print("%s:%s" % (entry.st_dev, entry.st_ino))
PY
)
if _forward_retire_dead_lock ELIVE "$$"; then
  fail "fresh live-PID check blocks stale dead observation"
else
  live_identity_after=$(python3 - "$LOCK_DIR/ELIVE.lock" <<'PY'
import os, sys
entry = os.lstat(sys.argv[1])
print("%s:%s" % (entry.st_dev, entry.st_ino))
PY
  )
  if [[ "$live_identity_before" == "$live_identity_after" ]] \
      && grep -qx "$$" "$LOCK_DIR/ELIVE.lock"; then
    pass "fresh live-PID check preserves exact lock bytes and inode"
  else
    fail "live-PID refusal changed lock bytes or identity"
  fi
fi

printf '%s\n' "$dead" > "$LOCK_DIR/EFAIL.lock"; chmod 600 "$LOCK_DIR/EFAIL.lock"
rm -f "$LOCK_DIR/ELIVE.lock"
MAX_CONCURRENT=1
expect "dead ownership leaves one recovery slot at MAX_CONCURRENT=1" \
  test "$(active_count)" = 0
forward_recovery_scan(){ return 1; }
if cycle_orphan_lock_scan; then
  fail "failed recovery makes orphan cycle non-zero"
else
  pass "failed recovery makes orphan cycle non-zero"
fi
expect "failed recovery preserves exact dead lock" grep -qx "$dead" "$LOCK_DIR/EFAIL.lock"

forward_recovery_scan(){
  local sid="$2"
  local row state pid capacity
  capacity=$(active_count) || return 1
  (( capacity < MAX_CONCURRENT )) || return 1
  row=$(_forward_lock_state "$sid") || return 1
  IFS=$'\t' read -r state pid <<< "$row"
  [[ "$state" == dead ]] || return 1
  _forward_retire_dead_lock "$sid" "$pid"
}
expect "authorized recovery cycle retires exact dead lock" cycle_orphan_lock_scan
expect "authorized recovery removed dead lock" test ! -e "$LOCK_DIR/EFAIL.lock"
expect "MAX_CONCURRENT=1 remains available after dead-lock recovery" \
  test "$(active_count)" = 0

printf '%s\n' "$dead" > "$LOCK_DIR/bad!.lock"; chmod 600 "$LOCK_DIR/bad!.lock"
if cycle_orphan_lock_scan; then
  fail "invalid lock identity blocks cycle"
else
  pass "invalid lock identity blocks cycle"
fi
expect "invalid lock identity remains untouched" test -e "$LOCK_DIR/bad!.lock"

rm -f "$LOCK_DIR/bad!.lock" "$LOCK_DIR/ELIVE.lock"
expect "empty orphan corpus is a closed no-op" cycle_orphan_lock_scan

printf '%s\n' "$dead" > "$LOCK_DIR/EABA.lock"; chmod 600 "$LOCK_DIR/EABA.lock"
printf '%s\n' "$$" > "$LOCK_DIR/EABA-SUCCESSOR.lock"; chmod 600 "$LOCK_DIR/EABA-SUCCESSOR.lock"
aba_old_before=$(python3 - "$LOCK_DIR/EABA.lock" <<'PY'
import os, sys
entry = os.lstat(sys.argv[1])
print("%s:%s" % (entry.st_dev, entry.st_ino))
PY
)
aba_successor_before=$(python3 - "$LOCK_DIR/EABA-SUCCESSOR.lock" <<'PY'
import os, sys
entry = os.lstat(sys.argv[1])
print("%s:%s" % (entry.st_dev, entry.st_ino))
PY
)
FAULT_PYTHON="$TMP/fault-python"; mkdir -p "$FAULT_PYTHON"
cat > "$FAULT_PYTHON/sitecustomize.py" <<'PY'
import os

_real_rename = os.rename
_injected = False

def _swap_before_quarantine(src, dst, *args, **kwargs):
    global _injected
    if (not _injected and src == "EABA.lock"
            and dst.startswith(".EABA.lock.") and dst.endswith(".retire")):
        _injected = True
        source_fd = kwargs.get("src_dir_fd")
        target_fd = kwargs.get("dst_dir_fd")
        _real_rename(
            src, "EABA-OLD.lock", src_dir_fd=source_fd, dst_dir_fd=target_fd
        )
        _real_rename(
            "EABA-SUCCESSOR.lock", src,
            src_dir_fd=source_fd, dst_dir_fd=source_fd,
        )
    return _real_rename(src, dst, *args, **kwargs)

os.rename = _swap_before_quarantine
PY
aba_rc=0
PYTHONPATH="$FAULT_PYTHON" _forward_retire_dead_lock EABA "$dead" || aba_rc=$?
aba_current_after=$(python3 - "$LOCK_DIR/EABA.lock" <<'PY'
import os, sys
entry = os.lstat(sys.argv[1])
print("%s:%s" % (entry.st_dev, entry.st_ino))
PY
)
aba_old_after=$(python3 - "$LOCK_DIR/EABA-OLD.lock" <<'PY'
import os, sys
entry = os.lstat(sys.argv[1])
print("%s:%s" % (entry.st_dev, entry.st_ino))
PY
)
if [[ "$aba_rc" -ne 0 && "$aba_current_after" == "$aba_successor_before" \
    && "$aba_old_after" == "$aba_old_before" ]] \
    && grep -qx "$$" "$LOCK_DIR/EABA.lock" \
    && grep -qx "$dead" "$LOCK_DIR/EABA-OLD.lock"; then
  pass "ABA swap restores exact successor and preserves old inode evidence"
else
  fail "ABA swap deleted or overwrote successor/old evidence"
fi
if _forward_retire_dead_lock EABA-OLD "$dead" \
    && [[ ! -e "$LOCK_DIR/EABA-OLD.lock" ]] \
    && [[ "$aba_current_after" == "$(python3 - "$LOCK_DIR/EABA.lock" <<'PY'
import os, sys
entry = os.lstat(sys.argv[1])
print("%s:%s" % (entry.st_dev, entry.st_ino))
PY
)" ]] && grep -qx "$$" "$LOCK_DIR/EABA.lock"; then
  pass "only the old dead inode retires after ABA refusal"
else
  fail "old-inode retirement disturbed the live successor"
fi
rm -f "$LOCK_DIR/EABA.lock"

printf '%s\n' "$dead" > "$LOCK_DIR/ERACE.lock"; chmod 600 "$LOCK_DIR/ERACE.lock"
( _forward_retire_dead_lock ERACE "$dead"; printf '%s\n' "$?" > "$TMP/race-a" ) &
p1=$!
( _forward_retire_dead_lock ERACE "$dead"; printf '%s\n' "$?" > "$TMP/race-b" ) &
p2=$!
wait "$p1"; wait "$p2"
race_a=$(cat "$TMP/race-a")
race_b=$(cat "$TMP/race-b")
sum=$(( race_a + race_b ))
if [[ "$sum" -eq 1 ]]; then
  pass "concurrent retirement has exactly one winner"
else
  fail "concurrent retirement has exactly one winner (rc_a=$race_a rc_b=$race_b)"
fi

python3 - "$DAEMON" <<'PY'
import sys
text = open(sys.argv[1]).read()
cleanup = text[text.index('clean_stale_locks()'):text.index('# ── Cycle-time orphan-lock scan')]
if 'rm -f "$lock"' not in cleanup:
    raise SystemExit(1)
# The sole removal remains inside the placeholder branch; numeric dead-PID
# handling is comments only until the descriptor-bound coordinator.
tail = cleanup.split('if [[ -z "$pid" || "$pid" == "pending" ]]', 1)[1]
if tail.count('rm -f "$lock"') != 1:
    raise SystemExit(1)
PY
expect "ordinary cleanup cannot delete numeric dead-lock evidence" test "$?" -eq 0

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
