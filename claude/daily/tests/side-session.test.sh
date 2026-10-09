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
has "$F" 'claude -n <KEY> "/pickup"' "prints the pickup command"
has "$F" "TaskStop" "stops the running agent"
has "$F" "worktree is kept" "keeps the worktree"
lacks "$F" "worktree remove" "never removes the worktree"
has "$F" 'Never write to `~/wiki`' "keeps the write rule"

echo "== /pickup =="
F="$C/pickup.md"
frontmatter_has "$F" description
frontmatter_has "$F" argument-hint
has "$F" "handoff/<KEY>.md" "loads the hand-off note"
has "$F" 'git branch --show-current' "KEY defaults to the branch's ticket key"
has "$F" 'Never write to `~/wiki` or to the diary' "side sessions never write the vault or the diary"
has "$F" "/report-back" "points at /report-back for the way back"

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
has "$F" "ask the user one question" "asks one question when the kind is not clear"
has "$F" "Never infer the kind from the conversation" "no guessing of the kind"

echo "== contract with /run-day =="
R="$C/run-day.md"
has "$R" "owner=external:<KEY>" "run-day reads the owner /handoff writes"
has "$R" "handoff/<KEY>.md" "run-day knows the hand-off note path"
has "$R" "kind: done | progress | handback | offplan" "run-day reads the kinds /report-back writes"

finish
