#!/usr/bin/env bash
set -euo pipefail

############################################################
# GAAI Skill Linter — validates SKILL.md files against R8-R12
#
# Description:
#   Checks SKILL.md files for skills-design.rules.md violations:
#   - R8: No hardcoded project memory paths in inputs (except index.md)
#   - R10: Memory must be resolved via index.md, not assumed paths
#   - R12: Inputs frontmatter must reflect runtime resolution
#
# Usage:
#   .gaai/core/scripts/skill-lint.sh                    # lint all SKILL.md
#   .gaai/core/scripts/skill-lint.sh path/to/SKILL.md   # lint specific file
#   .gaai/core/scripts/skill-lint.sh --changed           # lint git-changed only
#
# Exit codes:
#   0 — all checks pass
#   1 — violations found
#   2 — usage error
############################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GAAI_DIR="$PROJECT_DIR/.gaai"

# Colors
if [[ -t 1 ]]; then
  RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'; BOLD='\033[1m'
else
  RED=''; YELLOW=''; GREEN=''; NC=''; BOLD=''
fi

# ── Collect files to lint ────────────────────────────────────
FILES=()

if [[ "${1:-}" == "--changed" ]]; then
  # Only lint SKILL.md files changed in the last commit
  while IFS= read -r f; do
    [[ -f "$PROJECT_DIR/$f" ]] && FILES+=("$PROJECT_DIR/$f")
  done < <(git -C "$PROJECT_DIR" diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | grep 'SKILL\.md$' || true)
elif [[ -n "${1:-}" ]]; then
  # Lint specific file
  [[ -f "$1" ]] || { echo "File not found: $1" >&2; exit 2; }
  FILES+=("$1")
else
  # Lint all SKILL.md files
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$GAAI_DIR" -name "SKILL.md" -type f 2>/dev/null | sort)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No SKILL.md files to lint."
  exit 0
fi

# ── R8 violation patterns ────────────────────────────────────
# Hardcoded project memory paths in inputs/frontmatter
# Allowed: contexts/memory/index.md, contexts/memory/** (wildcard)
# Forbidden: contexts/memory/project/, contexts/memory/decisions/, etc.
R8_PATTERNS=(
  'contexts/memory/project/'
  'contexts/memory/decisions/'
  'contexts/memory/patterns/'
  'contexts/memory/domains/'
  'contexts/memory/contacts/'
  'contexts/memory/stack/'
  'contexts/memory/ops/'
  'contexts/memory/summaries/'
  'contexts/memory/sessions/'
  'contexts/memory/archive/'
)

# ── Lint ─────────────────────────────────────────────────────
violations=0
files_checked=0
files_with_issues=0

for file in "${FILES[@]}"; do
  file_issues=0
  rel_path="${file#"$PROJECT_DIR"/}"
  ((files_checked++))

  # Extract frontmatter inputs section (between --- markers)
  frontmatter=$(awk 'BEGIN{s=0} NR==1 && /^---$/{s=1; next} s==1 && /^---$/{exit} s==1{print}' "$file")
  inputs_section=$(echo "$frontmatter" | awk '/^inputs:/,/^[a-z]/' | head -20)

  # R8: Check for hardcoded memory paths in inputs frontmatter
  for pattern in "${R8_PATTERNS[@]}"; do
    if echo "$inputs_section" | grep -qF "$pattern"; then
      echo -e "${RED}R8${NC} $rel_path: hardcoded memory path in inputs: ${BOLD}$pattern${NC}"
      echo "     Fix: use 'contexts/memory/index.md' (registry) + 'contexts/memory/**' (resolved at runtime)"
      ((violations++))
      ((file_issues++))
    fi
  done

  # R8: Also check for specific DEC file references in inputs
  if echo "$inputs_section" | grep -qE 'contexts/memory/decisions/DEC-[0-9]+'; then
    echo -e "${RED}R8${NC} $rel_path: hardcoded decision file in inputs"
    echo "     Fix: resolve decisions via index.md Decision Registry, not by direct path"
    ((violations++))
    ((file_issues++))
  fi

  # R12: If inputs reference specific memory paths (not index.md or **), flag
  if echo "$inputs_section" | grep -qF 'contexts/memory/' && \
     ! echo "$inputs_section" | grep -qF 'index.md' && \
     ! echo "$inputs_section" | grep -qF '**'; then
    echo -e "${YELLOW}R12${NC} $rel_path: inputs reference memory paths but do not include index.md"
    echo "     Fix: add 'contexts/memory/index.md' as first input, use '**' for runtime resolution"
    ((violations++))
    ((file_issues++))
  fi

  if (( file_issues > 0 )); then
    ((files_with_issues++))
  fi
done

# ── Report ───────────────────────────────────────────────────
echo ""
if (( violations == 0 )); then
  echo -e "${GREEN}skill-lint: ${files_checked} files checked, 0 violations${NC}"
  exit 0
else
  echo -e "${RED}skill-lint: ${files_checked} files checked, ${violations} violation(s) in ${files_with_issues} file(s)${NC}"
  echo ""
  echo "Reference: .gaai/core/contexts/rules/skills-design.rules.md (R8-R12)"
  exit 1
fi
