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

# Hidden subcommand: render a live preview of a window's pane content. Called by
# fzf's --preview for the highlighted row (the argument is a "session:window",
# possibly with a trailing " (here)" tag to strip). Must run before the rest of
# the setup so it stays cheap and side-effect-free.
if [ "${1:-}" = "--preview" ]; then
    loc="${2:-}"
    loc="${loc% (here)}"
    [ -n "$loc" ] || exit 0
    tmux capture-pane -p -t "$loc" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n 40
    exit 0
fi

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

# Absolute path to this script, so fzf's --preview can re-invoke it.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# Signals that a Claude Code turn is in flight, taken from its live status line:
#   ✽ Inferring… (37s · ↓ 2.0k tokens)
#   ✻ Bloviating… (2m 37s · ↓ 1.7k tokens)          <- minutes appear past 60s
#   ✻ Cerebrating… (12s · ↑ 3.2k tokens · esc to interrupt)
# The dependable, output-safe markers are the elapsed-time timer that only the
# running status line shows — "(<N>s · … tokens)" or "(<N>m <N>s · … tokens)" —
# and the interrupt hint. Bare words ("Working") are avoided; they collide with
# ordinary output such as "working tree clean". The leading "([0-9]+[ms]" matches
# both the seconds-only and minutes-and-seconds forms of the timer.
#
# NOTE: unlike pane identification (which is version-independent), this DOES read
# Claude's status-line wording, so a future UI change could require updating it.
# It degrades gracefully: if the wording changes, identification and `--all` keep
# working — only the busy *filter* would need a new pattern here.
BUSY_RE='esc to interrupt|\([0-9]+[ms][^)]*·[^)]*tokens'

# Emit "session:window" for every pane that is a Claude Code session.
#
# Identification is version-independent: a pane is Claude if its process subtree
# contains a process named "claude" (the binary). We deliberately do NOT match
# the version string Claude reports as its command name (e.g. "2.1.218") — that
# changes on every update — nor the pane title glyph, which is an animated
# spinner while a turn runs and so is not a stable marker.
#
# The check uses a SINGLE `ps` snapshot walked in awk, not a per-pane `pgrep -P`.
# That matters for correctness as much as speed: Claude spawns short-lived
# children, so per-pane pgrep calls race against a moving process tree and
# intermittently miss the "claude" child. One consistent snapshot does not.
#
# awk walks, for each pane_pid, its descendants and reports whether any is
# "claude"; the shell then maps the matching pids back to "session:window".
claude_panes() {
    # pane_pid -> "session:window" map, tab-separated.
    local map
    map="$(tmux list-panes -a -F '#{pane_pid}	#{session_name}:#{window_index}')"

    # One ps snapshot; awk marks each root pid whose subtree contains "claude".
    printf '%s\n' "$map" | awk '
        NR==FNR { loc[$1]=$2; next }           # first pass: the tmux map
        { comm[$1]=$3; ppid[$1]=$2 }           # second pass: ps snapshot
        END {
            for (root in loc) {
                # BFS over descendants of this pane_pid
                delete seen; qn=0; q[qn++]=root; hit=0
                for (i=0; i<qn; i++) {
                    cur=q[i]
                    for (pid in ppid) {
                        if (ppid[pid]==cur && !(pid in seen)) {
                            seen[pid]=1; q[qn++]=pid
                            # comm may be a bare name ("claude") or a full path
                            # ("/Users/.../claude"); match the basename either way.
                            c=comm[pid]; sub(/^.*\//, "", c)
                            if (c=="claude") hit=1
                        }
                    }
                }
                if (hit) print loc[root]
            }
        }
    ' - <(ps -ax -o pid=,ppid=,comm=) \
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

# Build each picker row as TAB-separated columns for fzf:
#   1: raw "session:window" (hidden; used for selection + as the preview argument)
#   2: status icon  — ● busy, ○ idle
#   3: location, padded to align (+ " (here)" for the current window)
#   4: window name (Claude names the window after the task, so this is the useful
#      label; the live pane content is shown in the preview pane instead of inline)
# The window we were invoked from (passed as $1) is tagged "(here)"; selecting it
# is a no-op that just closes the popup.
annotate() {
    local self="$1" loc name snap icon here_tag label
    while IFS= read -r loc; do
        [ -n "$loc" ] || continue
        name="$(tmux display-message -p -t "$loc" '#{window_name}' 2>/dev/null || echo '?')"
        snap="$(tmux capture-pane -p -t "$loc" 2>/dev/null || true)"
        if printf '%s\n' "$snap" | grep -qiE "$BUSY_RE"; then
            icon='●'
        else
            icon='○'
        fi
        here_tag=""
        [ "$loc" = "$self" ] && here_tag=' (here)'
        label="$loc$here_tag"
        printf '%s\t%s\t%-18s\t%s\n' "$loc$here_tag" "$icon" "$label" "$name"
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
#
# Column layout from annotate (tab-separated):
#   f1 = raw "session:window" (hidden; used for selection + preview arg)
#   f2 = icon  f3 = location  f4 = window name
# --with-nth=2.. shows only the display columns; f1 is what we read back.
title="Busy Claude sessions"
[ "$SCOPE" = "all" ] && title="Claude sessions"

choice="$(printf '%s\n' "$windows" | annotate "$here" \
    | fzf --delimiter='\t' \
        --with-nth='2..' \
        --nth='3,4' \
        --no-sort --cycle --no-multi \
        --layout=reverse \
        --info=inline \
        --border=rounded --border-label=" $title " --border-label-pos=3 \
        --padding=0,1 --margin=1,2 \
        --prompt='search: ' \
        --pointer='▎' --marker='●' \
        --header='enter: jump    esc: cancel    ● busy  ○ idle' --header-first \
        --preview="$SELF --preview {1}" \
        --preview-window='right,54%,border-left,wrap' \
        --preview-label=' live view ' \
        --color='fg:-1,bg:-1,hl:6,fg+:15,bg+:-1,hl+:14,border:8,label:7,prompt:6,pointer:5,header:8,info:8,preview-border:8' \
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
