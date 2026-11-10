# kubectl guard, sourced from .zshrc. A bare kubectl whose current context is a prod one is
# refused: production takes an explicit --context, so a command typed for dev01 never lands on
# prod01 because the kubeconfig drifted. Lines that name --context, and the subcommands that
# only read or change the kubeconfig itself, pass straight through. Interactive shells only;
# scripts and agents call the binary.

kubectl() {
  local arg ctx
  for arg in "$@"; do
    [[ $arg == --context || $arg == --context=* ]] && { command kubectl "$@"; return }
  done
  case $1 in
    config|completion|version|help|--help|-h|"") command kubectl "$@"; return ;;
  esac
  ctx="$(command kubectl config current-context 2>/dev/null)"
  if [[ $ctx == *prod* ]]; then
    print -u2 -r -- "kubectl: the current context is $ctx. Name it to run there: kubectl --context $ctx $*"
    print -u2 -r -- "         or switch away: kubectx dev01"
    return 1
  fi
  command kubectl "$@"
}

# k9s on production, with every modifying action disabled.
alias k9prod='k9s --context prod01 --readonly'
