#!/usr/bin/env bash
# Structure checks for the memory step added to claude/commands/end-day.md.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib.sh"
F="$TEST_DIR/../../commands/end-day.md"

echo "== original behaviour is kept =="
has "$F" "~/.local/bin/end-day collect" "still collects the day"
has "$F" "~/.local/bin/end-day save" "still files the report"

echo "== unreported activity (spec 4.9 safety net) =="
has "$F" "## Unreported activity" "section exists"
has "$F" "**Unplanned**" "adds under the Unplanned group"
has "$F" "~/.local/state/run-day/inbox/" "processes waiting inbox messages first"
has "$F" "<!-- start-day:start -->" "compares against the plan block only"
has "$F" "Ask which to add" "asks before adding anything"
has "$F" "· note:" "gives added lines evidence for the tick guard"
has "$F" "Bash(awk:*)" "allows the awk and rg pipeline"

echo "== memory step =="
has "$F" "## Consolidate memory" "section exists"
has "$F" "state.md" "rewrites state.md"
has "$F" "60 lines" "keeps it to 60 lines"
has "$F" "qmd update && qmd embed" "re-indexes"
has "$F" 'git -C ~/wiki commit -m "wiki: $DAY day"' "commit message"
has "$F" "~/.local/state/run-day/done" "ends the run"
has "$F" "/review week" "Friday offer"
has "$F" "/review month" "first-workday offer"
has "$F" "Skip this whole step" "skips cleanly without a vault"
has "$F" '~/.local/bin/end-day touched "$DAY"' "finds touched projects with end-day touched"
has "$F" '~/.local/bin/end-day entries "$DAY"' "reads the day's log entries with end-day entries"
lacks "$F" 'index($0' "no awk \$0 (the command markdown substitutes it)"

finish
