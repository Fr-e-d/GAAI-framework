#!/bin/bash
# Update skills-index.yaml when any SKILL.md is modified

# Guard: prevent infinite loop (amend triggers post-commit again)
[ "$GAAI_SKILLS_INDEX_RUNNING" = "1" ] && exit 0
export GAAI_SKILLS_INDEX_RUNNING=1

if git diff-tree --no-commit-id --name-only -r HEAD | grep -q 'SKILL.md'; then
    echo "📝 Detected SKILL.md changes, checking skills index..."

    if node .gaai/core/scripts/check-and-update-skills-index.js; then
        if [ -f .gaai/core/skills/skills-index.yaml ] && ! git diff --quiet .gaai/core/skills/skills-index.yaml 2>/dev/null; then
            echo "✅ Index updated, adding to git..."
            git add .gaai/core/skills/skills-index.yaml
            git commit --amend --no-edit -q
            echo "   (amended previous commit with updated index)"
        else
            echo "✅ Skills index is already current"
        fi
    fi
fi
