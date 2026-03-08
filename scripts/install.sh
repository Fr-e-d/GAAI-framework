#!/usr/bin/env bash
set -euo pipefail

############################################################
# GAAI Installer
#
# Description:
#   Copies the .gaai/ framework into a target project and
#   deploys the right tool adapter (CLAUDE.md, .mdc, or
#   AGENTS.md).
#
# Usage:
#   bash .gaai/core/scripts/install.sh [--target <path>] [--tool <tool>] [--yes] [--wizard]
#
# Options:
#   --target  directory to install into (default: current dir)
#   --tool    ai-tool to configure: claude-code|cursor|windsurf|other
#             (skips interactive prompt if provided)
#   --yes     non-interactive: skip all prompts, use defaults
#   --wizard  guided interactive setup with auto-detection
#
# Exit codes:
#   0 — installed successfully
#   1 — installation failed
############################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAAI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET="."
TOOL=""
YES=false
WIZARD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --tool)   TOOL="$2";   shift 2 ;;
    --yes)    YES=true;    shift ;;
    --wizard) WIZARD=true; shift ;;
    *) >&2 echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Helpers ────────────────────────────────────────────────

info()    { echo "  → $*"; }
success() { echo "  ✅ $*"; }
warn()    { echo "  ⚠️  $*"; }
fail()    { echo "  ❌ $*"; exit 1; }

ask() {
  # ask <prompt> <varname>
  local prompt="$1"
  local __var="$2"
  local reply
  read -r -p "  $prompt " reply
  eval "$__var='$reply'"
}

# ── Tool auto-detection ────────────────────────────────────

detect_tool() {
  local dir="$1"
  if [[ -d "$dir/.claude" ]]; then
    echo "claude-code"
  elif [[ -d "$dir/.cursor" ]]; then
    echo "cursor"
  elif [[ -d "$dir/.windsurf" ]]; then
    echo "windsurf"
  else
    echo ""
  fi
}

tool_label() {
  case "$1" in
    claude-code) echo "Claude Code" ;;
    cursor)      echo "Cursor"      ;;
    windsurf)    echo "Windsurf"    ;;
    other)       echo "Other (generic AGENTS.md)" ;;
    *)           echo "Unknown"     ;;
  esac
}

# ── Wizard mode ────────────────────────────────────────────

if [[ "$WIZARD" == "true" ]]; then
  VERSION="$(cat "$GAAI_ROOT/VERSION" 2>/dev/null || echo '?')"
  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║        GAAI Setup Wizard v$VERSION           ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "  This wizard will install the GAAI framework into"
  echo "  your project and configure it for your AI tool."
  echo ""
  echo "────────────────────────────────────────────"
  echo "  Step 1 of 3 — Target directory"
  echo "────────────────────────────────────────────"
  echo ""
  echo "  Where should GAAI be installed?"
  echo "  Press Enter to use the current directory."
  echo ""
  ask "Target directory [.]:" WIZARD_TARGET
  if [[ -n "$WIZARD_TARGET" ]]; then
    TARGET="$WIZARD_TARGET"
  fi
  if [[ ! -d "$TARGET" ]]; then
    fail "Directory not found: $TARGET"
  fi
  TARGET="$(cd "$TARGET" && pwd)"
  echo ""
  echo "  → Installing into: $TARGET"

  echo ""
  echo "────────────────────────────────────────────"
  echo "  Step 2 of 3 — AI tool"
  echo "────────────────────────────────────────────"
  echo ""

  DETECTED="$(detect_tool "$TARGET")"
  if [[ -n "$DETECTED" ]]; then
    echo "  Detected: $(tool_label "$DETECTED") (based on existing config directory)"
    echo ""
    ask "Use $(tool_label "$DETECTED")? [Y/n]:" TOOL_CONFIRM
    if [[ "$TOOL_CONFIRM" =~ ^[nN]$ ]]; then
      DETECTED=""
    fi
  fi

  if [[ -z "$DETECTED" ]]; then
    echo "  Which AI tool do you use?"
    echo "    1) Claude Code"
    echo "    2) Cursor"
    echo "    3) Windsurf"
    echo "    4) Other (generic AGENTS.md)"
    echo ""
    ask "Enter number [1-4]:" TOOL_CHOICE
    case "$TOOL_CHOICE" in
      1) DETECTED="claude-code" ;;
      2) DETECTED="cursor"      ;;
      3) DETECTED="windsurf"    ;;
      4) DETECTED="other"       ;;
      *) warn "Invalid choice — defaulting to generic (AGENTS.md)"; DETECTED="other" ;;
    esac
  fi

  TOOL="$DETECTED"

  echo ""
  echo "────────────────────────────────────────────"
  echo "  Step 3 of 3 — Confirm"
  echo "────────────────────────────────────────────"
  echo ""
  echo "  Ready to install:"
  echo "    Directory : $TARGET"
  echo "    AI tool   : $(tool_label "$TOOL")"
  if [[ -d "$TARGET/.gaai" ]]; then
    echo "    Note      : .gaai/ already exists — will be overwritten"
  fi
  echo ""
  ask "Proceed? [Y/n]:" PROCEED
  if [[ "$PROCEED" =~ ^[nN]$ ]]; then
    echo ""
    echo "  Installation cancelled."
    exit 0
  fi
  YES=true  # skip individual prompts from here — wizard already confirmed
fi

# ── Pre-flight ─────────────────────────────────────────────

echo ""
echo "GAAI Installer v$(cat "$GAAI_ROOT/VERSION" 2>/dev/null || echo '?')"
echo "================================================"
echo ""

info "Running pre-flight checks..."
if ! bash "$SCRIPT_DIR/install-check.sh" --target "$TARGET"; then
  echo ""
  fail "Pre-flight check failed. Fix the issues above and re-run."
fi

echo ""

# ── Handle existing .gaai/ ────────────────────────────────

if [[ -d "$TARGET/.gaai" ]]; then
  if [[ "$YES" == "true" ]]; then
    warn ".gaai/ already exists in $TARGET — overwriting (--yes mode)"
  else
    warn ".gaai/ already exists in $TARGET"
    ask "Overwrite? This will replace all .gaai/ files. [y/N]" CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
      echo ""
      echo "Installation cancelled."
      exit 0
    fi
  fi
fi

# ── Copy .gaai/ ───────────────────────────────────────────

echo ""

if [[ -d "$TARGET/.gaai" ]]; then
  # ── Guard: never touch project/ ────────────────────────
  # Backup project/ before any changes so user data is recoverable
  if [[ -d "$TARGET/.gaai/project" ]]; then
    BACKUP_DIR="$TARGET/.gaai/.backup"
    BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
    BACKUP_PATH="$BACKUP_DIR/project-$BACKUP_TS"
    mkdir -p "$BACKUP_DIR"
    cp -r "$TARGET/.gaai/project" "$BACKUP_PATH"
    success "Backup created: .gaai/.backup/project-$BACKUP_TS"
  fi

  # Existing install: update core/ ONLY — never touch project/
  info "Updating .gaai/core/ (framework)..."
  rm -rf "$TARGET/.gaai/core"
  cp -r "$GAAI_ROOT/core" "$TARGET/.gaai/core"
  # Also update root-level .gaai/ files (VERSION, GAAI.md, etc.)
  for f in "$GAAI_ROOT"/VERSION "$GAAI_ROOT"/GAAI.md "$GAAI_ROOT"/README.md "$GAAI_ROOT"/QUICK-REFERENCE.md; do
    [[ -f "$f" ]] && cp "$f" "$TARGET/.gaai/"
  done

  # Guard: verify project/ was not altered
  if [[ -n "${BACKUP_PATH:-}" ]] && diff -rq "$TARGET/.gaai/project" "$BACKUP_PATH" >/dev/null 2>&1; then
    success ".gaai/core/ updated"
    success ".gaai/project/ preserved (verified unchanged)"
  elif [[ -n "${BACKUP_PATH:-}" ]]; then
    fail ".gaai/project/ was unexpectedly modified during update. Backup available at .gaai/.backup/project-$BACKUP_TS"
  else
    success ".gaai/core/ updated"
  fi
else
  # Fresh install: copy entire .gaai/
  info "Copying .gaai/ to $TARGET..."
  cp -r "$GAAI_ROOT" "$TARGET/.gaai"
  success ".gaai/ installed (core/ + project/)"
fi

# ── Select tool ──────────────────────────────────────────

if [[ -z "$TOOL" ]] && [[ "$YES" == "false" ]]; then
  echo ""
  echo "  Which AI tool do you use?"
  echo "    1) Claude Code"
  echo "    2) Cursor"
  echo "    3) Windsurf"
  echo "    4) Other (generic AGENTS.md)"
  echo ""
  ask "Enter number [1-4]:" TOOL_CHOICE
  case "$TOOL_CHOICE" in
    1) TOOL="claude-code" ;;
    2) TOOL="cursor"      ;;
    3) TOOL="windsurf"    ;;
    4) TOOL="other"       ;;
    *) warn "Invalid choice — defaulting to generic (AGENTS.md)"; TOOL="other" ;;
  esac
elif [[ -z "$TOOL" ]]; then
  # --yes without --tool: try auto-detection before falling back to other
  DETECTED_AUTO="$(detect_tool "$TARGET")"
  if [[ -n "$DETECTED_AUTO" ]]; then
    TOOL="$DETECTED_AUTO"
    info "Auto-detected AI tool: $(tool_label "$TOOL")"
  else
    TOOL="other"
  fi
fi

# ── Deploy adapter ───────────────────────────────────────

COMPAT_DIR="$TARGET/.gaai/core/compat"

echo ""
info "Deploying adapter for: $TOOL"

GAAI_MARKER="<!-- gaai-managed-section -->"

deploy_or_append() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [[ -f "$dest" ]]; then
    if grep -q "$GAAI_MARKER" "$dest"; then
      # Already injected — skip silently
      info "$label already contains GAAI section — skipping"
    else
      # Append to existing file
      printf '\n\n%s\n' "$GAAI_MARKER" >> "$dest"
      cat "$src" >> "$dest"
      success "$label — GAAI section appended (existing content preserved)"
    fi
  else
    cp "$src" "$dest"
    success "$label deployed to $(dirname "$dest")/"
  fi
}

case "$TOOL" in
  claude-code)
    # CLAUDE.md → project root (append if exists)
    deploy_or_append "$COMPAT_DIR/claude-code.md" "$TARGET/CLAUDE.md" "CLAUDE.md"

    # Slash commands → .claude/commands/
    mkdir -p "$TARGET/.claude/commands"
    for cmd in "$COMPAT_DIR/commands/"*.md; do
      cp "$cmd" "$TARGET/.claude/commands/"
      success ".claude/commands/$(basename "$cmd") deployed"
    done
    ;;

  cursor)
    # gaai.mdc → .cursor/rules/ (safe — scoped filename, no conflict)
    mkdir -p "$TARGET/.cursor/rules"
    cp "$COMPAT_DIR/cursor.mdc" "$TARGET/.cursor/rules/gaai.mdc"
    success ".cursor/rules/gaai.mdc deployed"
    ;;

  windsurf|other)
    # AGENTS.md → project root (append if exists)
    deploy_or_append "$COMPAT_DIR/windsurf.md" "$TARGET/AGENTS.md" "AGENTS.md"
    ;;
esac

# ── Run health check ─────────────────────────────────────

echo ""
info "Running health check..."
if bash "$TARGET/.gaai/core/scripts/health-check.sh" --core-dir "$TARGET/.gaai/core" --project-dir "$TARGET/.gaai/project"; then
  echo ""
else
  echo ""
  warn "Health check reported issues. Review the output above."
  warn "Installation is complete but may need attention."
fi

# ── Done ─────────────────────────────────────────────────

echo ""
echo "================================================"
echo "GAAI ready."
echo ""

case "$TOOL" in
  claude-code)
    echo "  Next steps:"
    echo "    1. Restart your Claude Code session — slash commands load at startup"
    echo "    2. Then run /gaai-bootstrap — scans your codebase and builds memory files"
    ;;
  cursor)
    echo "  Next steps:"
    echo "    Tell Cursor: \"Read .gaai/core/agents/bootstrap.agent.md,"
    echo "    then follow .gaai/core/workflows/context-bootstrap.workflow.md\""
    ;;
  *)
    echo "  Next steps:"
    echo "    Run the Bootstrap Agent — read .gaai/core/agents/bootstrap.agent.md"
    ;;
esac

echo ""
echo "  Documentation: .gaai/README.md"
echo ""
