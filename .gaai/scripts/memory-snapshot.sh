#!/usr/bin/env bash
set -euo pipefail

############################################################
# Memory Snapshot — GAAI
#
# Description:
#   Exports the current memory state to a timestamped
#   archive directory. Creates a point-in-time snapshot
#   of all active memory files for backup or audit.
#
# Usage:
#   ./scripts/memory-snapshot.sh [--gaai-dir <path>] [--output-dir <path>]
#
# Inputs:
#   --gaai-dir    optional path to .gaai/ (default: .gaai/)
#   --output-dir  optional output directory (default: .gaai/contexts/memory/archive/snapshots/)
#
# Outputs:
#   A timestamped directory containing all active memory files.
#   stdout — snapshot path
#
# Exit codes:
#   0 — snapshot created
#   1 — error
############################################################

GAAI_DIR=".gaai"
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gaai-dir) GAAI_DIR="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    *) >&2 echo "Unknown option: $1"; exit 1 ;;
  esac
done

MEMORY_DIR="$GAAI_DIR/contexts/memory"

if [[ ! -d "$MEMORY_DIR" ]]; then
  >&2 echo "Error: memory directory '$MEMORY_DIR' not found"
  exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="$MEMORY_DIR/archive/snapshots"
SNAPSHOT_DIR="$OUTPUT_DIR/$TIMESTAMP"

mkdir -p "$SNAPSHOT_DIR"

# Copy all active memory files (exclude archive/)
file_count=0
while IFS= read -r f; do
  # Skip archive subdirectory files
  [[ "$f" == *"/archive/"* ]] && continue
  dest="$SNAPSHOT_DIR/$(basename "$f")"
  cp "$f" "$dest"
  file_count=$((file_count + 1))
done < <(find "$MEMORY_DIR" -maxdepth 1 -type f -name "*.md" -o -name "*.yaml" 2>/dev/null | sort)

# Also include memory index if exists
[[ -f "$MEMORY_DIR/index.md" ]] && cp "$MEMORY_DIR/index.md" "$SNAPSHOT_DIR/index.md" 2>/dev/null || true

echo "Memory snapshot created: $SNAPSHOT_DIR"
echo "Files archived: $file_count"
exit 0
