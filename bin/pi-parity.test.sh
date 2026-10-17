#!/bin/bash
# Tests for bin/pi-parity. A sandbox git repo with the dotfiles layout stands in
# for the real one.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/pi-parity"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in: $2" ;; esac; }
lacks() { case "$2" in *"$3"*) fail "$1" "[$3] unexpectedly in: $2" ;; *) pass "$1" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$SANDBOX/dotfiles"
mkdir -p "$R/claude/commands" "$R/claude/daily/commands" "$R/pi/prompts"
git -C "$R" init -q -b main
printf -- '---\ndescription: c\n---\nStart the day.\n' > "$R/claude/commands/start-day.md"
printf -- '---\ndescription: p\n---\nStart the day in pi.\n' > "$R/pi/prompts/start-day.md"
printf -- '---\ndescription: c\n---\nRun the day.\n' > "$R/claude/daily/commands/run-day.md"
printf -- '---\ndescription: p\n---\nRun the day in pi.\n' > "$R/pi/prompts/run-day.md"
printf -- '---\ndescription: p\n---\npi only.\n' > "$R/pi/prompts/pi-only.md"
git -C "$R" add -A && git -C "$R" commit -qm init
run() { (cd "$R" && "$SCRIPT" "$@") 2>&1; }
msg() { printf '%s\n' "$1" > "$SANDBOX/msg"; echo "$SANDBOX/msg"; }

echo "check"
out="$(run)"; code=$?
check_code() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "exit $3, want $2"; }
check_code "unmarked pairs make check exit 1" 1 "$code"
has "lists a pair never compared" "$out" "start-day"
has "says it was never compared" "$out" "never compared"
has "finds twins in the daily plugin too" "$out" "run-day"
lacks "pi-only prompts have no twin to track" "$out" "pi-only"

run mark start-day run-day >/dev/null
out="$(run)"; code=$?
check_code "all in step: exit 0" 0 "$code"
has "says so" "$out" "in step"
[ -f "$R/pi/parity.json" ] && pass "mark writes the ledger" || fail "mark writes the ledger" "no pi/parity.json"

printf 'Also check Slack.\n' >> "$R/claude/commands/start-day.md"
out="$(run)"; code=$?
check_code "a changed Claude side: exit 1" 1 "$code"
has "names the drifted pair" "$out" "start-day"
lacks "leaves the other pair alone" "$out" "run-day"

out="$(run diff start-day)"
has "diff shows what changed on the Claude side" "$out" "+Also check Slack."

out="$(run mark nope 2>&1)"; code=$?
check_code "mark of an unknown name exits 2" 2 "$code"

echo "commit-msg"
git -C "$R" add claude/commands/start-day.md
out="$(run commit-msg "$(msg 'feat: slack in start-day')")"; code=$?
check_code "a Claude playbook change without its pi twin is stopped" 1 "$code"
has "names the pi prompt to port" "$out" "pi/prompts/start-day.md"
run commit-msg "$(msg $'feat: slack\n\nPi: later')" >/dev/null; check_code "'Pi: later' lets it through" 0 "$?"

printf 'Also check Slack in pi.\n' >> "$R/pi/prompts/start-day.md"
run mark start-day >/dev/null
git -C "$R" add -A
run commit-msg "$(msg 'feat: slack in both')" >/dev/null; check_code "ported and marked in the same commit passes" 0 "$?"
git -C "$R" commit -qm both

printf 'pi tweak\n' >> "$R/pi/prompts/run-day.md"; git -C "$R" add -A
run commit-msg "$(msg 'fix: pi only')" >/dev/null; check_code "a pi-only change passes" 0 "$?"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
