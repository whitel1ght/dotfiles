#!/bin/bash
# Tests for the review-local playbooks (claude/commands and pi/prompts twins):
# unresolved discussions come from `glab mr view --unresolved`, not a
# `glab api .../discussions` GET. Reads files only: no network, no model.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${COMMANDS_TEST_ROOT:-$(dirname "$TEST_DIR")}"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

for f in claude/commands/review-local.md pi/prompts/review-local.md; do
  echo "$f"
  file="$ROOT/$f"
  if [ ! -f "$file" ]; then fail "exists" "$file missing"; continue; fi
  hit="$(grep -nE 'glab api.*/discussions' "$file")"
  if [ -z "$hit" ]; then pass "no glab api read of /discussions"; else fail "no glab api read of /discussions" "$hit"; fi
  if grep -q -- '--unresolved' "$file"; then pass "reads unresolved threads with --unresolved"; else fail "reads unresolved threads with --unresolved" "[--unresolved] not in $f"; fi
done

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
