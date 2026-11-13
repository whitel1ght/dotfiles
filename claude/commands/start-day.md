---
description: Plan the working day from overnight reviews, tickets, Slack, meetings and yesterday's leftovers, filed in the diary
argument-hint: [--since 2026-09-24T15:00:00Z]
model: sonnet
allowed-tools: Bash(~/.local/bin/start-day:*), Bash(~/.local/bin/day-agent:*), Bash(day-agent:*), Bash(~/.local/bin/sync-tickets:*), Bash(~/.local/bin/clean-worktrees:*), Bash(~/.local/bin/friction-ledger:*), Bash(~/.local/bin/friction-cards:*), Bash(date:*), Bash(rg:*)
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
Slack. The digest has: carry-over from my last diary entry, `## Still open from earlier
plans` (every plan item of the last 30 days not yet ticked or dismissed, see step 3), my
open MRs (reviews received, approvals, pipelines), which of my MRs are ready to merge (and in what order,
when they depend on each other), MRs waiting on my review, Jira, `## Jira mentions of me`
(every comment or description on an ECFX ticket that mentioned me in the window, each
`awaiting reply` or `replied`: I commented on the ticket after it), `## QA candidates`
(other people's tickets in Ready for QA, each with its QA ledger state from the
claude-components QA skills), and last `## Repos`:
`repos-sync` has fetched every GitLab repo in `~/projects` and fast-forwarded its default
branch where that was safe, then `## Team plugins`: `team-plugins-sync` has updated the
team's Claude plugins to that clone and regenerated pi's team skills (`plink`). Repos are
setup, not work: keep them out of the plan, and tell me in one line how many repos moved
and which plugins updated, plus each repo left alone and anything that failed, with its
reason.

**Slack** (the claude.ai Slack connector; if its tools are deferred, load them with
ToolSearch). Use only `slack_search_public_and_private`, `slack_read_thread`,
`slack_read_channel`, `slack_list_user_channels` and `slack_read_user_profile`, all
read-only. The connector can also
send messages, react and edit canvases; never call those. Its tool description gives my
user ID. Turn the window start into Unix seconds for `after`
(`date -j -u -f %Y-%m-%dT%H:%M:%SZ <since> +%s`). Two searches:

1. DMs and group DMs (1:1 chats and the small group chats I am in). One
   `slack_search_public_and_private` call with
   `query: "-in:<@USDTCL35J> -from:<@USDTCL35J> -in:<@U073BCYADGU> -from:<@U073BCYADGU>"`,
   `channel_types: "im,mpim"`, `after: <window start>`, `sort: "timestamp"`,
   `include_context: false`, `limit: 20`, default (detailed) format. The two IDs are the
   Jira and GitLab apps: their DMs are bot posts that `include_bots` does not filter and
   that crowded people out of an `is:dm` search on 2026-11-09; the digest covers both
   sources. Follow `cursor` until the result says "End of results", with no page limit:
   every result is then in the window. Drop results marked `[BOT]` and DMs with any other
   app (Slackbot, Atlassian, Zoom, …). Each result names its channel ID, participants,
   author and `Message_ts`; group the rest by channel. A conversation needs me when its
   last message from someone else is newer than my last message there and asks something
   of me (a question, a request, a decision; in a group DM, my name, `<!here>`, or a
   request aimed at the group). Open the thread (`slack_read_thread` with the channel ID
   and `Message_ts`) only to see a reply I may have given in a thread. If the search
   fails, list my DMs and group DMs (`slack_list_user_channels`, `types: "im,mpim"`) and
   read each human one with `slack_read_channel`, `oldest` = window start; say in the
   closing message that the search failed.
2. Mentions in channels: `query: "<@MY_USER_ID>"`, `after` the same, `sort: "timestamp"`,
   following the cursor the same way. Skip results already seen in search 1.

For each person's request, open the thread when the search result is cut short. Note
who, what they need, and whether I already replied. If the connector isn't available,
write "Slack not connected" at the end of the plan, and carry on.

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

First run `~/.local/bin/day-agent init`. It creates today's agent file, the hidden place for
everything the plan line leaves out.

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

- **First**: things other people are waiting on. Replies owed on Slack: each DM or group
  DM request and each channel mention. Each `## Jira mentions of me` line marked `awaiting
  reply` that asks something of me (on its ticket's line when that ticket is already
  planned). Every review
  note on my MRs marked "awaiting my reply", whether or not it's a resolvable thread: a
  whole first review often arrives as one plain comment. That label only compares
  timestamps, so read the note: one with no finding, no question and no action asked of us
  (a confirmation pass, "no blockers", "ready to approve") is no plan item and gets no
  reply. MRs in my review queue marked
  review_now or re_review, oldest first, except backend ones (see If time). A failed
  pipeline on one of my MRs.
- **Today**: what I'm committed to. Tickets newly assigned to me, and tickets someone
  else moved, for example sent back by QA.

**Still open.** Every item under `## Still open from earlier plans` goes on today's plan,
in the group it belongs to by the rules above (its last group is shown), with fresh words
for today; a blocked one says what it waits on (`ecfx-17425 waits on product's pick`), and
its open children come with it. An item stays open until it is ticked `[X]` or dismissed
`[-]`: leaving it off a plan, or the user deleting its line, never closes it, and `save`
names any you leave out. Never dismiss or drop one yourself: `[-]` and `day-agent note
<key> dismissed "the user said: <what>"` are written only on my explicit word. One that is
already done (merged overnight, moved to QA) goes on the plan as `[X]`, after `day-agent
note <key> done "<evidence>"`. A `[>]` item is due the next working day; one deferred to a
date (`day-agent note <key> deferred "YYYY-MM-DD <why>"`) is listed under "Deferred, not
due yet" and stays off until that date. A keyless item is named by its ref
(`2026-11-06/p3`): give its line a new `<!-- pN -->` and run `day-agent note <pN> carried
"from <ref>: <facts>"`, which keeps it the same item. The `Expired` line names items first
planned over 30 days ago: they are no longer tracked and stay off; name them in one line
in the closing message.
- **If time**: reviews I owe on other people's backend MRs (ecfx-backend and backend
  services such as data-grpc-service), however long they've waited: they come after
  my own work. Then QA candidates from `## QA candidates`, at most two, as
  `- [ ] ecfx-NNNN QA (claude-components qa flow): <the check in a few words>`: only those marked `QA: unclaimed`
  (or a stage `ABANDONED`); one someone holds (`live`), finished (`done`) or dropped
  stays out. Rank them by how testable they are for us on dev01: a clear user scenario in
  the dashboard or admin, or an API answer to check, first; a backend-only change that needs
  logs, a provider or a simulator after; one that needs paid PACER calls or is a refactor
  with nothing to observe last, and out. When none fits, say so in one line at the end with
  how many were in Ready for QA. Then new pickups from the To-Do backlog, highest priority
  first, at most three.

Separately, **Merge**: one item per ticket whose MRs are ready to merge now, naming each
MR in merge order ("merge backend!6390, then admin!273"). A ticket that still has review
notes to answer goes in First instead, with the merge as its last step ("reply to Bob on
backend!870, then merge it"). Leave out "Waiting on dependencies" unless one of those MRs unblocks something
already in First or Today, in which case say so in one short line.

Before writing, check that every one of these made it in or was dropped on purpose: each
review note on my MRs that needs a reply, each review_now or re_review MR, each newly
assigned ticket, each still-open item, each Slack request (every DM and group DM
request, every channel mention), each Jira mention awaiting a reply (both under **First**)
and each unclaimed QA candidate. Then check that no
ticket starts two top-level lines: several review notes, MRs or carry-over lines on one
ticket are one item.

Leave out what isn't mine to move: a note marked "I replied since" is waiting on the
reviewer even if its thread is still unresolved. Also leave out MRs that are idle,
waiting on their author or already approved.
Someone else's MR whose last review from me is unaddressed stays out wherever it shows
up (a to-do marked "waiting on author", Slack, Jira) until its author pushes or replies.

`## My draft MRs` lists every open draft of mine, however old. A draft means unfinished work
and nothing else, so decide each one from its ticket and the carry-over:
- Finished (all that is left is waiting on another MR, a deploy, a release or a review): plan
  `<key> ship <repo>!<iid>` under **First**, as a child step when the ticket already has a line.
  It ships now, with the dependency in its description.
- Unfinished and on the plan: nothing more. Unfinished and parked: it stays out.
- Can't tell: leave it out and name it in the closing message. Hands-off items stay out.

Never plan a step like `undraft X once Y`: an MR that only waits on Y ships now.

Write it in my diary style, as a short list I can read at a glance: lowercase ticket
keys, plain words, one checkbox per ticket, starting with its key: `- [ ] <key> <few words>`,
what it is or what's next. Each line is at most 100 characters; children are shorter.
No `·` on a ticket line, no links, no `[↗]`, no `[label]: url` lines. Name an MR as plain `repo!iid`
("backend!870"), never linked, and a person by first name. A line without a ticket ends
with `<!-- pN -->`: run `day-agent id` for each one, then `day-agent note <pN> note "<what
it is>"` at once, so the next id is a new one. Keep it to what fits in a day, usually 6 to
14 items.

Everything else goes to the agent file, not the plan line. For each MR a line names or
owns, run `~/.local/bin/day-agent mr <key> <repo>!<iid> <url>`. For each still-open
item, take its facts from its `latest note` or `last state` in the digest, the carry-over's
`Agent notes from <last>:` section and the last diary, and run
`~/.local/bin/day-agent note <key> carried "<the facts still true: blocked reason, who has
it, last state>"` (a keyless one: `"from <ref>: <facts>"` under its new pN). The plan line gets fresh words for today, not
yesterday's line.

These examples are made up to show the shape; every line you write must come from what
you gathered:

```markdown
#### Plan

**Meetings:** 10:00 standup · 14:30 retrieve v2 sync

**Merge**
- [ ] ecfx-1020 merge dashboard!940
- [ ] ecfx-1007 merge backend!870, then admin!871

**First**
- [ ] reply to Anna: which firms get the new export <!-- p1 -->
- [ ] ecfx-1003 answer Bob's review on backend!812, then merge
- [ ] ecfx-1009 QA sent it back
  - [ ] fix the failed pipeline on backend!830
  - [ ] answer Erin in #qa about the empty state
  - [ ] re-test on staging, move back to In QA
- [ ] ecfx-1011 review Carol's backend!820 (retry cap)

**Today**
- [ ] ecfx-1004 finish calendar timezone fix, open MR
- [ ] ecfx-1008 storage policy not saved on practice groups: investigate

**If time**
- [ ] ecfx-1012 QA (claude-components qa flow): Roles page read-only for built-in roles
- [ ] ecfx-1015 pick up: keep filters after selecting documents
```

Leave out the Meetings line when there are none.

## 4. Coach

The friction queue count, and once a month the tool review. This step never blocks the plan:
if a command here fails or returns nothing, print one line (or nothing when there is nothing
to show) and go on to step 5. Nothing from this step goes into the diary, and the plan
written in step 3 never mentions the coach. Keep one count for the log: `offered` (the
queue count N, or 0). Every command here that takes a date
takes today's date inline, as `--date "$(date +%F)"`.

```bash
~/.local/bin/friction-cards count
```

When it prints a number N, print one line: friction queue: N waiting (`` ` f``). Otherwise
print nothing. Count N in `offered`.

### Monthly tool review

On the first /start-day of a month, offer it once, after the queue count. It is the first run of
the month when `~/wiki/work/friction/coach-log.md` has no row starting `| YYYY-MM-` for
this month (`rg -c "^\| $(date +%Y-%m)-" ~/wiki/work/friction/coach-log.md` finds none or
the file is missing). Ask one line: "Monthly tool review: run it now? (yes/no)".

On no, or no answer, do nothing more: the coach log row written below ends the offer for
this month, so it is not asked again before next month. On yes, start ONE research subagent in the background (the Agent tool, general-purpose, run in the background) and do not wait
for it: carry on with the coach log below. Its brief (it knows nothing
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
~/.local/bin/friction-ledger coach-log --date "$(date +%F)" --offered <N or 0> --answered 0 --landed 0 --failed 0 --cards 0
```

## 5. File it

Print the plan in the chat, then save it:

```bash
~/.local/bin/start-day save <<'PLAN'
<the plan, starting with #### Plan>
PLAN
```

The plan has no links: the MR urls are in the agent file, and the plan picker (`` ` g ``) opens
the plan's tickets and MRs.

When `save` prints `still open but not on this plan`, you left a still-open item out: put
it on the plan and save again.

This puts it at the top of today's `### ECFX` section, creating today's diary entry from
my template if needed. Running it again the same day replaces the plan and nothing else.
It also records this run's time, so tomorrow's window starts here. End with the
housekeeping lines, any source that wasn't available, and the diary path.
