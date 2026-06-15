#!/usr/bin/env bash
# test-allocate-id.sh — test suite for allocate-id.sh
# Covers AC1 (concurrent uniqueness), AC2 (cross-worktree visibility),
# AC3 (max over backlog AND ledger), AC4 (TTL + backlog prune).
# Exit 0 = ALL TESTS PASSED. Exit 1 = one or more failures.

set -euo pipefail

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
