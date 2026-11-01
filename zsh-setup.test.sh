#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
HOME_DIR="$ROOT/home"
STUBS="$ROOT/bin"
mkdir -p "$STUBS" "$HOME_DIR/.oh-my-zsh/custom/themes/powerlevel10k" \
    "$HOME_DIR/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
    "$HOME_DIR/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" \
    "$HOME_DIR/.oh-my-zsh/custom/plugins/fzf-tab"

cat > "$STUBS/zsh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$STUBS/kubectl" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = completion ] && [ "${2:-}" = zsh ] || exit 2
printf '# completion\nout=$(eval ${requestComp} 2>/dev/null)\n'
EOF
cat > "$STUBS/docker" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = completion ] && [ "${2:-}" = zsh ] || exit 2
printf '# completion\nout=$(eval ${requestComp} 2>/dev/null)\n'
EOF
chmod +x "$STUBS"/*

HOME="$HOME_DIR" PATH="$STUBS:/usr/bin:/bin" bash "$REPO/zsh-setup.sh" > "$ROOT/output"
for tool in kubectl docker; do
    completion="$HOME_DIR/.oh-my-zsh/cache/completions/_$tool"
    grep -q 'deadline 5.*requestComp' "$completion"
done
grep -q 'Zsh setup complete' "$ROOT/output"

printf 'zsh-setup tests passed\n'
