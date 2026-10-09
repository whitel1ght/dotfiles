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
has "$R" '${CLAUDE_PLUGIN_ROOT}/scripts/review-extract' "extraction goes through the tested script"
has "$R" "review-period <child level> <child id>" "recurses into grandchildren"
has "$R" "skip children whose file already exists" "skips existing children"
has "$R" "A period with no inputs is still written" "empty periods are written without asking"
has "$R" "missing lower-level periods" "threshold counts missing lower levels"
has "$R" "excluding the requested period" "threshold excludes the requested period"
has "$R" "ISO weeks by their Thursday" "month edges note"
has "$R" "must appear in \`daily-stats\` output" "every MR link must come from stats or given files"
has "$R" "links its decision file or is omitted" "decisions lines link a file"
has "$R" "nothing to commit" "identical regeneration is fine"
lacks "$R" "ls ~/wiki/diary" "no failing diary glob"
for c in "$TEST_DIR"/../commands/*.md "$TEST_DIR"/../../commands/end-day.md; do
  [ -f "$c" ] || continue
  if grep -nE '\$[0-9]' "$c" >/dev/null; then fail "$(basename "$c") has no \$0-\$9" "$(grep -nE '\$[0-9]' "$c" | head -3)"; else pass "$(basename "$c") has no \$0-\$9"; fi
done

echo "== ask-wiki =="
frontmatter_has "$A" description
has "$A" 'model: "haiku"' "runs in a haiku subagent"
has "$A" "~/wiki/AGENTS.md" "follows the vault's ask procedure"
has "$A" "at most 200 words" "answer length cap"
has "$A" "qmd query" "uses qmd"
has "$A" "Never write anything." "read-only"
has "$A" "values from step 2 of the ask procedure" "takes -n and -l from the vault's AGENTS.md"
has "$A" "qmd://<collection>/<relpath>" "names the qmd path form from --files"
has "$A" "~/wiki/projects/<collection>/<relpath>" "maps ecfx, epicmax and personal under projects/"
has "$A" "~/wiki/<collection>/<relpath>" "maps diary, reviews and notes at the vault top"
has "$A" "Never cite a \`qmd://\` path" "forbids citing qmd paths"
has "$A" "ecfx, epicmax, personal, diary, reviews, notes" "lists all six collections"
has "$A" "does not contain it" "no-answer case says memory lacks it"
has "$A" "Do not offer further searches" "no-answer case offers no extra searches"

finish
