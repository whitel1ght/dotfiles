#!/usr/bin/env bash
# Tests for review-period. Today is pinned to Thursday 2026-10-08 (ISO week 41).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RP="$TEST_DIR/review-period"
export REVIEW_TODAY=2026-10-08
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

# summary <args...>: id, from, to, ended, children ids
summary() { "$RP" "$@" | jq -r '[.id, .from, .to, (.ended | tostring), ([.children[].id] | join(","))] | join(" ")'; }

echo "== defaults: the period that just ended =="
assert_eq "2026-W40 2026-09-28 2026-10-04 true " "$(summary week)" "week"
assert_eq "2026-09 2026-09-01 2026-09-30 true 2026-W36,2026-W37,2026-W38,2026-W39" "$(summary month)" "month and its weeks"
assert_eq "2026-Q3 2026-07-01 2026-09-30 true 2026-07,2026-08,2026-09" "$(summary quarter)" "quarter and its months"
assert_eq "2025 2025-01-01 2025-12-31 true 2025-Q1,2025-Q2,2025-Q3,2025-Q4" "$(summary year)" "year and its quarters"

echo "== explicit periods =="
assert_eq "2026-W41 2026-10-05 2026-10-11 false " "$(summary week 2026-W41)" "the running week is not ended"
assert_eq "2025-W01 2024-12-30 2025-01-05 true " "$(summary week 2025-W01)" "ISO week 1 starts in the previous year"
assert_eq "2026-10 2026-10-01 2026-10-31 false 2026-W40,2026-W41,2026-W42,2026-W43,2026-W44" "$(summary month 2026-10)" "a week belongs to the month of its Thursday"
assert_eq "2026-01 2026-01-01 2026-01-31 true 2026-W01,2026-W02,2026-W03,2026-W04,2026-W05" "$(summary month 2026-01)" "January starts with week 1 of the ISO year"
assert_eq "reviews/2026-W40.md" "$("$RP" week | jq -r .file)" "file path is relative to the vault"

echo "== early January defaults =="
assert_eq "2025-Q4 2025-10-01 2025-12-31 true 2025-10,2025-11,2025-12" "$(REVIEW_TODAY=2026-01-05 summary quarter)" "quarter before Q1 is Q4 of last year"
assert_eq "2025-12 2025-12-01 2025-12-31 true 2025-W49,2025-W50,2025-W51,2025-W52" "$(REVIEW_TODAY=2026-01-05 summary month)" "month before January is December"

echo "== errors =="
"$RP" week 2026-10 >/dev/null 2>&1; assert_eq "2" "$?" "month spelling for a week exits 2"
"$RP" week 2026-W54 >/dev/null 2>&1; assert_eq "2" "$?" "week 54 exits 2"
"$RP" month 2026-13 >/dev/null 2>&1; assert_eq "2" "$?" "month 13 exits 2"
"$RP" decade >/dev/null 2>&1; assert_eq "2" "$?" "unknown level exits 2"
"$RP" >/dev/null 2>&1; assert_eq "2" "$?" "no arguments exits 2"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
