#!/bin/bash
# Tests for bin/decisions (the popup), through its non-interactive entry points.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/decisions"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "want [$2], got [$3]"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in: $2" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export RUN_DAY_STATE_DIR="$SANDBOX/state" INBOX_DIR="$SANDBOX/inbox" DECIDE="$TEST_DIR/decide"
export DECISIONS_SKIP="$SANDBOX/skip"
: > "$DECISIONS_SKIP"
a="$("$DECIDE" add --key ECFX-1 --blocks merge --question 'Fix or merge?' --option fix --option merge --recommend 2 </dev/null)"
b="$("$DECIDE" add --key ECFX-2 --question 'Defer?' --option yes --option no </dev/null)"

echo "list and skip"
check "blocking one first" "$a" "$("$SCRIPT" --act list | head -1 | awk '{print $1}')"
"$SCRIPT" --act skip "$a"
check "skipped one goes last" "$a" "$("$SCRIPT" --act list | tail -1 | awk '{print $1}')"

echo "preview"
out="$("$SCRIPT" --act preview "$a")"
has "header with key" "$out" "ECFX-1"
has "question shown" "$out" "Fix or merge?"
has "recommended marked" "$out" "2. merge   ← recommended"
case "$out" in *"status: open"*) fail "frontmatter hidden" "$out" ;; *) pass "frontmatter hidden" ;; esac

echo "confirm"
printf '\033' | "$SCRIPT" --confirm "$a" 1 >/dev/null
check "esc answers nothing" "open" "$("$DECIDE" list --json | jq -r --arg id "$a" '.[] | select(.id==$id) | "open"')"
printf '\n' | "$SCRIPT" --confirm "$a" rec >/dev/null
has "enter on rec answers the recommended" "$(cat "$RUN_DAY_STATE_DIR/decisions/$a.md")" "2 — merge"
printf 'nshould wait: a day\n' | "$SCRIPT" --confirm "$b" 1 >/dev/null
has "n adds a note" "$(cat "$RUN_DAY_STATE_DIR/decisions/$b.md")" "note: should wait: a day"

echo "ask"
c="$("$DECIDE" add --key ECFX-3 --question 'Which?' --option x --option y </dev/null)"
printf 'what does x cost?\n' | "$SCRIPT" --ask "$c" >/dev/null
has "question back recorded" "$("$DECIDE" show "$c")" "you: what does x cost?"
printf '\n' | "$SCRIPT" --ask "$c" >/dev/null; check "empty question is a no-op" "0" "$?"

echo "empty queue"
"$DECIDE" answer "$c" 1 >/dev/null
out="$("$SCRIPT" </dev/null 2>&1)"; code=$?
check "empty queue exits 0" "0" "$code"
has "says so" "$out" "nothing waiting on you"
out="$("$SCRIPT" --empty </dev/null 2>&1 >/dev/null)"
has "still says so when stdout is discarded (fzf become keeps fzf's /dev/null)" "$out" "nothing waiting on you"
out="$(DECISIONS_SIZE="40 7" "$SCRIPT" --empty </dev/null 2>&1)"
has "framed like the list: top edge with the label" "$out" "╭─ decisions "
has "framed: bottom edge" "$out" "╰"
check "framed: fills the popup height" "7" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
check "framed: every row as wide as the popup" "40" "$(printf '%s\n' "$out" | python3 -c 'import sys; print(*sorted({len(l.rstrip("\n")) for l in sys.stdin}))')"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
