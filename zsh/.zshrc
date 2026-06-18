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

# Plugins
plugins=(git zsh-autosuggestions brew sudo)

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
