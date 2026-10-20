---
description: Plan the working day from overnight reviews, tickets, Slack, meetings and yesterday's leftovers, filed in the diary
argument-hint: "[--since 2026-09-24T15:00:00Z]"
---

Build my plan for today. Everything here only reads, except the two housekeeping scripts
and saving the plan into my diary. Never send, reply to, react to or mark anything in
Slack, GitLab, Jira or the calendar.

## 1. Housekeeping

Run these one after the other. Each applies its own safety rules; just report what it
did in one line.

```bash
~/.local/bin/sync-tickets
~/.local/bin/clean-worktrees
```

Run sync-tickets first, so the Jira statuses gathered next are already true.

## 2. Gather

```bash
~/.local/bin/start-day collect $ARGUMENTS
```

The first line gives the start of the window ("Since ..."). Use the same window for
Slack. The digest has: carry-over from my last diary entry, my open MRs (reviews
received, approvals, pipelines), which of my MRs are ready to merge (and in what order,
when they depend on each other), MRs waiting on my review, and Jira.

**Slack** (the Slack MCP server, registered as `slack`; its tools are named
`mcp__slack__<tool>`). Do not assume tool names: from a codemode script, discover the
server's search, thread-read and user-profile tools with `searchTools` /
`describeNamespace("mcp__slack")` and use only those. The server can also send
messages, react and edit canvases; never call those. Find my user ID from what the
server's tool descriptions or profile tools tell you. Run two searches with `after` set to the window start:

- direct messages: filter `is:dm`, sorted by timestamp, then drop app and bot DMs
  (Jira, GitLab and the like), since the digest already covers those sources. The
  Jira app alone can fill a page, so follow the cursor until results are older than the
  window start, up to five pages, rather than stopping at the first page
- mentions: keyword `<@MY_USER_ID>`

For each person's request, open the thread when the search result is cut short. Note
who, what they need, and whether I already replied in that thread. Never post, react,
edit or mark read. If the slack server is not connected, write "Slack not connected"
at the end of the plan, and carry on.

**Calendars**, from local midnight to midnight, read-only:

- ECFX meetings live in Outlook. If a read-only Outlook calendar tool is actually
  registered this session, search the day with query `*`, oldest first. Its times are
  in the mailbox's time zone, which it names; show them as local time.
- My epicmax events live in Google Calendar: if a read-only Google Calendar tool is
  actually registered this session, list the events on the primary calendar.

Never create, change or answer events, or send mail. List today's events with start
time and title, merged in time order. Skip events I declined and all-day events that
aren't meetings. If a calendar has no such tool or one needs a sign-in, write "Outlook
not connected" or "Google Calendar not connected" at the end of the plan, and carry on
with the other.

## 3. Write the plan

**One item per ticket.** Gather everything a ticket needs today (review notes to answer,
a merge, a pipeline to fix, a Slack question about it) into one item, and put that item in
the most urgent group any of its actions belongs to: Merge, then First, then Today, then If
time. Write its actions in order on the one line, as short sentences or steps joined with
`;` or "then". When the steps happen at different times, or there are three or more,
list them as indented child checkboxes (`  - [ ] ...`) under the ticket's line. `save`
refuses a plan where two top-level lines start from the same ticket key, naming it; merge
those lines and save again. A line about another ticket may still mention it in passing
("ecfx-1019 waits on ecfx-1018"), and lines without a ticket (a Slack reply, a review of an
MR with no key) are one item per request as before.

Group the items by what they unblock, in this order:

- **First**: things other people are waiting on. Replies owed on Slack. Every review
  note on my MRs marked "awaiting my reply", whether or not it's a resolvable thread: a
  whole first review often arrives as one plain comment. MRs in my review queue marked
  review_now or re_review, oldest first, except backend ones (see If time). A failed
  pipeline on one of my MRs.
- **Today**: what I'm committed to. Unfinished items from the carry-over (unticked
  `- [ ]`, In progress and Blocked lines), tickets newly assigned to me, and tickets
  someone else moved, for example sent back by QA.
- **If time**: reviews I owe on other people's backend MRs (ecfx-backend and backend
  services such as data-grpc-service), however long they've waited: they come after
  my own work. Then new pickups from the To-Do backlog, highest priority first, at most
  three.

Separately, **Merge**: one item per ticket whose MRs are ready to merge now, naming each
MR in merge order ("merge backend !6390, then admin !273"). A ticket that still has review
notes to answer goes in First instead, with the merge as its last step ("reply to @bob on
backend !870, then merge it"). Leave out "Waiting on dependencies" unless one of those MRs unblocks something
already in First or Today, in which case say so in one short line.

Before writing, check that every one of these made it in or was dropped on purpose: each
review note on my MRs awaiting my reply, each review_now or re_review MR, each newly
assigned ticket, each unticked carry-over item and each Slack request. Then check that no
ticket starts two top-level lines: several review notes, MRs or carry-over lines on one
ticket are one item.

Leave out what isn't mine to move: a note marked "I replied since" is waiting on the
reviewer even if its thread is still unresolved. Also leave out MRs that are idle,
waiting on their author, already approved or drafts, and carry-over items already done.

Write it in my diary style: lowercase ticket keys, short plain phrases, one checkbox per
ticket, starting with its key. Name the MR or person so I know where to go. Keep it to what fits in a day,
usually 6 to 14 items. These examples are made up to show the shape; every line you
write must come from what you gathered:

```markdown
#### Plan

**Meetings:** 10:00 standup · 14:30 retrieve v2 sync

**Merge**
- [ ] ecfx-1020 merge dashboard !940
- [ ] ecfx-1007 merge backend !870, then admin !871

**First**
- [ ] reply to @anna in DM: which firms get the new export
- [ ] ecfx-1003 backend !812: address @bob's review (2 unresolved), then merge (dave approved)
- [ ] ecfx-1009 backend !830 and dashboard !941: QA sent it back
  - [ ] fix the failed pipeline on backend !830
  - [ ] answer @erin's question in #qa about the empty state
  - [ ] re-test on staging, move back to In QA
- [ ] review @carol's ecfx-1011 backend !820 (retry cap)

**Today**
- [ ] ecfx-1004 finish calendar timezone fix, open MR; @anna asked for it by Friday
- [ ] ecfx-1008 new: storage policy not saved on practice groups — investigate

**If time**
- [ ] ecfx-1015 pick up: keep filters after selecting documents
```

Leave out the Meetings line when there are none.

## 4. File it

Print the plan in the chat, then save it:

```bash
~/.local/bin/start-day save <<'PLAN'
<the plan, starting with #### Plan>
PLAN
```

Link an MR as plain text with a trailing `[↗][label]` ref, or inline `[dashboard!940](url)`; `save` converts inline links to trailing refs with the URLs listed below the plan.

This puts it at the top of today's `### ECFX` section, creating today's diary entry from
my template if needed. Running it again the same day replaces the plan and nothing else.
It also records this run's time, so tomorrow's window starts here. End with the
housekeeping lines, any source that wasn't available, and the diary path.
