#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOME_DIR="$(mktemp -d)"
trap 'rm -rf "$HOME_DIR"' EXIT
OUT="$HOME_DIR/stdout"
ERR="$HOME_DIR/stderr"

env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin DOTFILES_DIR="$REPO" \
    zsh -i -c '
      source "$DOTFILES_DIR/zsh/.zprofile"
      source "$DOTFILES_DIR/zsh/.zshenv"
      source "$DOTFILES_DIR/zsh/.zshrc"
      whence -w today yesterday NVM_DIR >/dev/null
      print -r -- "$PATH"
    ' > "$OUT" 2> "$ERR"

[ ! -s "$ERR" ] || { printf 'unexpected Zsh startup output:\n' >&2; cat "$ERR" >&2; exit 1; }
! grep -qE '/Users/|/opt/homebrew|pbcopy|brew shellenv' "$OUT"
grep -q "$HOME_DIR/.local/bin" "$OUT"
printf 'zsh-config tests passed\n'
