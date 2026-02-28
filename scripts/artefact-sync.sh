#!/usr/bin/env bash
set -euo pipefail

############################################################
# Artefact Sync — GAAI
#
# Description:
#   Validates cross-references between backlog items and
#   artefact files. Checks that every backlog item with
#   an artefact path points to an existing file, and that
#   artefact frontmatter IDs match backlog references.
#
# Usage:
#   ./scripts/artefact-sync.sh [--gaai-dir <path>]
#
# Inputs:
#   --gaai-dir  optional path to .gaai/project/ (default: .gaai/project/)
#
# Outputs:
#   stdout — sync report
#
# Exit codes:
#   0 — all references valid
#   1 — broken references found
############################################################

GAAI_DIR=".gaai/project"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gaai-dir) GAAI_DIR="$2"; shift 2 ;;
    *) >&2 echo "Unknown option: $1"; exit 1 ;;
  esac
done

PASS=0
FAIL=0

check() {
  local desc="$1"
  local result="$2"
  if [[ "$result" == "ok" ]]; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc — $result"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "GAAI Artefact Sync Check"
echo "========================"

ACTIVE_BACKLOG="$GAAI_DIR/contexts/backlog/active.backlog.yaml"

if [[ ! -f "$ACTIVE_BACKLOG" ]]; then
  >&2 echo "Error: $ACTIVE_BACKLOG not found"
  exit 1
fi

echo ""
echo "[ Backlog → Artefact References ]"

# Extract artefact paths from backlog YAML
# Expected format: artefact: contexts/artefacts/stories/E01S01.story.md
while IFS= read -r line; do
  if [[ "$line" =~ ^[[:space:]]*artefact:[[:space:]]+(.+)$ ]]; then
    artefact_path="${BASH_REMATCH[1]}"
    artefact_path="${artefact_path// /}"  # trim whitespace
    # Skip null values
    [[ "$artefact_path" == "null" ]] && continue
    [[ -z "$artefact_path" ]] && continue

    full_path="$GAAI_DIR/$artefact_path"
    # Remove .gaai/project/ prefix if already included
    [[ "$artefact_path" == .gaai/project/* ]] && full_path="$artefact_path"
    # v1.x compat: strip .gaai/ prefix
    [[ "$artefact_path" == .gaai/* ]] && full_path="$artefact_path"

    if [[ -f "$full_path" ]]; then
      check "$artefact_path" "ok"
    else
      check "$artefact_path" "FILE NOT FOUND at $full_path"
    fi
  fi
done < "$ACTIVE_BACKLOG"

echo ""
echo "[ Artefact Frontmatter Integrity ]"

# Check artefact files have required frontmatter
for artefact_type in "epics" "stories" "plans" "prd"; do
  artefact_dir="$GAAI_DIR/contexts/artefacts/$artefact_type"
  [[ -d "$artefact_dir" ]] || continue

  while IFS= read -r artefact_file; do
    [[ "$artefact_file" == *"_template"* ]] && continue
    [[ "$artefact_file" == *".gitkeep" ]] && continue

    has_type=$(grep -c "^type: artefact" "$artefact_file" 2>/dev/null || echo 0)
    has_id=$(grep -c "^id:" "$artefact_file" 2>/dev/null || echo 0)
    name=$(basename "$artefact_file")

    if [[ "$has_type" -gt 0 && "$has_id" -gt 0 ]]; then
      check "artefacts/$artefact_type/$name" "ok"
    else
      check "artefacts/$artefact_type/$name" "missing type or id in frontmatter"
    fi
  done < <(find "$artefact_dir" -type f -name "*.md" 2>/dev/null | sort)
done

# Summary
echo ""
echo "========================"
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "❌ Artefact sync FAILED"
  exit 1
else
  echo "✅ Artefact sync PASSED"
  exit 0
fi
