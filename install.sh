#!/bin/bash

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

create_symlink() {
    local source="$1"
    local target="$2"

    if [ -L "$target" ]; then
        log_warn "Symlink already exists: $target"
        return 0
    fi

    if [ -f "$target" ] || [ -d "$target" ]; then
        log_warn "File/directory exists at $target, backing up to ${target}.backup"
        mv "$target" "${target}.backup"
    fi

    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
    log_info "Created symlink: $target -> $source"
}

# Machine-local config files: private values, per-machine paths, credentials.
# They live outside this repo by design and so do not arrive with a clone.
#
# Every consumer of these reads them behind a [ -f ] guard, which means an
# absent file is SILENT. That is how a fresh machine ends up with no proxy
# credentials while every script reports success. Seeding a stub from the
# committed template makes the gap visible.
#
# Each *.example is written to be inert when copied verbatim, so seeding can
# never introduce a placeholder that looks like a real value.
SEEDED_CONFIGS=()

seed_local_config() {
    local example="$1" target="$2" mode="${3:-600}" hint="${4:-}"

    if [ ! -f "$example" ]; then
        log_warn "Missing template: $example"
        return 0
    fi

    # Never touch a file that already exists — it holds real credentials.
    [ -e "$target" ] && return 0

    mkdir -p "$(dirname "$target")"
    cp "$example" "$target"
    chmod "$mode" "$target"
    log_info "Created $target from $(basename "$example")"
    SEEDED_CONFIGS+=("$target${hint:+  ->  $hint}")
}

# i3 configuration
if [ -f "$DOTFILES_DIR/i3/config" ]; then
    create_symlink "$DOTFILES_DIR/i3/config" "$HOME/.config/i3/config"
fi

if [ -d "$DOTFILES_DIR/i3/scripts" ]; then
    create_symlink "$DOTFILES_DIR/i3/scripts" "$HOME/.config/i3/scripts"
fi

# Ghostty configuration
if [ -f "$DOTFILES_DIR/ghostty/config" ]; then
    create_symlink "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config"
fi

# tmux configuration
if [ -f "$DOTFILES_DIR/tmux/.tmux.conf" ]; then
    create_symlink "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
fi

# Neovim configuration
if [ -d "$DOTFILES_DIR/nvim" ]; then
    create_symlink "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
fi

# Zsh configuration
if [ -f "$DOTFILES_DIR/zsh/.zshrc" ]; then
    create_symlink "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
fi

if [ -f "$DOTFILES_DIR/zsh/.zprofile" ]; then
    create_symlink "$DOTFILES_DIR/zsh/.zprofile" "$HOME/.zprofile"
fi

if [ -f "$DOTFILES_DIR/zsh/.p10k.zsh" ]; then
    create_symlink "$DOTFILES_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
fi

# Git configuration
if [ -f "$DOTFILES_DIR/git/.gitconfig" ]; then
    create_symlink "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
fi

if [ -f "$DOTFILES_DIR/git/.gitignore_global" ]; then
    create_symlink "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
fi

if [ -f "$DOTFILES_DIR/git/config/git/ignore" ]; then
    create_symlink "$DOTFILES_DIR/git/config/git/ignore" "$HOME/.config/git/ignore"
fi

# --- Proxy routing (sing-box TUN) -----------------------------------------
# Routing policy lives in proxy/direct-domains.txt (what stays off the VPS)
# and proxy/block-domains.txt; secrets stay in
# ~/.config/sing-box/secrets.env and never enter this repo. The daemon runs as
# a root systemd service; see proxy/README.md for the model.
#
# The .deb from sing-box.app installs /usr/bin/sing-box and a unit at
# /usr/lib/systemd/system/sing-box.service that runs as User=sing-box and
# cannot read our mode-600 root config. Installing our unit at
# /etc/systemd/system/sing-box.service overrides it. We do not enable it here:
# `proxyctl on` does, so the machine is not routing everything through the VPS
# before secrets are filled in.
#
# Guarded like the rest: install.sh runs under `set -e`, and an unconfigured
# proxy must not abort the remaining setup. Set PROXY_SETUP=0 to skip.
setup_proxy() {
    local secrets="$HOME/.config/sing-box/secrets.env"
    local unit_src="$DOTFILES_DIR/proxy/sing-box.service"
    local unit_dst="/etc/systemd/system/sing-box.service"
    local found tmp_unit

    create_symlink "$DOTFILES_DIR/bin/proxyctl" "$HOME/.local/bin/proxyctl"

    # The committed unit names /usr/bin/sing-box (where the .deb puts it). A
    # manual or tarball install may land elsewhere, so substitute the path we
    # actually found rather than leave a unit that cannot exec.
    found="$(command -v sing-box || true)"

    if [ -f "$unit_src" ] && [ ! -f "$unit_dst" ]; then
        tmp_unit="$(mktemp)"
        sed "s|^ExecStart=/usr/bin/sing-box |ExecStart=${found:-/usr/bin/sing-box} |" \
            "$unit_src" > "$tmp_unit"
        sudo install -m 644 -o root -g root "$tmp_unit" "$unit_dst"
        rm -f "$tmp_unit"
        sudo systemctl daemon-reload
        log_info "Installed $unit_dst (ExecStart=${found:-/usr/bin/sing-box})"
    elif [ -f "$unit_dst" ]; then
        log_info "systemd unit already installed: $unit_dst"
    fi

    if [ -z "$found" ]; then
        log_warn "sing-box not installed - install it, then re-run this script:"
        log_warn "  curl -fsSL https://sing-box.app/install.sh | sudo sh"
        return 0
    fi

    if [ ! -f "$secrets" ]; then
        seed_local_config "$DOTFILES_DIR/proxy/secrets.env.example" \
            "$secrets" 600 "six VLESS values, then: proxyctl on"
        return 0
    fi

    log_info "Proxy configured - run 'proxyctl status' to check"
}

if [ "${PROXY_SETUP:-1}" != "0" ]; then
    setup_proxy || log_warn "Proxy setup incomplete"
fi

# Say plainly what still needs a human. These were all silent failures before:
# the file is created and readable, so every [ -f ] guard downstream passes,
# and the missing VALUE only surfaces much later.
if [ ${#SEEDED_CONFIGS[@]} -gt 0 ]; then
    echo
    log_warn "Created ${#SEEDED_CONFIGS[@]} local config file(s) from templates."
    log_warn "They are INERT until filled in - every value is commented out:"
    for _seeded in "${SEEDED_CONFIGS[@]}"; do
        log_warn "    $_seeded"
    done
    echo
fi

log_info "Dotfiles installation complete!"
log_info "You may need to restart applications to pick up the new configurations."
