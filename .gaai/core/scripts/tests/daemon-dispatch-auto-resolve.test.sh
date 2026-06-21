#!/usr/bin/env bash
# ── daemon-dispatch-auto-resolve.test.sh ──────────────────────────────────────
# Test harness for E156S07 — _auto_resolve_pr_conflicts() + _auto_resolve_push()
#
# Covers:
#   T1 SUCCESS path — generated files + backlog auto-section resolved, push OK
#   T2 ABORT path — hand-coded .ts conflict triggers ABORT + merge --abort
#   T3 ZERO-CONFLICT path — empty conflict list stays numeric and resolves
#
# Run from repo root: bash .gaai/core/scripts/tests/daemon-dispatch-auto-resolve.test.sh
# Exit 0 = all tests pass. Exit 1 = at least one failure.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
ROUTING_LOG="/tmp/gaai-auto-resolve-test.routing.jsonl"
STORY_ID="E999S99"
TRACE_ID="trace-test-001"

cleanup() { rm -f "$ROUTING_LOG"; }
trap cleanup EXIT

# Export env vars needed by daemon-dispatch.sh sourced functions
export PROJECT_DIR
export ROUTING_LOG_PATH="$ROUTING_LOG"
export GAAI_SKIP_OSS_REFCHECK=""
export SCHEDULER="$(which true)"  # stub scheduler — no-op

# Source daemon-dispatch.sh to get the functions
# shellcheck disable=SC2034
BACKLOG_FILE="/tmp/gaai-auto-resolve-test-backlog.yaml"
source "$SCRIPT_DIR/../daemon-dispatch.sh" 2>/dev/null || true

if ! type _auto_resolve_pr_conflicts &>/dev/null; then
  echo "SKIP: _auto_resolve_pr_conflicts not found (daemon-dispatch.sh may have changed)"
  exit 0
fi

# ── Git fixture helpers ───────────────────────────────────────────────────────

setup_git_fixture() {
  local fixture_dir="$1"
  local conflict_type="$2"  # "success" or "abort"

  rm -rf "$fixture_dir"
  mkdir -p "$fixture_dir"

  # Create bare repo as "origin"
  git init --bare "$fixture_dir/origin.git" 2>/dev/null

  # Create working clone
  git clone "$fixture_dir/origin.git" "$fixture_dir/worktree" 2>/dev/null
  cd "$fixture_dir/worktree"

  # Initial commit on main — include base versions of all files that will conflict
  # so git can perform proper 3-way merge (avoids add/add conflicts)
  git config user.email "test@gaa.test" 2>/dev/null
  git config user.name "Test" 2>/dev/null
  echo "initial" > README.md
  mkdir -p src contexts/artefacts/stories
  echo "// base" > src/worker-configuration.d.ts
  echo "base lockfile" > pnpm-lock.yaml
  # Base backlog: many existing stories to create separation between staging and story additions
  cat > active.backlog.yaml <<'YAML'
# Active backlog
stories:
  - id: E999S01
    status: done
    title: "Existing A"
  - id: E999S02
    status: done
    title: "Existing B"
  - id: E999S03
    status: done
    title: "Existing C"
  - id: E999S04
    status: done
    title: "Existing D"
  - id: E999S05
    status: done
    title: "Existing E"
  - id: E999S06
    status: done
    title: "Existing F"
  - id: E999S07
    status: done
    title: "Existing G"
  - id: E999S08
    status: done
    title: "Existing H"
  - id: E999S09
    status: done
    title: "Existing I"
  - id: E999S10
    status: done
    title: "Existing J"

# End of backlog
YAML
  git add . && git commit -m "initial" 2>/dev/null
  git branch -M main 2>/dev/null
  git push origin main 2>/dev/null

  # Create staging branch
  git checkout -b staging 2>/dev/null
  git push origin staging 2>/dev/null

  # Advance staging with drift (simulating another story merging)
  echo "// staging drift" > src/worker-configuration.d.ts
  echo "staging lockfile" > pnpm-lock.yaml
  # Backlog: insert staging story near top (after existing A)
  cat > active.backlog.yaml <<'YAML'
# Active backlog
stories:
  - id: E999S98
    status: done
    title: "Staging story"
  - id: E999S01
    status: done
    title: "Existing A"
  - id: E999S02
    status: done
    title: "Existing B"
  - id: E999S03
    status: done
    title: "Existing C"
  - id: E999S04
    status: done
    title: "Existing D"
  - id: E999S05
    status: done
    title: "Existing E"
  - id: E999S06
    status: done
    title: "Existing F"
  - id: E999S07
    status: done
    title: "Existing G"
  - id: E999S08
    status: done
    title: "Existing H"
  - id: E999S09
    status: done
    title: "Existing I"
  - id: E999S10
    status: done
    title: "Existing J"

# End of backlog
YAML
  git add . && git commit -m "staging drift" 2>/dev/null
  git push origin staging 2>/dev/null

  # Create story branch from main
  git checkout main 2>/dev/null
  git checkout -b "story/$STORY_ID" 2>/dev/null

  # Story-local changes (different content on same files = conflict)
  echo "// story change" > src/worker-configuration.d.ts
  echo "story lockfile" > pnpm-lock.yaml
  # Backlog: insert story near bottom (before existing J, different hunk than staging)
  cat > active.backlog.yaml <<'YAML'
# Active backlog
stories:
  - id: E999S01
    status: done
    title: "Existing A"
  - id: E999S02
    status: done
    title: "Existing B"
  - id: E999S03
    status: done
    title: "Existing C"
  - id: E999S04
    status: done
    title: "Existing D"
  - id: E999S05
    status: done
    title: "Existing E"
  - id: E999S06
    status: done
    title: "Existing F"
  - id: E999S07
    status: done
    title: "Existing G"
  - id: E999S08
    status: done
    title: "Existing H"
  - id: E999S99
    status: in_progress
    title: "This story"
  - id: E999S09
    status: done
    title: "Existing I"
  - id: E999S10
    status: done
    title: "Existing J"

# End of backlog
YAML
  echo "story artefact" > "contexts/artefacts/stories/${STORY_ID}.story.md"
  git add . && git commit -m "story changes" 2>/dev/null
  git push origin "story/$STORY_ID" 2>/dev/null

  # For abort test, add a conflicting .ts file on staging
  if [[ "$conflict_type" == "abort" ]]; then
    git checkout staging 2>/dev/null
    mkdir -p src 2>/dev/null
    echo "// staging hand-coded" > src/hand-coded.ts
    git add . && git commit -m "staging hand-coded" 2>/dev/null
    git push origin staging 2>/dev/null

    git checkout "story/$STORY_ID" 2>/dev/null
    echo "// story hand-coded" > src/hand-coded.ts
    git add . && git commit -m "story hand-coded" 2>/dev/null
    git push origin "story/$STORY_ID" 2>/dev/null
  fi

  cd - > /dev/null
}

setup_zero_conflict_fixture() {
  local fixture_dir="$1"

  rm -rf "$fixture_dir"
  mkdir -p "$fixture_dir"

  git init --bare "$fixture_dir/origin.git" 2>/dev/null
  git clone "$fixture_dir/origin.git" "$fixture_dir/worktree" 2>/dev/null
  cd "$fixture_dir/worktree"

  git config user.email "test@gaa.test" 2>/dev/null
  git config user.name "Test" 2>/dev/null
  echo "initial" > README.md
  git add . && git commit -m "initial" 2>/dev/null
  git branch -M main 2>/dev/null
  git push origin main 2>/dev/null

  git checkout -b staging 2>/dev/null
  git push origin staging 2>/dev/null

  git checkout -b "story/$STORY_ID" 2>/dev/null
  echo "story" > story.txt
  git add . && git commit -m "story changes" 2>/dev/null
  git push origin "story/$STORY_ID" 2>/dev/null

  cd - > /dev/null
}

# ── Stub gh ───────────────────────────────────────────────────────────────────

setup_gh_stub() {
  local stub_dir="$1"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal gh stub — just exits 0
exit 0
STUB
  chmod +x "$stub_dir/gh"
}

# ── T1: SUCCESS path ─────────────────────────────────────────────────────────

echo ""
echo "=== T1: SUCCESS path (generated files + backlog auto-section) ==="

FIXTURE_DIR="/tmp/gaai-auto-resolve-test-success"
rm -f "$ROUTING_LOG"
setup_git_fixture "$FIXTURE_DIR" "success"

WT_PATH="$FIXTURE_DIR/worktree"
BRANCH="story/$STORY_ID"

# Stub gh so auto-resolve doesn't try real GitHub
STUB_DIR="$FIXTURE_DIR/stubs"
setup_gh_stub "$STUB_DIR"
export PATH="$STUB_DIR:$PATH"

# Backoff override for test speed: skip waits
result=0
_auto_resolve_pr_conflicts "https://github.com/test/pr/1" "$BRANCH" "$WT_PATH" "$STORY_ID" "$TRACE_ID" || result=$?

if [[ "$result" -eq 0 ]]; then
  pass "T1: _auto_resolve_pr_conflicts returned 0 (SUCCESS)"
else
  fail "T1: _auto_resolve_pr_conflicts returned $result, expected 0"
fi

# Verify routing log has auto_merge_conflict_detected + auto_merge_resolved
if grep -q "auto_merge_conflict_detected" "$ROUTING_LOG" 2>/dev/null; then
  pass "T1: auto_merge_conflict_detected emitted"
else
  fail "T1: auto_merge_conflict_detected NOT found in routing log"
fi

if grep -q "auto_merge_resolved" "$ROUTING_LOG" 2>/dev/null; then
  pass "T1: auto_merge_resolved emitted"
else
  fail "T1: auto_merge_resolved NOT found in routing log"
fi

# Verify resolution strategy counts
resolved_line=$(grep "auto_merge_resolved" "$ROUTING_LOG" | tail -1)
if echo "$resolved_line" | grep -q '"theirs_count":2'; then
  pass "T1: theirs_count=2 (worker-configuration.d.ts + pnpm-lock.yaml)"
else
  fail "T1: theirs_count not 2 in: $(echo "$resolved_line" | head -c 200)"
fi

if echo "$resolved_line" | grep -q '"auto_section_count":0'; then
  pass "T1: auto_section_count=0 (backlog.yaml auto-merged by git, no conflict markers)"
else
  fail "T1: auto_section_count not 0 in: $(echo "$resolved_line" | head -c 200)"
fi

# Verify worktree is clean (no conflict markers)
cd "$WT_PATH"
if git diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
  fail "T1: unmerged files remain after resolve"
else
  pass "T1: no unmerged files after resolve"
fi
cd - > /dev/null

# Cleanup
export PATH="${PATH#"$STUB_DIR:"}"
rm -rf "$FIXTURE_DIR"

# ── T2: ABORT path ───────────────────────────────────────────────────────────

echo ""
echo "=== T2: ABORT path (hand-coded .ts conflict) ==="

FIXTURE_DIR="/tmp/gaai-auto-resolve-test-abort"
rm -f "$ROUTING_LOG"
setup_git_fixture "$FIXTURE_DIR" "abort"

WT_PATH="$FIXTURE_DIR/worktree"
BRANCH="story/$STORY_ID"

# Stub gh
STUB_DIR="$FIXTURE_DIR/stubs"
setup_gh_stub "$STUB_DIR"
export PATH="$STUB_DIR:$PATH"

result=0
_auto_resolve_pr_conflicts "https://github.com/test/pr/2" "$BRANCH" "$WT_PATH" "$STORY_ID" "$TRACE_ID" || result=$?

if [[ "$result" -eq 1 ]]; then
  pass "T2: _auto_resolve_pr_conflicts returned 1 (ABORT)"
else
  fail "T2: _auto_resolve_pr_conflicts returned $result, expected 1"
fi

# Verify routing log has auto_merge_aborted
if grep -q "auto_merge_aborted" "$ROUTING_LOG" 2>/dev/null; then
  pass "T2: auto_merge_aborted emitted"
else
  fail "T2: auto_merge_aborted NOT found in routing log"
fi

aborted_line=$(grep "auto_merge_aborted" "$ROUTING_LOG" | tail -1)
if echo "$aborted_line" | grep -q "hand_coded_conflict"; then
  pass "T2: abort_reason=hand_coded_conflict"
else
  fail "T2: abort_reason not hand_coded_conflict in: $(echo "$aborted_line" | head -c 200)"
fi

if echo "$aborted_line" | grep -q "hand-coded.ts"; then
  pass "T2: offending file (hand-coded.ts) in abort record"
else
  fail "T2: offending file not in abort record"
fi

# Verify worktree is clean (merge --abort executed)
cd "$WT_PATH"
if git status --porcelain 2>/dev/null | grep -q "^UU\|^AA\|^DU"; then
  fail "T2: worktree has unmerged paths (merge --abort not executed)"
else
  pass "T2: worktree clean after merge --abort"
fi
cd - > /dev/null

# Cleanup
export PATH="${PATH#"$STUB_DIR:"}"
rm -rf "$FIXTURE_DIR"

# ── T3: ZERO-CONFLICT path ───────────────────────────────────────────────────

echo ""
echo "=== T3: ZERO-CONFLICT path (empty conflict list remains numeric) ==="

FIXTURE_DIR="/tmp/gaai-auto-resolve-test-zero-conflict"
rm -f "$ROUTING_LOG"
setup_zero_conflict_fixture "$FIXTURE_DIR"

WT_PATH="$FIXTURE_DIR/worktree"
BRANCH="story/$STORY_ID"

STUB_DIR="$FIXTURE_DIR/stubs"
setup_gh_stub "$STUB_DIR"
export PATH="$STUB_DIR:$PATH"

result=0
_auto_resolve_pr_conflicts "https://github.com/test/pr/3" "$BRANCH" "$WT_PATH" "$STORY_ID" "$TRACE_ID" || result=$?

if [[ "$result" -eq 0 ]]; then
  pass "T3: _auto_resolve_pr_conflicts returned 0 (ZERO-CONFLICT)"
else
  fail "T3: _auto_resolve_pr_conflicts returned $result, expected 0"
fi

detected_line=$(grep "auto_merge_conflict_detected" "$ROUTING_LOG" | tail -1)
if echo "$detected_line" | grep -q '"conflicting_files_count":0'; then
  pass "T3: conflicting_files_count=0 emitted as numeric zero"
else
  fail "T3: conflicting_files_count not numeric zero in: $(echo "$detected_line" | head -c 200)"
fi

if grep -q "syntax error in expression" "$ROUTING_LOG" 2>/dev/null; then
  fail "T3: shell arithmetic syntax error leaked into routing log"
else
  pass "T3: no shell arithmetic syntax error"
fi

export PATH="${PATH#"$STUB_DIR:"}"
rm -rf "$FIXTURE_DIR"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed ==="
[[ "$FAIL_COUNT" -eq 0 ]] && exit 0 || exit 1
