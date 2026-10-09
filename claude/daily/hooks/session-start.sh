#!/usr/bin/env bash
# SessionStart (compact|resume): re-inject today's /run-day context. Silent when no run is active.
set -euo pipefail

STATE_DIR="${RUN_DAY_STATE_DIR:-$HOME/.local/state/run-day}"
WIKI="${WIKI_DIR:-$HOME/wiki}"
TODAY="${RUN_DAY_DATE:-$(date +%F)}"
STATE="$STATE_DIR/$TODAY.md"
DIARY="$WIKI/diary/$TODAY.md"
MAX_CHARS=6000

[ -f "$STATE" ] || exit 0

pending=0
if [ -d "$STATE_DIR/inbox" ]; then
  pending="$(find "$STATE_DIR/inbox" -maxdepth 1 -type f -name '[0-9]*T[0-9]*-*-????.md' | wc -l | tr -d ' ')"
fi
inbox_line=""
if [ "$pending" -gt 0 ]; then
  inbox_line="
$pending pending inbox message(s) in $STATE_DIR/inbox: process them first (run-day.md, section 7)."
fi

block=""
if [ -f "$DIARY" ]; then
  block="$(awk '/<!-- start-day:start -->/{f=1;next} /<!-- start-day:end -->/{f=0} f' "$DIARY")"
fi

ctx="A /run-day session is active for $TODAY. Playbook: ${CLAUDE_PLUGIN_ROOT:-the daily plugin}/commands/run-day.md (re-read it before acting on events).
Write rules: subagents never write ~/wiki; only this session writes diary markers, ~/wiki/projects/<p>/log entries and decisions; /end-day consolidates state.md.
owner=external:KEY in the run state means that item is in a side session: never dispatch it or start a review round for it.$inbox_line

## Diary plan block ($DIARY)
$block

## Run state ($STATE)
$(cat "$STATE")"

jq -n --arg c "${ctx:0:$MAX_CHARS}" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
