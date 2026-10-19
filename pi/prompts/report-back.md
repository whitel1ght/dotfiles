---
description: Report this side session's work back to the day session as one inbox message
argument-hint: "[done|progress|handback] [one-line summary]"
---

# /report-back [done|progress|handback] [one-line summary]

Write exactly one inbox message for the day's `/run-day` session to pick up.

1. Gather the facts — one command per call, nothing inferred from the conversation:

```bash
git branch --show-current
git rev-parse --show-toplevel
glab mr view -F json | jq -r '.web_url // empty'
glab mr view -F json | jq -r '.state // empty'
```

2. `KEY` = the branch's ticket key (`git branch --show-current | rg -io '[a-z]+-[0-9]+' | head -1 | tr 'a-z' 'A-Z'`),
   empty when the branch has none.
   `REPO` = `basename $(dirname <toplevel>)` when the path is `…/worktrees/<repo>/<name>`, else `basename <toplevel>`.
   `MR` = the `web_url` printed, `MR_STATE` = the `state` printed (`merged`, `opened`, …); each is
   empty when `glab` fails or there is no MR.
   No key: ask whether this is off-plan work (then the kind is `offplan` and the `"<KEY>"` argument
   is left out) or which key it belongs to. Not inside a repo: the same question, and leave `--repo`
   and `--mr` out.

3. Kind and summary. If the first word of `$ARGUMENTS` is `done`, `progress` or `handback`, it is
   the kind and the rest is the summary. No kind: all of `$ARGUMENTS` is the summary, and the kind
   is `done` when `MR_STATE` is `merged`; otherwise (open MR, no MR, `glab` failed) ask the user
   **one** question, `done | progress | handback`, and wait. Never guess the kind from what you did.
   No summary: ask the user for one line and wait.
   An explicit kind with no key still goes to `day-note` with that kind: without a key a
   `handback` cannot put an item back in the queue, so the day session only logs it.

4. `PROJECT` from the repo: `ecfx-*` → `ecfx`, an epicmax repo → `epicmax`, otherwise ask
   (`personal` is the other choice). A `KEY` starting `ECFX-` already means `ecfx`, so ask only
   for a repo that is not clearly one of these.

5. Write it with `day-note`. The kind is always passed explicitly. The summary goes in a quoted
   heredoc, exactly as written, never on the command line:

```bash
SUMMARY=$(cat <<'EOF'
<the summary exactly as given, any characters>
EOF
)
FILE="$(~/.local/bin/day-note --kind <kind> --project <project> --repo <repo> --mr <url> --session <KEY> -- "<KEY>" "$SUMMARY")"
```

   No key: drop the `"<KEY>"` argument and use `--session pi`. Leave `--mr` out when `MR` is empty,
   `--repo` out when `REPO` is empty. `--` ends the options, so a summary starting with `-` is never
   read as one. `day-note` records the summary as the log paragraph: a decision or state change
   worth keeping goes into the summary. If `day-note` fails, show its message and stop.
   `$FILE` is the path `day-note` printed — never go looking for the newest file in the inbox.

6. There is no session messaging in pi: the inbox file **is** the record, and `/run-day` reads it on
   its next inbox pass. Do not try to notify the day session.

Finish with one line: the kind, the key, the file name (`basename "$FILE"`) — and for `handback`, that the day session
will re-queue the item.
