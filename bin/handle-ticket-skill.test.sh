#!/bin/bash
# Tests for the MR-count rule in the handle-ticket skill, claude and pi twins.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TEST_DIR")"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in $4" ;; esac; }
lacks() { case "$2" in *"$3"*) fail "$1" "[$3] unexpectedly in $4" ;; *) pass "$1" ;; esac; }

for harness in claude pi; do
  f="$ROOT/$harness/skills/handle-ticket/SKILL.md"
  text="$(tr '\n' ' ' < "$f" | tr -s ' ')"
  echo "$harness"
  has "$harness: MR count follows the approved approach" "$text" "Open exactly the MRs the approach lists" "$f"
  lacks "$harness: no bare one-MR rule" "$text" "one review cycle, one MR.**" "$f"
  has "$harness: MR phases run once per listed MR" "$text" "run Phases 7–10 once per MR" "$f"
done

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
