#!/usr/bin/env bash
# Structure checks for the --auto mode of the fix-friction playbooks (both harnesses).
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib.sh"
C="$TEST_DIR/../commands/fix-friction.md"
P="$TEST_DIR/../../../pi/prompts/fix-friction.md"

for f in "$C" "$P"; do
  side="$(basename "$(dirname "$f")")"
  echo "== $side =="
  has "$f" "## 4. Stop" "$side: interactive mode keeps its stop for the user"
  has "$f" "## Auto mode" "$side: auto mode section exists"
  has "$f" "--auto" "$side: names the flag"
  has "$f" 'wt add <repo> coach-$F' "$side: worktree coach-F from local main"
  has "$f" "different model tier" "$side: reviewer on another tier"
  has "$f" "At most two fix rounds" "$side: caps the fix rounds"
  has "$f" '~/.local/bin/coach-fix built $F --repo' "$side: reports a built branch"
  has "$f" '--test-cmd' "$side: records the suite command"
  has "$f" '~/.local/bin/coach-fix built $F --mr' "$side: reports a draft MR"
  has "$f" '~/.local/bin/coach-fix fail $F --reason' "$side: reports a failure"
  has "$f" "needs the user:" "$side: user steps become a failure with the steps"
  has "$f" "Never merge" "$side: auto mode never merges"
  has "$f" "never asks" "$side: auto mode runs unattended"
  has "$f" "ECFX" "$side: ECFX repos are out"
  has "$f" "secret" "$side: secret entries are refused"
  has "$f" "--draft" "$side: claude-components MR is a draft"
  has "$f" "no reviewers" "$side: requests no reviewers"
  has "$f" "mr-description" "$side: writes the description with mr-description"
  lacks "$f" "dangerously" "$side: no permission bypass"
done

finish
