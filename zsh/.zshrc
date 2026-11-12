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
if [[ -d "$ZSH/custom/themes/powerlevel10k" ]]; then
  ZSH_THEME="powerlevel10k/powerlevel10k"
else
  ZSH_THEME="robbyrussell"
fi

# Zsh options
setopt autocd autopushd
ENABLE_CORRECTION="true"

# Load only plugins that are installed; fzf-tab must precede autosuggestions.
plugins=(git)
[[ -d "$ZSH/custom/plugins/fzf-tab" ]] && plugins+=(fzf-tab)
[[ -d "$ZSH/custom/plugins/zsh-autosuggestions" ]] && plugins+=(zsh-autosuggestions)
plugins+=(sudo)

# oh-my-zsh updates itself every 13 days without asking; under the p10k instant
# prompt it also stays silent.
zstyle ':omz:update' mode auto

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  PROMPT='%n@%m:%~%# '
fi

# The theme and plugins in the custom folder (powerlevel10k, fzf-tab, autosuggestions,
# syntax highlighting) are git clones that oh-my-zsh's updater skips. The
# autoupdate plugin (TamCore, installed by zsh-setup.sh) pulls them on the same
# 13-day cycle. It is sourced here instead of listed in plugins=() so its
# per-plugin lines go to a log: any output during startup trips the instant
# prompt's warning, and QUIET only hides its header. Ubuntu never sets ZSH_CUSTOM
# and $ZSH_CACHE_DIR only exists once oh-my-zsh has loaded, hence both fallbacks.
ZSH_CUSTOM_AUTOUPDATE_QUIET=true
ZSH_AUTOUPDATE_PLUGIN="${ZSH_CUSTOM:-$ZSH/custom}/plugins/autoupdate/autoupdate.plugin.zsh"
[[ -r "$ZSH_AUTOUPDATE_PLUGIN" ]] &&
    source "$ZSH_AUTOUPDATE_PLUGIN" >>"${ZSH_CACHE_DIR:-$HOME/.cache}/zsh-autoupdate.log" 2>&1
unset ZSH_AUTOUPDATE_PLUGIN

# -----------------------------------------------------------------------------
# ALIASES
# -----------------------------------------------------------------------------
# Editor shortcuts
alias vim="nvim"
alias vi="nvim"
alias vimconfig="nvim ~/.config/nvim/init.lua"
alias zshconfig="vim ~/.zshrc"

# Terminal config shortcuts
alias ohmyzsh="vim ~/.oh-my-zsh"

# Git productivity
today() {
  local day
  day="$(date +%F)" || return
  git log --all --pretty=format:'*%h - %s' --after="$day 00:00" --until="$day 23:59:59" \
    --author="$(git config user.name)" | clipboard_copy
}
yesterday() {
  local day
  day="$(date -d yesterday +%F)" || return
  git log --all --pretty=format:'*%h - %s' --after="$day 00:00" --until="$day 23:59:59" \
    --author="$(git config user.name)" | clipboard_copy
}

# File listing
alias eza='command eza -1 --icons=always'

# Jira sprint views, see `jt -h`
alias jmine='jt -m'   # current sprint, assigned to me
alias jtodo='jt -u'   # current Omni sprint, unassigned and To-Do

# Wiki sync. The server details live in ~/.zshrc.local; bin/notes reads them
# from the environment so none of them appear in this public repo.
alias pull_notes='notes pull'
alias push_notes='notes push'

# Local Pi chat on the 16k qwen2.5-coder (ollama/*.Modelfile). It cannot call
# tools, so they are off; feed it with @file and !command instead. No skills or
# context files either: they would take ~10k of its 16k window.
alias pil='pi --model ollama/qwen2.5-coder:14b-16k --no-tools -ns -nc -np'

# Local Pi agent on Qwen2.5-Coder 14B in LM Studio (pi/models.json). Load it
# with `lms load qwen/qwen2.5-coder-14b --context-length 16384`; the default 8k
# is too small. It can use the built-in tools, but extensions, skills, MCP and
# context files are off: with them Pi sends ~40k tokens before the first message.
alias pilm='pi --model lmstudio/qwen/qwen2.5-coder-14b --models lmstudio/qwen/qwen2.5-coder-14b -ne -ns -np -nc --no-mcp'

# Keep Pi and its extensions current before an interactive start. The updater
# skips subcommands/non-interactive calls, rate-limits successful updates, and
# always lets Pi start if an update fails. Ubuntu installs this helper via install.sh.
# The ECFX team skills (~/.pi/agent/skills-team) are off by default; `pi --team` loads them (D-664).
pi() {
  local -a args
  local a
  for a in "$@"; do
    [[ $a == --team ]] && args+=(--skill "$HOME/.pi/agent/skills-team") || args+=("$a")
  done
  (( $+commands[pi-autoupdate] )) && command pi-autoupdate "${args[@]}"
  command pi "${args[@]}"
}

# Provider-scoped OpenAI session.
alias piopenai='pi --model openai/gpt-6.1-sol --models "openai/*"'

# Better grep
alias grep='command grep --color=auto --exclude-dir=.git'

# Merge requests: run `mrglass`. It is a TUI built from ~/projects/mrglass into
# ~/go/bin (see the PATH entry below), so it needs no alias wrapper.

# -----------------------------------------------------------------------------
# PATH CONFIGURATION
# -----------------------------------------------------------------------------
# User-installed tools. Keep this ahead of the OS path so user-local helpers
# and compatibility shims (fd -> fdfind, bat -> batcat) are available to fzf.
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/bin" "$HOME/.cargo/bin" "$HOME/go/bin" $path)
export PATH

# Preserve Ubuntu's optional RVM/RubyGems setup without assuming it is present.
export GEM_HOME="${GEM_HOME:-$HOME/gems}"
if [[ -r /etc/profile.d/rvm.sh ]]; then source /etc/profile.d/rvm.sh; fi
path=("$GEM_HOME/bin" $path)
export PATH

# Optional local applications. These paths are home-relative and are harmless
# when the application is not installed.
[[ -d "$HOME/.opencode/bin" ]] && path=("$HOME/.opencode/bin" $path)
[[ -d "$HOME/.lmstudio/bin" ]] && path=("$HOME/.lmstudio/bin" $path)
export PATH

# -----------------------------------------------------------------------------
# DEVELOPMENT TOOLS
# -----------------------------------------------------------------------------
# Perl
if (command -v perl && command -v cpanm) >/dev/null 2>&1; then
  test -d "$HOME/perl5/lib/perl5" && eval $(perl -I "$HOME/perl5/lib/perl5" -Mlocal::lib)
fi

# NVM is installed per-user on Linux. Do not assume Homebrew or create a
# fake nvm installation; setup is a no-op when nvm.sh is absent.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# SDKMAN (must be at end for proper initialization)
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# -----------------------------------------------------------------------------
# ADDITIONAL TOOLS
# -----------------------------------------------------------------------------
# Zoxide (better cd)
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# -----------------------------------------------------------------------------
# FZF
# -----------------------------------------------------------------------------
# Ctrl-R fuzzy history, Ctrl-T insert a file path at the cursor, Alt-C cd into
# a subdirectory. Needs fzf >= 0.48 for `fzf --zsh`.
if [[ -o zle && -t 0 && -t 1 ]]; then
  if command -v fzf >/dev/null 2>&1 && fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  else
    for fzf_bindings in /usr/share/doc/fzf/examples/key-bindings.zsh /usr/share/fzf/key-bindings.zsh; do
      if [[ -r "$fzf_bindings" ]]; then source "$fzf_bindings"; break; fi
    done
  fi
  unset fzf_bindings
fi

# fd honours .gitignore, so generated trees stay out without being listed here.
# The explicit excludes are for directories git tracks or ignores per-repo but
# that are never what you are reaching for.
export FZF_DEFAULT_COMMAND='command fd --type f --hidden --follow --exclude .git --exclude node_modules --exclude build --exclude target'
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
  --bind 'ctrl-y:execute-silent(printf %s {2..} | clipboard-copy)+abort'
  --header 'ctrl-y copy | ctrl-/ preview'"

# Alt-C descends into a subdirectory of the current one. zoxide is the
# complement, not a duplicate: `z` jumps to directories already visited, from
# anywhere; Alt-C walks into ones you have never been to.
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git --exclude node_modules'
export FZF_ALT_C_OPTS="--preview 'eza -1 --icons --color=always {}'"

# -----------------------------------------------------------------------------
# FZF-TAB
# -----------------------------------------------------------------------------
# fzf-tab renders zsh's own completion results through fzf. These settings
# are inert until Oh My Zsh and fzf-tab are installed.
if (( $+builtins[zstyle] )); then
  zstyle ':completion:*' menu no
  zstyle ':completion:*:descriptions' format '[%d]'
  if command -v vivid >/dev/null 2>&1; then
    export LS_COLORS="$(vivid generate tokyonight-storm)"
  fi
  [[ -n "${LS_COLORS:-}" ]] && zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
fi

# Per-context previews. $realpath is the candidate as a path, $word as text.
# These are loaded only with Oh My Zsh's completion system.
if (( $+functions[compdef] )); then
  _dev() {
    local -a items
    items=("${(@f)$(dev --complete 2>/dev/null)}")
    _describe 'dev' items
  }
  compdef _dev dev
fi

if (( $+builtins[zstyle] )); then
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --icons --color=always $realpath'
  zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --icons --color=always $realpath'
  zstyle ':fzf-tab:complete:(nvim|vim|vi|bat|cat|less):*' fzf-preview 'bat -n --color=always $realpath'
  zstyle ':fzf-tab:complete:git-(checkout|switch|rebase|merge|log|show):*' \
    fzf-preview 'git log --oneline --graph --color=always $word | head -40'
fi
# `git add` mostly offers untracked paths, and `git diff` prints nothing for
# those — so fall back to the file's contents, and list directories.
if (( $+builtins[zstyle] )); then
  zstyle ':fzf-tab:complete:git-(add|stage|restore|rm):*' fzf-preview \
    'if [[ -d $realpath ]]; then eza -1 --icons --color=always -- $realpath;
     else d=$(git diff --color=always -- $realpath);
       [[ -n $d ]] && print -r -- $d || bat -n --color=always -- $realpath; fi'
  zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview 'ps -p $word -o comm=,args='
fi

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
if (( $+builtins[zstyle] )); then
  zstyle ':fzf-tab:complete:kubectl:*' fzf-flags --preview-window=hidden
  zstyle ':fzf-tab:complete:kubectl:*' fzf-preview \
    'deadline 8 kubectl describe \
       ${${words[(r)(po|pod|pods|deploy|deployment|deployments|svc|service|services|no|node|nodes|ns|namespace|namespaces|cm|configmap|configmaps|secret|secrets|job|jobs|cronjob|cronjobs|ing|ingress|sts|statefulset|statefulsets)]}:-pod} \
       $word 2>/dev/null | head -80'
fi

# docker inspect covers containers and images alike, so one rule serves every
# subcommand. Config.Env is dropped: it is usually the longest section and
# routinely carries credentials, which have no business on screen in a
# completion popup. No deadline — this is a local socket, measured at ~70ms.
if (( $+builtins[zstyle] )); then
  zstyle ':fzf-tab:complete:docker:*' fzf-preview \
    'docker inspect $word 2>/dev/null | jq -C "del(.[].Config.Env)" 2>/dev/null | head -60'
fi

# < and > move between completion groups (local vs remote branches, say).
if (( $+builtins[zstyle] )); then
  zstyle ':fzf-tab:*' switch-group '<' '>'
  zstyle ':fzf-tab:*' use-fzf-default-opts yes
fi

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

# Keep user-local tools available in shells started by interactive programs.
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/bin" $path)
export PATH
