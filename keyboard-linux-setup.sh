#!/usr/bin/env bash
# Map the laptop's Caps Lock key to the physical grave key using keyd.
# This keeps tmux's existing backtick prefix; it does not map Caps Lock to Super.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SELF_DIR/keyboard/linux/keyd.conf.example"
ROOT="${KEYBOARD_SETUP_ROOT:-}"
CONFIG_DIR="${ROOT}/etc/keyd"
TARGET="$CONFIG_DIR/dotfiles-capslock.conf"
MARKER='# Managed by dotfiles keyboard-linux-setup.sh.'

usage() {
    cat <<'EOF'
Usage:
  keyboard-linux-setup.sh apply --device-id VENDOR:PRODUCT:UNIQUE_ID [--device-id ...] [--dry-run]
  keyboard-linux-setup.sh status
  keyboard-linux-setup.sh remove [--dry-run]

Repeat --device-id for each keyboard you want to remap. Copy each complete ID
from `sudo keyd monitor` (format VENDOR:PRODUCT:UNIQUE_ID). Wildcards and
shortened vendor/product prefixes are deliberately rejected.
The apply/remove operations require root and restart keyd when needed.
EOF
}

log() { printf '[keyboard] %s\n' "$*"; }
die() { printf '[keyboard] ERROR: %s\n' "$*" >&2; exit 1; }

is_test_root() { [ -n "$ROOT" ]; }
require_root() {
    if [ "$(id -u)" -ne 0 ] && ! is_test_root; then
        die "run this command with sudo"
    fi
}

service_restart() {
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet keyd.service; then
        systemctl restart keyd.service
    else
        log "keyd is not active; configuration was written but not activated"
    fi
}

backup_existing() {
    local target="$1" backup="$1.backup" n=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
        backup="$1.backup.$n"
        n=$((n + 1))
    done
    cp -a -- "$target" "$backup"
    log "Backed up existing managed configuration to $backup"
}

apply() {
    local id dry=0 line config
    local -a ids=() normalized_ids=()
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --device-id) [ "$#" -ge 2 ] || die '--device-id requires VENDOR:PRODUCT:UNIQUE_ID'; ids+=("$2"); shift 2 ;;
            --dry-run) dry=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) die "unknown apply option: $1" ;;
        esac
    done
    [ "${#ids[@]}" -gt 0 ] || die 'provide at least one full keyd device ID'
    for id in "${ids[@]}"; do
        [[ "$id" =~ ^[[:xdigit:]]{4}:[[:xdigit:]]{4}:[[:xdigit:]]{8}$ ]] || die "invalid full keyd ID '$id'; use VENDOR:PRODUCT:UNIQUE_ID"
        id="${id,,}"
        [[ " ${normalized_ids[*]} " == *" $id "* ]] || normalized_ids+=("$id")
    done
    [ -r "$TEMPLATE" ] || die "missing template: $TEMPLATE"
    config="$(
        printf '%s\n' "$MARKER"
        while IFS= read -r line || [ -n "$line" ]; do
            if [ "$line" = '@KEYD_DEVICE_ID@' ]; then
                printf '%s\n' "${normalized_ids[@]}"
            else
                printf '%s\n' "$line"
            fi
        done < "$TEMPLATE"
    )"

    if [ "$dry" -eq 1 ]; then
        printf '%s\n' "$config"
        return 0
    fi
    require_root
    command -v keyd >/dev/null 2>&1 || die 'keyd is not installed; install and verify keyd before applying this mapping'
    command -v systemctl >/dev/null 2>&1 || die 'systemd is required for the managed keyd service'

    mkdir -p "$CONFIG_DIR"
    if [ -L "$TARGET" ]; then
        die "refusing to replace symlink $TARGET"
    fi
    if [ -f "$TARGET" ] && ! grep -qF "$MARKER" "$TARGET"; then
        die "refusing to replace unmanaged $TARGET; review it manually"
    fi

    local tmp
    tmp="$(mktemp "$CONFIG_DIR/.dotfiles-capslock.XXXXXX")"
    printf '%s\n' "$config" > "$tmp"
    chmod 644 "$tmp"
    if [ -f "$TARGET" ] && cmp -s "$tmp" "$TARGET"; then
        rm -f "$tmp"
        log 'Mapping already installed; restarting keyd to ensure it is active'
    else
        [ ! -e "$TARGET" ] || backup_existing "$TARGET"
        mv -f -- "$tmp" "$TARGET"
        log "Installed Caps Lock → grave mapping for ${normalized_ids[*]}"
    fi
    keyd check || die 'keyd rejected the current configuration; the mapping file was left in place and the service was not started'
    systemctl daemon-reload
    systemctl enable --now keyd.service
    systemctl restart keyd.service
    log 'Caps Lock now sends the grave key; verify it in Ghostty and tmux.'
}

status() {
    if [ -f "$TARGET" ] && grep -qF "$MARKER" "$TARGET"; then
        log "Managed mapping: $TARGET"
        sed -n '/^\[ids\]/,/^\[main\]/p; /^capslock =/p' "$TARGET"
    else
        log 'No dotfiles-managed keyd mapping is installed.'
    fi
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet keyd.service; then
        log 'keyd service is active.'
    else
        log 'keyd service is not active.'
    fi
}

remove_mapping() {
    local dry=0
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) dry=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) die "unknown remove option: $1" ;;
        esac
    done
    [ -e "$TARGET" ] || { log 'No managed mapping to remove.'; return 0; }
    [ ! -L "$TARGET" ] && grep -qF "$MARKER" "$TARGET" || die "refusing to remove unmanaged $TARGET"
    if [ "$dry" -eq 1 ]; then
        log "Would remove $TARGET and restart keyd if active."
        return 0
    fi
    require_root
    rm -- "$TARGET"
    log 'Removed managed Caps Lock mapping.'
    service_restart
}

case "${1:-}" in
    apply) apply "$@" ;;
    status) [ "$#" -eq 1 ] || die 'status takes no options'; status ;;
    remove) remove_mapping "$@" ;;
    -h|--help) usage ;;
    *) usage >&2; exit 2 ;;
esac
