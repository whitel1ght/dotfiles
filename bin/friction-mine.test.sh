#!/bin/bash
# Tests for bin/friction-mine. Every source dir points into a sandbox, TZ is pinned
# to UTC+3 and the fixtures are written here, so nothing touches ~/.local/state,
# ~/wiki, ~/.claude or ~/.pi. The miner calls only jq, awk and bin/friction.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/friction-mine"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
export TZ=Etc/GMT-3
D=2026-10-15
FR="$SANDBOX/friction" RD="$SANDBOX/run-day" DY="$SANDBOX/diary" PS="$SANDBOX/pi-sub" CP="$SANDBOX/claude" PI="$SANDBOX/pi" LEDGER="$SANDBOX/ledger.md"
mkdir -p "$FR" "$RD/done" "$DY" "$PS" "$CP/-proj" "$PI/--proj--"

export ZSH_HISTORY="$SANDBOX/none" COACH_SCAN_DIRS="$SANDBOX/none" FRICTION_WIKI="$SANDBOX/none"
mine() { FRICTION_DIR="$FR" RUN_DAY_DIR="$RD" DIARY_DIR="$DY" PI_SUB_STATE_DIR="$PS" CLAUDE_PROJECTS_DIR="$CP" PI_SESSIONS_DIR="$PI" "$SCRIPT" --ledger "$LEDGER" "$@" 2>"$SANDBOX/stderr"; }
grp() { jq -c --arg s "$1" '.groups[] | select(.sig == $s)' <<<"$OUT"; }
f() { jq -r "$2" <<<"$1"; }

# --- fixtures ---------------------------------------------------------------
# events: two equal after normalisation, one on another day
{ echo '{"ts":"2026-10-15T09:00:00+03:00","harness":"script","source":"changes-since","kind":"auth","key":"ECFX-1","msg":"Outlook not connected","sig":"changes-since:auth:outlook not connected"}'
  echo '{"ts":"2026-10-15T09:05:00+03:00","harness":"script","source":"changes-since","kind":"auth","key":"ECFX-2","msg":"Outlook not connected","sig":"changes-since:auth:outlook not connected"}'
  echo 'not json'
  echo '{"ts":"2026-10-15T09:06:00+03:00","harness":"script","source":"wait-for","kind":"service_down","key":"","msg":"gitlab down 3h","sig":"wait-for:service_down:gitlab down <n>h"}'; } >"$FR/$D.jsonl"
echo '{"ts":"2026-10-14T09:00:00+03:00","harness":"script","source":"old","kind":"other","key":"","msg":"yesterday","sig":"old:other:yesterday"}' >"$FR/2026-10-14.jsonl"

# run state: one item in the live file, one in done/, plus notes that must not become friction
cat >"$RD/$D.md" <<'EOT'
# run-day 2026-10-15
max_agents: 3
notes:
- merge request fetch failed with EOF, retried once
- reviewed the sidebar, all fine
- ecfx-9 | class=auto | agent=a1 | worktree=- | mr=- | retries=2 | needs_you=no | owner=main
- ecfx-10 | class=auto | agent=a2 | worktree=- | mr=- | retries=0 | needs_you=yes | owner=main
- ecfx-11 | class=auto | agent=a3 | worktree=- | mr=- | retries=0 | needs_you=no | owner=main
EOT
printf -- '- ecfx-12 | class=auto | retries=1 | needs_you=no | owner=main\n' >"$RD/done/$D.md"
printf -- '- ecfx-13 | class=auto | retries=5 | needs_you=no | owner=main\n' >"$RD/2026-10-14.md"

# diary
cat >"$DY/$D.md" <<'EOT'
# 2026-10-15
Outlook not connected. Google Calendar not connected.
- [!] ecfx-17418 pick up: Retry button · blocked: needs ECFX-17551 (backend classification)  [↗][ECFX-17418]
- [x] re-review dashboard!2232 · note: skipped by user, MR unchanged since my 10-10 review  [↗][ECFX-2648]
- [ ] check inbox (Slack unavailable) later
- [x] all good
<!-- friction:start -->
## Friction

- F-004 — Jira not connected (redis unavailable) → /fix-friction F-004
<!-- friction:end -->
EOT
printf 'Outlook not connected.\n' >"$DY/2026-10-14.md"

# pi-sub: started on the 15th (local), UTC 21:30 on the 14th is 00:30 local on the 15th
mkagent() { mkdir -p "$PS/$1"; echo "{\"id\":\"$1\",\"started_at\":\"$2\"}" >"$PS/$1/meta.json"; }
mkagent a-timeout 2026-10-15T07:00:00.000Z; echo '{"code":null,"signal":"SIGTERM","ended_at":"2026-10-15T08:00:00.000Z","how":"failed","by":"timeout"}' >"$PS/a-timeout/exit.json"
mkagent a-failed 2026-10-14T21:30:00.000Z; echo '{"code":1,"signal":null,"ended_at":"2026-10-15T08:00:00.000Z","how":"failed","error":"spawn pi ENOENT"}' >"$PS/a-failed/exit.json"
mkagent a-done 2026-10-15T07:00:00.000Z; echo '{"code":0,"signal":null,"ended_at":"2026-10-15T08:00:00.000Z","how":"done"}' >"$PS/a-done/exit.json"
mkagent a-old 2026-10-14T07:00:00.000Z; echo '{"code":1,"signal":null,"ended_at":"2026-10-14T08:00:00.000Z","how":"failed","error":"too old"}' >"$PS/a-old/exit.json"
mkagent a-retry 2026-10-15T07:00:00.000Z
printf '%s\n' '{"type":"agent_start"}' '{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000,"errorMessage":"Connection error."}' >"$PS/a-retry/events.jsonl"

# Claude transcript
cl() { jq -cn --arg ts "$1" --arg cwd "$2" --argjson m "$3" --arg t "$4" '{type:$t, timestamp:$ts, cwd:$cwd, message:$m}'; }
tu() { cl "$1" /w/ECFX-77 "{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"$2\",\"name\":\"Bash\",\"input\":{\"command\":\"$3\"}}]}" assistant; }
tr_() { cl "$1" /w/ECFX-77 "{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"$2\",\"is_error\":true,\"content\":\"$3\"}]}" user; }
meta() { cl "$1" /w/ECFX-77 "$(jq -cn --arg c "$2" '{role:"user",content:$c}')" user | jq -c '. + {isMeta:true}'; }
aq() { cl "$1" /w/ECFX-77 "$(jq -cn --arg c "$2" '{role:"assistant",content:[{type:"text",text:$c}]}')" assistant; }
us() { cl "$1" /w/ECFX-77 "$(jq -cn --arg c "$2" '{role:"user",content:$c}')" user; }
{ for i in 1 2 3; do tu "2026-10-15T07:0$i:00.000Z" "t$i" "glab mr view 12"; tr_ "2026-10-15T07:0$i:30.000Z" "t$i" "Exit code 2\nerror in step $i"; done
  for i in 1 2 3; do tu "2026-10-15T07:2$i:00.000Z" "n$i" "make build"; tr_ "2026-10-15T07:2$i:30.000Z" "n$i" "Exit code 1\nerror in step $i"; done
  tu 2026-10-15T07:24:00.000Z e1 "cd /w && FOO=1 ~/projects/dotfiles/bin/end-day --dry-run | tee out"; tr_ 2026-10-15T07:24:30.000Z e1 "Exit code 128\nfatal"
  tu 2026-10-15T07:25:00.000Z e2 "npm run dev -- --glab"; tr_ 2026-10-15T07:25:30.000Z e2 "Exit code 1\nboom"
  tr_ 2026-10-15T07:26:00.000Z nocmd "Exit code 1\nunknown command"
  tu 2026-10-15T07:27:00.000Z c1 "glab api projects/1/notes; echo =====; rg -l x notes"; tr_ 2026-10-15T07:27:30.000Z c1 "Exit code 1\n"
  tu 2026-10-15T07:28:00.000Z c2 "cat state.md\necho =====\nend-day entries 2026-10-15 ecfx | rg x"; tr_ 2026-10-15T07:28:30.000Z c2 "Exit code 1\n"
  tu 2026-10-15T07:29:00.000Z c3 "secret X >/dev/null && ls ~/x || true"; tr_ 2026-10-15T07:29:30.000Z c3 "Exit code 1\n"
  tu 2026-10-15T07:30:00.000Z s1 "glab mr view 77;\n"; tr_ 2026-10-15T07:30:30.000Z s1 "Exit code 1\n"
  tu 2026-10-15T07:31:00.000Z s2 "cd \\\"my dir\\\" && glab mr view 78"; tr_ 2026-10-15T07:31:30.000Z s2 "Exit code 1\n"
  tu 2026-10-15T07:10:00.000Z t4 "git push"; tr_ 2026-10-15T07:10:10.000Z t4 "The user doesn't want to proceed with this tool use. The tool use was rejected"
  tu 2026-10-15T07:12:00.000Z d1 "git reset --hard"; tr_ 2026-10-15T07:12:10.000Z d1 "Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Git Destructive]. If you have other tasks that don't depend on this action, continue working on those."
  tu 2026-10-15T07:13:00.000Z d2 "rm -rf build"; tr_ 2026-10-15T07:13:10.000Z d2 "Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Irreversible Local Destruction]. If you have other tasks that don't depend on this action, continue working on those."
  tu 2026-10-15T07:14:00.000Z d3 "glab mr note 5"; tr_ 2026-10-15T07:14:10.000Z d3 "Permission for this action was denied by the Claude Code auto mode classifier. Reason: [External System Writes]. If you have other tasks that don't depend on this action, continue working on those."
  tu 2026-10-15T07:15:00.000Z d4 "make deploy"; tr_ 2026-10-15T07:15:10.000Z d4 "Permission for this action was denied by the Claude Code auto mode classifier. Reason: The server-side auto mode classifier judged this action dangerous (it gave no explanation). If you have other tasks that don't depend on this action, continue working on those."
  tu 2026-10-15T07:16:00.000Z d5 "rm -rf /tmp/x/*"; tr_ 2026-10-15T07:16:10.000Z d5 "Permission for this command was denied by a built-in Claude Code safety check, not by the user. The check stops removals that can delete far more than intended."
  tu 2026-10-15T07:11:00.000Z t5 "ls"; tr_ 2026-10-15T07:11:10.000Z t5 "ls: nope"
  us 2026-10-15T07:12:00.000Z "[Request interrupted by user]"
  us 2026-10-15T07:13:00.000Z "no, that's not what I asked"
  us 2026-10-15T07:14:00.000Z "please add a test"
  us 2026-10-15T07:14:10.000Z "looks good, I want to make sure though that again is fine"
  us 2026-10-15T07:14:20.000Z "no, its fine"
  us 2026-10-15T07:14:30.000Z "okay, now do not stop the build again"
  aq 2026-10-15T07:14:40.000Z "Shall I continue with the migration?"
  us 2026-10-15T07:14:50.000Z "no, go ahead please"
  aq 2026-10-15T07:14:55.000Z "Which file do you mean?"
  us 2026-10-15T07:14:58.000Z "don't touch the config file, only the tests please, wrong one entirely"
  us 2026-10-15T07:15:00.000Z "<system-reminder>don't do this again</system-reminder>"
  aq 2026-10-15T07:30:00.000Z "Linter pass finished."
  us 2026-10-15T07:30:10.000Z "from now on always run the linter before committing"
  us 2026-10-15T07:31:00.000Z "why did you do that again?!"
  us 2026-10-15T07:32:00.000Z "THIS IS BROKEN fix it"
  us 2026-10-15T07:33:00.000Z "[Request interrupted by user]"
  us 2026-10-15T07:33:10.000Z "ok try the other approach instead"
  us 2026-10-15T07:34:00.000Z "and one more plain thing"
  us 2026-10-15T07:35:00.000Z "<command-name>/foo</command-name> always never must"
  us 2026-10-15T07:35:10.000Z "The daily plugin sent a message: [daily-event] always never"
  meta 2026-10-15T07:35:20.000Z "Caveat: you must always remember this"
  tr_ 2026-10-15T07:35:30.000Z t5 "you must always never again"
  tu 2026-10-14T07:00:00.000Z t6 "yesterday"; tr_ 2026-10-14T07:00:10.000Z t6 "old failure"
  us 2026-10-14T07:01:00.000Z "no, wrong, stop"; } >"$CP/-proj/s1.jsonl"

# pi transcript
pm() { jq -cn --arg ts "$1" --argjson m "$2" '{type:"message", timestamp:$ts, message:$m}'; }
{ echo '{"type":"session","version":3,"id":"p1","timestamp":"2026-10-15T07:00:00.000Z","cwd":"/w/ECFX-88"}'
  pm 2026-10-15T07:01:00.000Z '{"role":"assistant","content":[{"type":"toolCall","id":"c1","name":"bash","arguments":{"command":"npm test"}}]}'
  pm 2026-10-15T07:01:10.000Z '{"role":"toolResult","toolCallId":"c1","toolName":"bash","isError":true,"content":[{"type":"text","text":"1 failing"}]}'
  pm 2026-10-15T07:02:00.000Z '{"role":"assistant","stopReason":"error","errorMessage":"Our servers are currently overloaded.","content":[]}'
  pm 2026-10-15T07:03:00.000Z '{"role":"user","content":[{"type":"text","text":"why did you edit that file again?"}]}'
  pm 2026-10-15T07:03:30.000Z '{"role":"user","content":[{"type":"text","text":"okay, new important rule for reviews that should be applied"}]}'
  pm 2026-10-14T07:03:00.000Z '{"role":"user","content":[{"type":"text","text":"stop, wrong"}]}'; } >"$PI/--proj--/2026-10-15T07-00-00-000Z_p1.jsonl"

cat >"$LEDGER" <<'EOT'
# Friction ledger

| id | signature | class | first | last | days | status | fix |
|---|---|---|---|---|---|---|---|
| F-001 | changes-since:auth:outlook not connected | env | 2026-10-06 | 2026-10-14 | 5 | proposed | |
| F-002 | wait-for:service_down:gitlab down <n>h | env | 2026-10-06 | 2026-10-14 | 5 | fixed | abc1234 |
| F-003 | diary:auth:outlook not connected | env | 2026-10-06 | 2026-10-14 | 5 | open | |
EOT

OUT=$(mine --date $D); rc=$?
echo "friction-mine — shape"
assert_eq "0" "$rc" "exit 0"
assert_eq "$D" "$(f "$OUT" .date)" "date echoed"
assert_eq "yes" "$(jq -e '.groups | all(has("sig","source","kind","count","keys","confidence","samples","evidence","known","ledger_status"))' <<<"$OUT" >/dev/null && echo yes || echo no)" "every group has the §3 fields"
assert_eq "yes" "$(jq -e '.groups | . == sort_by([-.count, .sig])' <<<"$OUT" >/dev/null && echo yes || echo no)" "groups sorted biggest first"

echo "friction-mine — events file"
g=$(grp "changes-since:auth:outlook not connected")
assert_eq "2" "$(f "$g" .count)" "two events with one sig make one group of 2"
assert_eq '["ECFX-1","ECFX-2"]' "$(f "$g" '.keys|tostring')" "keys collected"
assert_eq "high" "$(f "$g" .confidence)" "high confidence"
assert_eq "$FR/$D.jsonl:1" "$(f "$g" '.evidence[0]')" "evidence is path:line"
assert_eq "" "$(grp 'old:other:yesterday')" "another day's events are left out"
assert_eq "service_down" "$(f "$(grp 'wait-for:service_down:gitlab down <n>h')" .kind)" "malformed line skipped, next event read"

echo "friction-mine — run state"
g=$(grp "run-state:retry:item retried: retries=<n>")
assert_eq "retry|2" "$(f "$g" '[.kind,.count]|join("|")')" "retries>0 from the live and done/ files, retries=0 ignored"
assert_eq '["ECFX-12","ECFX-9"]' "$(f "$g" '.keys|tostring')" "keys upper-cased"
g=$(grp "run-state:blocked:item needs you: class=auto")
assert_eq "blocked|ECFX-10" "$(f "$g" '[.kind,.keys[0]]|join("|")')" "needs_you=yes -> blocked"
assert_eq "" "$(jq -r '.groups[]|select(.sig|test("fetch failed|sidebar"))' <<<"$OUT")" "notes: lines are not friction"
assert_eq "" "$(jq -r '.groups[]|select(.evidence[0]|test("2026-10-14.md"))' <<<"$OUT")" "other days' run state ignored"

echo "friction-mine — diary"
assert_eq "" "$(grp 'diary:auth:jira not connected')$(grp 'diary:service_down:(redis unavailable)')" "the end-day friction block is not mined"
g=$(grp "diary:blocked:needs <key> (backend classification)")
assert_eq "blocked|ECFX-17418" "$(f "$g" '[.kind,.keys[0]]|join("|")')" "[!] ... · blocked: reason"
g=$(grp "diary:other:skipped by user, mr unchanged since my <n>-<n> review")
assert_eq "other|ECFX-2648" "$(f "$g" '[.kind,.keys[0]]|join("|")')" "note: skipped by user"
assert_eq "service_down" "$(f "$(grp 'diary:service_down:(slack unavailable)')" .kind)" "(… unavailable)"
assert_eq "auth" "$(f "$(grp 'diary:auth:google calendar not connected')" .kind)" "not connected, sentence by sentence"
assert_eq "1" "$(f "$(grp 'diary:auth:outlook not connected')" .count)" "yesterday's diary is not read"

echo "friction-mine — pi-sub"
assert_eq "timeout" "$(f "$(grp 'pi-sub:timeout:agent timed out')" .kind)" "exit by=timeout -> timeout"
assert_eq "tool_error" "$(f "$(grp 'pi-sub:tool_error:agent failed: spawn pi enoent')" .kind)" "failed -> tool_error (UTC 21:30 the day before is local the 15th)"
assert_eq "" "$(jq -r '.groups[]|select(.sig|test("too old"))' <<<"$OUT")" "agent started the day before is left out"
assert_eq "2" "$(jq '[.groups[]|select(.source=="pi-sub" and .kind!="retry")]|length' <<<"$OUT")" "how=done is not friction: only the timeout and the failure are groups"
assert_eq "retry" "$(f "$(grp 'pi-sub:retry:auto retry: connection error.')" .kind)" "events.jsonl auto_retry_start -> retry"

echo "friction-mine — Claude transcripts"
g=$(grp "claude:tool_error:bash: exit code <n>")
assert_eq "tool_error|6|ECFX-77" "$(f "$g" '[.kind,.count,.keys[0]]|join("|")')" "bare Exit code from our tools grouped (glab x3, end-day by path in a pipeline, glab with a trailing ;, glab after a quoted cd); key from the cwd"
assert_eq "retry" "$(f "$(grp 'claude:retry:repeated failing command x<n>: bash glab mr view <n>')" .kind)" "same failing command 3 times -> retry"
assert_eq "" "$(jq -r '.groups[]|select(.sig|test("make build|npm run dev|unknown command"))' <<<"$OUT")" "bare Exit code from other commands, or with no command found, is dropped (no group, no retry)"
assert_eq "6" "$(f "$g" .count)" "bare Exit code from a compound command (; newline && ||) with one of our tools in it is dropped; a leading cd DIR && (quoted too) and a trailing ; or newline are not a second statement"
assert_eq "denied|2" "$(f "$(grp 'claude:denied:bash denied: destructive git or rm')" '[.kind,.count]|join("|")')" "Git Destructive and Irreversible Local Destruction denials share one group"
assert_eq "denied" "$(f "$(grp 'claude:denied:bash denied: external system writes')" .kind)" "classifier tag becomes the reason, lowercased"
assert_eq "denied" "$(f "$(grp 'claude:denied:bash denied: unexplained')" .kind)" "classifier block with no explanation"
assert_eq "denied" "$(f "$(grp 'claude:denied:bash denied: safety check')" .kind)" "built-in safety check denial"
assert_eq "denied" "$(f "$(grp 'claude:denied:bash denied: by user')" .kind)" "permission denial by the user"
assert_eq "interrupt" "$(f "$(grp 'claude:interrupt:[request interrupted by user]')" .kind)" "interrupt"
g=$(grp "claude:correction:no, that's not what i asked")
assert_eq "correction|low" "$(f "$g" '[.kind,.confidence]|join("|")')" "correction wording -> correction, confidence low"
assert_eq "3" "$(jq '[.groups[]|select(.source=="claude" and .kind=="correction")]|length' <<<"$OUT")" "only prompts that open with a correction word count (5+ words; short ones after an assistant question do not)"
assert_eq "" "$(jq -r '.groups[]|select(.sig|test("looks good|its fine|stop the build|go ahead"))' <<<"$OUT")" "excluded: correction word mid-text, too short, 'again' anywhere, short reply to a question"
assert_eq "1" "$(jq '[.groups[]|select(.sig|test("^claude:correction:don.t touch"))]|length' <<<"$OUT")" "a long correction right after an assistant question still counts"
assert_eq "" "$(jq -r '.groups[]|select(.sig|test("old failure|yesterday"))' <<<"$OUT")" "yesterday's entries left out"
assert_eq "1" "$(jq '[.groups[]|select(.sig|test("ls: nope"))]|length' <<<"$OUT")" "a single failure stays a tool_error, no retry group"

echo "friction-mine — user_signals"
sg() { jq -c --arg t "$1" '.user_signals[] | select(.text == $t)' <<<"$OUT"; }
OUT=$(mine --date $D)
g=$(sg "from now on always run the linter before committing")
assert_eq "claude|from now on,always" "$(f "$g" '[.harness,(.markers|join(","))]|join("|")')" "direction markers"
assert_eq "Linter pass finished." "$(f "$g" .prev_assistant)" "prev_assistant is the preceding assistant text"
assert_eq "ECFX-77|/w/ECFX-77" "$(f "$g" '[.key,.cwd]|join("|")')" "key and cwd carried"
assert_eq "s1" "$(f "$g" .session)" "session from the transcript name"
assert_eq "2026-10-15T07:30:10.000Z" "$(f "$g" .ts)" "ts of the entry"
g=$(sg "why did you do that again?!")
assert_eq "again,why did,?!,correction" "$(f "$g" '.markers|join(",")')" "frustration markers, correction included"
assert_eq "caps" "$(f "$(sg 'THIS IS BROKEN fix it')" '.markers|join(",")')" "ALL-CAPS word of 4+ letters"
assert_eq "after_interrupt" "$(f "$(sg 'ok try the other approach instead')" '.markers|join(",")')" "a prompt right after an interrupt"
assert_eq "0" "$(jq '[.user_signals[]|select(.text=="and one more plain thing")]|length' <<<"$OUT")" "the next prompt is not after an interrupt, and has no marker"
assert_eq "0" "$(jq '[.user_signals[]|select(.text|test("^<|daily plugin|Caveat|^\\[Request|you must always never again|yesterday"))]|length' <<<"$OUT")" "injected, command-expansion, meta, interrupt marker and tool-result messages are skipped"
assert_eq "yes" "$(jq -e '[.user_signals[]|select(.harness=="pi")]|length >= 1' <<<"$OUT" >/dev/null && echo yes || echo no)" "pi prompts are candidates too"
assert_eq "yes" "$(jq -e '[.user_signals[]|.ts[0:10]]|unique == ["2026-10-15"]' <<<"$OUT" >/dev/null && echo yes || echo no)" "only the day's prompts"
for i in $(seq 1 45); do us "2026-10-15T08:$(printf %02d $((i % 60))):00.000Z" "always remember rule number $i" ; done >>"$CP/-proj/s2.jsonl"
OUT=$(mine --date $D)
assert_eq "40" "$(jq '.user_signals|length' <<<"$OUT")" "capped at 40 a day"
assert_eq "4" "$(jq '.user_signals[0].markers|length' <<<"$OUT")" "the most-marked kept first"
rm "$CP/-proj/s2.jsonl"; OUT=$(mine --date $D)

echo "friction-mine — state per file"
mkdir -p "$SANDBOX/cp2/-proj"
for n in a b; do
  { us 2026-10-15T08:00:00.000Z "plain opener $n"; aq 2026-10-15T08:01:00.000Z "tail $n"; us 2026-10-15T08:02:00.000Z "[Request interrupted by user]"; } >"$SANDBOX/cp2/-proj/$n.jsonl"
done
OUTS=$(CLAUDE_PROJECTS_DIR="$SANDBOX/cp2" FRICTION_DIR="$SANDBOX/none" RUN_DAY_DIR="$SANDBOX/none" DIARY_DIR="$SANDBOX/none" PI_SUB_STATE_DIR="$SANDBOX/none" PI_SESSIONS_DIR="$SANDBOX/none" "$SCRIPT" --ledger "$LEDGER" --date $D)
assert_eq "0" "$(jq '[.user_signals[]|select(.text|startswith("plain opener"))]|length' <<<"$OUTS")" "an interrupt ending one file does not mark the first prompt of the next file in the batch"

echo "friction-mine — pi transcripts"
assert_eq "tool_error|ECFX-88" "$(f "$(grp 'pi:tool_error:bash: <n> failing')" '[.kind,.keys[0]]|join("|")')" "isError toolResult -> tool_error, key from the session cwd"
assert_eq "service_down" "$(f "$(grp 'pi:service_down:our servers are currently overloaded.')" .kind)" "assistant errorMessage classified"
assert_eq "correction|low" "$(f "$(grp 'pi:correction:why did you edit that file again?')" '[.kind,.confidence]|join("|")')" "correction heuristic on pi prompts"
assert_eq "0" "$(jq '[.groups[]|select(.sig|test("stop, wrong|new important rule"))]|length' <<<"$OUT")" "yesterday's pi prompt and a mid-text match are left out"

echo "friction-mine — ledger"
g=$(grp "changes-since:auth:outlook not connected")
assert_eq "F-001|proposed" "$(f "$g" '[.known,.ledger_status]|join("|")')" "ledger signature match sets known and ledger_status"
assert_eq "null" "$(f "$g" '.regression')" "proposed is not a regression"
g=$(grp "wait-for:service_down:gitlab down <n>h")
assert_eq "F-002|fixed|true" "$(f "$g" '[.known,.ledger_status,.regression]|join("|")')" "fixed + seen again -> regression:true"
assert_eq "null|null" "$(f "$(grp 'diary:auth:google calendar not connected')" '[.known,.ledger_status]|map(tostring)|join("|")')" "unmatched group: known null, ledger_status null"

echo "friction-mine — last_seen"
assert_eq "2026-10-15T06:05:00Z" "$(f "$(grp 'changes-since:auth:outlook not connected')" .last_seen)" "friction log: the latest ts, offset converted to UTC"
assert_eq "2026-10-15T07:31:30Z" "$(f "$(grp 'claude:tool_error:bash: exit code <n>')" .last_seen)" "Claude transcript: the latest entry timestamp"
assert_eq "2026-10-15T07:01:10Z" "$(f "$(grp 'pi:tool_error:bash: <n> failing')" .last_seen)" "pi transcript: the entry timestamp"
assert_eq "null" "$(f "$(grp 'run-state:retry:item retried: retries=<n>')" .last_seen)" "a source without times: null"
assert_eq "null" "$(f "$(grp 'claude:retry:repeated failing command x<n>: bash glab mr view <n>')" .last_seen)" "retry records carry no time: null"
OUT2=$(FRICTION_DIR="$FR" RUN_DAY_DIR="$RD" DIARY_DIR="$DY" PI_SUB_STATE_DIR="$PS" CLAUDE_PROJECTS_DIR="$CP" PI_SESSIONS_DIR="$PI" "$SCRIPT" --ledger "$SANDBOX/none.md" --date $D); assert_eq "0" "$?" "a missing ledger is fine"
assert_eq "null" "$(jq -r '.groups[]|select(.sig=="changes-since:auth:outlook not connected")|.known' <<<"$OUT2")" "and nothing is known"

echo "friction-mine — coach-mine"
STUB="$SANDBOX/coach-stub"
cat >"$STUB" <<'EOT'
#!/bin/sh
echo '{"groups":[{"sig":"user:repeat:post the replies","source":"user","kind":"repeat","count":3,"days":2,"keys":[],"confidence":"high","samples":["post the replies"],"evidence":["/x:1"]},{"sig":"wait-for:service_down:gitlab down <n>h","source":"user","kind":"repeat","count":2,"days":1,"keys":[],"confidence":"low","samples":[],"evidence":[]}],"concepts":[{"harness":"claude","session":"s1","at":"2026-10-15T07:00:00Z","question":"what is x","answer":"x is y"}]}'
EOT
chmod +x "$STUB"
OUT=$(COACH_MINE="$STUB" mine --date $D)
g=$(grp "user:repeat:post the replies")
assert_eq "repeat|3|2|null" "$(f "$g" '[.kind,.count,.days,.known]|map(tostring)|join("|")')" "coach-mine groups are merged, days kept"
assert_eq "F-002|fixed|true" "$(f "$(grp 'wait-for:service_down:gitlab down <n>h' | jq -c 'select(.kind=="repeat")')" '[.known,.ledger_status,.regression]|join("|")')" "coach groups get the ledger lookup too"
assert_eq "what is x" "$(jq -r '.concepts[0].question' <<<"$OUT")" "concepts pass through at the top level"
assert_eq "yes" "$(jq -e '[.groups[]|select(.sig=="changes-since:auth:outlook not connected")]|length == 1' <<<"$OUT" >/dev/null && echo yes || echo no)" "friction-mine's own groups are still there"
printf '#!/bin/sh\nexit 1\n' >"$SANDBOX/coach-fail"; chmod +x "$SANDBOX/coach-fail"
OUT=$(COACH_MINE="$SANDBOX/coach-fail" mine --date $D); RC=$?
assert_eq "0" "$RC" "a failing coach-mine does not fail friction-mine"
assert_eq "yes" "$(jq -e '(.groups|length) > 0 and .concepts == []' <<<"$OUT" >/dev/null && echo yes || echo no)" "its own groups still print, concepts empty"
assert_eq "1" "$(wc -l <"$SANDBOX/stderr" | tr -d ' ')" "and one stderr line says so"

echo "friction-mine — date filtering"
OUT=$(mine --date 2026-10-14)
assert_eq "old:other:yesterday" "$(jq -r '.groups[]|select(.source=="old")|.sig' <<<"$OUT")" "--date 2026-10-14 reads that day's events"
assert_eq "yes" "$(jq -e '[.groups[].sig|select(startswith("changes-since"))]|length == 0' <<<"$OUT" >/dev/null && echo yes || echo no)" "and none of the 15th's"
assert_eq "yes" "$(jq -e '[.groups[]|select(.sig|test("old failure"))]|length == 1' <<<"$OUT" >/dev/null && echo yes || echo no)" "Claude entries of the 14th are found on the 14th"
OUT=$(mine --date 2026-01-01); assert_eq '{"date":"2026-01-01","user_signals":[],"groups":[],"concepts":[]}' "$(jq -c . <<<"$OUT")" "a quiet day gives an empty group list"
mine --date nope >/dev/null; assert_eq "1" "$?" "a bad --date is an error"

echo
echo "friction-mine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
