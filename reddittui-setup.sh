#!/bin/bash
#
# Install reddittui, a terminal Reddit client.
#
# Three things rule out the obvious install routes:
#
#   - No Homebrew formula exists. (`brew search` suggests `reddix`, which is a
#     different client and needs Reddit OAuth credentials — see the README for
#     why that disqualified it.)
#   - `go install` cannot work. Upstream's go.mod declares `module reddittui`,
#     a bare name rather than a repository path, so there is nothing for
#     `go install github.com/tonymajestro/reddit-tui@latest` to resolve.
#   - Building from a clone drags in a second Go toolchain. go.mod asks for Go
#     1.23.4 and this machine has 1.22.1, so `go build` silently downloads and
#     caches another toolchain on every fresh machine.
#
# So this takes the fourth route: the GoReleaser binary attached to the GitHub
# release, checksum-verified before it is installed. Upstream's own install.sh
# sudo-installs to /usr/local/bin; this installs to ~/.local/bin instead, which
# is already on PATH from .zshrc and needs no root.
#
# The version is pinned below. Bumping it is a one-line edit followed by
# `./reddittui-setup.sh install`; `status` reports when upstream is ahead.

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

REPO="tonymajestro/reddit-tui"
VERSION="${REDDITTUI_VERSION:-v0.3.9}"

# Seams for the test suite; all default to the real thing.
BIN_DIR="${REDDITTUI_BIN_DIR:-$HOME/.local/bin}"
CONFIG_FILE="${REDDITTUI_CONFIG:-$HOME/.config/reddittui/reddittui.toml}"
BASE_URL="${REDDITTUI_BASE_URL:-https://github.com/$REPO/releases/download}"
API_URL="${REDDITTUI_API_URL:-https://api.github.com/repos/$REPO}"

BIN="$BIN_DIR/reddittui"

usage() {
    cat <<EOF
Usage: $(basename "$0") [install|status]

  install   Download the pinned release, verify its checksum, install to
            $BIN_DIR (default)
  status    Report the installed version, the pinned version, and whether
            upstream has published a newer one

Pinned version: $VERSION (override with REDDITTUI_VERSION)
EOF
}

# GoReleaser names assets by uname-style OS and arch. Only the Darwin builds
# matter here, but the arch split is real: this repo runs on both prefixes.
asset_name() {
    local arch
    arch="$(uname -m)"

    case "$arch" in
        arm64)  echo "reddit-tui_Darwin_arm64.tar.gz" ;;
        x86_64) echo "reddit-tui_Darwin_x86_64.tar.gz" ;;
        *)
            log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac
}

installed_version() {
    [ -x "$BIN" ] || return 1
    # "reddittui version v0.3.9" -> "v0.3.9"
    "$BIN" -version 2>/dev/null | awk '{print $NF}'
}

latest_version() {
    curl -fsSL --max-time 10 "$API_URL/releases/latest" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null
}

cmd_install() {
    local asset current tmp checksums

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl not found"
        return 1
    fi

    asset="$(asset_name)" || return 1

    if current="$(installed_version)" && [ "$current" = "$VERSION" ]; then
        log_info "reddittui $VERSION already installed at $BIN"
        return 0
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    log_info "Downloading reddittui $VERSION ($asset)"
    if ! curl -fsSL -o "$tmp/$asset" "$BASE_URL/$VERSION/$asset"; then
        log_error "Download failed — is $VERSION a real release tag?"
        return 1
    fi

    # The checksums file is named after the bare version, without the v.
    checksums="reddit-tui_${VERSION#v}_checksums.txt"
    if ! curl -fsSL -o "$tmp/$checksums" "$BASE_URL/$VERSION/$checksums"; then
        log_error "Could not fetch $checksums — refusing to install unverified"
        return 1
    fi

    # Verify before extracting, not after installing. The whole point of
    # pulling a prebuilt binary instead of building one is that the checksum
    # is the only thing standing in for the build.
    if ! (cd "$tmp" && grep " $asset\$" "$checksums" | shasum -a 256 -c - >/dev/null 2>&1); then
        log_error "Checksum mismatch for $asset — refusing to install"
        return 1
    fi
    log_info "Checksum verified"

    tar xzf "$tmp/$asset" -C "$tmp"
    if [ ! -f "$tmp/reddittui" ]; then
        log_error "Archive did not contain a reddittui binary"
        return 1
    fi

    mkdir -p "$BIN_DIR"
    install -m 0755 "$tmp/reddittui" "$BIN"

    if [ -n "${current:-}" ]; then
        log_info "Upgraded reddittui $current -> $VERSION at $BIN"
    else
        log_info "Installed reddittui $VERSION at $BIN"
    fi
}

cmd_status() {
    local current latest

    if ! current="$(installed_version)"; then
        log_warn "reddittui: not installed — run '$(basename "$0") install'"
    else
        log_info "reddittui: $current at $BIN"
        if [ "$current" != "$VERSION" ]; then
            log_warn "pinned version is $VERSION — run '$(basename "$0") install'"
        fi
    fi

    if [ -L "$CONFIG_FILE" ]; then
        log_info "config: $CONFIG_FILE -> $(readlink "$CONFIG_FILE")"
    elif [ -f "$CONFIG_FILE" ]; then
        log_warn "config: $CONFIG_FILE exists but is not a symlink — run ./install.sh"
    else
        log_warn "config: $CONFIG_FILE missing — run ./install.sh"
    fi

    # Advisory only: a machine with no network still gets a useful status.
    if latest="$(latest_version)" && [ -n "$latest" ] && [ "$latest" != "$VERSION" ]; then
        log_warn "upstream is at $latest; this repo pins $VERSION"
        log_warn "to bump: edit VERSION in $(basename "$0"), then re-run install"
    fi
}

case "${1:-install}" in
    install) cmd_install ;;
    status)  cmd_status ;;
    -h|--help|help) usage ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 2
        ;;
esac
