#!/bin/bash
# Update skills-index.yaml when any SKILL.md is modified

if git diff-tree --no-commit-id --name-only -r HEAD | grep -q 'SKILL.md'; then
    echo "📝 Detected SKILL.md changes, checking skills index..."

    if node .gaai/core/scripts/check-and-update-skills-index.js; then
        if [ -f .gaai/core/skills/skills-index.yaml ]; then
            echo "✅ Index updated, adding to git..."
            git add .gaai/core/skills/skills-index.yaml
            git commit --amend --no-edit -q
            echo "   (amended previous commit with updated index)"
        fi
    fi
fi
