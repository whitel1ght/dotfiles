---
description: Plan the working day from overnight reviews, tickets, Slack, meetings and yesterday's leftovers, filed in the diary
argument-hint: [--since 2026-09-24T15:00:00Z]
model: sonnet
allowed-tools: Bash(~/.local/bin/start-day:*), Bash(~/.local/bin/sync-tickets:*), Bash(~/.local/bin/clean-worktrees:*), Bash(~/.local/bin/friction-ledger:*), Bash(~/.local/bin/cards:*), Bash(~/.local/bin/friction-cards:*), Bash(date:*), Bash(rg:*)
disable-model-invocation: true
---

Build my plan for today. Everything here only reads, except the two housekeeping scripts
saving the plan into my diary, and the coach step's own commands. Never send, reply to, react to or mark anything in
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
Someone else's MR whose last review from me is unaddressed stays out wherever it shows
up (a to-do marked "waiting on author", Slack, Jira) until its author pushes or replies.

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

## 4. Coach

The friction queue count, then a short card quiz. This step never blocks the plan:
if a command here fails or returns nothing, print one line (or nothing when there is nothing
to show) and go on to step 5. Nothing from this step goes into the diary, and the plan
written in step 3 never mentions the coach. Keep two counts for the log: `offered` (the
queue count N, or 0) and `cards` (the quiz count). Every command here that takes a date
takes today's date inline, as `--date "$(date +%F)"`.

```bash
~/.local/bin/friction-cards count
```

When it prints a number N, print one line: friction queue: N waiting (`` ` f``). Otherwise
print nothing. Count N in `offered`.

**Quiz.** Run `~/.local/bin/cards due --limit 5 --json` (an array of `{slug, front, back,
tags, new}`; nothing due means no quiz). One card at a time: show the `front` and wait for my
answer in my own words. Compare it to the `back`: 3 = complete and right, 2 = right with
gaps, 1 = partly right, 0 = wrong or "don't know". Give one line of feedback, show the
`back`, then run `~/.local/bin/cards grade <slug> <0-3>` and count the card in `cards`. If I
give no answer, or you cannot grade it, do not call `cards grade`; the card stays due.
`skip` ends the quiz (the remaining cards stay due); `drop` runs
`~/.local/bin/cards drop <slug>` and moves to the next card.

### Monthly tool review

On the first /start-day of a month, offer it once, after the quiz. It is the first run of
the month when `~/wiki/work/friction/coach-log.md` has no row starting `| YYYY-MM-` for
this month (`rg -c "^\| $(date +%Y-%m)-" ~/wiki/work/friction/coach-log.md` finds none or
the file is missing). Ask one line: "Monthly tool review: run it now? (yes/no)".

On no, or no answer, do nothing more: the coach log row written below ends the offer for
this month, so it is not asked again before next month. On yes, start ONE research subagent in the background (the Agent tool, general-purpose, run in the background) and do not wait
for it: carry on with the quiz summary and the coach log below. Its brief (it knows nothing
else; put the real date in place of `<T>`):

> Review the user's tools, read-only, and write down only what you can support. You never install
> anything, change any setup file, or edit the dotfiles repo; your only writes are the temp
> proposal files and the `friction-ledger add-tool` calls below.
> 1. Usage: run `~/.local/bin/coach-mine --commands --date <T>` (prints the programs the agents
>    and the shell ran over the last 30 days, with counts, never arguments). Never read
>    `~/.zsh_history`, the transcripts, or anything under `~/.secrets`.
> 2. Inventory: `ls ~/projects/dotfiles/bin` (the user's own scripts) and the tools the skills and
>    playbooks call (`rg -o` over `~/projects/dotfiles/claude` and `pi` for command names).
> 3. Candidates: the top custom scripts by use, and the most-run commands. For each, search the web
>    for a maintained alternative (a brew package, an official CLI or MCP server, a built-in
>    feature of a tool already installed). Check that the alternative is maintained (recent
>    release) and what switching costs: call sites to rewrite, headless or unattended use,
>    context cost of always-on tools, accounts and admin rights needed.
> 4. A verdict per candidate, with the use count, the alternative with its link, what would change,
>    and the risk: `switch` (clearly better), `try` (worth an experiment), or `keep`. Be honest:
>    keep is the right verdict when nothing is materially better.
> 5. For each `switch` or `try`, write the proposal (what to change, why, the use count, the link,
>    how to undo it) to a temp file and record it:
>    `~/.local/bin/friction-ledger add-tool --sig tool:<name> --proposal-file <file> --date <T>`
>    with `<name>` the tool or script name. Never record a `keep`. The coach offers new entries on
>    later mornings, and a proposal touching a guard, permission rule or hook is labelled as a
>    safety change there.
> 6. Reply with a summary of at most 25 lines: one line per candidate (name, use count, verdict,
>    reason), the `add-tool` ids, and the keep verdicts.

When its summary arrives, show me the verdicts in a few lines; if the session has ended by then,
the entries it recorded are still offered later. The review never blocks the plan. If a subagent cannot start, say so in one line and go on.

Last, log the counts (this replaces today's row if /start-day runs twice):

```bash
~/.local/bin/friction-ledger coach-log --date "$(date +%F)" --offered <N or 0> --answered 0 --landed 0 --failed 0 --cards <quiz count>
```

## 5. File it

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
