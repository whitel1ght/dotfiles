#!/bin/bash
# Tests for bin/cards. CARDS_DIR points into a sandbox and every card is synthetic,
# so nothing touches ~/wiki/cards.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/cards"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export TZ=Etc/GMT-3
export CARDS_DIR="$SANDBOX/cards"
D=2026-10-15
mkdir -p "$CARDS_DIR"

cards() { "$SCRIPT" "$@" 2>"$SANDBOX/stderr"; }
fm() { sed -n "s/^$2: //p" "$CARDS_DIR/$1.md" | head -1; }
reset() { rm -rf "$CARDS_DIR"; mkdir -p "$CARDS_DIR"; }
nfiles() { find "$CARDS_DIR" -type f | wc -l | tr -d ' '; }
mk() { # slug due interval ease reps lapses
    printf -- '---\ndue: %s\ninterval: %s\nease: %s\nreps: %s\nlapses: %s\ntags: [t]\nsource: s\nanki_id: 7\n---\n\n## Question: Q %s?\n\n### Answer: A.\n' "$2" "$3" "$4" "$5" "$6" "$1" >"$CARDS_DIR/$1.md"
}
mkparis() {
    printf -- '---\nanki_id: 12345\nnext_review: 2025-07-01\n---\n\n## Question: What is the capital of France?\n\n### Answer: Paris.\n' >"$CARDS_DIR/paris.md"
}

# --- add ---------------------------------------------------------------------
slug=$(cards add --front "What does the Hook do?" --back "It blocks." --tags "a,b" --source "ECFX-1: notes" --date $D)
assert_eq "what-does-the-hook-do" "$slug" "add prints the slug"
F="$CARDS_DIR/$slug.md"
assert_eq "## Question: What does the Hook do?" "$(grep '^## ' "$F")" "add writes the question heading"
assert_eq "### Answer: It blocks." "$(grep '^### ' "$F")" "add writes the answer heading"
assert_eq "[a, b]" "$(fm "$slug" tags)" "add writes tags"
assert_eq "ECFX-1: notes" "$(fm "$slug" source)" "add writes source"
assert_eq "$D" "$(fm "$slug" due)" "new card is due on the add date"
assert_eq "2.50" "$(fm "$slug" ease)" "new card ease starts at 2.50"
assert_eq "0 0 0" "$(fm "$slug" reps) $(fm "$slug" lapses) $(fm "$slug" interval)" "new card counters are zero"

dup=$(cards add --front "What does the hook do??" --back "other")
assert_eq "what-does-the-hook-do-2" "$dup" "slug dedup appends -2"
dup=$(cards add --front "  what does the   HOOK do?  " --back "other"); rc=$?
assert_eq "what-does-the-hook-do 0" "$dup $rc" "identical front (case, whitespace) returns the existing slug"
assert_eq "2" "$(nfiles)" "dedupe wrote nothing"
a=$(cards add --front "What does the hook do today again please now" --back x)
b=$(cards add --front "What does the hook do today again please later" --back x)
assert_eq "what-does-the-hook-do-today what-does-the-hook-do-today-2" "$a $b" "slug is at most 6 words, deduped"
cards add --back x >/dev/null; assert_eq "2" "$?" "add without --front exits 2"

# --- due ---------------------------------------------------------------------
reset
mk old 2026-10-01 3 2.5 2 0
mk older 2026-09-20 3 2.5 2 0
mk today 2026-10-15 3 2.5 2 0
mk later 2026-10-16 3 2.5 2 0
mkparis
assert_eq "older old today paris" "$(cards due --date $D | cut -f1 | tr '\n' ' ' | sed 's/ $//')" "due: oldest first, new last, future excluded"
assert_eq "older	Q older?" "$(cards due --date $D --limit 1)" "due: plain line is slug TAB front, limit applies"
j=$(cards due --date $D --json)
assert_eq "paris true What is the capital of France? Paris. 0" "$(jq -r '.[-1] | "\(.slug) \(.new) \(.front) \(.back) \(.tags|length)"' <<<"$j")" "due --json: paris.md is new and due"
assert_eq "false [\"t\"]" "$(jq -rc '.[0] | "\(.new) \(.tags)"' <<<"$j")" "due --json: reviewed card shape"
assert_eq "5" "$(cards due --date 2027-01-01 | wc -l | tr -d ' ')" "due: five cards listed"
mk x1 2026-10-01 3 2.5 2 0
assert_eq "5" "$(cards due --date 2027-01-01 | wc -l | tr -d ' ')" "due: default limit caps at 5"
cards due --date nope >/dev/null; assert_eq "2" "$?" "due with a bad date exits 2"
reset
mk zeta 2026-09-01 0 2.5 0 0
mk alpha 2026-10-01 0 2.5 0 0
mk beta 2026-10-01 0 2.5 0 0
assert_eq "zeta alpha beta" "$(cards due --date $D | cut -f1 | tr '\n' ' ' | sed 's/ $//')" "due: new cards oldest first too, then by slug"

# --- grade -------------------------------------------------------------------
state() { echo "$(fm "$1" due) $(fm "$1" interval) $(fm "$1" ease) $(fm "$1" reps) $(fm "$1" lapses)"; }
reset
cards add --front "Fresh zero" --back a >/dev/null
cards add --front "Fresh two" --back a >/dev/null
cards add --front "Fresh three" --back a >/dev/null
cards grade fresh-zero 0 --date $D; assert_eq "2026-10-16 1 2.30 1 1" "$(state fresh-zero)" "grade 0 on a fresh card"
cards grade fresh-two 2 --date $D; assert_eq "2026-10-16 1 2.50 1 0" "$(state fresh-two)" "grade 2, first rep: interval 1"
cards grade fresh-two 2 --date 2026-10-16; assert_eq "2026-10-19 3 2.50 2 0" "$(state fresh-two)" "grade 2, second rep: interval 3"
cards grade fresh-two 2 --date 2026-10-19; assert_eq "2026-10-27 8 2.50 3 0" "$(state fresh-two)" "grade 2, later rep: interval x ease (7.5 rounds to 8)"
cards grade fresh-three 3 --date $D; assert_eq "2026-10-18 3 2.65 1 0" "$(state fresh-three)" "grade 3 on a fresh card"
mk rev 2026-10-01 10 2.5 3 1
cards grade rev 0 --date $D; assert_eq "2026-10-16 1 2.30 4 2" "$(state rev)" "grade 0 on a reviewed card"
mk rev 2026-10-01 10 1.4 3 1
cards grade rev 0 --date $D; assert_eq "2026-10-16 1 1.30 4 2" "$(state rev)" "grade 0 ease floors at 1.3"
mk rev 2026-10-01 10 2.5 3 1
cards grade rev 1 --date $D; assert_eq "2026-10-27 12 2.35 4 1" "$(state rev)" "grade 1: interval x 1.2, ease -0.15"
mk rev 2026-10-01 10 2.5 3 1
cards grade rev 2 --date $D; assert_eq "2026-11-09 25 2.50 4 1" "$(state rev)" "grade 2 on a reviewed card"
mk rev 2026-10-01 10 2.5 3 1
cards grade rev 3 --date $D; assert_eq "2026-11-17 33 2.65 4 1" "$(state rev)" "grade 3 on a reviewed card (32.5 rounds to 33)"
assert_eq "yes" "$(grep -q '^anki_id: 7$' "$CARDS_DIR/rev.md" && grep -q '^## Question: Q rev?$' "$CARDS_DIR/rev.md" && echo yes || echo no)" "grade keeps unknown keys and the body"
assert_eq "no" "$(cards due --date $D | grep -q fresh-two && echo yes || echo no)" "graded card is no longer due"

mkparis
cards grade paris 3 --date $D; assert_eq "2026-10-18 3 2.65 1 0" "$(state paris)" "grade on a paris-style card adds scheduling"
assert_eq "12345 2025-07-01" "$(fm paris anki_id) $(fm paris next_review)" "paris keeps anki_id and next_review"

# --- errors leave the file byte-identical ------------------------------------
mk keep 2026-10-01 10 2.5 3 1
before=$(shasum "$CARDS_DIR/keep.md")
for bad in 4 -1 x 2.5 ""; do
    cards grade keep "$bad" --date $D; rc=$?
    assert_eq "2 $before" "$rc $(shasum "$CARDS_DIR/keep.md")" "invalid grade [$bad] exits 2, file untouched"
done
cards grade keep 2 --date nope; assert_eq "2 $before" "$? $(shasum "$CARDS_DIR/keep.md")" "invalid date exits 2, file untouched"
cards grade nosuch 2; assert_eq "1" "$?" "grade of a missing card exits 1"
cards drop nosuch; assert_eq "1" "$?" "drop of a missing card exits 1"
cards grade ../keep 2; assert_eq "1" "$?" "path-like slug is rejected"
assert_eq "0" "$(find "$CARDS_DIR" -name '*.tmp*' -o -name '.*.md*' | wc -l | tr -d ' ')" "no temp files left behind"

# --- drop --------------------------------------------------------------------
cards drop keep; assert_eq "0 no" "$? $([ -f "$CARDS_DIR/keep.md" ] && echo yes || echo no)" "drop deletes the file"
cards >/dev/null; assert_eq "2" "$?" "no command exits 2"

# --- tags and extra front matter (words) ---------------------------------------
reset
mk aaa 2026-10-10 3 2.5 2 0
printf -- '---\ndue: 2026-10-09\ninterval: 2\nease: 2.5\nreps: 1\nlapses: 0\ntags: [word]\nsource: s\n---\n\n## Question: What does *balmy* mean?\n\n### Answer: Mild.\n' >"$CARDS_DIR/balmy.md"
printf -- '---\ndue: 2026-10-08\ninterval: 2\nease: 2.5\nreps: 1\nlapses: 0\ntags: [word, word-check]\nsource: s\n---\n\n## Question: What does *milieu* mean?\n\n### Answer: Setting.\n' >"$CARDS_DIR/milieu.md"
assert_eq "milieu balmy" "$(cards due --date $D --tag word | cut -f1 | paste -sd ' ' -)" "due --tag lists only cards with that tag"
assert_eq "aaa" "$(cards due --date $D --exclude-tag word | cut -f1 | paste -sd ' ' -)" "due --exclude-tag leaves them out"
assert_eq "milieu" "$(cards due --date $D --tag word --limit 1 | cut -f1)" "the limit applies after the filter"
printf -- '---\ndue: 2026-10-07\ninterval: 2\nease: 2.5\nreps: 1\nlapses: 0\ntags: [drill]\nsource: s\n---\n\n## Question: Show the queue.\n\n### Answer: q.\n' >"$CARDS_DIR/drill-q.md"
assert_eq "aaa" "$(cards due --date $D --exclude-tag word --exclude-tag drill | cut -f1 | paste -sd ' ' -)" "due --exclude-tag twice leaves out both"
assert_eq "drill-q aaa" "$(cards due --date $D --exclude-tag word | cut -f1 | paste -sd ' ' -)" "one --exclude-tag still leaves the others in"
rm "$CARDS_DIR/drill-q.md"
slug=$(cards add --front "What does *imbroglio* mean?" --back "A muddle." --tags word --set word=imbroglio --set "met_in=the Watergate imbroglio" --date $D)
assert_eq "imbroglio|the Watergate imbroglio" "$(fm "$slug" word)|$(fm "$slug" met_in)" "add --set writes extra front-matter keys"
cards add --front "What does *x* mean?" --back "x." --set tags=oops >/dev/null; RC=$?
assert_eq "2|0" "$RC|$(ls "$CARDS_DIR" | grep -c '^what-does-x')" "--set may not overwrite a scheduling key"
cards add --front "What does *y* mean?" --back "y." --set novalue >/dev/null; assert_eq "2" "$?" "--set needs KEY=VALUE"

# --- review history ----------------------------------------------------------
reset
mk hist 2026-10-10 3 2.5 2 0
cards grade hist 2 --date 2026-10-15
cards grade hist 0 --date 2026-10-16
assert_eq "## Reviews|- 2026-10-15 grade 2 interval 8|- 2026-10-16 grade 0 interval 1" "$(sed -n '/^## Reviews/,$p' "$CARDS_DIR/hist.md" | sed '/^$/d' | paste -sd '|' -)" "each grade adds a dated line to the card's review history"
assert_eq "### Answer: A." "$(grep '^### Answer' "$CARDS_DIR/hist.md")" "the answer is untouched"
assert_eq "1" "$(grep -c '^## Reviews' "$CARDS_DIR/hist.md")" "one history section"
printf -- '---\ndue: 2026-10-10\ninterval: 3\nease: 2.5\nreps: 2\nlapses: 0\ntags: [t]\n---\n\n## Question: Q?\n\n### Answer: A.\n\nA note I wrote by hand.\n' >"$CARDS_DIR/hand.md"
cards grade hand 3 --date 2026-10-15
assert_eq "A note I wrote by hand." "$(grep 'by hand' "$CARDS_DIR/hand.md")" "hand-written text after the answer is kept"
assert_eq "## Reviews" "$(grep '^## ' "$CARDS_DIR/hand.md" | tail -1)" "and the history goes last"
assert_eq "Q?|A. A note I wrote by hand." "$("$SCRIPT" due --date 2026-12-31 --json | jq -r '.[] | select(.slug == "hand") | "\(.front)|\(.back | gsub("\\s+"; " "))"')" "the history is not part of the answer"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
