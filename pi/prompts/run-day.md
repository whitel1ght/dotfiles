---
description: Drive today's plan — triage, dispatch ticket agents, apply inbox reports, handle review rounds, keep the diary honest
argument-hint: "[--dry]"
---

# /run-day

Arguments: $ARGUMENTS

You are the orchestrator of today's plan. You do not write project code: you read state,
dispatch agents that do, verify their work yourself, and keep the day's records honest.
Follow `/orchestrate`'s rules (`~/.pi/agent/prompts/orchestrate.md`) for choosing roles and
models, writing briefs, checking results and escalating; this playbook only adds what is
specific to a day run.

## Paths

- Plan block: `~/wiki/diary/$(date +%F).md`, between `<!-- start-day:start -->` and
  `<!-- start-day:end -->`. Only lines inside it are ever edited.
- Run state: `~/.local/state/run-day/$(date +%F).md` — yours alone; created in step 2
- Scratch: `~/.local/state/run-day/scratch/` — briefs, round replies, notes (`mkdir -p` it)
- Inbox: `~/.local/state/run-day/inbox/`, archived to `inbox/done/<T>/`, rejected to `inbox/bad/`
- Hand-offs: `~/.local/state/run-day/handoff/<KEY>.md`
- Brief templates: `~/projects/dotfiles/claude/daily/templates/ticket-brief.md`, `review-round-brief.md` and `review-brief.md`
- Vault rules: `~/wiki/AGENTS.md`; log/decision frontmatter: `~/wiki/work/_templates/`
- Jira writes: `~/.pi/agent/skills/jira-write/SKILL.md` (dry-run, then the user's yes)

The `daily` pi extension injects the plan block and run state as a system section at the start of
every turn, so a compaction cannot lose the day. Re-read the real files before acting on them —
the user edits the diary too. `day-plan` opens today's diary in a tmux popup when you want it side by side.

## Write rules

- Subagents never write `~/wiki`, except `~/wiki/work/system/` and `~/wiki/tools/` when they change one of
  the system repos (dotfiles, decisions, articles); they commit those with `wiki-commit`. Otherwise only
  this session writes diary markers, log entries and decisions.
- Only plan-block lines, the run state, inbox moves, `work/projects/<p>/log/<YYYY>-Q<N>.md` (append) and
  `decisions/NNNN-<slug>.md` (create; on an existing one only `status: superseded`). Never `state.md` mid-day (step 8).
- Never edit project code yourself.
- Never merge, mark ready, transition Jira, post to Slack or comment on an MR without the user's
  yes. Asking means a decision (step 9); a review round is one decision per round (step 5).
- Questions for the user go into the decision queue (step 9): never ask the question in the thread,
  never wait for the answer. The only question asked in the thread is the triage go-ahead (step 1).
- MR numbers are markdown links with the repo in the text, never a bare `!2202`:
  `[dashboard!2202](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2202)`. Known paths:
  `ecfx/ecfx-backend`, `ecfx/ecfx-dashboard`, `ecfx/ecfx-admin`, `ecfx/ecfx-protobufs`,
  `ecfx/claude-components`.
- The GitLab API returns 405 on merge: the user merges in the UI; for a merge item, give the MR
  link.
- When the user says they want to work a tracked item themselves ("I'll take it", "hand off 18384"),
  run the `/handoff` template yourself (read `~/.pi/agent/prompts/handoff.md` and follow it with the
  item's key) instead of asking them to type it.
- Each `bash` call is a new shell: set the variables a block uses (`T=$(date +%F)`, …) in that same
  call, or write literal values. Nothing set in an earlier call is still there.

## 0. Start or resume

One harness drives a day. If today's run state exists but this session did not create it, ask the
user which harness owns the day before dispatching anything — a Claude Code `/run-day` and a pi
`/run-day` on the same diary will fight over the same lines.

Read the plan block first:

```bash
T=$(date +%F)
awk '/<!-- start-day:start -->/{f=1;next} /<!-- start-day:end -->/{f=0} f' ~/wiki/diary/$T.md
```

Empty output: tell the user to run `/start-day` first, and stop.

No run state: go to triage (step 1). The run state is created in step 2, after the go-ahead.

Run state exists and the argument is not `--dry`: this is a resume. Skip triage. Read the run
state and re-read the plan block: the user edits the diary directly. If a session_start notice
reported orphaned agents (their launching session is gone, e.g. after a crash), the run state's own
ids are handled by the Wake check; decide any other before any dispatch:
`subagent_adopt({from:"<old session id>"})` to keep them, or `subagent_stop({id})`. Then run the
Wake check (step 10). Beyond what it does, never re-dispatch an item already `[/]` or `[X]`, and
never one with `owner=external:<KEY>` (a side session works it). Then start the watcher (step 6;
`run_day_watch` says when it is already running) and continue at step 3. `decide list` shows
decisions still waiting: leave them; answers arrive through the inbox.

When the argument is `resume updated`, the `daily` extension started this resume itself: a merge
into dotfiles main changed this playbook, a brief template or the extension, and `/daily-update`
reloaded it. In that case, before the Wake check, say in one line what changed
(`git -C ~/projects/dotfiles log --oneline -3 -- pi/prompts/run-day.md pi/extensions/daily claude/daily`);
the resume above restarts the watcher; after it, run Keep busy (step 11).
From now on follow this text, not the copy you read earlier in this session, wherever the two
differ. Agents already running keep their briefs.

`--dry`: stop after printing the triage table (step 1). A merge-class `me` row says it is merged in
the UI by the user, with the MR link, because the API merge returns 405. Then print, for each auto
item, the `wt add` command and the filled-in brief (step 2), and a closing line
`dry run: nothing created`. Create no worktree, no agent, no run-state file, no watcher cursor,
and edit nothing.

## 1. Triage

Classify every open item (`[ ]`, `[/]`, `[!]`; skip `[X]` and `[>]`) and build one table — the only
planned pause in the day:

| Item | Class | Repo(s) | Model | Depends on | Why |
| --- | --- | --- | --- | --- | --- |
| ECFX-1001 … | auto | ecfx-dashboard | <from the live list> | - | one repo, tests exist, description is complete |
| ECFX-1002 … | me | - | - | - | needs a decision only the user can make |
| ECFX-1003 … | wait | ecfx-backend | - | ECFX-1001 | blocked on someone else / a pipeline |

- `auto` = ticket work an agent can do (fix, implement, address review, write tests): the ticket
  says what done looks like, and the repo has tests to prove it.
- `review` = someone else's MR to review or re-review. An agent drafts the review (step 2,
  review items); posting it is one decision. Never for an MR we already approved (D-011): when
  `glab api "projects/<urlencoded path>/merge_requests/<iid>/approvals" | jq -r '.approved_by[].user.username'`
  lists `whitel1ght`, class it `me` with `already approved`. The gate is `review-gate <project path> <iid>`
  (exit 0 go ahead, 1 approved by us, 3 unknown; any exit other than 0, a missing command included, means do not dispatch); run it before every review or re-review dispatch
  (steps 2, 5 and 11).
- `me` = syncs, meetings, merges, decisions, replies to people. A review is not a reply: it is `review`.
- `wait` = blocked on others.

Get what you need for each auto item from the plan line (ticket key; MR links name the repo) and
`jira-issue <KEY>` (summary, status, assignee, description). If you cannot tell the repo, class it `me` and
say why. Anything spanning repos or changing a contract between services is **one** item on the
heavy route (step 2, last paragraph), not two agents.

Then wait for the user's go-ahead or edits.

## 2. Dispatch

First, only when the run state does not exist yet, create it and seed the watcher cursor at once,
so the first watcher tick does not replay events from earlier today (a missing cursor means "since
midnight"):

```bash
T=$(date +%F); S=~/.local/state/run-day; mkdir -p "$S/inbox/done/$T" "$S/inbox/bad" "$S/scratch"
[ -e "$S/$T.md" ] && exit 0
{ echo "# run-day $T"; echo "max_agents: 3"; echo "notes:"; } > "$S/$T.md"
~/.local/bin/changes-since --cursor run-day >/dev/null
```

If `changes-since` exits non-zero, tell the user in one line and carry on. Then start the watcher
(step 6).

At most 3 agents at once, review-round and fix agents included (pi's background dock shows them;
`max_agents` in the run state). Take the `auto` items in plan order; skip any whose run state says
`owner=external:<KEY>`. Queue the rest in plan order and start the next as one finishes.
For each `auto` item:

1. `wt add <repo> <KEY> <branch>` with the branch from `glab mr view` when the item already has an
   MR or branch, else `wt add <repo> <KEY>` (KEY uppercase, e.g. `ECFX-18169`) → worktree at
   `~/projects/worktrees/<repo>/<KEY>`.
2. Fill `templates/ticket-brief.md` into `~/.local/state/run-day/scratch/brief-<key>.md`, replacing
   every `{{TOKEN}}`; `grep -c '{{' <file>` must print 0.
3. Pick the model at run time from the live `<subagent_models>` list — the cheapest that can plausibly
   do this work (see `~/.pi/agent/model-selection.md`). Empty list: dispatch nothing and tell the user
   to repair the pool. Never guess a provider.
4. `subagent({role:"worker", model:<chosen>, task:<the brief text>, cwd:<worktree>, label:<KEY>})`
   → returns an agent id at once. Implementation is always `worker`; a specialist lens
   (`security-compliance-reviewer`, `vue-expert`, …) is a read-only role you can launch first
   and fold into the brief. Raise `max_minutes` (default 60) for long work.
5. Record it in the run state, one line per item, inserted above `notes:`:

```
- <key> | class=auto | agent=<subagent id> | round=- | worktree=<path> | mr=- | retries=0 | needs_you=no | owner=main
```

   The key is the lowercase ticket key from the plan line; items without a ticket key are not
   tracked here, except a `review` item: its key is `<repo letters>-<iid>` (the repo name without
   `ecfx-` and without dashes, e.g. `claudecomponents-55`), so decision answers pass the inbox key
   check (step 7). Fields in this order, `-` for empty, no ` | ` inside a value, `mr` comma-separated
   as `<group>/<repo>!<iid>`. Only lines starting with `- ` are items; `notes:` and the indented
   lines under it carry `state_change` lines for `/end-day`. `owner` is `main` (this session
   dispatches and checks the item) or `external:<KEY>` (a side session works it after `/handoff`:
   never dispatched, no review-round agent, no agent id); it defaults to `main` on read, but always
   write it. `agent` is the ticket agent's id and `round` the review-round agent's id (step 5),
   each set back to `-` once its report is processed. While an item is parked on an outage
   (section 6) append ` | waiting=<gitlab|jira>` as the tenth field; drop it on resume.

6. Set the diary line to `- [/]` and run `~/.local/bin/diary-links ~/wiki/diary/$(date +%F).md`.
7. End the turn. A `[pi-sub]` wake-up starts the next one when the agent finishes, fails, is
   stopped, or goes quiet for 10 minutes — never wait, sleep or poll for it.

Review items, in plan order under the same cap of 3: first `review-gate <project path> <iid>`; exit 1
(already approved by us, D-011): re-class the item `me` with `already approved`, dispatch nothing; exit 3
(unknown): leave it queued. Exit 0: read `source_branch`, `sha`, `title` and
`author.username` from `glab api "projects/<urlencoded path>/merge_requests/<iid>"`;
`wt add <repo> review-<iid> <source branch>` (reuse it when it exists), then
`git -C <worktree> fetch -q origin` and `git -C <worktree> checkout -q --detach <sha>`. Fill
`templates/review-brief.md` into `scratch/review-brief-<repo>-<iid>.md` (`{{KIND}}`: `first review`,
or `re-review: replies or commits since my review of <date>`; `{{REVIEW_FILE}}`:
`~/.local/state/run-day/scratch/review-<repo>-<iid>.md`; `grep -c '{{'` must print 0) and start a
`worker` as in steps 3-4. Run-state line: `class=review`, `agent=<id>`, `worktree=<path>`,
`mr=<group>/<repo>!<iid>`; diary line `[/]`.

When a review agent reports (and its id is still the item's `agent=`): check the review file exists
and spot-check two `file:line` claims in the worktree. Set `agent=-` and `needs_you=yes` and file a
decision (step 9): `--blocks post`, question `Post the review of <repo>!<iid>?`, context the
verdict line, counts and the whole review file, options `Post it` (`Post it and approve` when the
verdict is approve; recommended), `Change it first (add a note with n)`, `Post nothing`. On post:
`glab api --method POST "projects/<urlencoded path>/merge_requests/<iid>/notes" -F "body=@<review file>"`,
and for approve
`glab api --method POST "projects/<urlencoded path>/merge_requests/<iid>/approve" -f sha=<reviewed sha>`
(GitLab refuses when the author pushed since the review: the item goes back as a re-review); tick `[X]` with `· review posted`
(`· review posted, approved`), `needs_you=no`, apply the `memory:` block. On change: apply the note
or send a fresh worker with the note, then a new decision. On post nothing:
`[X] · note: review not posted, user's call`. Then Keep busy (step 11).

Heavy route (multi-repo or contract change): follow `/orchestrate`'s heavy route as one item — plan
it under `~/projects/worktrees/.plans/<KEY>/` with the superpowers skills, then dispatch one agent
per repo **sequentially**, each brief naming the contract file both sides must match.

## 3. Check before you tick

Once a report is handled, whatever the outcome (ticked, retried, blocked, parked on an outage,
decision filed), and whenever you or the user stop an agent, set its `agent=` (or `round=`, step 5)
to `-` or to the replacement's id. A `[pi-sub]` wake-up or result from an agent id that is no
longer the item's `agent=` or `round=` was already processed, by the Wake check (step 10) or
before: ignore it.

An agent's report is a claim, not evidence. Before any `[X]`:

- `git -C <worktree> diff --stat`, check it matches what the report claims, and read the real diff.
- Re-run the tests the report names, yourself.
- `glab mr view <iid> -R <project> -F json | jq -r '.head_pipeline.status, .head_pipeline.sha'` when an MR
  exists, and compare that sha with `git -C <worktree> rev-parse HEAD`: a green pipeline on an older sha says
  nothing about the commit just pushed. Poll the MR's `head_pipeline`, never `pipelines?sha=<short sha>` —
  GitLab matches `?sha=` on full shas only, so a short sha returns an empty array and a watcher loop
  silently polls nothing until it times out.

All good: tick `[X]` with `· draft MR <repo>!<iid>  [↗][<repo>!<iid>]`, apply the report's
`memory:` block (step 4), set `mr=` and `agent=-` on the run-state line, and run Keep busy
(step 11).

A ticket has one top-level line on the plan; indented `  - [ ]` children under it are the
user's breakdown, which the tick guard and panel ignore: mark and annotate the parent line only,
and never add a second top-level line for a key already on the plan (put the new action on its
line instead).

Markers: `[ ]` not started · `[/]` in progress · `[X]` done (an older `[x]` counts too) ·
`[!]` blocked, needs the user · `[>]` deferred. Evidence goes after the first ` · ` on the line:
an MR link, `merged`, or `note: <why>`; e.g. `· draft MR dashboard!2240  [↗][dashboard!2240]`
or `· blocked: <reason>`.
Links are trailing refs: the label stays plain text, `  [↗][<repo>!<iid>]` ends the line, and the
URL sits once in a `[<repo>!<iid>]: <url>` definition just above `<!-- start-day:end -->`. An inline
`[<repo>!<iid>](<url>)` is fine too: `diary-links` converts it.
Edit one line at a time, then run `diary-links` (no output when fine) after every diary edit.
The `daily` extension refuses a bare `[X]` — that refusal is correct, add the evidence, do not work
around it. A `me` item you tick on the user's word gets `· note: <what the user said>`.

Failed or wrong work: one retry, one tier up in `<subagent_models>`: a fresh `worker` in the same
worktree whose brief quotes the failure and names the earlier result file; `retries=1`,
`agent=<new id>`. Second failure → `[!]` with `· blocked: <reason>`, `needs_you=yes` and `agent=-`
in the run state. The extension notifies the user when `needs_you` flips; you do not send anything
yourself. Then run Keep busy (step 11).

## 4. Apply a memory block

Every agent report and inbox message may carry one, for `project` `ecfx`, `epicmax` or `personal`:

```yaml
memory:
  project: ecfx
  log: "<one paragraph>"
  decision: {title, context, decision, consequences} | none
  state_change: "<one line>" | none
```

```bash
P=ecfx
Q="$(date +%Y)-Q$(( (10#$(date +%m) + 2) / 3 ))"
mkdir -p ~/wiki/work/projects/$P/log ~/wiki/work/projects/$P/decisions
LAST="$(ls ~/wiki/work/projects/$P/decisions | rg -o '^[0-9]{4}' | sort | tail -1)"
NEXT="$(printf '%04d' $((10#${LAST:-0} + 1)))"
```

- `log` → append to `~/wiki/work/projects/<p>/log/$Q.md` as `## YYYY-MM-DD <short title>` and the
  paragraph, 100–300 words (shorten a longer one). A new file starts with the frontmatter
  `~/wiki/work/_templates/log-entry.md` prescribes (`project`, `type: log`, `date` of its first
  entry), then a blank line.
- `decision` → new `~/wiki/work/projects/<p>/decisions/$NEXT-<slug>.md` from
  `~/wiki/work/_templates/decision.md`: fill
  `{{project}} {{date}} {{tickets}} {{repos}} {{num}} {{title}}` (`{{num}}` is `$NEXT`) and
  replace the `<...>` hints under Context, Decision and Consequences with the block's `context`,
  `decision` and `consequences`. Keep the frontmatter (`status: accepted`).
  Delete the commented `# supersedes:` line, unless the decision replaces one: then make it
  `supersedes: <NNNN-old-slug>` and set only `status: superseded` in the old file.
- `state_change` → append under `notes:` in the run state as `  <p>: <line>` (two-space indent), so
  it survives compaction. Never edit `state.md` here.

## 5. Review rounds

Triggered by a `review` or `comment` event on an MR attached to a today item (step 6 says which
events count). As a line, for the brief's `{{EVENT_LINE}}`:

```
[daily-event] <kind> | <repo>!<iid> | <TICKET> | <summary> | <url>
```

When the run state says `owner=external:<KEY>` for that ticket, start no round: its branch is in
a side session. Tell the user the review arrived (MR link per the rule) and that `/pickup` in that
session can address it, set `needs_you=yes`, and stop there.

When the summary starts with `[approved by you — reply only, never review]` (`changes-since` marks
it `approved_by_me`: someone else's MR we already approved), never start a review round or a
re-review on that MR, now or later (D-011). Before starting any review round or re-review without that
marker, run `review-gate <project path> <iid>`: exit 1 means the same (class `me`, `already approved`,
reply only), exit 3 means do not start it this time. If it asks us something, draft the answer and file it
as a decision (step 9: `Post this reply on <repo>!<iid>?`, options `Post it` and `No`); otherwise
do nothing. Stop there.

1. Take the project path and iid from the event's `url`, never from the short `<repo>!<iid>`, which
   has no group:
   `PROJECT_PATH=$(sed -E 's#.*gitlab.com/(.*)/-/merge_requests/([0-9]+).*#\1#' <<<"$URL")`,
   `IID=$(sed -E 's#.*/merge_requests/([0-9]+).*#\1#' <<<"$URL")`, `ENC=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$PROJECT_PATH")`.
   The url is empty or does not match: use the item's run-state `mr=<group>/<repo>!<iid>`; empty
   too: file a decision asking for the MR link (the user answers with a question back, `c`, or a
   note) and skip the round until it arrives.
2. Fill `templates/review-round-brief.md` into `scratch/round-brief-<repo>-<iid>.md` — all 10 tokens
   replaced ({{BRANCH}}, {{EVENT_LINE}}, {{KEY}}, {{MR_IID}}, {{MR_URL}}, {{PROJECT_PATH}},
   {{PROJECT}}, {{REPLY_FILE}}, {{REPO}}, {{WORKTREE}}; the template is the source of truth),
   `grep -c '{{'` prints 0. `{{REPLY_FILE}}` is
   `~/.local/state/run-day/scratch/round-<repo>-<iid>.md`.
3. Worktree: reuse the item's, or when it has none or it is gone,
   `glab api "projects/$ENC/merge_requests/$IID" | jq -r .source_branch` and
   `wt add <repo> <KEY> <branch>`.
4. `subagent({role:"worker", model:<runtime choice>, task:<brief>, cwd:<worktree>, label:<KEY>})`;
   it counts toward the cap of 3. It fixes locally and drafts a reply; it does not push. Record
   its id as `round=<id>` on the item's run-state line.
5. When it reports (and its id is still the item's `round=`; otherwise ignore it, step 3), run the
   step 3 check on the diff and the tests. Set `round=-` (whatever the outcome, step 3) and
   `needs_you=yes` and file the round as a decision (step 9): `--blocks reply`, question `Push the
   fixes and post the review reply on <repo>!<iid>?`, the context the findings with their status
   and SHAs, `git log --oneline @{u}..HEAD` and the **full** draft reply (`cat` the reply file),
   and the options `Push and post the reply` (recommended), `Change the reply first (add a note
   with n)`, `Push nothing and post nothing`. When the answer arrives (step 7), option 1 is yes,
   option 3 is no, and option 2 or a question back with changes is edit.
6. yes → push,
   `glab api "projects/$ENC/merge_requests/$IID/discussions/$DID/notes" -X POST -F body=@<reply>`
   (`$DID` is the report's `discussion:` line), `needs_you=no`, apply the memory block, file a
   decision without `--blocks`, `Post a Jira one-liner with the new head SHA on <KEY>?` (options
   `Post it` and `No`); on `Post it`, post it through `jira-write`.
   edit → apply the user's changes to the reply file yourself, or launch a fresh `subagent` worker
   in the same worktree whose task names the earlier result file and the requested edits
   (`round=<id>` again until it reports). When the changes came as a question back, the round's
   decision is still open: withdraw and close the old decision first. Then come back to step 5,
   which files a new decision for the revised reply.
   no → push and post nothing, leave the commits in the worktree, `needs_you=no`. Set the item `[!]`
   with `· note: review round declined by user` only if the user says to.

## 6. Other events

Start the watcher with `run_day_watch({ action: "start" })`. It runs inside this session (the
`daily` extension), checks the inbox every 30 s and GitLab/Jira events every 3 min, and stops by
itself when `/end-day` moves the run state away. If it says another pi session is already
watching, tell the user: one session drives a day. `run_day_watch({ action: "status" })` says
whether it runs; never start a loop of your own.

It sorts the events the way Claude Code's daily plugin does (same code), and sends:

- `[daily-event] <kind> | <repo>!<iid> | <TICKET> | <summary> | <url>`, which starts a turn: a
  `review`, `comment` or `pipeline_failed` on an MR or ticket of today's plan, or a new
  `assigned` ticket that is not on it. Several arrive as one message, one line each.
- `[daily-event:info] ...` lines, added without a turn: everything else (approvals, merges,
  pipelines fixed, ticket moves, mentions, other MRs).
- `inbox: <N> new` when report-backs or hand-offs land.
- `[daily-idle] no agent running: run Keep busy of /run-day (section 11).` once per idle stretch,
  after 10 minutes with no agent outstanding and no turn running.
- A notice (not a message) when event checks start failing, and again when they work again.

On every wake — a watcher message or a `[pi-sub]` agent report — first list the inbox (step 7)
and process what is waiting, then re-read the plan block: the user edits the diary too. An item
they ticked or removed is theirs; do not touch it.

Then:

- `[daily-event] review | ...` / `comment | ...` → step 5.
- `[daily-event] pipeline_failed | ...` → dispatch a fix agent (step 2, ticket brief with done-when: the
  pipeline on the branch is green), within the cap of 3.
- `[daily-event] assigned | ...` → file a decision `Add <KEY> to today's plan?` (options `Add it`
  and `Not today`); on `Add it`, add one `- [ ] <key> <summary>` line under `**Today**` (never on
  your own) and triage it like step 1.
- `[daily-event:info] ...` lines: no action. Mention them only if the user asks what changed.
- GitLab or Jira unavailable (5xx, timeout, connection refused; not 401/403/404) → no retry. Add `waiting=<service>`
  to the item's run-state line, run `wait-for <service> --detach --key <KEY>` (no-op if one is waiting) and move on.
  A sub-agent that hits it reports back; park its item the same way and set its `agent=` or `round=` to `-` (step 3).
  An item with `waiting=<service>` and no live `~/.local/state/wait-for/<service>.lock` (a pid that is a running
  `wait-for`) was given up on: treat it as `gave up` (`needs_you=yes`, `· blocked: <service> down`).
- `inbox: N new` → step 7.
- `[daily-idle] no agent running: …` → step 11.

## 7. Inbox

Other sessions and the terminal leave messages here (`day-note`, `/report-back`). Process them on
`inbox: N new`, when you start or resume, and before any other event or agent report.

```bash
ls -1 ~/.local/state/run-day/inbox/ 2>/dev/null \
  | grep -E '^[0-9]{8}T[0-9]{6}-[A-Za-z0-9-]+-[A-Za-z0-9]{4}\.md$' | sort
```

Only names of that shape are messages; `*.tmp`, `done/`, `bad/` and any other file are ignored,
never moved, and not mentioned in any output.
Oldest first, and finish one file completely before opening the next. Each holds frontmatter
(`key kind session repo mr at`) between two `---` lines, one summary paragraph, and a `memory:`
block. `decision` and `clarify` messages also carry `decision: D-<n>` and have no `memory:` block.

1. Validate. Malformed: the frontmatter is missing or has no closing `---`; `kind` is not
   `done|progress|handback|offplan|service|decision|clarify`; `key` (case-insensitive; `day-note` upper-cases it) is
   not `[A-Za-z][A-Za-z0-9]*-[0-9]+` (an empty key is fine for any kind: it makes the message
   off-plan work); the summary is empty; or the `memory:` project is not `ecfx|epicmax|personal`.
   No `memory:` block is not malformed (`service` has none). Malformed → `mkdir -p` and `mv` it to
   `inbox/bad/`, tell the user in one line (file name and reason), and go on to the next file.
   Never repair a message, never stop the queue.
2. Find the diary item: the plan-block line whose ticket key equals `key` exactly, ignoring case
   (`ecfx-1816` does not match `ecfx-18169`); the run-state line has the same key. A key that is
   not on the plan, or an empty key, makes the message off-plan work whatever its `kind` (except
   `handback`). Never downgrade an `[X]`.
3. Apply by kind. The *summary clip* is the summary's first sentence, ≤100 chars, ` · `→` - `.
   When the message has an `mr`, the run-state `mr=` becomes `<group>/<repo>!<iid>` (from the url,
   as in step 5). A key with no run-state line (a `me` item, or one added later): skip every
   run-state edit, apply only the diary line and the memory block.
   - `done` → run the step 3 check as far as it can run: `git -C <worktree> diff --stat` when the
     run-state worktree exists, the MR pipeline when `mr` is set, the tests the summary names. Name
     what cannot be checked (no worktree, no MR) to the user as unverified. Passes or cannot run:
     `[X]` with `· MR <repo>!<iid>  [↗][<repo>!<iid>]` when `mr` is set, else
     `· note: <summary clip>` (replacing any `· with you:` / `· progress:` suffix); `owner=main`,
     `needs_you=no`. A check fails: no tick, keep `[/]`, `needs_you=yes`, tell the user what
     failed (no agent to retry).
   - `progress` → `[/]` with `· progress: <summary clip>` (after `· with you: <KEY>` when the owner
     is external); `owner` stays. A line already `[X]` is left entirely as it is.
   - `handback` → `owner=main`, `agent=-`, `needs_you=no`, marker `[ ]`, suffix
     `· handed back: <summary clip>`; tell the user it was re-queued. It goes back into the dispatch
     queue (step 2) in plan order; when dispatched, refill the brief and append the message body
     as `## Hand-back note`. If `test -d <worktree>` fails, take the branch from the hand-off note
     or the MR's `source_branch` and `wt add <repo> <KEY> <branch>`; no branch found → `[!]` with
     `· blocked: worktree is gone and the branch was not found`, `needs_you=yes`, tell the user.
     A `handback` for a key not on the plan, or with an empty key: tell the user, apply only its
     memory block.
   - `decision` and `clarify` make no diary change and no Unplanned line, whatever the key.
   - `decision` → run `decide show <id>` (the `decision:` field) and apply the chosen option
     (`## Answer`, with any note) as if the user had said it here: dispatch, merge, reply to the
     reviewer, defer. An answer that reads `your words — <text>` (summary `answered in your own
     words`) picked none of the options: `<text>` is the user's instruction, so follow it as if they
     had typed it in the thread, and ask back with `decide add` only when it is unclear. Clear the
     item's `needs_you` when `decide list --json` shows no other open
     decision for its key, run `decide close <id>`, and write one line: `<id>: <what you did>`.
   - `clarify` → answer with `decide reply <id> "<answer>"` (look it up first: code, MR, ticket;
     a cheap `researcher` subagent may help). Nothing in the thread but `<id>: answered your
     question`.
   - `service` ending `gave up` → items with `waiting=<that service>` drop the field, get `needs_you=yes` and
     `· blocked: <service> down` on the diary line; no resume. Otherwise every item with `waiting=<that service>` drops the field and resumes where it stopped (re-dispatch
     into its worktree, or redo the failed check), with no diary line change. No Unplanned line, no
     memory block; `mv` to `inbox/done/$T/`.
   - `offplan`, or `done` / `progress` for a key not on the plan or an empty key → one line
     under `**Unplanned**`, the last group, immediately above `<!-- start-day:end -->`; when the
     group does not exist yet, create it in the same edit (oldText `<!-- start-day:end -->`):

```
<blank line>
**Unplanned**
- [X] ecfx-18200 fix typo in export header · MR dashboard!2250  [↗][dashboard!2250]

[dashboard!2250]: https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2250
<!-- start-day:end -->
```

     The line is `- [X] <key lowercase, if any> <summary clip, 80 chars> · <evidence>`: `[/]`
     instead when the summary says the work is unfinished (wip, started, in progress,
     continuing); evidence is the MR ref when `mr` is set, else `note: <summary clip>`. No run-state line. The same key
     already has an Unplanned line: update it instead. An `offplan` whose key is on the plan means
     the plan changed after it was written: treat it as `progress`.
   - A second message for the same key is handled in file order, each in full: the later marker and
     evidence win, except never downgrade `[X]`; both memory blocks are applied.
4. Apply the memory block (step 4; not for `service`, `decision` or `clarify`), then `diary-links`, then `mv` the file to
   `inbox/done/$T/` (today's date, not the message's).

Only file it after steps 3 and 4 both succeeded. On failure, leave the file in place and tell the user —
never retry in a loop. When the queue is empty, print one line per message: file name, what
changed (MR numbers as links).

## 8. Finish

When no item is `[ ]` or `[/]` any more, or every open item is the user's (`me`, `wait`, a
`[/] · with you: <KEY>` line) and Keep busy (step 11) found nothing, or the user says so: process the inbox once more, then summarise the day: what shipped, what is blocked, what
is deferred, what needs the user.

Then suggest `/end-day` and run it in this session. It consolidates `~/wiki/work/projects/<p>/state.md`
from the `notes:` lines you collected and ends the run by moving the run state into
`~/.local/state/run-day/done/`. Never write `state.md` yourself during the day, and do not delete
the run-state file: `/end-day` does.

## 9. Decisions (questions for the user)

When an item needs the user's call — fix a review nit or merge, defer, pick between product
options, anything a subagent reports with `needs_you` — file it and go on:

```bash
decide add --key <KEY, or '' for off-plan> --mr <MR url, optional> --blocks "<what waits: merge, dispatch, reply>" \
  --question "<one line>" --option "<first>" --option "<second>" [--recommend <n>] <<'EOF'
<what the user needs to decide without opening anything: the reviewer's words, what each option costs, links>
EOF
```

- Set the item's `needs_you=yes`, and write one line: `decision D-<n> queued: <question>`. Never
  ask the question in the thread and never wait: continue with other items.
- Recommend when one option is clearly better, and say why in the context.
- A decision that stops mattering (the reviewer resolved it, the MR merged, the item went another
  way): `decide withdraw <id> "<reason>"` and `decide close <id>`; clear `needs_you` when nothing
  else is open for the item.
- The user answers in the popup (tmux prefix `y`). The answer arrives as an inbox message of kind
  `decision` or `clarify` (step 7), which the watcher wakes you with.

## 10. Wake check

Run it on a `[daily-wake] woke after …` prompt (the `daily` extension sends one when the Mac wakes
with agents outstanding) and on a resume (step 0). Never file a decision from this step and never
ask: act, then say what you did. Items with `owner=external:<KEY>` are never touched here.

For each `owner=main` run-state line, call `subagent_result({id})` for its `agent=` id and its
`round=` id (each is one row; the head line says `done`, `failed` or `stopped`, or `running`):

- `running` → leave it; never dispatch a second agent for that item. If a `[pi-sub]` notice listed
  it as orphaned, `subagent_adopt({id})` so its wake-up reaches this session.
- `done`, and the id is still the item's `agent=` or `round=` (otherwise it was processed already:
  skip it) → if a `[pi-sub]` notice listed it as orphaned, `subagent_adopt({id})` first, so it is
  not listed again at the next session start. Process the `subagent_result` text (`lines` raised
  until the whole report shows) exactly as step 3 for a ticket agent (a `class=review` item: the review report, step 2), or step 5.5 for a review
  round; that sets `agent=-` or `round=-`, so its late `[pi-sub]` wake-up is ignored.
- `failed` or `stopped`, or an id pi-sub does not know → its process is gone (a live one shows
  `running` and is adopted above). A complete final report in its result (it failed, or names what
  blocks it) is a real failure: process it as step 3 or 5.5, so a failed check takes the normal
  retry. No result, or one cut off mid-work, means it was interrupted, and pi-sub cannot message
  it: continue it with a fresh `worker` in the same worktree (step 2 without `wt add`; a round
  gets the review-round brief, step 5.2) with its last result (the `subagent_result` text, or
  `none`) and `git -C <worktree> log --oneline -5` appended to the brief under `## Resume note`,
  and record the new id in `agent=` or `round=`. It counts as the same attempt, not a retry:
  `retries` stays. A worktree that is gone is recreated as for a `handback` (step 7); worktree and
  branch both gone is the blocker there (`[!]`, `needs_you=yes`).

A `[pi-sub idle]` flag after a wake: pi-sub has no message to a running agent, so leave it and
mention in your reply that it is quiet; no decision, no stop, no second agent.

Then process the inbox (step 7) and any `[daily-event]` messages still unanswered, and redo the
event you were handling if your last reply was cut off. End with one line per row:
`<KEY>: left running | report processed | continued | re-dispatched`.

## 11. Keep busy

Run this after every processed agent report, finished or blocked item and answered decision, at
the end of the dispatch in step 2, and on a `[daily-idle] no agent running: …` message. While fewer
than 3 agents run (ticket, review and round agents all count), fill the free slots in this order:

1. Queued `auto` and `review` items, in plan order (step 2).
2. Open `wait` and `me` items whose state moved: a `wait` item whose blocker cleared is dispatched (a `review` item only after `review-gate <project path> <iid>` exits 0; 1: class `me`, `already approved`; 3: leave it);
   for a merge item with a green pipeline and approvals and no decision open, file the merge
   decision with the MR link.
3. The sprint: the user's tickets first, then the team's unassigned To-Do tickets, highest rank
   first. Each line is `KEY<TAB>status<TAB>summary`:

```bash
jt --list -m
jt --list -u
```

   Skip keys already on the plan or in the run state, the user's tickets whose status is not
   `To-Do` or `In Progress`, epics, and tickets an agent cannot finish alone: read each candidate with
   `jira-issue <KEY>`; it needs a description that says what done looks like, and one repo you can
   name. Take as many as there are free slots. For each: add
   `- [ ] <key> <summary> (sprint: yours|unassigned)` under a `**From the sprint**` group (create
   it after the last group, above the link definitions), track it `class=auto`, and dispatch it as
   step 2.
   - An unassigned ticket is not the user's yet: add `## Not yours yet` to its brief with
     `Commit locally; do not push and do not open an MR.`, and file a decision (step 9):
     `Take <KEY> from the sprint?` with options `Take it` (assigns it to you in Jira; the agent
     pushes and opens the Draft MR) and `Leave it`. On `Take it`:
     `jira-api GET myself | jq -r .accountId`, then
     `jira-api PUT "issue/<KEY>/assignee" '{"accountId":"<id>"}'`, and start a fresh `worker` in its
     worktree to push and open the Draft MR. On `Leave it`: stop the agent and mark the line
     `[>] · note: left in the sprint`.
     Its report before `Take it` (also from the Wake check): run step 3's diff and test checks
     without the MR and pipeline parts, since there is none yet. Passing: `agent=-` and the line
     `[/] · ready locally, waiting on Take it` (no tick, no retry); the fresh worker after
     `Take it` pushes and opens the Draft MR, and its report gets the full step 3.
   - `jt` fails: say so in one line and try again at the next Keep busy.
4. Nothing in steps 1-3: Finish (step 8), naming what each step found empty.

Never end a turn saying the rest is the user's while a slot is free and one of steps 1-3 has
something. A review, a merge check or a sprint ticket is not the user's work because what comes
out of it is posted under their name: an agent drafts it, and a decision asks before anything is
posted.
