#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
STUBS="$ROOT/bin"
mkdir -p "$STUBS" "$ROOT/etc/keyd"
LOG="$ROOT/systemctl.log"
KEYD_LOG="$ROOT/keyd.log"
DEVICE_ID='1234:ABCD:89ABCDEF'
export KEYBOARD_SETUP_ROOT="$ROOT"
export KEYD_LOG

cat > "$STUBS/keyd" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$KEYD_LOG"
[ "${KEYD_CHECK_FAIL:-0}" != 1 ] || [ "${1:-}" != check ]
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

preview="$("$SCRIPT" apply --device-id "$DEVICE_ID" --dry-run)"
grep -q "^$DEVICE_ID$" <<<"$preview"
grep -q '^capslock = grave$' <<<"$preview"
[ ! -e "$TARGET" ]

if "$SCRIPT" apply --device-id '*' --dry-run >/dev/null 2>&1; then
    echo 'wildcard device ID unexpectedly accepted' >&2
    exit 1
fi
if "$SCRIPT" apply --device-id 1234:ABCD --dry-run >/dev/null 2>&1; then
    echo 'short vendor/product prefix unexpectedly accepted' >&2
    exit 1
fi
if "$SCRIPT" apply --dry-run >/dev/null 2>&1; then
    echo 'missing device ID unexpectedly accepted' >&2
    exit 1
fi

printf 'user-owned config\n' > "$TARGET"
if "$SCRIPT" apply --device-id "$DEVICE_ID" >/dev/null 2>&1; then
    echo 'unmanaged keyd config unexpectedly replaced' >&2
    exit 1
fi
grep -q 'user-owned config' "$TARGET"
rm "$TARGET"

"$SCRIPT" apply --device-id "$DEVICE_ID" >/dev/null
[ -f "$TARGET" ]
grep -q "^$DEVICE_ID$" "$TARGET"
grep -q '^capslock = grave$' "$TARGET"
[ "$(stat -c %a "$TARGET")" = 644 ]
[ "$(grep -c '^enable --now keyd.service$' "$LOG")" = 1 ]
[ "$(grep -c '^daemon-reload$' "$LOG")" = 1 ]

before="$(sha256sum "$TARGET")"
"$SCRIPT" apply --device-id "$DEVICE_ID" >/dev/null
[ "$(sha256sum "$TARGET")" = "$before" ]
[ "$(grep -c '^enable --now keyd.service$' "$LOG")" = 2 ]
[ "$(grep -c '^daemon-reload$' "$LOG")" = 2 ]
[ "$(grep -c '^check$' "$KEYD_LOG")" = 2 ]

rm "$TARGET"
if KEYD_CHECK_FAIL=1 "$SCRIPT" apply --device-id "$DEVICE_ID" >/dev/null 2>&1; then
    echo 'invalid keyd configuration was activated' >&2
    exit 1
fi
[ -f "$TARGET" ]
[ "$(grep -c '^enable --now keyd.service$' "$LOG")" = 2 ]
rm "$TARGET"

printf '[ids]\n*\n[main]\ncapslock = control\n' > "$ROOT/etc/keyd/unrelated.conf"
"$SCRIPT" remove >/dev/null
[ ! -e "$TARGET" ]
[ -f "$ROOT/etc/keyd/unrelated.conf" ]
! grep -q 'disable keyd.service' "$LOG"

grep -q '^restart keyd.service$' "$LOG"

printf 'keyboard-linux-setup tests passed\n'
