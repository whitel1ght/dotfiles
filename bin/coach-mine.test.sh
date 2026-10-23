#!/bin/bash
# Tests for bin/coach-mine. Every input points into a sandbox, TZ is pinned to UTC+3
# and the fixtures (including a fake token) are written here, so nothing touches
# ~/.claude, ~/.pi, ~/.zsh_history or ~/wiki.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/coach-mine"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
yn() { jq -e "$2" <<<"$1" >/dev/null 2>&1 && echo yes || echo no; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export TZ=Etc/GMT-3
D=2026-10-15
CP="$SANDBOX/claude" PI="$SANDBOX/pi" WIKI="$SANDBOX/wiki" FW="$SANDBOX/friction" ZH="$SANDBOX/zsh_history"
mkdir -p "$CP/-proj" "$PI/--proj--" "$WIKI/notes" "$FW" "$SANDBOX/repo"

mine() { CLAUDE_PROJECTS_DIR="$CP" PI_SESSIONS_DIR="$PI" ZSH_HISTORY="$ZH" FRICTION_WIKI="$FW" COACH_SCAN_DIRS="$WIKI:$SANDBOX/repo" "$SCRIPT" "$@" 2>"$SANDBOX/stderr"; }
f() { jq -r "$2" <<<"$1"; }

# --- fixtures ---------------------------------------------------------------
TOK="abcdefTEST""TOKEN0123456789"
cl() { jq -cn --arg ts "$1" --arg cwd "$2" --argjson m "$3" --arg t "$4" '{type:$t, timestamp:$ts, cwd:$cwd, sessionId:"s1", message:$m}'; }
us() { cl "$1" /w/ECFX-77 "$(jq -cn --arg c "$2" '{role:"user",content:$c}')" user; }
as() { cl "$1" /w/ECFX-77 "$(jq -cn --arg c "$2" '{role:"assistant",content:[{type:"text",text:$c}]}')" assistant; }
long() { printf '%s ' "$1"; for _ in 1 2 3 4 5 6; do printf 'It works by keeping state in one place and reading it back later. '; done; }
pm() { jq -cn --arg ts "$1" --argjson m "$2" '{type:"message", timestamp:$ts, message:$m}'; }

{ us 2026-10-14T07:00:00.000Z "check the mr queue and post the replies for ECFX-123"
  us 2026-10-15T07:00:00.000Z "check the mr queue and post the replies for ECFX-456"
  us 2026-10-14T07:10:00.000Z "yes, looks right, go on"
  us 2026-10-15T07:10:00.000Z "yes, looks right, go on"
  us 2026-10-14T07:11:00.000Z "continue please"
  us 2026-10-15T07:11:00.000Z "continue please"
  us 2026-10-14T07:12:00.000Z "<system-reminder>sync the wiki notes for the standup again</system-reminder>"
  us 2026-10-15T07:12:00.000Z "<system-reminder>sync the wiki notes for the standup again</system-reminder>"
  us 2026-10-14T07:13:00.000Z "The daily plugin sent a message: rebuild the whole index please now"
  us 2026-10-15T07:13:00.000Z "The daily plugin sent a message: rebuild the whole index please now"
  us 2026-10-14T07:20:00.000Z "new rule: always run the linter before every commit"
  us 2026-10-15T07:20:00.000Z "New rule: always run the linter before every commit!"
  us 2026-10-15T07:25:00.000Z "new rule: keep every commit message under seventy two characters wide"
  us 2026-10-14T07:21:00.000Z "never ever push to main without asking me first"
  us 2026-10-13T07:21:00.000Z "rebase the branch onto main and push it for review"
  us 2026-09-20T07:22:00.000Z "rebase the branch onto main and push it for review"
  us 2026-10-15T07:22:00.000Z "rebase the branch onto main and push it for review"
  us 2026-10-15T07:30:00.000Z "explain how the retry queue works in this project"
  as 2026-10-15T07:30:20.000Z "Let me look at the code."
  as 2026-10-15T07:30:40.000Z "$(long 'The retry queue')"
  us 2026-10-15T07:31:00.000Z "could you fix the retry queue so it explains itself better?"
  as 2026-10-15T07:31:20.000Z "$(long 'Fixed.')"
  us 2026-10-15T07:32:00.000Z "so where are we now with the retry queue work?"
  as 2026-10-15T07:32:20.000Z "$(long 'Status.')"
  us 2026-10-14T10:00:00.000Z "call the status api with Bearer $TOK for the health page"
  us 2026-10-15T10:00:00.000Z "call the status api with Bearer $TOK for the health page"
  us 2026-10-15T10:05:00.000Z "call the status api with Bearer $TOK for the health page"
  us 2026-10-15T10:05:00.000Z "call the status api with Bearer $TOK for the health page"
  us 2026-10-15T07:50:00.000Z "explain how the token header gets built here"
  as 2026-10-15T07:50:20.000Z "$(long "It sends Bearer $TOK in the header.")"
  us 2026-10-15T11:00:00.000Z "run the nightly export for the reports"
  printf '%s\n' '{"type":"user","timestamp":"2026-10-15T07:40:00.000Z","message":{"role":"user","content":"check the mr queue and post the repl'; } >"$CP/-proj/s1.jsonl"

us 2026-10-15T12:00:00.000Z "run the nightly export for the reports" >"$CP/-proj/s2.jsonl"
{ echo '{"type":"session","version":3,"id":"p1","timestamp":"2026-10-14T07:00:00.000Z","cwd":"/w/ECFX-88"}'
  pm 2026-10-14T09:00:00.000Z '{"role":"user","content":[{"type":"text","text":"check the mr queue and post the replies for ECFX-1011"}]}'
  pm 2026-10-15T09:00:00.000Z '{"role":"user","content":[{"type":"text","text":"what is the difference between a mutex and a semaphore?"}]}'
  pm 2026-10-15T09:00:30.000Z "$(jq -cn --arg c "$(long 'A mutex')" '{role:"assistant",content:[{type:"text",text:$c}]}')"; } >"$PI/--proj--/2026-10-14T07-00-00-000Z_p1.jsonl"

{ echo 'ls -la'; echo "curl -H 'Authorization: Bearer $TOK' https://example.test/api"; echo 'echo done'; } >"$ZH"
printf 'clean line\nToken: Bearer %s\n' "$TOK" >"$WIKI/notes/leak.md"
printf 'nothing to see\n' >"$WIKI/notes/clean.md"
printf 'Bearer %s\0binary\n' "$TOK" >"$WIKI/notes/blob.bin"
printf 'x=Bearer $TOKEN is a placeholder\n' >"$SANDBOX/repo/doc.md"

cat >"$FW/directions.md" <<'EOT'
# Standing directions

| id | rule | scope | since | source | status |
|---|---|---|---|---|---|
| D-007 | Always run the linter before every commit | global | 2026-09-01 | claude | active |
| D-008 | keep every commit message under seventy two characters wide | global | 2026-09-02 | claude | active |
EOT

OUT=$(mine --date $D); RC=$?
assert_eq "0" "$RC" "coach-mine exits 0"
assert_eq "yes" "$(yn "$OUT" '(.groups|type)=="array" and (.concepts|type)=="array"')" "prints {groups, concepts}"

echo "coach-mine — repeat"
g=$(jq -c '[.groups[]|select(.kind=="repeat")|select(.samples[0]|test("mr queue"))]|.[0]' <<<"$OUT")
assert_eq "3|2|high|user" "$(f "$g" '[.count,.days,.confidence,.source]|join("|")')" "a prompt said 3 times on 2 days (Claude and pi) forms one repeat group"
assert_eq "yes" "$(yn "$g" '(.sig|startswith("user:repeat:")) and (.sig|test("<key>"))')" "sig is user:repeat:<normalised head> with the ticket key replaced"
assert_eq "1" "$(jq '[.groups[]|select(.kind=="repeat")|select(.samples[0]|test("mr queue"))]|length' <<<"$OUT")" "ticket numbers and the half-written last line neither split nor inflate the group"
assert_eq "0" "$(jq '[.groups[]|select(.sig|test("looks right|continue please|sync the wiki|rebuild the whole"))]|length' <<<"$OUT")" "acknowledgements and injected lines never cluster"
g=$(jq -c '[.groups[]|select(.sig|test("rebase the branch"))]|.[0]' <<<"$OUT")
assert_eq "2|2|low" "$(f "$g" '[.count,.days,.confidence]|join("|")')" "the 14-day window cuts older sightings; count 2 stays low"
OUT14=$(mine --date 2026-10-14)
assert_eq "0" "$(jq '[.groups[]|select(.sig|test("rebase the branch"))]|length' <<<"$OUT14")" "a repeat with nothing on the mined date is not emitted"

g=$(jq -c '[.groups[]|select(.sig|test("status api"))]|.[0]' <<<"$OUT")
assert_eq "3|2" "$(f "$g" '[.count,.days]|join("|")')" "a prompt carrying a token still clusters (3 on 2 days) and a replayed entry counts once"
assert_eq "yes" "$(yn "$g" '.samples[0]|test("<secret:bearer>")')" "the token in a prompt is replaced by a placeholder"
g=$(jq -c '[.groups[]|select(.sig|test("nightly export"))]|.[0]' <<<"$OUT")
assert_eq "2|1|low" "$(f "$g" '[.count,.days,.confidence]|join("|")')" "the same prompt in two sessions on one day counts twice"

echo "coach-mine — restated"
g=$(jq -c '[.groups[]|select(.kind=="restated")|select(.samples[0]|test("linter"))]|.[0]' <<<"$OUT")
assert_eq "2|2|high|user" "$(f "$g" '[.count,.days,.confidence,.source]|join("|")')" "a rule restated on two days forms a restated group"
assert_eq "yes" "$(yn "$g" '.samples|any(test("restates D-007"))')" "and notes the matching standing direction"
assert_eq "0" "$(jq '[.groups[]|select(.sig|test("push to main"))]|length' <<<"$OUT")" "a rule said once is not a group"
g=$(jq -c '[.groups[]|select(.kind=="restated")|select(.samples[0]|test("seventy two"))]|.[0]' <<<"$OUT")
assert_eq "1|high|yes" "$(f "$g" '[.count,.confidence,(.samples|any(test("restates D-008")))|tostring]|join("|")' | sed 's/true/yes/')" "a rule said once on the date that matches a standing direction is a group"

echo "coach-mine — secret"
g=$(jq -c '[.groups[]|select(.kind=="secret")|select(.evidence[0]|test("leak.md"))]|.[0]' <<<"$OUT")
assert_eq "files|high" "$(f "$g" '[.source,.confidence]|join("|")')" "a planted bearer token in a wiki file gives a secret group"
assert_eq "yes" "$(yn "$g" '.evidence[0]|endswith("notes/leak.md:2 bearer")')" "evidence is <path>:<line> <pattern>"
assert_eq "yes" "$(yn "$OUT" '[.groups[]|select(.kind=="secret")|select(.evidence[0]|test("zsh_history:2 bearer"))]|length==1')" "the zsh history is scanned"
assert_eq "0" "$(jq '[.groups[]|select(.kind=="secret")|select(.evidence[0]|test("blob.bin|clean.md|doc.md"))]|length' <<<"$OUT")" "binary files, clean files and placeholders are not flagged"
assert_eq "0" "$(grep -c "$TOK" <<<"$OUT"; true)" "the token is not in stdout"
assert_eq "0" "$(grep -c "$TOK" "$SANDBOX/stderr"; true)" "the token is not in stderr"
assert_eq "0" "$(grep -c "Authorization" <<<"$OUT"; true)" "nor is the line around it"

echo "coach-mine — concepts"
assert_eq "3" "$(jq '.concepts|length' <<<"$OUT")" "explain and what-is questions (one answer quoting a token) give a concept; a fix request and a status ping give none"
c=$(jq -c '.concepts[]|select(.question|test("retry queue"))' <<<"$OUT")
assert_eq "claude|s1" "$(f "$c" '[.harness,.session]|join("|")')" "concept carries harness and session"
assert_eq "yes" "$(yn "$c" '.answer|startswith("The retry queue")')" "the answer is the last assistant text of the turn, not the first"
assert_eq "yes" "$(yn "$OUT" '[.concepts[]|select(.harness=="pi")]|length==1 and all(.[]; .answer|length<=1500)')" "pi concepts are found, answer cut to 1500 chars"

echo "coach-mine — robustness"
OUT=$(CLAUDE_PROJECTS_DIR="$SANDBOX/none" PI_SESSIONS_DIR="$SANDBOX/none" ZSH_HISTORY="$SANDBOX/none" FRICTION_WIKI="$SANDBOX/none" COACH_SCAN_DIRS="$SANDBOX/none" "$SCRIPT" --date $D); RC=$?
assert_eq "0|{\"groups\":[],\"concepts\":[]}" "$RC|$(jq -c . <<<"$OUT")" "missing inputs give an empty result"
"$SCRIPT" --date nope >/dev/null 2>&1; assert_eq "1" "$?" "a bad --date is an error"

echo
echo "coach-mine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
