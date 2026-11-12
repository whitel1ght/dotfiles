#!/bin/bash
# Tests for bin/day-agent. DIARY_DIR points into a sandbox, and the date and the
# clock are fixed through DAY_AGENT_DATE and DAY_AGENT_NOW, so nothing here
# touches ~/wiki.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/day-agent"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
DIARY="$SANDBOX/diary"
DATE=2026-11-05
AGENT="$DIARY/.agent/$DATE.md"

run() { (DIARY_DIR="$DIARY" DAY_AGENT_DATE="$DATE" DAY_AGENT_NOW="${NOW:-09:12}" "$SCRIPT" "$@" 2>"$SANDBOX/stderr"); }
errs() { cat "$SANDBOX/stderr"; }
reset() { rm -rf "${DIARY:?}"; mkdir -p "$DIARY"; }
fresh() { reset; run init; }

echo "day-agent - path and init"
reset
assert_eq "$AGENT" "$(run path)" "path prints <DIARY_DIR>/.agent/<date>.md"
assert_eq "no" "$([ -e "$AGENT" ] && echo yes || echo no)" "path creates nothing"
run init; rc=$?
assert_eq "0" "$rc" "init exits 0"
assert_eq "# agent notes $DATE" "$(cat "$AGENT")" "init writes the header and nothing else"
printf '# agent notes %s\n## ecfx-1\n' "$DATE" > "$AGENT"
run init; rc=$?
assert_eq "0" "$rc" "init twice exits 0"
assert_eq "# agent notes $DATE
## ecfx-1" "$(cat "$AGENT")" "init leaves an existing file alone"

echo "day-agent - note"
reset
run note ecfx-1 note "x" >/dev/null; rc=$?
assert_eq "3" "$rc" "note with no agent file exits 3"
assert_contains "$(errs)" "day-agent: no agent file for $DATE (old-format day)" "and says old-format day"
assert_eq "no" "$([ -e "$AGENT" ] && echo yes || echo no)" "and creates no file"
run mr ecfx-1 backend!1 https://x/1 >/dev/null; rc=$?
assert_eq "3" "$rc" "mr with no agent file exits 3"
assert_eq "no" "$([ -e "$AGENT" ] && echo yes || echo no)" "and creates no file either"
fresh
run note ECFX-17482 progress "O2, N1 fixed, pushed at 811e370a3"; rc=$?
assert_eq "0" "$rc" "note exits 0"
assert_eq "# agent notes $DATE
## ecfx-17482
- 09:12 progress: O2, N1 fixed, pushed at 811e370a3" "$(cat "$AGENT")" "note lowercases KEY and creates the section"
NOW=10:05 run note p3 note "replied to Levi in Slack"
NOW=11:40 run note ecfx-17482 done "merged dec5a42eb2"
assert_eq "# agent notes $DATE
## ecfx-17482
- 09:12 progress: O2, N1 fixed, pushed at 811e370a3
- 11:40 done: merged dec5a42eb2
## p3
- 10:05 note: replied to Levi in Slack" "$(cat "$AGENT")" "an entry lands at the end of an existing middle section, other sections keep their order"
run note ecfx-17482 note "line one
line two"
assert_eq "- 09:12 note: line one line two" "$(grep 'line one' "$AGENT")" "newlines in TEXT fold to spaces"
run note ecfx-9 note "$(printf 'tab\there\rcr  and  gaps')"
assert_eq "- 09:12 note: tab here cr and gaps" "$(tail -n 1 "$AGENT")" "tabs and CRs fold to single spaces"
for k in progress done note blocked with-you handed-back carried; do
  run note ecfx-5 "$k" "x"; assert_eq "0" "$?" "kind $k accepted"
done
n=$(wc -l < "$AGENT")
run note ecfx-5 nope "x"; rc=$?
assert_eq "2" "$rc" "an unknown kind exits 2"
assert_contains "$(errs)" "day-agent: unknown kind" "and says so"
run note ecfx-5 note ""; assert_eq "2" "$?" "empty TEXT exits 2"
run note ecfx-5 note "  "; assert_eq "2" "$?" "blank TEXT exits 2"
run note "bad key" note "x"; rc=$?
assert_eq "2" "$rc" "a bad KEY exits 2"
assert_contains "$(errs)" "day-agent: bad key" "and says so"
run note ecfx-5 note "x" "y" >/dev/null; assert_eq "2" "$?" "too many arguments exit 2"
run note ECFX x "y" >/dev/null; assert_eq "2" "$?" "a key without a number exits 2"
assert_eq "$((n))" "$(wc -l < "$AGENT" | tr -d ' ')" "refused calls write nothing"
fresh
run note ecfx-1 note 'a/b & c \ "d"'
assert_eq '- 09:12 note: a/b & c \ "d"' "$(sed -n 3p "$AGENT")" "TEXT with / & backslash and quotes is written as typed"
run note ecfx-2 note '\1 \n & /'
assert_eq '- 09:12 note: \1 \n & /' "$(sed -n 5p "$AGENT")" "backslash sequences are not interpreted"

echo "day-agent - mr"
fresh
run mr ecfx-17482 ecfx-dashboard!2289 https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289; rc=$?
assert_eq "0" "$rc" "mr exits 0"
assert_eq "# agent notes $DATE
## ecfx-17482
- mr: dashboard!2289 https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289" "$(cat "$AGENT")" "mr drops ecfx- from the repo and writes the line"
run mr ECFX-17482 dashboard!2289 https://x/y
assert_eq "3" "$(wc -l < "$AGENT" | tr -d ' ')" "the same repo!iid twice adds one line"
run mr ecfx-17482 backend!7 https://x/7
assert_eq "- mr: backend!7 https://x/7" "$(tail -n 1 "$AGENT")" "another MR is added"
run mr ecfx-17482 ECFX-Dashboard!22 https://x/22
assert_eq "- mr: dashboard!22 https://x/22" "$(tail -n 1 "$AGENT")" "an uppercase repo is lowercased before ecfx- is stripped"
run mr ecfx-17482 nonsense https://x/7; assert_eq "2" "$?" "a bad REPO!IID exits 2"
run mr "bad key" backend!7 https://x/7; assert_eq "2" "$?" "mr with a bad KEY exits 2"
assert_contains "$(errs)" "day-agent: bad key" "and says so"

run mr ecfx-17482 backend!8 "https://x/a b"; assert_eq "2" "$?" "a URL with a space exits 2"
assert_contains "$(errs)" "day-agent: bad url" "and says so"
run mr ecfx-17482 backend!8 "$(printf 'https://x/a\tb')"; assert_eq "2" "$?" "a URL with a tab exits 2"
assert_eq "5" "$(wc -l < "$AGENT" | tr -d ' ')" "bad URLs write nothing"

echo "day-agent - show and mrs"
reset
run show >/dev/null; assert_eq "1" "$?" "show exits 1 when there is no file"
fresh
run note p3 note "hello"
NOW=10:00 run note ecfx-1 done "ok"
run mr ecfx-1 dashboard!1 https://x/1
run mr p3 backend!2 https://x/2
assert_eq "# agent notes $DATE
## p3
- 09:12 note: hello
- mr: backend!2 https://x/2
## ecfx-1
- 10:00 done: ok
- mr: dashboard!1 https://x/1" "$(run show)" "show prints the whole file"
assert_eq "## ecfx-1
- 10:00 done: ok
- mr: dashboard!1 https://x/1" "$(run show ECFX-1)" "show KEY prints the one section"
run show ecfx-404 >/dev/null; assert_eq "1" "$?" "show of a missing section exits 1"
assert_eq "p3	backend!2	https://x/2
ecfx-1	dashboard!1	https://x/1" "$(run mrs)" "mrs prints key, repo!iid and url separated by tabs"
fresh
rm -f "$AGENT"
run mrs >/dev/null; assert_eq "0" "$?" "mrs with no file exits 0"
assert_eq "" "$(run mrs)" "and prints nothing"

echo "day-agent - id"
reset
assert_eq "p1" "$(run id)" "id with no diary and no file is p1"
run id >/dev/null; assert_eq "0" "$?" "and exits 0"
printf '# %s\n<!-- start-day:start -->\n- [ ] reply to Levi <!-- p1 -->\n<!-- start-day:end -->\n' "$DATE" > "$DIARY/$DATE.md"
assert_eq "p2" "$(run id)" "id sees <!-- p1 --> in the diary block"
run init
run note p2 note "x"
assert_eq "p3" "$(run id)" "id sees ## p2 in the agent file"
printf '# %s\n<!-- start-day:start -->\n- [ ] a <!-- p1 -->\n<!-- start-day:end -->\n- [ ] later <!-- p9 -->\n' "$DATE" > "$DIARY/$DATE.md"
assert_eq "p3" "$(run id)" "a marker outside the block is ignored"
printf '# %s\n- [ ] a <!-- p7 -->\n' "$DATE" > "$DIARY/$DATE.md"
assert_eq "p3" "$(run id)" "a diary with no block is ignored"
run note p12 note "x"
assert_eq "p13" "$(run id)" "two-digit ids count numerically"

echo "day-agent - concurrency"
fresh
i=0; while [ "$i" -lt 20 ]; do run note ecfx-1 note "n$i" & i=$((i + 1)); done; wait
assert_eq "20" "$(grep -c '^- 09:12 note: n' "$AGENT")" "20 parallel notes on one key leave exactly 20 entries"
assert_eq "1" "$(grep -c '^## ecfx-1$' "$AGENT")" "and one section"
assert_eq "no" "$([ -e "$AGENT.lock" ] && echo yes || echo no)" "the lock is released"
assert_eq "0" "$(ls "$DIARY/.agent" | grep -c tmp)" "no temp files are left"
mkdir "$AGENT.lock"
(DAY_AGENT_LOCK_TRIES=3 DIARY_DIR="$DIARY" DAY_AGENT_DATE="$DATE" "$SCRIPT" note ecfx-1 note x 2>"$SANDBOX/stderr"); rc=$?
assert_eq "1" "$rc" "a held lock gives exit 1"
assert_contains "$(errs)" "day-agent: busy" "and says busy"
assert_eq "yes" "$([ -d "$AGENT.lock" ] && echo yes || echo no)" "and the other holder's lock is left alone"
rmdir "$AGENT.lock"
mkdir "$AGENT.lock"
old=$(date -v-60S +%Y%m%d%H%M.%S 2>/dev/null || date -d '60 seconds ago' +%Y%m%d%H%M.%S)
touch -t "$old" "$AGENT.lock"
run note ecfx-1 note "after stale"; rc=$?
assert_eq "0" "$rc" "a lock 60 s old is broken"
assert_eq "- 09:12 note: after stale" "$(tail -n 1 "$AGENT")" "and the note is written"
assert_eq "no" "$([ -e "$AGENT.lock" ] && echo yes || echo no)" "and the lock is released after"

echo "day-agent - usage"
run >/dev/null; assert_eq "2" "$?" "no arguments exit 2"
assert_contains "$(errs)" "usage" "and print usage to stderr"
run frobnicate >/dev/null; assert_eq "2" "$?" "an unknown subcommand exits 2"
assert_contains "$(errs)" "usage" "with usage"

echo "day-agent - grammar"
fresh
NOW=09:12 run note ecfx-17482 progress "O2, N1 fixed"
run mr ecfx-17482 ecfx-dashboard!2289 https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289
NOW=11:40 run note ecfx-17482 with-you "waiting on you"
run note p3 handed-back 'a/b & c \ "d"'
bad=0
while IFS= read -r line; do
  case "$line" in
    "# agent notes "*) continue ;;
  esac
  if printf '%s\n' "$line" | grep -Eq '^## [^[:space:]]+[[:space:]]*$' ||
     printf '%s\n' "$line" | grep -Eq '^- mr: [^[:space:]]+ [^[:space:]]+[[:space:]]*$' ||
     printf '%s\n' "$line" | grep -Eq '^- [0-9][0-9]:[0-9][0-9] [a-z-]+: .+$'; then :; else
    bad=$((bad + 1)); echo "         no grammar match: [$line]"
  fi
done < "$AGENT"
assert_eq "0" "$bad" "every line of a file built with every subcommand matches the parser's regexes"

echo "day-agent - closing kinds and earlier refs"
fresh
run note 2026-11-06/P3 dismissed "the user said: not needed"; rc=$?
assert_eq "0" "$rc" "a keyless item of an earlier day is keyed by its ref"
run note 2026-10-20/i2 expired "first planned 2026-10-20"
run note ecfx-1 deferred "2026-11-11 after the release"
assert_eq "# agent notes $DATE
## 2026-11-06/p3
- 09:12 dismissed: the user said: not needed
## 2026-10-20/i2
- 09:12 expired: first planned 2026-10-20
## ecfx-1
- 09:12 deferred: 2026-11-11 after the release" "$(cat "$AGENT")" "dismissed, expired and deferred are kinds"
run note ecfx-1 deferred "next week" >/dev/null; rc=$?
assert_eq "2" "$rc" "a deferred note without a date is refused"
assert_contains "$(errs)" "YYYY-MM-DD" "naming the date it needs"
run note 2026-11-06/x3 dismissed "x" >/dev/null; assert_eq "2" "$?" "a malformed ref is refused"
run note ecfx-1 dropped "x" >/dev/null; assert_eq "2" "$?" "there is no dropped kind"
assert_eq "p1" "$(run id)" "ref sections do not take a pN id"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
