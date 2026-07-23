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

# Link each entry of a directory individually, rather than the directory itself.
# Used for ~/.claude/{skills,agents}, which may be owned by another repo
# (claude-components symlinks those whole directories to itself). Linking
# per-item lets personal and work components share one directory.
link_dir_contents() {
    local source_dir="$1"
    local target_dir="$2"

    [ -d "$source_dir" ] || return 0

    # If the target is a symlink to another repo, resolve it so our links land
    # in the real directory rather than being created relative to the link.
    if [ -L "$target_dir" ]; then
        local resolved
        resolved="$(cd "$target_dir" 2>/dev/null && pwd -P)" || {
            log_error "Broken symlink at $target_dir — skipping"
            return 1
        }
        log_warn "$target_dir is a symlink (owned by another repo); linking into $resolved"
        target_dir="$resolved"
    fi

    mkdir -p "$target_dir"

    local entry name target
    for entry in "$source_dir"/*; do
        [ -e "$entry" ] || continue
        name="$(basename "$entry")"
        [ "$name" = ".gitkeep" ] && continue
        target="$target_dir/$name"

        if [ -L "$target" ]; then
            if [ "$(readlink "$target")" = "$entry" ]; then
                log_info "Already linked: $target"
            else
                log_warn "Re-linking $target (pointed to $(readlink "$target"))"
                rm "$target"
                ln -s "$entry" "$target"
                log_info "Created symlink: $target -> $entry"
            fi
            continue
        fi

        if [ -e "$target" ]; then
            log_warn "File/directory exists at $target, backing up to ${target}.backup"
            mv "$target" "${target}.backup"
        fi

        ln -s "$entry" "$target"
        log_info "Created symlink: $target -> $entry"
    done
}

# tmux configuration
if [ -f "$DOTFILES_DIR/tmux/.tmux.conf" ]; then
    create_symlink "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
fi

# tmux helper scripts (referenced from .tmux.conf as ~/.tmux.conf.d/<name>)
if [ -f "$DOTFILES_DIR/tmux/claude-busy.sh" ]; then
    create_symlink "$DOTFILES_DIR/tmux/claude-busy.sh" "$HOME/.tmux.conf.d/claude-busy.sh"
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

if [ -f "$DOTFILES_DIR/zsh/.zshenv" ]; then
    create_symlink "$DOTFILES_DIR/zsh/.zshenv" "$HOME/.zshenv"
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

# Keep a host repo's .git/info/exclude in sync with our personal component names,
# so symlinks we place inside its working tree don't show up as untracked files.
# Local-only (not committed), and rewritten in place on each run.
sync_git_exclude() {
    local host_repo="$1"
    local subdir="$2"
    local source_dir="$3"

    [ -d "$host_repo/.git" ] || return 0
    [ -d "$source_dir" ] || return 0

    local exclude_file="$host_repo/.git/info/exclude"
    local begin="# >>> dotfiles personal claude components >>>"
    local end="# <<< dotfiles personal claude components <<<"

    mkdir -p "$(dirname "$exclude_file")"
    touch "$exclude_file"

    # Drop any previous block, then append a freshly generated one.
    local tmp
    tmp="$(mktemp)"
    awk -v b="$begin" -v e="$end" '
        $0 == b { skip = 1 }
        !skip   { print }
        $0 == e { skip = 0 }
    ' "$exclude_file" > "$tmp"

    {
        echo "$begin"
        echo "# Managed by ~/projects/dotfiles/install.sh — do not edit by hand."
        echo "# Personal skills/agents symlinked in from ~/projects/dotfiles/claude/."
        local entry name
        for entry in "$source_dir"/*; do
            [ -e "$entry" ] || continue
            name="$(basename "$entry")"
            [ "$name" = ".gitkeep" ] && continue
            echo "/$subdir/$name"
        done
        echo "$end"
    } >> "$tmp"

    mv "$tmp" "$exclude_file"
    log_info "Synced personal component names into $exclude_file"
}

# Claude Code configuration
# skills/ and agents/ are linked per-item so they coexist with work components
# from claude-components, which symlinks those whole directories to itself.
if [ -d "$DOTFILES_DIR/claude/skills" ]; then
    link_dir_contents "$DOTFILES_DIR/claude/skills" "$HOME/.claude/skills"
fi

if [ -d "$DOTFILES_DIR/claude/agents" ]; then
    link_dir_contents "$DOTFILES_DIR/claude/agents" "$HOME/.claude/agents"
fi

# If claude-components is checked out, keep its local exclude list current so
# our symlinks inside its skills/ and agents/ dirs stay out of its git status.
CLAUDE_COMPONENTS_DIR="${CLAUDE_COMPONENTS_DIR:-$HOME/projects/claude-components}"
if [ -d "$CLAUDE_COMPONENTS_DIR/.git" ]; then
    sync_git_exclude "$CLAUDE_COMPONENTS_DIR" "skills" "$DOTFILES_DIR/claude/skills"
fi

if [ -f "$DOTFILES_DIR/claude/CLAUDE.md" ]; then
    create_symlink "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
fi

if [ -f "$DOTFILES_DIR/claude/settings.json" ]; then
    create_symlink "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
fi

# Optional: Install Homebrew packages
log_info "To install Homebrew packages, run: ./brew-install.sh"

log_info "Dotfiles installation complete!"
log_info "You may need to restart applications to pick up the new configurations."