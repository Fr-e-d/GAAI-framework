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
# Environment overrides:
#   GAAI_TARGET_BRANCH=develop    override default branch (default: staging)
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

# ── Auto-detect core/project layout (v2.x split vs v1.x flat) ────────────
if [[ -d "$GAAI_DIR/project" ]]; then
  GAAI_PROJECT_DIR="$GAAI_DIR/project"
else
  GAAI_PROJECT_DIR="$GAAI_DIR/contexts"  # v1.x backwards compat
fi

# ── Configuration ─────────────────────────────────────────────────────────
TARGET_BRANCH="${GAAI_TARGET_BRANCH:-staging}"

# ── Platform guard ────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin|Linux) ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "ERROR: Native Windows is not supported. Use WSL instead:"
    echo "  wsl --install && wsl"
    echo "  cd /mnt/c/path/to/project && bash .gaai/core/scripts/daemon-setup.sh"
    exit 1
    ;;
esac

echo ""
echo "GAAI Daemon Setup"
echo "  project: $PROJECT_ROOT"
echo "  branch:  $TARGET_BRANCH"
echo "================================"

# ── 1. Prerequisites ─────────────────────────────────────────────────────

echo ""
echo "[ Prerequisites ]"

# python3
if command -v python3 &>/dev/null; then
  pass "python3 found ($(python3 --version 2>&1 | head -1))"
else
  fail "python3 not found — install Python 3 (https://www.python.org/downloads/)"
fi

# claude CLI
if command -v claude &>/dev/null; then
  pass "claude CLI found"
else
  fail "claude CLI not found — install: npm install -g @anthropic-ai/claude-code"
fi

# Terminal launcher (platform-specific)
if [[ "$OS" == "Darwin" ]]; then
  if command -v tmux &>/dev/null; then
    pass "tmux found (preferred launcher on macOS)"
  elif [[ -d "/System/Applications/Utilities/Terminal.app" ]] || [[ -d "/Applications/Utilities/Terminal.app" ]]; then
    pass "Terminal.app available (fallback launcher)"
  else
    warn "Neither tmux nor Terminal.app found — install tmux: brew install tmux"
  fi
else
  if command -v tmux &>/dev/null; then
    pass "tmux found ($(tmux -V 2>&1))"
  else
    fail "tmux not found — install: apt install tmux (or equivalent)"
  fi
fi

# git repo
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  pass "Inside a git repository"
else
  fail "Not inside a git repository — initialize: git init && git checkout -b $TARGET_BRANCH"
fi

# Target branch
if git -C "$PROJECT_ROOT" rev-parse --verify "$TARGET_BRANCH" &>/dev/null 2>&1 || \
   git -C "$PROJECT_ROOT" rev-parse --verify "origin/$TARGET_BRANCH" &>/dev/null 2>&1; then
  pass "$TARGET_BRANCH branch exists"
else
  fail "$TARGET_BRANCH branch not found — create: git checkout -b $TARGET_BRANCH (or set GAAI_TARGET_BRANCH)"
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

# git command
if command -v git &>/dev/null; then
  pass "git found ($(git --version 2>&1 | head -1))"
else
  fail "git not found — install git (https://git-scm.com/downloads)"
fi

# jq (optional — enriched monitoring)
if command -v jq &>/dev/null; then
  pass "jq found (optional — enriched monitoring)"
else
  warn "jq not found — monitor dashboard will show reduced info. Install: brew install jq (macOS) / apt install jq (Linux)"
fi

# timeout / gtimeout (optional — delivery hard timeout)
if command -v gtimeout &>/dev/null; then
  pass "gtimeout found (delivery hard timeout)"
elif command -v timeout &>/dev/null; then
  pass "timeout found (delivery hard timeout)"
else
  warn "Neither timeout nor gtimeout found — deliveries won't auto-timeout. Install: brew install coreutils (macOS) / apt install coreutils (Linux)"
fi

# ── 2. Auto-configure (idempotent) ───────────────────────────────────────

echo ""
echo "[ Configuration ]"

# Claude settings — skipDangerousModePermissionPrompt
# Required for headless daemon mode (without it, permission prompts hang forever).
# This suppresses the warning dialog when using --dangerously-skip-permissions.
# It does NOT affect normal interactive Claude Code sessions.
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
if [[ -f "$CLAUDE_SETTINGS" ]] && CLAUDE_SETTINGS="$CLAUDE_SETTINGS" python3 -c "
import json, sys, os
with open(os.environ['CLAUDE_SETTINGS']) as f:
    d = json.load(f)
sys.exit(0 if d.get('skipDangerousModePermissionPrompt') == True else 1)
" 2>/dev/null; then
  pass "skipDangerousModePermissionPrompt already set"
else
  if [[ -f "$CLAUDE_SETTINGS" ]]; then
    CLAUDE_SETTINGS="$CLAUDE_SETTINGS" python3 -c "
import json, os
p = os.environ['CLAUDE_SETTINGS']
with open(p) as f:
    d = json.load(f)
d['skipDangerousModePermissionPrompt'] = True
with open(p, 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null && pass "skipDangerousModePermissionPrompt added" || fail "Could not update $CLAUDE_SETTINGS"
  else
    echo '{ "skipDangerousModePermissionPrompt": true }' > "$CLAUDE_SETTINGS"
    pass "Created $CLAUDE_SETTINGS with skipDangerousModePermissionPrompt"
  fi
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
  warn "No .githooks/ directory — pre-push safety hook not active (push to production not blocked)"
fi

# Secrets file from template (optional — only if project uses .env.example)
if [[ -f "$PROJECT_ROOT/.env.example" ]]; then
  # Detect target: .dev.vars if project has any framework config file, .env otherwise
  if compgen -G "$PROJECT_ROOT/wrangler.*" &>/dev/null; then
    SECRETS_FILE="$PROJECT_ROOT/.dev.vars"
  else
    SECRETS_FILE="$PROJECT_ROOT/.env"
  fi
  if [[ -f "$SECRETS_FILE" ]]; then
    pass "$(basename "$SECRETS_FILE") already exists"
  else
    cp "$PROJECT_ROOT/.env.example" "$SECRETS_FILE"
    warn "Created $(basename "$SECRETS_FILE") from .env.example — review and add real secrets before running daemon"
  fi
fi

# Delivery lock + log directories
BACKLOG_DIR="$GAAI_PROJECT_DIR/contexts/backlog"
LOCK_DIR="$BACKLOG_DIR/.delivery-locks"
LOG_DIR="$BACKLOG_DIR/.delivery-logs"

mkdir -p "$LOCK_DIR" && pass ".delivery-locks/ directory ready"
mkdir -p "$LOG_DIR" && pass ".delivery-logs/ directory ready"

# ── 3. Health check ──────────────────────────────────────────────────────

echo ""
echo "[ Health Check ]"

HEALTH_SCRIPT="$CORE_DIR/scripts/health-check.sh"
if [[ -f "$HEALTH_SCRIPT" ]]; then
  if bash "$HEALTH_SCRIPT" --core-dir "$CORE_DIR" --project-dir "$GAAI_PROJECT_DIR" >/dev/null 2>&1; then
    pass "health-check.sh passed"
  else
    fail "health-check.sh reported issues — run directly for details: bash $HEALTH_SCRIPT"
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
