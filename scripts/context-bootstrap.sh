#!/usr/bin/env bash
set -euo pipefail

############################################################
# Context Bootstrap Summary — GAAI
#
# Description:
#   Prints a formatted summary of the current project context
#   from memory files. Used to verify bootstrap state and
#   provide a quick orientation at session start.
#
# Usage:
#   ./scripts/context-bootstrap.sh [--gaai-dir <path>]
#
# Inputs:
#   --gaai-dir  optional path to .gaai/project/ (default: .gaai/project/)
#
# Outputs:
#   stdout — formatted context summary
#
# Exit codes:
#   0 — success
#   1 — .gaai/project/ not found or missing required files
############################################################

GAAI_DIR=".gaai/project"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gaai-dir) GAAI_DIR="$2"; shift 2 ;;
    *) >&2 echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ ! -d "$GAAI_DIR" ]]; then
  >&2 echo "Error: $GAAI_DIR not found. Run from project root."
  exit 1
fi

VERSION="unknown"
# VERSION lives in core/, not project/
CORE_DIR="${GAAI_DIR%/project}/core"
[[ -f "$CORE_DIR/VERSION" ]] && VERSION=$(cat "$CORE_DIR/VERSION" | tr -d '[:space:]')

echo ""
echo "╔══════════════════════════════════════╗"
echo "║      GAAI Context Summary v$VERSION      ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Project memory
PROJECT_MEMORY="$GAAI_DIR/contexts/memory/project.memory.md"
if [[ -f "$PROJECT_MEMORY" ]]; then
  echo "── Project Memory ──────────────────────"
  # Print non-frontmatter content (after second ---)
  awk '/^---/{n++; if(n==2){found=1; next}} found{print}' "$PROJECT_MEMORY" | head -30
  echo ""
else
  echo "⚠  project.memory.md not found — bootstrap not complete"
  echo ""
fi

# Active backlog count
ACTIVE_BACKLOG="$GAAI_DIR/contexts/backlog/active.backlog.yaml"
if [[ -f "$ACTIVE_BACKLOG" ]]; then
  total=$(grep -c "^  - id:" "$ACTIVE_BACKLOG" 2>/dev/null || echo 0)
  refined=$(grep -c "status: refined" "$ACTIVE_BACKLOG" 2>/dev/null || echo 0)
  in_progress=$(grep -c "status: in-progress" "$ACTIVE_BACKLOG" 2>/dev/null || echo 0)
  echo "── Active Backlog ──────────────────────"
  echo "  Total items : $total"
  echo "  Refined     : $refined"
  echo "  In progress : $in_progress"
  echo ""
fi

# Memory index
MEMORY_INDEX="$GAAI_DIR/contexts/memory/index.md"
if [[ -f "$MEMORY_INDEX" ]]; then
  echo "── Memory Index ────────────────────────"
  cat "$MEMORY_INDEX" | head -20
  echo ""
fi

# Decision count
DECISIONS_DIR="$GAAI_DIR/contexts/memory"
decision_count=$(find "$DECISIONS_DIR" -name "*.memory.md" 2>/dev/null | wc -l | tr -d ' ')
echo "── Memory Files ────────────────────────"
echo "  Memory files: $decision_count"
echo ""

# Skill count (skills live in core/, not project/)
skill_count=$(find "$CORE_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
echo "── Skills ──────────────────────────────"
echo "  Loaded skills: $skill_count"
echo ""

echo "Run './scripts/health-check.sh' for full integrity check."
echo ""
