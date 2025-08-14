#!/bin/bash

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

# Check if zsh is installed
if ! command -v zsh >/dev/null 2>&1; then
    log_error "Zsh is not installed. Install it first:"
    log_info "brew install zsh"
    exit 1
fi

# Install Oh My Zsh if not already installed
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    log_info "✅ Oh My Zsh installed"
else
    log_info "Oh My Zsh already installed"
fi

# Install Powerlevel10k theme
if [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
    log_info "Installing Powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    log_info "✅ Powerlevel10k theme installed"
else
    log_info "Powerlevel10k theme already installed"
fi

# Check if .p10k.zsh exists and copy it
if [ -f "$HOME/.p10k.zsh" ]; then
    log_info "Found existing Powerlevel10k configuration"
    cp "$HOME/.p10k.zsh" "$(dirname "$0")/zsh/.p10k.zsh"
    log_info "✅ Powerlevel10k config copied to dotfiles"
fi

log_info "Zsh setup complete!"
log_info "Run the main install script to symlink your zsh configs"
log_info ""
log_info "To set zsh as your default shell:"
log_info "chsh -s \$(which zsh)"