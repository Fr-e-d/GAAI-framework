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
#   bash install.sh [--target <path>] [--tool <tool>] [--yes]
#
# Options:
#   --target  directory to install into (default: current dir)
#   --tool    ai-tool to configure: claude-code|cursor|windsurf|other
#             (skips interactive prompt if provided)
#   --yes     non-interactive: skip all prompts, use defaults
#
# Exit codes:
#   0 — installed successfully
#   1 — installation failed
############################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="."
TOOL=""
YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --tool)   TOOL="$2";   shift 2 ;;
    --yes)    YES=true;    shift ;;
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

# ── Pre-flight ─────────────────────────────────────────────

echo ""
echo "GAAI Installer v$(cat "$SCRIPT_DIR/.gaai/VERSION" 2>/dev/null || echo '?')"
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
info "Copying .gaai/ to $TARGET..."
cp -r "$SCRIPT_DIR/.gaai" "$TARGET/"
success ".gaai/ installed"

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
  TOOL="other"
fi

# ── Deploy adapter ───────────────────────────────────────

COMPAT_DIR="$TARGET/.gaai/compat"

echo ""
info "Deploying adapter for: $TOOL"

case "$TOOL" in
  claude-code)
    # CLAUDE.md → project root
    cp "$COMPAT_DIR/claude-code.md" "$TARGET/CLAUDE.md"
    success "CLAUDE.md deployed to $TARGET/"

    # Slash commands → .claude/commands/
    mkdir -p "$TARGET/.claude/commands"
    for cmd in "$COMPAT_DIR/commands/"*.md; do
      cp "$cmd" "$TARGET/.claude/commands/"
      success ".claude/commands/$(basename "$cmd") deployed"
    done
    ;;

  cursor)
    # gaai.mdc → .cursor/rules/
    mkdir -p "$TARGET/.cursor/rules"
    cp "$COMPAT_DIR/cursor.mdc" "$TARGET/.cursor/rules/gaai.mdc"
    success ".cursor/rules/gaai.mdc deployed"
    ;;

  windsurf|other)
    # AGENTS.md → project root
    cp "$COMPAT_DIR/windsurf.md" "$TARGET/AGENTS.md"
    success "AGENTS.md deployed to $TARGET/"
    ;;
esac

# ── Run health check ─────────────────────────────────────

echo ""
info "Running health check..."
if bash "$TARGET/.gaai/scripts/health-check.sh" --gaai-dir "$TARGET/.gaai"; then
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
    echo "    Existing project? → /gaai-bootstrap"
    echo "    New project?      → fill in .gaai/contexts/memory/memory/project/context.md"
    echo "                        then /gaai-discover"
    ;;
  cursor)
    echo "  Next steps:"
    echo "    Existing project? → tell Cursor: \"Read .gaai/agents/bootstrap.agent.md,"
    echo "                        then follow .gaai/workflows/context-bootstrap.workflow.md\""
    echo "    New project?      → fill in .gaai/contexts/memory/memory/project/context.md"
    echo "                        then tell Cursor: \"Read .gaai/agents/discovery.agent.md...\""
    ;;
  *)
    echo "  Next steps:"
    echo "    Read .gaai/GAAI.md to get started."
    ;;
esac

echo ""
echo "  Documentation: docs/README.md"
echo ""
