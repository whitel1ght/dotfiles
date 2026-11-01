# Linux login-shell environment. Keep PATH entries home-relative and portable.
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/bin" "$HOME/.cargo/bin" "$HOME/go/bin" $path)
export PATH
