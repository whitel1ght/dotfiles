---
description: Tell the /run-day session what you did on a ticket by leaving an inbox message, and nudge it if it is running
argument-hint: [done|progress|handback] [one-line summary]
allowed-tools: Bash(day-note:*), Bash(git:*), Bash(glab mr view:*), Bash(jq:*), Bash(rg:*), Bash(tr:*), Bash(head:*), Bash(printf:*), Bash(cat:*), Bash(ls:*), Bash(date:*), Bash(basename:*), Bash(dirname:*), Read
---

# Report back to the day session

Arguments: $ARGUMENTS

1. Infer from the current directory, one command per call (each is covered by `allowed-tools`):

```bash
git branch --show-current
git rev-parse --show-toplevel
glab mr view -F json | jq -r '.web_url // empty'
```

   KEY: pipe the branch through `rg -io '[a-z]+-[0-9]+' | head -1 | tr a-z A-Z` (`printf '%s' "<branch>" | rg ...`); empty when the branch has no ticket key. REPO: when the toplevel path matches `.../worktrees/<repo>/<name>`, `<repo>` is `basename "$(dirname <toplevel>)"`, otherwise `basename <toplevel>`. MR: the `web_url` printed, empty when `glab` fails or there is no MR.
   No key: ask whether this is off-plan work (then the kind is `offplan` and the KEY argument is left out) or which key it is. Not a git repository: same question, and leave `--repo` and `--mr` out.
2. Kind and summary. If the first word of the arguments is `done`, `progress` or `handback`, it is the kind and the rest is the summary. No kind means `progress`, and all the arguments are the summary; `done` is used only when the user asks for it explicitly. Never infer the kind from the conversation or the MR state. With no summary, ask the user for one line and wait. An explicit kind with no key still goes to `day-note` with that kind: without a key a `handback` cannot put an item back in the queue, so the day session only logs it.
3. Write the message. The kind is always passed explicitly. Leave `--mr` out when the MR is empty, `--repo` out when the repo is empty. Pass the summary through a quoted heredoc so backticks, `$` and quotes in it are never interpreted by the shell:

```bash
SUMMARY=$(cat <<'EOF'
<summary text exactly as written, any characters>
EOF
)
FILE="$(day-note --kind <kind> --repo <repo> --mr <mr url> --session <KEY> "$KEY" "$SUMMARY")"
```

   Substitute the inferred values for `<repo>`, `<mr url>` and `<KEY>` (plain words, safe unquoted), and write the key itself in place of `"$KEY"`. Leave the `"$KEY"` argument out when there is no key (off-plan work) and use `--session claude` instead of `--session <KEY>`. Never place the summary text itself on the `day-note` line: only `"$SUMMARY"` expands it. `day-note` records the summary as the log paragraph; a decision or state change worth keeping goes into the summary. If it fails, show its message and stop: there is no message to announce, so nothing else runs.
4. The file is the path `day-note` printed: `$FILE`, its name is `$(basename "$FILE")`. Never search the inbox for the newest file.
5. Nudge the day session. If the `ListAgents` and `SendMessage` tools are available (load `SendMessage` with ToolSearch if it is deferred) and `ListAgents` lists a session named `day-$(date +%F)`, send it the text `inbox: <file name>` (`basename` of `$FILE`). Skip the nudge silently, with no error and no mention, when either tool is missing, the day session is not listed, or the send fails. The inbox file is the record; the nudge only wakes the day session, which also finds the file on its next event or through the mod's 30 s inbox listing.
6. Say in one line what was reported: kind, key, file name. For `handback`, add that the day session will put the item back in its queue.
