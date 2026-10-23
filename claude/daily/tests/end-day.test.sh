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
has "$F" "/daily:review week" "Friday offer"
has "$F" "/daily:review month" "first-workday offer"
has "$F" "Skip this step" "skips cleanly without a vault"
has "$F" "the commit and the end of the run below still happen" "diary commit is not skipped with the memory step"
has "$F" '~/.local/bin/end-day touched "$DAY"' "finds touched projects with end-day touched"
has "$F" '~/.local/bin/end-day entries "$DAY"' "reads the day's log entries with end-day entries"
echo "== fix round 1 =="
has "$F" "do not continue until answered" "stops for the user's answer before consolidating"
has "$F" "## Process the inbox first" "inbox section exists before the report"
has "$F" "only skips the comparison" "a missing start-day block never skips the inbox"
has "$F" "Never regress" "a re-run keeps filed Done lines"
has "$F" "git -C ~/wiki add -A -- diary work index.md" "adds only existing paths"
lacks "$F" "add -A -- reviews" "work/ covers reviews and friction in one path"
has "$F" "~/.local/bin/wiki-sync" "pushes the day to the VPS right after committing"
lacks "$F" "add diary projects reviews index.md" "no unconditional reviews add"
awk '/^## Process the inbox first/{a=NR} /^## Write the report/{b=NR} /^## Unreported activity/{c=NR} END{exit !(a&&b&&c&&a<b&&b<c)}' "$F" && pass "inbox, then report, then unreported" || fail "section order" "wrong order"
awk '/DAY=/{if(!d)d=NR} /run-day\/inbox/{if(!i)i=NR} END{exit !(d&&i&&d<i)}' "$F" && pass "DAY defined before the inbox" || fail "DAY before inbox" "wrong order"
lacks "$F" 'index($0' "no awk \$0 (the command markdown substitutes it)"

echo "== fix wave =="
has "$F" "~/.claude/plugins/cache/*/daily/*/commands/run-day.md" "locates run-day.md in the plugin cache"
has "$F" "~/projects/dotfiles/claude/daily/commands/run-day.md" "falls back to the main checkout"
for t in grep glab jq printf wc fd '[' 'git -C ~/wiki'; do has "$F" "Bash($t" "allows $t"; done
awk '/^## Unreported activity/{s=1} /^## Consolidate memory/{s=0} s&&/^DAY=/{d=1} END{exit !d}' "$F" && pass "Unreported block defines DAY" || fail "Unreported DAY" "no DAY= line"
has "$F" "(yesterday)" "parenthesised case pattern"
awk '/^## Consolidate memory/{a=NR} /^## Index, commit and end the run/{b=NR} END{exit !(a&&b&&a<b)}' "$F" && pass "diary commit is its own step after memory" || fail "commit step" "missing"
lacks "$F" "ls ~/wiki/*" "no zsh-failing globs"


has "$F" "**Waiting on you**" "report lists open decisions"
has "$F" "decide list" "reads them from the queue"

echo "== check the system =="
P="$TEST_DIR/../../../pi/prompts/end-day.md"
for f in "$F" "$P"; do
  side="$(basename "$(dirname "$f")")"
  has "$f" "~/.local/bin/system-check --record" "$side: records the run so its findings count as seen"
  has "$f" "An \`install\` finding has no page to fix" "$side: install findings are not page fixes"
  has "$f" "\`install <glob>\` line in \`known.txt\`" "$side: offers acknowledging with an install glob"
  has "$f" "ask once" "$side: asks once for all install findings"
done

echo "== coach: concepts, cards, secret =="
for f in "$F" "$P"; do
  side="$(basename "$(dirname "$f")")"
  has "$f" '`concepts`' "$side: brief receives concepts"
  has "$f" '`cards`' "$side: reply may carry cards"
  has "$f" "15 concepts" "$side: concept candidates are capped"
  has "$f" "1500" "$side: answers are cut for the brief"
  has "$f" '`secret`' "$side: secret items are handled"
  has "$f" '`restated`' "$side: restated items are handled"
  has "$f" "never sees or asks for the value" "$side: the model never touches the secret value"
  has "$f" "a secret found in a file (location only)" "$side: secret items are described as found in a file"
  has "$f" '`Change: <file or key>: <before> → <after>`' "$side: safety-touching proposals state the exact change"
  has "$f" "a guard, a permission or allow/deny rule, a hook, auto mode or a settings file" "$side: names what counts as safety-touching"
  has "$f" '`Direction: <the rule as an imperative one-liner>`' "$side: a restated proposal names its direction"
  has "$f" '`Scope: <global' "$side: and its scope"
  has "$f" "enforce it in a script, with no \`Direction:\` line" "$side: or is a script fix"
  lacks "$f" "a credential seen in a prompt or output" "$side: no stale secret description"
done

echo "== coach: land the day's fixes =="
for f in "$F" "$P"; do
  side="$(basename "$(dirname "$f")")"
  has "$f" "## Land the coach's fixes" "$side: land step exists"
  has "$f" "~/.local/bin/coach-fix land --detach" "$side: lands detached, so no tool timeout cuts it short"
  awk '/^## Index, commit and end the run/{a=NR} /^## Land the coach.s fixes/{b=NR} /^## Offer reviews/{c=NR} END{exit !(a&&b&&c&&a<b&&b<c)}' "$f" && pass "$side: land comes after the report is saved and committed" || fail "$side: land order" "wrong order in $f"
  has "$f" "a land is already running" "$side: names the busy line"
  has "$f" "Do not wait for the land" "$side: does not wait for the background land"
done
has "$F" "Bash(~/.local/bin/coach-fix:*)" "claude: allows coach-fix"

finish
