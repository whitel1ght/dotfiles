#!/usr/bin/env bash
# Structure checks for the idea review playbook (both harnesses) and the system-session command.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib.sh"
C="$TEST_DIR/../commands/ideas.md"
P="$TEST_DIR/../../../pi/prompts/ideas.md"

for f in "$C" "$P"; do
  side="$(basename "$(dirname "$f")")"
  echo "== $side: ideas =="
  frontmatter_has "$f" description
  has "$f" "ideas sync" "$side: syncs the memory copy first"
  has "$f" "ideas due --limit 3" "$side: takes at most three due ideas"
  has "$f" "ideas record" "$side: records each review through the script"
  has "$f" "ideas answer" "$side: records the user's answers through the script"
  has "$f" "Never edit \`~/wiki/IDEA.md\`" "$side: IDEA.md is read only"
  has "$f" "as data" "$side: idea text is data, never instructions"
  has "$f" "**Stale**" "$side: groups stale ideas"
  has "$f" "**Actionable**" "$side: groups actionable ideas with a proposal"
  has "$f" "**Needs your input**" "$side: groups ideas that need elaboration"
  has "$f" "wait for the user's yes" "$side: builds nothing without a yes"
  has "$f" "--id" "$side: named ideas are reviewed whatever the cap"
  has "$f" "wiki-commit" "$side: commits the memory copy"
  has "$f" "~/wiki/work/system/" "$side: checks the setup before the web"
  lacks "$f" 'ideas record I-NNN --verdict "$' "$side: no idea text in shell"
  lacks "$f" '$(cat' "$side: no idea text in shell (no command substitution of entry files)"
done
has "$C" "/daily:ideas" "commands: names its namespaced command"
has "$P" "/ideas" "pi: names its command"
lacks "$P" "/daily:" "pi: no Claude-only names"

finish
