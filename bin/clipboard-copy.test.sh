#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/clipboard-copy"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
STUBS="$ROOT/bin"
X11_STUBS="$ROOT/x11-bin"
mkdir -p "$STUBS" "$X11_STUBS"

cat > "$STUBS/wl-copy" <<'EOF'
#!/usr/bin/env bash
cat > "$CLIPBOARD_CAPTURE"
printf 'wl-copy %s\n' "$*" >> "$CLIPBOARD_LOG"
EOF
cat > "$STUBS/xclip" <<'EOF'
#!/usr/bin/env bash
cat > "$CLIPBOARD_CAPTURE"
printf 'xclip %s\n' "$*" >> "$CLIPBOARD_LOG"
EOF
cat > "$STUBS/xsel" <<'EOF'
#!/usr/bin/env bash
cat > "$CLIPBOARD_CAPTURE"
printf 'xsel %s\n' "$*" >> "$CLIPBOARD_LOG"
EOF
chmod +x "$STUBS"/*
ln -s "$STUBS/xclip" "$X11_STUBS/xclip"
for tool in env bash cat; do ln -s "$(command -v "$tool")" "$X11_STUBS/$tool"; done
export CLIPBOARD_CAPTURE="$ROOT/capture" CLIPBOARD_LOG="$ROOT/log"

printf 'wayland secret' | PATH="$STUBS:/usr/bin:/bin" WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 "$SCRIPT"
[ "$(<"$CLIPBOARD_CAPTURE")" = 'wayland secret' ]
grep -qx 'wl-copy ' "$CLIPBOARD_LOG"

: > "$CLIPBOARD_LOG"
printf 'x11 text' | PATH="$STUBS:/usr/bin:/bin" WAYLAND_DISPLAY= DISPLAY=:0 "$SCRIPT"
[ "$(<"$CLIPBOARD_CAPTURE")" = 'x11 text' ]
grep -qx 'xclip -selection clipboard -in' "$CLIPBOARD_LOG"

: > "$CLIPBOARD_LOG"
printf 'Xwayland fallback' | PATH="$X11_STUBS" WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 "$SCRIPT"
[ "$(<"$CLIPBOARD_CAPTURE")" = 'Xwayland fallback' ]
grep -qx 'xclip -selection clipboard -in' "$CLIPBOARD_LOG"

if printf 'private' | PATH=/usr/bin:/bin WAYLAND_DISPLAY= DISPLAY= "$SCRIPT" >"$ROOT/stdout" 2>"$ROOT/stderr"; then
    echo 'expected missing desktop clipboard to fail' >&2
    exit 1
fi
[ ! -s "$ROOT/stdout" ]
grep -q 'install wl-clipboard' "$ROOT/stderr"

printf 'clipboard-copy tests passed\n'
