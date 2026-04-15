#!/usr/bin/env bash
set -euo pipefail

############################################################
# GAAI Memory-Delta Schema Validator
#
# Purpose:
#   Enforces the canonical memory-delta schema defined in
#   .gaai/core/skills/cross/memory-alignment-check/SKILL.md.
#   Validates every *.md file under contexts/artefacts/memory-deltas/
#   (including the processed/ subfolder).
#
# Invocation:
#   bash .gaai/core/scripts/validate-memory-deltas.sh           # auto-resolve path
#   bash .gaai/core/scripts/validate-memory-deltas.sh <dir>     # explicit dir override
#
# Exit codes:
#   0 — all files pass (or no directory / no files found)
#   1 — one or more schema violations detected
#   2 — script-internal error (permissions, unexpected failure)
#
# Example FAIL output:
#   FAIL: .gaai/project/contexts/artefacts/memory-deltas/ExxSxx.memory-delta.md — missing required section header (expected one of: ## Confirmed Entries, ## Contradicted Entries, ## New Knowledge Candidates)
#   FAIL: .gaai/project/contexts/artefacts/memory-deltas/EyySyy.memory-delta.md — missing YAML frontmatter
#   Total: 42 files checked, 2 failures.
############################################################

# ── Script-internal error trap (exit code 2) ────────────────
trap 'echo "SCRIPT ERROR: unexpected failure at line $LINENO" >&2; exit 2' ERR

# ── Canonical section headers (single source of truth) ──────
CANONICAL_SECTION_HEADERS=(
  "## Confirmed Entries"
  "## Contradicted Entries"
  "## New Knowledge Candidates"
)

# ── Path resolution ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Accept optional explicit directory as first argument
MEMORY_DELTAS_DIR="${1:-$PROJECT_DIR/.gaai/project/contexts/artefacts/memory-deltas}"

# ── Missing directory: exit 0 with advisory ─────────────────
if [[ ! -d "$MEMORY_DELTAS_DIR" ]]; then
  echo "no memory-deltas directory found, nothing to validate"
  exit 0
fi

# ── Helpers ──────────────────────────────────────────────────

# Strip PROJECT_DIR prefix for display (repo-root-relative paths)
relative_path() {
  local abs="$1"
  echo "${abs#"$PROJECT_DIR/"}"
}

declare -a FAIL_MESSAGES=()

record_fail() {
  local filepath="$1"
  local reason="$2"
  local rel
  rel="$(relative_path "$filepath")"
  FAIL_MESSAGES+=("FAIL: $rel — $reason")
}

# ── Advisory: log symlinks (do not count, do not FAIL) ──────
while IFS= read -r -d '' symlink; do
  rel="$(relative_path "$symlink")"
  echo "ADVISORY: skipping symlink: $symlink"
done < <(find "$MEMORY_DELTAS_DIR" -name "*.md" -type l -print0 2>/dev/null | sort -z)

# ── Main traversal ───────────────────────────────────────────
total=0

while IFS= read -r -d '' filepath; do
  ((total++)) || true

  # ── Empty file ──────────────────────────────────────────
  if [[ ! -s "$filepath" ]]; then
    record_fail "$filepath" "empty file"
    continue
  fi

  # ── YAML frontmatter present (first line must be ---) ───
  first_line_check="$(awk 'NR==1{ if(/^---$/){ print "yes" } else { print "no" }; exit }' "$filepath")"
  if [[ "$first_line_check" != "yes" ]]; then
    record_fail "$filepath" "missing YAML frontmatter"
    continue
  fi

  # ── artefact_type: memory-delta in frontmatter ──────────
  frontmatter_content="$(awk 'NR==1{next} /^---$/{exit} {print}' "$filepath")"
  if ! echo "$frontmatter_content" | grep -q "artefact_type: memory-delta"; then
    record_fail "$filepath" "frontmatter missing 'artefact_type: memory-delta'"
    continue
  fi

  # ── At least one canonical section header in body ───────
  body="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2{print}' "$filepath")"

  found_section=0
  for header in "${CANONICAL_SECTION_HEADERS[@]}"; do
    if echo "$body" | grep -qF "$header"; then
      found_section=1
      break
    fi
  done

  if [[ "$found_section" -eq 0 ]]; then
    record_fail "$filepath" "missing required section header (expected one of: ## Confirmed Entries, ## Contradicted Entries, ## New Knowledge Candidates)"
  fi

done < <(find "$MEMORY_DELTAS_DIR" -name "*.md" -type f -print0 2>/dev/null | sort -z)

# ── Output ───────────────────────────────────────────────────
failure_count="${#FAIL_MESSAGES[@]}"

for msg in "${FAIL_MESSAGES[@]+"${FAIL_MESSAGES[@]}"}"; do
  echo "$msg"
done

if [[ "$failure_count" -eq 0 ]]; then
  echo "Total: $total files checked, 0 failures. All memory-deltas conform to canonical schema."
  exit 0
else
  echo "Total: $total files checked, $failure_count failures."
  exit 1
fi
