#!/bin/bash
# Check for memory index drift when files under contexts/memory/ are modified.
# Considers all index*.md files at the root of contexts/memory/ as registries
# (active index.md + any sibling index files like index-decisions.md when
# Decision Registry or other heavy sections are extracted per file-size budget).

if git diff-tree --no-commit-id --name-only -r HEAD | grep -q 'contexts/memory/.*\.md$'; then
    echo "🧠 Detected memory file changes, checking index drift..."

    ROOT="$(git rev-parse --show-toplevel)"
    MEMORY_DIR="$ROOT/.gaai/project/contexts/memory"

    # Collect all registry files at memory root (index.md + index-*.md siblings)
    INDEX_FILES=()
    while IFS= read -r f; do
        INDEX_FILES+=("$f")
    done < <(find "$MEMORY_DIR" -maxdepth 1 -type f \( -name "index.md" -o -name "index-*.md" \) 2>/dev/null | sort)

    if [ ${#INDEX_FILES[@]} -eq 0 ]; then
        echo "⚠️  No index*.md found — skipping drift check"
        exit 0
    fi

    # Find .md files on disk (exclude index files themselves, READMEs, archives, templates, examples)
    UNREGISTERED=0
    while IFS= read -r file; do
        rel="${file#"$MEMORY_DIR"/}"
        # Skip index itself, sibling indices, READMEs, archive, sessions, templates, example files.
        # Also skip *.draft.md: drafts are tracked in the registry by their logical decision id
        # (without the .draft suffix), so the filename never matches the registry row — same
        # rationale as templates/examples (non-final artifacts tracked outside the per-file index).
        case "$rel" in
            index.md|index-*.md|README*|archive/*|sessions/*) continue ;;
            *_template*|*.example.md|*.draft.md) continue ;;
        esac
        # Check if file is referenced in ANY registry file by:
        #   1. Full relative path (e.g., decisions/DEC-1.md)
        #   2. Filename only (e.g., DEC-1.md)
        #   3. Filename without extension (e.g., DEC-1) — Decision Registry uses this format
        filename="$(basename "$rel")"
        filename_no_ext="${filename%.md}"
        FOUND=0
        for idx in "${INDEX_FILES[@]}"; do
            if grep -qF "$rel" "$idx" 2>/dev/null ||
               grep -qF "$filename" "$idx" 2>/dev/null ||
               grep -qF "$filename_no_ext" "$idx" 2>/dev/null; then
                FOUND=1
                break
            fi
        done
        if [ "$FOUND" -eq 0 ]; then
            echo "  ⚠️  Not in any registry: $rel"
            ((UNREGISTERED++))
        fi
    done < <(find "$MEMORY_DIR" -name "*.md" -type f 2>/dev/null | sort)

    if (( UNREGISTERED == 0 )); then
        echo "✅ Memory index is in sync (${#INDEX_FILES[@]} registry file(s) checked)"
    else
        echo "⚠️  ${UNREGISTERED} memory file(s) not found in any registry (run memory-index-sync to fix)"
    fi
fi
