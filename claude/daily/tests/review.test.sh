#!/usr/bin/env bash
# Structure checks for commands/review.md and commands/ask-wiki.md.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib.sh"
R="$TEST_DIR/../commands/review.md"
A="$TEST_DIR/../commands/ask-wiki.md"

echo "== review =="
frontmatter_has "$R" description
frontmatter_has "$R" argument-hint
has "$R" '${CLAUDE_PLUGIN_ROOT}/scripts/review-period' "resolves the period with the script"
has "$R" "daily-stats <from> <to>" "numbers come from daily-stats"
has "$R" "never estimate numbers" "no invented numbers"
has "$R" "Shipped" "section Shipped"
has "$R" "Per project" "section Per project"
has "$R" "Decisions" "section Decisions"
has "$R" "Carry-over & time sinks" "section Carry-over"
has "$R" "Brag bullets" "section Brag bullets"
has "$R" "Spawn a \`sonnet\` subagent" "prose by a sonnet subagent"
has "$R" "Subagents never write to the vault" "subagent writes to scratchpad"
has "$R" "qmd update && qmd embed" "re-indexes"
has "$R" 'git -C ~/wiki commit -m "wiki: review' "commit message format"
has "$R" "Nothing this period." "empty sections are explicit"
has "$R" "{{date}}" "fills the template's {{date}} token"
has "$R" "{{period}}" "fills the template's {{period}} token"

echo "== ask-wiki =="
frontmatter_has "$A" description
has "$A" 'model: "haiku"' "runs in a haiku subagent"
has "$A" "~/wiki/AGENTS.md" "follows the vault's ask procedure"
has "$A" "at most 200 words" "answer length cap"
has "$A" "qmd query" "uses qmd"
has "$A" "Never write anything." "read-only"
has "$A" "values from step 2 of the ask procedure" "takes -n and -l from the vault's AGENTS.md"

finish
