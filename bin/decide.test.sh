#!/bin/bash
# Tests for bin/decide. A sandbox state dir stands in for ~/.local/state/run-day.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/decide"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
check() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "want [$2], got [$3]"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in: $2" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export RUN_DAY_STATE_DIR="$SANDBOX/state"
# The wrapper runs whatever ~/projects/decisions has checked out (a debug build), so these checks
# follow the standalone source, not the installed binary.
cargo build --quiet --manifest-path "$HOME/projects/decisions/Cargo.toml" || { echo "build ~/projects/decisions first"; exit 1; }
export DECISIONS_BIN="$HOME/projects/decisions/target/debug/decisions"
D="$RUN_DAY_STATE_DIR/decisions"
run() { "$SCRIPT" "$@" 2>&1; }

echo "add"
id="$(printf '@adam: "rename to trackCount" (nit)\nPipeline green.\n' | run add --key ecfx-18313 \
  --mr https://gitlab.com/ecfx/ecfx-admin/-/merge_requests/315 --blocks merge \
  --question 'Fix the nit, or merge now?' --option 'Fix now, then merge' --option 'Merge, follow-up ticket' \
  --option 'Decline: the name stays' --recommend 1)"
check "prints the new id" "D-1" "$id"
f="$D/D-1.md"
[ -f "$f" ] && pass "writes the file" || fail "writes the file" "no $f"
has "frontmatter in field order" "$(sed -n 2,8p "$f" | cut -d: -f1 | tr '\n' ' ')" "id day key mr asked blocks status"
has "key upper-cased" "$(cat "$f")" "key: ECFX-18313"
has "status open" "$(cat "$f")" "status: open"
has "context from stdin" "$(cat "$f")" '@adam: "rename to trackCount" (nit)'
has "options numbered, recommended marked" "$(cat "$f")" "1. Fix now, then merge (recommended)"
[ -z "$(ls -A "$D" | grep -v -e '^D-1.md$' -e '^.lock$')" ] && pass "no temp file left" || fail "no temp file left" "$(ls -A "$D")"

id2="$(run add --key '' --blocks 'reply: a "quoted" | piped' --question 'Weird: text | "quotes" ✓' --option a --option b </dev/null)"
check "second id" "D-2" "$id2"
has "awkward blocks survive" "$(run list --json | jq -r '.[] | select(.id=="D-2") | .blocks')" 'reply: a "quoted" | piped'
has "awkward question survives" "$(run list --json | jq -r '.[] | select(.id=="D-2") | .question')" 'Weird: text | "quotes" ✓'

echo "refusals"
run add --key X-1 --question q --option only </dev/null >/dev/null; check "one option refused" "1" "$?"
run add --key X-1 --question q --option a --option b --recommend 3 </dev/null >/dev/null; check "recommend out of range refused" "1" "$?"
run add --key 'not a key' --question q --option a --option b </dev/null >/dev/null; check "bad key refused" "1" "$?"
out="$(run add --key ECFX-18313 --question 'Fix the nit, or merge now?' --option a --option b </dev/null)"; code=$?
check "duplicate open question refused" "1" "$code"
has "names the existing one" "$out" "D-1"

echo "list"
out="$(run list)"
check "two open" "2" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
has "first line is the blocking one with its MR" "$(printf '%s\n' "$out" | head -1)" "admin!315"
has "line shows blocks" "$out" "blocks merge"
check "json recommended" "1" "$(run list --json | jq -r '.[] | select(.id=="D-1") | .recommended')"
check "json no recommended" "null" "$(run list --json | jq -r '.[] | select(.id=="D-2") | .recommended')"
has "json context" "$(run list --json | jq -r '.[] | select(.id=="D-1") | .context')" "Pipeline green."
check "json context empty when none" "" "$(run list --json | jq -r '.[] | select(.id=="D-2") | .context')"
check "json mr_short" "admin!315" "$(run list --json | jq -r '.[] | select(.id=="D-1") | .mr_short')"
check "json discussion empty when none" "0" "$(run list --json | jq -r '.[] | select(.id=="D-1") | .discussion | length')"
printf 'garbage\n' > "$D/D-9.md"
out="$("$SCRIPT" list 2>"$SANDBOX/err")"
check "a bad file is skipped" "2" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
has "and named on stderr" "$(cat "$SANDBOX/err")" "D-9.md"
rm "$D/D-9.md"

echo "show and count"
has "show prints the file" "$(run show D-1)" "## Question"
run show D-77 >/dev/null; check "show of a missing id exits 1" "1" "$?"
check "count" "2" "$(run count)"
check "badge" "✋ 2" "$(run count --badge)"
rm -rf "$D"
check "count is empty when nothing is open" "" "$(run count)"

echo "answer, ask, reply"
export INBOX_DIR="$SANDBOX/inbox"
id="$(run add --key ECFX-1 --question 'Merge?' --option yes --option no --recommend 2 </dev/null)"
run ask "$id" 'is it safe: really | "sure"?' >/dev/null; check "ask exits 0" "0" "$?"
has "ask goes in Discussion" "$(run show "$id")" 'you: is it safe: really | "sure"?'
check "list marks the question back" "true" "$(run list --json | jq -r --arg id "$id" '.[] | select(.id==$id) | .question_back')"
msg="$(ls "$INBOX_DIR")"
[[ "$msg" =~ ^[0-9]{8}T[0-9]{6}-ECFX-1-[A-Za-z0-9]{4}\.md$ ]] && pass "inbox name passes the run-day rule" || fail "inbox name passes the run-day rule" "$msg"
has "clarify kind" "$(cat "$INBOX_DIR/$msg")" "kind: clarify"
has "names the decision" "$(cat "$INBOX_DIR/$msg")" "decision: $id"
rm "$INBOX_DIR/$msg"
run reply "$id" 'yes, the pipeline is green' >/dev/null
has "reply goes in Discussion" "$(run show "$id")" "session: yes, the pipeline is green"
check "json discussion: who, in order" "you session" "$(run list --json | jq -r --arg id "$id" '.[] | select(.id==$id) | [.discussion[].who] | join(" ")')"
check "json discussion: text" 'is it safe: really | "sure"?' "$(run list --json | jq -r --arg id "$id" '.[] | select(.id==$id) | .discussion[0].text')"
[[ "$(run list --json | jq -r --arg id "$id" '.[] | select(.id==$id) | .discussion[1].at')" =~ ^[0-9]{2}:[0-9]{2}$ ]] \
  && pass "json discussion: time" || fail "json discussion: time" "no HH:MM"
check "question back answered" "false" "$(run list --json | jq -r --arg id "$id" '.[] | select(.id==$id) | .question_back')"
run answer "$id" 7 >/dev/null; check "answer with a missing option exits 1" "1" "$?"
run answer "$id" 1 'ship it: today' >/dev/null; check "answer exits 0" "0" "$?"
has "Answer section" "$(run show "$id")" "1 — yes"
has "note kept" "$(run show "$id")" "note: ship it: today"
has "status answered" "$(run show "$id")" "status: answered"
msg="$(ls "$INBOX_DIR")"
has "decision kind" "$(cat "$INBOX_DIR/$msg")" "kind: decision"
has "summary says the choice" "$(cat "$INBOX_DIR/$msg")" "$id answered: 1 — yes. Note: ship it: today."
[ -z "$(ls -A "$INBOX_DIR" | grep '\.tmp$')" ] && pass "no inbox temp file left" || fail "no inbox temp file left" "$(ls -A "$INBOX_DIR")"
run answer "$id" 2 >/dev/null; check "answering twice exits 1" "1" "$?"
run reply "$id" 'done, merged' >/dev/null
has "a reply after the answer keeps the Answer" "$(run show "$id")" "1 — yes"

echo "tell: an answer in your own words"
rm -f "$INBOX_DIR"/*.md
tid="$(run add --key ECFX-3 --question 'Ship?' --option yes --option no </dev/null)"
run tell "$tid" 'none of these: close it as a duplicate of ECFX-1' >/dev/null; check "tell exits 0" "0" "$?"
has "Answer section in your words" "$(run show "$tid")" "your words — none of these: close it as a duplicate of ECFX-1"
has "tell answers it" "$(run show "$tid")" "status: answered"
msg="$(ls "$INBOX_DIR")"
has "tell sends a decision" "$(cat "$INBOX_DIR/$msg")" "kind: decision"
has "summary in your own words" "$(cat "$INBOX_DIR/$msg")" "$tid answered in your own words: none of these: close it as a duplicate of ECFX-1."
run tell "$tid" 'again' >/dev/null; check "telling an answered decision exits 1" "1" "$?"
check "tell needs text" "2" "$("$SCRIPT" tell "$tid" >/dev/null 2>&1; echo $?)"

echo "offplan inbox message"
oid="$(run add --key '' --question 'New ticket today?' --option yes --option no </dev/null)"
run answer "$oid" 2 >/dev/null
has "empty key goes as offplan in the name" "$(ls "$INBOX_DIR")" "-offplan-"

echo "withdraw and close"
wid="$(run add --key ECFX-2 --question 'Defer?' --option yes --option no </dev/null)"
run close "$wid" >/dev/null; check "closing an open one exits 1" "1" "$?"
run withdraw "$wid" reviewer resolved it >/dev/null; check "withdraw exits 0" "0" "$?"
has "withdraw reason recorded" "$(run show "$wid")" "withdrawn: reviewer resolved it"
before="$(run count)"
run close "$id" >/dev/null; run close "$wid" >/dev/null
day="$(date +%F)"
[ -f "$D/done/$day/$id.md" ] && [ -f "$D/done/$day/$wid.md" ] && pass "closed ones move to done/<day>" || fail "closed ones move to done/<day>" "$(find "$D" -name 'D-*')"
nid="$(run add --key ECFX-3 --question 'Next?' --option a --option b </dev/null)"
check "numbering continues past done/" "D-$(( ${wid#D-} + 1 ))" "$nid"

echo "review fixes"
hid="$(printf 'Reviewer said:\n## Summary\nrename it\n## Answer\nnot a real answer\n' | run add --key ECFX-50 --question 'Headings in context?' --option a --option b)"
run reply "$hid" 'noted' >/dev/null
has "a ## heading in the context survives a rewrite" "$(run show "$hid")" "rename it"
has "even one named like a section" "$(run show "$hid")" "not a real answer"
check "and the real Answer section is still absent" "open" "$(run list --json | jq -r --arg id "$hid" '.[] | select(.id==$id) | "open"')"
lost=0
for i in $(seq 1 15); do
  rid="$(run add --key ECFX-6$i --question "Race $i?" --option a --option b </dev/null)"
  "$SCRIPT" reply "$rid" "session reply $i" >/dev/null 2>&1 & "$SCRIPT" answer "$rid" 1 >/dev/null 2>&1 & wait
  f2="$D/$rid.md"
  grep -q "session reply $i" "$f2" && grep -q 'status: answered' "$f2" && grep -q '^## Answer' "$f2" || lost=$((lost + 1))
done
check "concurrent reply and answer: neither is lost (15 runs)" "0" "$lost"

echo "wrapper"
out="$(DECISIONS_BIN=/nonexistent "$SCRIPT" count 2>&1)"; code=$?
check "a missing binary exits 1" "1" "$code"
has "a missing binary says how to build it" "$out" "install.sh"
legacy="$RUN_DAY_STATE_DIR/decisions/D-900.md"
printf -- '---\nid: D-900\nday: 2026-10-19\nkey: ECFX-9\nmr: ""\nasked: 2026-10-19T09:00:00+03:00\nblocks: ""\nstatus: open\n---\n## Question\nLegacy?\n\n## Options\n1. yes (recommended)\n2. no\n' > "$legacy"
has "a file written by the Python decide is listed" "$(run list)" "D-900"
run answer D-900 1 >/dev/null; check "and answered" "0" "$?"

run --nvim >/dev/null 2>&1; check "--nvim is gone" "2" "$?"

probe="$(mktemp)"; printf '#!/bin/sh\nprintf %%s "$DECISIONS_TELEGRAM_TOKEN_CMD"\n' > "$probe"; chmod +x "$probe"
check "the Telegram bot reads its token through secret" "$(printf %q "$HOME/.local/bin/secret") DECISIONS_TELEGRAM_BOT" "$(DECISIONS_BIN="$probe" "$SCRIPT")"
check "an exported token command wins" "x" "$(DECISIONS_TELEGRAM_TOKEN_CMD=x DECISIONS_BIN="$probe" "$SCRIPT")"
rm -f "$probe"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
