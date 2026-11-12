#!/bin/bash
# Tests for bin/plan-open: plan items stay open until ticked, dismissed or 30 days old.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/plan-open"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_lacks() { case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly in [$1]" ;; *) pass "$3" ;; esac; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
export DIARY_DIR="$SANDBOX/diary"
TODAY=2026-11-10

reset() { rm -rf "$DIARY_DIR"; mkdir -p "$DIARY_DIR/.agent"; }
# plan DATE LINE...: a diary file with a plan block holding the lines
plan() {
  local d="$1"; shift
  { echo "# $d"; echo '## Work'; echo '### ECFX'; echo '<!-- start-day:start -->'; echo '#### Plan'; echo
    printf '%s\n' "$@"; echo '<!-- start-day:end -->'; } > "$DIARY_DIR/$d.md"
}
# note DATE KEY KIND TEXT: through the real day-agent
note() {
  [ -f "$DIARY_DIR/.agent/$1.md" ] || DAY_AGENT_DATE="$1" "$TEST_DIR/day-agent" init
  DAY_AGENT_DATE="$1" DAY_AGENT_NOW=09:00 "$TEST_DIR/day-agent" note "$2" "$3" "$4"
}
list() { "$SCRIPT" list --date "$TODAY" "$@"; }
missing() { "$SCRIPT" missing --date "$TODAY"; }

echo "plan-open — an item left off yesterday's plan is still open"
reset
plan 2026-11-08 '**First**' '- [/] ecfx-100 answer Bob on backend!1' '  - [X] fix N1' '  - [ ] reply to Bob' \
  '- [X] ecfx-101 merged dashboard!2' '**Today**' '- [ ] ecfx-102 investigate the filter bug'
plan 2026-11-09 '**First**' '- [/] ecfx-100 answer Bob, then merge'
note 2026-11-08 ecfx-102 blocked "waits on Levi's answer"
out=$(list)
assert_contains "$out" "- [ ] ecfx-102 investigate the filter bug" "the deleted line is listed with its words"
assert_contains "$out" "first planned 2026-11-08, 2 days open, last on the plan 2026-11-08 (Today)" "with its first day, days open and group"
assert_contains "$out" "latest note (2026-11-08 blocked): waits on Levi's answer" "with its latest agent note"
assert_contains "$out" "- [/] ecfx-100 answer Bob, then merge" "an item on yesterday's plan is listed from that plan"
assert_contains "$out" "first planned 2026-11-08, 2 days open, last on the plan 2026-11-09" "and keeps its first day"
assert_lacks "$out" "ecfx-101" "a ticked item is not listed"

echo "plan-open — leaving it off again does not close it"
assert_eq "ecfx-100 answer Bob, then merge
ecfx-102 investigate the filter bug" "$(printf '%s\n' '- [ ] ecfx-200 new work' | missing)" "missing names both open items a plan leaves out"
assert_eq "ecfx-102 investigate the filter bug" "$(printf '%s\n' '**Today**' '- [/] ecfx-100 merge' | missing)" "an item back on the plan is not missing"
plan "$TODAY" '- [ ] ecfx-200 new work'
assert_contains "$("$SCRIPT" list --date 2026-11-11)" "- [ ] ecfx-102 investigate the filter bug" "the day after, it is still listed"

echo "plan-open — ticking or dismissing closes it"
reset
plan 2026-11-08 '- [ ] ecfx-102 investigate the filter bug' '- [ ] ecfx-103 chase product' '- [ ] ecfx-104 old idea'
plan 2026-11-09 '- [X] ecfx-102 found it' '- [-] ecfx-103 chase product'
note "$TODAY" ecfx-104 dismissed "the user said: not needed"
assert_eq "(none)" "$(list)" "[X], [-] and a dismissed note each close an item"
reset
plan 2026-11-08 '- [ ] ecfx-104 old idea'
note 2026-11-08 ecfx-104 done "a step's evidence"
note 2026-11-08 ecfx-104 note "nothing closes it but a tick"
assert_contains "$(list)" "ecfx-104" "a done or note entry alone does not close it"
reset
plan 2026-11-08 '- [X] ecfx-105 shipped' '  - [ ] follow-up check'
assert_eq "(none)" "$(list)" "a ticked parent closes the item, open children too"

echo "plan-open — a ticket reopened after it was closed is a new item"
reset
plan 2026-10-01 '- [X] ecfx-106 first round'
plan 2026-11-08 '- [ ] ecfx-106 second round'
out=$(list)
assert_contains "$out" "first planned 2026-11-08" "its first day is the new line's"
assert_lacks "$out" "Expired" "and it is not expired"

echo "plan-open — 30 days, then expired once"
reset
plan 2026-10-10 '- [ ] ecfx-107 long forgotten' '- [ ] reply to Anna about exports'
plan 2026-11-09 '- [ ] ecfx-108 fresh'
out=$(list --record)
assert_contains "$out" "Expired (first planned over 30 days ago" "an item first planned 31 days ago is listed as expired"
assert_contains "$out" "ecfx-107 long forgotten (since 2026-10-10)" "naming it"
assert_contains "$out" "2026-10-10/i2 reply to Anna about exports" "a keyless one by its ref"
assert_lacks "$(sed -n '/^- /p' <<<"$out")" "ecfx-107" "it is not listed as open"
assert_contains "$(cat "$DIARY_DIR/.agent/$TODAY.md")" "## ecfx-107" "--record writes an expired note"
assert_contains "$(cat "$DIARY_DIR/.agent/$TODAY.md")" "## 2026-10-10/i2" "for the keyless one too"
out=$(list)
assert_lacks "$out" "ecfx-107" "the next run no longer lists it"
assert_contains "$out" "ecfx-108" "the young item stays"

echo "plan-open — keyless items keep their identity across days"
reset
plan 2026-11-06 '- [/] figure out the devbox state <!-- p3 -->' '- [ ] re-review Travis on claude-components!55'
plan 2026-11-09 '- [/] devbox: message for Chris <!-- p1 -->' '- [!] claude-components!55 waits on Travis'
note 2026-11-09 p1 carried "from 2026-11-06/p3: state checked"
out=$(list)
assert_eq 2 "$(grep -c '^- ' <<<"$out")" "a carried pN line and a line on the same MR are the same items"
assert_contains "$out" "- [/] devbox: message for Chris
  ref 2026-11-09/p1, first planned" "named by the latest ref"
assert_contains "$out" "first planned 2026-11-06, 4 days open" "first planned on the first day"
assert_contains "$out" "latest note (2026-11-09 carried): from 2026-11-06/p3: state checked" "its latest note"
note "$TODAY" p2 carried "from 2026-11-09/p1: message drafted"
assert_eq "2026-11-09/i2 claude-components!55 waits on Travis" "$(printf '%s\n' '- [ ] devbox message <!-- p2 -->' | missing)" "a carried-from note links today's line"
assert_eq "" "$(printf '%s\n' '- [ ] devbox message <!-- p2 -->' '- [ ] claude-components!55 ping Travis <!-- p3 -->' | missing)" "so does the same MR"
note "$TODAY" 2026-11-06/p3 dismissed "the user said: drop it"
assert_eq 1 "$(list | grep -c '^- ')" "an earlier ref of a keyless item dismisses it"
plan 2026-11-08 '- [ ] write the release notes'
plan 2026-11-09 '- [ ] write the release notes'
assert_contains "$(list)" "first planned 2026-11-08" "the same words are the same item"

echo "plan-open — a dated deferral keeps it off the plan until its date"
reset
plan 2026-11-06 '- [>] ecfx-18778 merge backend!6889 after the release'
note 2026-11-06 ecfx-18778 deferred "2026-11-11 after the Tue release"
out=$(list)
assert_contains "$out" "Deferred, not due yet" "a future date is not due"
assert_contains "$out" "deferred until 2026-11-11" "and says until when"
assert_eq "" "$(printf '%s\n' '- [ ] ecfx-1 x' | missing)" "missing does not name it"
out=$("$SCRIPT" list --date 2026-11-11)
assert_lacks "$out" "Deferred, not due yet" "on its date it is due"
assert_contains "$out" "was deferred until 2026-11-11, due now" "and says so"
reset
plan 2026-11-09 '- [>] ecfx-109 tomorrow'
assert_contains "$(list)" "- [>] ecfx-109 tomorrow" "an undated [>] is due the next day"

echo "plan-open — old-format lines"
reset
plan 2026-11-02 '- [/] ecfx-110 backend!1: answer Bill · progress: fixes pushed  [↗][backend!1]'
out=$(list)
assert_contains "$out" "- [/] ecfx-110 backend!1: answer Bill" "the suffix and refs are not part of the words"
assert_contains "$out" "last state: progress: fixes pushed" "the suffix is the last state when there are no notes"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
