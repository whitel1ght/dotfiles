#!/bin/bash
#
# Put backtick back under the left pinky.
#
# This machine's keyboard is ANSI, where backtick/tilde sits at the top-left
# under Esc. The previous one was ISO, where that key sits next to left Shift —
# under the pinky, one finger, no reach. tmux's prefix is backtick
# (tmux/.tmux.conf), so the whole prefix layer moved to a key that is now both
# a stretch and one slip away from Esc, which nvim uses constantly.
#
# Rather than rebind the prefix — which would mean relearning `+j, `+a, `+o,
# `+c and every fuzzmux key — this remaps Caps Lock to send backtick. The key
# lands back under the pinky and tmux.conf is untouched.
#
# Caps Lock is the only free key in that zone: Tab, Esc, 1, q, a and z are all
# bound somewhere in this repo, and Caps Lock does nothing here — it is not
# switching input sources and carries no modifier remap.
#
# The remap is a HID-layer UserKeyMapping, applied by hidutil. That is a native
# macOS mechanism, so it needs no Karabiner and no kernel extension. It does
# not survive a reboot, which is what the LaunchAgent is for.
#
# The real backtick key keeps working — both keys send the same code, so either
# one is the prefix. Double-tapping still types a literal backtick, via the
# `bind-key ` send-prefix` line already in tmux.conf.

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# USB HID usage codes, page 0x07 (Keyboard/Keypad).
#   0x39 Caps Lock                0x700000039 = 30064771129 decimal
#   0x35 Grave Accent and Tilde   0x700000035 = 30064771125 decimal
# hidutil takes hex on --set but prints decimal on --get, so status matches on
# the decimal forms.
SRC_HEX="0x700000039"
DST_HEX="0x700000035"
SRC_DEC="30064771129"
DST_DEC="30064771125"

MAPPING="{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":$SRC_HEX,\"HIDKeyboardModifierMappingDst\":$DST_HEX}]}"
CLEARED='{"UserKeyMapping":[]}'

LABEL="local.keyremap"
PLIST_SRC="$DOTFILES_DIR/keyboard/local.keyremap.plist"

# Seams for the test suite; all default to the real thing.
HIDUTIL="${HIDUTIL:-/usr/bin/hidutil}"
LAUNCHCTL="${LAUNCHCTL:-launchctl}"
OS_NAME="${OS_NAME:-$(uname -s)}"
AGENT_DIR="${AGENT_DIR:-$HOME/Library/LaunchAgents}"

PLIST_DST="$AGENT_DIR/$LABEL.plist"
DOMAIN="gui/$(id -u)"

usage() {
    cat <<EOF
Usage: $(basename "$0") [apply|remove|status]

  apply    Remap Caps Lock to backtick, now and at every login (default)
  remove   Clear the remap and uninstall the LaunchAgent
  status   Report whether the remap and the LaunchAgent are in place

The remap lives in the HID layer and is cleared by every reboot, so the
LaunchAgent is what makes it stick. Run 'status' after a macOS upgrade.
EOF
}

is_mapped() {
    local current
    current="$("$HIDUTIL" property --get "UserKeyMapping" 2>/dev/null || true)"
    case "$current" in
        *"$SRC_DEC"*)
            case "$current" in
                *"$DST_DEC"*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

agent_installed() {
    [ -f "$PLIST_DST" ]
}

cmd_apply() {
    if [ ! -f "$PLIST_SRC" ]; then
        log_error "Missing $PLIST_SRC"
        return 1
    fi

    # Apply to the running session first, so the key works immediately rather
    # than only after the next login.
    "$HIDUTIL" property --set "$MAPPING" >/dev/null
    log_info "Caps Lock now sends backtick"

    # Copied rather than symlinked, and re-copied on every run: launchd reads
    # this file at login, so editing the repo copy should take effect on the
    # next apply without anyone remembering a second step.
    mkdir -p "$AGENT_DIR"
    cp "$PLIST_SRC" "$PLIST_DST"
    chmod 644 "$PLIST_DST"

    # bootout first so a re-run reloads an edited plist instead of silently
    # keeping the version launchd already has. It fails when nothing is
    # loaded, which is the normal first-run case, hence the guard.
    "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    "$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST_DST"
    log_info "Installed LaunchAgent $LABEL — the remap now survives reboots"

    log_warn 'tmux prefix is unchanged: Caps Lock is now the ` key it already expects.'
}

cmd_remove() {
    "$HIDUTIL" property --set "$CLEARED" >/dev/null
    log_info "Cleared the key remap — Caps Lock is Caps Lock again"

    if agent_installed; then
        "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" 2>/dev/null || true
        rm -f "$PLIST_DST"
        log_info "Removed LaunchAgent $LABEL"
    else
        log_info "No LaunchAgent installed"
    fi
}

cmd_status() {
    if is_mapped; then
        log_info "Remap: active (Caps Lock -> backtick)"
    else
        log_warn "Remap: not active"
    fi

    if agent_installed; then
        log_info "LaunchAgent: installed at $PLIST_DST"
    else
        log_warn "LaunchAgent: not installed — the remap will not survive a reboot"
    fi
}

if [ "$OS_NAME" != "Darwin" ]; then
    log_warn "Not macOS ($OS_NAME) — nothing to do"
    exit 0
fi

case "${1:-apply}" in
    apply)  cmd_apply ;;
    remove) cmd_remove ;;
    status) cmd_status ;;
    -h|--help|help) usage ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 2
        ;;
esac
