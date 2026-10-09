---
description: Tell the /run-day session what you did on a ticket by leaving an inbox message, and nudge it if it is running
argument-hint: [done|progress|handback] [one-line summary]
allowed-tools: Bash(day-note:*), Bash(git:*), Bash(glab mr view:*), Bash(ls:*), Bash(date:*), Bash(basename:*), Bash(dirname:*), Read
---

# Report back to the day session

Arguments: $ARGUMENTS

1. Kind and summary. If the first word of the arguments is `done`, `progress` or `handback`, it is the kind and the rest is the summary. With no kind (step 2 comes first for the MR state): when the arguments are empty and `glab mr view` shows the MR `merged`, or the user confirms the work is finished, the kind is `done`; otherwise ask the user one question, `done`, `progress` or `handback`, and wait. Never infer the kind from the conversation. With no summary, ask the user for one line and wait.
2. Infer the rest from the current directory:

```bash
BRANCH="$(git branch --show-current 2>/dev/null)"
KEY="$(printf '%s' "$BRANCH" | rg -io '[a-z]+-[0-9]+' | head -1 | tr a-z A-Z)"
TOP="$(git rev-parse --show-toplevel 2>/dev/null)"
case "$TOP" in */worktrees/*/*) REPO="$(basename "$(dirname "$TOP")")" ;; *) REPO="$(basename "$TOP")" ;; esac
MR="$(glab mr view -F json 2>/dev/null | jq -r '.web_url // empty')"
```

   No key: ask whether this is off-plan work (then the kind is `offplan` and the KEY argument is left out) or which key it is. Not a git repository: same question, and leave `--repo` and `--mr` out.
3. Write the message. The kind is always passed explicitly. Leave `--mr` out when `$MR` is empty, `--repo` out when `$REPO` is empty:

```bash
FILE="$(day-note --kind <kind> --repo "$REPO" --mr "$MR" --session "$KEY (claude)" "$KEY" "<summary>")"
```

   Leave the `"$KEY"` argument out when there is no key (off-plan work). `day-note` records the summary as the log paragraph; a decision or state change worth keeping goes into the summary. If it fails, show its message and stop: there is no message to announce, so nothing else runs.
4. The file is the path `day-note` printed: `$FILE`, its name is `$(basename "$FILE")`. Never search the inbox for the newest file.
5. Nudge the day session. If the `ListAgents` and `SendMessage` tools are available (load `SendMessage` with ToolSearch if it is deferred) and `ListAgents` lists a session named `day-$(date +%F)`, send it the text `inbox: <file name>` (`basename` of `$FILE`). Skip the nudge silently, with no error and no mention, when either tool is missing, the day session is not listed, or the send fails. The inbox file is the record; the nudge only wakes the day session, which also finds the file on its next event or through the mod's 30 s inbox listing.
6. Say in one line what was reported: kind, key, file name. For `handback`, add that the day session will put the item back in its queue.
