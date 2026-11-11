#!/bin/bash
# Pins the rule lines of the shared claude/CLAUDE.md that coach fixes added, so an edit that
# drops one fails here. Usage: bash claude/CLAUDE.test.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MD="$DIR/CLAUDE.md"
SKILLS=("$DIR/skills/handle-ticket/SKILL.md" "$DIR/../pi/skills/handle-ticket/SKILL.md")
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
# section FILE HEADING: the lines under "## HEADING" up to the next "## ", joined into one line
section() { awk -v h="## $2" '$0 == h {on=1; next} /^## /{on=0} on' "$1" | tr '\n' ' ' | tr -s ' '; }
has() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] missing" ;; esac; }

echo "CLAUDE.md and ship-mr — a draft means unfinished work"
gitlab=$(section "$MD" "GitLab and Jira APIs")
has "$gitlab" "An MR stays in draft only while its work is unfinished" "the rule itself"
has "$gitlab" "A finished MR ships without asking" "shipping takes no card (D-447)"
has "$gitlab" "Depends on:" "a dependency goes in the description"
for ship in "$DIR/commands/ship-mr.md" "$DIR/../pi/prompts/ship-mr.md"; do
  doc=$(tr '\n' ' ' < "$ship" | tr -s ' ')
  has "$doc" "A dependency is never a reason to stay in draft" "$ship: a dependency does not hold the ship"
  has "$doc" "Depends on: <repo>!<iid>, merge after it" "$ship: the dependency line for the description"
  has "$doc" "left in draft: <the unfinished work>" "$ship: only unfinished work is a reason in the report"
  has "$doc" "Reading the diff yourself is not a review" "$ship: the panel is the review (D-450)"
  has "$doc" "the review panel could not run" "$ship: no panel, no ship"
done

echo "CLAUDE.md, review-local and handle-ticket — mr-ship needs a recorded review"
has "$gitlab" "refuses an MR with no recorded review" "the gate is stated"
has "$gitlab" "\`--no-review\` is mine alone" "the bypass is the user's"
for doc_file in "$DIR/commands/review-local.md" "$DIR/../pi/prompts/review-local.md" \
    "$DIR/skills/handle-ticket/SKILL.md" "$DIR/../pi/skills/handle-ticket/SKILL.md"; do
  doc=$(tr '\n' ' ' < "$doc_file" | tr -s ' ')
  has "$doc" "mr-ship --reviewed <repo> <iid> <head_sha>" "$doc_file: records the review"
  has "$doc" "\`Panel:\` line" "$doc_file: the line the record checks for"
done

echo "CLAUDE.md — coach rules"
prefs=$(section "$MD" Preferences)
has "$prefs" "Edit and Write accept only a file opened with the Read tool" "F-016/F-022 only the Read tool counts"
has "$prefs" "since the last context summary" "F-016 Read again after a context summary"
has "$prefs" "For an exact replacement in one file use the Edit tool" "F-045 Edit over python or sed"
has "$prefs" "never reach for a destructive git or \`rm\` command" "F-004 no destructive step past a block"
has "$prefs" "five sentences or fewer" "F-100 short messages to people"
questions=$(section "$MD" Questions)
has "$questions" "goes to the decisions deck through \`ask_user\`, in every session" "every question goes to the decisions deck"
has "$questions" "Never use the question form (AskUserQuestion)" "F-014 no question form"
has "$questions" "Every option on a card names who acts" "options name who acts (2026-11-05)"
has "$questions" "Never write I," "no first person in options"
has "$questions" "when I answer in the chat, \`withdraw\` the card" "an answer in the chat withdraws the card"
has "$questions" "also file it with \`tell_user\`" "a late answer also goes to the deck"
has "$questions" "already names the next step, do that step" "F-081 do the named next step"
has "$(section "$MD" Secrets)" 'right: `curl -H "PRIVATE-TOKEN: $(secret NAME)" …`; wrong: `secret NAME`' "F-013 secret example"
has "$(section "$MD" Artifacts)" "never resend the refused content unchanged" "F-028 merge onto the live version"
has "$(section "$MD" Artifacts)" "Before publishing to an existing artifact this session has not read or published, read it first" "F-054 read an artifact before publishing over it"
apis=$(section "$MD" "GitLab and Jira APIs")
has "$apis" 'Run `/mr-description` before any `glab mr create`' "F-015 /mr-description before MR writes"
replies=$(section "$MD" "Review replies")
has "$replies" '`mr-review-response` skill, unasked' "F-051 replies through mr-review-response"
has "$replies" '"post it" or "post both" posts exactly what was shown' "F-051 a yes posts what was shown"
has "$(section "$MD" Worktrees)" "Double-quote every variable" "F-030 quoted variables in worktree sessions"

echo "CLAUDE.md — a finished dotfiles branch is landed by the agent"
tooling=$(section "$MD" "Tests and tooling")
has "$tooling" "land it yourself with \`dot-land <branch>\`" "F-109 the agent lands dotfiles branches"
has "$tooling" "never hand a dotfiles merge back to me" "F-109 no merge handed back"
has "$tooling" "If the tests fail or \`dot-land\` refuses" "F-109 a red branch is not landed"
has "$tooling" "ECFX MRs I merge in the GitLab UI" "F-109 ECFX merges stay the user's"

echo "handle-ticket — draft MR step (Claude and pi copies)"
for SKILL in "${SKILLS[@]}"; do
  name="${SKILL#"$DIR/"}"
  step=$(awk '/^Run `\/mr-description` for the body first/{print NR; exit}' "$SKILL")
  create=$(awk '/^glab mr create --draft/{print NR; exit}' "$SKILL")
  [ -n "$step" ] && [ -n "$create" ] && [ "$step" -lt "$create" ] &&
    pass "F-015 /mr-description comes before glab mr create in $name" ||
    fail "F-015 /mr-description comes before glab mr create in $name" "step line [$step], create line [$create]"
done

echo "handle-ticket — JIRA_BASE defined where used (Claude and pi copies)"
for SKILL in "${SKILLS[@]}"; do
  name="${SKILL#"$DIR/"}"
  if ! grep -q '\$JIRA_BASE' "$SKILL" || grep -q '^[[:space:]]*JIRA_BASE=' "$SKILL"; then
    pass "JIRA_BASE is defined wherever \$JIRA_BASE is used in $name"
  else
    fail "JIRA_BASE is defined wherever \$JIRA_BASE is used in $name" "\$JIRA_BASE used, no JIRA_BASE= line"
  fi
done

echo "CLAUDE.md — mockups are proposals, Chrome is the browser (insights 2026-11-11)"
evidence=$(section "$MD" "Evidence")
has "$evidence" "A mockup or design is a proposal, not a decision" "mockup details are not decisions"
has "$evidence" "under open questions, with whose mockup it is" "they are listed with their source"
browser=$(section "$MD" "Browser")
has "$browser" "Claude in Chrome extension tools" "UI checks run in Chrome"
has "$browser" "stop and tell me; never switch to Playwright or a terminal browser pane" "no silent browser fallback"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
