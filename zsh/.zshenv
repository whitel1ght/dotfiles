# ~/.zshenv — sourced for EVERY zsh invocation (interactive, login, and
# non-interactive `zsh -c`). Put env vars that non-interactive tools need here,
# not in .zshrc (which is skipped for non-interactive shells).

# No secrets here: they live in ~/.secrets/secrets.env and each tool reads the
# one it needs with $(secret NAME) when it runs, so no shell (and no agent
# started from one) carries a token in its environment.

# Run a command under a hard deadline: `deadline 2 some-command args`.
#
# macOS ships no timeout(1), and kubectl's --request-timeout does not cover
# connection setup, so an fzf preview against an unreachable cluster hangs the
# pane indefinitely. The obvious `perl -e 'alarm N; exec @ARGV'` does not work
# here: alarm survives exec, but the Go runtime ignores SIGALRM when nothing is
# listening for it, and kubectl and docker are both Go. So fork instead and
# signal the child with TERM, then KILL — which Go does honour.
#
# Lives here rather than .zshrc because fzf runs preview commands in a
# non-interactive zsh, which never reads .zshrc.
deadline() {
  perl -e '
    my $secs = shift;
    my $pid = fork // exit 127;
    unless ($pid) { exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "TERM", $pid; kill "KILL", $pid; exit 124 };
    alarm $secs;
    waitpid $pid, 0;
    alarm 0;
    exit $? >> 8;
  ' -- "$@"
}
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
