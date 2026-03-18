#!/usr/bin/env bash
# ── GAAI Pre-Push Guard ───────────────────────────────────────────────
# Blocks all pushes to protected branches (production, main).
# AI agents must work exclusively on staging. Promotion to protected
# branches is a human action via GitHub PR.
# ─────────────────────────────────────────────────────────────────────

PROTECTED_BRANCHES="production|main"

while read local_ref local_sha remote_ref remote_sha; do
  branch="${remote_ref#refs/heads/}"
  if [[ "$branch" =~ ^($PROTECTED_BRANCHES)$ ]]; then
    echo ""
    echo "BLOCKED: Push to '$branch' is not allowed from this environment."
    echo "Use GitHub PR to promote staging → $branch."
    echo ""
    exit 1
  fi
done

exit 0
