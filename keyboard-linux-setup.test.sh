#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
STUBS="$ROOT/bin"
mkdir -p "$STUBS" "$ROOT/etc/keyd"
LOG="$ROOT/systemctl.log"
export KEYBOARD_SETUP_ROOT="$ROOT"

cat > "$STUBS/keyd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$STUBS/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
[ "${1:-}" != is-active ] || [ "${KEYD_ACTIVE:-1}" = 1 ]
EOF
chmod +x "$STUBS"/*
export SYSTEMCTL_LOG="$LOG"
export PATH="$STUBS:/usr/bin:/bin"
SCRIPT="$REPO/keyboard-linux-setup.sh"
TARGET="$ROOT/etc/keyd/dotfiles-capslock.conf"

preview="$("$SCRIPT" apply --device-id 1234:ABCD --dry-run)"
grep -q '^1234:ABCD$' <<<"$preview"
grep -q '^capslock = grave$' <<<"$preview"
[ ! -e "$TARGET" ]

if "$SCRIPT" apply --device-id '*' --dry-run >/dev/null 2>&1; then
    echo 'wildcard device ID unexpectedly accepted' >&2
    exit 1
fi
if "$SCRIPT" apply --dry-run >/dev/null 2>&1; then
    echo 'missing device ID unexpectedly accepted' >&2
    exit 1
fi

printf 'user-owned config\\n' > "$TARGET"
if "$SCRIPT" apply --device-id 1234:ABCD >/dev/null 2>&1; then
    echo 'unmanaged keyd config unexpectedly replaced' >&2
    exit 1
fi
grep -q 'user-owned config' "$TARGET"
rm "$TARGET"

"$SCRIPT" apply --device-id 1234:ABCD >/dev/null
[ -f "$TARGET" ]
grep -q '^1234:ABCD$' "$TARGET"
grep -q '^capslock = grave$' "$TARGET"
[ "$(stat -c %a "$TARGET")" = 644 ]
[ "$(grep -c '^enable --now keyd.service$' "$LOG")" = 1 ]

before="$(sha256sum "$TARGET")"
"$SCRIPT" apply --device-id 1234:ABCD >/dev/null
[ "$(sha256sum "$TARGET")" = "$before" ]
[ "$(grep -c '^enable --now keyd.service$' "$LOG")" = 2 ]

printf '[ids]\n*\n[main]\ncapslock = control\n' > "$ROOT/etc/keyd/unrelated.conf"
"$SCRIPT" remove >/dev/null
[ ! -e "$TARGET" ]
[ -f "$ROOT/etc/keyd/unrelated.conf" ]
! grep -q 'disable keyd.service' "$LOG"

grep -q '^restart keyd.service$' "$LOG"

printf 'keyboard-linux-setup tests passed\n'
