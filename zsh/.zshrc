# ============================================================================
# ZSH CONFIGURATION
# ============================================================================

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

source $ZSH/oh-my-zsh.sh

# -----------------------------------------------------------------------------
# ALIASES
# -----------------------------------------------------------------------------
# Editor shortcuts
alias vim="nvim"
alias vi="nvim"
alias vimconfig="vim ~/.config/nvim/init.vim"
alias zshconfig="vim ~/.zshrc"

# Terminal config shortcuts
alias ohmyzsh="vim ~/.oh-my-zsh"

# Git productivity
alias today='git log --all --pretty=format:"*%h - %s" --after="$(date +%Y-%m-%d) 00:00" --until="$(date +%Y-%m-%d) 23:59" --author="`git config user.name`" | pbcopy'
alias yesterday='git log --all --pretty=format:"*%h - %s" --after="$(date -v -1d +%Y-%m-%d) 00:00" --until="$(date -v -1d +%Y-%m-%d) 23:59" --author="`git config user.name`" | pbcopy'

# File listing
alias eza='eza -1 --icons'

# Wiki sync. The server details live in ~/.zshrc.local; bin/notes reads them
# from the environment so none of them appear in this public repo.
alias pull_notes='notes pull'
alias push_notes='notes push'

# Better grep
grep='grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn}'

# Architecture-specific
alias io="arch -x86_64 io"

# gitlab-mr-status — open-MR status report + change notifications
# (https://gitlab.com tool living in ~/projects/gitlab-mr-status)
export MRS_DIR="$HOME/projects/gitlab-mr-status"
alias mrs="$MRS_DIR/bin/mr-status.py"           # regenerate the report once
alias mrsw="$MRS_DIR/bin/mr-status.py --watch"  # watch & refresh on interval
alias mrsd="$MRS_DIR/bin/mr-status.py --diff"   # print JSON change-list
alias mrsn="$MRS_DIR/bin/mr-notify.py"          # diff + desktop notifications
alias mrso="open $MRS_DIR/mr-status.md"         # open the report

# -----------------------------------------------------------------------------
# PATH CONFIGURATION
# -----------------------------------------------------------------------------
# Homebrew paths
export PATH="/opt/homebrew/opt/jpeg/bin:$PATH"
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"

# User binaries
export PATH="$HOME/.codeium/windsurf/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# -----------------------------------------------------------------------------
# DEVELOPMENT TOOLS
# -----------------------------------------------------------------------------
# Perl
if (command -v perl && command -v cpanm) >/dev/null 2>&1; then
  test -d "$HOME/perl5/lib/perl5" && eval $(perl -I "$HOME/perl5/lib/perl5" -Mlocal::lib)
fi

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

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
# Ctrl-R fuzzy history, Ctrl-T insert a file path at the cursor, Alt-C cd into
# a subdirectory. Needs fzf >= 0.48 for `fzf --zsh`.
source <(fzf --zsh)

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
export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always {}'"

# Ctrl-R: preview is hidden until ctrl-/ because most history lines fit on one
# line; it earns its keep on the long ones. ctrl-y yanks without running.
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window up:3:hidden:wrap
  --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
  --header 'ctrl-y copy | ctrl-/ preview'"

# Alt-C descends into a subdirectory of the current one. zoxide is the
# complement, not a duplicate: `z` jumps to directories already visited, from
# anywhere; Alt-C walks into ones you have never been to.
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
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --icons --color=always $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --icons --color=always $realpath'
zstyle ':fzf-tab:complete:(nvim|vim|vi|bat|cat|less):*' fzf-preview 'bat -n --color=always $realpath'
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

# Superfile (spf) — cd_on_quit only makes superfile print its last directory;
# the shell has to act on it. `command` stops the function recursing into itself.
spf() {
  local dir
  dir="$(command spf --print-last-dir "$@")" || return
  if [[ -n "$dir" ]]; then
    cd "$dir"
  fi
}

# Syntax highlighting
source "$HOME/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# Powerlevel10k configuration
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# -----------------------------------------------------------------------------
# PRIVATE CONFIGURATION
# -----------------------------------------------------------------------------
# Load private/local configurations (API keys, server configs, etc.)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

export PATH="$HOME/.local/bin:$PATH"

# Warn if the machine-rebuild vault is behind the files it mirrors. Compares
# mtimes only — never opens the vault, so no passphrase and no measurable cost.
# Silent unless something drifted, and silent entirely without ~/wiki.
command -v vault-check >/dev/null 2>&1 && vault-check
