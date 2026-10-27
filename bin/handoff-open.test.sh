#!/bin/bash
# Tests for bin/handoff-open. tmux is a PATH stub: its answers come from FAKE_* variables and
# its argv goes to a log, so no window opens and no real tmux server is asked.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/handoff-open"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
refute_contains() { case "$1" in *"$2"*) fail "$3" "[$2] found in [$1]" ;; *) pass "$3" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
BIN="$SANDBOX/bin"; WT="$SANDBOX/wt/ECFX-1"; LOG="$SANDBOX/tmux.log"
mkdir -p "$BIN" "$WT"
cat > "$BIN/tmux" <<'STUB'
#!/bin/bash
{ echo "--- tmux"; printf '%s\n' "$@"; } >> "$TMUX_LOG"
[ -z "${FAKE_NOSERVER:-}" ] || exit 1
case "$1" in
  list-sessions) echo "main: 4 windows" ;;
  display-message) [ -n "${FAKE_DISPLAY:-}" ] && echo "$FAKE_DISPLAY" || exit 1 ;;
  list-panes) printf '%b' "${FAKE_PANES:-}" ;;
  list-clients) printf '%b' "${FAKE_CLIENTS:-}" ;;
  list-windows) printf '%b' "${FAKE_WINDOWS:-}" ;;
esac
exit 0
STUB
chmod +x "$BIN/tmux"
[ "$(PATH="$BIN:$PATH" command -v tmux)" = "$BIN/tmux" ] || { echo "refusing to run: the tmux stub is not first on PATH"; exit 1; }

# the script's ancestors include this test shell, so a pane whose pid is $$ is "the caller's pane"
run() { : > "$LOG"; OUT="$(PATH="$BIN:$PATH" TMUX_LOG="$LOG" TMUX= TMUX_PANE="${PANE:-}" "$SCRIPT" "$@" 2>"$SANDBOX/stderr")"; RC=$?; }
log() { sed 's/^/|/' "$LOG" | tr '\n' ' '; }
reset() { unset FAKE_NOSERVER FAKE_DISPLAY FAKE_PANES FAKE_CLIENTS FAKE_WINDOWS PANE; }

echo "handoff-open — no \$TMUX, the caller's pane found by its process"
reset; export FAKE_PANES="99999 other\n$$ dev box\n" FAKE_CLIENTS="200 other\n" FAKE_WINDOWS="0 mrglass\n1 main\n"
run ECFX-1 "$WT"
assert_eq "0|opened dev box:ECFX-1" "$RC|$OUT" "opens in the session of the pane it runs under, not the busiest client"
assert_contains "$(log)" "|new-window |-t |=dev box: |-n |ECFX-1 |-c |$WT |claude -n ECFX-1 \"/daily:pickup ECFX-1\" " "a named window in the worktree running the pickup"

echo "handoff-open — \$TMUX_PANE wins"
reset; export FAKE_DISPLAY="work" FAKE_PANES="$$ dev\n"; PANE=%3
run ECFX-1 "$WT"
assert_eq "opened work:ECFX-1" "$OUT" "the session of \$TMUX_PANE"

echo "handoff-open — no pane of ours: the most recently active client"
reset; export FAKE_PANES="99999 x\n" FAKE_CLIENTS="100 old\n300 main\n200 other\n"
run ECFX-1 "$WT"
assert_eq "opened main:ECFX-1" "$OUT" "the client with the latest activity"

echo "handoff-open — an existing window is focused, never a second one"
reset; export FAKE_PANES="$$ main\n" FAKE_WINDOWS="0 mrglass\n8 ECFX-1:claude\n"
run ECFX-1 "$WT"
assert_eq "0|focused main:ECFX-1:claude" "$RC|$OUT" "tmux's automatic name KEY:<cmd> counts as the ticket's window"
assert_contains "$(log)" "|select-window |-t |=main:8 " "selected by index"
refute_contains "$(log)" "new-window" "no new window"
reset; export FAKE_PANES="$$ main\n" FAKE_WINDOWS="3 ECFX-10\n4 ECFX-1\n"
run ECFX-1 "$WT"
assert_contains "$(log)" "|select-window |-t |=main:4 " "an exact name, not a longer key that starts the same"

echo "handoff-open — pi"
reset; export FAKE_PANES="$$ main\n"
run ECFX-1 "$WT" pi
assert_contains "$(log)" "|pi -n ECFX-1 \"/pickup ECFX-1\" " "pi runs its own pickup"

echo "handoff-open — no tmux server"
reset; export FAKE_NOSERVER=1
run ECFX-1 "$WT"
assert_eq "0|run: cd $WT && claude -n ECFX-1 \"/daily:pickup ECFX-1\"" "$RC|$OUT" "prints the command for a new terminal"
reset; export FAKE_PANES="99999 x\n" FAKE_CLIENTS=""
run ECFX-1 "$WT"
assert_eq "0|run: cd $WT && claude -n ECFX-1 \"/daily:pickup ECFX-1\"" "$RC|$OUT" "no session to open in: the same"

echo "handoff-open — refusals"
reset; export FAKE_PANES="$$ main\n"
run 'ECFX-1; rm -rf x' "$WT"
assert_eq "1|" "$RC|$(log | rg -o 'new-window' || true)" "a key that is not a ticket key"
run ECFX-1 "$SANDBOX/missing"
assert_eq "1" "$RC" "a missing worktree"
run ECFX-1 "$WT" codex
assert_eq "1" "$RC" "an unknown harness"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
