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
# like a real value. A bogus value is worse than none: a tool prints a precise
# "unset" error when a variable is absent, but resolves "your.server.ip.here"
# and fails at DNS when it is set to a placeholder.
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

# OpenCode Console credential for Pi's opencode-go provider (pi/models.json).
# The opencode CLI itself is no longer configured here — this link exists only
# because pi's model route reads the Console token out of the opencode database.
if [ -f "$DOTFILES_DIR/bin/opencode-console-auth" ]; then
    create_symlink "$DOTFILES_DIR/bin/opencode-console-auth" "$HOME/.local/bin/opencode-console-auth"
fi

# Pi configuration
# plink does the linking, for the same reason olink exists: create_symlink skips
# a target that is already a symlink even when it points at the wrong place, and
# ~/.pi/agent also holds auth.json, sessions/ and install/, which are Pi's own.
# Linking is per item, never the directory.
if [ -f "$DOTFILES_DIR/bin/plink" ]; then
    create_symlink "$DOTFILES_DIR/bin/plink" "$HOME/.local/bin/plink"
    DOTFILES_DIR="$DOTFILES_DIR" bash "$DOTFILES_DIR/bin/plink"
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


# mrglass configuration
# Only config.yaml is linked. The Jira credentials come from ~/.secrets (the
# mrglass function in .zshrc passes them in). mrglass also writes state under
# ~/.local/state, so nothing else here is machine-local.
if [ -f "$DOTFILES_DIR/mrglass/config.yaml" ]; then
    create_symlink "$DOTFILES_DIR/mrglass/config.yaml" \
        "$HOME/.config/mrglass/config.yaml"
fi

# Gradle init script: the forked Groovy compiler defaults to a 512 MB heap, and
# a backend build that outgrows it hangs instead of failing. Only init.d is
# linked; ~/.gradle also holds caches and gradle.properties.
if [ -f "$DOTFILES_DIR/gradle/init.d/groovy-heap.gradle" ]; then
    create_symlink "$DOTFILES_DIR/gradle/init.d/groovy-heap.gradle" "$HOME/.gradle/init.d/groovy-heap.gradle"
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

# Sourced at the end of .zshrc behind [ -f ]: machine-local settings, no secrets.
seed_local_config "$DOTFILES_DIR/zsh/.zshrc.local.example" \
    "$HOME/.zshrc.local" 600 "machine-local settings (VPS host, MCP client ids)"

# Every secret lives in ~/.secrets/secrets.env: `secrets` edits it, `secret NAME`
# reads one value. Nothing sources it, so no shell carries a token. The team's
# ops skills read their Jira credentials from ~/.config/ecfx/jira.env, which
# links to the same file (same KEY=value format, same JIRA_* names).
seed_local_config "$DOTFILES_DIR/secrets/secrets.env.example" \
    "$HOME/.secrets/secrets.env" 600 "Jira, Slack MCP, proxy and other tokens (edit with: secrets)"
chmod 700 "$HOME/.secrets" 2>/dev/null || true
mkdir -p "$HOME/.config/ecfx" && chmod 700 "$HOME/.config/ecfx"
create_symlink "$HOME/.secrets/secrets.env" "$HOME/.config/ecfx/jira.env"
create_symlink "$DOTFILES_DIR/bin/secret" "$HOME/.local/bin/secret"
create_symlink "$DOTFILES_DIR/bin/secrets" "$HOME/.local/bin/secrets"

# Git configuration
if [ -f "$DOTFILES_DIR/git/.gitconfig" ]; then
    create_symlink "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
fi

if [ -f "$DOTFILES_DIR/git/.gitignore_global" ]; then
    create_symlink "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
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
# Skills are no longer linked into ~/.claude/skills. That directory was a single
# namespace shared by every project, so everything in it reached the system
# prompt of every session whether or not it applied. They are published as a
# marketplace instead: a repository names the plugins it wants in its own
# .claude/settings.json, the names arrive namespaced, and nothing loads unasked.
#
#   claude plugin install personal@dmitry-dotfiles --scope project
#
# Refresh vendored third-party skills first — the sync also regenerates the
# personal wrapper and the marketplace manifest. Guarded because install.sh runs
# under `set -e`: a failed sync must fall back to the committed copies, not abort
# the install.
if [ "${SKILLS_SYNC:-1}" != "0" ] && [ -x "$DOTFILES_DIR/claude/vendor-sync.sh" ]; then
    "$DOTFILES_DIR/claude/vendor-sync.sh" || log_warn "Vendor sync failed — using committed copies"
fi

if command -v claude >/dev/null 2>&1 && [ -f "$DOTFILES_DIR/claude/.claude-plugin/marketplace.json" ]; then
    claude plugin marketplace add "$DOTFILES_DIR/claude" >/dev/null 2>&1 \
        || claude plugin marketplace update dmitry-dotfiles >/dev/null 2>&1 \
        || log_warn "Could not register the dotfiles marketplace"
fi

if [ -f "$DOTFILES_DIR/claude/CLAUDE.md" ]; then
    create_symlink "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
fi

# Commands are the exception to the rule above: global, but typed only. Each
# declares `disable-model-invocation: true`, which keeps its description out of
# the system prompt — the body loads only when invoked as /name.
link_dir_contents "$DOTFILES_DIR/claude/commands" "$HOME/.claude/commands"

# wt keeps worktrees in ~/projects/worktrees/<repo>/<name>. These hooks send
# Claude Code's own worktrees (claude -w, subagent isolation) there too, instead
# of <repo>/.claude/worktrees. settings.json isn't linked, since Claude Code
# rewrites it; only the two hook keys are merged in.
if [ -f "$DOTFILES_DIR/bin/wt" ]; then
    create_symlink "$DOTFILES_DIR/bin/wt" "$HOME/.local/bin/wt"
    settings="$HOME/.claude/settings.json"
    [ -f "$settings" ] || echo '{}' > "$settings"
    tmp="$(mktemp)"
    if jq --arg wt "$HOME/.local/bin/wt" '
        .hooks.WorktreeCreate = [{hooks: [{type: "command", command: "\($wt) hook-create"}]}]
        | .hooks.WorktreeRemove = [{hooks: [{type: "command", command: "\($wt) hook-remove"}]}]' \
        "$settings" > "$tmp"; then
        mv "$tmp" "$settings"
    else
        rm -f "$tmp"; log_warn "Could not add the worktree hooks to $settings"
    fi
fi


# Agents stay out of ~/.secrets: secrets-guard runs before every Bash call (pi
# runs it too, through its claude-hooks extension) and the deny rules keep
# Claude's file tools out. docker-guard refuses a Gradle test run while Docker is
# down (it would hang on Testcontainers). gitlab-api-guard refuses a GitLab API
# write whose body comes from stdin or that lacks a JSON content type.
# dashboard-check lints a .ts/.vue file Claude just edited in ecfx-dashboard
# (PostToolUse; pi has no such event). Merged, not linked, since Claude Code
# rewrites settings.json; re-runs leave one copy of each.
settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -f "$settings" ] || echo '{}' > "$settings"
tmp="$(mktemp)"
if jq --arg g "$DOTFILES_DIR/bin/secrets-guard" --arg d "$DOTFILES_DIR/bin/docker-guard" \
      --arg a "$DOTFILES_DIR/bin/gitlab-api-guard" --arg c "$DOTFILES_DIR/bin/dashboard-check" '
    def without($cmds): [.[]? | select([.hooks[]?.command] - $cmds == [.hooks[]?.command])];
    .hooks.PreToolUse = ((.hooks.PreToolUse | without([$g, $d, $a]))
        + [{matcher: "Bash", hooks: [{type: "command", command: $g}]},
           {matcher: "Bash", hooks: [{type: "command", command: $d}]},
           {matcher: "Bash", hooks: [{type: "command", command: $a}]}])
    | .hooks.PostToolUse = ((.hooks.PostToolUse | without([$c]))
        + [{matcher: "Edit|Write|MultiEdit", hooks: [{type: "command", command: $c, timeout: 40}]}])
    | (.permissions.deny // []) as $deny
    | .permissions.deny = $deny + (["Read(~/.secrets/**)", "Edit(~/.secrets/**)",
        "Read(~/.config/ecfx/jira.env)"] - $deny)' "$settings" > "$tmp"; then
    mv "$tmp" "$settings"
else
    rm -f "$tmp"; log_warn "Could not add the agent hooks to $settings"
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

# wiki-sync commits a folder and pushes it to its git repo on the VPS (the remote
# is in the folder's .git/config, set when it is cloned): ~/wiki, and ~/artifacts
# (the sources of published claude.ai pages). One LaunchAgent per folder runs it
# every 15 minutes; .zshrc runs `wiki-sync check` for each to warn when it fails.
# WIKI_SYNC_AGENT=0 skips the agents. It replaced the rsync `notes`.
if [ -f "$DOTFILES_DIR/bin/wiki-sync" ]; then
    create_symlink "$DOTFILES_DIR/bin/wiki-sync" "$HOME/.local/bin/wiki-sync"
    rm -f "$HOME/.local/bin/notes"
    for spec in "wiki:$HOME/wiki:$HOME/.local/state/wiki-sync" \
                "artifacts:$HOME/artifacts:$HOME/.local/state/artifacts-sync"; do
        name="${spec%%:*}"; rest="${spec#*:}"; dir="${rest%%:*}"; state="${rest#*:}"
        [ "${WIKI_SYNC_AGENT:-1}" != "0" ] && [ -d "$dir/.git" ] || continue
        label="local.$name-sync"
        agent="$HOME/Library/LaunchAgents/$label.plist"
        mkdir -p "$HOME/Library/LaunchAgents" "$state"
        sed -e "s#__LABEL__#$label#g" -e "s#__DIR__#$dir#g" -e "s#__STATE__#$state#g" \
            -e "s#__NAME__#$name#g" -e "s#__HOME__#$HOME#g" \
            "$DOTFILES_DIR/launchd/autosync.plist" > "$agent.new"
        if ! cmp -s "$agent.new" "$agent"; then
            mv "$agent.new" "$agent"
            launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
            launchctl bootstrap "gui/$(id -u)" "$agent" \
                && log_info "Loaded the $name sync agent (every 15 minutes)" \
                || log_warn "Could not load $agent"
        else
            rm -f "$agent.new"
        fi
    done
fi

# ecfx-daily-commits lists today's commits across all ecfx-* repos.
if [ -f "$DOTFILES_DIR/bin/ecfx-daily-commits" ]; then
    create_symlink "$DOTFILES_DIR/bin/ecfx-daily-commits" "$HOME/.local/bin/ecfx-daily-commits"
fi

# sync-tickets moves my Jira tickets to match my MRs; driven by /sync-tickets.
if [ -f "$DOTFILES_DIR/bin/sync-tickets" ]; then
    create_symlink "$DOTFILES_DIR/bin/sync-tickets" "$HOME/.local/bin/sync-tickets"
fi

# clean-worktrees removes merged worktrees; driven by /clean-worktrees.
if [ -f "$DOTFILES_DIR/bin/clean-worktrees" ]; then
    create_symlink "$DOTFILES_DIR/bin/clean-worktrees" "$HOME/.local/bin/clean-worktrees"
fi

# end-day gathers the day's work for /end-day and files it in the diary.
if [ -f "$DOTFILES_DIR/bin/end-day" ]; then
    create_symlink "$DOTFILES_DIR/bin/end-day" "$HOME/.local/bin/end-day"
fi

# start-day gathers overnight activity for /start-day and files the plan in the diary.
if [ -f "$DOTFILES_DIR/bin/start-day" ]; then
    create_symlink "$DOTFILES_DIR/bin/start-day" "$HOME/.local/bin/start-day"
fi

# daily-stats counts a date range of the diary (plus my merged MRs) as JSON, for /review.
if [ -f "$DOTFILES_DIR/bin/daily-stats" ]; then
    create_symlink "$DOTFILES_DIR/bin/daily-stats" "$HOME/.local/bin/daily-stats"
fi

# diary-links moves the inline links in diary plan/report blocks to trailing refs.
if [ -f "$DOTFILES_DIR/bin/diary-links" ]; then
    create_symlink "$DOTFILES_DIR/bin/diary-links" "$HOME/.local/bin/diary-links"
fi

# changes-since prints what changed on my tickets and MRs since the last look, as JSON lines.
if [ -f "$DOTFILES_DIR/bin/changes-since" ]; then
    create_symlink "$DOTFILES_DIR/bin/changes-since" "$HOME/.local/bin/changes-since"
fi

# day-note leaves a message in the run-day inbox (hand-offs, report-backs, off-plan work).
if [ -f "$DOTFILES_DIR/bin/day-note" ]; then
    create_symlink "$DOTFILES_DIR/bin/day-note" "$HOME/.local/bin/day-note"
fi

# friction-ledger keeps the friction ledger in the wiki; /end-day's reflect step calls it.
if [ -f "$DOTFILES_DIR/bin/friction-ledger" ]; then
    create_symlink "$DOTFILES_DIR/bin/friction-ledger" "$HOME/.local/bin/friction-ledger"
fi

# friction records friction events; friction-mine gathers the day's friction for /end-day.
for f in friction friction-mine; do
    if [ -f "$DOTFILES_DIR/bin/$f" ]; then
        create_symlink "$DOTFILES_DIR/bin/$f" "$HOME/.local/bin/$f"
    fi
done

# coach-mine finds repeated prompts, restated rules, secrets in files and concept questions; friction-mine merges it.
if [ -f "$DOTFILES_DIR/bin/coach-mine" ]; then
    create_symlink "$DOTFILES_DIR/bin/coach-mine" "$HOME/.local/bin/coach-mine"
fi

# cards stores and schedules the usage coach's quiz cards in the wiki.
if [ -f "$DOTFILES_DIR/bin/cards" ]; then
    create_symlink "$DOTFILES_DIR/bin/cards" "$HOME/.local/bin/cards"
fi

# coach-fix queues the coach's approved fixes, builds each in a tmux job and lands them after /end-day.
if [ -f "$DOTFILES_DIR/bin/coach-fix" ]; then
    create_symlink "$DOTFILES_DIR/bin/coach-fix" "$HOME/.local/bin/coach-fix"
fi

# agent-report prints a background agent's final reply from its transcript (Wake check in the day session).
if [ -f "$DOTFILES_DIR/bin/agent-report" ]; then
    create_symlink "$DOTFILES_DIR/bin/agent-report" "$HOME/.local/bin/agent-report"
fi

# wait-for waits out a GitLab or Jira outage and then tells the run-day inbox.
if [ -f "$DOTFILES_DIR/bin/wait-for" ]; then
    create_symlink "$DOTFILES_DIR/bin/wait-for" "$HOME/.local/bin/wait-for"
fi

# day-plan opens today's diary plan in nvim in a tmux popup (tmux prefix+e, /day-plan).
if [ -f "$DOTFILES_DIR/bin/day-plan" ]; then
    create_symlink "$DOTFILES_DIR/bin/day-plan" "$HOME/.local/bin/day-plan"
fi

# repos-sync fetches every GitLab repo in ~/projects and fast-forwards its default branch (start-day collect).
if [ -f "$DOTFILES_DIR/bin/repos-sync" ]; then
    create_symlink "$DOTFILES_DIR/bin/repos-sync" "$HOME/.local/bin/repos-sync"
fi

# team-plugins-sync updates the team's Claude plugins and pi's team skills to the clone (start-day collect).
if [ -f "$DOTFILES_DIR/bin/team-plugins-sync" ]; then
    create_symlink "$DOTFILES_DIR/bin/team-plugins-sync" "$HOME/.local/bin/team-plugins-sync"
fi

# handoff-open opens a handed-off ticket's side session in a tmux window (/daily:handoff, /handoff).
if [ -f "$DOTFILES_DIR/bin/handoff-open" ]; then
    create_symlink "$DOTFILES_DIR/bin/handoff-open" "$HOME/.local/bin/handoff-open"
fi

# decide files the questions /run-day is waiting on; decisions is the deck that answers them
# (tmux prefix+y). Both are a wrapper around the standalone decisions binary; answers reach
# the session through run-day-inbox-answer, which writes the run-day inbox.
for f in decide decisions run-day-inbox-answer; do
    [ -f "$DOTFILES_DIR/bin/$f" ] && create_symlink "$DOTFILES_DIR/bin/$f" "$HOME/.local/bin/$f"
done

# The decisions binary (the deck, decide's commands, the MCP server) is the standalone
# project at ~/projects/decisions (DECISIONS_SRC). It is rebuilt only when its sources change
# (a hash of them is kept beside the binary), and installed under ~/.local/share/decisions so
# ~/.local/bin/decisions can stay a link to the bin/decisions wrapper. Needs cargo (the
# Brewfile's rust). DECISIONS_SETUP=0 skips.
setup_decisions() {
    local crate="${DECISIONS_SRC:-$HOME/projects/decisions}" root="$HOME/.local/share/decisions" sum
    if [ ! -f "$crate/Cargo.toml" ]; then
        log_warn "no decisions source at $crate - clone https://github.com/whitel1ght/decisions there"
        return 0
    fi
    if ! command -v cargo >/dev/null 2>&1; then
        log_warn "cargo not found - decide and the decisions popup need it: run ./brew-install.sh"
        return 0
    fi
    sum=$(cd "$crate" && find Cargo.toml Cargo.lock src -type f | LC_ALL=C sort | xargs shasum | shasum | cut -d' ' -f1)
    if [ -x "$root/bin/decisions" ] && [ "$(cat "$root/src.sha" 2>/dev/null)" = "$sum" ]; then
        log_info "decisions app up to date"
        return 0
    fi
    cargo install --locked --quiet --path "$crate" --root "$root" || return 1
    printf '%s\n' "$sum" > "$root/src.sha"
    DECISIONS_BUILT=1
    log_info "Built the decisions app"
}

if [ "${DECISIONS_SETUP:-1}" != "0" ]; then
    setup_decisions || log_warn "decisions build failed - decide and the popup keep the last built binary"
fi

# The decisions Telegram bot runs as a LaunchAgent (launchd/decisions-telegram.plist) through the
# bin/decisions wrapper, once `decisions telegram pair` has linked the chat; a rebuilt binary
# restarts it. DECISIONS_TELEGRAM_AGENT=0 skips.
setup_decisions_telegram() {
    local label="local.decisions-telegram" agent state
    agent="$HOME/Library/LaunchAgents/$label.plist"
    state="${RUN_DAY_STATE_DIR:-$HOME/.local/state/run-day}/decisions/telegram.json"
    if ! grep -qE '"chat_id": *-?[0-9]' "$state" 2>/dev/null; then
        log_info "decisions Telegram bot not paired: run decisions telegram pair, then ./install.sh"
        return 0
    fi
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    sed -e "s#__LABEL__#$label#g" -e "s#__HOME__#$HOME#g" \
        "$DOTFILES_DIR/launchd/decisions-telegram.plist" > "$agent.new"
    if ! cmp -s "$agent.new" "$agent"; then
        mv "$agent.new" "$agent"
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        launchctl bootstrap "gui/$(id -u)" "$agent" \
            && log_info "Loaded the decisions Telegram bot" \
            || log_warn "Could not load $agent"
    else
        rm -f "$agent.new"
        if [ "${DECISIONS_BUILT:-0}" = 1 ]; then
            launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null \
                && log_info "Restarted the decisions Telegram bot on the new build" || true
        fi
    fi
}

if [ "${DECISIONS_TELEGRAM_AGENT:-1}" != "0" ]; then
    setup_decisions_telegram || log_warn "could not set up the decisions Telegram bot"
fi

# frictions is the deck over the friction queue (tmux prefix+` f); friction-cards builds its cards
# and prints the status badge. The tick LaunchAgent (launchd/frictions-tick.plist) runs
# `friction-cards tick` every 2 minutes. FRICTIONS_TICK_AGENT=0 skips it.
for f in frictions friction-cards; do
    [ -f "$DOTFILES_DIR/bin/$f" ] && create_symlink "$DOTFILES_DIR/bin/$f" "$HOME/.local/bin/$f"
done

setup_frictions_tick() {
    local label="local.frictions-tick" agent
    agent="$HOME/Library/LaunchAgents/$label.plist"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    sed -e "s#__LABEL__#$label#g" -e "s#__HOME__#$HOME#g" \
        "$DOTFILES_DIR/launchd/frictions-tick.plist" > "$agent.new"
    if ! cmp -s "$agent.new" "$agent"; then
        mv "$agent.new" "$agent"
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        launchctl bootstrap "gui/$(id -u)" "$agent" \
            && log_info "Loaded the frictions tick agent" \
            || log_warn "Could not load $agent"
    else
        rm -f "$agent.new"
    fi
}

if [ "${FRICTIONS_TICK_AGENT:-1}" != "0" ]; then
    setup_frictions_tick || log_warn "could not set up the frictions tick agent"
fi

# mr-watch finds new review notes on my MRs and posts the replies; driven by /watch-mrs.
if [ -f "$DOTFILES_DIR/bin/mr-watch" ]; then
    create_symlink "$DOTFILES_DIR/bin/mr-watch" "$HOME/.local/bin/mr-watch"
fi

# jira-api is the Jira REST helper the daily system calls; it reads its login with `secret`.
if [ -f "$DOTFILES_DIR/bin/jira-api" ]; then
    create_symlink "$DOTFILES_DIR/bin/jira-api" "$HOME/.local/bin/jira-api"
fi

# jt searches and previews Jira tickets with fzf, on top of jira-cli. jira-cli
# keeps its own config; the token comes from JIRA_API_TOKEN, which jt (and the
# jira-cli skill) pass from ~/.secrets, so the config only needs the site, login
# and project.
if [ -f "$DOTFILES_DIR/bin/jt" ]; then
    create_symlink "$DOTFILES_DIR/bin/jt" "$HOME/.local/bin/jt"
fi
if command -v jira >/dev/null 2>&1 && [ ! -f "$HOME/.config/.jira/.config.yml" ] \
    && jira_user="$("$DOTFILES_DIR/bin/secret" JIRA_USER 2>/dev/null)"; then
    JIRA_API_TOKEN="$("$DOTFILES_DIR/bin/secret" JIRA_TOKEN 2>/dev/null)" \
    jira init --installation cloud --server https://ecfxdev.atlassian.net \
        --login "$jira_user" --auth-type basic --project ECFX --board None \
        || echo "jira init failed; run it by hand once JIRA_TOKEN in ~/.secrets works"
fi

# art opens a published claude.ai artifact from its source in ~/artifacts (fzf picker).
if [ -f "$DOTFILES_DIR/bin/art" ]; then
    create_symlink "$DOTFILES_DIR/bin/art" "$HOME/.local/bin/art"
fi

# dev switches the dashboard dev server between worktrees (tmux window dev:dashboard).
if [ -f "$DOTFILES_DIR/bin/dev" ]; then
    create_symlink "$DOTFILES_DIR/bin/dev" "$HOME/.local/bin/dev"
fi

# webui runs Open WebUI against LM Studio on demand; `webui install` builds its venv.
if [ -f "$DOTFILES_DIR/bin/webui" ]; then
    create_symlink "$DOTFILES_DIR/bin/webui" "$HOME/.local/bin/webui"
fi

# docs-check keeps the system manual (~/wiki/tools) in step with this repo; the
# repo's commit-msg hook runs it, and `docs-check coverage` lists what is undocumented.
if [ -f "$DOTFILES_DIR/bin/docs-check" ]; then
    create_symlink "$DOTFILES_DIR/bin/docs-check" "$HOME/.local/bin/docs-check"
    git -C "$DOTFILES_DIR" config core.hooksPath .githooks
    # decisions and articles run the same hook folder; docs-check finds its repo by path.
    for repo in decisions articles; do
        if [ -d "$HOME/projects/$repo/.git" ]; then
            git -C "$HOME/projects/$repo" config core.hooksPath "$DOTFILES_DIR/.githooks"
        fi
    done
fi

# localai starts/stops the whole local AI stack: LM Studio, its models, Open WebUI.
if [ -f "$DOTFILES_DIR/bin/localai" ]; then
    create_symlink "$DOTFILES_DIR/bin/localai" "$HOME/.local/bin/localai"
fi

# articles lives in its own repo (~/projects/articles); link its wrapper when cloned.
if [ -x "$HOME/projects/articles/bin/articles" ]; then
    create_symlink "$HOME/projects/articles/bin/articles" "$HOME/.local/bin/articles"
fi

# tmux-prune closes idle tmux windows; bound to prefix+X in tmux/.tmux.conf.
if [ -f "$DOTFILES_DIR/bin/tmux-prune" ]; then
    create_symlink "$DOTFILES_DIR/bin/tmux-prune" "$HOME/.local/bin/tmux-prune"
fi

# open-path backs the prefix+o file picker (tmux/.tmux.conf); a vendored copy of
# the tmux-claude-picker plugin script that also reads pi session transcripts.
if [ -f "$DOTFILES_DIR/bin/open-path" ]; then
    create_symlink "$DOTFILES_DIR/bin/open-path" "$HOME/.local/bin/open-path"
fi

# wiki-commit commits an agent's edits to wiki pages with an Agent-edit trailer.
if [ -f "$DOTFILES_DIR/bin/wiki-commit" ]; then
    create_symlink "$DOTFILES_DIR/bin/wiki-commit" "$HOME/.local/bin/wiki-commit"
fi

# system-check reports drift in the system memory as JSON; /end-day runs it.
if [ -f "$DOTFILES_DIR/bin/system-check" ]; then
    create_symlink "$DOTFILES_DIR/bin/system-check" "$HOME/.local/bin/system-check"
fi

# session-picker backs the prefix+j / prefix+a window pickers (tmux/.tmux.conf);
# a vendored copy of the tmux-claude-picker plugin script that also covers pi,
# opencode, and codex sessions.
if [ -f "$DOTFILES_DIR/bin/session-picker" ]; then
    create_symlink "$DOTFILES_DIR/bin/session-picker" "$HOME/.local/bin/session-picker"
fi

# cs launches Claude Code with a chosen skill set rather than every skill and
# agent installed under ~/.claude. See the header of bin/cs for why that matters.
if [ -f "$DOTFILES_DIR/bin/cs" ]; then
    create_symlink "$DOTFILES_DIR/bin/cs" "$HOME/.local/bin/cs"
fi

# cs-add links skills into a session that is already running; Claude Code
# rescans its skill directories, so they arrive without a restart.
if [ -f "$DOTFILES_DIR/bin/cs-add" ]; then
    create_symlink "$DOTFILES_DIR/bin/cs-add" "$HOME/.local/bin/cs-add"
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

# Install repy from its tagged source; it is not on crates.io. Only its config
# used to be handled here, so a fresh machine got a linked configuration.json
# and no reader. `cargo install --list` records the tag each crate was built
# from, which makes re-runs a local no-op instead of a git fetch. Needs cargo
# from the Brewfile's rust formula. Set REPY_SETUP=0 to skip.
REPY_TAG="v0.25.0"

setup_repy() {
    if ! command -v cargo >/dev/null 2>&1; then
        log_warn "cargo not found - run ./brew-install.sh, then re-run this script"
        return 0
    fi

    if cargo install --list | grep -qF "newptcai/repy?tag=$REPY_TAG#"; then
        log_info "repy $REPY_TAG already installed"
        return 0
    fi

    cargo install --locked --git https://github.com/newptcai/repy --tag "$REPY_TAG" || return 1
    log_info "Installed repy $REPY_TAG"
}

if [ "${REPY_SETUP:-1}" != "0" ]; then
    setup_repy || log_warn "repy install failed"
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
# Routing policy lives in proxy/direct-domains.txt (what stays off the VPS)
# and proxy/block-domains.txt; the VLESS_* values stay in
# ~/.secrets/secrets.env and never enter this repo. Guarded like the
# vendor sync above: install.sh runs under `set -e`, and an unconfigured proxy
# must not abort the remaining setup. Set PROXY_SETUP=0 to skip.
setup_proxy() {
    local secrets="$HOME/.secrets/secrets.env"
    local plist="/Library/LaunchDaemons/local.singbox.plist"

    create_symlink "$DOTFILES_DIR/bin/proxyctl" "$HOME/.local/bin/proxyctl"

    if ! command -v sing-box >/dev/null 2>&1; then
        log_warn "sing-box not installed - run: brew install sing-box"
        return 0
    fi

    if ! SECRETS_FILE="$secrets" "$DOTFILES_DIR/bin/secret" VLESS_UUID >/dev/null 2>&1; then
        log_warn "Proxy not configured: add the six VLESS_* values with \`secrets\`"
        log_warn "  (proxy/secrets.env.example says where each comes from), then: proxyctl on"
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

# --- SDKMAN ----------------------------------------------------------------
# .zshrc sources ~/.sdkman/bin/sdkman-init.sh behind [[ -s ]], so its absence is
# silent there. The ecfx-* runners are not so forgiving: each sources that path
# UNCONDITIONALLY, so on a machine without SDKMAN they die on line 1 with "No
# such file or directory" and never reach the work they describe.
#
# ecfx-backend's .sdkmanrc pins java 25.0.3-tem, gradle, micronaut and groovy;
# the runners call `sdk env install` themselves, so only SDKMAN itself is
# needed here. There is no Homebrew formula, hence the upstream installer.
#
# rcupdate=false matters: without it the installer appends its init block to
# ~/.zshrc, which is a symlink into this repo — it would edit a versioned file
# and duplicate the block .zshrc already carries. Set SDKMAN_SETUP=0 to skip.
setup_sdkman() {
    if [ -d "$HOME/.sdkman" ]; then
        log_info "SDKMAN already installed"
        return 0
    fi

    command -v curl >/dev/null 2>&1 || { log_warn "curl not found - skipping SDKMAN"; return 0; }

    curl -s "https://get.sdkman.io?rcupdate=false" | bash >/dev/null 2>&1 || return 1
    [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] || return 1
    log_info "Installed SDKMAN"
}

if [ "${SDKMAN_SETUP:-1}" != "0" ]; then
    setup_sdkman || log_warn "SDKMAN install failed - the ecfx-* runners will not work"
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