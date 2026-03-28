#!/bin/bash
# Check for memory index drift when files under contexts/memory/ are modified

if git diff-tree --no-commit-id --name-only -r HEAD | grep -q 'contexts/memory/.*\.md$'; then
    echo "🧠 Detected memory file changes, checking index drift..."

    ROOT="$(git rev-parse --show-toplevel)"
    MEMORY_DIR="$ROOT/.gaai/project/contexts/memory"
    INDEX_FILE="$MEMORY_DIR/index.md"

    [ -f "$INDEX_FILE" ] || { echo "⚠️  No index.md found — skipping drift check"; exit 0; }

    # Find .md files on disk (exclude index.md, READMEs, archives, templates, examples)
    UNREGISTERED=0
    while IFS= read -r file; do
        rel="${file#"$MEMORY_DIR"/}"
        # Skip index itself, READMEs, archive, sessions, templates, and example files
        case "$rel" in
            index.md|README*|archive/*|sessions/*) continue ;;
            *_template*|*.example.md) continue ;;
        esac
        # Check if the file is referenced in index.md by:
        #   1. Full relative path (e.g., decisions/DEC-1.md)
        #   2. Filename only (e.g., DEC-1.md)
        #   3. Filename without extension (e.g., DEC-1) — Decision Registry uses this format
        filename="$(basename "$rel")"
        filename_no_ext="${filename%.md}"
        if ! grep -qF "$rel" "$INDEX_FILE" 2>/dev/null &&
           ! grep -qF "$filename" "$INDEX_FILE" 2>/dev/null &&
           ! grep -qF "$filename_no_ext" "$INDEX_FILE" 2>/dev/null; then
            echo "  ⚠️  Not in index: $rel"
            ((UNREGISTERED++))
        fi
    done < <(find "$MEMORY_DIR" -name "*.md" -type f 2>/dev/null | sort)

    if (( UNREGISTERED == 0 )); then
        echo "✅ Memory index is in sync"
    else
        echo "⚠️  ${UNREGISTERED} memory file(s) not found in index.md (run memory-index-sync to fix)"
    fi
fi
