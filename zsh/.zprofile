# Added by Docker Desktop, which writes into ~/.zprofile — a symlink into this
# repo, so it edited a versioned file directly. Rewritten $HOME-relative: Docker
# hardcodes the absolute path, which does not port to another machine or user.
# Docker may re-add its own block on a future launch; delete the duplicate.
export PATH="$PATH:$HOME/.docker/bin"

eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/usr/local/opt/ruby/bin:$PATH"


# Added by Toolbox App
export PATH="$PATH:/usr/local/bin"

