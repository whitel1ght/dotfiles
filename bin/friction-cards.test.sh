#!/bin/bash
# Tests for bin/friction-cards. The deck is a stub `frictions` that logs every call and its
# stdin and keeps its open cards in a JSON file; the ledger lives in a sandbox, so nothing
# touches ~/wiki, ~/.local/state or the real deck.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/friction-cards"
LEDGER="$TEST_DIR/friction-ledger"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export FRICTION_WIKI="$SANDBOX/friction" COACH_STATE_DIR="$SANDBOX/coach" FRICTION_LEDGER="$LEDGER"
export SANDBOX FRICTIONS_BIN="$SANDBOX/frictions" DECK="$SANDBOX/deck.json" CALLS="$SANDBOX/calls.log" STDINS="$SANDBOX/stdins"
mkdir -p "$STDINS" "$SANDBOX/bin"
echo '[]' >"$DECK"; : >"$CALLS"

# The deck: add prints D-<n> and records the card; list --json answers from $DECK (open cards:
# id, key, status, source, question); withdraw is only logged; close drops the card.
cat >"$FRICTIONS_BIN" <<'STUB'
#!/bin/bash
set -u
cmd="$1"; shift
case "$cmd" in
  add)
    key="" src="" q="" opts=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --key) key="$2"; shift ;; --source) src="$2"; shift ;; --question) q="$2"; shift ;;
        --option) opts="$opts${opts:+|}$2"; shift ;; --recommend) shift ;;
      esac
      shift
    done
    if [ -f "$SANDBOX/add.fail" ] && grep -qx "$key" "$SANDBOX/add.fail"; then echo "deck refused $key" >&2; exit 1; fi
    n=$(( $(ls "$STDINS" | wc -l) + 1 ))
    cat >"$STDINS/$n"
    printf 'add key=%s source=%s opts=%s q=%s stdin=%s\n' "$key" "$src" "$opts" "$q" "$n" >>"$CALLS"
    jq --arg id "D-$n" --arg k "$key" --arg s "$src" --arg q "$q" '. + [{id: $id, key: $k, status: "open", source: $s, question: $q}]' "$DECK" >"$DECK.new" && mv "$DECK.new" "$DECK"
    echo "D-$n" ;;
  list) echo "list $*" >>"$CALLS"; cat "$DECK" ;;
  withdraw) echo "withdraw $*" >>"$CALLS" ;;
  close) echo "close $*" >>"$CALLS"; [ ! -f "$SANDBOX/close.fail" ] || exit 1; jq --arg id "$1" 'map(select(.id != $id))' "$DECK" >"$DECK.new" && mv "$DECK.new" "$DECK" ;;
  count) echo "count $*" >>"$CALLS"; echo "7" ;;
esac
STUB
chmod +x "$FRICTIONS_BIN"
# a whoami that would leave a mark if a proposal's `whoami` were ever executed
printf '#!/bin/bash\ntouch "%s/whoami-ran"\n' "$SANDBOX" >"$SANDBOX/bin/whoami"; chmod +x "$SANDBOX/bin/whoami"
export PATH="$SANDBOX/bin:$PATH"

# coach-fix stub: logs its arguments; fails with "boom" while cf.fail exists; sleeps while cf.sleep exists
export COACH_FIX="$SANDBOX/cf" CF_LOG="$SANDBOX/cf.log" FAKE_TMUX_DIR="$SANDBOX/tmux" COACH_HARNESS=claude
: >"$CF_LOG"; mkdir -p "$FAKE_TMUX_DIR"
cat >"$COACH_FIX" <<'STUB'
#!/bin/bash
echo "$*" >>"$CF_LOG"
[ ! -f "$SANDBOX/cf.sleep" ] || { echo $$ >"$SANDBOX/cf.pid"; exec sleep 30; }
[ ! -f "$SANDBOX/cf.fail" ] || { echo "first line" >&2; echo "boom" >&2; exit 1; }
STUB
chmod +x "$COACH_FIX"
cat >"$SANDBOX/bin/tmux" <<'STUB'
#!/bin/bash
d="$FAKE_TMUX_DIR"
[ ! -e "$d/noserver" ] || { echo "no server running" >&2; exit 1; }
case "$1" in
  list-sessions) echo "main: 1 windows" ;;
  list-windows) cat "$d/windows" 2>/dev/null ;;
  new-window) shift; name="" dir=""
    while [ $# -gt 0 ]; do case "$1" in -d) ;; -n) name="$2"; shift ;; -c) dir="$2"; shift ;; *) break ;; esac; shift; done
    echo "$name" >>"$d/windows"; printf '%s|%s\n' "$name" "$*" >>"$d/log" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$SANDBOX/bin/tmux"

fld() { grep -m1 "^$2:" "$FRICTION_WIKI/$1.md" | sed "s/^$2: *//"; }
adds() { grep -c '^add ' "$CALLS"; }
call_for() { grep "^add key=$1 " "$CALLS" | head -1; }
stdin_for() { cat "$STDINS/$(call_for "$1" | sed 's/.* stdin=//')"; }
last_stdin_for() { cat "$STDINS/$(grep "^add key=$1 " "$CALLS" | tail -1 | sed 's/.* stdin=//')"; }
sync() { "$SCRIPT" sync --date 2026-10-20 2>"$SANDBOX/err"; }
# groups as "sig|kind|count"
groups() { printf '%s\n' "$@" | jq -Rn '{date: "2026-10-10", groups: [inputs | split("|") | {sig: .[0], source: "x", kind: .[1], count: (.[2] | tonumber), keys: [], confidence: "high",
  samples: ["sample " + .[0]], evidence: []}]}' >"$SANDBOX/g.json"; "$LEDGER" apply --date 2026-10-10 --mine-json "$SANDBOX/g.json" >/dev/null; }
propose() { "$LEDGER" set "$1" --status proposed --proposal-file "$2" --date 2026-10-12; }

groups "k:tool:a|tool|2" "k:tool:b|tool|2" "k:tool:c|tool|2" "k:tool:d|tool|2" "k:tool:e|tool|2" "k:tool:f|tool|2" "k:tool:g|tool|2" "k:tool:h|tool|2"
printf 'Tighten the thing\n\n## Change\n- a → b\n' >"$SANDBOX/p1.md"

echo "sync: two eligible entries"
propose F-001 "$SANDBOX/p1.md"; propose F-002 "$SANDBOX/p1.md"
OUT="$(sync)"
assert_eq "2" "$(adds)" "two add calls"
assert_has "key=F-001 source=coach:suggestion opts=Apply|Ignore|Later q=F-001 · Tighten the thing" "$(call_for F-001)" "F-001: key, source, three options, question"
assert_has "key=F-002 source=coach:suggestion opts=Apply|Ignore|Later" "$(call_for F-002)" "F-002: key, source, three options"
assert_eq "offered|offered" "$(fld F-001 status)|$(fld F-002 status)" "ledger entries are now offered"
assert_eq "2" "$(grep -c '^filed' <<<"$OUT")" "one line printed per card filed"
assert_has "Before → after" "$(stdin_for F-001)" "the context labels the change"
assert_has "a → b" "$(stdin_for F-001)" "the context shows the change line"

echo "sync: dedupe"
sync >/dev/null
assert_eq "2" "$(adds)" "a second sync files nothing"

echo "sync: two at once"
propose F-003 "$SANDBOX/p1.md"; propose F-004 "$SANDBOX/p1.md"
sync >/dev/null & sync >/dev/null & wait
assert_eq "1 1" "$(grep -c '^add key=F-003 ' "$CALLS") $(grep -c '^add key=F-004 ' "$CALLS")" "each card is filed once"
assert_eq "4" "$(adds)" "four cards in all"
[ ! -d "$COACH_STATE_DIR/.cards.lock" ] && pass "lock released" || fail "lock released" "still held"

echo "sync: a dead holder's lock"
mkdir -p "$COACH_STATE_DIR/.cards.lock"; echo 999999 >"$COACH_STATE_DIR/.cards.lock/pid"
sync >/dev/null; assert_eq "0" "$?" "taken over"

echo "sync: text from the ledger stays text"
printf 'Run `whoami` then $(id) and "quotes"\nsecond $line \\ with `tick`\n\nthird; rm -rf /\n' >"$SANDBOX/p5.md"
propose F-005 "$SANDBOX/p5.md"
sync >/dev/null
PROP="$(cat "$SANDBOX/p5.md")"
case "$(stdin_for F-005)" in *"$PROP"*) pass "the proposal arrives byte-for-byte on stdin" ;; *) fail "proposal on stdin" "$(stdin_for F-005)" ;; esac
assert_has 'q=F-005 · Run `whoami` then $(id) and "quotes"' "$(call_for F-005)" "the question is one line"
[ ! -e "$SANDBOX/whoami-ran" ] && pass "nothing from the proposal was executed" || fail "executed" "whoami ran"

echo "sync: safety and nochange"
printf 'Loosen the permission guard\n\n## Change\n- deny Bash → allow Bash\n- keep rule 2\n' >"$SANDBOX/p6.md"
printf 'Loosen the docker guard\n' >"$SANDBOX/p7.md"
propose F-006 "$SANDBOX/p6.md"; propose F-007 "$SANDBOX/p7.md"
sync >/dev/null
assert_eq "**Loosens a safety control**" "$(stdin_for F-006 | head -1)" "a safety context starts with the warning"
assert_has "- deny Bash → allow Bash" "$(stdin_for F-006)" "and lists its change lines"
assert_has "- keep rule 2" "$(stdin_for F-006)" "all of them"
assert_has "opts=Ignore|Later q=" "$(call_for F-007)" "a nochange card has Ignore and Later only"
assert_has 'Press `a` to ask the coach for the exact change.' "$(stdin_for F-007)" "and tells how to ask"

echo "sync: a rule and a file-held credential"
printf 'Add a rule\nDirection: Always run the tests first\nScope: dotfiles\n' >"$SANDBOX/p8.md"
groups "k:restated:rule|restated|2" "k:secret:key|secret|2"
propose F-009 "$SANDBOX/p8.md"; propose F-010 "$SANDBOX/p1.md"
sync >/dev/null
assert_has "opts=Apply: add the rule|Ignore|Later" "$(call_for F-009)" "rule options"
assert_has "source=coach:secret opts=Done (I did the steps)|Later|Ignore" "$(call_for F-010)" "secret-card options"

echo "sync: closing cards"
D1="$(jq -r '.[] | select(.key == "F-001") | .id' "$DECK")"
"$LEDGER" set F-001 --status fixed --date 2026-10-21
OUT="$(sync)"
assert_has "withdraw $D1 " "$(cat "$CALLS")" "a card whose entry was fixed is withdrawn"
assert_has "close $D1" "$(cat "$CALLS")" "and closed"
assert_has "closed $D1" "$OUT" "one line says so"
assert_eq "0" "$(jq --arg id "$D1" '[.[] | select(.id == $id)] | length' "$DECK")" "it left the deck"
assert_eq "1" "$(jq '[.[] | select(.key == "F-002")] | length' "$DECK")" "an offered entry's card stays"

echo "sync: results"
groups "k:tool:l|tool|2" "k:tool:m|tool|2" "k:tool:n|tool|2"
"$LEDGER" set F-011 --status landed --fix abc1234 --date 2026-10-20
"$LEDGER" set F-012 --status failed --reason "tests failed" --date 2026-10-20
"$LEDGER" set F-013 --status failed --reason "needs the user to log in" --date 2026-10-20
before="$(adds)"
sync >/dev/null
assert_eq "$((before + 3))" "$(adds)" "each result is filed"
assert_has "source=coach:landed opts=OK " "$(call_for F-011)" "landed: OK"
assert_has "git revert abc1234" "$(stdin_for F-011)" "landed context says how to undo it"
assert_has "opts=Retry|Ignore " "$(call_for F-012)" "retryable failure: Retry and Ignore"
assert_has "source=coach:failed opts=OK " "$(call_for F-013)" "a failure the user must fix: OK"
assert_has "tests failed" "$(stdin_for F-012)" "failed context gives the reason"
assert_eq "2026-10-20" "$(fld F-011 result_reported_on)" "the entry gets result_reported_on"
sync >/dev/null
assert_eq "$((before + 3))" "$(adds)" "a result is filed once"
assert_eq "3" "$(jq '[.[] | select(.key == "F-011" or .key == "F-012" or .key == "F-013")] | length' "$DECK")" "result cards stay open while landed or failed"
"$LEDGER" set F-011 --status fixed --date 2026-10-21
sync >/dev/null
assert_eq "0" "$(jq '[.[] | select(.key == "F-011")] | length' "$DECK")" "a result card closes once its entry moves on"

TODAY="$(date +%F)"
deck_id() { jq -r --arg k "$1" '[.[] | select(.key == $k)][0].id // empty' "$DECK"; }
event() { # kind key option [text]: one hook line for the open card on key
  local d; d="$(deck_id "$2")"
  jq -nc --arg e "$1" --arg id "$d" --arg k "$2" --arg s "$(jq -r --arg k "$2" '[.[] | select(.key == $k)][0].source' "$DECK")" \
    --arg o "${3:-}" --arg t "${4:-}" '{event: $e, id: $id, key: $k, source: $s, option: (if $o == "" then null else ($o | tonumber) end), note: null, text: (if $t == "" then null else $t end), at: "x"}'
}
hook() { local f="$SANDBOX/ev.json"; event "$@" >"$f"; "$SCRIPT" handle "$f"; } # the hook's work, run synchronously
windows_log() { cat "$FAKE_TMUX_DIR/log" 2>/dev/null; }

echo "review: a failing add does not block the next card"
groups "k:tool:o1|tool|2" "k:tool:o2|tool|2"
propose F-014 "$SANDBOX/p1.md"; propose F-015 "$SANDBOX/p1.md"
echo F-014 >"$SANDBOX/add.fail"
sync >/dev/null; rc=$?
assert_eq "0" "$rc" "sync still exits 0"
assert_eq "1" "$(jq '[.[] | select(.key == "F-015")] | length' "$DECK")" "the next card is filed"
assert_eq "0" "$(jq '[.[] | select(.key == "F-014")] | length' "$DECK")" "the failing one is not"
assert_has "F-014" "$(cat "$SANDBOX/err")" "one line names the entry"
assert_eq "1" "$(wc -l <"$SANDBOX/err" | tr -d ' ')" "and only one line"
rm "$SANDBOX/add.fail"; sync >/dev/null
assert_eq "1" "$(jq '[.[] | select(.key == "F-014")] | length' "$DECK")" "the failed one is filed on the next sync"

echo "review: closed is only echoed when the close worked"
D14="$(deck_id F-014)"; "$LEDGER" set F-014 --status declined --date 2026-10-21
touch "$SANDBOX/close.fail"
OUT="$(sync)"
case "$OUT" in *"closed $D14"*) fail "no false close line" "$OUT" ;; *) pass "no false close line" ;; esac
rm "$SANDBOX/close.fail"
OUT="$(sync)"; assert_has "closed $D14" "$OUT" "echoed once the close worked"

echo "review: a lock dir with no pid file"
mkdir -p "$COACH_STATE_DIR/.cards.lock"; touch -t 202601010000 "$COACH_STATE_DIR/.cards.lock"
SECONDS=0; sync >/dev/null; rc=$?
assert_eq "0" "$rc" "an old pid-less lock is taken over"
[ "$SECONDS" -lt 10 ] && pass "without waiting it out" || fail "without waiting it out" "${SECONDS}s"

echo "review: a failed result shows the reason once"
assert_eq "1" "$(stdin_for F-012 | grep -c 'tests failed')" "the reason appears once"

echo "hook: apply"
hook answered F-002 1
assert_eq "landing" "$(fld F-002 status)" "suggestion Apply -> landing"
assert_eq "enqueue F-002" "$(grep 'enqueue F-002' "$CF_LOG")" "coach-fix enqueue, no flag"
assert_eq "" "$(deck_id F-002)" "the card is closed"
hook answered F-006 1
assert_eq "enqueue F-006 --approved-safety" "$(grep 'enqueue F-006' "$CF_LOG")" "a safety card enqueues with --approved-safety"
hook answered F-009 1
assert_eq "fixed" "$(fld F-009 status)" "a rule card is fixed"
assert_has "D-" "$(fld F-009 fix)" "a rule card makes a D-NNN"
assert_eq "" "$(grep 'F-009' "$CF_LOG")" "and never calls coach-fix"
assert_eq "" "$(deck_id F-009)" "its card is closed"

echo "hook: other answers"
hook answered F-003 3; assert_eq "$TODAY" "$(fld F-003 offered_on)" "Later -> offered_on today"
hook answered F-004 2; assert_eq "declined" "$(fld F-004 status)" "Ignore -> declined"
hook answered F-010 1; assert_eq "fixed" "$(fld F-010 status)" "Done on a secret card -> fixed"
assert_eq "" "$(grep 'F-010' "$CF_LOG")" "and never calls coach-fix"
assert_eq "" "$(deck_id F-010)" "the secret card is closed"
hook answered F-012 1; assert_eq "retry F-012" "$(grep 'F-012' "$CF_LOG")" "Retry on a failed result -> coach-fix retry"
hook answered F-013 1
assert_eq "" "$(deck_id F-013)" "OK on a result card closes it"
assert_eq "" "$(grep 'F-013' "$CF_LOG")" "and calls nothing"

echo "hook: a refused answer"
"$LEDGER" set F-015 --status landing --date 2026-10-21
hook answered F-015 1
assert_eq "" "$(deck_id F-015)" "the card is closed"
assert_eq "landing" "$(fld F-015 status)" "the ledger is unchanged"
assert_eq "" "$(grep 'F-015' "$CF_LOG")" "no coach-fix call"
assert_eq "1" "$(grep -c 'F-015' "$COACH_STATE_DIR/logs/cards.log")" "one log line"

echo "hook: coach-fix fails"
groups "k:tool:q1|tool|2"
propose F-016 "$SANDBOX/p1.md"; sync >/dev/null
touch "$SANDBOX/cf.fail"
hook answered F-016 1
assert_eq "2" "$(grep -c "^add key=F-016 " "$CALLS")" "the card is filed again"
assert_has "could not queue the fix: boom" "$(fld F-016 reason)" "with the last stderr line as the reason"
assert_has "could not queue the fix: boom" "$(last_stdin_for F-016 | head -1)" "the re-filed card starts with the note"
rm "$SANDBOX/cf.fail"

echo "hook: returns fast, detached"
groups "k:tool:r1|tool|2"
propose F-017 "$SANDBOX/p1.md"; sync >/dev/null
touch "$SANDBOX/cf.sleep"; rm -f "$SANDBOX/cf.pid"
start=$(date +%s); event answered F-017 1 | "$SCRIPT" hook; took=$(( $(date +%s) - start ))
[ "$took" -lt 3 ] && pass "the hook returns in under 3 s" || fail "fast hook" "${took}s"
i=0; while [ ! -s "$SANDBOX/cf.pid" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
[ -s "$SANDBOX/cf.pid" ] && pass "the detached work reached coach-fix" || fail "detached work" "coach-fix never started"
kill "$(cat "$SANDBOX/cf.pid" 2>/dev/null)" 2>/dev/null
rm -f "$SANDBOX/cf.sleep"
i=0; while pgrep -f "handle $COACH_STATE_DIR" >/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
pgrep -f "handle $COACH_STATE_DIR" >/dev/null && fail "no orphan" "handle still running" || pass "no process outlives the test"
sync >/dev/null # the killed coach-fix left F-017 proposed; settle its card now

echo "reply: asked"
D7="$(deck_id F-007)"
hook asked F-007 "" "why not a config fix?"
[ -f "$COACH_STATE_DIR/replies/F-007.json" ] && [ -n "$(windows_log)" ] && pass "a job file and a window" || fail "job" "$(windows_log)"
assert_eq '["why not a config fix?"]' "$(jq -c .questions "$COACH_STATE_DIR/replies/F-007.json")" "the job file holds the question"
assert_eq "$D7" "$(jq -r .card "$COACH_STATE_DIR/replies/F-007.json")" "and the card"
assert_has "reply-F-007|" "$(windows_log)" "window reply-F-007"
assert_has "claude '/daily:fix-friction F-007 --revise'" "$(windows_log)" "running the revise prompt"
assert_eq "$D7" "$(deck_id F-007)" "the card stays open"
hook told F-007 "" "and what about a hook?"
assert_eq "2" "$(jq ".questions | length" "$COACH_STATE_DIR/replies/F-007.json")" "a second question is appended"
assert_eq "1" "$(windows_log | wc -l | tr -d ' ')" "no second window"

echo "reply: a permission flag"
groups "k:tool:t1|tool|2"
propose F-018 "$SANDBOX/p1.md"; sync >/dev/null
COACH_HARNESS="claude -p" "$SCRIPT" reply F-018 --card "$(deck_id F-018)" <<<"why?" >/dev/null 2>&1
assert_has "permission flag -p" "$(cat "$FRICTION_WIKI/F-018.md")" "unrevised with the permission-flag reason"
[ ! -f "$COACH_STATE_DIR/replies/F-018.json" ] && pass "no job file" || fail "no job file" "left"
assert_eq "1" "$(windows_log | wc -l | tr -d ' ')" "no window started"
assert_has "You asked" "$(last_stdin_for F-018 | head -1)" "the re-filed card shows the user's words"

echo "revised"
printf 'Use a config change instead\n\n## Change\n- old → new\n' >"$SANDBOX/p7b.md"; printf 'Because the hook cannot see it.\n' >"$SANDBOX/ans.md"
"$SCRIPT" revised F-007 --answer-file "$SANDBOX/ans.md" --proposal-file "$SANDBOX/p7b.md" >/dev/null
assert_has "Use a config change instead" "$(cat "$FRICTION_WIKI/F-007.md")" "the proposal is replaced"
assert_has "why not a config fix? / and what about a hook?" "$(cat "$FRICTION_WIKI/F-007.md")" "Discussion has both questions"
assert_has "Because the hook cannot see it." "$(cat "$FRICTION_WIKI/F-007.md")" "and the answer"
assert_has "withdraw $D7 " "$(cat "$CALLS")" "the old card is withdrawn"
NEW7="$(deck_id F-007)"; [ -n "$NEW7" ] && [ "$NEW7" != "$D7" ] && pass "a new card is filed" || fail "new card" "[$NEW7]"
assert_has "**You asked:** why not a config fix? / and what about a hook?" "$(last_stdin_for F-007)" "its context shows You asked"
[ ! -f "$COACH_STATE_DIR/replies/F-007.json" ] && pass "the job file is gone" || fail "job file" "left"

echo "tick: the watchdog"
groups "k:tool:u1|tool|2" "k:tool:u2|tool|2" "k:tool:u3|tool|2"
propose F-019 "$SANDBOX/p1.md"; propose F-020 "$SANDBOX/p1.md"; propose F-021 "$SANDBOX/p1.md"; sync >/dev/null
mkdir -p "$COACH_STATE_DIR/replies"
job() { jq -nc --arg id "$1" --arg c "$(deck_id "$1")" --argjson e "$(( $(date +%s) - $2 ))" '{id: $id, card: $c, questions: ["q"], started_epoch: $e}' >"$COACH_STATE_DIR/replies/$1.json"; }
job F-019 60; job F-020 2000; job F-021 10
printf 'reply-F-020\n' >"$FAKE_TMUX_DIR/windows"
"$SCRIPT" tick >/dev/null 2>&1
assert_has "the reply job ended without an answer" "$(cat "$FRICTION_WIKI/F-019.md")" "no window, 60 s: the card is re-filed with the reason"
assert_has "the reply job stalled in tmux window reply-F-020 (waiting on a prompt?)" "$(cat "$FRICTION_WIKI/F-020.md")" "window present, 2000 s: stalled"
assert_has "reply-F-020" "$(cat "$FAKE_TMUX_DIR/windows")" "the stalled window is left open"
[ -f "$COACH_STATE_DIR/replies/F-021.json" ] && pass "10 s old, no window: untouched" || fail "untouched" "job removed"
assert_eq "offered" "$(fld F-021 status)" "its entry is untouched"
[ ! -f "$COACH_STATE_DIR/replies/F-019.json" ] && pass "handled job files are gone" || fail "job file" "left"
rm -f "$COACH_STATE_DIR/replies/F-021.json" # it would age past the watchdog threshold while later tests run

echo "fix round: a late revision never undoes an answer"
groups "k:tool:v1|tool|2" "k:tool:v2|tool|2"
propose F-022 "$SANDBOX/p1.md"; propose F-023 "$SANDBOX/p1.md"; sync >/dev/null
job F-022 60
hook answered F-022 1
[ "$(fld F-022 status)" = landing ] && [ ! -f "$COACH_STATE_DIR/replies/F-022.json" ] && pass "answering Apply cancels the reply job" || fail "job cancelled" "$(fld F-022 status)"
before="$(adds)"
job F-022 60; "$SCRIPT" revised F-022 --answer-file "$SANDBOX/ans.md" >/dev/null 2>&1
assert_eq "landing" "$(fld F-022 status)" "a late revised leaves the entry landing"
assert_eq "$before" "$(adds)" "and files no card"
[ ! -f "$COACH_STATE_DIR/replies/F-022.json" ] && pass "the job file is gone" || fail "job file" "left"
job F-022 60; "$SCRIPT" tick >/dev/null 2>&1
assert_eq "landing" "$(fld F-022 status)" "a tick with a dead window leaves it landing"
assert_eq "$before" "$(adds)" "and files no card"
[ ! -f "$COACH_STATE_DIR/replies/F-022.json" ] && pass "job file gone after tick" || fail "job file" "left"

echo "fix round: a failed revise keeps the job and the card"
printf '#!/bin/bash\n[ "$1" = revise ] && exit 1\nexec "%s" "$@"\n' "$LEDGER" >"$SANDBOX/ledger-wrap"; chmod +x "$SANDBOX/ledger-wrap"
D23="$(deck_id F-023)"; job F-023 60
FRICTION_LEDGER="$SANDBOX/ledger-wrap" "$SCRIPT" tick >/dev/null 2>&1
[ -f "$COACH_STATE_DIR/replies/F-023.json" ] && pass "tick: the job file stays" || fail "job file" "gone"
assert_eq "$D23" "$(deck_id F-023)" "tick: the card stays open"
FRICTION_LEDGER="$SANDBOX/ledger-wrap" "$SCRIPT" unrevised F-023 --reason x >/dev/null 2>&1; rc=$?
assert_eq "1" "$rc" "direct: exits 1"
[ -f "$COACH_STATE_DIR/replies/F-023.json" ] && pass "direct: the job file stays" || fail "job file" "gone"
[ ! -d "$COACH_STATE_DIR/.cards.lock" ] && pass "the lock is released" || fail "lock" "held"

echo "hook: Ignore on a failed result"
groups "k:tool:w1|tool|2"
"$LEDGER" set F-024 --status failed --reason "tests failed" --date 2026-10-20
sync >/dev/null
assert_eq "Retry|Ignore" "$(call_for F-024 | sed 's/.*opts=\([^ ]*\) .*/\1/')" "the failed card offers Retry and Ignore"
hook answered F-024 2
assert_eq "" "$(deck_id F-024)" "Ignore closes the failed result card"
assert_eq "" "$(grep 'F-024' "$CF_LOG")" "and calls no coach-fix"

echo "count"
assert_eq "7" "$("$SCRIPT" count)" "count asks the deck"
"$SCRIPT" count --badge >/dev/null; assert_has "count --badge" "$(cat "$CALLS")" "count passes --badge on"

echo "hook: a failed retry comes back"
lastid() { ls "$FRICTION_WIKI" | sed -n 's/^\(F-[0-9]*\)\.md$/\1/p' | sort | tail -1; }
groups "k:tool:rt|tool|2"; RT="$(lastid)"
"$LEDGER" set "$RT" --status failed --reason "tests failed" --date 2026-10-20
sync >/dev/null
assert_eq "2026-10-20" "$(fld "$RT" result_reported_on)" "the failed result is reported"
touch "$SANDBOX/cf.fail"
hook answered "$RT" 1
rm "$SANDBOX/cf.fail"
assert_eq "2" "$(grep -c "^add key=$RT " "$CALLS")" "the failed result card is filed again"
assert_has "could not retry: boom" "$(last_stdin_for "$RT")" "its context carries the note"
assert_has "could not retry: boom" "$(fld "$RT" reason)" "the reason carries the last stderr line"

echo "sync: a stale cards listing"
groups "k:tool:st|tool|2"; ST="$(lastid)"
propose "$ST" "$SANDBOX/p1.md"
cat >"$SANDBOX/stale-ledger" <<'STUB'
#!/bin/bash
out="$("$LEDGER" "$@")"; rc=$?
if [ "$1" = cards ]; then "$LEDGER" set "$STALE_ID" --status landing --date 2026-10-20; fi
printf '%s\n' "$out"; exit $rc
STUB
chmod +x "$SANDBOX/stale-ledger"
FRICTION_LEDGER="$SANDBOX/stale-ledger" LEDGER="$LEDGER" STALE_ID="$ST" sync >"$SANDBOX/out"
assert_eq "landing" "$(fld "$ST" status)" "the entry stays landing"
assert_eq "" "$(deck_id "$ST")" "no card stays open for it"
assert_has "closed" "$(cat "$SANDBOX/out")" "one line says the card was closed"

echo "jq missing"
mkdir -p "$SANDBOX/nojq"
OUT="$(PATH="$SANDBOX/nojq" /bin/bash "$SCRIPT" sync --date 2026-10-20 2>&1)"; rc=$?
assert_eq "1" "$rc" "exits 1"
assert_eq "1" "$(wc -l <<<"$OUT" | tr -d ' ')" "one line"
assert_has "jq" "$OUT" "naming jq"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
