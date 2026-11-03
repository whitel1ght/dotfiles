#!/bin/bash
# Tests for bin/friction. FRICTION_DIR points into a sandbox and TZ is pinned, so
# nothing here touches ~/.local/state. friction calls only jq.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/friction"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'chmod -R u+w "${SANDBOX:?}" 2>/dev/null; rm -rf "${SANDBOX:?}"' EXIT
DIR="$SANDBOX/friction"

run() { TZ=Etc/GMT-3 FRICTION_DIR="$DIR" "$SCRIPT" "$@"; }
sig() { run sig "$@"; }
TODAY=$(TZ=Etc/GMT-3 date +%F)
FILE="$DIR/$TODAY.jsonl"

echo "friction sig — normalisation"
assert_eq "changes-since:auth:outlook not connected" "$(sig changes-since auth 'Outlook NOT   connected')" "lowercases and collapses whitespace"
assert_eq "a:other:fetch <url> failed" "$(sig a other 'fetch https://gitlab.com/ecfx/x/-/merge_requests/12?a=b failed')" "URL -> <url>"
assert_eq "a:other:cannot read <path> or <path>" "$(sig a other 'cannot read /Users/dmitry/x/y.md or ~/wiki/diary')" "absolute and ~ paths -> <path>"
assert_eq "a:other:<key> and <key> blocked" "$(sig a other 'ECFX-123 and AB2-9 blocked')" "Jira keys -> <key>"
assert_eq "a:other:head <hex> and <hex>" "$(sig a other 'head 6e6c8f0876dde87 and DEADBEEF01')" "hex of 7+ chars -> <hex>"
assert_eq "a:other:decade and cafebabe stay" "$(sig a other 'decade and cafebabe stay')" "a hex-looking word without a digit is kept"
assert_eq "a:other:at <ts> and <ts> then <ts>" "$(sig a other 'at 2026-10-15T09:12:03+03:00 and 2026-10-15 then 09:12:03')" "ISO dates and times -> <ts>"
assert_eq "a:retry:attempt <n> of <n> after <n>ms" "$(sig a retry 'attempt 2 of 3 after 1500ms')" "remaining digit runs -> <n>"
assert_eq "a:other:<path>" "$(sig a other '/usr/bin/env')" "a path alone"

echo "friction sig — families"
WT_FAMILY="claude:tool_error:bash: the worktree isolation check refused the command"
assert_eq "$WT_FAMILY" "$(sig claude tool_error 'Bash: This session is isolated in the worktree /Users/d/w/x, but this command is too complex to verify that it stays inside the worktree.')" "a worktree refusal collapses to its family"
assert_eq "$WT_FAMILY" "$(sig claude tool_error 'Bash: This session is isolated in the worktree /Users/d/w/x, but this command runs git -C against another repository.')" "so does another wording of it"
assert_eq "claude:tool_error:skill: an inline shell command in a skill failed" "$(sig claude tool_error 'Skill: Shell command failed for pattern "!`git status --short`": [stderr] fatal')" "inline skill shell failures share one family"
assert_eq "claude:tool_error:edit: <tool_use_error>string to replace not found in file." "$(sig claude tool_error 'Edit: <tool_use_error>String to replace not found in file.')" "other messages keep their own signature"
assert_eq "120" "$(sig a other "$(printf 'x%.0s' $(seq 200))" | cut -d: -f3 | tr -d '\n' | wc -c | tr -d ' ')" "norm is cut to 120 chars"
assert_eq "same" "$([ "$(sig s k 'retry 1 of ECFX-1')" = "$(sig s k 'retry 9 of ECFX-77')" ] && echo same || echo different)" "messages differing only in numbers and keys share a sig"

echo "friction — append"
run --harness claude --key ECFX-123 --source changes-since auth "Outlook not connected (try 3)"; rc=$?
assert_eq "0" "$rc" "exit 0"
assert_eq "1" "$(wc -l <"$FILE" | tr -d ' ')" "one line in <FRICTION_DIR>/<today>.jsonl, dir created on demand"
assert_eq "harness,source,kind,key,msg,sig" "$(jq -r '[keys_unsorted[] | select(. != "ts")] | join(",")' "$FILE")" "fields: ts, harness, source, kind, key, msg, sig"
assert_eq "yes" "$([[ "$(jq -r .ts "$FILE")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+03:00$ ]] && echo yes || echo no)" "ts is local time with a +03:00 style offset"
assert_eq "claude|changes-since|auth|ECFX-123|Outlook not connected (try 3)" "$(jq -r '[.harness,.source,.kind,.key,.msg]|join("|")' "$FILE")" "values as given"
assert_eq "changes-since:auth:outlook not connected (try <n>)" "$(jq -r .sig "$FILE")" "sig is the §2 signature"
out=$(run other "second event"); assert_eq "" "$out" "prints nothing"
assert_eq "2" "$(wc -l <"$FILE" | tr -d ' ')" "appends, never rewrites"
assert_eq "script|unknown|" "$(sed -n 2p "$FILE" | jq -r '[.harness,.source,.key]|join("|")')" "defaults: harness script, source unknown, empty key"
run tool_error "multi
line		message"
assert_eq "multi line message" "$(sed -n 3p "$FILE" | jq -r .msg)" "newlines and tabs become single spaces"
run other "$(printf 'y%.0s' $(seq 500))"
assert_eq "300" "$(sed -n 4p "$FILE" | jq -r '.msg|length')" "msg is cut to 300 chars"
assert_eq "4" "$(wc -l <"$FILE" | tr -d ' ')" "still one line per event"

echo "friction — never breaks the caller"
mkdir -p "$SANDBOX/ro"; chmod 555 "$SANDBOX/ro"
(TZ=Etc/GMT-3 FRICTION_DIR="$SANDBOX/ro/sub" "$SCRIPT" other "cannot write" 2>"$SANDBOX/err"); rc=$?
assert_eq "0" "$rc" "exit 0 when the dir is not writable"
(TZ=Etc/GMT-3 FRICTION_DIR="$DIR" "$SCRIPT" 2>/dev/null); assert_eq "0" "$?" "exit 0 on missing arguments"
(TZ=Etc/GMT-3 FRICTION_DIR="$DIR" "$SCRIPT" --bogus 2>/dev/null); assert_eq "0" "$?" "exit 0 on a bad option"
assert_eq "4" "$(wc -l <"$FILE" | tr -d ' ')" "and nothing is appended for a malformed call"

echo
echo "friction: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
