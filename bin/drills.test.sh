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

echo "drills check"
chk() { drills check --accept "$1" -- "$2"; }
A="friction-cards count"
assert_eq "ok" "$(chk "$A" 'friction-cards count')" "forms: the command"
assert_eq "ok" "$(chk "$A" 'friction-cards  count --json')" "forms: extra spaces and flags"
assert_eq "ok" "$(chk "$A" '"friction-cards" count')" "forms: quotes"
assert_eq "ok" "$(chk "$A" '~/.local/bin/friction-cards count')" "forms: a full path"
assert_eq "wrong" "$(chk "$A" 'friction-cards')" "forms: a required word missing"
assert_eq "wrong" "$(chk "$A" 'cards count')" "forms: another command"
assert_eq "wrong" "$(chk "$A" 'count friction-cards')" "forms: words out of order"
assert_eq "ok" "$(chk "words look gordian knot" 'w gordian knot')" "alias: expanded before matching"
assert_eq "wrong" "$(chk "words look gordian knot" 'w gordian')" "alias: still needs the arguments"
assert_eq "refuse" "$(chk "$A" 'friction-cards count; rm -rf ~/x')" "compound: ;"
assert_eq "refuse" "$(chk "$A" 'friction-cards count && git push')" "compound: &&"
assert_eq "refuse" "$(chk "$A" 'friction-cards count || true')" "compound: ||"
assert_eq "refuse" "$(chk "$A" 'friction-cards count &')" "compound: &"
assert_eq "refuse" "$(chk "$A" 'sudo friction-cards count')" "compound: sudo"
assert_eq "refuse" "$(chk "$A" 'env X=1 friction-cards count')" "compound: env"
assert_eq "refuse" "$(chk "$A" 'friction-cards count > out')" "compound: a redirect"
assert_eq "refuse" "$(chk "$A" 'friction-cards count $(rm x)')" "compound: a command substitution"
assert_eq "ok" "$(chk "cards due" 'cards due | head -3')" "pipe: into a reader"
assert_eq "refuse" "$(chk "cards due" 'cards due | sh')" "pipe: into anything else"
assert_eq "refuse" "$(chk "$A" 'friction-cards count "unclosed')" "a line the shell cannot parse"

echo "drills round"
D=2026-10-27
T0=1800000000
export DRILLS_NOW=$T0
jget() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1]))' "$1"; }
step() { drills step -- "$1"; }
graded() { sed -n 's/^- [0-9-]* grade \([0-3]\).*/\1/p' "$CARDS_DIR/$1.md" | tail -1; }
results() { cat "$DRILLS_STATE/$D.json" 2>/dev/null; }
reset
A1="$(drills add --goal "Count the friction cards." --cmd friction-cards --accept "friction-cards count" --run yes --date 2026-10-01)"
A2="$(drills add --goal "Open the hand-off window for ECFX-1." --cmd handoff-open --accept "handoff-open ECFX-1" --run no --date 2026-10-02)"
assert_eq "Goal: Count the friction cards." "$(drills start --date $D)" "start prints the first goal, oldest new drill first"
OUT="$(step 'cards count')"
assert_eq "wrong|False" "$(jget action <<<"$OUT")|$(jget done <<<"$OUT")" "a wrong line is wrong"
assert_has "friction-cards count" "$(jget message <<<"$OUT")" "and shows the right command"
OUT="$(step 'friction-cards count; rm -rf ~/x')"
assert_eq "refuse" "$(jget action <<<"$OUT")" "a compound line is refused"
OUT="$(step 'friction-cards count')"
assert_eq "run" "$(jget action <<<"$OUT")" "the right line after a miss runs"
assert_has "Goal: Open the hand-off window for ECFX-1." "$(jget message <<<"$OUT")" "and the next goal follows"
assert_eq "1" "$(graded "$A1")" "graded 1 after a miss"
OUT="$(step '?')"
assert_eq "show" "$(jget action <<<"$OUT")" "? shows the answer"
OUT="$(step 'handoff-open ECFX-1 ~/w')"
assert_eq "checked|True" "$(jget action <<<"$OUT")|$(jget done <<<"$OUT")" "a run-no drill is checked, and the last one ends the round"
assert_eq "0" "$(graded "$A2")" "graded 0 after the answer was shown"
assert_eq '{"right": 0, "total": 2}' "$(results)" "the day's results"
assert_eq "Drills: 0 right of 2" "$(drills finish)" "finish prints the round"
assert_eq "False" "$([ -e "$DRILLS_STATE/round.json" ] && echo True || echo False)" "and removes the round"
assert_eq "Drills: 0 right of 2" "$(drills finish)" "finish twice is safe"
OUT="$(step 'friction-cards count')"
assert_eq "True" "$(jget done <<<"$OUT")" "no round: done"

reset
A1="$(drills add --goal "Count the friction cards." --cmd friction-cards --accept "friction-cards count" --run yes --date 2026-10-01)"
drills start --date $D >/dev/null
OUT="$(step 'friction-cards count --json')"
assert_eq "run|True|2" "$(jget action <<<"$OUT")|$(jget done <<<"$OUT")|$(graded "$A1")" "first try: graded 2"
assert_eq '{"right": 1, "total": 1}' "$(results)" "and counted right"

reset
A1="$(drills add --goal "G1." --cmd a --accept "a one" --run yes --date 2026-10-01)"
A2="$(drills add --goal "G2." --cmd b --accept "b two" --run yes --date 2026-10-02)"
drills start --date $D >/dev/null
step 'a one; b' >/dev/null
OUT="$(step 'a one')"
assert_eq "2" "$(graded "$A1")" "a refused line is not a try"
OUT="$(DRILLS_NOW=$((T0 + 301)) step 'b two')"
assert_eq "run|True|2" "$(jget action <<<"$OUT")|$(jget done <<<"$OUT")|$(graded "$A2")" "timeout: the next right line is graded and ends the round"
drills finish >/dev/null

reset
A1="$(drills add --goal "G1." --cmd a --accept "a one" --run yes --date 2026-10-01)"
A2="$(drills add --goal "G2." --cmd b --accept "b two" --run yes --date 2026-10-02)"
drills start --date $D >/dev/null
step 'a one' >/dev/null
assert_eq '{"right": 1, "total": 1}|' "$(results)|$(graded "$A2")" "abandoned round: what was done is kept, the rest ungraded"
OUT="$(DRILLS_NOW=$((T0 + 301)) step 'nope')"
assert_eq "True|" "$(jget done <<<"$OUT")|$(graded "$A2")" "timeout on a wrong line ends the round, ungraded"

reset
assert_eq "no drills due" "$(drills start --date $D)" "no drills: says so"
assert_eq "False" "$([ -e "$DRILLS_STATE/round.json" ] && echo True || echo False)" "and writes no round"
G="$(drills add --goal "Due later." --cmd c --accept "c" --run yes --date 2026-10-01)"
drills start --date $D >/dev/null; step 'c' >/dev/null; drills finish >/dev/null
N="$(drills add --goal "New one." --cmd n --accept "n" --run yes --date 2026-10-20)"
assert_eq "Goal: New one." "$(drills start --date 2026-12-31)" "new drills come before reviewed ones"
drills finish >/dev/null
unset DRILLS_NOW

echo "drills stats"
reset
assert_eq "" "$(drills stats --date $D --line)" "--line prints nothing before the first drill card"
K="$(drills add --goal "Known." --cmd k --accept "k" --run yes)"
L="$(drills add --goal "Learning." --cmd l --accept "l" --run yes)"
sed -i '' 's/^interval: .*/interval: 25/' "$CARDS_DIR/$K.md"; sed -i '' 's/^interval: .*/interval: 3/' "$CARDS_DIR/$L.md"
mkdir -p "$DRILLS_STATE"
echo '{"right": 2, "total": 3}' >"$DRILLS_STATE/2026-10-25.json"
echo '{"right": 1, "total": 2}' >"$DRILLS_STATE/2026-10-26.json"
echo '{"right": 4, "total": 5}' >"$DRILLS_STATE/2026-10-27.json"
echo '{"right": 0, "total": 0}' >"$DRILLS_STATE/2026-10-23.json"
assert_eq '{"right": 4, "total": 5, "streak": 3}' "$(drills stats --date 2026-10-27 --json)" "the day's counts and the streak"
assert_eq "3" "$(drills stats --date 2026-10-28 --json | jget streak)" "the streak holds on a day with no round yet"
assert_eq "Drills: 4 right of 5 · streak 3 days" "$(drills stats --date 2026-10-27 --line)" "--line is one sentence for the diary"
assert_eq "Drills: 0 right of 0 · streak 0 days" "$(drills stats --date 2026-10-30 --line)" "a missed day ends the streak"
assert_eq "known|learning" "$(fm "$K" stage)|$(fm "$L" stage)" "a drill with an interval of 21 days or more is marked known"

echo "drills open"
TB="$SANDBOX/tbin"; TLOG="$SANDBOX/tmux.log"; mkdir -p "$TB"
cat >"$TB/tmux" <<'STUB'
#!/bin/bash
{ echo "--- tmux"; printf '%s\n' "$@"; } >>"$TMUX_LOG"
case "$1" in
  display-message) echo "main" ;;
  list-windows) printf '%b' "${FAKE_WINDOWS:-}" ;;
esac
exit 0
STUB
printf '#!/bin/sh\n[ -n "$FAKE_PANE" ] || exit 1\necho "$FAKE_PANE"\n' >"$TB/tmux-here"
chmod +x "$TB/tmux" "$TB/tmux-here"
topen() { : >"$TLOG"; PATH="$TB:$PATH" TMUX_LOG="$TLOG" DRILLS_TMUX_HERE="$TB/tmux-here" drills open --date $D; }
OUT="$(FAKE_PANE=%3 FAKE_WINDOWS='1 nvim\n2 claude\n' topen)"
assert_eq "opened main:drills" "$OUT" "opened in the caller's session"
assert_has "new-window
-t
=main:
-n
drills" "$(cat "$TLOG")" "as a window named drills"
assert_has "/drills window --date $D" "$(cat "$TLOG")" "running drills window for the day"
OUT="$(PATH="$TB:$PATH" TMUX_LOG="$TLOG" DRILLS_TMUX_HERE="$SANDBOX/missing" drills open --date $D)"; RC=$?
assert_eq "0|drills need tmux" "$RC|$OUT" "no tmux-here at all: the same line"
OUT="$(FAKE_PANE=%3 FAKE_WINDOWS='1 nvim\n4 drills\n' topen)"
assert_eq "focused main:drills" "$OUT" "an open drills window is focused instead"
assert_has "select-window
-t
=main:4" "$(cat "$TLOG")" "by its index"
OUT="$(FAKE_PANE= topen)"; RC=$?
assert_eq "0|drills need tmux" "$RC|$OUT" "no tmux: one line, exit 0, never a command to run"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
