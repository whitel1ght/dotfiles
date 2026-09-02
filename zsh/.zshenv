# ~/.zshenv — sourced for EVERY zsh invocation (interactive, login, and
# non-interactive `zsh -c`). Put env vars that non-interactive tools need here,
# not in .zshrc (which is skipped for non-interactive shells).

# Source machine-local secrets (NOT in this repo) if present — e.g. JIRA_EMAIL /
# JIRA_API_TOKEN for mrglass. Keeps tokens out of version control.
[ -f "$HOME/.config/mrglass/secrets.env" ] && source "$HOME/.config/mrglass/secrets.env"
