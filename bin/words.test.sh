#!/bin/bash
# Tests for bin/words. CARDS_DIR, WORDS_STATE and the diary are sandboxed; macdict is a stub on
# WORDS_MACDICT and the feed a fixture on WORDS_FEED, so nothing reaches ~/wiki or the network.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/words"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export CARDS_DIR="$SANDBOX/cards" WORDS_STATE="$SANDBOX/state" WORDS_CARDS="$TEST_DIR/cards"
export WORDS_MACDICT="$SANDBOX/macdict"
cat >"$WORDS_MACDICT" <<'STUB'
#!/bin/bash
case "$1" in
  imbroglio) printf 'imbroglio im·bro·glio | imˈbrōlyō |\n\nnoun (plural imbroglios) an extremely confused, complicated, or embarrassing situation: the Watergate imbroglio.\n  • archaic a confused heap.\n\nORIGIN mid 18th century: Italian.\n' ;;
  "gordian knot"|"it's"|well-being|balmy|milieu|cordial) printf '%s\n\nnoun a sense of %s: an example of %s.\n' "$1" "$1" "$1" ;;
  *) printf 'No definition found for "%s".\n' "$1" ;;
esac
STUB
chmod +x "$WORDS_MACDICT"

words() { "$SCRIPT" "$@" 2>"$SANDBOX/stderr"; }
fm() { sed -n "s/^$2: //p" "$CARDS_DIR/$1.md" | head -1; }
ncards() { find "$CARDS_DIR" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }
reset() { rm -rf "$CARDS_DIR" "$WORDS_STATE"; mkdir -p "$CARDS_DIR"; }

echo "words add"
reset
S="$(words add imbroglio --date 2026-10-27 --met-in "the Watergate imbroglio dragged on" --from lookup)"; RC=$?
assert_eq "0|1" "$RC|$(ncards)" "a word the dictionary knows is saved as one card"
assert_eq "imbroglio|lookup|2026-10-27|learning|the Watergate imbroglio dragged on" "$(fm "$S" word)|$(fm "$S" from)|$(fm "$S" captured)|$(fm "$S" stage)|$(fm "$S" met_in)" "with its word-card keys"
assert_eq "[word]" "$(fm "$S" tags)" "tagged word"
assert_eq '## Question: What does *imbroglio* mean? — "the Watergate imbroglio dragged on"' "$(grep '^## Question' "$CARDS_DIR/$S.md")" "the front asks the meaning, with the sentence it was met in"
BACK="$(sed -n 's/^### Answer: //p' "$CARDS_DIR/$S.md")"
assert_has "an extremely confused, complicated, or embarrassing situation" "$BACK" "the back is the first sense"
case "$BACK" in *ORIGIN*|*im·bro·glio*) fail "short back" "$BACK" ;; *) pass "without the headword line or the origin" ;; esac
[ "${#BACK}" -le 300 ] && pass "at most 300 characters" || fail "short back" "${#BACK} chars"
assert_eq "$S" "$(words add Imbroglio --from mw)" "a word already saved prints its slug"
assert_eq "1" "$(ncards)" "and writes nothing"
words add zzqqxx >/dev/null; RC=$?
assert_eq "1|1" "$RC|$(ncards)" "a word the dictionary lacks exits 1 and saves nothing"
assert_has "no definition for zzqqxx" "$(cat "$SANDBOX/stderr")" "and says so"
S2="$(words add zzqqxx --back "a made-up word")"; RC=$?
assert_eq "0|a made-up word" "$RC|$(sed -n 's/^### Answer: //p' "$CARDS_DIR/$S2.md")" "--back saves it anyway"
assert_eq '## Question: What does *zzqqxx* mean?' "$(grep '^## Question' "$CARDS_DIR/$S2.md")" "no sentence, no quote on the front"

echo "words add — odd words"
for w in "gordian knot" "it's" "well-being"; do
  S="$(words add "$w")"; RC=$?
  assert_eq "0|$w" "$RC|$(fm "$S" word)" "\"$w\" is saved"
  assert_eq "$S" "$(words add "$(echo "$w" | tr a-z A-Z)")" "and \"$w\" in capitals matches it"
done

echo "words today"
reset
export WORDS_FEED="$TEST_DIR/words.fixture-feed.xml"
S="$(words today --date 2026-10-26)"; RC=$?
assert_eq "0|disparate|mw|2026-10-26" "$RC|$(fm "$S" word)|$(fm "$S" from)|$(fm "$S" captured)" "the day's word from the feed is saved"
assert_has "The orchestral project joins disparate musical elements" "$(fm "$S" met_in)" "with the feed's example sentence"
assert_eq "### Answer: different from each other" "$(grep '^### Answer' "$CARDS_DIR/$S.md")" "and its short definition as the back"
assert_eq "" "$(words today --date 2026-10-26)" "a second run the same day prints nothing"
assert_eq "1" "$(ncards)" "and saves nothing"
S="$(words today --date 2030-01-01)"
assert_eq "milieu" "$(fm "$S" word)" "a date the feed does not have takes the newest word"
reset
WORDS_FEED="$SANDBOX/nope.xml" words today >/dev/null; RC=$?
assert_eq "0|0" "$RC|$(ncards)" "bad feed: a missing feed exits 0 and saves nothing"
assert_has "words today:" "$(cat "$SANDBOX/stderr")" "with one line on stderr"
printf '<html><body>Sign in to the wifi</body></html>' >"$SANDBOX/portal.xml"
WORDS_FEED="$SANDBOX/portal.xml" words today >/dev/null; RC=$?
assert_eq "0|0" "$RC|$(ncards)" "bad feed: an HTML page exits 0 and saves nothing"

echo "words import-diary"
reset
DIARY="$SANDBOX/diary"; mkdir -p "$DIARY"
line() { printf '# %s\n\n- [X] reading any fiction book\n%s\n- [ ] drawing\n' "$1" "$2" >"$DIARY/$1.md"; }
line 2026-08-19 '- [X] merriam-webster word of the day (balmy - warm, mild, pleasant for weather; foolish, irrational for an idea)'
line 2026-08-20 '- [X] merriam-webster word of the day (cordial)'
line 2026-08-21 '- [X] merriam-webster word of the day (sacrosant)'
line 2026-08-22 '- [ ] merriam-webster word of the day (vindicate)'
line 2026-08-23 '- [X] merriam-webster word of the day (tacit = unspoken)'
line 2026-08-24 '- [x] merriam-webster word of the day (salvo, mostly in military context (artillery) - a volley)'
line 2026-08-25 '- [X] merriam-webster word of the day (paTIna)'
line 2026-08-26 '- [X] merriam-webster word of the day (milieu - setting)'
line 2026-08-27 '- [ ] merriam-webster word of the day'
words add milieu >/dev/null
OUT="$(words import-diary --diary-dir "$DIARY")"; RC=$?
assert_eq "0|imported 6, already saved 1, to check 2" "$RC|$OUT" "imports the ticked words and says how it went"
B="$(words add balmy)"
assert_eq "warm, mild, pleasant for weather; foolish, irrational for an idea|diary|2026-08-19" "$(sed -n 's/^### Answer: //p' "$CARDS_DIR/$B.md")|$(fm "$B" from)|$(fm "$B" captured)" "a meaning written in the diary is the back, dated by the diary day"
assert_eq "unspoken" "$(sed -n 's/^### Answer: //p' "$CARDS_DIR/$(words add tacit).md")" "odd diary lines: an = separator"
assert_eq "mostly in military context (artillery) - a volley" "$(sed -n 's/^### Answer: //p' "$CARDS_DIR/$(words add salvo).md")" "odd diary lines: a comma, nested parentheses and a later ' - ' stay in the meaning"
assert_has "a sense of cordial" "$(sed -n 's/^### Answer: //p' "$CARDS_DIR/$(words add cordial).md")" "a bare word gets its back from the dictionary"
SC="$(words add sacrosant)"
assert_eq "(look this one up again)|[word, word-check]" "$(sed -n 's/^### Answer: //p' "$CARDS_DIR/$SC.md")|$(fm "$SC" tags)" "a word the dictionary lacks is kept, marked to check"
assert_eq "patina" "$(fm "$(words add patina)" word)" "stress capitals become a plain lower-case word"
assert_eq "" "$(rg -l 'vindicate' "$CARDS_DIR" 2>/dev/null)" "an unticked line is skipped"
assert_eq "imported 0, already saved 7, to check 0" "$(words import-diary --diary-dir "$DIARY")" "a second run imports nothing"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
