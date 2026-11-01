# ~/.zshenv — sourced for EVERY zsh invocation (interactive, login, and
# non-interactive `zsh -c`). Put env vars that non-interactive tools need here,
# not in .zshrc (which is skipped for non-interactive shells).

# Source machine-local secrets (NOT in this repo) if present — e.g. JIRA_EMAIL /
# JIRA_API_TOKEN for mrglass. Keeps tokens out of version control.
[ -f "$HOME/.config/mrglass/secrets.env" ] && source "$HOME/.config/mrglass/secrets.env"

# Run a command under a hard deadline: `deadline 2 some-command args`.
#
# The standard timeout(1) command does not consistently bound all child
# processes used by preview commands. Fork and signal the child with TERM then
# KILL so Go tools such as kubectl and docker also stop.
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
[[ -r "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
