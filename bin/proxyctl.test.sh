#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
HOME_DIR="$ROOT/home"
STUBS="$ROOT/bin"
mkdir -p "$HOME_DIR/.local/bin" "$STUBS" "$ROOT/cwd"
ln -s "$REPO/bin/proxyctl" "$HOME_DIR/.local/bin/proxyctl"
cat > "$STUBS/qrencode" <<'EOF'
#!/usr/bin/env bash
printf 'QR:%s\n' "$*"
EOF
chmod +x "$STUBS/qrencode"

out="$(cd "$ROOT/cwd" && env -u DOTFILES HOME="$HOME_DIR" PATH="$STUBS:$PATH" \
    "$HOME_DIR/.local/bin/proxyctl" happ --terminal)"
grep -q '^QR:-t ansiutf8 -m 2 happ://routing/onadd/' <<<"$out"
grep -q 'Scan with the iPhone camera' <<<"$out"

printf 'proxyctl checkout-path tests passed\n'
