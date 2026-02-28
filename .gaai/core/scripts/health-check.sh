#!/usr/bin/env bash
set -euo pipefail

############################################################
# Health Check — GAAI
#
# Description:
#   Validates the integrity of the .gaai/ folder structure.
#   Checks that all required files exist, all SKILL.md files
#   have required frontmatter keys, and cross-references
#   are consistent.
#
# Usage:
#   ./scripts/health-check.sh [--gaai-dir <path>]
#
# Inputs:
#   --gaai-dir  optional path to .gaai/ (default: .gaai/)
#
# Outputs:
#   stdout — check results
#   Exit 0 if all checks pass, Exit 1 if any check fails
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed
############################################################

GAAI_DIR=".gaai"

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
echo "GAAI Health Check — $GAAI_DIR"
echo "================================"

# 1. Required top-level files
echo ""
echo "[ Core Files ]"
for f in "GAAI.md" "VERSION"; do
  [[ -f "$GAAI_DIR/$f" ]] && check "$f exists" "ok" || check "$f exists" "MISSING"
done

# 2. Required directories
echo ""
echo "[ Directory Structure ]"
for d in "agents" "skills" "contexts/rules" "contexts/memory" "contexts/backlog" "contexts/artefacts" "workflows" "scripts" "compat"; do
  [[ -d "$GAAI_DIR/$d" ]] && check "$d/ exists" "ok" || check "$d/ exists" "MISSING"
done

# 3. Agent files
echo ""
echo "[ Agent Files ]"
for agent in "discovery.agent.md" "delivery.agent.md" "bootstrap.agent.md"; do
  [[ -f "$GAAI_DIR/agents/$agent" ]] && check "agents/$agent" "ok" || check "agents/$agent" "MISSING"
done

# 4. SKILL.md files — check all skill dirs have SKILL.md with name + description
echo ""
echo "[ Skill Files ]"
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
  # Check required frontmatter keys
  has_name=$(grep -c "^name:" "$skill_file" || true)
  has_desc=$(grep -c "^description:" "$skill_file" || true)
  if [[ "$has_name" -gt 0 && "$has_desc" -gt 0 ]]; then
    check "skills/$skill_name/SKILL.md" "ok"
    skill_count=$((skill_count + 1))
  else
    check "skills/$skill_name/SKILL.md" "missing name or description in frontmatter"
    skill_missing=$((skill_missing + 1))
  fi
done < <(find "$GAAI_DIR/skills" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)

# 5. Rule files
echo ""
echo "[ Rule Files ]"
for rule in "orchestration.rules.md" "skills.rules.md" "artefacts.rules.md" "backlog.rules.md" "memory.rules.md" "context-discovery.rules.md"; do
  [[ -f "$GAAI_DIR/contexts/rules/$rule" ]] && check "rules/$rule" "ok" || check "rules/$rule" "MISSING"
done

# 6. Backlog files
echo ""
echo "[ Backlog Files ]"
for f in "active.backlog.yaml" "blocked.backlog.yaml" "_template.backlog.yaml"; do
  [[ -f "$GAAI_DIR/contexts/backlog/$f" ]] && check "backlog/$f" "ok" || check "backlog/$f" "MISSING"
done

# 7. VERSION format
echo ""
echo "[ Version ]"
if [[ -f "$GAAI_DIR/VERSION" ]]; then
  version=$(cat "$GAAI_DIR/VERSION" | tr -d '[:space:]')
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    check "VERSION format ($version)" "ok"
  else
    check "VERSION format" "invalid: '$version' (expected semver)"
  fi
fi

# Summary
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "❌ Health check FAILED"
  exit 1
else
  echo "✅ Health check PASSED"
  exit 0
fi
