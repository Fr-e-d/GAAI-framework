#!/usr/bin/env bash
# daemon-routing-matrix.test.sh
#
# Shell runner for the proxy/direct compatibility contract proxy/direct compatibility matrix regression test.
# Runs the node:test fixture covering all five matrix rows × {Plan, Impl, QA} env checks.
#
# AC4: deterministic dry-run command for the proxy/direct compatibility matrix.
# AC5: node:test exits non-zero if the [AC5] named assertion fails.
#
# Usage (from repo root):
#   bash .gaai/core/scripts/tests/daemon-routing-matrix.test.sh
#
# Requires: Node.js >= 18 (node:test + node --test).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
TESTS_DIR="${REPO_ROOT}/.gaai/core/scripts/tests"
FIXTURE="${TESTS_DIR}/daemon-routing-matrix.fixture.js"

if [[ ! -f "${FIXTURE}" ]]; then
  echo "ERROR: fixture not found: ${FIXTURE}" >&2
  exit 1
fi

cd "${REPO_ROOT}"
exec node --test "${FIXTURE}"
