#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# GAAI Daemon Setup — one-command prerequisite checker + configurator
# ═══════════════════════════════════════════════════════════════════════════
#
# Description:
#   Validates that all prerequisites for the Delivery Daemon are met,
#   auto-configures idempotent settings, and runs health-check.
#
# Usage:
#   bash .gaai/core/scripts/daemon-setup.sh
#
# Exit codes:
#   0 — all checks passed, daemon is ready
#   1 — one or more prerequisites failed
# ═══════════════════════════════════════════════════════════════════════════

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }

# ── Locate project root ──────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GAAI_DIR="$(cd "$CORE_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$GAAI_DIR/.." && pwd)"

# ── Platform guard ────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin|Linux) ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "ERROR: Native Windows is not supported. Use WSL instead."
    exit 1
    ;;
esac

echo ""
echo "GAAI Daemon Setup"
echo "  project: $PROJECT_ROOT"
echo "================================"

# ── 1. Prerequisites ─────────────────────────────────────────────────────

echo ""
echo "[ Prerequisites ]"

# python3
if command -v python3 &>/dev/null; then
  pass "python3 found ($(python3 --version 2>&1 | head -1))"
else
  fail "python3 not found — install Python 3"
fi

# claude CLI
if command -v claude &>/dev/null; then
  pass "claude CLI found"
else
  fail "claude CLI not found — install from https://claude.com/claude-code"
fi

# Terminal (platform-specific — OS set in platform guard above)
if [[ "$OS" == "Darwin" ]]; then
  if [[ -d "/System/Applications/Utilities/Terminal.app" ]] || [[ -d "/Applications/Utilities/Terminal.app" ]]; then
    pass "Terminal.app available (macOS)"
  else
    fail "Terminal.app not found"
  fi
  if command -v tmux &>/dev/null; then
    pass "tmux also available (optional on macOS)"
  fi
else
  if command -v tmux &>/dev/null; then
    pass "tmux found ($(tmux -V 2>&1))"
  else
    fail "tmux not found — install with: apt install tmux (or equivalent)"
  fi
fi

# git repo
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  pass "Inside a git repository"
else
  fail "Not inside a git repository"
fi

# staging branch
if git -C "$PROJECT_ROOT" rev-parse --verify staging &>/dev/null 2>&1 || \
   git -C "$PROJECT_ROOT" rev-parse --verify origin/staging &>/dev/null 2>&1; then
  pass "staging branch exists"
else
  fail "staging branch not found (local or remote) — create with: git checkout -b staging"
fi

# delivery-daemon.sh
if [[ -f "$CORE_DIR/scripts/delivery-daemon.sh" ]]; then
  pass "delivery-daemon.sh exists"
else
  fail "delivery-daemon.sh not found in $CORE_DIR/scripts/"
fi

# backlog-scheduler.sh
if [[ -f "$CORE_DIR/scripts/backlog-scheduler.sh" ]]; then
  pass "backlog-scheduler.sh exists"
else
  fail "backlog-scheduler.sh not found in $CORE_DIR/scripts/"
fi

# ── 2. Auto-configure (idempotent) ───────────────────────────────────────

echo ""
echo "[ Configuration ]"

# Claude settings — skipDangerousModePermissionPrompt
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  if python3 -c "
import json, sys, os
with open(os.environ['CLAUDE_SETTINGS']) as f:
    d = json.load(f)
sys.exit(0 if d.get('skipDangerousModePermissionPrompt') == True else 1)
" 2>/dev/null; then
    pass "skipDangerousModePermissionPrompt already set"
  else
    # Merge into existing settings
    if CLAUDE_SETTINGS="$CLAUDE_SETTINGS" python3 -c "
import json, os
p = os.environ['CLAUDE_SETTINGS']
with open(p) as f:
    d = json.load(f)
d['skipDangerousModePermissionPrompt'] = True
with open(p, 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null; then
      pass "skipDangerousModePermissionPrompt added to existing settings"
    else
      fail "Could not update $CLAUDE_SETTINGS"
    fi
  fi
else
  echo '{ "skipDangerousModePermissionPrompt": true }' > "$CLAUDE_SETTINGS"
  pass "Created $CLAUDE_SETTINGS with skipDangerousModePermissionPrompt"
fi

# git hooksPath (if .githooks/ exists)
if [[ -d "$PROJECT_ROOT/.githooks" ]]; then
  CURRENT_HOOKS=$(git -C "$PROJECT_ROOT" config --get core.hooksPath 2>/dev/null || echo "")
  if [[ "$CURRENT_HOOKS" == ".githooks" ]]; then
    pass "git core.hooksPath already set to .githooks"
  else
    git -C "$PROJECT_ROOT" config core.hooksPath .githooks
    pass "Set git core.hooksPath to .githooks"
  fi
else
  warn "No .githooks/ directory — skipping hooksPath config"
fi

# .dev.vars from .env.example
if [[ -f "$PROJECT_ROOT/.env.example" ]] && [[ ! -f "$PROJECT_ROOT/.dev.vars" ]]; then
  cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.dev.vars"
  pass "Created .dev.vars from .env.example"
elif [[ -f "$PROJECT_ROOT/.dev.vars" ]]; then
  pass ".dev.vars already exists"
else
  warn "No .env.example found — skipping .dev.vars"
fi

# Delivery lock + log directories
BACKLOG_DIR="$GAAI_DIR/project/contexts/backlog"
LOCK_DIR="$BACKLOG_DIR/.delivery-locks"
LOG_DIR="$BACKLOG_DIR/.delivery-logs"

mkdir -p "$LOCK_DIR" && pass ".delivery-locks/ directory ready"
mkdir -p "$LOG_DIR" && pass ".delivery-logs/ directory ready"

# ── 3. Health check ──────────────────────────────────────────────────────

echo ""
echo "[ Health Check ]"

HEALTH_SCRIPT="$CORE_DIR/scripts/health-check.sh"
if [[ -f "$HEALTH_SCRIPT" ]]; then
  if bash "$HEALTH_SCRIPT" --core-dir "$CORE_DIR" --project-dir "$GAAI_DIR/project" >/dev/null 2>&1; then
    pass "health-check.sh passed"
  else
    warn "health-check.sh reported issues — run it directly for details"
  fi
else
  warn "health-check.sh not found — skipping"
fi

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed, $WARN warnings"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "❌ Setup incomplete — fix the failures above before starting the daemon."
  exit 1
else
  echo "✅ Daemon setup complete. Start with:"
  echo ""
  echo "  bash .gaai/core/scripts/daemon-start.sh"
  echo ""
  exit 0
fi
