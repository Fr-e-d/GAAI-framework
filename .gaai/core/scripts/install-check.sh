#!/usr/bin/env bash
set -euo pipefail

############################################################
# GAAI Pre-flight Check
#
# Description:
#   Verifies that the environment meets the requirements
#   to run the GAAI installer.
#
# Usage:
#   bash install-check.sh [--target <path>]
#
# Options:
#   --target  directory where .gaai/ will be installed
#             (default: current directory)
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more requirements not met
############################################################

TARGET="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    *) >&2 echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Derive canonical absolute path and Claude Code memory location
TARGET_ABS=$(cd "$TARGET" && pwd)
CLAUDE_SLUG=$(echo "$TARGET_ABS" | tr '/' '-')
CLAUDE_MEM_DIR="$HOME/.claude/projects/$CLAUDE_SLUG/memory"
CLAUDE_MEM_FILE="$CLAUDE_MEM_DIR/MEMORY.md"

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
echo "GAAI Pre-flight Check"
echo "====================="

# 1. Bash version
echo ""
echo "[ Shell ]"
bash_major="${BASH_VERSINFO[0]}"
if [[ "$bash_major" -ge 3 ]]; then
  check "bash ${BASH_VERSION} (3.2+ required)" "ok"
else
  check "bash version" "found ${BASH_VERSION}, need 3.2+"
fi

# 2. Git
echo ""
echo "[ Dependencies ]"
if command -v git &>/dev/null; then
  git_version=$(git --version | awk '{print $3}')
  check "git ($git_version)" "ok"
else
  check "git" "not found — install git before proceeding"
fi

# 3. Python 3 (for backlog-scheduler.sh)
if command -v python3 &>/dev/null; then
  py_version=$(python3 --version 2>&1 | awk '{print $2}')
  check "python3 ($py_version) — for backlog-scheduler.sh" "ok"
else
  check "python3 — for backlog-scheduler.sh" "not found (optional — backlog-scheduler.sh will not work)"
fi

# 4. Write access to target
echo ""
echo "[ Target Directory ]"
if [[ -d "$TARGET" ]]; then
  if touch "$TARGET/.gaai-preflight-test" 2>/dev/null; then
    rm -f "$TARGET/.gaai-preflight-test"
    check "write access to $TARGET" "ok"
  else
    check "write access to $TARGET" "no write permission"
  fi
else
  check "target directory $TARGET" "does not exist"
fi

# 5. No existing .gaai/ conflict
if [[ -d "$TARGET/.gaai" ]]; then
  echo "  ⚠️  .gaai/ in target — already exists (installer will prompt before overwriting)"
  PASS=$((PASS + 1))
else
  check ".gaai/ in target — ok (not present, clean install)" "ok"
fi

# 6. Git hooks
echo ""
echo "[ Git Hooks ]"
HOOKS_PATH=$(cd "$TARGET" && git config --get core.hooksPath 2>/dev/null || echo "")
if [[ "$HOOKS_PATH" == ".githooks" ]]; then
  check "core.hooksPath set to .githooks" "ok"
else
  check "core.hooksPath" "not set to .githooks (installer will configure this)"
fi

if [[ -d "$TARGET/.githooks" ]]; then
  for dispatcher in pre-push post-commit; do
    if [[ -x "$TARGET/.githooks/$dispatcher" ]]; then
      check ".githooks/$dispatcher dispatcher" "ok"
    else
      check ".githooks/$dispatcher dispatcher" "missing or not executable (installer will create it)"
    fi
  done
else
  check ".githooks/ directory" "not present (installer will create it)"
fi

# 7. Claude Code memory integration
echo ""
echo "[ Claude Code ]"
CLAUDE_DETECTED=false
if [[ -d "$HOME/.claude" ]] || [[ -f "$TARGET/CLAUDE.md" ]]; then
  CLAUDE_DETECTED=true
  check "Claude Code detected (~/.claude/ or CLAUDE.md found)" "ok"
else
  echo "  ⏭  Claude Code not detected — skipping memory integration"
fi

if [[ "$CLAUDE_DETECTED" == true ]]; then
  # Ensure memory directory and file exist
  mkdir -p "$CLAUDE_MEM_DIR"
  [[ -f "$CLAUDE_MEM_FILE" ]] || touch "$CLAUDE_MEM_FILE"

  # Idempotency check (AC4)
  if grep -q "GAAI-MEMORY-POINTER" "$CLAUDE_MEM_FILE"; then
    check "GAAI memory pointer already configured — skipping" "ok"
  else
    # Append pointer block (AC2, AC3)
    cat >> "$CLAUDE_MEM_FILE" << 'GAAI_POINTER'

<!-- GAAI-MEMORY-POINTER -->
## GAAI Project Memory

This project uses GAAI for governed memory management.

**Source of truth:** `.gaai/project/contexts/memory/index.md`
Read this index FIRST to know what context exists before acting.

**Rules:**
1. Project decisions, architecture, strategy, patterns → GAAI memory (`.gaai/project/contexts/memory/`)
2. This tool's native memory → ONLY for tool-specific behavioral feedback (corrections, preferences)
3. NEVER duplicate GAAI memory content here
4. When asked to "log" or "remember" something about the project → write to GAAI memory, not here
5. If you find project knowledge here that should be in GAAI memory → migrate it, then remove it from here
GAAI_POINTER
    check "GAAI memory pointer injected into $CLAUDE_MEM_FILE" "ok"
  fi

  # Scan for migration candidates (AC5)
  MIGRATE_CANDIDATES=()
  # Pattern 1: project_*.md files
  for f in "$CLAUDE_MEM_DIR"/project_*.md; do
    [[ -f "$f" ]] && MIGRATE_CANDIDATES+=("$f")
  done
  # Pattern 2: files whose first non-blank line starts with "# Project" (skip MEMORY.md)
  for f in "$CLAUDE_MEM_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
    first_line=$(grep -m1 . "$f" 2>/dev/null || true)
    if [[ "$first_line" == "# Project"* ]]; then
      already=false
      for c in "${MIGRATE_CANDIDATES[@]:-}"; do [[ "$c" == "$f" ]] && already=true; done
      [[ "$already" == false ]] && MIGRATE_CANDIDATES+=("$f")
    fi
  done
  MIGRATE_COUNT=${#MIGRATE_CANDIDATES[@]}

  # Offer migration (AC5)
  if [[ "$MIGRATE_COUNT" -gt 0 ]]; then
    echo ""
    echo "  Detected $MIGRATE_COUNT project-level file(s) in Claude Code memory."
    printf "  Migrate to GAAI memory? [y/N] "
    read -r -t 10 MIGRATE_ANSWER || true
    if [[ "${MIGRATE_ANSWER:-N}" =~ ^[Yy]$ ]]; then
      # Migration (AC6)
      GAAI_MIGRATE_DIR="$TARGET/.gaai/project/contexts/memory/migrated"
      if [[ ! -d "$TARGET/.gaai" ]]; then
        echo "  ℹ  .gaai/ not yet installed — created migration target at $GAAI_MIGRATE_DIR"
      fi
      mkdir -p "$GAAI_MIGRATE_DIR"
      for f in "${MIGRATE_CANDIDATES[@]}"; do
        cp "$f" "$GAAI_MIGRATE_DIR/$(basename "$f")"
        rm "$f"
        echo "  ✅ Migrated: $(basename "$f")"
      done
      check "Migration complete: $MIGRATE_COUNT file(s) moved to .gaai/project/contexts/memory/migrated/" "ok"
    else
      echo "  ⏭  Migration skipped."
    fi
  fi
fi

# 8. Cursor integration
echo ""
echo "[ Cursor Integration ]"
if [[ -d "$TARGET/.cursor" ]]; then
  check "Cursor detected (.cursor/ found) — memory integration will be configured by installer" "ok"
else
  echo "  ⏭  Cursor not detected (.cursor/ not found) — memory integration will be skipped"
fi

# 9. Continue integration
echo ""
echo "[ Continue Integration ]"
if [[ -d "$TARGET/.continue" ]]; then
  check "Continue detected (.continue/ found) — memory integration will be configured by installer" "ok"
else
  echo "  ⏭  Continue not detected (.continue/ not found) — memory integration will be skipped"
fi

# Summary
echo ""
echo "====================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "❌ Pre-flight check FAILED — resolve issues above before running install.sh"
  exit 1
else
  echo "✅ Pre-flight check PASSED — ready to install"
  exit 0
fi
