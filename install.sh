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

# Machine-local config files: private values, per-machine paths, credentials.
# They live outside this repo by design and so do not arrive with a clone.
#
# Every consumer of these reads them behind a [ -f ] guard, which means an
# absent file is SILENT. That is how a fresh machine ends up with no git
# identity, no Jira token and no wiki-sync host while every script reports
# success. Seeding a stub from the committed template makes the gap visible.
#
# Each *.example is written to be inert when copied verbatim — its assignments
# are commented out — so seeding can never introduce a placeholder that looks
# like a real value. A bogus value is worse than none: bin/notes prints a
# precise "unset: NOTES_USER" when the variable is absent, but resolves
# "your.server.ip.here" and fails at DNS when it is set to a placeholder.
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

# Superfile configuration
# Config and runtime state (logs, pinned.json, bundled themes) share one
# directory, so link the two config files rather than the directory itself.
SUPERFILE_DIR="$HOME/Library/Application Support/superfile"

if [ -f "$DOTFILES_DIR/superfile/config.toml" ]; then
    create_symlink "$DOTFILES_DIR/superfile/config.toml" "$SUPERFILE_DIR/config.toml"
fi

if [ -f "$DOTFILES_DIR/superfile/hotkeys.toml" ]; then
    create_symlink "$DOTFILES_DIR/superfile/hotkeys.toml" "$SUPERFILE_DIR/hotkeys.toml"
fi

# Repy ebook reader
# Only configuration.json is linked: repy keeps its library and reading
# positions in its own state files, which are machine-local. Same split as
# superfile. The link must also be in place before repy is first launched —
# repy writes a full default config when the file is absent, which would leave
# a real file where the symlink belongs.
if [ -f "$DOTFILES_DIR/repy/configuration.json" ]; then
    create_symlink "$DOTFILES_DIR/repy/configuration.json" "$HOME/.config/repy/configuration.json"
fi

# Newsboat configuration
# Only the config file is linked. The urls file is generated by
# bin/newsboat-urls from feeds.txt + subreddits.txt, so linking it would make a
# generated file look editable.
if [ -f "$DOTFILES_DIR/newsboat/config" ]; then
    create_symlink "$DOTFILES_DIR/newsboat/config" "$HOME/.config/newsboat/config"
fi

# Reddittui configuration
# Only the toml is linked. reddittui writes its cache to ~/.cache/reddittui and
# its log to ~/.local/state, so nothing else in this directory is machine-local.
if [ -f "$DOTFILES_DIR/reddittui/reddittui.toml" ]; then
    create_symlink "$DOTFILES_DIR/reddittui/reddittui.toml" \
        "$HOME/.config/reddittui/reddittui.toml"
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

# Sourced at the end of .zshrc behind [ -f ]. Holds the wiki-sync server that
# bin/notes needs; without it `notes pull` stops with "unset: NOTES_USER ...".
seed_local_config "$DOTFILES_DIR/zsh/.zshrc.local.example" \
    "$HOME/.zshrc.local" 600 "wiki sync host for bin/notes (pull_notes/push_notes)"

# Sourced by .zshenv for EVERY zsh invocation, so these reach non-interactive
# shells and tool subprocesses. Without them mrglass shows no ticket detail and
# the handle-ticket skill gets 401 from the Jira REST API.
seed_local_config "$DOTFILES_DIR/mrglass/secrets.env.example" \
    "$HOME/.config/mrglass/secrets.env" 600 "JIRA_EMAIL + JIRA_API_TOKEN for mrglass"

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

# ~/.gitconfig ends with an [include] of this path. git skips a missing include
# without a word, then falls back to username@hostname for authorship — which
# writes commits as e.g. "dmitry@192.168.2.97" and only warns.
seed_local_config "$DOTFILES_DIR/git/.gitconfig.local.example" \
    "$HOME/.gitconfig.local" 644 "set user.name and user.email before committing"

# Keep a host repo's .git/info/exclude in sync with our personal component names,
# so symlinks we place inside its working tree don't show up as untracked files.
# Local-only (not committed), and rewritten in place on each run.
sync_git_exclude() {
    local host_repo="$1"
    local subdir="$2"
    local source_dir="$3"
    local mode="${4:-replace}"

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
    if [ "$mode" = "append" ]; then
        # Keep the existing block; strip only its terminator so we can extend it.
        # -xF: the marker contains regex-significant characters.
        # `|| :`: with no prior block grep matches nothing and exits 1, which
        # would abort install.sh under `set -e` before the remaining links run.
        grep -vxF "$end" "$exclude_file" > "$tmp" || :
    else
        awk -v b="$begin" -v e="$end" '
            $0 == b { skip = 1 }
            !skip   { print }
            $0 == e { skip = 0 }
        ' "$exclude_file" > "$tmp"
    fi

    {
        if [ "$mode" != "append" ]; then
            echo "$begin"
            echo "# Managed by ~/projects/dotfiles/install.sh — do not edit by hand."
            echo "# Personal skills/agents symlinked in from ~/projects/dotfiles/claude/."
        fi
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

# Refresh vendored third-party skills, then link each wrapper. Each wrapper is a
# skills-dir plugin, so its skills are namespaced and cannot collide with the
# bare names in claude/skills/. Guarded because install.sh runs under `set -e`:
# a failed sync must fall back to the committed copies, not abort the install.
if [ "${SKILLS_SYNC:-1}" != "0" ] && [ -x "$DOTFILES_DIR/claude/vendor-sync.sh" ]; then
    "$DOTFILES_DIR/claude/vendor-sync.sh" || log_warn "Vendor sync failed — using committed copies"
    if command -v claude >/dev/null 2>&1; then
        claude plugin marketplace update || log_warn "Marketplace update failed"
    fi
fi

if [ -d "$DOTFILES_DIR/claude/vendor" ]; then
    link_dir_contents "$DOTFILES_DIR/claude/vendor" "$HOME/.claude/skills"
fi

# If claude-components is checked out, keep its local exclude list current so
# our symlinks inside its skills/ and agents/ dirs stay out of its git status.
CLAUDE_COMPONENTS_DIR="${CLAUDE_COMPONENTS_DIR:-$HOME/projects/claude-components}"
if [ -d "$CLAUDE_COMPONENTS_DIR/.git" ]; then
    sync_git_exclude "$CLAUDE_COMPONENTS_DIR" "skills" "$DOTFILES_DIR/claude/skills"
    sync_git_exclude "$CLAUDE_COMPONENTS_DIR" "skills" "$DOTFILES_DIR/claude/vendor" append
fi

if [ -f "$DOTFILES_DIR/claude/CLAUDE.md" ]; then
    create_symlink "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
fi


# macdict backs repy's "Define Word"; reaches the macOS dictionaries via ctypes,
# so it needs no venv or third-party package.
if [ -f "$DOTFILES_DIR/bin/macdict" ]; then
    create_symlink "$DOTFILES_DIR/bin/macdict" "$HOME/.local/bin/macdict"
fi

# vault-check warns from .zshrc when the machine-rebuild vault is behind the
# files it mirrors. It reads the managed-file list from ~/wiki/vault-lib.sh and
# is a silent no-op without it, so a machine with no wiki never sees it.
if [ -f "$DOTFILES_DIR/bin/vault-check" ]; then
    create_symlink "$DOTFILES_DIR/bin/vault-check" "$HOME/.local/bin/vault-check"
fi

# notes syncs ~/wiki with the server; pull_notes / push_notes in .zshrc call it.
# Server details come from ~/.zshrc.local, never from this repo.
if [ -f "$DOTFILES_DIR/bin/notes" ]; then
    create_symlink "$DOTFILES_DIR/bin/notes" "$HOME/.local/bin/notes"
fi

# tmux-prune closes idle tmux windows; bound to prefix+X in tmux/.tmux.conf.
if [ -f "$DOTFILES_DIR/bin/tmux-prune" ]; then
    create_symlink "$DOTFILES_DIR/bin/tmux-prune" "$HOME/.local/bin/tmux-prune"
fi

# Install TPM and the plugins tmux/.tmux.conf declares. Nothing else did this:
# the config ends in `run '~/.tmux/plugins/tpm/tpm'`, which is silent when the
# path does not exist, so on a fresh machine every plugin binding — fuzzmux's
# prefix s/w/f, the Claude pickers on j/a/o, resurrect and continuum — was
# simply absent with no error anywhere. Guarded like the steps below: a network
# failure must not abort the rest. Set TMUX_SETUP=0 to skip.
setup_tmux_plugins() {
    local tpm="$HOME/.tmux/plugins/tpm"

    if [ ! -d "$tpm" ]; then
        git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm" || return 1
        log_info "Installed TPM"
    fi

    # install_plugins reads TMUX_PLUGIN_MANAGER_PATH, which only exists once the
    # config has been sourced by a running server. A server started before TPM
    # was cloned never ran the `run` line, so re-source before installing.
    if tmux info >/dev/null 2>&1; then
        tmux source-file "$HOME/.tmux.conf" 2>/dev/null || true
    fi

    "$tpm/bin/install_plugins" >/dev/null 2>&1 || return 1
    log_info "tmux plugins installed"

    tmux info >/dev/null 2>&1 && tmux source-file "$HOME/.tmux.conf" 2>/dev/null || true
}

if [ "${TMUX_SETUP:-1}" != "0" ] && command -v tmux >/dev/null 2>&1; then
    setup_tmux_plugins || log_warn "tmux plugin setup failed — run tmux and press prefix+I"
fi


# Install reddittui from its checksum-verified release binary. Guarded the same
# way: a network failure here must not abort the remaining setup. Set
# REDDITTUI_SETUP=0 to skip.
if [ "${REDDITTUI_SETUP:-1}" != "0" ] && [ -x "$DOTFILES_DIR/reddittui-setup.sh" ]; then
    "$DOTFILES_DIR/reddittui-setup.sh" install || log_warn "reddittui setup failed"
fi

# Start the self-hosted Redlib that reddittui reads reddit through. Guarded the
# same way, and it fails loudly but harmlessly on a machine with no Docker
# running — reddittui is simply unusable until it is up. Set REDLIB_SETUP=0 to
# skip.
if [ "${REDLIB_SETUP:-1}" != "0" ] && [ -x "$DOTFILES_DIR/redlib-setup.sh" ]; then
    "$DOTFILES_DIR/redlib-setup.sh" up || log_warn "redlib setup failed"
fi


# Disable the macOS media analysis daemons. Guarded like the vendor sync above:
# install.sh runs under `set -e`, and a launchctl failure must not abort the
# remaining setup. Set MACOS_DAEMONS=0 to keep stock macOS behaviour.
if [ "${MACOS_DAEMONS:-1}" != "0" ] && [ -x "$DOTFILES_DIR/macos-daemons.sh" ]; then
    "$DOTFILES_DIR/macos-daemons.sh" disable || log_warn "Daemon disable failed"
fi

# Remap Caps Lock to backtick, restoring the tmux prefix to the position it had
# on the previous (ISO) keyboard. Guarded like the daemon toggle above:
# install.sh runs under `set -e`, and a hidutil failure must not abort the
# remaining setup. Set KEYBOARD_SETUP=0 to keep stock Caps Lock.
if [ "${KEYBOARD_SETUP:-1}" != "0" ] && [ -x "$DOTFILES_DIR/keyboard-setup.sh" ]; then
    "$DOTFILES_DIR/keyboard-setup.sh" apply || log_warn "Keyboard remap failed"
fi

# --- Proxy routing (sing-box TUN) -----------------------------------------
# All routing rules live in proxy/proxy-domains.txt; secrets stay in
# ~/.config/sing-box/secrets.env and never enter this repo. Guarded like the
# vendor sync above: install.sh runs under `set -e`, and an unconfigured proxy
# must not abort the remaining setup. Set PROXY_SETUP=0 to skip.
setup_proxy() {
    local secrets="$HOME/.config/sing-box/secrets.env"
    local plist="/Library/LaunchDaemons/local.singbox.plist"

    create_symlink "$DOTFILES_DIR/bin/proxyctl" "$HOME/.local/bin/proxyctl"

    if ! command -v sing-box >/dev/null 2>&1; then
        log_warn "sing-box not installed - run: brew install sing-box"
        return 0
    fi

    if [ ! -f "$secrets" ]; then
        seed_local_config "$DOTFILES_DIR/proxy/secrets.env.example" \
            "$secrets" 600 "six VLESS values, then: proxyctl on"
        return 0
    fi

    if [ ! -f "$plist" ]; then
        log_warn "LaunchDaemon not installed yet. Run:"
        log_warn "  sudo install -m 644 -o root -g wheel \\"
        log_warn "    $DOTFILES_DIR/proxy/local.singbox.plist $plist"
        log_warn "  then: proxyctl on"
        return 0
    fi

    log_info "Proxy configured - run 'proxyctl status' to check"
}

if [ "${PROXY_SETUP:-1}" != "0" ]; then
    setup_proxy || log_warn "Proxy setup incomplete"
fi

# --- ECFX tooling (private repo) -------------------------------------------
# The ecfx-* helper scripts live in a separate private repo because they carry
# employer infrastructure detail that does not belong in a public one. Guarded
# like the proxy setup above: install.sh runs under `set -e`, and an absent
# repo (a machine that does no ECFX work) must not abort the remaining setup.
# Set ECFX_TOOLING=0 to skip.
setup_ecfx_tooling() {
    local tooling="$HOME/projects/ecfx-tooling"

    if [ ! -d "$tooling/bin" ]; then
        log_warn "ecfx-tooling not present - skipping. To set it up:"
        log_warn "  git clone git@github.com:whitel1ght/ecfx-tooling.git $tooling"
        log_warn "  then re-run this script"
        return 0
    fi

    local script
    for script in "$tooling"/bin/*; do
        [ -f "$script" ] || continue
        create_symlink "$script" "$HOME/.local/bin/$(basename "$script")"
    done
}

if [ "${ECFX_TOOLING:-1}" != "0" ]; then
    setup_ecfx_tooling || log_warn "ECFX tooling setup incomplete"
fi

# Install oh-my-zsh, powerlevel10k and the three plugins .zshrc names. This is
# not optional in practice: without them a new machine gets "plugin not found"
# from oh-my-zsh and a prompt that falls back to the p10k wizard. Guarded like
# the tooling above — install.sh runs under `set -e` and a network failure here
# must not abort the rest. Set ZSH_SETUP=0 to skip. Safe to re-run, and safe in
# either order relative to the symlinks above thanks to --keep-zshrc.
if [ "${ZSH_SETUP:-1}" != "0" ] && [ -x "$DOTFILES_DIR/zsh-setup.sh" ]; then
    "$DOTFILES_DIR/zsh-setup.sh" || log_warn "zsh setup failed"
fi

# Optional: Install Homebrew packages
log_info "To install Homebrew packages, run: ./brew-install.sh"

# Say plainly what still needs a human. These were all silent failures before:
# the file is created and readable, so every [ -f ] guard downstream passes,
# and the missing VALUE only surfaces much later as a 401 or a DNS error.
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