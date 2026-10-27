#!/usr/bin/env bash
# Structure checks for commands/handoff.md, pickup.md and report-back.md, and their contract with /run-day.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib.sh"
C="$TEST_DIR/../commands"

echo "== /handoff =="
F="$C/handoff.md"
frontmatter_has "$F" description
frontmatter_has "$F" argument-hint
has "$F" "owner=external:<KEY>" "sets the run-state owner"
has "$F" "needs_you=no" "clears needs_you"
has "$F" "~/.local/state/run-day/handoff/<KEY>.md" "writes the hand-off note"
has "$F" "· with you: <KEY>" "marks the diary line"
has "$F" 'handoff-open <KEY> "<worktree>"' "opens the side session through handoff-open"
has "$F" 'claude -n <KEY> "/daily:pickup <KEY>"' "the window runs the namespaced pickup"
lacks "$F" 'test -n "$TMUX"' "does not decide on \$TMUX, which a harness shell can lack"
has "$F" 'Bash(handoff-open:*)' "allows handoff-open"
has "$F" 'Only when it prints `run: …`' "prints a command only when there is no tmux"
has "$F" '`/daily:report-back done`' "tells the user the namespaced report-back"
has "$F" 'a bare number (`18169`) is `ECFX-` plus the number' "bare number is an ECFX key"
lacks "$F" "disable-model-invocation" "the day session may run handoff itself"
lacks "$F" 'claude -n <KEY> "/pickup' "no bare /pickup in the command"

has "$F" "TaskStop" "stops the running agent"
has "$F" "worktree is kept" "keeps the worktree"
lacks "$F" "worktree remove" "never removes the worktree"
has "$F" 'worktrees/<repo>/<KEY>' "derives the repo from the worktree path"
has "$F" 'Never write to `~/wiki`' "keeps the write rule"

echo "== /pickup =="
F="$C/pickup.md"
frontmatter_has "$F" description
frontmatter_has "$F" argument-hint
has "$F" "handoff/<KEY>.md" "loads the hand-off note"
has "$F" 'git branch --show-current' "KEY defaults to the branch's ticket key"
has "$F" 'Never write to `~/wiki` or to the diary' "side sessions never write the vault or the diary"
has "$F" "/daily:report-back" "points at the namespaced /report-back for the way back"
has "$F" 'a bare number, `18384`, is `ECFX-18384`' "bare number is an ECFX key"
has "$F" "tr a-z A-Z" "uppercases the key from the branch"
has "$F" "will not write the vault or the diary" "summary ends with the no-write line"
has "$F" "do it in the day session" "refuses writes even when asked"
lacks "$F" "say so explicitly" "no override of the never-write rule"
has "$F" "Read(~/.local/state/run-day/handoff/" "allows reading the hand-off note"

echo "== /report-back =="
F="$C/report-back.md"
frontmatter_has "$F" description
frontmatter_has "$F" argument-hint
has "$F" "day-note --kind" "writes the message with day-note"
has "$F" "--mr" "passes the MR"
has "$F" "--session" "passes the session"
has "$F" "glab mr view" "infers the MR from the branch"
has "$F" "ListAgents" "looks for the day session"
has "$F" "SendMessage" "nudges the day session"
has "$F" 'day-$(date +%F)' "names the day session"
has "$F" "inbox: <file name>" "nudge text"
has "$F" "Skip the nudge silently" "the nudge is optional"
has "$F" 'FILE="$(day-note --kind' "captures the path day-note prints"
lacks "$F" "tail -1" "never guesses the newest inbox file"
lacks "$F" "ask the user one question" "no question about the kind"
has "$F" "the kind is \`done\` when MR_STATE is \`merged\`" "merged MR and no kind gives done"
has "$F" "glab mr view -F json | jq -r '.state // empty'" "reads the MR state"
has "$F" "ask the user ONE question, \`done | progress | handback\`, and wait" "open MR and no kind asks"
lacks "$F" "No kind means \`progress\`" "kind no longer defaults to progress"
lacks "$F" "or the user confirms" "done is never inferred from the conversation"
has "$F" "SUMMARY=\$(cat <<'EOF'" "summary passed through a quoted heredoc"
has "$F" '"$SUMMARY"' "summary expanded only as a quoted variable"
lacks "$F" '"<summary>"' "summary never interpolated in double quotes"
lacks "$F" "(claude)" "no ' (claude)' session suffix"
has "$F" "--session claude" "session is claude when there is no key"
has "$F" "Bash(rg:*)" "allows rg"
has "$F" "Bash(tr:*)" "allows tr"
has "$F" "Bash(head:*)" "allows head"
has "$F" "Bash(printf:*)" "allows printf"
has "$F" "Bash(jq:*)" "allows jq"
has "$F" "Bash(cat:*)" "allows cat for the heredoc"
lacks "$F" "case " "no case statement outside the allowed commands"
has "$F" "Never infer the kind from the conversation" "no guessing of the kind"
has "$F" "The kind is always passed explicitly" "day-note always gets --kind"

echo "== contract with /run-day =="
R="$C/run-day.md"
has "$R" "owner=external:<KEY>" "run-day reads the owner /handoff writes"
has "$R" "handoff/<KEY>.md" "run-day knows the hand-off note path"
has "$R" "kind: done | progress | handback | offplan" "run-day reads the kinds /report-back writes"

echo "== fix wave: project inference, allowed-tools =="
has "$F" "--project" "report-back passes --project"
has "$F" "starting \`ecfx-\`" "project from the repo name"
has "$F" '--session <KEY> -- "$KEY" "$SUMMARY"' "-- guards the positional args"
lacks "$F" "Bash(git:*)" "no blanket git"
has "$F" "Bash(git branch:*)" "allows git branch"
has "$F" "Bash(git rev-parse:*)" "allows git rev-parse"
J="$TEST_DIR/../skills/jira-write/SKILL.md"
grep -qx "allowed-tools: Bash" "$J" && fail "jira-write is not unscoped Bash" "unscoped Bash" || pass "jira-write is not unscoped Bash"
has "$J" "allowed-tools: Bash(*/jira-write --dry-run:*)" "only the dry run is pre-approved"
lacks "$J" '"${CLAUDE_PLUGIN_ROOT}' "script path is unquoted so the allow rule matches"
lacks "$J" '"$S"' "no variable carried between Bash calls"


H="$C/handoff.md"
has "$H" "decide withdraw" "handoff withdraws the item's open decisions"
has "$H" "handed off" "with the reason handed off"

echo "== namespaced names in Claude-facing text =="
CL="$TEST_DIR/../.."
if rg -n '(^|[^A-Za-z0-9:/_.-])/(pickup|report-back|fix-friction|handoff|ask-wiki)\b' "$CL" -g '!tests' -g '!*.test.sh' -g '!node_modules' >/tmp/bare-names.$$ 2>&1; then
  fail "no bare daily command names under claude/" "$(head -5 /tmp/bare-names.$$)"
else
  pass "no bare daily command names under claude/"
fi
rm -f /tmp/bare-names.$$
P="$TEST_DIR/../../../pi/prompts"
has "$P/handoff.md" 'a bare number (`18169`) is `ECFX-` plus the number' "pi handoff: bare number rule"
has "$P/handoff.md" "pi -n <KEY> \"/pickup <KEY>\"" "pi handoff opens pi with /pickup KEY"
has "$P/pickup.md" 'a bare number, `18384`, is `ECFX-18384`' "pi pickup: bare number rule"
has "$R" "daily:handoff" "run-day tells the day session to run the handoff itself"

echo "== handoff guard and window reuse =="
G="Only when the user explicitly asks to work this item themselves; never on your own initiative."
has "$H" "$G" "claude handoff: explicit-request guard"
has "$P/handoff.md" "$G" "pi handoff: explicit-request guard"
for f in "$H" "$P/handoff.md"; do
  [ "$(grep -cF -- "$G" "$f")" -ge 2 ] && pass "guard in description and body: $f" || fail "guard twice" "$f"
done
has "$H" "never a second claude session" "reuses an existing window"
has "$H" 'a leading `~` becomes `$HOME`' "worktree is absolute"
has "$P/handoff.md" '~/.local/bin/handoff-open <KEY> "<worktree>" pi' "pi opens its side session through handoff-open"
has "$P/handoff.md" "never a second pi session" "pi reuses an existing window"
lacks "$P/handoff.md" 'test -n "$TMUX"' "pi does not decide on \$TMUX"
has "$P/handoff.md" 'a leading `~` becomes `$HOME`' "pi: worktree is absolute"

finish
