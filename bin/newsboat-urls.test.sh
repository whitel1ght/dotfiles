#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
HOME_DIR="$ROOT/home"
mkdir -p "$HOME_DIR/.local/bin" "$ROOT/cwd"
ln -s "$REPO/bin/newsboat-urls" "$HOME_DIR/.local/bin/newsboat-urls"

(
    cd "$ROOT/cwd"
    env -u DOTFILES HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
        "$HOME_DIR/.local/bin/newsboat-urls" > "$ROOT/output"
)
OUT="$HOME_DIR/.config/newsboat/urls"
[ -s "$OUT" ]
grep -q 'https://lobste.rs/rss' "$OUT"
grep -q 'https://www.reddit.com/r/' "$OUT"
grep -q '~reddit' "$OUT"

printf 'newsboat-urls tests passed\n'
