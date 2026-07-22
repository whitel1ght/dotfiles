---
name: ecfx-daily-commits
description: Use when the user asks for a list, report, or summary of today's commits (or another day's commits) across ecfx- projects — e.g. "what did I do today", "collect today's commits", "daily work report".
---

# ecfx Daily Commits

## Overview

Produce the user's daily commit list across all `~/projects/ecfx-*` repos — including nested checkouts like `ecfx-dashboard/src/protobufs` — by running the bundled script and printing its output verbatim.

## How to Use

```bash
~/.claude/skills/ecfx-daily-commits/collect.sh                # today
~/.claude/skills/ecfx-daily-commits/collect.sh "yesterday 00:00" "today 00:00"   # yesterday
~/.claude/skills/ecfx-daily-commits/collect.sh "2026-07-01 00:00"                # since a date
```

## Output Contract

The reply IS the script's output, byte-for-byte: plain repo-name headers (no bold, no heading markup), no intro line before the first header, no reformatting. One section per repo with commits, oldest first —

```
ecfx-backend

- c2179fa06 — feat(ECFX-14575): add InboxItem.canReprocess() eligibility guard
- 015e9d9de — feat(ECFX-14575): add manual marker column to inbox_item_process_job

ecfx-protobufs (via ecfx-dashboard/src/protobufs)

- 64fc2de — feat(ECFX-14575): add InboxItem.reprocessable and Firm.allow_user_reprocessing_of_failed_items
```

Commits authored under a different name spelling carry `(authored as …)` — the script handles this. Repos with no commits are omitted. If the script prints nothing, reply exactly: `No commits in ecfx- projects for that period.`

After the list, add at most one short line if something needs the user's attention (e.g. a commit that exists only in a nested checkout and isn't pushed). No tables, no per-repo summaries, no narrative.

## Notes

- The script searches **all branches, remotes, and tags** (stashes excluded) and matches author `Mamyr` (covers both "Dmitry Mamyrev" and "Dzmitry Mamyrau").
- Nested repos are discovered up to 4 levels deep (`.git` dir or gitfile), skipping `node_modules`.
- For a custom scope (different author, non-ecfx projects), adapt the script's variables rather than reformatting its output by hand.
