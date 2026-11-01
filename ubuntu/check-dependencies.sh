#!/usr/bin/env bash
set -euo pipefail

MIN_NVIM=0.11.0
MIN_TMUX=3.5
MIN_FZF=0.48.0
FAIL=0

ok() { printf '  ok      %s\n' "$*"; }
warn() { printf '  MISSING %s\n' "$*"; FAIL=1; }
note() { printf '  note    %s\n' "$*"; }

version_ge() {
    local actual="$1" minimum="$2"
    [ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n1)" = "$minimum" ]
}

check_command() {
    local cmd="$1" purpose="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$purpose ($(command -v "$cmd"))"
        return 0
    fi
    warn "$purpose (missing command: $cmd)"
    return 1
}

check_version() {
    local cmd="$1" minimum="$2" version="$3"
    if [ -z "$version" ]; then
        warn "$cmd >= $minimum (could not determine version)"
    elif version_ge "$version" "$minimum"; then
        ok "$cmd $version (minimum $minimum)"
    else
        warn "$cmd $version is too old; need >= $minimum (use a verified upstream release, not an unpinned random binary)"
    fi
}

printf 'Ubuntu dotfiles dependency check\n'
check_command zsh 'Zsh' || true
check_command git 'Git' || true
check_command jq 'jq' || true
check_command sqlite3 'SQLite (OpenCode auth helper)' || true
check_command xdg-open 'xdg-open (desktop URL/file opener)' || true

if command -v nvim >/dev/null 2>&1; then
    version="$(nvim --version 2>/dev/null | head -n1 | sed -n 's/^NVIM v//p')"
    check_version nvim "$MIN_NVIM" "$version"
else
    warn 'Neovim >= 0.11.0 (missing command: nvim)'
fi

if command -v tmux >/dev/null 2>&1; then
    version="$(tmux -V 2>/dev/null | awk '{print $2}')"
    check_version tmux "$MIN_TMUX" "$version"
else
    warn 'tmux >= 3.5 (missing command: tmux)'
fi

if command -v fzf >/dev/null 2>&1; then
    version="$(fzf --version 2>/dev/null | awk 'NR==1 {print $1}')"
    check_version fzf "$MIN_FZF" "$version"
else
    warn 'fzf >= 0.48.0 (missing command: fzf)'
fi

if command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; then
    ok 'fd (fd or fdfind)'
else
    warn 'fd-find (install the fd -> fdfind compatibility link with install.sh)'
fi
if command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1; then
    ok 'bat (bat or batcat)'
else
    warn 'bat (install the bat -> batcat compatibility link with install.sh)'
fi

if command -v keyd >/dev/null 2>&1; then
    ok 'keyd (Linux Caps Lock -> tmux prefix mapping)'
else
    warn 'keyd (needed for persistent Caps Lock -> grave mapping; verify Ubuntu package/source and device ID before activation)'
fi

if command -v node >/dev/null 2>&1; then
    version="$(node --version 2>/dev/null | sed 's/^v//')"
    check_version node 24.0.0 "$version"
else
    note 'Node.js 24 is needed for Pi extension tests and selected Node-based tooling; install/use NVM if required.'
fi

if [ "$FAIL" -ne 0 ]; then
    printf '\nResolve the missing/old required dependencies before enabling full parity.\n' >&2
    exit 1
fi
printf '\nRequired command/version checks passed. Optional applications are not checked here.\n'
