#!/usr/bin/env bash
# allocate-id.test.sh — tests for lib/allocate-id.sh
#
# Covers atomic allocation under flock (AC1), cross-session/cross-worktree
# ledger visibility (AC2), max-over-backlog-and-ledger (AC3), landed/TTL
# pruning (AC4), and project-agnostic + graceful-flock-degradation (AC6).
# Each test runs in an isolated GAAI_LEDGER_DIR so they never touch the host
# ledger, and most use a fixture backlog via GAAI_BACKLOG_PATH (no git repo
# required → also exercises project-agnostic behaviour).
#
# Usage: bash .gaai/core/scripts/tests/allocate-id.test.sh
# Exit 0 = all pass. Exit 1 = at least one failure.

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ALLOC="$SCRIPT_DIR/../lib/allocate-id.sh"

_TMPDIR="${TMPDIR:-/tmp}"; _TMPDIR="${_TMPDIR%/}"
ROOT_TMP="$(mktemp -d "${_TMPDIR}/allocate-id.test.XXXXXX")"
cleanup() { rm -rf "$ROOT_TMP"; }
trap cleanup EXIT

FIXTURE="$ROOT_TMP/backlog.yaml"
# Backlog max epic = 220 (from E220S0x); E220 story max = 02; E174 story max = 10.
cat > "$FIXTURE" << 'YAML_EOF'
items:
- id: E174S10
- id: E219S03
- id: E220S01
- id: E220S02
YAML_EOF

# Allocate into a fresh ledger dir; echo the ID (stdout only).
alloc() {
  local dir="$1"; shift
  GAAI_LEDGER_DIR="$dir" GAAI_BACKLOG_PATH="$FIXTURE" bash "$ALLOC" "$@" 2>/dev/null
}

test_basic_epic() {
  local d="$ROOT_TMP/basic-epic" out
  out="$(alloc "$d" epic)" || { fail "basic_epic: non-zero exit"; return; }
  printf '%s' "$out" | grep -qE '^E[0-9]+$' \
    && pass "basic_epic: single call returns '$out' (E<number>)" \
    || fail "basic_epic: bad format '$out'"
}

test_basic_story() {
  local d="$ROOT_TMP/basic-story" out
  out="$(alloc "$d" story E220)" || { fail "basic_story: non-zero exit"; return; }
  printf '%s' "$out" | grep -qE '^E[0-9]+S[0-9]+$' \
    && pass "basic_story: single call returns '$out' (E<n>S<m>)" \
    || fail "basic_story: bad format '$out'"
}

# AC1: N parallel invocations must all return distinct IDs.
concurrent_distinct() {
  local label="$1"; shift
  local d="$ROOT_TMP/conc-$label" out_dir="$ROOT_TMP/concout-$label"
  mkdir -p "$out_dir"; rm -rf "$d"
  local pids=() i
  for i in $(seq 1 10); do
    GAAI_LEDGER_DIR="$d" GAAI_BACKLOG_PATH="$FIXTURE" \
      bash "$ALLOC" "$@" > "$out_dir/out.$i.txt" 2>/dev/null &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
  local total uniq
  total=$(cat "$out_dir"/out.*.txt | wc -l | tr -d ' ')
  uniq=$(cat "$out_dir"/out.*.txt | sort -u | wc -l | tr -d ' ')
  [ "$total" = "10" ] && [ "$uniq" = "10" ] \
    && pass "concurrent_$label: 10 parallel calls → 10 distinct IDs" \
    || fail "concurrent_$label: duplicates (total=$total unique=$uniq)"
}

test_concurrent_epic()  { concurrent_distinct epic  epic; }
test_concurrent_story() { concurrent_distinct story story E220; }

# AC2: a reservation in one allocation dir is honoured by a later call sharing
# the same ledger (same repo key → same ledger file).
test_cross_session_visibility() {
  local d="$ROOT_TMP/cross" a b
  rm -rf "$d"
  a="$(alloc "$d" epic)" || { fail "cross_session: call A failed"; return; }
  b="$(alloc "$d" epic)" || { fail "cross_session: call B failed"; return; }
  [ "$a" != "$b" ] \
    && pass "cross_session: A='$a' then B='$b' (B did not reuse A's ID)" \
    || fail "cross_session: B reused A's ID ($a)"
}

# AC3: next = max(backlog, ledger) + 1. Backlog max epic = 220, ledger empty.
test_backlog_max_respected() {
  local d="$ROOT_TMP/backlog-max" out
  rm -rf "$d"
  out="$(alloc "$d" epic)" || { fail "backlog_max: non-zero exit"; return; }
  [ "$out" = "E221" ] \
    && pass "backlog_max: backlog epic 220 → '$out'" \
    || fail "backlog_max: expected E221, got '$out'"
}

# AC3: ledger reservation above backlog max is honoured.
test_ledger_max_respected() {
  local d="$ROOT_TMP/ledger-max" out
  rm -rf "$d"
  # Reserve E221 (backlog max is 220), then reserve again: expect E222.
  alloc "$d" epic >/dev/null   # E221
  out="$(alloc "$d" epic)" || { fail "ledger_max: non-zero exit"; return; }
  [ "$out" = "E222" ] \
    && pass "ledger_max: after reserving E221, next → '$out'" \
    || fail "ledger_max: expected E222, got '$out'"
}

# AC4: a ledger entry whose ID has landed in the backlog is pruned on next call.
test_prune_landed() {
  local d="$ROOT_TMP/prune-landed" ledger out lines_before lines_after
  rm -rf "$d"
  # Reserve a story that the fixture backlog already contains (E220S02).
  # Manually plant it as an in-flight reservation to simulate a stale entry.
  mkdir -p "$d/reservations"
  ledger="$d/reservations/default.ledger"
  printf '%s\tstory\tE220S02\n' "$(date +%s)" > "$ledger"
  lines_before=$(wc -l < "$ledger" | tr -d ' ')
  out="$(alloc "$d" story E220)"   # backlog max story = 02 → next = 03
  lines_after=$(wc -l < "$ledger" 2>/dev/null | tr -d ' ')
  # After the call, the planted E220S02 (landed) must be gone; only the new
  # reservation (E220S03) should remain → exactly 1 line.
  [ "$lines_after" = "1" ] && printf '%s' "$out" | grep -q 'E220S03' \
    && pass "prune_landed: stale E220S02 dropped, returned '$out', ledger=$lines_after line(s)" \
    || fail "prune_landed: not pruned (before=$lines_before after=$lines_after out='$out')"
}

# AC4: a reservation older than the TTL is pruned on next call.
test_prune_ttl() {
  local d="$ROOT_TMP/prune-ttl" ledger out
  rm -rf "$d"
  mkdir -p "$d/reservations"
  ledger="$d/reservations/default.ledger"
  # Plant a stale epic reservation (well over the 72h default TTL).
  local stale; stale=$(( $(date +%s) - 100000 ))
  printf '%s\tepic\tE500\n' "$stale" > "$ledger"
  out="$(alloc "$d" epic)"   # stale E500 pruned → next from backlog max 220 → E221
  [ "$out" = "E221" ] \
    && pass "prune_ttl: stale E500 pruned, next → '$out'" \
    || fail "prune_ttl: expected E221, got '$out'"
}

# AC6: with flock absent from PATH, the allocator still returns a valid ID and
# emits a same-host-limitation warning to stderr.
test_flock_unavailable() {
  local d="$ROOT_TMP/no-flock" out err_out restricted_path flock_bin dd
  rm -rf "$d"
  # Build a PATH that keeps every standard utility dir but EXCLUDES the
  # directory holding flock, so `command -v flock` fails and the allocator
  # takes its no-flock degradation branch (AC6).
  flock_bin="$(command -v flock 2>/dev/null)"
  restricted_path=""
  for dd in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
    [ -n "$flock_bin" ] && [ "$dd" = "$(dirname "$flock_bin")" ] && continue
    [ -d "$dd" ] && restricted_path="${restricted_path:+$restricted_path:}$dd"
  done
  # On hosts where flock shares a directory with required utilities (e.g. Linux
  # /usr/bin) flock cannot be excluded without losing mktemp/awk/etc. Skip
  # honestly rather than fail.
  if PATH="$restricted_path" command -v flock >/dev/null 2>&1; then
    echo "  SKIP: flock_unavailable — flock not excludable on this host; AC6 degradation untestable here"
    return
  fi
  out="$(PATH="$restricted_path" GAAI_LEDGER_DIR="$d" GAAI_BACKLOG_PATH="$FIXTURE" \
         bash "$ALLOC" epic 2>"$ROOT_TMP/no-flock.err")"
  err_out="$(cat "$ROOT_TMP/no-flock.err")"
  printf '%s' "$out" | grep -qE '^E[0-9]+$' \
    && printf '%s' "$err_out" | grep -qi 'flock unavailable' \
    && pass "flock_unavailable: returned '$out' + warned (no crash)" \
    || fail "flock_unavailable: out='$out' err='$err_out'"
}

# AC6: project-agnostic. No GAAI_BACKLOG_PATH and not a git repo → no crash,
# returns a valid E<number> (computes from ledger only / empty backlog).
test_project_agnostic() {
  local d="$ROOT_TMP/agnostic" out err_out workdir
  rm -rf "$d"
  workdir="$ROOT_TMP/nowhere"; mkdir -p "$workdir"
  out="$(cd "$workdir" && GAAI_LEDGER_DIR="$d" GAAI_BACKLOG_PATH="" \
         bash "$ALLOC" epic 2>"$ROOT_TMP/agnostic.err")"
  err_out="$(cat "$ROOT_TMP/agnostic.err")"
  printf '%s' "$out" | grep -qE '^E[0-9]+$' \
    && pass "project_agnostic: no-repo/no-backlog → '$out' (graceful)" \
    || fail "project_agnostic: bad output '$out' (err='$err_out')"
}

echo "## allocate-id.test.sh"
test_basic_epic
test_basic_story
test_concurrent_epic
test_concurrent_story
test_cross_session_visibility
test_backlog_max_respected
test_ledger_max_respected
test_prune_landed
test_prune_ttl
test_flock_unavailable
test_project_agnostic

echo
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
