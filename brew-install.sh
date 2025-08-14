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

# Check if Homebrew is installed
if ! command -v brew >/dev/null 2>&1; then
    log_error "Homebrew is not installed!"
    log_info "Install Homebrew first:"
    echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi

# Check if Brewfile exists
if [ ! -f "$DOTFILES_DIR/Brewfile" ]; then
    log_error "Brewfile not found in $DOTFILES_DIR"
    exit 1
fi

log_info "Installing Homebrew packages from Brewfile..."
log_info "This may take a while depending on your internet connection and the number of packages."

cd "$DOTFILES_DIR"

# Install packages from Brewfile
if brew bundle install; then
    log_info "✅ All Homebrew packages installed successfully!"
else
    log_warn "Some packages may have failed to install. Check the output above."
fi

log_info "To update your Brewfile after installing new packages:"
log_info "brew bundle dump --describe --force"