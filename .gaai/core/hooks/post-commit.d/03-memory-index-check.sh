#!/bin/bash
# Check for memory index drift when files under contexts/memory/ are modified

if git diff-tree --no-commit-id --name-only -r HEAD | grep -q 'contexts/memory/.*\.md$'; then
    echo "🧠 Detected memory file changes, checking index drift..."

    ROOT="$(git rev-parse --show-toplevel)"
    MEMORY_DIR="$ROOT/.gaai/project/contexts/memory"
    INDEX_FILE="$MEMORY_DIR/index.md"

    [ -f "$INDEX_FILE" ] || { echo "⚠️  No index.md found — skipping drift check"; exit 0; }

    # Find .md files on disk (exclude index.md itself, README files, and archive/)
    UNREGISTERED=0
    while IFS= read -r file; do
        rel="${file#"$MEMORY_DIR"/}"
        # Skip index itself, READMEs, and archive
        case "$rel" in
            index.md|README*|archive/*|sessions/*) continue ;;
        esac
        # Check if the file is referenced in index.md
        basename_no_ext="${rel%.md}"
        if ! grep -qF "$rel" "$INDEX_FILE" 2>/dev/null; then
            # Also check by filename only (index sometimes uses short references)
            filename="$(basename "$rel")"
            if ! grep -qF "$filename" "$INDEX_FILE" 2>/dev/null; then
                echo "  ⚠️  Not in index: $rel"
                ((UNREGISTERED++))
            fi
        fi
    done < <(find "$MEMORY_DIR" -name "*.md" -type f 2>/dev/null | sort)

    if (( UNREGISTERED == 0 )); then
        echo "✅ Memory index is in sync"
    else
        echo "⚠️  ${UNREGISTERED} memory file(s) not found in index.md (run memory-index-sync to fix)"
    fi
fi
