#!/bin/bash
# Tests for bin/macdict's lookup log (macOS only: it uses the real Dictionary.app). WORDS_STATE
# points into a sandbox, so the user's log is never touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/macdict"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export WORDS_STATE="$SANDBOX/state"
LOG="$WORDS_STATE/lookups.log"

echo "macdict — lookup log"
OUT="$("$SCRIPT" imbroglio)"
case "$OUT" in *"confused"*) pass "a hit prints the definition" ;; *) fail "definition" "$OUT" ;; esac
assert_eq "imbroglio" "$(cut -d' ' -f2- "$LOG" 2>/dev/null)" "and logs the word with a timestamp"
[[ "$(cut -d' ' -f1 "$LOG")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$ ]] && pass "the timestamp is YYYY-MM-DDTHH:MM" || fail "timestamp" "$(cat "$LOG")"
"$SCRIPT" zzqqxx >/dev/null
assert_eq "1" "$(wc -l <"$LOG" | tr -d ' ')" "a miss is not logged"
MACDICT_LOG=0 "$SCRIPT" milieu >/dev/null
assert_eq "1" "$(wc -l <"$LOG" | tr -d ' ')" "MACDICT_LOG=0 (words' own lookups) is not logged"
mkdir -p "$SANDBOX/ro"; chmod 500 "$SANDBOX/ro"
OUT2="$(WORDS_STATE="$SANDBOX/ro/x" "$SCRIPT" imbroglio 2>&1)"
[ "$OUT2" = "$OUT" ] && pass "a log that cannot be written changes nothing in the output" || fail "unwritable log" "$OUT2"
chmod 700 "$SANDBOX/ro"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
