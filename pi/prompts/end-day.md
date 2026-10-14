---
description: Standup report of the day's work across commits, MRs, Jira and sessions, filed in the diary
argument-hint: "[yesterday | YYYY-MM-DD]"
---

Collect the day's work:

```bash
SESSIONS=pi ~/.local/bin/end-day collect $ARGUMENTS
```

The digest has four sections: commits, GitLab activity (each MR marked as mine or a
review for someone else), Jira status changes, and pi sessions (my prompts and each
session's last replies). A line in brackets means that source was unavailable; mention it
in one line at the end of the report rather than guessing its contents.

## Write the report

Write for a teammate at standup: someone who knows the product but wasn't in my
sessions. They care about outcomes, not mechanics. So "Export keeps the column order
users set (backend and dashboard MRs up for review)" rather than "address review round 3
(O3, N9, N10)".

Use this shape, and leave out any section that would be empty. The report opens with a
standup summary (always present), then the sections:

```markdown
**Standup**
Merged ECFX-1001 (backend!6613, tickets In QA). ECFX-1003 is in review on both repos.
Bulk archive (ECFX-1007) waits on product to decide whether it notifies clients. Tomorrow:
start on the ECFX-1004 calendar fix.

**Done**
- ECFX-1001 CSV export keeps column order — merged, ticket In QA
- Reviewed @alice's ECFX-1002 audit-log MR — approved

**In progress**
- ECFX-1003 Rate-limit webhook retries — backend and dashboard MRs open; review addressed
- ECFX-1004 Timezone bug on the calendar — root cause found, fix not started

**Picked up**
- ECFX-1005, ECFX-1006 — moved to In Progress

**Blocked / waiting**
- ECFX-1007 Bulk archive — waiting on product to decide whether it notifies clients
```

These tickets are made up to show the shape. Every line you write must come from the
digest.

The **Standup** paragraph is what I paste into the standup thread:

- One paragraph, at most 5 sentences, plain text after the `**Standup**` line.
- Highlight what matters, not a rewrite of the list: what shipped or merged (ticket keys
  and MR ids as plain text, like `backend!6613`), what is in flight and its state,
  blockers or anything waiting on others, key decisions, and the first focus for
  tomorrow. Skip routine items.
- No markdown links in the paragraph (`diary-links` would add trailing refs to it), no
  bullets, no headings, no emoji.

How to get there:

- **One line per ticket**, merging everything about it from all four sources: several
  commits, an MR in three repos and two sessions become one line. Lead with the ticket key
  and a plain-language name for the work, then the state it ended the day in.
- **Done** means something finished: an MR merged, a ticket moved to In QA or Done, a
  review given, a question answered or a decision made. **In progress** is everything
  else that moved forward. **Picked up** is a ticket that only moved to In Progress, with
  nothing else yet. **Blocked / waiting** is anything waiting on a person, a release or a
  decision. My prompts and the sessions' replies are the best evidence for this.
- **Account for every ticket.** Before writing, list every ticket key in the digest,
  across all four sections. Each one must end up in a line, or be one you dropped as
  noise on purpose. A ticket with activity in several repos is easy to under-report:
  check each of its MRs, because one may have merged while another opened.
- **Work without a ticket** counts too: investigations, proposals, write-ups, tooling,
  tickets filed, answers to someone's question. Name what came out of it. Local reviews
  I ran on my own MRs belong in that ticket's line, as what they found, not as separate
  lines.
- **Leave out the noise:** merge commits, formatting fixes, and a session that only ran
  this report or small talk. Review-round numbers and finding IDs belong in the MR, not
  here.
- Keep each line under about 20 words. A normal day is 5–12 lines in total.

## File it

Print the report in the chat, then save the same text into the diary, Standup first. Use a quoted
heredoc so nothing in the report gets expanded:

```bash
~/.local/bin/end-day save $ARGUMENTS <<'REPORT'
<the report>
REPORT
```

`save` replaces the block it wrote on an earlier run and never touches my own lines, so
running it again the same day is safe. When the diary already has a `<!-- daily-report:start -->`
block for the day, read it first and build on it: keep every Done line that carries an MR link
or other evidence, and only add new material or move a line forward. Never regress a line, for
example `Done` to `In progress`, because this run's digest is thinner than the earlier one.
When that block already has a `**Standup**` paragraph, rewrite it for the whole day rather
than appending. Note the path it printed, then continue with the next section.

## Consolidate memory

Skip this step, and say so in one line, when `~/wiki/projects` does not exist or the day has
no log entries below (the commit and the end of the run still happen). It is the only place
project `state.md` files change; during the day `/run-day` only appends logs and decisions.

Find which projects were touched — `end-day touched` prints one project name per line, the
projects with a `## <day> <title>` log entry or a decision dated `<day>`; empty output means
none:

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
~/.local/bin/end-day touched "$DAY"
```

For each project `<p>` it prints:

1. Read `~/wiki/projects/<p>/state.md`, the day's log entries
   (`~/.local/bin/end-day entries "$DAY" <p>`), the decisions dated that day
   (`rg -l "^date: $DAY" ~/wiki/projects/<p>/decisions`), and the `<p>:` lines under `notes:` in
   `~/.local/state/run-day/$DAY.md` if it exists (the `state_change` lines `/run-day` collected).
2. Rewrite `state.md` in full from the old state plus those: current focus, open threads (drop
   what finished, add what started), links to existing notes. Keep the file's frontmatter and
   headings, set its `date` to `$DAY`, and keep it at **60 lines or fewer** (`wc -l` it). It is a
   snapshot, not a history: history lives in the log.
3. If the project's one-line focus changed, update its line in the `## Long-term memory (projects)`
   section of `~/wiki/index.md` (edit only that section).

## Commit and end the run

This always runs, even when the memory step was skipped: the report and the diary edits still get
committed. Set `DAY` again here (new shell):

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
qmd update && qmd embed
git -C ~/wiki add -A -- diary projects index.md
[ -d ~/wiki/reviews ] && git -C ~/wiki add -A -- reviews
git -C ~/wiki diff --cached --quiet || git -C ~/wiki commit -m "wiki: $DAY day"
```

If `qmd` fails, say so in one line and still commit. Never touch `*.pdf` or `*.kdbx`.

Then end the run: move `~/.local/state/run-day/$DAY.md` into `~/.local/state/run-day/done/`
(create the directory). That switches off the run-state injection and the event watcher. Skip it
when there is no such file.

End with the diary path, the projects consolidated, and the commit, then print the Standup
paragraph once more (the `**Standup**` line and the paragraph, nothing else) as the very last
thing, so I can copy it.
