# Drop duplicate PATH entries: installers and re-sourced files keep prepending.
typeset -U path PATH

# ============================================================================
# ZSH CONFIGURATION
# ============================================================================

# -----------------------------------------------------------------------------
# VAULT DRIFT WARNING
# -----------------------------------------------------------------------------
# Warn if the machine-rebuild vault is behind the files it mirrors. Compares
# mtimes only — never opens the vault, so no passphrase and no measurable cost
# (measured at under 10ms). Silent unless something drifted, and silent
# entirely without ~/wiki.
#
# This MUST stay above the instant prompt preamble below. p10k captures console
# output produced after that preamble and warns about it on every start, since
# such output breaks the prompt it has already drawn. This used to sit at the
# end of the file and was harmless only because ~/wiki was empty and the check
# never printed; restoring the wiki made it print, and p10k started complaining.
#
# Called by absolute path on purpose: ~/.local/bin is added to PATH further
# down in this file, so `command -v vault-check` finds nothing this early.
[ -x "$HOME/.local/bin/vault-check" ] && "$HOME/.local/bin/vault-check"
# Same for the git backups of ~/wiki and ~/artifacts: one line when the last
# sync to the VPS failed or none succeeded for a day, nothing otherwise.
[ -x "$HOME/.local/bin/wiki-sync" ] && "$HOME/.local/bin/wiki-sync" check
[ -x "$HOME/.local/bin/wiki-sync" ] && WIKI_DIR="$HOME/artifacts" WIKI_SYNC_NAME=artifacts \
    WIKI_SYNC_STATE="$HOME/.local/state/artifacts-sync" "$HOME/.local/bin/wiki-sync" check

# -----------------------------------------------------------------------------
# POWERLEVEL10K INSTANT PROMPT
# -----------------------------------------------------------------------------
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# -----------------------------------------------------------------------------
# OH-MY-ZSH CONFIGURATION
# -----------------------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# Zsh options
setopt autocd autopushd
ENABLE_CORRECTION="true"

# Plugins. Order matters: oh-my-zsh adds these to fpath, runs compinit, then
# sources them in array order. fzf-tab has to be sourced after compinit but
# before anything that wraps widgets, so it sits ahead of zsh-autosuggestions.
plugins=(git fzf-tab zsh-autosuggestions brew sudo)

# oh-my-zsh updates itself every 13 days without asking; under the p10k instant
# prompt it also stays silent.
zstyle ':omz:update' mode auto

source $ZSH/oh-my-zsh.sh

# The theme and plugins in $ZSH_CUSTOM (powerlevel10k, fzf-tab, autosuggestions,
# syntax highlighting) are git clones that oh-my-zsh's updater skips. The
# autoupdate plugin (TamCore, installed by zsh-setup.sh) pulls them on the same
# 13-day cycle. It is sourced here instead of listed in plugins=() so its
# per-plugin lines go to a log: any output during startup trips the instant
# prompt's warning, and QUIET only hides its header.
ZSH_CUSTOM_AUTOUPDATE_QUIET=true
[[ -r $ZSH_CUSTOM/plugins/autoupdate/autoupdate.plugin.zsh ]] &&
    source $ZSH_CUSTOM/plugins/autoupdate/autoupdate.plugin.zsh >>"$ZSH_CACHE_DIR/custom-update.log" 2>&1

# -----------------------------------------------------------------------------
# ALIASES
# -----------------------------------------------------------------------------
# Editor shortcuts
alias vim="nvim"
alias vi="nvim"
alias vimconfig="vim ~/.config/nvim/init.lua"
alias zshconfig="vim ~/.zshrc"

# Terminal config shortcuts
alias ohmyzsh="vim ~/.oh-my-zsh"

# Git productivity
alias today='git log --all --pretty=format:"*%h - %s" --after="$(date +%Y-%m-%d) 00:00" --until="$(date +%Y-%m-%d) 23:59" --author="`git config user.name`" | pbcopy'
alias yesterday='git log --all --pretty=format:"*%h - %s" --after="$(date -v -1d +%Y-%m-%d) 00:00" --until="$(date -v -1d +%Y-%m-%d) 23:59" --author="`git config user.name`" | pbcopy'

# File listing
alias eza='eza -1 --icons'

# Jira sprint views, see `jt -h`
alias jmine='jt -m'   # current sprint, assigned to me
alias jtodo='jt -u'   # current Omni sprint, unassigned and To-Do

# The wiki backs itself up: a LaunchAgent runs wiki-sync (git commit + push to
# the VPS) every 15 minutes. `wiki-sync` forces a run, `wiki-sync status` explains.


# Every interactive pi, plain or through an alias below, first updates pi and its extensions
# (bin/pi-autoupdate: a few seconds, skipped for subcommands, -p and within 10 min of the last
# update), so it never opens on an "update available" notice.
pi() { (( $+commands[pi-autoupdate] )) && pi-autoupdate "$@"; command pi "$@"; }

# w <word>: define a word (macOS's dictionary) and save it as a word to learn (bin/words; the
# words track of the learning system). Replaces the Unix `w` (who is logged in) in this shell.
alias w='words look'

# Local Pi agent on Qwen2.5-Coder 14B in LM Studio (pi/models.json). Load it
# with `lms load qwen/qwen2.5-coder-14b --context-length 16384`; the default 8k
# is too small. It can use the built-in tools, but extensions, skills, MCP and
# context files are off: with them Pi sends ~40k tokens before the first message.
alias pilm='pi --model lmstudio/qwen/qwen2.5-coder-14b --models lmstudio/qwen/qwen2.5-coder-14b -ne -ns -np -nc --no-mcp'

# Same lean setup on Gemma 4 E4B (8-bit MLX, vision + native tool calls). Load it
# with `lms load gemma-4-e4b-it-mlx -c 32768 --parallel 1`; ~8.4 GB resident (or
# just run `localai`). Meant for talking things through and learning, not for
# agent work: no skills or context files (they would fill Gemma's 32k window;
# all skills alone are ~20k tokens). One extension is loaded despite -ne: web
# search (pi-web-access; queries go to Exa). Prompt overhead is ~4.3k tokens.
# pi/local-model/wiki-search stays out until secrets are moved out of ~/wiki.
alias pigm='pi --model lmstudio/gemma-4-e4b-it-mlx --models lmstudio/gemma-4-e4b-it-mlx -ne -ns -np -nc --no-mcp -e ~/.pi/agent/npm/node_modules/pi-web-access/dist/index.js'

# Free Pi session, with Longcat as the only scoped model.
alias pifree='pi --model opencode-go/longcat-2.5-preview-free --models opencode-go/longcat-2.5-preview-free'

# Provider-scoped sessions.
alias piopenai='pi --model openai/gpt-6.1-sol --models "openai/*"'

# Longcat leads a ten-model Go pool with coding, reasoning and flash alternatives.
alias pigo='pi --model opencode-go/longcat-2.5-preview-free --models opencode-go/longcat-2.5-preview-free,opencode-go/gpt-6-luna,opencode-go/glm-5.3,opencode-go/qwen3.8-max,opencode-go/grok-4.7,opencode-go/mimo-v2.6-pro,opencode-go/kimi-k3,opencode-go/glm-5.3-flash,opencode-go/qwen3.8-flash,opencode-go/deepseek-v4.1-flash'

# Better grep
alias grep='grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn}'

# Architecture-specific
alias io="arch -x86_64 io"

# Merge requests: run `mrglass`. It is a TUI built from ~/projects/mrglass into
# ~/go/bin (see the PATH entry below). Its Jira detail needs JIRA_EMAIL and
# JIRA_API_TOKEN, handed to that one process from ~/.secrets.
mrglass() {
  JIRA_EMAIL="$(secret JIRA_USER)" JIRA_API_TOKEN="$(secret JIRA_TOKEN)" command mrglass "$@"
}

# -----------------------------------------------------------------------------
# PATH CONFIGURATION
# -----------------------------------------------------------------------------
# Homebrew paths
export PATH="/opt/homebrew/opt/jpeg/bin:$PATH"
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"

# User binaries
export PATH="$HOME/.cargo/bin:$PATH"
# Where `go install` puts binaries. Without this, installing a Go tool
# appears to succeed and the command is then simply not found — mrglass,
# built from ~/projects/mrglass, lands here.
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# -----------------------------------------------------------------------------
# DEVELOPMENT TOOLS
# -----------------------------------------------------------------------------

# Node Version Manager
#
# nvm comes from Homebrew, which does NOT create ~/.nvm and does NOT put nvm.sh
# there — it installs to $HOMEBREW_PREFIX/opt/nvm/nvm.sh and leaves NVM_DIR to
# you. Sourcing "$NVM_DIR/nvm.sh" therefore matched nothing on a fresh machine,
# and the [ -s ] guard made that silent: nvm installed, nvm never loaded, no
# node, no npm. Everything downstream that needs node failed with no clue why —
# mason could not install ts_ls, vue_ls, eslint, jsonls, cssls, html, pyright or
# elm-language-server, so eight LSP servers were simply absent.
#
# NVM_DIR is still ~/.nvm: that is where nvm puts the node versions it installs,
# and it has to exist before the first `nvm install` or nvm errors out.
# HOMEBREW_PREFIX comes from .zprofile, with a fallback for non-login shells
# that never sourced it.
export NVM_DIR="$HOME/.nvm"
[ -d "$NVM_DIR" ] || mkdir -p "$NVM_DIR"
NVM_BREW="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm"
[ -s "$NVM_BREW/nvm.sh" ] && \. "$NVM_BREW/nvm.sh"
[ -s "$NVM_BREW/etc/bash_completion.d/nvm" ] && \. "$NVM_BREW/etc/bash_completion.d/nvm"
unset NVM_BREW

# SDKMAN (must be at end for proper initialization)
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# -----------------------------------------------------------------------------
# ADDITIONAL TOOLS
# -----------------------------------------------------------------------------
# Zoxide (better cd)
eval "$(zoxide init zsh)"

# -----------------------------------------------------------------------------
# FZF
# -----------------------------------------------------------------------------
# Ctrl-R fuzzy history, Ctrl-T insert a file path, Ctrl-X then c cd into a
# subdirectory (AeroSpace owns Alt-C). Needs fzf >= 0.48 for `fzf --zsh`.
source <(fzf --zsh)

# A real widget consumes the whole sequence; undefined-key can leak its suffix.
ignore-editor-key() { :; }
zle -N ignore-editor-key
for keymap in emacs viins vicmd; do
  bindkey -M "$keymap" '^Xc' fzf-cd-widget
  for sequence in '\e[1;6P' '\e[1;6Q' '\e[1;6R' '\e[1;6S' '\e[15;6~' '\e[17;6~' '\e[18;6~' '\e[19;6~' '\e[20;6~'; do
    bindkey -M "$keymap" "$sequence" ignore-editor-key
  done
done
unset keymap sequence

# fd honours .gitignore, so generated trees stay out without being listed here.
# The explicit excludes are for directories git tracks or ignores per-repo but
# that are never what you are reaching for.
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git --exclude node_modules --exclude build --exclude target'
# TokyoNight Storm, to match ghostty's theme. bg and gutter are -1 (terminal
# default) rather than #24283b so the terminal's own background shows through.
export FZF_DEFAULT_OPTS="--height 60% --layout reverse --border
  --bind 'ctrl-/:toggle-preview'
  --color=bg:-1,gutter:-1,bg+:#292e42,fg:#c0caf5,fg+:#c0caf5
  --color=hl:#7aa2f7,hl+:#7dcfff,query:#c0caf5,prompt:#7dcfff
  --color=pointer:#bb9af7,marker:#9ece6a,spinner:#bb9af7
  --color=info:#565f89,header:#7aa2f7,border:#565f89"

# bat ships no TokyoNight theme; base16 renders through the terminal's own 16
# colours, which ghostty has already set to TokyoNight Storm.
export BAT_THEME="base16"

# Ctrl-T reuses the same walker so the two agree on what a file is.
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
# img-preview draws images as pictures (Kitty graphics) and the rest with bat.
export FZF_CTRL_T_OPTS="--preview 'img-preview {}'"

# Ctrl-R: preview is hidden until ctrl-/ because most history lines fit on one
# line; it earns its keep on the long ones. ctrl-y yanks without running.
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window up:3:hidden:wrap
  --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
  --header 'ctrl-y copy | ctrl-/ preview'"

# Ctrl-X then c descends into a subdirectory. zoxide is the complement, not
# a duplicate: `z` jumps to directories already visited, from anywhere;
# the picker walks into ones you have never been to.
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git --exclude node_modules'
export FZF_ALT_C_OPTS="--preview 'eza -1 --icons --color=always {}'"

# -----------------------------------------------------------------------------
# FZF-TAB
# -----------------------------------------------------------------------------
# fzf-tab does not complete anything itself — it renders zsh's own completion
# results through fzf. So every completion definition already installed (git,
# kubectl, glab, gh, brew, docker) becomes a searchable list for free. Loaded
# from the plugins array above.
zstyle ':completion:*' menu no                     # required: fzf-tab replaces the menu
zstyle ':completion:*:descriptions' format '[%d]'  # group headers fzf-tab renders
# macOS sets LSCOLORS (BSD format); zsh's list-colors needs the GNU LS_COLORS,
# so without this the completion list is uncoloured. vivid generates it in the
# same theme as the terminal. Warm cost is ~0ms.
command -v vivid >/dev/null 2>&1 && export LS_COLORS="$(vivid generate tokyonight-storm)"
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Per-context previews. $realpath is the candidate as a path, $word as text.
# bin/dev: Tab offers its subcommands and the dashboard worktrees, by branch,
# instead of the files in the current directory.
_dev() {
  local -a items
  items=("${(@f)$(dev --complete 2>/dev/null)}")
  _describe 'dev' items
}
compdef _dev dev

zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --icons --color=always $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --icons --color=always $realpath'
zstyle ':fzf-tab:complete:(nvim|vim|vi|bat|cat|less|open):*' fzf-preview 'img-preview $realpath'
zstyle ':fzf-tab:complete:git-(checkout|switch|rebase|merge|log|show):*' \
  fzf-preview 'git log --oneline --graph --color=always $word | head -40'
# `git add` mostly offers untracked paths, and `git diff` prints nothing for
# those — so fall back to the file's contents, and list directories.
zstyle ':fzf-tab:complete:git-(add|stage|restore|rm):*' fzf-preview \
  'if [[ -d $realpath ]]; then eza -1 --icons --color=always -- $realpath;
   else d=$(git diff --color=always -- $realpath);
     [[ -n $d ]] && print -r -- $d || bat -n --color=always -- $realpath; fi'
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview 'ps -p $word -o comm=,args='

# kubectl: $words carries the whole command line, so the resource type can be
# read off it and defaults to pod for verbs that imply one (logs, exec). Capped
# by `deadline` because kubectl blocks on connection setup, not just requests —
# without it a preview against an unreachable cluster hangs the pane.
#
# The preview starts hidden, which is the point. `kubectl describe` against
# this cluster measures 3.3-4.3s, essentially all of it connection setup, so a
# live preview would stall every arrow-key move for seconds. fzf does not run
# the command while the window is hidden, so navigation stays instant and
# ctrl-/ fetches details only for the pod actually being considered. The
# deadline is 8s rather than 2s because 2s never completes a real describe.
zstyle ':fzf-tab:complete:kubectl:*' fzf-flags --preview-window=hidden
zstyle ':fzf-tab:complete:kubectl:*' fzf-preview \
  'deadline 8 kubectl describe \
     ${${words[(r)(po|pod|pods|deploy|deployment|deployments|svc|service|services|no|node|nodes|ns|namespace|namespaces|cm|configmap|configmaps|secret|secrets|job|jobs|cronjob|cronjobs|ing|ingress|sts|statefulset|statefulsets)]}:-pod} \
     $word 2>/dev/null | head -80'

# docker inspect covers containers and images alike, so one rule serves every
# subcommand. Config.Env is dropped: it is usually the longest section and
# routinely carries credentials, which have no business on screen in a
# completion popup. No deadline — this is a local socket, measured at ~70ms.
zstyle ':fzf-tab:complete:docker:*' fzf-preview \
  'docker inspect $word 2>/dev/null | jq -C "del(.[].Config.Env)" 2>/dev/null | head -60'

# < and > move between completion groups (local vs remote branches, say).
zstyle ':fzf-tab:*' switch-group '<' '>'
# Without this fzf-tab ignores FZF_DEFAULT_OPTS entirely (its default is "no"),
# and the popup would keep fzf's stock colours while everything else is themed.
zstyle ':fzf-tab:*' use-fzf-default-opts yes

# Superfile (spf) — cd_on_quit makes superfile write `cd '<dir>'` to its lastdir
# file on exit; the shell has to source that. The tidier-looking --print-last-dir
# cannot be used here: it prints to stdout, so capturing it in $(…) also takes the
# terminal away from bubbletea, which then has no tty to size itself against and
# renders the whole TUI into the pipe — the window just sits there looking hung.
# The file is cleared first so a crashed or killed superfile cannot cd us to
# wherever the previous run ended. `command` stops the function recursing.
spf() {
  local lastdir_file
  lastdir_file="$(command spf path-list --lastdir-file)" || return
  command rm -f -- "$lastdir_file"
  command spf "$@" || return
  if [[ -f $lastdir_file ]]; then
    eval "$(<"$lastdir_file")"
  fi
}

# Syntax highlighting. Sourced by path rather than through the plugins array
# because it has to come last — after fzf's keybindings above define their
# widgets, since it wraps whatever exists at load time. Guarded: on a machine
# where zsh-setup.sh has not run yet, an unguarded source made every shell
# start with an error.
ZSH_HIGHLIGHT="$ZSH/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -r "$ZSH_HIGHLIGHT" ]] && source "$ZSH_HIGHLIGHT"
unset ZSH_HIGHLIGHT

# Powerlevel10k configuration
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# -----------------------------------------------------------------------------
# PRIVATE CONFIGURATION
# -----------------------------------------------------------------------------
# Load private/local configurations (API keys, server configs, etc.)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH=/Users/dmitry/.opencode/bin:$PATH
export PATH="$HOME/bin:$PATH"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/dmitry/.lmstudio/bin"
# End of LM Studio CLI section

