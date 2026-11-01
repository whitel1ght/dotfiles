#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
STUBS="$ROOT/bin"
mkdir -p "$STUBS"

make_tool() {
    local name="$1" body="$2"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$STUBS/$name"
    chmod +x "$STUBS/$name"
}
make_tool nvim 'printf "NVIM v%s\n" "${NVIM_VERSION:-0.12.0}"'
make_tool tmux 'if [ "${1:-}" = -V ]; then printf "tmux %s\n" "${TMUX_VERSION:-3.5}"; fi'
make_tool fzf 'printf "%s (debian)\n" "${FZF_VERSION:-0.50.0}"'
for tool in zsh git jq sqlite3 xdg-open fdfind batcat keyd; do
    make_tool "$tool" 'exit 0'
done
make_tool node 'printf "v%s\n" "${NODE_VERSION:-24.0.0}"'

out="$(PATH="$STUBS:/usr/bin:/bin" bash "$REPO/ubuntu/check-dependencies.sh")"
grep -q 'nvim 0.12.0 (minimum 0.11.0)' <<<"$out"
grep -q 'tmux 3.5 (minimum 3.5)' <<<"$out"
grep -q 'fzf 0.50.0 (minimum 0.48.0)' <<<"$out"
grep -q 'keyd (.*)' <<<"$out"

if out="$(PATH="$STUBS:/usr/bin:/bin" NVIM_VERSION=0.10.4 TMUX_VERSION=3.4 FZF_VERSION=0.44.1 \
    bash "$REPO/ubuntu/check-dependencies.sh" 2>&1)"; then
    echo 'outdated tools unexpectedly passed dependency check' >&2
    exit 1
fi
grep -q 'nvim 0.10.4 is too old' <<<"$out"
grep -q 'tmux 3.4 is too old' <<<"$out"
grep -q 'fzf 0.44.1 is too old' <<<"$out"

printf 'dependency-check tests passed\n'
