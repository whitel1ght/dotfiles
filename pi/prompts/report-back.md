---
description: Report this side session's work back to the day session as one inbox message
argument-hint: [done|progress|handback]
---

# /report-back [done|progress|handback]

Write exactly one inbox message for the day's `/run-day` session to pick up. Ask at most one question.

1. Gather the facts — one command per call, nothing inferred from the conversation:

```bash
git branch --show-current
git rev-parse --show-toplevel
glab mr view -F json | jq -r .web_url
glab mr view -F json | jq -r .state
```

2. `KEY` = the branch's ticket key (`git branch --show-current | rg -io '[a-z]+-[0-9]+' | head -1 | tr 'a-z' 'A-Z'`).
   `REPO` = `basename $(dirname <toplevel>)` when the path is `…/worktrees/<repo>/<name>`, else `basename <toplevel>`.
   No key, or not inside a repo: ask whether this is `offplan` or which key it belongs to.

3. `kind` = `$1` when it is `done|progress|handback`; else `done` when the MR state is `merged`;
   else ask **one** question. Never guess it from what you did.

4. `PROJECT` from the repo: `ecfx-*` → `ecfx`, an epicmax repo → `epicmax`, otherwise ask
   (`personal` is the other choice).

5. Write it with `day-note` — the summary goes in a heredoc, never on the command line:

```bash
SUMMARY=$(cat <<'EOF'
<what changed, what is verified, what is left — plain prose, no bullet theatre>
EOF
)
FILE="$(~/.local/bin/day-note --kind <kind> --project <project> --repo <repo> --mr <url> --session <KEY> -- "<KEY>" "$SUMMARY")"
```

   No key: drop the `"<KEY>"` argument and use `--session pi`. `--` ends the options.
   `$FILE` is the path `day-note` printed — never go looking for the newest file in the inbox.

6. There is no session messaging in pi: the inbox file **is** the record, and `/run-day` reads it on
   its next inbox pass. Do not try to notify the day session.

Finish with one line: the kind, the key, the file name — and for `handback`, that the day session
will re-queue the item.
