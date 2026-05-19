#!/usr/bin/env bash
# oss-sync-marker-commit.test.sh — regression test for E160S06 self-commit block
# Usage: bash .gaai/core/scripts/tests/oss-sync-marker-commit.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

_TMPDIR="${TMPDIR:-/tmp}"; _TMPDIR="${_TMPDIR%/}"
REPO="$_TMPDIR/oss-sync-marker-test-$$"
cleanup() { rm -rf "$REPO"; }
trap cleanup EXIT

# ── Setup: init temp git repo ─────────────────────────────────────────────────
git init -q "$REPO"
git -C "$REPO" config user.email "test@gaai.test"
git -C "$REPO" config user.name "GAAI Test"
mkdir -p "$REPO/.github"
# Write fake sync log (pre-existing content to simulate append path)
echo "[2026-05-19 00:00:00] [test] SYNC_START" > "$REPO/.github/.sync-log"
echo "v2.0.0:abc123" > "$REPO/.github/.last-auto-bump"
# Stage + commit initial state
git -C "$REPO" add .github
git -C "$REPO" commit -q -m "chore: initial state"

# Simulate marker update (as the sync script would do just before the block)
PENDING_MARKER="2.1.0:def456"
echo "$PENDING_MARKER" > "$REPO/.github/.last-auto-bump"
echo "[2026-05-19 01:00:00] [test] MARKER_PERSISTED:${PENDING_MARKER}" >> "$REPO/.github/.sync-log"

# ── Mock post-commit hook for Assert 3 ───────────────────────────────────────
mkdir -p "$REPO/.git/hooks"
cat > "$REPO/.git/hooks/post-commit" << 'HOOK_EOF'
#!/bin/bash
[ -n "$GAAI_SYNC_IN_PROGRESS" ] && exit 0
touch "$(git rev-parse --show-toplevel)/.HOOK_FIRED"
HOOK_EOF
chmod +x "$REPO/.git/hooks/post-commit"

# ── Run the self-commit block (mirrors AC1 code) ──────────────────────────────
PROJECT_ROOT="$REPO"
(
    cd "$PROJECT_ROOT"
    export GAAI_SYNC_IN_PROGRESS=1
    git add .github/.last-auto-bump .github/.sync-log
    git commit -m "chore(oss-sync): bump marker + log to ${PENDING_MARKER}" --quiet 2>/dev/null || true
    # Push omitted in test (no remote); simulated as no-op
)

# ── Assert 1: git status clean ────────────────────────────────────────────────
STATUS=$(git -C "$REPO" status --porcelain .github/.last-auto-bump .github/.sync-log 2>/dev/null)
if [ -z "$STATUS" ]; then
    pass "Assert 1: git status --porcelain .github/ is empty after self-commit"
else
    fail "Assert 1: git status --porcelain returned: $STATUS"
fi

# ── Assert 2: commit message ──────────────────────────────────────────────────
LAST_MSG=$(git -C "$REPO" log -1 --pretty=%s)
if echo "$LAST_MSG" | grep -q "chore(oss-sync): bump marker"; then
    pass "Assert 2: commit message contains 'chore(oss-sync): bump marker' (got: $LAST_MSG)"
else
    fail "Assert 2: commit message mismatch (got: $LAST_MSG)"
fi

# ── Assert 3: recursion guard (GAAI_SYNC_IN_PROGRESS blocks hook re-entry) ───
if [ -f "$REPO/.HOOK_FIRED" ]; then
    fail "Assert 3: .HOOK_FIRED exists — GAAI_SYNC_IN_PROGRESS guard did NOT block hook"
else
    pass "Assert 3: .HOOK_FIRED absent — recursion guard correctly blocked hook re-entry"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
