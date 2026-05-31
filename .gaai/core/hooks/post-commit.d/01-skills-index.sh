#!/bin/bash
# Update skills-index.yaml (core + project) when any SKILL.md is modified

# Guard: prevent infinite loop (amend triggers post-commit again)
[ "$GAAI_SKILLS_INDEX_RUNNING" = "1" ] && exit 0
export GAAI_SKILLS_INDEX_RUNNING=1

# Guard: skip amend on story/* branches — they must not carry skills-index changes (E182S01 AC3)
_current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ "$_current_branch" == story/* ]]; then
  echo "ℹ️  skills-index: skipping amend on story branch (${_current_branch})"
  exit 0
fi

if git diff-tree --no-commit-id --name-only -r HEAD | grep -q 'SKILL.md'; then
    echo "📝 Detected SKILL.md changes, checking skills indices..."

    if node .gaai/core/scripts/check-and-update-skills-index.cjs; then
        NEED_AMEND=false
        for idx in .gaai/core/skills/skills-index.yaml .gaai/project/skills/skills-index.yaml; do
            if [ -f "$idx" ] && ! git diff --quiet "$idx" 2>/dev/null; then
                git add "$idx"
                NEED_AMEND=true
            fi
        done
        if $NEED_AMEND; then
            echo "✅ Index updated, adding to git..."
            git commit --amend --no-edit -q
            echo "   (amended previous commit with updated indices)"
        else
            echo "✅ Skills indices are already current"
        fi
    fi
fi
