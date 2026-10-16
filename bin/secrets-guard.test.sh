#!/bin/bash
# Tests for bin/secrets-guard, the PreToolUse hook that keeps agents out of
# ~/.secrets. Each case feeds it the JSON Claude Code (and pi's claude-hooks
# extension) sends for a Bash call.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/secrets-guard"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
run() { # run <command> -> exit code of the hook
    jq -n --arg c "$1" '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' \
        | "$SCRIPT" >/dev/null 2>"$ERR"
}
blocks() { run "$2"; local code=$?; [ "$code" -eq 2 ] && pass "$1" || fail "$1" "exit $code for: $2"; }
allows() { run "$2"; local code=$?; [ "$code" -eq 0 ] && pass "$1" || fail "$1" "exit $code for: $2 ($(cat "$ERR"))"; }

ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT

echo "the folder"
blocks "cat of the file" 'cat ~/.secrets/secrets.env'
blocks "absolute path" "head /Users/x/.secrets/recovery.md"
blocks "listing the folder" 'ls -la $HOME/.secrets'
blocks "search into it" 'rg --hidden token ~/.secrets'
blocks "copying it out" 'cp ~/.secrets/secrets.env /tmp/x'
run 'cat ~/.secrets/secrets.env'
case "$(cat "$ERR")" in *secret*) pass "says why" ;; *) fail "says why" "$(cat "$ERR")" ;; esac

echo "the secret command"
blocks "bare call prints a value" 'secret JIRA_TOKEN'
blocks "after a separator" 'cd /tmp && secret JIRA_TOKEN'
blocks "piped into something" 'secret JIRA_TOKEN | pbcopy'
blocks "by path" '~/.local/bin/secret JIRA_TOKEN'
blocks "the editor" 'secrets'
allows "inline substitution keeps the value out of output" 'curl -u "me:$(secret JIRA_TOKEN)" https://x'
allows "two substitutions" 'X=$(secret A) Y=$(secret B) tool'
allows "listing names" 'secret -l'
allows "the word in text" 'git commit -m "keep secret values out of logs"'
allows "grep for the word" 'rg -n secret bin/'
allows "a markdown mention" 'echo "edit them with `secrets`" >> notes.md'
allows "inside a quoted pattern" "rg -n 'a|box/secrets|b' ."
allows "inside a double-quoted message" 'die "missing; run: secrets"'

echo "the team jira.env link"
blocks "reading it" 'cat ~/.config/ecfx/jira.env'
blocks "sourcing it" 'source ~/.config/ecfx/jira.env && echo $JIRA_TOKEN'
allows "checking it exists" 'test -f ~/.config/ecfx/jira.env && echo ok'

echo "other calls"
allows "ordinary command" 'git status'
printf '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' | "$SCRIPT" >/dev/null 2>&1
[ $? -eq 0 ] && pass "non-Bash tools pass (deny rules cover them)" || fail "non-Bash tools pass" "blocked"
printf 'not json' | "$SCRIPT" >/dev/null 2>&1
[ $? -eq 0 ] && pass "bad input never blocks" || fail "bad input never blocks" "blocked"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
