#!/usr/bin/env bash
# Install the specifically missing Ubuntu parity dependencies without replacing
# distro tmux/fzf packages or touching credentials, proxy services, or Pi auth.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOME_DIR="${HOME:?HOME must be set}"
USER_BIN="$HOME_DIR/.local/bin"
TOOL_ROOT="$HOME_DIR/.local/opt/dotfiles-toolchain"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME_DIR/.pi/agent}"

TMUX_VERSION='3.5a'
TMUX_SHA256='16216bd0877170dfcc64157085ba9013610b12b082548c7c9542cc0103198951'
FZF_VERSION='0.61.3'
FZF_AMD64_SHA256='6a4f4b211b6b8944c7320f66db468d731888aa86b19d5b0ccdf28fa0d0e06e47'
FZF_ARM64_SHA256='0a15108bbf20f563e620cb7527515b7db6fcf6ecfec2a2540a58585b9f02c3c6'
KEYD_VERSION='2.6.0'
KEYD_COMMIT='7c0aecb'
KEYD_SHA256='697089681915b89d9e98caf93d870dbd4abce768af8a647d54650a6a90744e26'
PI_SUBAGENTS_VERSION='0.76.0'

APPLY=0
CONFIGURE_KEYBOARD=0
DEVICE_ID=''
SKIP_PI=0
MODE_SET=0
WORK_DIR=''
STAGING_PATHS=()

usage() {
    cat <<'EOF'
Install missing Ubuntu dotfiles parity dependencies.

Usage:
  ubuntu/install-missing.sh                         # preview only (default)
  ubuntu/install-missing.sh --dry-run
  ubuntu/install-missing.sh --apply [--skip-pi]
  ubuntu/install-missing.sh --apply --configure-keyboard --device-id VVVV:PPPP:HHHHHHHH

The installer adds apt build/runtime dependencies, installs pinned tmux/fzf
under ~/.local/opt/dotfiles-toolchain with links in ~/.local/bin, builds pinned
keyd without starting it, and installs only the pinned pi-subagents package.
Existing distro tmux/fzf packages are not removed or overwritten.

Keyboard activation is a separate, explicit option. Identify the laptop device
with `sudo keyd monitor` first. Activation requires an interactive confirmation
and never writes a wildcard keyd rule.
EOF
}

log() { printf '[install-missing] %s\n' "$*"; }
die() { printf '[install-missing] ERROR: %s\n' "$*" >&2; exit 1; }

version_ge() {
    local actual="$1" minimum="$2"
    [ -n "$actual" ] && [ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n1)" = "$minimum" ]
}

command_version() {
    case "$1" in
        tmux) command -v tmux >/dev/null 2>&1 && tmux -V 2>/dev/null | awk '{print $2}' ;;
        fzf) command -v fzf >/dev/null 2>&1 && fzf --version 2>/dev/null | awk 'NR == 1 {print $1}' ;;
        *) return 1 ;;
    esac
}

needs_upgrade() {
    local name="$1" minimum="$2" version
    version="$(command_version "$name" || true)"
    ! version_ge "$version" "$minimum"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run)
                [ "$MODE_SET" -eq 0 ] || die 'choose only one of --dry-run or --apply'
                MODE_SET=1
                APPLY=0
                shift
                ;;
            --apply)
                [ "$MODE_SET" -eq 0 ] || die 'choose only one of --dry-run or --apply'
                MODE_SET=1
                APPLY=1
                shift
                ;;
            --configure-keyboard)
                CONFIGURE_KEYBOARD=1
                shift
                ;;
            --device-id)
                [ "$#" -ge 2 ] || die '--device-id requires VENDOR:PRODUCT:UNIQUE_ID'
                DEVICE_ID="$2"
                shift 2
                ;;
            --skip-pi)
                SKIP_PI=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *) die "unknown option: $1" ;;
        esac
    done

    if [ "$CONFIGURE_KEYBOARD" -eq 1 ]; then
        [[ "$DEVICE_ID" =~ ^[[:xdigit:]]{4}:[[:xdigit:]]{4}:[[:xdigit:]]{8}$ ]] || die '--configure-keyboard requires the full --device-id VENDOR:PRODUCT:UNIQUE_ID from keyd monitor'
    elif [ -n "$DEVICE_ID" ]; then
        die '--device-id is accepted only with --configure-keyboard'
    fi
}

print_plan() {
    cat <<EOF
Ubuntu missing-dependency plan
  apt packages: bat/fd-find (if missing), build-essential, bison, pkg-config,
                libevent-dev, libncurses-dev, curl, ca-certificates, coreutils
  tmux:         $TMUX_VERSION (verified source archive SHA-256 $TMUX_SHA256)
  fzf:          $FZF_VERSION (verified release binary SHA-256 for this architecture)
  keyd:         v$KEYD_VERSION (verified source archive SHA-256 $KEYD_SHA256)
  Pi:           npm:pi-subagents@$PI_SUBAGENTS_VERSION only (unless --skip-pi)
  tool location: $TOOL_ROOT and $USER_BIN
EOF
    if [ "$CONFIGURE_KEYBOARD" -eq 1 ]; then
        printf '  keyboard:    enable Caps Lock -> grave for requested full ID %s after verification and confirmation\n' "$DEVICE_ID"
    else
        printf '  keyboard:    install keyd only; do not enable service or change mappings\n'
    fi
    if [ "$APPLY" -eq 0 ]; then
        printf '\nDRY RUN: no packages, downloads, Pi settings, services, or keyboard mappings changed.\n'
    fi
}

verify_keyboard_device() {
    local wanted_vendor wanted_product ignored_unique
    local event vendor product properties
    IFS=: read -r wanted_vendor wanted_product ignored_unique <<<"$DEVICE_ID"
    wanted_vendor="${wanted_vendor,,}"
    wanted_product="${wanted_product,,}"
    command -v udevadm >/dev/null 2>&1 || die 'udevadm is required to verify a keyboard device ID'

    for event in /sys/class/input/event*; do
        [ -e "$event/device/id/vendor" ] && [ -e "$event/device/id/product" ] || continue
        vendor="$(tr '[:upper:]' '[:lower:]' < "$event/device/id/vendor")"
        product="$(tr '[:upper:]' '[:lower:]' < "$event/device/id/product")"
        [ "$vendor:$product" = "$wanted_vendor:$wanted_product" ] || continue
        properties="$(udevadm info --query=property --path="$event" 2>/dev/null || true)"
        if grep -qx 'ID_INPUT_KEYBOARD=1' <<<"$properties"; then
            log "verified the vendor/product prefix for full keyd ID $DEVICE_ID belongs to a keyboard at $event"
            return 0
        fi
    done
    die "device prefix for $DEVICE_ID was not found as a keyboard in sysfs; recheck the full ID with sudo keyd monitor"
}

confirm_keyboard_activation() {
    [ -t 0 ] || die 'keyboard activation requires a terminal for the confirmation prompt'
    printf '\nThis will enable keyd and change Caps Lock on device %s to emit grave.\n' "$DEVICE_ID" >&2
    printf 'Confirm that `sudo keyd monitor` identified the laptop keyboard, then type APPLY %s: ' "$DEVICE_ID" >&2
    local answer
    IFS= read -r answer
    [ "$answer" = "APPLY $DEVICE_ID" ] || die 'keyboard activation was not confirmed'
}

require_apply_prerequisites() {
    [ "$(id -u)" -ne 0 ] || die 'run as your normal user; this script uses sudo only for apt/keyd system installation'
    command -v sudo >/dev/null 2>&1 || die 'sudo is required for apt and keyd system installation'

    . /etc/os-release
    [ "${ID:-}" = ubuntu ] || die "this installer supports Ubuntu only (detected ${PRETTY_NAME:-unknown})"
    [ "${VERSION_ID:-}" = 24.04 ] || die "review package availability before using on Ubuntu ${VERSION_ID:-unknown}; this installer is pinned/tested for 24.04"

    if [ "$CONFIGURE_KEYBOARD" -eq 1 ]; then
        verify_keyboard_device
        confirm_keyboard_activation
    fi
    sudo -v
}

install_apt_dependencies() {
    local packages=(build-essential bison pkg-config libevent-dev libncurses-dev curl ca-certificates coreutils)
    if ! command -v bat >/dev/null 2>&1 && ! command -v batcat >/dev/null 2>&1; then
        packages+=(bat)
    fi
    if ! command -v fd >/dev/null 2>&1 && ! command -v fdfind >/dev/null 2>&1; then
        packages+=(fd-find)
    fi
    log "refreshing apt metadata and installing: ${packages[*]}"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends "${packages[@]}"
}

download_verified() {
    local url="$1" expected="$2" output="$3"
    curl --proto '=https' --tlsv1.2 --fail --location --retry 3 --connect-timeout 20 --output "$output" "$url"
    printf '%s  %s\n' "$expected" "$output" | sha256sum --check --status || die "SHA-256 verification failed for $url"
}

ensure_command_compat() {
    local name="$1" alternate="$2" target="$USER_BIN/$1" source
    command -v "$name" >/dev/null 2>&1 && return 0
    source="$(command -v "$alternate" 2>/dev/null || true)"
    [ -n "$source" ] || return 0
    if [ -e "$target" ] || [ -L "$target" ]; then
        log "leaving existing compatibility target untouched: $target"
        return 0
    fi
    mkdir -p "$USER_BIN"
    ln -s -- "$source" "$target"
    log "created compatibility link $target -> $source"
}

local_link() {
    local target="$2" link current
    link="$USER_BIN/$1"
    mkdir -p "$USER_BIN"
    if [ -L "$link" ]; then
        current="$(readlink -f -- "$link" 2>/dev/null || true)"
        if [ "$current" = "$target" ]; then
            return 0
        fi
        case "$current" in
            "$TOOL_ROOT"/*) ln -sfn -- "$target" "$link" ;;
            *) die "refusing to replace foreign symlink $link -> ${current:-broken}" ;;
        esac
    elif [ -e "$link" ]; then
        die "refusing to replace existing non-managed file $link"
    else
        ln -s -- "$target" "$link"
    fi
}

install_tmux() {
    local current source_dir stage target archive jobs
    if ! needs_upgrade tmux 3.5; then
        log "tmux $(command_version tmux) already meets >= 3.5"
        return 0
    fi

    target="$TOOL_ROOT/tmux-$TMUX_VERSION"
    if [ -x "$target/bin/tmux" ]; then
        current="$("$target/bin/tmux" -V 2>/dev/null | awk '{print $2}')"
        [ "$current" = "$TMUX_VERSION" ] || die "existing $target is not the expected tmux $TMUX_VERSION; inspect it manually"
        log "reusing verified-version tmux at $target"
    elif [ -e "$target" ]; then
        die "refusing to overwrite incomplete tool directory $target"
    else
        mkdir -p "$TOOL_ROOT"
        archive="$WORK_DIR/tmux-$TMUX_VERSION.tar.gz"
        download_verified "https://github.com/tmux/tmux/releases/download/$TMUX_VERSION/tmux-$TMUX_VERSION.tar.gz" "$TMUX_SHA256" "$archive"
        source_dir="$WORK_DIR/tmux-src"
        mkdir -p "$source_dir"
        tar -xzf "$archive" -C "$source_dir" --strip-components=1
        stage="$TOOL_ROOT/.tmux-$TMUX_VERSION.staging.$$"
        [ ! -e "$stage" ] || die "staging path already exists: $stage"
        STAGING_PATHS+=("$stage")
        mkdir -p "$stage"
        jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')"
        (cd "$source_dir" && ./configure --prefix="$stage" && make -j"$jobs" && make install)
        [ -x "$stage/bin/tmux" ] || die 'tmux build did not produce a binary'
        current="$("$stage/bin/tmux" -V 2>/dev/null | awk '{print $2}')"
        [ "$current" = "$TMUX_VERSION" ] || die "built tmux reports '$current', expected $TMUX_VERSION"
        mv -- "$stage" "$target"
        log "installed tmux $TMUX_VERSION under $target (distro package left intact)"
    fi
    local_link tmux "$target/bin/tmux"
}

install_fzf() {
    local current target archive source_dir stage arch asset checksum
    if ! needs_upgrade fzf 0.48.0; then
        log "fzf $(command_version fzf) already meets >= 0.48.0"
        return 0
    fi

    case "$(uname -m)" in
        x86_64) arch=amd64; checksum="$FZF_AMD64_SHA256" ;;
        aarch64|arm64) arch=arm64; checksum="$FZF_ARM64_SHA256" ;;
        *) die "no pinned fzf $FZF_VERSION release for architecture $(uname -m)" ;;
    esac
    asset="fzf-$FZF_VERSION-linux_$arch.tar.gz"
    target="$TOOL_ROOT/fzf-$FZF_VERSION"
    if [ -x "$target/bin/fzf" ]; then
        current="$("$target/bin/fzf" --version 2>/dev/null | awk 'NR == 1 {print $1}')"
        [ "$current" = "$FZF_VERSION" ] || die "existing $target is not the expected fzf $FZF_VERSION; inspect it manually"
        log "reusing verified-version fzf at $target"
    elif [ -e "$target" ]; then
        die "refusing to overwrite incomplete tool directory $target"
    else
        mkdir -p "$TOOL_ROOT"
        archive="$WORK_DIR/$asset"
        download_verified "https://github.com/junegunn/fzf/releases/download/v$FZF_VERSION/$asset" "$checksum" "$archive"
        source_dir="$WORK_DIR/fzf-src"
        mkdir -p "$source_dir"
        tar -xzf "$archive" -C "$source_dir"
        [ -x "$source_dir/fzf" ] || die 'fzf release archive did not contain an executable fzf'
        current="$("$source_dir/fzf" --version 2>/dev/null | awk 'NR == 1 {print $1}')"
        [ "$current" = "$FZF_VERSION" ] || die "downloaded fzf reports '$current', expected $FZF_VERSION"
        stage="$TOOL_ROOT/.fzf-$FZF_VERSION.staging.$$"
        [ ! -e "$stage" ] || die "staging path already exists: $stage"
        STAGING_PATHS+=("$stage")
        mkdir -p "$stage/bin"
        install -m 755 "$source_dir/fzf" "$stage/bin/fzf"
        mv -- "$stage" "$target"
        log "installed fzf $FZF_VERSION under $target (distro package left intact)"
    fi
    local_link fzf "$target/bin/fzf"
}

install_keyd() {
    local source_dir archive jobs
    if command -v keyd >/dev/null 2>&1; then
        log "keyd already installed at $(command -v keyd); leaving its version and files untouched"
        return 0
    fi

    archive="$WORK_DIR/keyd-$KEYD_VERSION.tar.gz"
    download_verified "https://github.com/rvaiya/keyd/archive/refs/tags/v$KEYD_VERSION.tar.gz" "$KEYD_SHA256" "$archive"
    source_dir="$WORK_DIR/keyd-src"
    mkdir -p "$source_dir"
    tar -xzf "$archive" -C "$source_dir" --strip-components=1
    jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')"
    log "building upstream keyd v$KEYD_VERSION"
    make -C "$source_dir" -j"$jobs" COMMIT="$KEYD_COMMIT"
    "$source_dir/bin/keyd" --help >/dev/null 2>&1 || die 'built keyd binary failed its smoke test'
    sudo make -C "$source_dir" install PREFIX=/usr/local
    sudo systemctl daemon-reload
    log 'installed keyd service files; service remains disabled unless keyboard configuration was explicitly requested'
}

pi_package_version() {
    local package_json="$PI_DIR/npm/node_modules/pi-subagents/package.json"
    [ -r "$package_json" ] || return 1
    if command -v node >/dev/null 2>&1; then
        node -e 'const p=require(process.argv[1]); process.stdout.write(`${p.name}@${p.version}`)' "$package_json"
    else
        sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/pi-subagents@\1/p' "$package_json" | head -n1
    fi
}

install_pi_package() {
    local installed pi_bin settings_file
    [ "$SKIP_PI" -eq 0 ] || { log 'Pi package install skipped by --skip-pi'; return 0; }
    settings_file="$PI_DIR/settings.json"
    installed="$(pi_package_version || true)"
    if [ "$installed" = "pi-subagents@$PI_SUBAGENTS_VERSION" ] && \
        [ -r "$settings_file" ] && grep -Fq "npm:pi-subagents@$PI_SUBAGENTS_VERSION" "$settings_file"; then
        log "pi-subagents@$PI_SUBAGENTS_VERSION is installed and declared in Pi settings"
        return 0
    fi

    if [ -x "$PI_DIR/bin/pi" ]; then
        pi_bin="$PI_DIR/bin/pi"
    elif command -v pi >/dev/null 2>&1; then
        pi_bin="$(command -v pi)"
    else
        die 'Pi is not installed; install Pi from its official instructions before installing pi-subagents'
    fi
    log "installing only npm:pi-subagents@$PI_SUBAGENTS_VERSION through Pi (this updates the user's Pi package settings)"
    (cd "$HOME_DIR" && "$pi_bin" install "npm:pi-subagents@$PI_SUBAGENTS_VERSION")
    installed="$(pi_package_version || true)"
    [ "$installed" = "pi-subagents@$PI_SUBAGENTS_VERSION" ] || die "Pi install completed but expected package was not found under $PI_DIR/npm/node_modules"
}

activate_keyboard() {
    [ "$CONFIGURE_KEYBOARD" -eq 1 ] || return 0
    sudo systemctl cat keyd.service >/dev/null 2>&1 || die 'keyd.service is not installed; refusing to write a mapping without a service unit'
    log "applying the confirmed Caps Lock -> grave mapping for $DEVICE_ID"
    sudo "$REPO_ROOT/keyboard-linux-setup.sh" apply --device-id "$DEVICE_ID"
}

run_validation() {
    local failed=0 node_version
    export PATH="$USER_BIN:$PATH"
    "$SCRIPT_DIR/check-dependencies.sh" || failed=1

    node_version="$(node --version 2>/dev/null | sed 's/^v//' || true)"
    if version_ge "$node_version" 24.0.0 && [ -d "$PI_DIR/npm/node_modules/pi-subagents" ]; then
        log 'running pinned Pi subagent agent-discovery tests with Node 24+'
        PI_SUBAGENTS_PACKAGE="$PI_DIR/npm/node_modules/pi-subagents" node --test "$REPO_ROOT/pi/agents.test.mjs" || failed=1
    else
        log 'Pi agent-discovery test skipped; it requires Node 24+ and the installed package'
    fi
    return "$failed"
}

cleanup() {
    local path
    for path in "${STAGING_PATHS[@]}"; do
        [ ! -e "$path" ] || rm -rf -- "$path"
    done
    [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ] || rm -rf -- "$WORK_DIR"
}

main() {
    parse_args "$@"
    export PATH="$USER_BIN:$PATH"
    print_plan
    [ "$APPLY" -eq 1 ] || return 0

    require_apply_prerequisites
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-missing.XXXXXX")"
    trap cleanup EXIT

    install_apt_dependencies
    ensure_command_compat fd fdfind
    ensure_command_compat bat batcat
    install_tmux
    install_fzf
    install_keyd
    install_pi_package
    activate_keyboard
    log 'installation steps finished; checking the configured dependency set'
    run_validation || die 'some checks still fail; review the output above'
    log 'all required dependency checks passed'
}

main "$@"
