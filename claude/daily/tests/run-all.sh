#!/usr/bin/env bash
# Runs every check for the daily plugin: bash tests, plugin validation, mod unit tests.
set -uo pipefail

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

run() {
  echo "### $*"
  "$@" || { echo "### FAILED: $*"; FAILED=1; }
}

run bash "$PLUGIN/tests/session-start.test.sh"
run bash "$PLUGIN/tests/templates.test.sh"
run bash "$PLUGIN/tests/run-day.test.sh"
run bash "$PLUGIN/tests/side-session.test.sh"
run bash "$PLUGIN/tests/review.test.sh"
run bash "$PLUGIN/tests/end-day.test.sh"
run bash "$PLUGIN/skills/jira-write/scripts/jira-write.test.sh"
run bash "$PLUGIN/scripts/review-period.test.sh"
run bash "$PLUGIN/scripts/review-extract.test.sh"
run bash "$PLUGIN/../../bin/end-day.test.sh"
run bash "$PLUGIN/../vendor-sync.test.sh"
run claude plugin validate "$PLUGIN"
run claude plugin test "$PLUGIN"

[ "$FAILED" -eq 0 ] && echo "ALL OK" || { echo "SOME CHECKS FAILED"; exit 1; }
