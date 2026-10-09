#!/usr/bin/env bash
# Structure checks for the prompt templates: every placeholder is one the command knows how to fill,
# and the report contract the orchestrator parses is present.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$TEST_DIR/../templates"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
lacks() { grep -qF -- "$2" "$1" && fail "$3" "[$2] unexpectedly in $1" || pass "$3"; }
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "[$2] missing from $1"; }

BRIEF_KEYS="KEY SUMMARY REPO WORKTREE BRANCH DESCRIPTION DONE_WHEN PROJECT"
ROUND_KEYS="KEY REPO MR_IID WORKTREE BRANCH MR_URL PROJECT_PATH EVENT_LINE REPLY_FILE PROJECT"

unknown() { # file, allowed-keys
  grep -o '{{[A-Z_]*}}' "$1" | tr -d '{}' | sort -u | while read -r k; do
    case " $2 " in *" $k "*) ;; *) echo "$k" ;; esac
  done
}

echo "== ticket-brief =="
f="$T/ticket-brief.md"
for k in $BRIEF_KEYS; do has "$f" "{{$k}}" "has {{$k}}"; done
[ -z "$(unknown "$f" "$BRIEF_KEYS")" ] && pass "no unknown placeholders" || fail "unknown placeholders" "$(unknown "$f" "$BRIEF_KEYS")"
has "$f" "memory:" "ends with the memory block"
has "$f" "decision: {title, context, decision, consequences} | none" "memory block has the decision field"
has "$f" "state_change:" "memory block has state_change"
has "$f" "**Draft**" "states the Draft MR rule"
has "$f" "never write to \`~/wiki\`" "forbids vault writes"

echo "== review-round-brief =="
f="$T/review-round-brief.md"
for k in $ROUND_KEYS; do has "$f" "{{$k}}" "has {{$k}}"; done
[ -z "$(unknown "$f" "$ROUND_KEYS")" ] && pass "no unknown placeholders" || fail "unknown placeholders" "$(unknown "$f" "$ROUND_KEYS")"
has "$f" "shared:mr-review-response" "names the reply skill"
lacks "$f" "Claude Opus 5.5" "no hard-coded model in the commit trailer"
has "$f" "commit trailer" "trailer follows the repo or session convention"
has "$f" "Stop before its step 5" "stops before the post step"
has "$f" "discussion:" "reports the discussion id"
has "$f" "reply_file:" "reports the reply file"
has "$f" "memory:" "ends with the memory block"
has "$f" "never write to \`~/wiki\`" "forbids vault writes"
has "$f" "no Slack, no Jira transition" "forbids Slack posts and Jira transitions"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
