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
export FRICTIONS_BIN="$SANDBOX/frictions" DECK="$SANDBOX/deck.json" CALLS="$SANDBOX/calls.log" STDINS="$SANDBOX/stdins"
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
    n=$(( $(ls "$STDINS" | wc -l) + 1 ))
    cat >"$STDINS/$n"
    printf 'add key=%s source=%s opts=%s q=%s stdin=%s\n' "$key" "$src" "$opts" "$q" "$n" >>"$CALLS"
    jq --arg id "D-$n" --arg k "$key" --arg s "$src" --arg q "$q" '. + [{id: $id, key: $k, status: "open", source: $s, question: $q}]' "$DECK" >"$DECK.new" && mv "$DECK.new" "$DECK"
    echo "D-$n" ;;
  list) echo "list $*" >>"$CALLS"; cat "$DECK" ;;
  withdraw) echo "withdraw $*" >>"$CALLS" ;;
  close) echo "close $*" >>"$CALLS"; jq --arg id "$1" 'map(select(.id != $id))' "$DECK" >"$DECK.new" && mv "$DECK.new" "$DECK" ;;
  count) echo "count $*" >>"$CALLS"; echo "7" ;;
esac
STUB
chmod +x "$FRICTIONS_BIN"
# a whoami that would leave a mark if a proposal's `whoami` were ever executed
printf '#!/bin/bash\ntouch "%s/whoami-ran"\n' "$SANDBOX" >"$SANDBOX/bin/whoami"; chmod +x "$SANDBOX/bin/whoami"
export PATH="$SANDBOX/bin:$PATH"

fld() { grep -m1 "^$2:" "$FRICTION_WIKI/$1.md" | sed "s/^$2: *//"; }
adds() { grep -c '^add ' "$CALLS"; }
call_for() { grep "^add key=$1 " "$CALLS" | head -1; }
stdin_for() { cat "$STDINS/$(call_for "$1" | sed 's/.* stdin=//')"; }
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

echo "count"
assert_eq "7" "$("$SCRIPT" count)" "count asks the deck"
"$SCRIPT" count --badge >/dev/null; assert_has "count --badge" "$(cat "$CALLS")" "count passes --badge on"

echo "jq missing"
mkdir -p "$SANDBOX/nojq"
OUT="$(PATH="$SANDBOX/nojq" /bin/bash "$SCRIPT" sync --date 2026-10-20 2>&1)"; rc=$?
assert_eq "1" "$rc" "exits 1"
assert_eq "1" "$(wc -l <<<"$OUT" | tr -d ' ')" "one line"
assert_has "jq" "$OUT" "naming jq"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
