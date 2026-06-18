# ~/.zshenv — sourced for EVERY zsh invocation (interactive, login, and
# non-interactive `zsh -c`). Put env vars that non-interactive tools need here,
# not in .zshrc (which is skipped for non-interactive shells).

# Bypass the local NekoBox proxy (127.0.0.1:2080) for GitLab. The proxy
# intermittently resets connections mid-TLS-handshake (SSL_ERROR_SYSCALL / EOF)
# and adds ~300ms latency; the direct path to gitlab.com is clean and faster.
# Appended so it composes with any no_proxy injected by launchd/NekoBox.
export NO_PROXY="${NO_PROXY:+$NO_PROXY,}gitlab.com,.gitlab.com"
export no_proxy="${no_proxy:+$no_proxy,}gitlab.com,.gitlab.com"
