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
        # Skip index itself, sibling indices, READMEs, archive, sessions, processed memory-deltas, templates, example files
        # (memory-deltas/processed/ = triaged transient artefacts, like sessions/; raw memory-deltas/ stay flagged = "to triage" signal)
        case "$rel" in
            index.md|index-*.md|README*|archive/*|sessions/*|memory-deltas/processed/*) continue ;;
            *_template*|*.example.md) continue ;;
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

    # ── Registry row width ────────────────────────────────────────────────────
    # An index row is a pointer: metadata + a short topic, capped at 200 characters
    # by the base rules. Substance belongs in the target file.
    #
    # This is a RATCHET, not an audit. Registries in the wild already carry rows well
    # past the cap, and enumerating every one of them on each memory commit would bury
    # the signal under warnings nobody can act on in the moment. So only rows that THIS
    # commit introduces are reported — the standing debt is left to a compaction pass
    # (memory-index-compact), while a new violation is caught while it is still one line
    # in one commit.
    CAP=200
    NEW_OVER=0

    # Characters, not bytes: a topic carrying arrows or accents is shorter than its byte
    # count, and the cap is stated in characters. Without python3 the check falls back to
    # bytes, which can only over-report — it never lets a long row through unseen.
    if command -v python3 >/dev/null 2>&1; then
        _rows_over_cap() { python3 -c '
import sys
cap = int(sys.argv[1])
for line in sys.stdin.read().splitlines():
    if len(line) > cap:
        print("%d\t%s" % (len(line), line[:72]))
' "$CAP"; }
    else
        _rows_over_cap() { awk -v cap="$CAP" 'length($0) > cap { printf "%d\t%.72s\n", length($0), $0 }'; }
    fi

    for idx in "${INDEX_FILES[@]}"; do
        rel_idx="${idx#"$ROOT"/}"
        # Added lines only (leading '+'), table rows only, minus the header separator.
        added="$(git diff-tree --no-commit-id -r -p HEAD -- "$rel_idx" 2>/dev/null \
                 | sed -n 's/^+\(|.*\)$/\1/p' \
                 | grep -Ev '^\|[-: |]+\|?[[:space:]]*$')"
        [ -z "$added" ] && continue
        while IFS=$'\t' read -r len excerpt; do
            [ -z "$len" ] && continue
            if (( NEW_OVER == 0 )); then
                echo "⚠️  Registry rows over the ${CAP}-char pointer cap were added:"
            fi
            echo "  ⚠️  ${len} chars in $(basename "$rel_idx"): ${excerpt}…"
            ((NEW_OVER++))
        done < <(printf '%s\n' "$added" | _rows_over_cap)
    done

    if (( NEW_OVER > 0 )); then
        echo "  → Trim to a metadata + ≤30-word topic pointer; the detail belongs in the target file."
    fi
fi
