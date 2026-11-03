#!/usr/bin/env bash
# Link Ubuntu dotfiles, seed machine-local config templates, and seed the
# per-host Pi settings file. Package installation, system services, keyboard
# remapping, and authentication are separate, explicit operations; this script
# never enables the proxy.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info() { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

DRY_RUN="${DRY_RUN:-0}"
LINKS_ONLY="${DOTFILES_LINKS_ONLY:-0}"
SEEDED_CONFIGS=()

unique_backup() {
    local path="$1" backup="${1}.backup" n=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
        backup="${1}.backup.$n"
        n=$((n + 1))
    done
    printf '%s\n' "$backup"
}

resolved_path() {
    readlink -m -- "$1" 2>/dev/null || printf '%s\n' "$1"
}

is_managed_dotfiles_path() {
    case "$1" in
        "$DOTFILES_DIR"/i3/*|"$DOTFILES_DIR"/ghostty/*|"$DOTFILES_DIR"/tmux/*|\
        "$DOTFILES_DIR"/nvim/*|"$DOTFILES_DIR"/zsh/*|"$DOTFILES_DIR"/git/*|\
        "$DOTFILES_DIR"/bin/*|"$DOTFILES_DIR"/claude/*|"$DOTFILES_DIR"/pi/*|\
        "$DOTFILES_DIR"/superfile/*|"$DOTFILES_DIR"/newsboat/*|\
        "$DOTFILES_DIR"/mrglass/*|"$DOTFILES_DIR"/repy/*|"$DOTFILES_DIR"/proxy/*|\
        "$DOTFILES_DIR"/keyboard/*|"$DOTFILES_DIR"/ollama/*)
            return 0 ;;
        *) return 1 ;;
    esac
}

create_symlink() {
    local source="$1" target="$2" source_real target_real old_real backup
    source_real="$(resolved_path "$source")"

    if [ -L "$target" ]; then
        old_real="$(resolved_path "$target")"
        if [ "$old_real" = "$source_real" ]; then
            log_info "Already linked: $target"
            return 0
        fi
        if is_managed_dotfiles_path "$old_real"; then
            if [ "$DRY_RUN" = 1 ]; then
                log_info "Would repair dotfiles link: $target -> $source"
                return 0
            fi
            rm -- "$target"
        else
            log_warn "Leaving foreign symlink untouched: $target -> $(readlink "$target")"
            return 0
        fi
    elif [ -e "$target" ]; then
        backup="$(unique_backup "$target")"
        if [ "$DRY_RUN" = 1 ]; then
            log_info "Would back up $target to $backup and link it to $source"
            return 0
        fi
        mkdir -p "$(dirname "$target")"
        mv -- "$target" "$backup"
        log_warn "Backed up $target to $backup"
    elif [ "$DRY_RUN" = 1 ]; then
        log_info "Would link $target -> $source"
        return 0
    fi

    mkdir -p "$(dirname "$target")"
    ln -s -- "$source" "$target"
    log_info "Created symlink: $target -> $source"
}

link_dir_contents() {
    local source_dir="$1" target_dir="$2" resolved entry name
    [ -d "$source_dir" ] || return 0

    if [ -L "$target_dir" ]; then
        resolved="$(cd "$target_dir" 2>/dev/null && pwd -P)" || {
            log_warn "Leaving broken directory symlink untouched: $target_dir"
            return 0
        }
        target_dir="$resolved"
    fi
    [ "$DRY_RUN" = 1 ] || mkdir -p "$target_dir"

    for entry in "$source_dir"/*; do
        [ -e "$entry" ] || continue
        name="$(basename "$entry")"
        [ "$name" = .gitkeep ] && continue
        create_symlink "$entry" "$target_dir/$name"
    done
}

seed_local_config() {
    local example="$1" target="$2" mode="${3:-600}" hint="${4:-}"
    if [ ! -f "$example" ]; then
        log_warn "Missing template: $example"
        return 0
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        log_info "Would seed $target from $(basename "$example")"
        return 0
    fi
    mkdir -p "$(dirname "$target")"
    (umask 077; cp -- "$example" "$target")
    chmod "$mode" "$target"
    log_info "Created $target from $(basename "$example")"
    SEEDED_CONFIGS+=("$target${hint:+  ->  $hint}")
}

ensure_command_compat() {
    local target_name="$1" alternate="$2" target="$HOME/.local/bin/$1" source
    command -v "$target_name" >/dev/null 2>&1 && return 0
    source="$(command -v "$alternate" 2>/dev/null || true)"
    [ -n "$source" ] || return 0
    if [ -e "$target" ] || [ -L "$target" ]; then
        log_warn "Cannot create $target -> $alternate: target already exists"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        log_info "Would create compatibility link $target -> $source"
        return 0
    fi
    mkdir -p "$(dirname "$target")"
    ln -s -- "$source" "$target"
    log_info "Created compatibility command: $target -> $source"
}

link_command() {
    local name="$1"
    [ -f "$DOTFILES_DIR/bin/$name" ] || return 0
    create_symlink "$DOTFILES_DIR/bin/$name" "$HOME/.local/bin/$name"
}

# Core dotfiles. i3 is retained for this Ubuntu host; no AeroSpace or macOS
# launch services are installed by this script.
create_symlink "$DOTFILES_DIR/i3/config" "$XDG_CONFIG_HOME/i3/config"
create_symlink "$DOTFILES_DIR/i3/scripts" "$XDG_CONFIG_HOME/i3/scripts"
create_symlink "$DOTFILES_DIR/ghostty/config" "$XDG_CONFIG_HOME/ghostty/config"
create_symlink "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
create_symlink "$DOTFILES_DIR/nvim" "$XDG_CONFIG_HOME/nvim"

for name in .zshrc .zprofile .zshenv .p10k.zsh; do
    [ -f "$DOTFILES_DIR/zsh/$name" ] || continue
    case "$name" in .p10k.zsh) target="$HOME/.p10k.zsh" ;; *) target="$HOME/$name" ;; esac
    create_symlink "$DOTFILES_DIR/zsh/$name" "$target"
done

create_symlink "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
create_symlink "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
create_symlink "$DOTFILES_DIR/git/config/git/ignore" "$XDG_CONFIG_HOME/git/ignore"

# Portable command links. Do not link tests, macOS-only helpers, or the proxy
# script indirectly: the Ubuntu branch's bin/proxyctl is deliberately retained.
[ "$DRY_RUN" = 1 ] || mkdir -p "$HOME/.local/bin"
for name in art cards changes-since clean-worktrees clipboard-copy coach-fix coach-mine cs cs-add \
    daily-stats day-note day-plan day-status decide decisions dev diary-links \
    drills docs-check ecfx-daily-commits ecfx-docker end-day friction friction-cards friction-ledger \
    friction-mine frictions ideas jira-api jira-issue jt mr-ship mr-watch \
    newsboat-urls notes open-path opencode-console-auth pi-autoupdate pi-contract \
    pi-parity plink repos-sync run-day-inbox-answer session-picker start-day sync-tickets system-check \
    team-plugins-sync tmux-prune vault-check wiki-commit wiki-sync words wt proxyctl; do
    link_command "$name"
done
ensure_command_compat fd fdfind
ensure_command_compat bat batcat

# Pi owns auth, sessions, package state and the rest of ~/.pi/agent. Link only
# managed configuration items through plink.
#
# settings.json is the exception: Pi rewrites per-host state into it (changelog
# markers, device identity), so it is seeded as a regular file rather than
# linked. Seeding never overwrites an existing file or symlink; bin/plink
# converts an owned legacy link into a per-host copy instead of re-linking it.
seed_local_config "$DOTFILES_DIR/pi/settings.json" \
    "$HOME/.pi/agent/settings.json" 664 'per-host Pi defaults; Pi writes changelog markers here'

if [ -f "$DOTFILES_DIR/bin/plink" ]; then
    if [ "$DRY_RUN" = 1 ]; then
        log_info "Would link Pi configuration with bin/plink"
    else
        DOTFILES_DIR="$DOTFILES_DIR" bash "$DOTFILES_DIR/bin/plink"
    fi
fi

# Claude instructions and invoke-only commands are linked individually; skills
# are installed through the local marketplace, not injected globally.
create_symlink "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
link_dir_contents "$DOTFILES_DIR/claude/commands" "$HOME/.claude/commands"

# Optional active Claude worktree hooks. Existing hooks are merged, not replaced.
install_claude_hooks() {
    local settings="$HOME/.claude/settings.json" tmp create remove backup
    command -v jq >/dev/null 2>&1 || { log_warn 'jq missing; cannot configure Claude hooks'; return 0; }
    create="$HOME/.local/bin/wt hook-create"
    remove="$HOME/.local/bin/wt hook-remove"
    mkdir -p "$(dirname "$settings")"
    if [ -L "$settings" ]; then
        log_warn "Leaving symlinked Claude settings untouched: $settings"
        return 0
    fi
    [ -f "$settings" ] || printf '{}\n' > "$settings"
    tmp="$(mktemp "${settings}.XXXXXX")"
    if ! jq --arg create "$create" --arg remove "$remove" '
        def ensure_hook($key; $command):
          .hooks[$key] = ((.hooks[$key] // []) + [{hooks:[{type:"command", command:$command}]}]
            | unique_by(tojson));
        .hooks = (.hooks // {})
        | ensure_hook("WorktreeCreate"; $create)
        | ensure_hook("WorktreeRemove"; $remove)
    ' "$settings" > "$tmp"; then
        rm -f "$tmp"
        log_warn "Could not parse $settings; leaving it untouched"
        return 0
    fi
    if cmp -s "$tmp" "$settings"; then
        rm -f "$tmp"
        return 0
    fi
    backup="$(unique_backup "$settings")"
    cp -a -- "$settings" "$backup"
    chmod --reference="$settings" "$tmp"
    mv -f -- "$tmp" "$settings"
    log_info "Merged dotfiles worktree hooks into $settings (backup: $backup)"
}

if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${CLAUDE_HOOKS:-0}" = 1 ]; then
    install_claude_hooks
fi

# Never perform a vendor fetch or modify Claude's registered marketplaces unless
# specifically requested. Offline generation uses already committed sources.
if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${SKILLS_SYNC:-0}" = 1 ]; then
    "$DOTFILES_DIR/claude/vendor-sync.sh" || log_warn 'Claude vendor refresh failed; committed vendored files remain available'
elif [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${CLAUDE_MARKETPLACE:-0}" = 1 ]; then
    "$DOTFILES_DIR/claude/vendor-sync.sh" --offline || log_warn 'Could not build the local Claude marketplace wrapper'
fi
if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${CLAUDE_MARKETPLACE:-0}" = 1 ]; then
    if command -v claude >/dev/null 2>&1; then
        claude plugin marketplace add "$DOTFILES_DIR/claude" \
            || claude plugin marketplace update dmitry-dotfiles \
            || log_warn 'Could not register the dotfiles marketplace'
    else
        log_warn 'CLAUDE_MARKETPLACE=1 requested but Claude Code is not installed'
    fi
fi

# Optional terminal application configs use XDG paths. Repy can select its data
# prefix based on whether ~/.config/repy exists, so don't hide an older library.
create_symlink "$DOTFILES_DIR/superfile/config.toml" "$XDG_CONFIG_HOME/superfile/config.toml"
create_symlink "$DOTFILES_DIR/superfile/hotkeys.toml" "$XDG_CONFIG_HOME/superfile/hotkeys.toml"
create_symlink "$DOTFILES_DIR/newsboat/config" "$XDG_CONFIG_HOME/newsboat/config"
create_symlink "$DOTFILES_DIR/mrglass/config.yaml" "$XDG_CONFIG_HOME/mrglass/config.yaml"

if [ -f "$HOME/.repy/states.db" ] && [ ! -d "$XDG_CONFIG_HOME/repy" ]; then
    log_warn "Found legacy ~/.repy/states.db; not creating ~/.config/repy until its library/state is migrated. See README."
else
    create_symlink "$DOTFILES_DIR/repy/configuration.json" "$XDG_CONFIG_HOME/repy/configuration.json"
fi

# Seed only inert, commented templates. Never overwrite an existing file or
# dangling symlink containing machine-local data.
seed_local_config "$DOTFILES_DIR/zsh/.zshrc.local.example" \
    "$HOME/.zshrc.local" 600 'wiki sync settings and optional environment variables'
seed_local_config "$DOTFILES_DIR/git/.gitconfig.local.example" \
    "$HOME/.gitconfig.local" 644 'set Git name/email before committing'
seed_local_config "$DOTFILES_DIR/mrglass/secrets.env.example" \
    "$XDG_CONFIG_HOME/mrglass/secrets.env" 600 'JIRA_EMAIL and JIRA_API_TOKEN'
seed_local_config "$DOTFILES_DIR/proxy/secrets.env.example" \
    "$XDG_CONFIG_HOME/sing-box/secrets.env" 600 'VLESS values; proxy remains stopped'

# Proxy setup is deliberately limited to linking and seeding. The systemd unit
# is already part of the Ubuntu branch and is never installed/enabled here.
if [ "${PROXY_SETUP:-1}" != 0 ]; then
    if command -v sing-box >/dev/null 2>&1; then
        log_info "sing-box detected. Review proxy/README.md; enable the systemd unit separately when ready."
    else
        log_warn 'sing-box is not installed; proxyctl is linked but the tunnel is inactive'
    fi
fi

# Optional network/application setup. Defaults are non-invasive.
if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${ZSH_SETUP:-0}" = 1 ]; then
    "$DOTFILES_DIR/zsh-setup.sh" || log_warn 'Zsh plugin setup failed; config links remain installed'
fi
if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${TMUX_SETUP:-0}" = 1 ]; then
    tpm="$HOME/.tmux/plugins/tpm"
    if [ ! -d "$tpm" ]; then
        git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm" \
            || log_warn 'Could not clone TPM; install plugins manually with prefix+I'
    fi
    log_info 'TPM is staged. Install plugins in a separate tmux server with prefix+I; no live tmux server was reconfigured.'
fi
if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${REPY_SETUP:-0}" = 1 ]; then
    if command -v cargo >/dev/null 2>&1; then
        cargo install --locked --git https://github.com/newptcai/repy --tag v0.25.0 \
            || log_warn 'repy installation failed'
    else
        log_warn 'cargo missing; install Rust/Cargo first to build repy'
    fi
fi
if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${SDKMAN_SETUP:-0}" = 1 ] && [ ! -d "$HOME/.sdkman" ]; then
    curl -fsSL 'https://get.sdkman.io?rcupdate=false' | bash \
        || log_warn 'SDKMAN installation failed'
fi
if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${OLLAMA_SETUP:-0}" = 1 ]; then
    log_warn 'OLLAMA_SETUP only builds an already-downloaded compatible model; inspect the Modelfile and hardware before running it.'
    if command -v ollama >/dev/null 2>&1 && ollama list >/dev/null 2>&1; then
        for modelfile in "$DOTFILES_DIR"/ollama/*.Modelfile; do
            [ -f "$modelfile" ] || continue
            name="$(sed -n 's/^# name: *//p' "$modelfile" | head -n1)"
            base="$(sed -n 's/^FROM *//p' "$modelfile" | head -n1)"
            [ -n "$name" ] && [ -n "$base" ] || { log_warn "Invalid Modelfile: $modelfile"; continue; }
            if ollama show "$base" >/dev/null 2>&1; then
                ollama create "$name" -f "$modelfile" || log_warn "Could not build $name"
            else
                log_warn "$name skipped; pull base model $base manually if desired"
            fi
        done
    else
        log_warn 'Ollama is missing or not running; no model was downloaded or started'
    fi
fi

# The key remap is required for final parity but remains an explicit system-level
# action. It needs a verified laptop keyboard ID and must never run in links-only
# or test installations.
if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${KEYBOARD_SETUP:-0}" = 1 ]; then
    [ -n "${KEYBOARD_DEVICE_ID:-}" ] || log_warn 'Set KEYBOARD_DEVICE_ID=VENDOR:PRODUCT after identifying the laptop keyboard, then run keyboard-linux-setup.sh apply.'
    if [ -n "${KEYBOARD_DEVICE_ID:-}" ]; then
        sudo "$DOTFILES_DIR/keyboard-linux-setup.sh" apply --device-id "$KEYBOARD_DEVICE_ID" \
            || log_warn 'Caps Lock mapping was not activated; see keyboard-linux-setup.sh status'
    fi
else
    log_warn 'Caps Lock → tmux prefix is not active yet. After installing keyd and identifying the laptop keyboard, run: sudo ./keyboard-linux-setup.sh apply --device-id VENDOR:PRODUCT'
fi

if [ "$DRY_RUN" != 1 ] && [ "$LINKS_ONLY" != 1 ] && [ "${NEWSBOAT_SETUP:-0}" = 1 ]; then
    urls="$XDG_CONFIG_HOME/newsboat/urls"
    if [ ! -e "$urls" ] && [ ! -L "$urls" ]; then
        DOTFILES="$DOTFILES_DIR" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
            "$DOTFILES_DIR/bin/newsboat-urls"
    else
        log_info "Preserving existing Newsboat URLs file: $urls"
    fi
fi

if [ ${#SEEDED_CONFIGS[@]} -gt 0 ]; then
    printf '\n'
    log_warn "Created ${#SEEDED_CONFIGS[@]} local config file(s) that this repo never overwrites:"
    printf '  %s\n' "${SEEDED_CONFIGS[@]}"
    log_warn 'Keep private values and per-host choices here; no placeholders are active.'
fi

if [ "$DRY_RUN" = 1 ]; then
    log_info 'Dry run complete; no links or config files were changed.'
elif [ "$LINKS_ONLY" = 1 ]; then
    log_info 'Links-only setup complete; network, package, service, and keyboard activation were skipped.'
else
    log_info 'Dotfiles linked. Optional packages, services, authentication, and keyboard activation remain separate.'
fi
