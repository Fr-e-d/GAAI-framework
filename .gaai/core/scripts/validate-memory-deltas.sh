#!/usr/bin/env bash
# validate-memory-deltas.sh
#
# Purpose:
#   Enforces the canonical memory-delta schema defined in:
#   .gaai/core/skills/cross/memory-alignment-check/SKILL.md
#
# Usage (run from repo root):
#   .gaai/core/scripts/validate-memory-deltas.sh
#
# Exit codes:
#   0 — all files PASS (or no memory-deltas directory found)
#   1 — one or more files FAIL schema validation
#   2 — script-internal error (permissions, unexpected state)
#
# Example FAIL output:
#   FAIL: contexts/artefacts/memory-deltas/E43S03.memory-delta.md — missing required section header
#         (expected one of: ## Confirmed Entries, ## Contradicted Entries, ## New Knowledge Candidates)
#   Total: 3 files checked, 1 failure.
#
set -uo pipefail
# NOTE: Do NOT use set -e — arithmetic expressions like ((failures++)) return exit 1
# when the result is 0 (i.e. when incrementing from 0 to 1), which would abort under set -e.

trap 'echo "Script-internal error on line $LINENO. Exiting with code 2." >&2; exit 2' ERR

# Canonical section headers — update this list if schema changes
CANONICAL_SECTIONS=(
  "## Confirmed Entries"
  "## Contradicted Entries"
  "## New Knowledge Candidates"
)

# One-time grandfather of pre-canonical-schema memory-delta files (audit finding F24, E164S29).
# Context: 21 legacy deltas use heterogeneous non-canonical section headers with no single
# rename rule; normalizing them would risk distorting historical artefacts.
# Policy: this list MUST NOT grow — new deltas MUST conform to canonical section headers.
# Entries MAY be removed as the corresponding delta is triaged/normalized and moved to
# processed/ (which this validator already excludes from checks).
LEGACY_GRANDFATHERED=(
  "E100S16"  "E163S08a" "E163S08c" "E163S23"  "E163S25"
  "E171S01"  "E171S07"  "E171S08"  "E173S01"  "E173S04"
  "E174S03"  "E174S07"  "E174S09"  "E175S01"  "E175S03"
  "E176S03"  "E176S04"  "E176S06"  "E176S07"  "E176S08"
  "E47S12"
)

# Resolve repo root from script location (script lives at .gaai/core/scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DELTA_DIR="$REPO_ROOT/.gaai/project/contexts/artefacts/memory-deltas"

# Allow override for testing edge cases (e.g. DELTA_DIR_OVERRIDE=/tmp/nonexistent)
if [[ -n "${DELTA_DIR_OVERRIDE:-}" ]]; then
  DELTA_DIR="$DELTA_DIR_OVERRIDE"
fi

if [[ ! -d "$DELTA_DIR" ]]; then
  echo "Advisory: no memory-deltas directory found at $DELTA_DIR, nothing to validate."
  exit 0
fi

failures=0
total=0

# Advisory: log symlinks and non-regular files (AC3d)
while IFS= read -r f; do
  echo "Advisory: skipping non-regular file: $(basename "$f")"
done < <(find "$DELTA_DIR" -maxdepth 1 -name "*.md" ! -type f 2>/dev/null | sort)

# Collect regular .md files at maxdepth 1 only (processed/ excluded)
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find "$DELTA_DIR" -maxdepth 1 -type f -name "*.md" 2>/dev/null | sort)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "Total: 0 files checked, 0 failures. All memory-deltas conform to canonical schema."
  exit 0
fi

for f in "${files[@]}"; do
  rel_path="${f#"$REPO_ROOT/"}"
  ((total++)) || true

  # AC3b — empty file
  if [[ ! -s "$f" ]]; then
    echo "FAIL: $rel_path — empty file"
    ((failures++)) || true
    continue
  fi

  # AC3c — missing YAML frontmatter (must start with ---)
  first_line=$(head -1 "$f")
  if [[ "$first_line" != "---" ]]; then
    echo "FAIL: $rel_path — missing YAML frontmatter"
    ((failures++)) || true
    continue
  fi

  # AC1a — frontmatter must contain artefact_type: memory-delta
  # Extract only between first --- and second --- (awk skips line 1, stops at next ---)
  fm_block=$(awk 'NR==1{next} /^---/{exit} {print}' "$f")
  if ! echo "$fm_block" | grep -q "^artefact_type: memory-delta"; then
    echo "FAIL: $rel_path — frontmatter missing 'artefact_type: memory-delta'"
    ((failures++)) || true
    continue
  fi

  # Determine if this file is in the grandfather allowlist
  file_basename="$(basename "$f" .memory-delta.md)"
  is_grandfathered=false
  for legacy in "${LEGACY_GRANDFATHERED[@]}"; do
    if [[ "$file_basename" == "$legacy" ]]; then
      is_grandfathered=true
      break
    fi
  done

  # AC1b — body must contain at least one canonical section header
  # Skipped for grandfathered legacy files (canonical-section check only — other checks above still apply)
  if [[ "$is_grandfathered" == false ]]; then
    section_found=false
    for section in "${CANONICAL_SECTIONS[@]}"; do
      if grep -qF "$section" "$f"; then
        section_found=true
        break
      fi
    done

    if [[ "$section_found" == false ]]; then
      echo "FAIL: $rel_path — missing required section header (expected one of: ${CANONICAL_SECTIONS[*]})"
      ((failures++)) || true
    fi
  fi
done

# Advisory: grandfathered file no longer on disk — the allowlist entry can be pruned
for legacy in "${LEGACY_GRANDFATHERED[@]}"; do
  if [[ ! -f "$DELTA_DIR/${legacy}.memory-delta.md" ]]; then
    echo "Advisory: grandfathered file no longer exists: ${legacy}.memory-delta.md — safe to remove from LEGACY_GRANDFATHERED"
  fi
done

if [[ $failures -eq 0 ]]; then
  echo "Total: $total files checked, 0 failures. All memory-deltas conform to canonical schema."
  exit 0
else
  echo ""
  echo "Total: $total files checked, $failures failure(s)."
  exit 1
fi
