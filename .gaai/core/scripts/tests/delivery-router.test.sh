#!/usr/bin/env bash
# delivery-router.test.sh — runner for the Delivery model-routing fixture.
#
# Usage (from repo root):
#   bash .gaai/core/scripts/tests/delivery-router.test.sh
#
# Requires Node.js >= 18 (node:test).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
FIXTURE="${REPO_ROOT}/.gaai/core/scripts/tests/delivery-router.fixture.mjs"

if [[ ! -f "$FIXTURE" ]]; then
  echo "ERROR: fixture not found: $FIXTURE" >&2
  exit 1
fi

cd "$REPO_ROOT"
exec node --test "$FIXTURE"
