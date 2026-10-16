#!/usr/bin/env bash
# SessionStart: re-inject today's /run-day context (compact|resume), and the standing directions
# learned from earlier days (every start; `session-start.sh directions` is the directions only).
# Silent when there is neither. A missing friction-ledger or directions file injects nothing.
set -euo pipefail

STATE_DIR="${RUN_DAY_STATE_DIR:-$HOME/.local/state/run-day}"
WIKI="${WIKI_DIR:-$HOME/wiki}"
TODAY="${RUN_DAY_DATE:-$(date +%F)}"
STATE="$STATE_DIR/$TODAY.md"
DIARY="$WIKI/diary/$TODAY.md"
MAX_CHARS=6000
BLOCK_MAX=3000

FRICTION_LEDGER_BIN="${FRICTION_LEDGER_BIN:-$(command -v friction-ledger 2>/dev/null || echo "$HOME/.local/bin/friction-ledger")}"
dir_text=""
if [ -x "$FRICTION_LEDGER_BIN" ]; then
  directions="$("$FRICTION_LEDGER_BIN" directions render 2>/dev/null || true)"
  [ -z "$directions" ] || dir_text="

## Standing directions
Rules the user gave in earlier sessions, active until retired. Follow them.
$directions"
fi

if [ "${1:-}" = directions ] || [ ! -f "$STATE" ]; then
  [ -n "$dir_text" ] || exit 0
  jq -n --arg c "${dir_text#
}" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
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

# Codepoint-safe cut regardless of locale.
cut_chars() { printf '%s' "$1" | jq -Rrs --argjson n "$2" '.[:$n]'; }
len() { printf '%s' "$1" | jq -Rrs 'length'; }

head_text="A /run-day session is active for $TODAY. Playbook: ${CLAUDE_PLUGIN_ROOT:-the daily plugin}/commands/run-day.md (re-read it before acting on events).
Write rules: subagents never write ~/wiki; only this session writes diary markers, ~/wiki/work/projects/<p>/log entries and decisions; /end-day consolidates state.md.
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

ctx="$head_text$block_head$block$state_text"

jq -n --arg c "$(cut_chars "$ctx" "$MAX_CHARS")$dir_text" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
