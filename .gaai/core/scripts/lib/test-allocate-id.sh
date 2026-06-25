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

# ── Test 7: AC5 — word-embedded E<n> branch names do not inflate the epic max ─
echo "Test 7: AC5 — over-match guard (E2E-style branch names ignored)"

T7="${WORK}/t7"; mkdir -p "$T7"
T7_BARE="${WORK}/t7-remote.git"
T7_SEED="${WORK}/t7-seed"
T7_WORK="${WORK}/t7-work"

git init -q --bare "$T7_BARE"
git init -q "$T7_SEED"
(
  cd "$T7_SEED"
  git config user.email t@example.test; git config user.name tester
  git commit -q --allow-empty -m init
  git branch E2E-test-harness          # token E2 followed by a letter → must be ignored
  git branch feature-no-id             # no token at all
  git remote add origin "$T7_BARE"
  git push -q origin --all
) >/dev/null 2>&1
git init -q "$T7_WORK"
( cd "$T7_WORK"; git remote add testremote "$T7_BARE" ) >/dev/null 2>&1

T7_EMPTY="${T7}/active.backlog.yaml"; printf '# empty\n' > "$T7_EMPTY"

R7="$(cd "$T7_WORK" && GAAI_SCAN_REMOTE=1 GAAI_REMOTE=testremote \
  GAAI_BACKLOG_PATH="$T7_EMPTY" GAAI_RESERVATION_LEDGER="${WORK}/t7.tsv" "$ALLOCATOR" epic)"
if [[ "$R7" == "E1" ]]; then
  _pass "E2E-test-harness ignored (empty backlog/ledger → ${R7}, not E2/E3)"
else
  _fail "Expected E1 (E2E-* must not seed the epic max), got: ${R7}"
fi

# ── Test 8: AC6 — git-CAS concurrency (hermetic local bare remote) ───────────
echo "Test 8: AC6 — git-CAS concurrent reservations get distinct IDs"

T8_BARE="${WORK}/t8-remote.git"
T8_SEED="${WORK}/t8-seed"
T8_WORK_A="${WORK}/t8-work-a"
T8_WORK_B="${WORK}/t8-work-b"

git init -q --bare "$T8_BARE"
git init -q "$T8_SEED"
(
  cd "$T8_SEED"
  git config user.email t@example.test
  git config user.name tester
  git commit -q --allow-empty -m init
  git remote add origin "$T8_BARE"
  git push -q origin HEAD
) >/dev/null 2>&1

git clone -q "$T8_BARE" "$T8_WORK_A" >/dev/null 2>&1
git clone -q "$T8_BARE" "$T8_WORK_B" >/dev/null 2>&1

T8_EMPTY="${WORK}/t8-empty.yaml"
printf '# empty\n' > "$T8_EMPTY"
T8_OUT_A="${WORK}/t8a.txt"
T8_OUT_B="${WORK}/t8b.txt"

(
  cd "$T8_WORK_A"
  GAAI_SCAN_REMOTE=1 GAAI_RESERVATION_BACKEND=git-cas \
  GAAI_BACKLOG_PATH="$T8_EMPTY" GAAI_RESERVATION_LEDGER="${WORK}/t8a.tsv" \
    "$ALLOCATOR" epic > "$T8_OUT_A" 2>/dev/null
) &
PID_A=$!

(
  cd "$T8_WORK_B"
  GAAI_SCAN_REMOTE=1 GAAI_RESERVATION_BACKEND=git-cas \
  GAAI_BACKLOG_PATH="$T8_EMPTY" GAAI_RESERVATION_LEDGER="${WORK}/t8b.tsv" \
    "$ALLOCATOR" epic > "$T8_OUT_B" 2>/dev/null
) &
PID_B=$!

wait "$PID_A" "$PID_B" 2>/dev/null || true

T8_ID_A="$(cat "$T8_OUT_A" 2>/dev/null || echo "")"
T8_ID_B="$(cat "$T8_OUT_B" 2>/dev/null || echo "")"

if [[ -n "$T8_ID_A" && -n "$T8_ID_B" && "$T8_ID_A" != "$T8_ID_B" ]]; then
  _pass "CAS concurrent: A=${T8_ID_A}, B=${T8_ID_B} (distinct)"
else
  _fail "CAS concurrent: A='${T8_ID_A}' B='${T8_ID_B}' — expected distinct non-empty IDs"
fi

# Verify refs/gaai/reservations was pushed to the bare remote after both runs.
T8_CAS_ON_REMOTE="$(cd "$T8_WORK_A" && \
  git ls-remote origin refs/gaai/reservations 2>/dev/null | awk '{print $1}' || echo "")"
if [[ -n "$T8_CAS_ON_REMOTE" ]]; then
  _pass "refs/gaai/reservations present on remote (OID=${T8_CAS_ON_REMOTE:0:12}...)"
else
  _fail "refs/gaai/reservations absent from remote after two CAS allocations"
fi

# ── Test 9: dec mode — basic allocation from decisions directory ──────────────
echo "Test 9: dec mode — allocation from decisions dir + _log.md"

T9="${WORK}/t9"
T9_DECISIONS="${WORK}/t9-decisions"
mkdir -p "$T9" "$T9_DECISIONS"
printf '# empty\n' > "${T9}/active.backlog.yaml"
T9_LEDGER="${WORK}/t9.tsv"

# Dec ids built from vars — no literal dec-id pattern in source
T9_N_A=5; T9_N_B=10; T9_N_NEXT=11
T9_DEC_A="DEC-${T9_N_A}"; T9_DEC_B="DEC-${T9_N_B}"; T9_DEC_NEXT="DEC-${T9_N_NEXT}"

# Populate decisions dir with two files (max = T9_N_B → expect T9_N_NEXT)
touch "${T9_DECISIONS}/${T9_DEC_A}.md" "${T9_DECISIONS}/${T9_DEC_B}.md"

R9A="$(GAAI_SCAN_REMOTE=0 GAAI_DECISIONS_PATH="$T9_DECISIONS" \
  GAAI_BACKLOG_PATH="${T9}/active.backlog.yaml" GAAI_RESERVATION_LEDGER="$T9_LEDGER" \
  "$ALLOCATOR" dec)"

if [[ "$R9A" == "$T9_DEC_NEXT" ]]; then
  _pass "dec allocation from decisions dir (max ${T9_DEC_B} → ${T9_DEC_NEXT}): ${R9A}"
else
  _fail "Expected ${T9_DEC_NEXT} from decisions dir (${T9_DEC_A}, ${T9_DEC_B}), got: ${R9A}"
fi

# Add _log.md referencing a higher dec — should yield T9_N_LOG_NEXT
T9_N_LOG=15; T9_N_LOG_NEXT=16
T9_DEC_LOG="DEC-${T9_N_LOG}"; T9_DEC_LOG_NEXT="DEC-${T9_N_LOG_NEXT}"
T9_DECISIONS2="${WORK}/t9-decisions2"
mkdir -p "$T9_DECISIONS2"
touch "${T9_DECISIONS2}/${T9_DEC_A}.md" "${T9_DECISIONS2}/${T9_DEC_B}.md"
printf '| %s | tooling | operational | some decision |\n' "$T9_DEC_LOG" > "${T9_DECISIONS2}/_log.md"
T9_LEDGER2="${WORK}/t9b.tsv"

R9B="$(GAAI_SCAN_REMOTE=0 GAAI_DECISIONS_PATH="$T9_DECISIONS2" \
  GAAI_BACKLOG_PATH="${T9}/active.backlog.yaml" GAAI_RESERVATION_LEDGER="$T9_LEDGER2" \
  "$ALLOCATOR" dec)"

if [[ "$R9B" == "$T9_DEC_LOG_NEXT" ]]; then
  _pass "dec allocation from _log.md max (${T9_DEC_LOG} in log > ${T9_DEC_B} in files → ${T9_DEC_LOG_NEXT}): ${R9B}"
else
  _fail "Expected ${T9_DEC_LOG_NEXT} (_log.md max ${T9_DEC_LOG} > files max ${T9_DEC_B}), got: ${R9B}"
fi

# ── Test 10: concurrent dec allocations → distinct IDs ───────────────────────
echo "Test 10: dec mode — 5 concurrent allocations yield distinct IDs"

T10="${WORK}/t10"
T10_DECISIONS="${WORK}/t10-decisions"
mkdir -p "$T10" "$T10_DECISIONS"
printf '# empty\n' > "${T10}/active.backlog.yaml"
T10_OUT="${WORK}/t10-out"
mkdir -p "$T10_OUT"

PIDS10=()
for i in $(seq 1 5); do
  GAAI_SCAN_REMOTE=0 \
  GAAI_DECISIONS_PATH="$T10_DECISIONS" \
  GAAI_BACKLOG_PATH="${T10}/active.backlog.yaml" \
  GAAI_RESERVATION_LEDGER="${WORK}/t10.tsv" \
    "$ALLOCATOR" dec > "${T10_OUT}/${i}.txt" 2>/dev/null &
  PIDS10+=($!)
done

for pid in "${PIDS10[@]}"; do
  wait "$pid" || true
done

RESULTS10=()
for i in $(seq 1 5); do
  val="$(cat "${T10_OUT}/${i}.txt" 2>/dev/null || echo "")"
  RESULTS10+=("$val")
done

UNIQUE10="$(printf '%s\n' "${RESULTS10[@]}" | grep -v '^$' | sort -u | wc -l | tr -d ' ')"
TOTAL10="$(printf '%s\n' "${RESULTS10[@]}" | grep -v '^$' | wc -l | tr -d ' ')"

if [[ "$TOTAL10" -eq 5 && "$UNIQUE10" -eq 5 ]]; then
  _pass "5 concurrent dec allocations → 5 distinct IDs ($(printf '%s\n' "${RESULTS10[@]}" | sort -t- -k2 -n | tr '\n' ' '))"
else
  _fail "Expected 5 unique dec IDs, got total=${TOTAL10} unique=${UNIQUE10}: $(printf '%s\n' "${RESULTS10[@]}" | sort | tr '\n' ' ')"
fi

# ── Test 11: Kind-branched landed-prune (AC3 — three sub-checks) ─────────────
echo "Test 11: AC3 — kind-branched landed-prune"

T11="${WORK}/t11"
T11_DECISIONS="${WORK}/t11-decisions"
T11_BACKLOG="${WORK}/t11-backlog"
mkdir -p "$T11" "$T11_DECISIONS" "$T11_BACKLOG"
T11_NOW="$(date +%s)"

# Dec prune ids — built from vars (no literal dec-id pattern in source)
T11_N_LANDED=20; T11_N_KEPT=21
T11_DEC_LANDED="DEC-${T11_N_LANDED}"; T11_DEC_KEPT="DEC-${T11_N_KEPT}"

# 11a: dec entries — T11_DEC_LANDED with matching file (landed → prune); T11_DEC_KEPT without (keep)
T11_LEDGER_A="${WORK}/t11a.tsv"
printf '# GAAI ID reservation ledger — do not edit manually\n' > "$T11_LEDGER_A"
printf '%s\tdec\t%s\n' "$T11_DEC_LANDED" "$T11_NOW" >> "$T11_LEDGER_A"
printf '%s\tdec\t%s\n' "$T11_DEC_KEPT"   "$T11_NOW" >> "$T11_LEDGER_A"
touch "${T11_DECISIONS}/${T11_DEC_LANDED}.md"   # file exists → entry should be pruned
                                                 # ${T11_DEC_KEPT}.md does NOT exist → entry kept
T11_EMPTY_BACKLOG="${T11_BACKLOG}/active.backlog.yaml"
printf '# empty\n' > "$T11_EMPTY_BACKLOG"

GAAI_SCAN_REMOTE=0 \
GAAI_DECISIONS_PATH="$T11_DECISIONS" \
GAAI_BACKLOG_PATH="$T11_EMPTY_BACKLOG" \
GAAI_RESERVATION_LEDGER="$T11_LEDGER_A" \
  "$ALLOCATOR" dec > /dev/null 2>/dev/null || true

T11A_IDS="$(grep -v '^#' "$T11_LEDGER_A" 2>/dev/null | awk -F'\t' '{print $1}' | sort | tr '\n' ' ' || true)"
if ! echo "$T11A_IDS" | grep -qF "$T11_DEC_LANDED" && echo "$T11A_IDS" | grep -qF "$T11_DEC_KEPT"; then
  _pass "11a: dec ${T11_DEC_LANDED} (file exists) pruned, ${T11_DEC_KEPT} (no file) kept — ledger: ${T11A_IDS}"
else
  _fail "11a: dec prune wrong — ${T11_DEC_LANDED} should be gone, ${T11_DEC_KEPT} should remain — ledger: ${T11A_IDS}"
fi

# 11b: epic entries — E${T11_N_LANDED} in backlog (prune), E${T11_N_KEPT} not in backlog (keep) — unchanged
T11_LEDGER_B="${WORK}/t11b.tsv"
printf '# GAAI ID reservation ledger — do not edit manually\n' > "$T11_LEDGER_B"
printf 'E%s\tepic\t%s\n' "$T11_N_LANDED" "$T11_NOW" >> "$T11_LEDGER_B"
printf 'E%s\tepic\t%s\n' "$T11_N_KEPT"   "$T11_NOW" >> "$T11_LEDGER_B"
printf -- '- id: E%s\n  epic: E%s\n  title: Landed epic\n  status: done\n' \
  "$T11_N_LANDED" "$T11_N_LANDED" > "${T11_BACKLOG}/active.backlog.yaml"

GAAI_SCAN_REMOTE=0 \
GAAI_DECISIONS_PATH="$T11_DECISIONS" \
GAAI_BACKLOG_PATH="${T11_BACKLOG}/active.backlog.yaml" \
GAAI_RESERVATION_LEDGER="$T11_LEDGER_B" \
  "$ALLOCATOR" epic > /dev/null 2>/dev/null || true

T11B_IDS="$(grep -v '^#' "$T11_LEDGER_B" 2>/dev/null | awk -F'\t' '{print $1}' | sort | tr '\n' ' ' || true)"
if ! echo "$T11B_IDS" | grep -q "E${T11_N_LANDED}" && echo "$T11B_IDS" | grep -q "E${T11_N_KEPT}"; then
  _pass "11b: epic E${T11_N_LANDED} (in backlog) pruned, E${T11_N_KEPT} (not in backlog) kept — ledger: ${T11B_IDS}"
else
  _fail "11b: epic prune wrong — E${T11_N_LANDED} should be gone, E${T11_N_KEPT} should remain — ledger: ${T11B_IDS}"
fi

# 11c: Anti-cross-prune — epic E${T11_N_LANDED} NOT in backlog, dec file for same number EXISTS → must NOT prune epic
T11_DECISIONS_C="${WORK}/t11-decisions-c"
mkdir -p "$T11_DECISIONS_C"
touch "${T11_DECISIONS_C}/${T11_DEC_LANDED}.md"  # dec file exists — epic entry must NOT be pruned by it
T11_LEDGER_C="${WORK}/t11c.tsv"
printf '# GAAI ID reservation ledger — do not edit manually\n' > "$T11_LEDGER_C"
printf 'E%s\tepic\t%s\n' "$T11_N_LANDED" "$T11_NOW" >> "$T11_LEDGER_C"
printf '# empty backlog\n' > "${T11_BACKLOG}/empty.yaml"

GAAI_SCAN_REMOTE=0 \
GAAI_DECISIONS_PATH="$T11_DECISIONS_C" \
GAAI_BACKLOG_PATH="${T11_BACKLOG}/empty.yaml" \
GAAI_RESERVATION_LEDGER="$T11_LEDGER_C" \
  "$ALLOCATOR" epic > /dev/null 2>/dev/null || true

T11C_IDS="$(grep -v '^#' "$T11_LEDGER_C" 2>/dev/null | awk -F'\t' '{print $1}' | sort | tr '\n' ' ' || true)"
if echo "$T11C_IDS" | grep -q "E${T11_N_LANDED}"; then
  _pass "11c: ${T11_DEC_LANDED}.md does NOT prune epic E${T11_N_LANDED} (kind-branch respected) — ledger: ${T11C_IDS}"
else
  _fail "11c: kind-branch violated — epic E${T11_N_LANDED} pruned because ${T11_DEC_LANDED}.md exists — ledger: ${T11C_IDS}"
fi

# ── Test 12: dec CAS concurrency (AC6) ───────────────────────────────────────
echo "Test 12: AC6 — git-CAS dec concurrent reservations get distinct IDs"

T12_BARE="${WORK}/t12-remote.git"
T12_SEED="${WORK}/t12-seed"
T12_WORK_A="${WORK}/t12-work-a"
T12_WORK_B="${WORK}/t12-work-b"
T12_DECISIONS_A="${WORK}/t12-decisions-a"
T12_DECISIONS_B="${WORK}/t12-decisions-b"
mkdir -p "$T12_DECISIONS_A" "$T12_DECISIONS_B"

git init -q --bare "$T12_BARE"
git init -q "$T12_SEED"
(
  cd "$T12_SEED"
  git config user.email t@example.test
  git config user.name tester
  git commit -q --allow-empty -m init
  git remote add origin "$T12_BARE"
  git push -q origin HEAD
) >/dev/null 2>&1

git clone -q "$T12_BARE" "$T12_WORK_A" >/dev/null 2>&1
git clone -q "$T12_BARE" "$T12_WORK_B" >/dev/null 2>&1

T12_EMPTY="${WORK}/t12-empty.yaml"
printf '# empty\n' > "$T12_EMPTY"
T12_OUT_A="${WORK}/t12a.txt"
T12_OUT_B="${WORK}/t12b.txt"

(
  cd "$T12_WORK_A"
  GAAI_SCAN_REMOTE=1 GAAI_RESERVATION_BACKEND=git-cas \
  GAAI_DECISIONS_PATH="$T12_DECISIONS_A" \
  GAAI_BACKLOG_PATH="$T12_EMPTY" GAAI_RESERVATION_LEDGER="${WORK}/t12a.tsv" \
    "$ALLOCATOR" dec > "$T12_OUT_A" 2>/dev/null
) &
PID12_A=$!

(
  cd "$T12_WORK_B"
  GAAI_SCAN_REMOTE=1 GAAI_RESERVATION_BACKEND=git-cas \
  GAAI_DECISIONS_PATH="$T12_DECISIONS_B" \
  GAAI_BACKLOG_PATH="$T12_EMPTY" GAAI_RESERVATION_LEDGER="${WORK}/t12b.tsv" \
    "$ALLOCATOR" dec > "$T12_OUT_B" 2>/dev/null
) &
PID12_B=$!

wait "$PID12_A" "$PID12_B" 2>/dev/null || true

T12_ID_A="$(cat "$T12_OUT_A" 2>/dev/null || echo "")"
T12_ID_B="$(cat "$T12_OUT_B" 2>/dev/null || echo "")"

if [[ -n "$T12_ID_A" && -n "$T12_ID_B" && "$T12_ID_A" != "$T12_ID_B" ]]; then
  _pass "CAS dec concurrent: A=${T12_ID_A}, B=${T12_ID_B} (distinct)"
else
  _fail "CAS dec concurrent: A='${T12_ID_A}' B='${T12_ID_B}' — expected distinct non-empty DEC IDs"
fi

# Verify refs/gaai/reservations was pushed to the bare remote.
T12_CAS_ON_REMOTE="$(cd "$T12_WORK_A" && \
  git ls-remote origin refs/gaai/reservations 2>/dev/null | awk '{print $1}' || echo "")"
if [[ -n "$T12_CAS_ON_REMOTE" ]]; then
  _pass "refs/gaai/reservations present on remote after dec CAS (OID=${T12_CAS_ON_REMOTE:0:12}...)"
else
  _fail "refs/gaai/reservations absent from remote after two dec CAS allocations"
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
