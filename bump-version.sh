#!/usr/bin/env bash
set -euo pipefail

# bump-version.sh — Update GAAI framework version across all locations
# Usage: ./bump-version.sh <new-version>
# Example: ./bump-version.sh 2.2.0
#
# This script lives in the GAAI-framework OSS repo root (not distributed to consumers).
# It updates all 4 locations where the version appears, then creates a git tag.

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

# ── Validate input ──────────────────────────────────────────────────
NEW_VERSION="${1:-}"

if [[ -z "$NEW_VERSION" ]]; then
  echo "Usage: $0 <new-version>"
  echo "Example: $0 2.2.0"
  exit 1
fi

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be semver (e.g. 2.2.0), got: $NEW_VERSION"
  exit 1
fi

CORE_DIR="$REPO_ROOT/.gaai/core"
OLD_VERSION="$(cat "$CORE_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')"

if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
  echo "Version is already $NEW_VERSION — nothing to do."
  exit 0
fi

echo "Bumping GAAI: $OLD_VERSION → $NEW_VERSION"
echo ""

# ── 1. core/VERSION (source of truth) ──────────────────────────────
echo "$NEW_VERSION" > "$CORE_DIR/VERSION"
echo "  ✓ core/VERSION"

# ── 2. core/README.md — title line ─────────────────────────────────
if [[ -f "$CORE_DIR/README.md" ]]; then
  sed -i '' "s/GAAI Framework (v[0-9]*\.[0-9]*\.[0-9]*)/GAAI Framework (v$NEW_VERSION)/" "$CORE_DIR/README.md"
  echo "  ✓ core/README.md title"
else
  echo "  ⚠ core/README.md not found — skipped"
fi

# ── 3. core/README.md — subtree example tag ────────────────────────
if [[ -f "$CORE_DIR/README.md" ]]; then
  sed -i '' "s/gaai-framework v[0-9]*\.[0-9]*\.[0-9]* --squash/gaai-framework v$NEW_VERSION --squash/" "$CORE_DIR/README.md"
  echo "  ✓ core/README.md subtree example"
fi

# ── 4. README.md (repo root) — shields.io badge ────────────────────
if [[ -f "$REPO_ROOT/README.md" ]]; then
  sed -i '' "s/version-[0-9]*\.[0-9]*\.[0-9]*-blue/version-$NEW_VERSION-blue/" "$REPO_ROOT/README.md"
  echo "  ✓ README.md badge"
else
  echo "  ⚠ README.md not found — skipped"
fi

echo ""
echo "Done. All locations updated to v$NEW_VERSION."
echo ""
echo "Next steps:"
echo "  git add -A && git commit -m \"chore: bump version to $NEW_VERSION\""
echo "  git tag v$NEW_VERSION"
echo "  git push origin main --tags"
