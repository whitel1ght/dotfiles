---
description: Standup report of the day's work across commits, MRs, Jira and sessions, filed in the diary
argument-hint: "[yesterday | YYYY-MM-DD]"
---

Collect the day's work:

```bash
~/.local/bin/daily-report collect $ARGUMENTS
```

The digest has four sections: commits, GitLab activity (each MR marked as mine or a
review for someone else), Jira status changes, and sessions (my prompts and each
session's last reply). A line in brackets means that source was unavailable; mention it
in one line at the end of the report rather than guessing its contents.

## Write the report

Write for a teammate at standup: someone who knows the product but wasn't in my
sessions. They care about outcomes, not mechanics. So "Export keeps the column order
users set (backend and dashboard MRs up for review)" rather than "address review round 3
(O3, N9, N10)".

Use this shape, and leave out any section that would be empty:

```markdown
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

Print the report in the chat, then save the same text into the diary. Use a quoted
heredoc so nothing in the report gets expanded:

```bash
~/.local/bin/daily-report save $ARGUMENTS <<'REPORT'
<the report>
REPORT
```

`save` replaces the block it wrote on an earlier run and never touches my own lines, so
running it again the same day is safe. End with the path it printed.
