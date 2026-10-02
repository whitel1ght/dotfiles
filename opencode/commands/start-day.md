---
description: Plan the working day from overnight reviews, tickets, Slack, meetings and yesterday's leftovers, filed in the diary
# argument-hint (inert in OpenCode): [--since 2026-09-24T15:00:00Z]
# disable-model-invocation (structural): only ever reachable as a slash command.
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

**Slack** (the claude.ai Slack connector; if its tools are deferred, load them with
ToolSearch). Use only `slack_search_public_and_private`, `slack_read_thread` and
`slack_read_user_profile`. The connector can also send messages, react and edit
canvases; never call those. Its tool description gives my user ID. Run two searches with
`after` set to the window start:

- direct messages: filter `is:dm`, sorted by timestamp, then drop app and bot DMs
  (Jira, GitLab and the like), since the digest already covers those sources. The
  Jira app alone can fill a page, so follow the cursor until results are older than the
  window start, up to five pages, rather than stopping at the first page
- mentions: keyword `<@MY_USER_ID>`

For each person's request, open the thread when the search result is cut short. Note
who, what they need, and whether I already replied in that thread. If the connector
isn't available, write "Slack not connected" at the end of the plan, and carry on.

**Calendars**, from local midnight to midnight, read-only:

- ECFX meetings live in Outlook: the Microsoft 365 connector's `outlook_calendar_search`
  with query `*`, `order: oldest`. Its times are in the mailbox's time zone, which it
  names; show them as local time.
- My epicmax events: the Google Calendar connector's `list_events` on the primary
  calendar.

Both connectors can also create, change and answer events and send mail; never call
those. List today's events with start time and title, merged in time order. Skip events
I declined and all-day events that aren't meetings. If one needs a sign-in, name it as
not connected at the end, and carry on with the other.

## 3. Write the plan

Group the work by what it unblocks, in this order:

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

Separately, **Merge**: one checkbox per MR under "Merge now", and one checkbox per chain
under "Merge in order" naming each MR in merge order ("merge backend !6390, then admin
!273"). Leave out "Waiting on dependencies" unless one of those MRs unblocks something
already in First or Today, in which case say so in one short line.

Before writing, check that every one of these made it in or was dropped on purpose: each
review note on my MRs awaiting my reply, each review_now or re_review MR, each newly
assigned ticket, each unticked carry-over item and each Slack request. Group several
review notes on one MR into one item.

Leave out what isn't mine to move: a note marked "I replied since" is waiting on the
reviewer even if its thread is still unresolved. Also leave out MRs that are idle,
waiting on their author, already approved or drafts, and carry-over items already done.

Write it in my diary style: lowercase ticket keys, short plain phrases, one checkbox per
action. Name the MR or person so I know where to go. Keep it to what fits in a day,
usually 6 to 14 items. These examples are made up to show the shape; every line you
write must come from what you gathered:

```markdown
#### Plan

**Meetings:** 10:00 standup · 14:30 retrieve v2 sync

**Merge**
- [ ] merge dashboard !940 (ecfx-1020)
- [ ] merge backend !870, then admin !871 (ecfx-1007)

**First**
- [ ] reply to @anna in DM: which firms get the new export
- [ ] ecfx-1003 address @bob's review on backend !812 (2 unresolved)
- [ ] review @carol's ecfx-1011 backend !820 (retry cap)

**Today**
- [ ] ecfx-1004 finish calendar timezone fix, open MR
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

This puts it at the top of today's `### ECFX` section, creating today's diary entry from
my template if needed. Running it again the same day replaces the plan and nothing else.
It also records this run's time, so tomorrow's window starts here. End with the
housekeeping lines, any source that wasn't available, and the diary path.
