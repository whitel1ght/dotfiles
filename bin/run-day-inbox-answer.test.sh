#!/bin/bash
# bin/run-day-inbox-answer: decisions' on_answer events become run-day inbox files.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/run-day-inbox-answer"
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "want [$2], got [$3]"; }
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
ev() { printf '{"event":"%s","id":"D-7","key":"%s","source":"","option":2,"note":null,"text":"%s","at":"2026-10-20T11:20:00+03:00"}\n' "$1" "$2" "$3"; }

echo "kinds and format"
export INBOX_DIR="$SANDBOX/inbox"
ev answered ECFX-1 'D-7 answered: 2 — Push only.' | "$SCRIPT"; check "exits 0" "0" "$?"
f="$(ls "$INBOX_DIR")"
[[ "$f" =~ ^[0-9]{8}T[0-9]{6}-ECFX-1-[a-z0-9]{4}\.md$ ]] && pass "name passes the run-day rule" || fail "name passes the run-day rule" "$f"
check "body" "$(printf -- '---\nkey: ECFX-1\nkind: decision\ndecision: D-7\nsession: decisions\nat: 2026-10-20T11:20:00+03:00\n---\nD-7 answered: 2 — Push only.')" "$(cat "$INBOX_DIR/$f")"
rm "$INBOX_DIR"/*
ev told ECFX-1 'D-7 answered in your own words: close it.' | "$SCRIPT"
check "told is a decision" "kind: decision" "$(grep '^kind:' "$INBOX_DIR"/*)"
rm "$INBOX_DIR"/*
ev asked '' 'D-7: the user asks: why?' | "$SCRIPT"
check "asked is a clarify" "kind: clarify" "$(grep '^kind:' "$INBOX_DIR"/*)"
case "$(ls "$INBOX_DIR")" in *-offplan-*) pass "empty key is offplan" ;; *) fail "empty key is offplan" "$(ls "$INBOX_DIR")" ;; esac
check "no temp file left" "" "$(ls -A "$INBOX_DIR" | grep '\.tmp$')"

echo "defaults without environment"
unset INBOX_DIR
HOME="$SANDBOX/home" RUN_DAY_STATE_DIR= bash -c "$(printf '%q' "$SCRIPT")" < <(ev answered ECFX-2 'D-7 answered: 1 — Yes.')
check "writes under ~/.local/state/run-day/inbox" "1" "$(ls "$SANDBOX/home/.local/state/run-day/inbox" | wc -l | tr -d ' ')"

echo "questions from other sessions"
export INBOX_DIR="$SANDBOX/inbox2"
printf '{"event":"answered","id":"D-8","key":"","source":"claude-code · repo","option":1,"note":null,"text":"D-8 answered: 1 — Yes.","at":"2026-10-20T11:20:00+03:00"}\n' | "$SCRIPT"
check "an answer to another session's question exits 0" "0" "$?"
check "and writes no run-day inbox file" "" "$(ls "$INBOX_DIR" 2>/dev/null)"
unset INBOX_DIR

echo "bad input"
echo 'not json' | "$SCRIPT" 2>/dev/null; check "bad JSON exits 1" "1" "$?"
echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
