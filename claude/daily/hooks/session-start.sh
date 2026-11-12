#!/usr/bin/env bash
# SessionStart: re-inject today's /run-day context (compact|resume), and the standing directions
# learned from earlier days plus the system map (every start; `session-start.sh directions` is
# those two only). Silent when there is none. A missing friction-ledger, directions file or map
# injects nothing.
set -euo pipefail

STATE_DIR="${RUN_DAY_STATE_DIR:-$HOME/.local/state/run-day}"
WIKI="${WIKI_DIR:-$HOME/wiki}"
TODAY="${RUN_DAY_DATE:-$(date +%F)}"
STATE="$STATE_DIR/$TODAY.md"
DIARY="$WIKI/diary/$TODAY.md"
MAX_CHARS=6000
BLOCK_MAX=3000
AGENT_MAX=2000
AGENT_MARK="[agent notes truncated: run day-agent show]"
AGENT_FILE="$WIKI/diary/.agent/$TODAY.md"
# Claude Code drops additionalContext past ~10k characters. The run context (at most MAX_CHARS)
# always goes in whole; the map takes what is left, then the directions; each cut is marked.
TOTAL_MAX=9000
CUT_MARK="
(cut)"

# Codepoint-safe cut regardless of locale.
cut_chars() { printf '%s' "$1" | jq -Rrs --argjson n "$2" '.[:$n]'; }
len() { printf '%s' "$1" | jq -Rrs 'length'; }

# line_cut <text> <n>: the text if it has n characters or fewer, else its leading whole lines within n.
line_cut() {
  printf '%s' "$1" | jq -Rrs --argjson n "$2" 'if length <= $n then . else (.[:$n + 1]) as $h | if ($h | test("\n")) then ($h | sub("\n[^\n]*$"; "")) else "" end end'
}

# fit <text> <room>: the text if it fits, else its head and the cut mark, else nothing.
fit() {
  if [ "$(len "$1")" -le "$2" ]; then
    printf '%s' "$1"
  elif [ "$2" -gt "${#CUT_MARK}" ]; then
    printf '%s%s' "$(cut_chars "$1" $(($2 - ${#CUT_MARK})))" "$CUT_MARK"
  fi
}

# emit <run context>: the hook JSON with the run context, then what fits of the directions and
# the map; nothing at all when all three are empty.
emit() {
  local room map_part dir_part c
  room=$((TOTAL_MAX - $(len "$1")))
  map_part="$(fit "$map_text" "$room")"
  room=$((room - $(len "$map_part")))
  dir_part="$(fit "$dir_text" "$room")"
  c="$1$dir_part$map_part"
  [ -n "$1" ] || c="${c#
}"
  [ -n "$c" ] || return 0
  jq -n --arg c "$c" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
}

FRICTION_LEDGER_BIN="${FRICTION_LEDGER_BIN:-$(command -v friction-ledger 2>/dev/null || echo "$HOME/.local/bin/friction-ledger")}"
dir_text=""
if [ -x "$FRICTION_LEDGER_BIN" ]; then
  directions="$("$FRICTION_LEDGER_BIN" directions render 2>/dev/null || true)"
  [ -z "$directions" ] || dir_text="

## Standing directions
Rules the user gave in earlier sessions, active until retired. Follow them.
$directions"
fi

# The map is cut to 3072 bytes (iconv drops a split trailing character).
SYSTEM_MAP="${SYSTEM_MAP:-$WIKI/work/system/map.md}"
map_text=""
if [ -f "$SYSTEM_MAP" ]; then
  map="$(head -c 3072 "$SYSTEM_MAP" 2>/dev/null | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || true)"
  # The map's own "# …" title would repeat the heading it is wrapped in.
  case "$map" in "# "*) case "$map" in *$'\n'*) map="${map#*$'\n'}" ;; *) map="" ;; esac ;; esac
  [ -z "${map//[[:space:]]/}" ] || map_text="

## System map
$map"
fi

if [ "${1:-}" = directions ] || [ ! -f "$STATE" ]; then
  emit ""
  exit 0
fi

pending=0
if [ -d "$STATE_DIR/inbox" ]; then
  pending="$(find "$STATE_DIR/inbox" -maxdepth 1 -type f -name '[0-9]*T[0-9]*-*-????.md' | wc -l | tr -d ' ')"
fi
inbox_line=""
if [ "$pending" -gt 0 ]; then
  inbox_line="
$pending pending inbox message(s) in $STATE_DIR/inbox: process them first (run-day.md, section 7)."
fi

# Buffered: an unterminated start marker yields no block rather than the rest of the diary.
block=""
if [ -f "$DIARY" ]; then
  block="$(awk '/^<!-- start-day:start -->/{f=1;buf="";next} /^<!-- start-day:end -->/{if(f){printf "%s", buf; f=0};next} f{buf=buf $0 "\n"}' "$DIARY")"
fi

head_text="A /run-day session is active for $TODAY. Playbook: ${CLAUDE_PLUGIN_ROOT:-the daily plugin}/commands/run-day.md (re-read it before acting on events).
Write rules: subagents never write ~/wiki, except ~/wiki/work/system/ and ~/wiki/tools/ when they change a system repo (dotfiles, decisions, articles), committed with wiki-commit; only this session writes diary markers, ~/wiki/work/projects/<p>/log entries and decisions; /end-day consolidates state.md.
owner=external:KEY in the run state means that item is in a side session: never dispatch it or start a review round for it.$inbox_line"
state_text="

## Run state ($STATE)
$(cat "$STATE")"
block_head="

## Diary plan block ($DIARY)
"

# Run state is the tail and must survive: trim the diary block first, the state only as a last resort.
room=$((MAX_CHARS - $(len "$head_text") - $(len "$state_text") - $(len "$block_head") - 40))
[ "$room" -gt "$BLOCK_MAX" ] && room=$BLOCK_MAX
if [ "$room" -le 0 ]; then
  block=""
  state_text="$(cut_chars "$state_text" $((MAX_CHARS - $(len "$head_text"))))"
elif [ "$(len "$block")" -gt "$room" ]; then
  block="$(cut_chars "$block" "$room")
[plan block truncated]"
fi

# The agent notes come after the plan block and are cut first: they take what MAX_CHARS leaves.
agent_text=""
if [ -f "$AGENT_FILE" ]; then
  notes="$(<"$AGENT_FILE")"
  if [ -n "${notes//[[:space:]]/}" ]; then
    agent_head="

## Agent notes ($AGENT_FILE)
"
    avail=$((MAX_CHARS - $(len "$head_text$block_head$block$state_text")))
    room=$((avail - $(len "$agent_head")))
    [ "$room" -gt "$AGENT_MAX" ] && room=$AGENT_MAX
    if [ "$(len "$notes")" -le "$room" ]; then
      agent_text="$agent_head$notes"
    else
      room=$((room - ${#AGENT_MARK} - 1))
      kept=""
      [ "$room" -lt 100 ] || kept="$(line_cut "$notes" "$room")"
      if [ -n "$kept" ]; then
        agent_text="$agent_head$kept
$AGENT_MARK"
      elif [ "$avail" -ge $((${#AGENT_MARK} + 1)) ]; then
        agent_text="
$AGENT_MARK"
      fi
    fi
  fi
fi

ctx="$head_text$block_head$block$agent_text$state_text"

emit "$(cut_chars "$ctx" "$MAX_CHARS")"
