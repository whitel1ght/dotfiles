#!/bin/bash
# Tests for bin/day-note. INBOX_DIR and DIARY_DIR point into a sandbox and TZ is
# pinned, so nothing here touches ~/.local/state or ~/wiki. day-note calls no
# other tool, so there is nothing to stub on PATH.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/day-note"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
INBOX="$SANDBOX/state/inbox"; DIARY="$SANDBOX/diary"
mkdir -p "$DIARY"

TODAY=$(date +%F)
{ printf '# %s\n\n- [ ] ecfx-18169 outside the block\n\n<!-- start-day:start -->\n#### Plan\n\n' "$TODAY"
  printf -- '- [ ] ecfx-18169 fix retry button\n- [/] review [!6584](https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6584) for ecfx-18171\n- [ ] ECFX-18200 layout\n'
  printf '<!-- start-day:end -->\n\n- [ ] ecfx-77 only after the block\n'; } > "$DIARY/$TODAY.md"

run() { (TZ=Etc/GMT-3 INBOX_DIR="$INBOX" DIARY_DIR="$DIARY" "$SCRIPT" "$@" 2>"$SANDBOX/stderr"); }
errs() { cat "$SANDBOX/stderr"; }
field() { sed -n '/^---$/,/^---$/p' "$1" | sed -n "s/^$2: *//p"; }
memf() { sed -n "s/^  $2: //p" "$1"; }
count() { ls "$INBOX" 2>/dev/null | wc -l | tr -d ' '; }

echo "day-note — the message"
f=$(run --kind done --repo ecfx-dashboard --mr https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231 --session "ECFX-18169" ECFX-18169 "Retry button fixed, MR open."); rc=$?
assert_eq "0" "$rc" "exit 0"
assert_eq "$INBOX" "$(dirname "$f")" "prints the path, inside an INBOX_DIR that did not exist"
assert_eq "yes" "$([[ "$(basename "$f")" =~ ^[0-9]{8}T[0-9]{6}-ECFX-18169-[0-9a-f]{4}\.md$ ]] && echo yes || echo no)" "file name is YYYYMMDDTHHMMSS-KEY-rand4.md"
assert_eq "1" "$(count)" "one message in the inbox"
assert_eq "0" "$(ls "$INBOX" | grep -c '\.tmp$')" "and no *.tmp left behind (it was renamed)"
assert_eq "$(printf -- '---\nkey: ECFX-18169\nkind: done\nsession: ECFX-18169\nrepo: ecfx-dashboard\nmr: https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231\nat: %s\n---\nRetry button fixed, MR open.\n\nmemory:\n  project: ecfx\n  log: "Retry button fixed, MR open."\n  decision: none\n  state_change: none' "$(field "$f" at)")" "$(cat "$f")" "whole file: frontmatter, one-paragraph summary, memory block with log = summary and the other fields none"
assert_eq "yes" "$([[ "$(field "$f" at)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+03:00$ ]] && echo yes || echo no)" "at is local time with a +03:00 style offset"

echo "day-note — defaults"
rm -rf "${INBOX:?}"
f=$(run ECFX-18169 "Done."); assert_eq "done" "$(field "$f" kind)" "kind defaults to done when KEY is on today's plan"
assert_eq "terminal" "$(field "$f" session)" "session defaults to terminal"
assert_eq "" "$(sed -n '/^---$/,/^---$/p' "$f" | grep -E '^(repo|mr):')" "repo and mr lines are left out when not given"
f=$(run ecfx-18169 "lower case key"); assert_eq "ECFX-18169" "$(field "$f" key)" "a lower-case key is upper-cased"
f=$(run ecfx-18200 "Layout done"); assert_eq "done" "$(field "$f" kind)" "plan match ignores case (the plan says ECFX-18200, the key is typed lower case; ecfx-18169 is on the plan as lower case)"
f=$(run ECFX-1817 "Not planned"); assert_eq "offplan" "$(field "$f" kind)" "a key that is only the start of a planned one (ecfx-18171) is not on the plan"
f=$(run ECFX-18171 "Planned"); assert_eq "done" "$(field "$f" kind)" "while the longer key is, found inside a markdown line"
f=$(run ECFX-77 "After the block"); assert_eq "offplan" "$(field "$f" kind)" "a line outside the start-day block is not the plan"
f=$(run ECFX-99 "Unplanned ticket"); assert_eq "offplan" "$(field "$f" kind)" "kind defaults to offplan when KEY is not on the plan"
assert_eq "yes" "$([[ "$(basename "$f")" == *-ECFX-99-* ]] && echo yes || echo no)" "an off-plan message that has a key still names the key in the file"
f=$(run "Quick favour for a teammate"); assert_eq "offplan" "$(field "$f" kind)" "no KEY means offplan"
assert_eq "" "$(field "$f" key)" "and an empty key"
assert_eq "key:" "$(sed -n 2p "$f")" "written as exactly key: with no trailing space"
assert_eq "yes" "$([[ "$(basename "$f")" =~ ^[0-9]{8}T[0-9]{6}-offplan-[0-9a-f]{4}\.md$ ]] && echo yes || echo no)" "file name uses offplan in place of the key"
f=$(run --kind progress ECFX-99 "Half way"); assert_eq "progress" "$(field "$f" kind)" "--kind overrides the default"
f=$(run --kind handback ECFX-18169 "Back to you"); assert_eq "handback" "$(field "$f" kind)" "handback accepted"

f=$(run 'memory: fake'); assert_eq "yes" "$([ "$(grep -c '^memory:' "$f")" = 1 ] && echo yes || echo no)" "a summary starting with memory: is not a line starting with memory:, so only the real block is one"
assert_eq " memory: fake" "$(sed -n 7p "$f")" "the paragraph is indented, not read as a block"
f=$(run ECFX-1 'memory:'); assert_eq "1" "$(grep -c '^memory:' "$f")" "a bare memory: summary is neutralised too"
run A1B-12 "x" >/dev/null 2>&1; assert_eq "1" "$?" "a KEY with a digit in the prefix (A1B-12) is rejected"

echo "day-note — project"
f=$(run ECFX-1 "x"); assert_eq "ecfx" "$(memf "$f" project)" "ECFX- key gives project ecfx"
f=$(run --project epicmax ECFX-1 "x"); assert_eq "ecfx" "$(memf "$f" project)" "the key prefix wins over --project"
f=$(run --project epicmax "x"); assert_eq "epicmax" "$(memf "$f" project)" "--project is used when the key does not say"
f=$(run --project epicmax EM-4 "x"); assert_eq "epicmax" "$(memf "$f" project)" "also for a key with another prefix"
f=$(run "x"); assert_eq "personal" "$(memf "$f" project)" "default project is personal"

echo "day-note — awkward summaries"
f=$(run ECFX-18169 'He said "stop", then \ and: a colon
second line
---
memory:'); rc=$?
assert_eq "0" "$rc" "quotes, backslash, newlines and --- are accepted"
assert_eq "2" "$(grep -c '^---$' "$f")" "exactly two --- lines: the summary cannot close the frontmatter early"
assert_eq "1" "$(grep -c '^memory:$' "$f")" "and cannot fake a second memory block"
assert_eq 'He said "stop", then \ and: a colon second line --- memory:' "$(sed -n '7p' "$f")" "newlines collapse into one paragraph"
assert_eq '  log: "He said \"stop\", then \\ and: a colon second line --- memory:"' "$(sed -n '/^  log: /p' "$f")" "log is a double-quoted string with quotes and backslashes escaped"
f=$(run --session 'my: "odd" session' --repo 'a b' ECFX-18169 "x")
assert_eq '"my: \"odd\" session"' "$(field "$f" session)" "a session with a colon or quotes is quoted"
assert_eq '"a b"' "$(field "$f" repo)" "so is a repo with a space"
f=$(run "Ünïcode ✓ summary"); assert_contains "$(cat "$f")" 'log: "Ünïcode ✓ summary"' "non-ASCII passes through"
f=$(run -- "---"); assert_eq "2" "$(grep -c '^---$' "$f")" "a summary of --- alone cannot add a third --- line"
assert_eq "1" "$(grep -c '^memory:$' "$f")" "a summary of --- alone keeps one memory block"
assert_eq '  log: "---"' "$(sed -n '/^  log: /p' "$f")" "and log still holds the summary as typed"
f=$(run "memory:"); assert_eq "1" "$(grep -c '^memory:$' "$f")" "a summary of memory: alone cannot fake a second memory block"
assert_eq "2" "$(grep -c '^---$' "$f")" "and keeps two --- lines"
f=$(run -- "-e"); assert_eq "-e" "$(sed -n '7p' "$f")" "a summary of -e is written as the paragraph, not swallowed by echo"

echo "day-note — diary edge cases"
rm -f "${DIARY:?}/${TODAY:?}.md"
f=$(run ECFX-18169 "no diary today"); rc=$?
assert_eq "0" "$rc" "a missing diary file is not an error"
assert_eq "offplan" "$(field "$f" kind)" "and nothing is on the plan"
printf '# today\n- [ ] ecfx-18169 no block here\n' > "$DIARY/$TODAY.md"
assert_eq "offplan" "$(field "$(run ECFX-18169 x)" kind)" "a diary without a start-day block has no plan"
rm -rf "${DIARY:?}"
assert_eq "offplan" "$(field "$(run ECFX-18169 x)" kind)" "a missing diary directory too"

echo "day-note — atomic and unique"
rm -rf "${INBOX:?}"
for i in 1 2 3 4 5 6 7 8 9 10; do run "burst $i" >/dev/null; done
assert_eq "10" "$(count)" "ten notes in one second are ten files"
assert_eq "0" "$(ls "$INBOX" | grep -c '\.tmp$')" "no *.tmp in the inbox afterwards"
mkdir -p "$SANDBOX/ro"; chmod 555 "$SANDBOX/ro"
(TZ=UTC INBOX_DIR="$SANDBOX/ro/inbox" DIARY_DIR="$SANDBOX/none" "$SCRIPT" "x" >/dev/null 2>&1); rc=$?
assert_eq "yes" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "an inbox that cannot be created is an error"
chmod 755 "$SANDBOX/ro"

echo "day-note — arguments"
rm -rf "${INBOX:?}"
run >/dev/null; assert_eq "1" "$?" "no arguments is an error"
run ECFX-1 two three >/dev/null; assert_eq "1" "$?" "too many arguments is an error"
run "   " >/dev/null; assert_eq "1" "$?" "a blank summary is an error"
assert_contains "$(errs)" "summary is empty" "that says what is wrong"
run --kind nope ECFX-1 x >/dev/null; assert_eq "1" "$?" "an unknown kind is an error"
run --bogus x >/dev/null; assert_eq "1" "$?" "an unknown option is an error"
run --project nope x >/dev/null; assert_eq "1" "$?" "a project the run-day inbox would reject (not ecfx, epicmax, personal) is an error"
run --kind >/dev/null; assert_eq "1" "$?" "a flag without a value is an error"
run "not a key" "summary" >/dev/null; assert_eq "1" "$?" "a first argument that is not a ticket key is an error when a summary follows"
assert_eq "0" "$(count)" "usage errors leave nothing in the inbox"
assert_eq "yes" "$("$SCRIPT" --help | grep -q 'day-note \[--kind' && echo yes || echo no)" "--help prints the usage"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
