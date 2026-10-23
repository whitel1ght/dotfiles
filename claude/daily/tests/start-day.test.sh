#!/usr/bin/env bash
# Structure checks for the coach step in the start-day playbooks (both harnesses).
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib.sh"
C="$TEST_DIR/../../commands/start-day.md"
P="$TEST_DIR/../../../pi/prompts/start-day.md"

for f in "$C" "$P"; do
  side="$(basename "$(dirname "$f")")"
  echo "== $side =="
  has "$f" "## 4. Coach" "$side: coach step exists"
  has "$f" "## 5. File it" "$side: File it is renumbered"
  lacks "$f" "## 4. File it" "$side: no stale File it number"
  awk '/^## 3\. Write the plan/{a=NR} /^## 4\. Coach/{b=NR} /^## 5\. File it/{c=NR} END{exit !(a&&b&&c&&a<b&&b<c)}' "$f" && pass "$side: coach sits between plan and File it" || fail "$side: order" "wrong order in $f"
  has "$f" "friction-ledger coach-offer --date" "$side: asks the ledger for the offer"
  has "$f" "friction-ledger coach-answer" "$side: records each answer"
  has "$f" "**loosens a safety control**" "$side: safety label wording"
  has "$f" "before → after" "$side: safety item shows the exact change"
  has "$f" "the proposal does not state the exact change" "$side: no yes without a stated change"
  has "$f" "coach-fix enqueue F-NNN --approved-safety" "$side: safety yes passes the flag"
  has "$f" 'coach-fix enqueue F-NNN`' "$side: non-safety yes passes no flag"
  has "$f" "retry the" "$side: a failed enqueue is retried once"
  has "$f" 'coach-answer F-NNN later --date "$T"` (a different answer' "$side: a second failure turns the answer into later"
  has "$f" "the suggestion will come back" "$side: user is told the suggestion returns"
  lacks "$f" "stays \`landing\`" "$side: no false landing claim"
  has "$f" "record a no as no, and turn a yes into later" "$side: no stays no on a change-less safety item"
  has "$f" "not waiting for an answer" "$side: exit 1 is reported, not retried"
  has "$f" "cards due --limit 5 --json" "$side: quiz pulls due cards"
  has "$f" "cards grade" "$side: quiz grades"
  has "$f" "cards drop" "$side: drop is handled"
  has "$f" "\`skip\`" "$side: skip ends the quiz"
  has "$f" "do not call \`cards grade\`" "$side: no grade without an answer"
  has "$f" "Nothing from this step goes into the diary" "$side: no-diary rule"
  has "$f" "never mentions the coach" "$side: plan text stays coach-free"
  has "$f" "friction-ledger coach-log --date" "$side: logs the counts"
  has "$f" "### Monthly tool review" "$side: monthly review subsection"
  has "$f" "Monthly tool review: run it now? (yes/no)" "$side: monthly offer line"
  has "$f" "never blocks the plan" "$side: coach never blocks the plan"
  has "$f" '`results` items also carry `status`' "$side: results name their status, fix and reason fields"
done

finish
