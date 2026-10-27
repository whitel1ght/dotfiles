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

echo "CLAUDE.md — coach rules"
prefs=$(section "$MD" Preferences)
has "$prefs" "Edit and Write accept only a file opened with the Read tool" "F-016/F-022 only the Read tool counts"
has "$prefs" "since the last context summary" "F-016 Read again after a context summary"
has "$prefs" "For an exact replacement in one file use the Edit tool" "F-045 Edit over python or sed"
has "$prefs" "never reach for a destructive git or \`rm\` command" "F-004 no destructive step past a block"
has "$prefs" "Ask clarifying questions in plain text" "F-014 questions in plain text"
has "$(section "$MD" Secrets)" 'right: `curl -H "PRIVATE-TOKEN: $(secret NAME)" …`; wrong: `secret NAME`' "F-013 secret example"
has "$(section "$MD" Artifacts)" "never resend the refused content unchanged" "F-028 merge onto the live version"
apis=$(section "$MD" "GitLab and Jira APIs")
has "$apis" 'Run `/mr-description` before any `glab mr create`' "F-015 /mr-description before MR writes"
replies=$(section "$MD" "Review replies")
has "$replies" '`mr-review-response` skill, unasked' "F-051 replies through mr-review-response"
has "$replies" '"post it" or "post both" posts exactly what was shown' "F-051 a yes posts what was shown"
has "$(section "$MD" Worktrees)" "Double-quote every variable" "F-030 quoted variables in worktree sessions"

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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
