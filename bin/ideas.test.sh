#!/bin/bash
# Tests for bin/ideas. IDEAS_FILE and IDEAS_DIR point into a sandbox, so ~/wiki is never read or
# written.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/ideas"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
sed_edit() { if sed --version >/dev/null 2>&1; then sed -i "$1" "$2"; else sed -i '' "$1" "$2"; fi; }
date_add() { date -d "$(date +%F) + $1 days" +%F 2>/dev/null || date -v+"$1"d +%F; }
export IDEAS_FILE="$SANDBOX/IDEA.md" IDEAS_DIR="$SANDBOX/ideas"

ideas() { "$SCRIPT" "$@" 2>"$SANDBOX/stderr"; }
fm() { awk -v k="$2" 'NR > 1 && $0 == "---" { exit } index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^ +/, "", v); print v; exit }' "$IDEAS_DIR/$1.md"; }
id_of() { rg -l --fixed-strings "text: $1" "$IDEAS_DIR" 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null | sed 's/\.md$//'; }
reset() { rm -rf "$IDEAS_DIR"; }

echo "ideas sync — first run"
cat >"$IDEAS_FILE" <<'EOF'
# here is the ideas I'd like to write down and review

- my own dictionary app
- nice way to compare a git file with itself in another branch

## review & implement:

- [ ] ideas watcher
- [ ] learn kubectl and how to work with it

## implemented:

- [X] close all empty windows tmux
- [-] nvm for claude skills (claude plugin system instead)
EOF
SUM_BEFORE="$(shasum "$IDEAS_FILE")"
OUT="$(ideas sync)"; RC=$?
assert_eq "0" "$RC" "sync exits 0"
assert_eq "6" "$(ls "$IDEAS_DIR"/I-*.md 2>/dev/null | wc -l | tr -d ' ')" "one file per idea"
assert_eq "4" "$(jq '.new | length' <<<"$OUT")" "the four open ideas are new"
assert_eq "0|0|0" "$(jq -r '[.edited, .closed, .gone] | map(length) | join("|")' <<<"$OUT")" "nothing edited, closed or gone"
D="$(id_of "my own dictionary app")"
assert_eq "loose|none|new" "$(fm "$D" section)|$(fm "$D" mark)|$(fm "$D" status)" "a loose line: section loose, no checkbox, new"
W="$(id_of "ideas watcher")"
assert_eq "review|open|new" "$(fm "$W" section)|$(fm "$W" mark)|$(fm "$W" status)" "a review item: section review, open box"
X="$(id_of "close all empty windows tmux")"
assert_eq "implemented|done|done" "$(fm "$X" section)|$(fm "$X" mark)|$(fm "$X" status)" "a ticked line is recorded as done"
N="$(id_of "nvm for claude skills (claude plugin system instead)")"
assert_eq "dropped|dropped" "$(fm "$N" mark)|$(fm "$N" status)" "a [-] line is recorded as dropped"
assert_eq "I-001" "$D" "ids start at I-001, in file order"
assert_has "| $W | new |" "$(cat "$IDEAS_DIR/index.md")" "the index has a row per idea"
assert_eq "$SUM_BEFORE" "$(shasum "$IDEAS_FILE")" "IDEA.md is never written"

echo "ideas sync — second run"
touch -t 202601010000 "$IDEAS_DIR"/I-*.md
OUT="$(ideas sync)"
assert_eq '{"new":[],"edited":[],"closed":[],"gone":[]}' "$(jq -c . <<<"$OUT")" "nothing changes"
assert_eq "0" "$(find "$IDEAS_DIR" -name 'I-*.md' -newer "$IDEAS_FILE" | wc -l | tr -d ' ')" "no entry file is rewritten"

echo "ideas sync — odd lines"
reset
cat >"$IDEAS_FILE" <<'EOF'
# title line

-
- a long idea that
  goes on over a second line
- [x] lowercase tick

## no colon heading
- under a heading without a colon
EOF
OUT="$(ideas sync)"; RC=$?
assert_eq "0" "$RC" "odd lines do not crash sync"
assert_eq "3" "$(ls "$IDEAS_DIR"/I-*.md | wc -l | tr -d ' ')" "no entry for a bare dash or the title"
assert_eq "1" "$(rg -l --fixed-strings 'text: a long idea that goes on over a second line' "$IDEAS_DIR" | wc -l | tr -d ' ')" "a continuation line joins its idea"
assert_eq "done" "$(fm "$(id_of 'lowercase tick')" status)" "a lowercase [x] counts as done"
assert_eq "loose" "$(fm "$(id_of 'under a heading without a colon')" section)" "an unknown heading counts as loose"

setfm() { sed_edit "s|^$2:.*|$2: $3|" "$IDEAS_DIR/$1.md"; } # id key value (stands in for record/answer)
start() { reset; printf '# ideas\n\n## review & implement:\n\n'"$1" >"$IDEAS_FILE"; ideas sync >/dev/null; }

echo "ideas sync — edits"
start '- [ ] learn more about nushell and if it is worth switching to it\n'
E="$(id_of 'learn more about nushell')"
setfm "$E" status reviewed; setfm "$E" answer no
printf '# ideas\n\n## review & implement:\n\n- [ ] learn more about nushell and if it is worth swiching to it\n' >"$IDEAS_FILE"
OUT="$(ideas sync)"
assert_eq "$E|reviewed|no" "$(id_of 'learn more about nushell and if it is worth swiching')|$(fm "$E" status)|$(fm "$E" answer)" "a typo fix keeps the entry, its review and the answer"
assert_eq "0|0" "$(jq -r '[.edited, .new] | map(length) | join("|")' <<<"$OUT")" "and is neither edited nor new"
printf '# ideas\n\n## review & implement:\n\n- [ ] learn more about nushell and whether to switch my main shell to it\n' >"$IDEAS_FILE"
OUT="$(ideas sync)"
assert_eq "[\"$E\"]" "$(jq -c .edited <<<"$OUT")" "a substantive edit re-opens the same entry"
assert_eq "edited|" "$(fm "$E" status)|$(fm "$E" answer)" "as edited, its answer cleared"
printf '# ideas\n\n## review & implement:\n\n- [ ] a raspberry pi torrent media center\n' >"$IDEAS_FILE"
OUT="$(ideas sync)"
assert_eq "gone" "$(fm "$E" status)" "a rewrite leaves the old entry gone"
assert_eq "1|1" "$(jq -r '[.new, .gone] | map(length) | join("|")' <<<"$OUT")" "and makes a new one"

echo "ideas sync — ticks"
start '- [ ] limiting claude access to certain files\n'
L="$(id_of 'limiting claude access')"
setfm "$L" status reviewed
printf '# ideas\n\n## review & implement:\n\n- [X] limiting claude access to certain files\n' >"$IDEAS_FILE"
OUT="$(ideas sync)"
assert_eq "[\"$L\"]|[]" "$(jq -c .closed <<<"$OUT")|$(jq -c .edited <<<"$OUT")" "a tick closes, never edits"
assert_eq "done" "$(fm "$L" status)" "recorded as done"

echo "ideas sync — similar ideas and removed lines"
start '- [ ] learn kubectl\n- [ ] learn kubectl basics\n- [ ] T1 schedule watcher\n'
assert_eq "3" "$(ls "$IDEAS_DIR"/I-*.md | wc -l | tr -d ' ')" "similar ideas both present stay two"
printf '# ideas\n\n## review & implement:\n\n- [ ] learn kubectl\n- [ ] learn kubectl basics\n' >"$IDEAS_FILE"
OUT="$(ideas sync)"
assert_eq "gone" "$(fm "$(id_of 'T1 schedule watcher')" status)" "a removed line is gone"
assert_eq "new|new" "$(fm "$(id_of 'learn kubectl')" status)|$(fm "$(id_of 'learn kubectl basics')" status)" "its neighbours are untouched"

echo "ideas due"
start '- [ ] first\n- [ ] second\n- [ ] third\n- [ ] fourth\n- [ ] fifth\n- [ ] sixth\n- [X] seventh done\n'
FIRST="$(id_of first)"; SECOND="$(id_of second)"; THIRD="$(id_of third)"; FOURTH="$(id_of fourth)"; FIFTH="$(id_of fifth)"; SIXTH="$(id_of sixth)"
setfm "$FIRST" first_seen 2026-01-03; setfm "$SECOND" first_seen 2026-01-01
assert_eq "[\"$SECOND\",\"$FIRST\",\"$THIRD\"]" "$(ideas due --limit 3 | jq -c 'map(.id)')" "oldest first, capped by --limit"
assert_eq "id text section status" "$(ideas due | jq -r '.[0] | keys_unsorted | join(" ")')" "each item has id, text, section, status"
setfm "$THIRD" status reviewed; setfm "$FOURTH" answer no; setfm "$FIFTH" later_until 2099-01-01
assert_eq "[\"$SECOND\",\"$FIRST\",\"$SIXTH\"]" "$(ideas due | jq -c 'map(.id)')" "not reviewed, answered no, later in the future, or done"
setfm "$FIFTH" later_until 2026-01-01
assert_has "\"$FIFTH\"" "$(ideas due | jq -c 'map(.id)')" "a later date that has passed makes it due again"
assert_eq "[\"$THIRD\",\"$FOURTH\"]" "$(ideas due --limit 1 --id "$THIRD" --id "$FOURTH" | jq -c 'map(.id)')" "--id returns those ideas whatever their state or the limit"

echo "ideas record"
printf 'It exists: atuin does this.\n' >"$SANDBOX/review.md"
ideas record "$FIRST" --verdict stale --summary "atuin already does it" --file "$SANDBOX/review.md"; RC=$?
assert_eq "0|reviewed|stale|atuin already does it|$(date +%F)" "$RC|$(fm "$FIRST" status)|$(fm "$FIRST" verdict)|$(fm "$FIRST" summary)|$(fm "$FIRST" reviewed_on)" "record writes status, verdict, summary and the date"
assert_has "It exists: atuin does this." "$(cat "$IDEAS_DIR/$FIRST.md")" "and the review body"
assert_has "| $FIRST | reviewed | stale |" "$(cat "$IDEAS_DIR/index.md")" "and the index row"
cp "$IDEAS_DIR/$SECOND.md" "$SANDBOX/before.md"
ideas record "$SECOND" --verdict maybe --summary x --file "$SANDBOX/review.md"; RC=$?
assert_eq "2|same" "$RC|$(cmp -s "$SANDBOX/before.md" "$IDEAS_DIR/$SECOND.md" && echo same || echo changed)" "a bad verdict exits 2 and writes nothing"
ideas record I-999 --verdict stale --summary x --file "$SANDBOX/review.md"; assert_eq "1" "$?" "an unknown id exits 1"
ideas sync >/dev/null
assert_eq "reviewed|stale" "$(fm "$FIRST" status)|$(fm "$FIRST" verdict)" "a later sync keeps the review"

echo "ideas answer"
ideas answer "$SECOND" later; assert_eq "later|$(date_add 7)" "$(fm "$SECOND" answer)|$(fm "$SECOND" later_until)" "later sets the date 7 days on"
ideas answer "$SIXTH" later --days 2; assert_eq "$(date_add 2)" "$(fm "$SIXTH" later_until)" "--days changes it"
assert_has "\"$SECOND\"" "$(IDEAS_TODAY=$(date_add 8) "$SCRIPT" due | jq -c 'map(.id)')" "and it is due again after that date"
ideas answer "$FIRST" yes; assert_eq "yes|$(date +%F)" "$(fm "$FIRST" answer)|$(fm "$FIRST" answered_on)" "yes records the answer only"
ideas answer "$FIRST" maybe; assert_eq "2" "$?" "a bad answer exits 2"

echo "ideas — the lock"
mkdir -p "$IDEAS_DIR/.lock"; sleep 30 & HOLDER=$!; echo "$HOLDER" >"$IDEAS_DIR/.lock/pid"
( sleep 1; kill "$HOLDER" 2>/dev/null ) &
ideas record "$SIXTH" --verdict elaborate --summary "which shell?" --file "$SANDBOX/review.md"; RC=$?
assert_eq "0|elaborate" "$RC|$(fm "$SIXTH" verdict)" "concurrent record waits for the holder, then writes"
assert_eq "no" "$([ -d "$IDEAS_DIR/.lock" ] && echo yes || echo no)" "and releases the lock"
mkdir -p "$IDEAS_DIR/.lock"; echo 999999 >"$IDEAS_DIR/.lock/pid"
ideas answer "$SIXTH" no; assert_eq "0|no" "$?|$(fm "$SIXTH" answer)" "a dead holder's lock is taken over"

echo "final review fixes"
start '- [ ] reviewed then later\n'
RL="$(id_of 'reviewed then later')"
ideas record "$RL" --verdict actionable --summary "do it" --file "$SANDBOX/review.md"
ideas answer "$RL" later --days 2
assert_eq "[]" "$(ideas due | jq -c 'map(.id)')" "a reviewed idea answered later is not due before its date"
assert_eq "[\"$RL\"]" "$(IDEAS_TODAY=$(date_add 3) "$SCRIPT" due | jq -c 'map(.id)')" "and is due again once the date has passed"
IDEAS_TODAY=$(date_add 3) "$SCRIPT" record "$RL" --verdict elaborate --summary "asked again" --file "$SANDBOX/review.md"
assert_eq "||" "$(fm "$RL" answer)|$(fm "$RL" answered_on)|$(fm "$RL" later_until)" "a re-review clears the old answer: the new review waits for a new one"
assert_eq "[]" "$(IDEAS_TODAY=$(date_add 3) "$SCRIPT" due | jq -c 'map(.id)')" "a re-reviewed idea is not due again while its new review waits for an answer"
printf '# ideas\n\n## review & implement:\n\n- [ ] reviewed then later\n- [ ] a brand new idea\n' >"$IDEAS_FILE"
assert_has "a brand new idea" "$(ideas due --sync --limit 3 | jq -r '.[].text')" "due --sync picks up a line added since the last sync"
printf '# ideas\n\n* * *\n\n## implemented:\n\n- plain implemented line\n' >"$IDEAS_FILE"; reset; ideas sync >/dev/null
assert_eq "done" "$(fm "$(id_of 'plain implemented line')" status)" "a plain bullet under implemented is done, never reviewed"
assert_eq "1" "$(ls "$IDEAS_DIR"/I-*.md | wc -l | tr -d ' ')" "a * * * rule is not an idea"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
