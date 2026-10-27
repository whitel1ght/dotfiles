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

echo "heredoc bodies"
NL=$'\n'
TAB=$'\t'
allows "prose line in a cat body" "cat > f <<'EOF'${NL}   secret Done, Later${NL}EOF"
allows "; secret in a python body" "python3 - <<'PY'${NL}x = 1; secret presentation${NL}PY"
allows "unquoted and double-quoted words" "cat <<EOF${NL}secret Done${NL}EOF${NL}cat <<\"EOF\"${NL}secrets${NL}EOF"
allows "<<- with a tab-indented terminator" "cat <<-EOF${NL}secret Done${NL}${TAB}EOF"
allows "two heredocs on one line" "cat <<A <<B${NL}secret one${NL}A${NL}secret two${NL}B"
allows "a here-string is not a heredoc" "cat <<< 'x'${NL}echo ok"
allows "the 2026-10-26 command, replayed" "$(cat "$TEST_DIR/testdata/secrets-guard/heredoc-replay.test.txt")"
blocks "bash heredoc still runs its lines" "bash <<EOF${NL}secret GITLAB_TOKEN${NL}EOF"
blocks "sh -s heredoc" "sh -s <<'EOF'${NL}secret GITLAB_TOKEN${NL}EOF"
blocks "/bin/bash heredoc" "/bin/bash <<'EOF'${NL}secret GITLAB_TOKEN${NL}EOF"
blocks "ssh host heredoc" "ssh host <<'EOF'${NL}secret GITLAB_TOKEN${NL}EOF"
blocks "zsh heredoc after a pipe" "echo x | zsh <<'EOF'${NL}secret GITLAB_TOKEN${NL}EOF"
blocks "bare call after the heredoc ends" "cat <<'EOF'${NL}text${NL}EOF${NL}secret GITLAB_TOKEN"
blocks "terminator must be the whole line" "cat <<'EOF'${NL}EOF x${NL}secret GITLAB_TOKEN"
blocks "an unterminated heredoc stays checked" "cat <<'EOF'${NL}secret GITLAB_TOKEN"
blocks "second heredoc after a skipped one" "cat <<A <<B${NL}x${NL}A${NL}y${NL}B${NL}secret T"
blocks "the folder inside a body" "cat <<EOF${NL}~/.secrets/secrets.env${NL}EOF"
blocks "jira.env read inside a body" "cat <<'EOF'${NL}source ~/.config/ecfx/jira.env${NL}EOF"

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
