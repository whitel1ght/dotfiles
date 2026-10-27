# The drill window's hook: `drills window` sources it after ~/.zshrc. Every line typed goes to
# `drills step` before it can run; only a right line for a run-yes drill runs. 5 goals or
# $DRILLS_ROUND_SECONDS (300) end the window.

# line → prints the verdict (accept, clear, accept-exit or clear-exit), then the message
_drill_handle() {
  local out action done
  out="$("${DRILLS_CMD:-drills}" step -- "$1" 2>/dev/null)" || { print clear; print "drills: step failed"; return }
  action="$(jq -r '.action' <<<"$out" 2>/dev/null)"
  done="$(jq -r '.done' <<<"$out" 2>/dev/null)"
  local verdict=clear
  [[ $action == run ]] && verdict=accept
  [[ $done == true ]] && verdict="$verdict-exit"
  print -r -- "$verdict"
  jq -r '.message // empty' <<<"$out" 2>/dev/null
}

_drill_end() {
  "${DRILLS_CMD:-drills}" finish >/dev/null 2>&1
  sleep 2
  exit
}

# verdict, message → print it now; for a line that runs, only the mark, the rest after its output
_drill_say() {
  if [[ $1 == accept* ]]; then
    print -r -- "${2%%$'\n'*}"
    [[ $2 == *$'\n'* ]] && _drill_after="${2#*$'\n'}"
  else
    print -r -- "$2"
  fi
}

_drill_accept_line() {
  [[ -z ${BUFFER//[[:space:]]/} ]] && { zle .accept-line; return }
  local out verdict
  out="$(_drill_handle "$BUFFER")"
  verdict="${out%%$'\n'*}"
  zle -I
  _drill_say "$verdict" "${out#*$'\n'}"
  [[ $verdict == *-exit ]] && _drill_exit_after=1
  [[ $verdict == accept* ]] || BUFFER=""
  zle .accept-line
}

_drill_precmd() {
  [[ -n ${_drill_after:-} ]] && { print -r -- "$_drill_after"; _drill_after="" }
  (( ${_drill_exit_after:-0} )) && _drill_end
}

TRAPALRM() { print; print "Time's up."; _drill_end }

if [[ -o zle ]]; then
  # every widget that runs the buffer goes through the check, not only Enter's
  for w in accept-line accept-and-hold accept-line-and-down-history accept-and-infer-next-history; do
    zle -N "$w" _drill_accept_line
  done
  unset w
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _drill_precmd
  TMOUT=${DRILLS_ROUND_SECONDS:-300}
fi
