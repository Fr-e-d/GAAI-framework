#!/bin/bash
# Lint SKILL.md files against R8-R12 when any SKILL.md is modified

if git diff-tree --no-commit-id --name-only -r HEAD | grep -q 'SKILL\.md$'; then
    echo "🔍 Detected SKILL.md changes, running skill-lint..."
    if bash .gaai/core/scripts/skill-lint.sh --changed; then
        echo "✅ Skill lint passed"
    else
        echo "⚠️  Skill lint found violations (non-blocking — review recommended)"
    fi
fi
