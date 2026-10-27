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

setfm() { sed -i '' "s|^$2:.*|$2: $3|" "$IDEAS_DIR/$1.md"; } # id key value (stands in for record/answer)
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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
