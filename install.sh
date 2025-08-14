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

# tmux configuration
if [ -f "$DOTFILES_DIR/tmux/.tmux.conf" ]; then
    create_symlink "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
fi

# Aerospace configuration
if [ -f "$DOTFILES_DIR/aerospace/aerospace.toml" ]; then
    create_symlink "$DOTFILES_DIR/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"
fi

# Ghostty configuration
if [ -f "$DOTFILES_DIR/ghostty/config" ]; then
    create_symlink "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config"
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

# Optional: Install Homebrew packages
log_info "To install Homebrew packages, run: ./brew-install.sh"

log_info "Dotfiles installation complete!"
log_info "You may need to restart applications to pick up the new configurations."