#!/bin/bash
#
# Toggle the macOS on-device media analysis daemons.
#
# mediaanalysisd and photoanalysisd scan the Photos library for faces, scenes,
# OCR and Visual Look Up. Disabling them stops that work; it also stops HomeKit
# Secure Video analysis and Live Text, which share the same XPC services.
#
# On macOS 15 (Sequoia) mediaanalysisd also leaks compiled Neural Engine model
# bundles under ~/Library/Containers/com.apple.mediaanalysisd, which can grow to
# tens of gigabytes.
#
# Both labels are user LaunchAgents, so `launchctl disable` works without sudo
# and persists across reboots. SIP still blocks `bootout`, so an already-running
# instance survives until it idles out or the machine reboots.

set -e

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

DAEMONS=(
    com.apple.mediaanalysisd
    com.apple.photoanalysisd
)

# Seams for the test suite; both default to the real thing.
LAUNCHCTL="${LAUNCHCTL:-launchctl}"
OS_NAME="${OS_NAME:-$(uname -s)}"

DOMAIN="gui/$(id -u)"

usage() {
    cat <<EOF
Usage: $(basename "$0") [disable|enable|status]

  disable   Stop the media analysis daemons from launching (default)
  enable    Restore stock macOS behaviour
  status    Report whether each daemon is currently disabled

macOS updates can reset launchd's override database, so re-run 'status'
after upgrading to confirm the daemons are still disabled.
EOF
}

# `launchctl print-disabled` is authoritative: it reads the override database
# that actually gates launching, not whether a process happens to be alive.
is_disabled() {
    local label="$1" listing="$2"
    case "$listing" in
        *"\"$label\" => disabled"*) return 0 ;;
        *) return 1 ;;
    esac
}

is_running() {
    local label="$1" state
    state="$("$LAUNCHCTL" print "$DOMAIN/$label" 2>/dev/null || true)"
    case "$state" in
        *"state = running"*) return 0 ;;
        *) return 1 ;;
    esac
}

cmd_disable() {
    local label still_running=0
    for label in "${DAEMONS[@]}"; do
        "$LAUNCHCTL" disable "$DOMAIN/$label"
        log_info "Disabled $label"
        if is_running "$label"; then
            still_running=1
            log_warn "$label is still running; SIP blocks bootout"
        fi
    done

    if [ "$still_running" -eq 1 ]; then
        log_warn "Reboot to stop the running instance — it will not relaunch after that."
    fi
}

cmd_enable() {
    local label
    for label in "${DAEMONS[@]}"; do
        "$LAUNCHCTL" enable "$DOMAIN/$label"
        log_info "Enabled $label"
    done
    log_info "Stock behaviour restored. Photos will re-analyse the library in the background."
}

cmd_status() {
    local listing label
    listing="$("$LAUNCHCTL" print-disabled "$DOMAIN" 2>/dev/null || true)"

    for label in "${DAEMONS[@]}"; do
        if is_disabled "$label" "$listing"; then
            log_info "$label: disabled"
        else
            log_warn "$label: enabled"
        fi
    done
}

if [ "$OS_NAME" != "Darwin" ]; then
    log_warn "Not macOS ($OS_NAME) — nothing to do"
    exit 0
fi

case "${1:-disable}" in
    disable) cmd_disable ;;
    enable)  cmd_enable ;;
    status)  cmd_status ;;
    -h|--help|help) usage ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 2
        ;;
esac
