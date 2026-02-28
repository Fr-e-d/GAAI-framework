#!/usr/bin/env bash
set -euo pipefail

############################################################
# Health Check — GAAI
#
# Description:
#   Validates the integrity of the .gaai/ folder structure.
#   Supports both v2.x (core/project split) and v1.x (flat).
#   Checks that all required files exist, all SKILL.md files
#   have required frontmatter keys, and cross-references
#   are consistent.
#
# Usage:
#   ./scripts/health-check.sh [--core-dir <path>] [--project-dir <path>]
#   ./scripts/health-check.sh [--gaai-dir <path>]   # v1.x compat
#
# Inputs:
#   --core-dir     path to .gaai/core/ (default: auto-detect)
#   --project-dir  path to .gaai/project/ (default: auto-detect)
#   --gaai-dir     v1.x compat: flat .gaai/ dir (maps to both)
#
# Outputs:
#   stdout — check results
#   Exit 0 if all checks pass, Exit 1 if any check fails
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed
############################################################

CORE_DIR=""
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --core-dir)    CORE_DIR="$2";    shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --gaai-dir)    CORE_DIR="$2"; PROJECT_DIR="$2"; shift 2 ;;  # v1.x compat
    *) >&2 echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Auto-detect if not specified
if [[ -z "$CORE_DIR" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
if [[ -z "$PROJECT_DIR" ]]; then
  if [[ -d "$CORE_DIR/../project" ]]; then
    PROJECT_DIR="$CORE_DIR/../project"
  else
    PROJECT_DIR="$CORE_DIR"  # v1.x flat layout
  fi
fi

PASS=0
FAIL=0
WARN_COUNT=0

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

check_warn() {
  local desc="$1"
  local result="$2"
  if [[ "$result" == "ok" ]]; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ⚠️  $desc — $result"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

echo ""
echo "GAAI Health Check"
echo "  core:    $CORE_DIR"
echo "  project: $PROJECT_DIR"
echo "================================"

# 1. Required framework files (in core/)
echo ""
echo "[ Core Files ]"
for f in "GAAI.md" "VERSION"; do
  [[ -f "$CORE_DIR/$f" ]] && check "$f exists" "ok" || check "$f exists" "MISSING"
done

# 2. Required framework directories (in core/)
echo ""
echo "[ Framework Structure (core/) ]"
for d in "agents" "skills" "contexts/rules" "workflows" "scripts" "compat"; do
  [[ -d "$CORE_DIR/$d" ]] && check "core/$d/" "ok" || check "core/$d/" "MISSING"
done

# 3. Required project directories (in project/)
echo ""
echo "[ Project Structure (project/) ]"
for d in "contexts/memory" "contexts/backlog" "contexts/artefacts"; do
  [[ -d "$PROJECT_DIR/$d" ]] && check "project/$d/" "ok" || check "project/$d/" "MISSING"
done

# 4. Optional project extension directories (warn if absent, not fail)
echo ""
echo "[ Project Extensions (optional) ]"
for d in "agents" "skills" "contexts/rules" "workflows" "scripts"; do
  [[ -d "$PROJECT_DIR/$d" ]] && check_warn "project/$d/" "ok" || check_warn "project/$d/" "not present (optional)"
done

# 5. Agent files (in core/)
echo ""
echo "[ Agent Files ]"
for agent in "discovery.agent.md" "delivery.agent.md" "bootstrap.agent.md"; do
  [[ -f "$CORE_DIR/agents/$agent" ]] && check "agents/$agent" "ok" || check "agents/$agent" "MISSING"
done

# 6. SKILL.md files — check all skill dirs have SKILL.md with name + description
echo ""
echo "[ Skill Files (core/) ]"
skill_count=0
skill_missing=0
while IFS= read -r skill_dir; do
  skill_file="$skill_dir/SKILL.md"
  skill_name=$(basename "$skill_dir")
  if [[ ! -f "$skill_file" ]]; then
    check "skills/$skill_name/SKILL.md" "MISSING"
    skill_missing=$((skill_missing + 1))
    continue
  fi
  has_name=$(grep -c "^name:" "$skill_file" || true)
  has_desc=$(grep -c "^description:" "$skill_file" || true)
  if [[ "$has_name" -gt 0 && "$has_desc" -gt 0 ]]; then
    check "skills/$skill_name/SKILL.md" "ok"
    skill_count=$((skill_count + 1))
  else
    check "skills/$skill_name/SKILL.md" "missing name or description in frontmatter"
    skill_missing=$((skill_missing + 1))
  fi
done < <(find "$CORE_DIR/skills" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)

# 6b. SKILL.md files in project/ (optional)
if [[ -d "$PROJECT_DIR/skills" ]]; then
  echo ""
  echo "[ Skill Files (project/) ]"
  while IFS= read -r skill_dir; do
    skill_file="$skill_dir/SKILL.md"
    skill_name=$(basename "$skill_dir")
    if [[ ! -f "$skill_file" ]]; then
      check_warn "project/skills/$skill_name/SKILL.md" "MISSING"
      continue
    fi
    has_name=$(grep -c "^name:" "$skill_file" || true)
    has_desc=$(grep -c "^description:" "$skill_file" || true)
    if [[ "$has_name" -gt 0 && "$has_desc" -gt 0 ]]; then
      check "project/skills/$skill_name/SKILL.md" "ok"
      skill_count=$((skill_count + 1))
    else
      check_warn "project/skills/$skill_name/SKILL.md" "missing name or description in frontmatter"
    fi
  done < <(find "$PROJECT_DIR/skills" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)
fi

# 7. Rule files (in core/)
echo ""
echo "[ Rule Files ]"
for rule in "orchestration.rules.md" "skills.rules.md" "artefacts.rules.md" "backlog.rules.md" "memory.rules.md" "context-discovery.rules.md"; do
  [[ -f "$CORE_DIR/contexts/rules/$rule" ]] && check "rules/$rule" "ok" || check "rules/$rule" "MISSING"
done

# 8. Backlog files (in project/)
echo ""
echo "[ Backlog Files ]"
for f in "active.backlog.yaml" "blocked.backlog.yaml" "_template.backlog.yaml"; do
  [[ -f "$PROJECT_DIR/contexts/backlog/$f" ]] && check "backlog/$f" "ok" || check "backlog/$f" "MISSING"
done

# 9. VERSION format
echo ""
echo "[ Version ]"
if [[ -f "$CORE_DIR/VERSION" ]]; then
  version=$(cat "$CORE_DIR/VERSION" | tr -d '[:space:]')
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    check "VERSION format ($version)" "ok"
  else
    check "VERSION format" "invalid: '$version' (expected semver)"
  fi
fi

# Summary
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed, $WARN_COUNT warnings"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "❌ Health check FAILED"
  exit 1
else
  echo "✅ Health check PASSED"
  exit 0
fi
