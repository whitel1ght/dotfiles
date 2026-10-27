#!/bin/bash
# Tests for zsh/drill.zsh (the drill window's hook) and `drills window`. `drills` is a stub on
# DRILLS_CMD answering what the test sets, so no card or state is touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$TEST_DIR/../zsh/drill.zsh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
STUB="$SANDBOX/drills"
answer() { printf '#!/bin/sh\necho "$*" >>"%s/calls"\ncat <<'"'"'EOF'"'"'\n%s\nEOF\n' "$SANDBOX" "$1" >"$STUB"; chmod +x "$STUB"; }
handle() { DRILLS_CMD="$STUB" zsh -f -c 'source "$1"; _drill_handle "$2"' _ "$HOOK" "$1"; }

echo "drill.zsh"
DRILLS_CMD="$STUB" zsh -f -c 'source "$1"; (( $+functions[_drill_accept_line] && $+functions[_drill_handle] ))' _ "$HOOK"
assert_eq "0" "$?" "sourcing it defines the widget and its handler, even without zle"

answer '{"action": "refuse", "message": "One command please.", "done": false}'
OUT="$(cd "$SANDBOX" && handle "friction-cards count; touch $SANDBOX/marker")"
assert_eq "clear" "$(head -1 <<<"$OUT")" "refused line not run: the buffer is cleared"
assert_has "One command please." "$OUT" "and the message is shown"
assert_eq "no" "$([ -e "$SANDBOX/marker" ] && echo yes || echo no)" "the line never ran"
assert_eq "step -- friction-cards count; touch $SANDBOX/marker" "$(tail -1 "$SANDBOX/calls")" "the line went to drills step as one argument"

answer '{"action": "run", "message": "✓\nGoal: Next one.", "done": false}'
assert_eq "accept" "$(handle "friction-cards count" | head -1)" "a right run-yes line is accepted"
answer '{"action": "checked", "message": "✓ (checked, not run)", "done": false}'
assert_eq "clear" "$(handle "handoff-open ECFX-1" | head -1)" "a run-no line is cleared, never run"
answer '{"action": "wrong", "message": "✗ → x", "done": false}'
assert_eq "clear" "$(handle "nope" | head -1)" "a wrong line is cleared"
answer '{"action": "run", "message": "✓\nDrills: 5 right of 5", "done": true}'
assert_eq "accept-exit" "$(handle "friction-cards count" | head -1)" "the last right line runs, then the window ends"
answer '{"action": "show", "message": "Time is up.", "done": true}'
assert_eq "clear-exit" "$(handle "nope" | head -1)" "time up on a wrong line ends the window"
printf '#!/bin/sh\nexit 1\n' >"$STUB"
assert_eq "clear" "$(handle "rm -rf x" | head -1)" "drills step failing: the line is not run"
say() { DRILLS_CMD="$STUB" zsh -f -c 'source "$1"; _drill_say "$2" "$3"; print -- "-- command output --"; _drill_precmd' _ "$HOOK" "$1" "$2"; }
assert_eq "✓|-- command output --|Goal: Next one." "$(say accept $'✓\nGoal: Next one.' | paste -sd '|' -)" "after a command that runs, the next goal prints below its output"
assert_eq "✗ → x   (type it)|Goal: Same.|-- command output --" "$(say clear $'✗ → x   (type it)\nGoal: Same.' | paste -sd '|' -)" "a cleared line prints its whole message at once"

echo "drill.zsh in a real interactive zsh (keys)"
if command -v tmux >/dev/null 2>&1; then
  ZD="$SANDBOX/zd"; mkdir -p "$ZD"
  printf '#!/bin/sh\ncase "$3" in *OK*) echo "{\\"action\\": \\"run\\", \\"message\\": \\"ok\\", \\"done\\": false}" ;; *) echo "{\\"action\\": \\"wrong\\", \\"message\\": \\"no\\", \\"done\\": false}" ;; esac\n' >"$STUB"; chmod +x "$STUB"
  printf 'bindkey -e\nexport DRILLS_CMD=%q\nsource %q\nPS1="> "\n' "$STUB" "$HOOK" >"$ZD/.zshrc"
  S="drz$$"
  tmux new-session -d -s "$S" -x 120 -y 30 "ZDOTDIR=$ZD zsh -i"
  waitfor() { for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e "$1" ] && return 0; sleep 0.2; done; return 1; }
  waitfor "$SANDBOX/never" || true
  tmux send-keys -t "$S" "touch $SANDBOX/k-enter" Enter
  tmux send-keys -t "$S" "touch $SANDBOX/k-ctrl-o" C-o
  tmux send-keys -t "$S" "touch $SANDBOX/k-esc-a" Escape a
  tmux send-keys -t "$S" "touch $SANDBOX/k-ctrl-j" C-j
  tmux send-keys -t "$S" "touch $SANDBOX/k-OK" Enter
  waitfor "$SANDBOX/k-OK"; RAN=$?
  tmux kill-session -t "$S" 2>/dev/null
  assert_eq "0" "$RAN" "a right line still runs"
  for k in enter ctrl-o esc-a ctrl-j; do
    assert_eq "no" "$([ -e "$SANDBOX/k-$k" ] && echo yes || echo no)" "a wrong line sent with $k never runs"
  done
else
  echo "  skip - no tmux"
fi

echo "drills window"
export CARDS_DIR="$SANDBOX/cards" DRILLS_STATE="$SANDBOX/state" DRILLS_WINDOW_WAIT=0
mkdir -p "$CARDS_DIR"
OUT="$("$TEST_DIR/drills" window --date 2026-10-27)"; RC=$?
assert_eq "0|no drills due" "$RC|$OUT" "no drills: says so and exits"
"$TEST_DIR/drills" add --goal "Count the friction cards." --cmd friction-cards --accept "friction-cards count" --run yes --date 2026-10-01 >/dev/null
printf '#!/bin/sh\necho "args: $*"\ncat "$ZDOTDIR/.zshrc"\n' >"$SANDBOX/fakezsh"; chmod +x "$SANDBOX/fakezsh"
OUT="$(DRILLS_ZSH="$SANDBOX/fakezsh" "$TEST_DIR/drills" window --date 2026-10-27)"
assert_has "args: -i" "$OUT" "it runs an interactive zsh"
assert_has 'source "$HOME/.zshrc"' "$OUT" "that reads the user's own .zshrc"
assert_has "zsh/drill.zsh" "$OUT" "then the drill hook"
assert_has "POWERLEVEL9K_INSTANT_PROMPT=quiet" "$OUT" "p10k stays quiet about the banner in this window only"
assert_has "Goal: Count the friction cards." "$OUT" "and shows the first goal"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
