#!/usr/bin/env bash
# Pre-push validator : block push when a hermetic test is not executable.
#
# validate-public-release.sh discovers scripts/tests/*.sh and invokes each one
# as an executable, treating a matched-but-non-executable file as a phase
# failure. Because that phase is fail-fast, a single file at mode 644 stops the
# whole gate on file discovery — before any assertion runs — so the CI log shows
# a failure with no FAIL: line and no test output. That reads as a mystery.
#
# This has bitten twice: once when the gate was first made mandatory and a batch
# of pre-existing tests had to be chmod'd, and again when a newly added test
# landed without the bit and kept the gate red until someone read the discovery
# error. Nothing enforced the bit at commit time, so each new test file added
# without it repeats the outage.
#
# Checks the git index, not the filesystem: the index mode is what a push
# publishes, and a file can be executable locally while staged as 100644.
#
# Cost : one git ls-files over a single directory, single-digit ms.
# Failure mode : push aborted, with the exact `git update-index` fix to apply.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
TESTS_REL=".gaai/core/scripts/tests"

[ -d "$ROOT/$TESTS_REL" ] || exit 0

# Mode 100755 is executable; 100644 is not. Symlinks (120000) are out of scope.
OFFENDERS="$(git -C "$ROOT" ls-files -s -- "$TESTS_REL/*.sh" \
  | awk '$1 == "100644" { print $4 }')"

[ -z "$OFFENDERS" ] && exit 0

{
  echo ""
  echo "❌ pre-push: hermetic test(s) staged without the executable bit — push aborted."
  echo ""
  echo "   validate-public-release.sh invokes each $TESTS_REL/*.sh as an"
  echo "   executable and fails the whole shell-tests phase on discovery when one"
  echo "   is not. The gate stops before running a single assertion."
  echo ""
  echo "   Offending file(s):"
  printf '     %s\n' $OFFENDERS
  echo ""
  echo "   Fix:"
  echo "     chmod +x $OFFENDERS"
  echo "     git update-index --chmod=+x $OFFENDERS"
  echo "     git commit --amend --no-edit    # or stage as a new commit"
  echo ""
} >&2

exit 1
