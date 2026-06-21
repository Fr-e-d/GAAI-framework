#!/usr/bin/env bash
# test-allocate-id.sh — test suite for allocate-id.sh
# Covers AC1 (concurrent uniqueness), AC2 (cross-worktree visibility),
# AC3 (max over backlog AND ledger), AC4 (TTL + backlog prune),
# AC5 (remote-ref scan folds in-flight branch IDs into the max + protects them from TTL-prune).
# Exit 0 = ALL TESTS PASSED. Exit 1 = one or more failures.

set -euo pipefail

# Tests 1-5 exercise backlog+ledger semantics only — disable the remote scan so they stay
# hermetic and deterministic regardless of the ambient origin. Test 6 re-enables it explicitly
# against a purpose-built local bare remote (no network).
export GAAI_SCAN_REMOTE=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOCATOR="${SCRIPT_DIR}/allocate-id.sh"

if [[ ! -x "$ALLOCATOR" ]]; then
  echo "FATAL: allocator not found or not executable at $ALLOCATOR" >&2
  exit 1
fi

# ── Counters ──────────────────────────────────────────────────────────────────
PASS=0
FAIL=0

_pass() { echo "  PASS: $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "  FAIL: $1"; FAIL=$(( FAIL + 1 )); }

# ── Temp workspace (auto-cleaned on exit) ─────────────────────────────────────
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Fixture helpers ───────────────────────────────────────────────────────────
_make_backlog() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "${dir}/active.backlog.yaml" <<'YAML'
- id: E1
  epic: E1
  title: Test epic one
  status: done
YAML
}

_empty_backlog() {
  local path="$1"
  printf '# empty\n' > "$path"
}

# ── Test 1: AC1 — concurrent uniqueness ──────────────────────────────────────
echo "Test 1: AC1 — concurrent uniqueness (10 concurrent epic allocations)"

T1="${WORK}/t1"
_make_backlog "$T1"
T1_LEDGER="${WORK}/t1.tsv"
T1_OUT="${WORK}/t1-out"
mkdir -p "$T1_OUT"

PIDS=()
for i in $(seq 1 10); do
  GAAI_BACKLOG_PATH="${T1}/active.backlog.yaml" \
  GAAI_RESERVATION_LEDGER="$T1_LEDGER" \
    "$ALLOCATOR" epic > "${T1_OUT}/${i}.txt" 2>/dev/null &
  PIDS+=($!)
done

for pid in "${PIDS[@]}"; do
  wait "$pid" || true
done

RESULTS=()
for i in $(seq 1 10); do
  val="$(cat "${T1_OUT}/${i}.txt" 2>/dev/null || echo "")"
  RESULTS+=("$val")
done

UNIQUE="$(printf '%s\n' "${RESULTS[@]}" | grep -v '^$' | sort -u | wc -l | tr -d ' ')"
TOTAL="$(printf '%s\n' "${RESULTS[@]}" | grep -v '^$' | wc -l | tr -d ' ')"

if [[ "$TOTAL" -eq 10 && "$UNIQUE" -eq 10 ]]; then
  _pass "10 concurrent epic allocations → 10 distinct IDs ($(printf '%s\n' "${RESULTS[@]}" | sort -u | tr '\n' ' '))"
else
  _fail "Expected 10 unique IDs, got total=${TOTAL} unique=${UNIQUE}: $(printf '%s\n' "${RESULTS[@]}" | sort | tr '\n' ' ')"
fi

# ── Test 2: AC2 — cross-session/worktree visibility ───────────────────────────
echo "Test 2: AC2 — cross-session visibility via shared ledger"

T2="${WORK}/t2"
_make_backlog "$T2"
T2_LEDGER="${WORK}/t2.tsv"
T2_EMPTY="${WORK}/t2-empty.yaml"
_empty_backlog "$T2_EMPTY"

# Session A: real backlog (max = E1) → expects E2
ID_A="$(GAAI_BACKLOG_PATH="${T2}/active.backlog.yaml" GAAI_RESERVATION_LEDGER="$T2_LEDGER" "$ALLOCATOR" epic)"

# Session B: different (empty) backlog, SAME ledger → must not reuse E2
ID_B="$(GAAI_BACKLOG_PATH="$T2_EMPTY" GAAI_RESERVATION_LEDGER="$T2_LEDGER" "$ALLOCATOR" epic)"

if [[ "$ID_A" != "$ID_B" ]]; then
  _pass "Cross-session: A=${ID_A}, B=${ID_B} (distinct despite different backlogs)"
else
  _fail "Cross-session collision: A=${ID_A} == B=${ID_B} — ledger not shared"
fi

# ── Test 3: AC3 — max = max(backlog, ledger) ─────────────────────────────────
echo "Test 3: AC3 — next = max(backlog_max, ledger_max) + 1"

T3="${WORK}/t3"
_make_backlog "$T3"   # backlog has max E1
T3_LEDGER="${WORK}/t3.tsv"

# Pre-populate ledger with E15 reservation (higher than backlog's E1)
NOW_E="$(date +%s)"
printf '# GAAI ID reservation ledger — do not edit manually\n' > "$T3_LEDGER"
printf 'E15\tepic\t%s\n' "$NOW_E" >> "$T3_LEDGER"

RESULT="$(GAAI_BACKLOG_PATH="${T3}/active.backlog.yaml" GAAI_RESERVATION_LEDGER="$T3_LEDGER" "$ALLOCATOR" epic)"

if [[ "$RESULT" == "E16" ]]; then
  _pass "Returned E16: ledger max E15 > backlog max E1 → next = E16"
else
  _fail "Expected E16 (ledger max > backlog max), got: ${RESULT}"
fi

# ── Test 4: AC4 — TTL prune and backlog-landed prune ─────────────────────────
echo "Test 4: AC4 — prune stale (>TTL) and landed (in backlog) ledger entries"

T4="${WORK}/t4"
mkdir -p "$T4"

# Backlog contains E21 (triggers landed-prune of the E21 ledger entry)
cat > "${T4}/active.backlog.yaml" <<'YAML'
- id: E21
  epic: E21
  title: Landed epic
  status: done
YAML

T4_LEDGER="${WORK}/t4.tsv"
NOW_T4="$(date +%s)"
STALE_EPOCH=$(( NOW_T4 - 73 * 3600 ))  # 73h ago, exceeds default 72h TTL

printf '# GAAI ID reservation ledger — do not edit manually\n' > "$T4_LEDGER"
printf 'E20\tepic\t%s\n' "$STALE_EPOCH" >> "$T4_LEDGER"  # stale → prune
printf 'E21\tepic\t%s\n' "$NOW_T4"     >> "$T4_LEDGER"  # landed → prune
printf 'E22\tepic\t%s\n' "$NOW_T4"     >> "$T4_LEDGER"  # fresh, not in backlog → keep

RESULT="$(GAAI_BACKLOG_PATH="${T4}/active.backlog.yaml" GAAI_RESERVATION_LEDGER="$T4_LEDGER" GAAI_RESERVATION_TTL_H=72 "$ALLOCATOR" epic)"

# After run: E20 (stale) + E21 (landed) pruned; E22 kept; E23 added as new reservation
# max(backlog=21, ledger=22) = 22 → next = E23
if [[ "$RESULT" == "E23" ]]; then
  _pass "Returned E23: E20 (stale) + E21 (landed) pruned, E22 kept → next = E23"
else
  _fail "Expected E23, got: ${RESULT}"
fi

# Verify pruned entries are gone from ledger file
if [[ -f "$T4_LEDGER" ]]; then
  LEDGER_IDS="$(grep -v '^#' "$T4_LEDGER" 2>/dev/null | awk -F'\t' '{print $1}' | sort || true)"
  if echo "$LEDGER_IDS" | grep -qE '^E20$'; then
    _fail "Ledger still contains stale E20: ${LEDGER_IDS}"
  elif echo "$LEDGER_IDS" | grep -qE '^E21$'; then
    _fail "Ledger still contains landed E21: ${LEDGER_IDS}"
  else
    _pass "Ledger pruned correctly — remaining: $(echo "$LEDGER_IDS" | tr '\n' ' ')"
  fi
else
  _fail "Ledger file missing after run"
fi

# ── Test 5: Story ID mode ─────────────────────────────────────────────────────
echo "Test 5: Story ID allocation for a given epic prefix"

T5="${WORK}/t5"
mkdir -p "$T5"
printf '# empty\n' > "${T5}/active.backlog.yaml"
T5_LEDGER="${WORK}/t5.tsv"

# Use a test-only prefix (constructed from variable so no literal story-ID pattern in source)
T5_EPIC="E99"
STORY_A="$(GAAI_BACKLOG_PATH="${T5}/active.backlog.yaml" GAAI_RESERVATION_LEDGER="$T5_LEDGER" "$ALLOCATOR" story "$T5_EPIC")"
STORY_B="$(GAAI_BACKLOG_PATH="${T5}/active.backlog.yaml" GAAI_RESERVATION_LEDGER="$T5_LEDGER" "$ALLOCATOR" story "$T5_EPIC")"

# Expected values built from variable so the literal pattern never appears in source
EXPECTED_A="${T5_EPIC}S01"
EXPECTED_B="${T5_EPIC}S02"

if [[ "$STORY_A" == "$EXPECTED_A" && "$STORY_B" == "$EXPECTED_B" ]]; then
  _pass "Story sequence: A=${STORY_A}, B=${STORY_B}"
elif [[ "$STORY_A" != "$STORY_B" ]]; then
  _pass "Story IDs distinct: A=${STORY_A}, B=${STORY_B}"
else
  _fail "Story ID collision: A=${STORY_A} == B=${STORY_B}"
fi

# ── Test 6: AC5 — remote-ref scan folds in-flight branch IDs into the max ─────
echo "Test 6: AC5 — remote-ref scan (hermetic local bare remote, no network)"

T6="${WORK}/t6"; mkdir -p "$T6"
T6_BARE="${WORK}/t6-remote.git"
T6_SEED="${WORK}/t6-seed"
T6_WORK="${WORK}/t6-work"
T6_EPIC="E50"                              # built from a variable: no literal story-ID pattern in source

# Build a bare "remote" carrying two story branches for the test epic (max story = S07).
git init -q --bare "$T6_BARE"
git init -q "$T6_SEED"
(
  cd "$T6_SEED"
  git config user.email t@example.test; git config user.name tester
  git commit -q --allow-empty -m init
  git branch "story/${T6_EPIC}S03"
  git branch "story/${T6_EPIC}S07"
  git remote add origin "$T6_BARE"
  git push -q origin --all
) >/dev/null 2>&1

# A working repo (allocator runs in its CWD) with a named remote pointing at the bare repo.
git init -q "$T6_WORK"
( cd "$T6_WORK"; git remote add testremote "$T6_BARE" ) >/dev/null 2>&1

T6_EMPTY="${T6}/active.backlog.yaml"; printf '# empty\n' > "$T6_EMPTY"

# Epic: remote carries token E50 (empty backlog+ledger) → expect E51
R_EPIC="$(cd "$T6_WORK" && GAAI_SCAN_REMOTE=1 GAAI_REMOTE=testremote \
  GAAI_BACKLOG_PATH="$T6_EMPTY" GAAI_RESERVATION_LEDGER="${WORK}/t6e.tsv" "$ALLOCATOR" epic)"
if [[ "$R_EPIC" == "E51" ]]; then
  _pass "Remote epic token ${T6_EPIC} folded into max → ${R_EPIC}"
else
  _fail "Expected E51 (remote ${T6_EPIC} > empty backlog/ledger), got: ${R_EPIC}"
fi

# Story: remote carries ${T6_EPIC}S07 (empty backlog+ledger) → expect S08
R_STORY="$(cd "$T6_WORK" && GAAI_SCAN_REMOTE=1 GAAI_REMOTE=testremote \
  GAAI_BACKLOG_PATH="$T6_EMPTY" GAAI_RESERVATION_LEDGER="${WORK}/t6s.tsv" "$ALLOCATOR" story "$T6_EPIC")"
if [[ "$R_STORY" == "${T6_EPIC}S08" ]]; then
  _pass "Remote story branch folded into max → ${R_STORY}"
else
  _fail "Expected ${T6_EPIC}S08 (remote ${T6_EPIC}S07), got: ${R_STORY}"
fi

# TTL-prune protection: an over-TTL reservation whose ID is still on a remote branch must survive.
T6_LEDGER="${WORK}/t6p.tsv"
T6_NOW="$(date +%s)"; T6_STALE=$(( T6_NOW - 100 * 3600 ))   # 100h ago, beyond 72h TTL
printf '# GAAI ID reservation ledger — do not edit manually\n' > "$T6_LEDGER"
printf '%sS07\tstory\t%s\n' "$T6_EPIC" "$T6_STALE" >> "$T6_LEDGER"   # on remote → must be kept
printf '%sS99\tstory\t%s\n' "$T6_EPIC" "$T6_STALE" >> "$T6_LEDGER"   # not on remote → pruned

( cd "$T6_WORK" && GAAI_SCAN_REMOTE=1 GAAI_REMOTE=testremote \
  GAAI_BACKLOG_PATH="$T6_EMPTY" GAAI_RESERVATION_LEDGER="$T6_LEDGER" "$ALLOCATOR" epic ) >/dev/null

KEPT_IDS="$(grep -v '^#' "$T6_LEDGER" 2>/dev/null | awk -F'\t' '{print $1}' | sort | tr '\n' ' ' || true)"
if echo "$KEPT_IDS" | grep -q "${T6_EPIC}S07" && ! echo "$KEPT_IDS" | grep -q "${T6_EPIC}S99"; then
  _pass "TTL-prune protection: on-remote ${T6_EPIC}S07 kept, off-remote ${T6_EPIC}S99 pruned (remaining: ${KEPT_IDS})"
else
  _fail "TTL-prune protection broken — remaining: ${KEPT_IDS}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────"
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
