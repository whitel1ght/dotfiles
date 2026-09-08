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
    # --keep-zshrc is load-bearing. --unattended sets OVERWRITE_CONFIRMATION=no,
    # and KEEP_ZSHRC defaults to no, so without it the installer moves ~/.zshrc
    # to ~/.zshrc.pre-oh-my-zsh and writes its own template — without asking,
    # and explicitly including the case where ~/.zshrc is a symlink. Running
    # install.sh first and this second would silently undo every zsh symlink.
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" \
        --unattended --keep-zshrc
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

# Plugins .zshrc requires. zsh-autosuggestions is named in the plugins array and
# zsh-syntax-highlighting is sourced by path at the end of .zshrc, so a machine
# without them gets "plugin not found" and a source error on every shell start.
for plugin_spec in \
    "zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git" \
    "zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git"
do
    plugin_name="${plugin_spec%% *}"
    plugin_url="${plugin_spec#* }"
    plugin_dir="$HOME/.oh-my-zsh/custom/plugins/$plugin_name"
    if [ ! -d "$plugin_dir" ]; then
        log_info "Installing $plugin_name..."
        git clone --depth=1 "$plugin_url" "$plugin_dir"
        log_info "✅ $plugin_name installed"
    else
        log_info "$plugin_name already installed"
    fi
done

# Install fzf-tab. It must live under custom/plugins because .zshrc loads it
# through the oh-my-zsh plugins array, which is what puts it after compinit and
# ahead of zsh-autosuggestions.
if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/fzf-tab" ]; then
    log_info "Installing fzf-tab..."
    git clone --depth=1 https://github.com/Aloxaf/fzf-tab.git "$HOME/.oh-my-zsh/custom/plugins/fzf-tab"
    log_info "✅ fzf-tab installed"
else
    log_info "fzf-tab already installed"
fi

# Generate completions for tools that ship a generator rather than a static
# _file. fzf-tab renders whatever zsh's completion system knows, so without
# these `kubectl <TAB>` and `docker <TAB>` produce nothing. They are generated
# rather than committed: the output is tied to the installed binary version.
COMPDIR="$HOME/.oh-my-zsh/cache/completions"   # already on fpath via oh-my-zsh
mkdir -p "$COMPDIR"
for tool in kubectl docker; do
    if command -v "$tool" >/dev/null 2>&1; then
        "$tool" completion zsh > "$COMPDIR/_$tool"
        # Cobra completions ask the running server for candidate names. kubectl
        # against an unreachable cluster does not give up: measured still
        # running after 90s, which freezes the shell on TAB whenever the proxy
        # is routing direct. Cap that call — see deadline() in .zshenv.
        sed -i '' \
          's|out=$(eval ${requestComp} 2>/dev/null)|out=$(eval "deadline 5 ${requestComp}" 2>/dev/null)|' \
          "$COMPDIR/_$tool"
        log_info "✅ generated $tool completion"
    else
        log_warn "$tool not installed, skipping its completion"
    fi
done
# compinit caches what it found; drop the dump so the new files are picked up.
rm -f "$HOME/.zcompdump"*

log_info "Zsh setup complete!"
log_info "Run ./install.sh to symlink the zsh configs (safe in either order)"
log_info ""
log_info "To set zsh as your default shell:"
log_info "chsh -s \$(which zsh)"