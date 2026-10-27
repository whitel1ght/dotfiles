#!/bin/bash
# Tests for bin/drills. CARDS_DIR, DRILLS_STATE and the aliases are sandboxed, so nothing reaches
# ~/wiki or ~/.local/state.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/drills"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export CARDS_DIR="$SANDBOX/cards" DRILLS_STATE="$SANDBOX/state" DRILLS_CARDS="$TEST_DIR/cards"
export DRILLS_ALIASES="$SANDBOX/aliases.zsh"
printf "alias w='words look'\nalias ll=\"ls -la\"\n" >"$DRILLS_ALIASES"

drills() { "$SCRIPT" "$@" 2>"$SANDBOX/stderr"; }
fm() { sed -n "s/^$2: //p" "$CARDS_DIR/$1.md" | head -1; }
ncards() { find "$CARDS_DIR" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }
reset() { rm -rf "$CARDS_DIR" "$DRILLS_STATE"; mkdir -p "$CARDS_DIR"; }

echo "drills add"
reset
S="$(drills add --goal "Show how many friction cards are waiting." --cmd friction-cards --accept "friction-cards count" --run yes --date 2026-10-27)"; RC=$?
assert_eq "0|1" "$RC|$(ncards)" "a drill is one card"
assert_eq "[drill]|friction-cards|friction-cards count|yes|hand|learning" "$(fm "$S" tags)|$(fm "$S" cmd)|$(fm "$S" accept)|$(fm "$S" run)|$(fm "$S" from)|$(fm "$S" stage)" "with its drill keys"
assert_eq "## Question: Show how many friction cards are waiting." "$(grep '^## Question' "$CARDS_DIR/$S.md")" "the front is the goal"
assert_eq "### Answer: friction-cards count" "$(grep '^### Answer' "$CARDS_DIR/$S.md")" "the back is the command"
assert_eq "$S|1" "$(drills add --goal "Count the friction cards." --cmd friction-cards --accept "friction-cards   count" --run yes)|$(ncards)" "the same accept again prints the slug and writes nothing"
drills add --goal "x" --cmd x --accept "x" --run maybe >/dev/null; assert_eq "2" "$?" "--run must be yes or no"
drills add --goal "" --cmd x --accept "x" --run yes >/dev/null; assert_eq "2" "$?" "an empty goal exits 2"
S2="$(drills add --goal "Open the hand-off window for ECFX-123." --cmd handoff-open --accept "handoff-open ECFX-123" --run no --back "handoff-open ECFX-123 ~/w" --page terminal.md --from manual)"
assert_eq "no|manual|terminal.md|handoff-open ECFX-123 ~/w" "$(fm "$S2" run)|$(fm "$S2" from)|$(fm "$S2" page)|$(sed -n 's/^### Answer: //p' "$CARDS_DIR/$S2.md")" "--back, --page and --from are kept"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
