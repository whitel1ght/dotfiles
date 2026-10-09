---
description: Work today's plan with parallel ticket agents, tick the diary, and record decisions and project updates in ~/wiki
argument-hint: [--dry | resume]
disable-model-invocation: true
---

# Run the day

Arguments: $ARGUMENTS

You are the orchestrator of today's plan. Follow `/orchestrate`'s rules (`~/.claude/commands/orchestrate.md`) for choosing models, writing briefs, checking results and escalating; this command only adds what is specific to a day run. Heavy-route tickets (several repos, or a contract between services) follow `/orchestrate`'s heavy route as one item.

Paths used below (`T` is today's date, `date +%F`):
- Diary: `~/wiki/diary/T.md`. The plan is the block between `<!-- start-day:start -->` and `<!-- start-day:end -->`. Only lines inside it are ever edited.
- Run state: `~/.local/state/run-day/T.md`. While it exists the SessionStart hook, the status line and the watcher are active. `/day-plan` (or prefix+e in tmux) opens today's plan in nvim in a popup.
- Vault: `~/wiki`. Rules: `~/wiki/AGENTS.md`.
- Inbox: `~/.local/state/run-day/inbox/`. Other sessions leave messages there (section 7).

## Write rules (never break these)

- Subagents never write to `~/wiki`. This session is the only writer during the day.
- This session edits only: diary lines inside the plan block, the run-state file, inbox files it moves to `inbox/done/<T>/` or `inbox/bad/`, `~/wiki/projects/<p>/log/<YYYY>-Q<N>.md` (append), `~/wiki/projects/<p>/decisions/NNNN-<slug>.md` (create; and an old decision's `status` (only to `superseded`), section 4). It never edits project code (`/orchestrate`: that goes to subagents).
- Never merge, mark an MR ready, transition a Jira ticket, post to Slack or post a comment without asking. The one exception is a review round (below), which has its own single confirmation.
- Every MR number in text you show the user is a markdown link with the repo in the link text, e.g. `[dashboard!2202](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2202)`, never a bare `!2202`. Known paths: `ecfx/ecfx-backend`, `ecfx/ecfx-dashboard`, `ecfx/ecfx-admin`, `ecfx/ecfx-protobufs`, `ecfx/claude-components`.
- Each Bash call is a new shell: re-set the variables a block uses in that same call, or use literal values. Nothing set in an earlier block is still there.
- A GitLab API merge returns 405 on these repos: for a merge item, give the user the MR link to merge in the UI.

## 0. Start

1. Read the plan block:

```bash
T="$(date +%F)"
awk '/<!-- start-day:start -->/{f=1;next} /<!-- start-day:end -->/{f=0} f' ~/wiki/diary/$T.md
```

   Empty output: tell the user to run `/start-day` first, and stop.
2. If `~/.local/state/run-day/$T.md` exists and the argument is not `--dry`, this is a resume: read it and skip triage. Background agents from before the resume are gone: for each `[/]` item with no report in this session, tell the user and, on their yes, re-dispatch it into its existing worktree (step 2.2, without `wt add`). Items whose run-state line says `owner=external:<KEY>` are in a side session: never re-dispatch them. Then process the inbox (section 7) and continue at step 3.

## 1. Triage (the one planned pause)

Classify every open item (`[ ]`, `[/]`, `[!]`; skip `[x]` and `[>]`):

- **auto**: ticket work an agent can do (fix, implement, address review, write tests).
- **me**: syncs, meetings, merges, decisions, replies to people.
- **wait**: blocked on others.

Get what you need for each auto item from the plan line (ticket key, MR links name the repo) and `jira-api GET issue/<KEY>` (summary, description). Show one table: item, class, repo(s), model, depends on. A multi-repo ticket is one item on the heavy route. If you cannot tell the repo, class it `me` and say why. **Wait for approval or edits.**

With `--dry`: stop after printing the table (a merge-class `me` row says: merged in the UI by you, with the MR link, because the API merge returns 405), then print for each auto item the `wt add` command and the filled-in brief (step 2), and a closing line `dry run: nothing created`. Create no worktree, no agent, no run-state file, and edit nothing.

## 2. Dispatch

1. Create the run-state file (and its directory). Format, one line per tracked item, fields in this order, `-` for empty, no ` | ` inside a value, `mr` comma-separated as `<group>/<repo>!<iid>`:

```
# run-day 2026-10-08
max_agents: 3
- ecfx-18169 | class=auto | agent=- | worktree=- | mr=- | retries=0 | needs_you=no | owner=main
notes:
  ecfx: <one line from a state_change>
```

   Only lines starting with `- ` are items; `notes:` and the indented lines under it carry `state_change` lines for `/end-day`.

   `owner` is `main` (this session dispatches and checks the item) or `owner=external:<KEY>` (a side session works it after `/handoff`; the item is never dispatched, never gets a review-round agent, and has no agent id). It is optional on read and defaults to `main`; always write it.

   Immediately after creating the file, seed the watcher cursor so the first watcher tick does not replay events from earlier today (a missing cursor means "since the beginning"):

```bash
changes-since --cursor run-day >/dev/null
```

   If it exits non-zero, tell the user in one line and carry on: the watcher reports the failure itself once.

   The key is the lowercase ticket key from the plan line. Items without a ticket key are not tracked in this file.
2. For each auto item, in plan order, while fewer than **3** ticket agents are running (review-round agents count): `wt add <repo> <KEY> <branch>` with the branch from `glab mr view` when the item already has an MR or branch, else `wt add <repo> <KEY>` (KEY uppercase, e.g. `ECFX-18169`), fill `${CLAUDE_PLUGIN_ROOT}/templates/ticket-brief.md` (replace every `{{...}}` placeholder; `grep -c '{{'` on the filled brief must print 0), save it in the scratchpad as `brief-<key>.md`, and spawn a background `sonnet` subagent: `Agent` with `run_in_background: true`, `model: "sonnet"`, `description: "<KEY> <three words>"`, the repo's specialist `subagent_type` when one exists, and a prompt that points at the brief file. Skip items whose run state says `owner=external:<KEY>`. Queue the rest in plan order; start the next as one finishes.
3. Record the agent id the `Agent` call returned, the worktree and `needs_you=no` in the run-state line. Set the diary line to `[/]`.

## 3. Diary markers and check-before-tick

Markers: `[ ]` todo, `[/]` in progress, `[x]` done, `[!]` blocked, `[>]` deferred to tomorrow. Evidence goes after ` · ` at the end of the line, e.g. `· draft MR dashboard!2240  [↗][dashboard!2240]` or `· blocked: <reason>`. Links are trailing refs: the label stays plain text, `  [↗][<repo>!<iid>]` ends the line, and the URL sits once in a `[<repo>!<iid>]: <url>` definition just above `<!-- start-day:end -->`. Write the inline `[<repo>!<iid>](<url>)` if it is easier; `diary-links` converts it. Edit one line at a time with the Edit tool, then run `diary-links ~/wiki/diary/$(date +%F).md` (no output when fine; do it after every diary edit). The tick guard refuses an `[x]` that carries no MR link, `merged` or `· note: <why>`; for a `me` item you ticked on the user's word, write `· note: <what the user said>`.

When a ticket agent reports:
1. Read its report. Run `git -C <worktree> diff --stat` and check it matches what the report claims.
2. Confirm it ran the tests it names, by running the same command yourself, and that the MR pipeline status is known (`glab api "projects/<urlencoded path>/merge_requests/<iid>" | jq -r .head_pipeline.status`).
3. All good: tick `[x]` with `· draft MR <repo>!<iid>  [↗][<repo>!<iid>]`, then apply the `memory:` block (step 4), update the run-state line (`mr=`), and dispatch the next queued item.
4. A check fails: **one retry** with the next model tier (`sonnet` then `opus`), the failure quoted in the brief, `retries=1`. A second failure: mark `[!]` with `· blocked: <reason>`, set `needs_you=yes`, call `PushNotification` with the ticket key and the reason.

## 4. Applying a `memory:` block

For `project: <p>` (`ecfx`, `epicmax` or `personal`):

```bash
P=ecfx
Q="$(date +%Y)-Q$(( (10#$(date +%m) + 2) / 3 ))"
mkdir -p ~/wiki/projects/$P/log ~/wiki/projects/$P/decisions
LAST="$(ls ~/wiki/projects/$P/decisions | rg -o '^[0-9]{4}' | sort | tail -1)"
NEXT="$(printf '%04d' $((10#${LAST:-0} + 1)))"
```

- **log**: append to `~/wiki/projects/$P/log/$Q.md` a `## YYYY-MM-DD <short title>` heading and the paragraph (100 to 300 words; shorten a longer one). A new file starts with the frontmatter that `~/wiki/_templates/log-entry.md` prescribes (`project`, `type: log`, `date` of its first entry), then a blank line:

```bash
P=ecfx
Q="$(date +%Y)-Q$(( (10#$(date +%m) + 2) / 3 ))"
LOGF=~/wiki/projects/$P/log/$Q.md
[ -f "$LOGF" ] || printf -- '---\nproject: %s\ntype: log\ndate: %s\n---\n\n' "$P" "$(date +%F)" > "$LOGF"
```
- **decision** (not `none`): create `~/wiki/projects/$P/decisions/$NEXT-<slug>.md` from `~/wiki/_templates/decision.md`: copy the template, fill its `{{project}}`, `{{date}}`, `{{tickets}}`, `{{repos}}`, `{{num}}` (`$NEXT`) and `{{title}}` tokens, and replace the `<...>` hints under Context, Decision and Consequences with the block's `context`, `decision` and `consequences`. Keep the template's frontmatter as is (`status: accepted`). Delete the commented `# supersedes:` line, unless the decision replaces one: then make it `supersedes: <NNNN-old-slug>` and change the old file's `status` to `superseded`, the only edit a decision file ever gets.
- **state_change**: do not edit `state.md`; `/end-day` consolidates it. Append it as `  <p>: <line>` under `notes:` in the run-state file so it survives compaction.

## 5. Review rounds (automatic, one confirmation per round)

Trigger: a prompt line `[daily-event] review | ...` or `[daily-event] comment | ...` for an MR attached to a today item (the watcher only sends those; event line format: `[daily-event] <kind> | <repo>!<iid> | <TICKET> | <summary> | <url>`).

If the item's run-state `owner` is `external:<KEY>`, do not spawn a review-round agent for it: its branch is in a side session. Tell the user the review arrived (MR link per the rule) and that `/pickup` in that session can address it, set `needs_you=yes`, and stop here.

1. Take the GitLab project path and iid from the event's `url` field (the fifth field of the event line), never from the short `<repo>!<iid>` form, which has no group. For `https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231` the path is `ecfx/ecfx-dashboard` and the iid is `2231`:

```bash
URL='<url from the event line>'
PROJECT_PATH="$(printf '%s' "$URL" | sed -E 's#^https?://[^/]+/(.+)/-/merge_requests/[0-9]+.*$#\1#')"
IID="$(printf '%s' "$URL" | sed -E 's#^.*/merge_requests/([0-9]+).*$#\1#')"
ENC="${PROJECT_PATH//\//%2F}"
printf '%s %s %s\n' "$PROJECT_PATH" "$IID" "$ENC"
```

   `<urlencoded path>` below means the `$ENC` value printed by this block (write it out literally in later calls, or derive it again in the same call), `{{PROJECT_PATH}}` is `$PROJECT_PATH`, `{{MR_IID}}` is `$IID`. If the url is `-` or does not match, use the `mr=<group>/<repo>!<iid>` field of the item's run-state line instead; if that is empty too, ask the user for the MR link.
   Find the item's worktree in the run-state file. If it has none, get the branch with `glab api "projects/<urlencoded path>/merge_requests/<iid>" | jq -r .source_branch` and run `wt add <repo> <KEY> <branch>`.
2. Spawn a background `sonnet` subagent (counts toward the cap of 3) with `${CLAUDE_PLUGIN_ROOT}/templates/review-round-brief.md` filled in. `{{REPLY_FILE}}` is `<scratchpad>/round-<repo>-<iid>.md`. The template's ten placeholders are {{BRANCH}}, {{EVENT_LINE}}, {{KEY}}, {{MR_IID}}, {{MR_URL}}, {{PROJECT_PATH}}, {{PROJECT}}, {{REPLY_FILE}}, {{REPO}}, {{WORKTREE}} (the template is the source of truth); `grep -c '{{'` on the filled review-round brief must print 0. The agent fixes (commits locally, no push) or declines or defers every finding and drafts the reply; `shared:mr-review-response` has no draft-only mode, so the brief stops it before its post step.
3. When it reports: run the check from step 3 on the diff and tests. Set `needs_you=yes`. Show the user: the findings with their status and SHAs, `git log --oneline` of the new commits, and the full draft reply (`cat` the reply file). Ask: `yes` / `edit` / `no`.
4. `yes`: `git -C <worktree> push`, then post the reply into the review's discussion:

```bash
glab api --method POST "projects/<urlencoded path>/merge_requests/<iid>/discussions/<discussion id>/notes" -F "body=@<reply file>"
```

   `<discussion id>` comes from the agent's `discussion:` report line. Then set `needs_you=no`, apply the `memory:` block, and say that a Jira one-liner with the new head SHA is available (post it only if the user says so, through the `jira-write` skill).
   `edit`: apply the user's changes to the reply file or send the agent back (`SendMessage`) and show again. `no`: push and post nothing; leave the commits in the worktree; set the item `[!]` with `· note: review round declined by user` only if the user says to.

## 6. Other events

- `[daily-event] assigned | ...`: offer to add the ticket to today's plan; on yes add one `- [ ] <key> <summary>` line under `**Today**` (never add on your own) and triage it like step 1.
- `[daily-event] pipeline_failed | ...` on a today MR: dispatch a fix agent under the normal autonomy rule (ticket brief, done-when: the pipeline on the branch is green), within the cap of 3.
- `[daily-event:info] ...` lines: no action. Mention them only if the user asks what changed.
- `inbox: <N> new` (from the mod): process the inbox, section 7.
- Before handling any other event or agent report, list the inbox (section 7) and process what is waiting. Then re-read the plan block: the user edits the diary too. An item they ticked or removed is theirs; do not touch it.
- No mod (the status line stays empty): there is no watcher and no inbox listing. Start `/loop 5m` with the prompt `check the run-day inbox (section 7), then run changes-since --cursor run-day and handle each line it prints as an event`, and keep the rule above.

## 7. Inbox (hand-offs, report-backs, off-plan work)

Other Claude sessions and the terminal leave messages in `~/.local/state/run-day/inbox/` (`day-note`, `/report-back`). Process them when the prompt line `inbox: <N> new` arrives, when you start or resume, before handling any other event (section 6), and on every `/loop` tick when the mod is not active.

```bash
INBOX=~/.local/state/run-day/inbox
T="$(date +%F)"
ls -1 "$INBOX" 2>/dev/null | grep -E '^[0-9]{8}T[0-9]{6}-[A-Za-z0-9-]+-[A-Za-z0-9]{4}\.md$' | sort
```

Only names of that shape are messages (the same rule as the mod); `*.tmp`, `done/`, `bad/` and any other file are ignored, never moved, and not mentioned in any output, even if they appear in `ls`. `$f` in the commands below is `$INBOX/<name>`.

File names start with a timestamp, so that order is **oldest first**. Handle one file completely before the next. A message is frontmatter between two `---` lines, one summary paragraph, then a `memory:` block (the four fields of an agent report):

```
---
key: ECFX-18169            # empty for off-plan work without a ticket
kind: done | progress | handback | offplan
session: ECFX-18169
repo: ecfx-dashboard       # optional
mr: https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231   # optional
at: 2026-10-08T15:42:00+03:00
---
<one-paragraph summary>

memory:
  project: ecfx
  log: "<one paragraph>"
  decision: {title, context, decision, consequences} | none
  state_change: "<one line>" | none
```

1. **Validate.** The message is malformed when: the frontmatter is missing or has no closing `---`; `kind` is not one of `done`, `progress`, `handback`, `offplan`; `key` (compare case-insensitively; `day-note` upper-cases it) is not `[A-Za-z][A-Za-z0-9]*-[0-9]+` (an empty key is fine for any kind, it makes the message off-plan work, step 2); the summary is empty; or the `memory:` block names a `project` other than `ecfx`, `epicmax` or `personal`. A message with no `memory:` block is not malformed, there is just nothing to apply. A malformed file goes to `~/.local/state/run-day/inbox/bad/`:

```bash
INBOX=~/.local/state/run-day/inbox
f="$INBOX/<name>"
mkdir -p "$INBOX/bad"; mv "$f" "$INBOX/bad/"
```

   Tell the user in one line (file name and the reason), then carry on with the next file. Never repair a file, never stop the queue.
2. **Find the item.** `<key>` is the lowercase `key`. The plan line is the one inside the start-day block whose ticket key equals it exactly, ignoring case (`ecfx-1816` does not match `ecfx-18169`); the run-state line has the same key. A key that is not on the plan, and an empty key, make the message off-plan work whatever its `kind` says (except `handback`, below).
3. **Apply by kind.** For every `[x]` you write, the tick guard needs an MR link, `merged` or `· note: <why>`; the *summary clip* below is the first sentence of the summary, at most 100 characters, with any ` · ` replaced by ` - `. When the message has an `mr`, the run-state `mr=` becomes `<group>/<repo>!<iid>` (derive the path and iid from the url as in section 5).
   - `done`, key on the plan: run the check of section 3 as far as it can be run: `git -C <worktree> diff --stat` when the run-state worktree exists, the MR pipeline status when `mr` is set, the tests the summary names. What cannot be checked (no worktree, no MR) is named to the user as unverified. Checks pass or cannot run: tick `[x]` with `· MR <repo>!<iid>  [↗][<repo>!<iid>]` when `mr` is set, otherwise `· note: <summary clip>` (`done` replaces any existing `· with you:` / `· progress:` suffix); set `owner=main` and `needs_you=no`. A check fails: do not tick, keep `[/]`, set `needs_you=yes`, tell the user what failed (no agent exists to retry). A line that is already `[x]` stays as it is; never downgrade a ticked line.
   - `progress`, key on the plan: `[/]`, suffix `· progress: <summary clip>` (after `· with you: <KEY>` when the owner is external); `owner` stays. A line that is already `[x]` is left entirely as it is (a late `progress` is a no-op; never downgrade a ticked line).
   - A key with no run-state line (a `me` item, or one added to the plan later): skip every run-state edit, apply only the diary line and the memory block.
   - `handback`, key on the plan: `owner=main`, `agent=-`, `needs_you=no`, marker `[ ]`, suffix `· handed back: <summary clip>`; the item goes back into the dispatch queue (section 2.2) in plan order. When it is dispatched, append the message body to the filled brief as a `## Hand-back note` section so the agent starts from it. If `test -d <worktree>` fails, the worktree is gone: take the branch from `~/.local/state/run-day/handoff/<KEY>.md` or from the MR (`glab api "projects/<urlencoded path>/merge_requests/<iid>" | jq -r .source_branch`) and run `wt add <repo> <KEY> <branch>`; if no branch can be found, mark `[!]` with `· blocked: worktree is gone and the branch was not found`, `needs_you=yes`, and tell the user. Tell the user the item was re-queued. A `handback` for a key that is not on the plan, or with an empty key, has no item to queue: tell the user and only apply its memory block.
   - `offplan`, or `done` / `progress` for a key that is not on the plan, or an empty key: write one line under the `**Unplanned**` group, the last group of the block. Unplanned lines always go immediately above `<!-- start-day:end -->`; when the group does not exist yet, create it in the same Edit (old_string `<!-- start-day:end -->`):

```
<blank line>
**Unplanned**
- [x] ecfx-18200 fix typo in export header · MR dashboard!2250  [↗][dashboard!2250]

[dashboard!2250]: https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2250
<!-- start-day:end -->
```

     The line is `- [x] <key lowercase, if any> <summary clip, 80 characters> · <evidence>`: `[x]` by default, `[/]` when the summary says the work is unfinished (wip, started, in progress, continuing); evidence is `MR <repo>!<iid>  [↗][<repo>!<iid>]` when `mr` is set, else `note: <summary clip>`. No run-state line. If the same key already has an Unplanned line, update that line instead of adding another. An `offplan` message whose key is on the plan means the plan changed after it was written: treat it as `progress`.
   - A second message for the same key is handled in file order, each in full: the later marker and evidence win, except that you never downgrade `[x]`, and both `memory:` blocks are applied (two log entries).
4. **Memory.** For every kind, apply the `memory:` block (section 4) with the `project` it names.
5. **File it away.** Once steps 3 and 4 succeeded, move the file to `~/.local/state/run-day/inbox/done/$T/` (today's date, not the message's):

```bash
INBOX=~/.local/state/run-day/inbox
T="$(date +%F)"
f="$INBOX/<name>"
mkdir -p "$INBOX/done/$T"; mv "$f" "$INBOX/done/$T/"
```

   If a step failed, leave the file where it is, tell the user, and go on to the next one; never retry in a loop.

When the queue is empty, print one line per message: file name, what changed. MR numbers are links per the rule above.

## 8. Finish

When no item is `[ ]` or `[/]` any more (or the user says so; a `[/] · with you: <KEY>` line is still open), process the inbox once more, then print a summary: done, blocked, deferred, what needs the user. Suggest `/end-day`. The same session runs `/end-day`; do not delete the run-state file, `/end-day` does.
