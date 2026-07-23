#!/usr/bin/env bash
#
# claude-busy.sh — find tmux windows running Claude Code that are actively working,
# and (by default) let you fuzzy-pick one to jump to.
#
# "Working" is inferred from each pane's visible content: while Claude is running a
# turn it renders a status line ("esc to interrupt", a spinner, token/elapsed
# counters). A pane parked at the prompt shows none of these, so it's treated as idle.
#
# Usage:
#   claude-busy.sh            # fzf picker of busy Claude windows; switches to the pick
#   claude-busy.sh --list     # just print busy windows (one "session:window" per line)
#   claude-busy.sh --all      # picker over ALL Claude windows, busy or not
#   claude-busy.sh --print    # picker, but print the choice instead of switching
#
# Intended to be driven from a tmux key binding (see .tmux.conf), but works standalone.
# The binding runs this inside `tmux popup`, passing the invoking client as
# CALLER_CLIENT so we switch the right client (switch-client from within a popup
# would otherwise target the popup's own client).

set -euo pipefail

MODE="pick"     # pick | list | print
SCOPE="busy"    # busy | all

for arg in "$@"; do
    case "$arg" in
        --list)  MODE="list" ;;
        --print) MODE="print" ;;
        --all)   SCOPE="all" ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

if [ -z "${TMUX:-}" ] && ! tmux info >/dev/null 2>&1; then
    echo "no tmux server running" >&2
    exit 1
fi

# Signals that a Claude Code turn is in flight, taken from its live status line:
#   ✽ Inferring… (37s · ↓ 2.0k tokens)
#   ✻ Bloviating… (2m 37s · ↓ 1.7k tokens)          <- minutes appear past 60s
#   ✻ Cerebrating… (12s · ↑ 3.2k tokens · esc to interrupt)
# The dependable, output-safe markers are the elapsed-time timer that only the
# running status line shows — "(<N>s · … tokens)" or "(<N>m <N>s · … tokens)" —
# and the interrupt hint. Bare words ("Working") are avoided; they collide with
# ordinary output such as "working tree clean". The leading "([0-9]+[ms]" matches
# both the seconds-only and minutes-and-seconds forms of the timer.
BUSY_RE='esc to interrupt|\([0-9]+[ms][^)]*·[^)]*tokens'

# Emit "session:window" for every pane that is a Claude Code session. Claude Code
# reports its version as the pane's process name (e.g. "2.1.218"), so the reliable
# selector is a version-string command — NOT "claude"/"node", which both miss the
# real sessions and false-match unrelated node processes. "claude" is kept as a
# fallback in case a build reports the binary name instead.
claude_panes() {
    tmux list-panes -a \
        -F '#{session_name}:#{window_index}	#{pane_current_command}' \
        | grep -iE '	([0-9]+\.[0-9]+\.[0-9]+|claude)$' \
        | cut -f1 \
        | sort -u
}

# Print windows to consider, one "session:window" per line, honoring SCOPE.
select_windows() {
    local loc snap
    while IFS= read -r loc; do
        [ -n "$loc" ] || continue
        if [ "$SCOPE" = "all" ]; then
            echo "$loc"
            continue
        fi
        snap="$(tmux capture-pane -p -t "$loc" 2>/dev/null || true)"
        if printf '%s\n' "$snap" | grep -qiE "$BUSY_RE"; then
            echo "$loc"
        fi
    done < <(claude_panes)
}

# Build a human-friendly picker line: "session:window  ⟨window name⟩  last output line".
# The window we were invoked from (passed as $1) is tagged so it's obvious in the
# list; selecting it is a no-op that just closes the popup.
annotate() {
    local self="$1" loc name tail marker
    while IFS= read -r loc; do
        [ -n "$loc" ] || continue
        name="$(tmux display-message -p -t "$loc" '#{window_name}' 2>/dev/null || echo '?')"
        # Last non-empty visible line gives a hint of what it's doing.
        tail="$(tmux capture-pane -p -t "$loc" 2>/dev/null \
                | grep -v '^[[:space:]]*$' | tail -n1 | cut -c1-60)"
        marker=""
        [ "$loc" = "$self" ] && marker=" (here)"
        printf '%s\t%s\t%s\n' "$loc$marker" "$name" "$tail"
    done
}

windows="$(select_windows)"

# The window the user is currently viewing. It's kept in the picker (tagged
# "(here)") so the list is complete; selecting it just closes the popup.
here="$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null || true)"

if [ "$MODE" = "list" ]; then
    printf '%s\n' "$windows"
    exit 0
fi

# Everything below is the interactive picker. Pauses on any dead-end message so a
# tmux popup doesn't blink shut before it can be read.
notice() { echo "$1" >&2; [ -t 1 ] && sleep 1.4; }

if [ -z "$windows" ]; then
    label="busy Claude"
    [ "$SCOPE" = "all" ] && label="Claude"
    notice "No $label windows right now."
    exit 0
fi

# Show every busy window, including the current one. Plain fzf (not fzf-tmux):
# the caller runs us inside a `tmux popup`, which already provides the overlay.
# annotate tags the current window with " (here)"; strip that back off the pick.
choice="$(printf '%s\n' "$windows" | annotate "$here" \
    | fzf --with-nth=1,2,3 --delimiter='\t' \
        --prompt='claude> ' \
        --header='Enter: switch  Esc: cancel' \
        --no-sort --cycle \
    | cut -f1 | sed 's/ (here)$//')"

[ -n "$choice" ] || exit 0

if [ "$MODE" = "print" ]; then
    printf '%s\n' "$choice"
    exit 0
fi

# Picking the current window is a no-op: just close the popup, no switch needed.
if [ "$choice" = "$here" ]; then
    exit 0
fi

# Switch the caller's client to the chosen window. When run inside a `tmux popup`,
# `display-message -p '#{client_name}'` still resolves to the client that opened
# the popup, so targeting it explicitly switches the right terminal. (tmux does
# NOT expand #{client_name} in a binding's `display-popup -e`, so it must be read
# here, at runtime, rather than passed in as an environment variable.)
client="$(tmux display-message -p '#{client_name}' 2>/dev/null)"
if [ -n "$client" ]; then
    tmux switch-client -c "$client" -t "$choice"
else
    tmux switch-client -t "$choice"
fi
