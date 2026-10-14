---
description: Hand one in-flight item to a side session — write the hand-off note, mark the run state external, tell the user how to pick it up
argument-hint: <KEY>
---

# /handoff <KEY>

Move an item out of this day's session so a side session can finish it, without losing context.
Writes the hand-off note, the run state and the diary — asks nothing.

Stop when any of these hold, and say which:

- no run-state line for `<KEY>` in `~/.local/state/run-day/$(date +%F).md` (there is no active run)
- the line already has `owner=external:` (already handed off)
- `worktree=-` (nothing was dispatched; there is no work to hand over)

1. Collect progress from the worktree on that line — one command per call, no invented facts:

```bash
W=<worktree>
git -C "$W" branch --show-current
git -C "$W" log --oneline @{upstream}..HEAD 2>/dev/null || git -C "$W" log --oneline -10
git -C "$W" diff --stat
git -C "$W" status --short
```

2. Stop the delegate if one is still running: `acp_delegate_cancel({runId:<run id from the run state>})`. A cancelled run keeps its output files, so quote what it finished in the hand-off note.

3. Write `~/.local/state/run-day/handoff/<KEY>.md`, exactly this shape:

```markdown
# Hand-off: <KEY> — <one-line summary>

Handed off: <ISO timestamp>
Repo: <repo>
Worktree: <path>
Branch: <branch>
MR: <url or ->

## Original brief

<the filled brief from ~/.local/state/run-day/scratch/brief-<key>.md, verbatim; if it is gone, the plan line and the ticket description>

## Progress so far

<what the collected git output actually shows: commits, dirty files, test state>

## Open questions

<what the side session must decide or find out; "none" only if there are none>
```

4. Update the run-state line for `<KEY>`: `agent=-`, `needs_you=no`, `owner=external:<KEY>`. Leave every other field.

5. Diary: set the item to `[/]` with ` · with you: <KEY>` as the first evidence on the line, then
   `~/.local/bin/diary-links ~/wiki/diary/$(date +%F).md`.

6. Print the pickup command for the user:

```
cd <worktree> && pi -n <KEY> "/pickup"
```
