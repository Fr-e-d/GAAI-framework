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
