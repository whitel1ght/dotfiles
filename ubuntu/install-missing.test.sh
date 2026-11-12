#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/ubuntu/install-missing.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf -- "$ROOT"' EXIT
STUBS="$ROOT/stubs"
LOG="$ROOT/commands.log"
DEVICE_ID='0001:0001:09b4e68d'
EXTERNAL_ID='320f:5086:fc5f7b56'
mkdir -p "$STUBS" "$ROOT/home"

for command_name in sudo apt-get curl pi; do
    cat > "$STUBS/$command_name" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$INSTALL_MISSING_LOG"
exit 99
EOF
    chmod +x "$STUBS/$command_name"
done

export HOME="$ROOT/home"
export PI_CODING_AGENT_DIR="$HOME/.pi/agent"
export INSTALL_MISSING_LOG="$LOG"
export PATH="$STUBS:/usr/bin:/bin"

preview="$("$SCRIPT")"
grep -q 'DRY RUN: no packages, downloads, Pi settings, services, or keyboard mappings changed' <<<"$preview"
grep -q 'tmux:         3.5a' <<<"$preview"
grep -q 'fzf:          0.61.3' <<<"$preview"
grep -q 'keyd:         v2.6.0' <<<"$preview"
grep -q 'repo pi-sub extension, linked by bin/plink' <<<"$preview"
[ ! -e "$LOG" ]
[ ! -e "$HOME/.local" ]

preview="$("$SCRIPT" --dry-run --configure-keyboard --device-id "$DEVICE_ID" --device-id "$EXTERNAL_ID")"
grep -q "enable Caps Lock -> grave for requested full IDs $DEVICE_ID $EXTERNAL_ID after verification and confirmation" <<<"$preview"
if "$SCRIPT" --configure-keyboard >/dev/null 2>&1; then
    echo 'keyboard configuration without a device ID was accepted' >&2
    exit 1
fi
if "$SCRIPT" --dry-run --device-id "$DEVICE_ID" >/dev/null 2>&1; then
    echo 'device ID without --configure-keyboard was accepted' >&2
    exit 1
fi
if "$SCRIPT" --dry-run --configure-keyboard --device-id 1234:abcd >/dev/null 2>&1; then
    echo 'short vendor/product prefix unexpectedly accepted' >&2
    exit 1
fi
if "$SCRIPT" --dry-run --configure-keyboard --device-id '*' >/dev/null 2>&1; then
    echo 'wildcard keyboard ID was accepted' >&2
    exit 1
fi
if "$SCRIPT" --dry-run --apply >/dev/null 2>&1; then
    echo 'conflicting dry-run/apply modes were accepted' >&2
    exit 1
fi
[ ! -e "$LOG" ]

printf 'install-missing tests passed\n'
