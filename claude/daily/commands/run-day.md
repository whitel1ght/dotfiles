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

- Subagents never write to `~/wiki`, except `~/wiki/work/system/` and `~/wiki/tools/` when they change one of the system repos (dotfiles, decisions, articles); they commit those with `wiki-commit`. Otherwise this session is the only writer during the day.
- This session edits only: diary lines inside the plan block, the run-state file, inbox files it moves to `inbox/done/<T>/` or `inbox/bad/`, `~/wiki/work/projects/<p>/log/<YYYY>-Q<N>.md` (append), `~/wiki/work/projects/<p>/decisions/NNNN-<slug>.md` (create; and an old decision's `status` (only to `superseded`), section 4). It never edits project code (`/orchestrate`: that goes to subagents).
- Never merge, mark an MR ready, transition a Jira ticket, post to Slack or post a comment without the user's yes. Asking means a decision (section 9); a review round (below) is one decision per round.
- Questions for the user go into the decision queue (section 9): never ask the question in the thread, never wait for the answer. The only question asked in the thread is the triage go-ahead (section 1).
- Every MR number in text you show the user is a markdown link with the repo in the link text, e.g. `[dashboard!2202](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2202)`, never a bare `!2202`. Known paths: `ecfx/ecfx-backend`, `ecfx/ecfx-dashboard`, `ecfx/ecfx-admin`, `ecfx/ecfx-protobufs`, `ecfx/claude-components`.
- Each Bash call is a new shell: re-set the variables a block uses in that same call, or use literal values. Nothing set in an earlier block is still there.
- A GitLab API merge returns 405 on these repos: for a merge item, give the user the MR link to merge in the UI.
- When the user says they want to work a tracked item themselves ("I'll take it", "hand off 18384"), run the handoff yourself with the Skill tool (`daily:handoff`, the item's key as the argument) instead of asking them to type it.

## 0. Start

1. Read the plan block:

```bash
T="$(date +%F)"
awk '/<!-- start-day:start -->/{f=1;next} /<!-- start-day:end -->/{f=0} f' ~/wiki/diary/$T.md
```

   Empty output: tell the user to run `/start-day` first, and stop.
2. If `~/.local/state/run-day/$T.md` exists and the argument is not `--dry`, this is a resume: read it and skip triage. Background agents from before the resume may be gone: run the Wake check (section 10). Items whose run-state line says `owner=external:<KEY>` are in a side session: never re-dispatch them. Then continue at step 3.

   When the argument is `resume updated`, the plugin started this resume itself: a merge into dotfiles main changed this playbook or a brief template, the plugin folder reloaded, and the mod ran `/daily:run-day resume updated`. In that case, before the Wake check, say in one line what changed (`git -C ~/projects/dotfiles log --oneline -3 -- claude/daily`); after the resume, run Keep busy (section 11). From now on follow this text, not the copy you read earlier in this session, wherever the two differ. Agents already running keep their briefs.

## 1. Triage (the one planned pause)

Classify every open item (`[ ]`, `[/]`, `[!]`; skip `[X]` and `[>]`):

- **auto**: ticket work an agent can do (fix, implement, address review, write tests).
- **review**: someone else's MR to review or re-review. An agent drafts the review (section 2 step 4); posting it is one decision. Never for an MR we already approved (D-011): when `glab api "projects/<urlencoded path>/merge_requests/<iid>/approvals" | jq -r '.approved_by[].user.username'` lists `whitel1ght`, class it `me` with `already approved`.
- **me**: syncs, meetings, merges, decisions, replies to people. A review is not a reply: it is `review`.
- **wait**: blocked on others.

Get what you need for each auto item from the plan line (ticket key, MR links name the repo) and `jira-api GET issue/<KEY>` (summary, description). Show one table: item, class, repo(s), model, depends on. A multi-repo ticket is one item on the heavy route. If you cannot tell the repo, class it `me` and say why. **Wait for approval or edits.**

With `--dry`: stop after printing the table (a merge-class `me` row says: merged in the UI by you, with the MR link, because the API merge returns 405), then print for each auto item the `wt add` command and the filled-in brief (step 2), and a closing line `dry run: nothing created`. Create no worktree, no agent, no run-state file, and edit nothing.

## 2. Dispatch

1. Create the run-state file (and its directory). Format, one line per tracked item, fields in this order, `-` for empty, no ` | ` inside a value, `mr` comma-separated as `<group>/<repo>!<iid>`:

```
# run-day 2026-10-08
max_agents: 3
- ecfx-18169 | class=auto | agent=- | round=- | worktree=- | mr=- | retries=0 | needs_you=no | owner=main
notes:
  ecfx: <one line from a state_change>
```

   Only lines starting with `- ` are items; `notes:` and the indented lines under it carry `state_change` lines for `/end-day`.

   `owner` is `main` (this session dispatches and checks the item) or `owner=external:<KEY>` (a side session works it after `/daily:handoff`; the item is never dispatched, never gets a review-round agent, and has no agent id). It is optional on read and defaults to `main`; always write it.

   `agent` is the ticket agent's id and `round` the review-round agent's id (section 5), each set back to `-` once its report is processed.

   `waiting=<service>` (`gitlab` or `jira`) is a tenth field, written only while an item is parked on an outage (section 6); drop it when the item resumes.

   Immediately after creating the file, seed the watcher cursor so the first watcher tick does not replay events from earlier today (a missing cursor means "since the beginning"):

```bash
changes-since --cursor run-day >/dev/null
```

   If it exits non-zero, tell the user in one line and carry on: the watcher reports the failure itself once.

   The key is the lowercase ticket key from the plan line. Items without a ticket key are not tracked in this file, except a `review` item: its key is `<repo letters>-<iid>` (the repo name without `ecfx-` and without dashes, e.g. `claudecomponents-55`), so decision answers pass the inbox key check (section 7).
2. For each auto item, in plan order, while fewer than **3** ticket agents are running (review-round agents count): `wt add <repo> <KEY> <branch>` with the branch from `glab mr view` when the item already has an MR or branch, else `wt add <repo> <KEY>` (KEY uppercase, e.g. `ECFX-18169`), fill `${CLAUDE_PLUGIN_ROOT}/templates/ticket-brief.md` (replace every `{{...}}` placeholder; `grep -c '{{'` on the filled brief must print 0), save it in the scratchpad as `brief-<key>.md`, and spawn a background `sonnet` subagent: `Agent` with `run_in_background: true`, `model: "sonnet"`, `description: "<KEY> <three words>"`, the repo's specialist `subagent_type` when one exists, and a prompt that points at the brief file. Skip items whose run state says `owner=external:<KEY>`. Queue the rest in plan order; start the next as one finishes.
3. Record the agent id the `Agent` call returned, the worktree and `needs_you=no` in the run-state line (`agent=` keeps the id until its report is processed, section 3). Set the diary line to `[/]`.
4. Each `review` item, in plan order, under the same cap of 3 (ticket, review and round agents all count): read `source_branch`, `sha`, `title` and `author.username` from `glab api "projects/<urlencoded path>/merge_requests/<iid>"`; `wt add <repo> review-<iid> <source branch>` (reuse the worktree when it exists), then `git -C <worktree> fetch -q origin` and `git -C <worktree> checkout -q --detach <sha>`. Fill `${CLAUDE_PLUGIN_ROOT}/templates/review-brief.md` (`{{KIND}}`: `first review`, or `re-review: replies or commits since my review of <date>`; `{{REVIEW_FILE}}`: `<scratchpad>/review-<repo>-<iid>.md`; `grep -c '{{'` must print 0) and spawn a background `sonnet` subagent as in step 2. Run-state line: `class=review`, `agent=<id>`, `worktree=<path>`, `mr=<group>/<repo>!<iid>`. Set the diary line to `[/]`.

   When a review agent reports (and its id is still the item's `agent=`; otherwise ignore it, section 3): check the review file exists and spot-check two `file:line` claims in the worktree. Set `agent=-` and `needs_you=yes` and file a decision (section 9): `--blocks post`, question `Post the review of <repo>!<iid>?`, context the agent's verdict line and counts and the whole review file (`cat` it), options `Post it` (`Post it and approve` when the verdict is approve; recommended), `Change it first (add a note with n)`, `Post nothing`. On post: `glab api --method POST "projects/<urlencoded path>/merge_requests/<iid>/notes" -F "body=@<review file>"`, and for approve `glab api --method POST "projects/<urlencoded path>/merge_requests/<iid>/approve" -f sha=<reviewed sha>` (the `sha` the review was drafted at: GitLab refuses when the author pushed since, and then the item goes back to review as a re-review); tick `[X]` with `· review posted` (`· review posted, approved`), set `needs_you=no`, apply the `memory:` block. On change: apply the note to the file, or send the agent back with `SendMessage`, then file a new decision. On post nothing: `[X] · note: review not posted, user's call`. Then Keep busy (section 11).

## 3. Diary markers and check-before-tick

Markers: `[ ]` todo, `[/]` in progress, `[X]` done (an older `[x]` counts too), `[!]` blocked, `[>]` deferred to tomorrow. Evidence goes after ` · ` at the end of the line, e.g. `· draft MR dashboard!2240  [↗][dashboard!2240]` or `· blocked: <reason>`. Links are trailing refs: the label stays plain text, `  [↗][<repo>!<iid>]` ends the line, and the URL sits once in a `[<repo>!<iid>]: <url>` definition just above `<!-- start-day:end -->`. Write the inline `[<repo>!<iid>](<url>)` if it is easier; `diary-links` converts it. Edit one line at a time with the Edit tool, then run `diary-links ~/wiki/diary/$(date +%F).md` (no output when fine; do it after every diary edit). The tick guard refuses an `[X]` that carries no MR link, `merged` or `· note: <why>`; for a `me` item you ticked on the user's word, write `· note: <what the user said>`. A ticket has one top-level line on the plan; indented `  - [ ]` children under it are the user's breakdown, which the tick guard and panel ignore: mark and annotate the parent line only, and never add a second top-level line for a key already on the plan (put the new action on its line instead).

Once a report is handled, whatever the outcome (ticked, retried, blocked, parked on an outage, decision filed), and whenever you or the user stop an agent, set its `agent=` (or `round=`, section 5) to `-` or to the replacement's id. A report or completion notification from an agent id that is no longer the item's `agent=` or `round=` was already processed, by the Wake check (section 10) or before: ignore it.

When a ticket agent reports:
1. Read its report. Run `git -C <worktree> diff --stat` and check it matches what the report claims.
2. Confirm it ran the tests it names, by running the same command yourself, and that the MR pipeline status is known (`glab api "projects/<urlencoded path>/merge_requests/<iid>" | jq -r .head_pipeline.status`).
3. All good: tick `[X]` with `· draft MR <repo>!<iid>  [↗][<repo>!<iid>]`, then apply the `memory:` block (step 4), update the run-state line (`mr=`, `agent=-`), and run Keep busy (section 11).
4. A check fails: **one retry** with the next model tier (`sonnet` then `opus`), the failure quoted in the brief, `retries=1`, `agent=<new id>`. A second failure: mark `[!]` with `· blocked: <reason>`, set `needs_you=yes` and `agent=-`, call `PushNotification` with the ticket key and the reason, and run Keep busy (section 11).

## 4. Applying a `memory:` block

For `project: <p>` (`ecfx`, `epicmax` or `personal`):

```bash
P=ecfx
Q="$(date +%Y)-Q$(( (10#$(date +%m) + 2) / 3 ))"
mkdir -p ~/wiki/work/projects/$P/log ~/wiki/work/projects/$P/decisions
LAST="$(ls ~/wiki/work/projects/$P/decisions | rg -o '^[0-9]{4}' | sort | tail -1)"
NEXT="$(printf '%04d' $((10#${LAST:-0} + 1)))"
```

- **log**: append to `~/wiki/work/projects/$P/log/$Q.md` a `## YYYY-MM-DD <short title>` heading and the paragraph (100 to 300 words; shorten a longer one). A new file starts with the frontmatter that `~/wiki/work/_templates/log-entry.md` prescribes (`project`, `type: log`, `date` of its first entry), then a blank line:

```bash
P=ecfx
Q="$(date +%Y)-Q$(( (10#$(date +%m) + 2) / 3 ))"
LOGF=~/wiki/work/projects/$P/log/$Q.md
[ -f "$LOGF" ] || printf -- '---\nproject: %s\ntype: log\ndate: %s\n---\n\n' "$P" "$(date +%F)" > "$LOGF"
```
- **decision** (not `none`): create `~/wiki/work/projects/$P/decisions/$NEXT-<slug>.md` from `~/wiki/work/_templates/decision.md`: copy the template, fill its `{{project}}`, `{{date}}`, `{{tickets}}`, `{{repos}}`, `{{num}}` (`$NEXT`) and `{{title}}` tokens, and replace the `<...>` hints under Context, Decision and Consequences with the block's `context`, `decision` and `consequences`. Keep the template's frontmatter as is (`status: accepted`). Delete the commented `# supersedes:` line, unless the decision replaces one: then make it `supersedes: <NNNN-old-slug>` and change the old file's `status` to `superseded`, the only edit a decision file ever gets.
- **state_change**: do not edit `state.md`; `/end-day` consolidates it. Append it as `  <p>: <line>` under `notes:` in the run-state file so it survives compaction.

## 5. Review rounds (automatic, one decision per round)

Trigger: a prompt line `[daily-event] review | ...` or `[daily-event] comment | ...` for an MR attached to a today item (the watcher only sends those; event line format: `[daily-event] <kind> | <repo>!<iid> | <TICKET> | <summary> | <url>`).

If the item's run-state `owner` is `external:<KEY>`, do not spawn a review-round agent for it: its branch is in a side session. Tell the user the review arrived (MR link per the rule) and that `/daily:pickup` in that session can address it, set `needs_you=yes`, and stop here.

If the summary starts with `[approved by you — reply only, never review]` (`changes-since` marks it `approved_by_me`: someone else's MR we already approved), never start a review round or a re-review on that MR, now or later (D-011). If it asks us something, draft the answer and file it as a decision (`Post this reply on <repo>!<iid>?`, options `Post it` and `No`); otherwise do nothing. Stop here.

1. Take the GitLab project path and iid from the event's `url` field (the fifth field of the event line), never from the short `<repo>!<iid>` form, which has no group. For `https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231` the path is `ecfx/ecfx-dashboard` and the iid is `2231`:

```bash
URL='<url from the event line>'
PROJECT_PATH="$(printf '%s' "$URL" | sed -E 's#^https?://[^/]+/(.+)/-/merge_requests/[0-9]+.*$#\1#')"
IID="$(printf '%s' "$URL" | sed -E 's#^.*/merge_requests/([0-9]+).*$#\1#')"
ENC="${PROJECT_PATH//\//%2F}"
printf '%s %s %s\n' "$PROJECT_PATH" "$IID" "$ENC"
```

   `<urlencoded path>` below means the `$ENC` value printed by this block (write it out literally in later calls, or derive it again in the same call), `{{PROJECT_PATH}}` is `$PROJECT_PATH`, `{{MR_IID}}` is `$IID`. If the url is `-` or does not match, use the `mr=<group>/<repo>!<iid>` field of the item's run-state line instead; if that is empty too, file a decision asking for the MR link (the user answers with a question back, `c`, or a note) and skip the round until it arrives.
   Find the item's worktree in the run-state file. If it has none, get the branch with `glab api "projects/<urlencoded path>/merge_requests/<iid>" | jq -r .source_branch` and run `wt add <repo> <KEY> <branch>`.
2. Spawn a background `sonnet` subagent (counts toward the cap of 3) with `${CLAUDE_PLUGIN_ROOT}/templates/review-round-brief.md` filled in. `{{REPLY_FILE}}` is `<scratchpad>/round-<repo>-<iid>.md`. The template's ten placeholders are {{BRANCH}}, {{EVENT_LINE}}, {{KEY}}, {{MR_IID}}, {{MR_URL}}, {{PROJECT_PATH}}, {{PROJECT}}, {{REPLY_FILE}}, {{REPO}}, {{WORKTREE}} (the template is the source of truth); `grep -c '{{'` on the filled review-round brief must print 0. The agent fixes (commits locally, no push) or declines or defers every finding and drafts the reply; `shared:mr-review-response` has no draft-only mode, so the brief stops it before its post step. Record the id the `Agent` call returned as `round=<id>` on the item's run-state line.
3. When it reports (and its id is still the item's `round=`; otherwise ignore it, section 3): run the check from step 3 on the diff and tests. Set `round=-` (whatever the outcome, section 3) and `needs_you=yes` and file the round as a decision (section 9): `--blocks reply`, question `Push the fixes and post the review reply on <repo>!<iid>?`, the context the findings with their status and SHAs, `git log --oneline` of the new commits and the full draft reply (`cat` the reply file), and the options `Push and post the reply` (recommended), `Change the reply first (add a note with n)`, `Push nothing and post nothing`. When the answer arrives (section 7), option 1 is `yes`, option 3 is `no`, and option 2 or a question back with changes is `edit`.
4. `yes`: `git -C <worktree> push`, then post the reply into the review's discussion:

```bash
glab api --method POST "projects/<urlencoded path>/merge_requests/<iid>/discussions/<discussion id>/notes" -F "body=@<reply file>"
```

   `<discussion id>` comes from the agent's `discussion:` report line. Then set `needs_you=no`, apply the `memory:` block, and file a decision without `--blocks`, `Post a Jira one-liner with the new head SHA on <KEY>?` (options `Post it` and `No`); on `Post it`, post it through the `jira-write` skill.
   `edit`: apply the user's changes (the decision's note and Discussion) to the reply file or send the agent back (`SendMessage`; `round=<id>` again until it reports). When the changes came as a question back, the round's decision is still open: withdraw and close the old decision first. Then file a new decision for the revised reply. `no`: push and post nothing; leave the commits in the worktree; set the item `[!]` with `· note: review round declined by user` only if the user says to.

## 6. Other events

- `[daily-event] assigned | ...`: file a decision `Add <KEY> to today's plan?` (options `Add it` and `Not today`); on `Add it`, add one `- [ ] <key> <summary>` line under `**Today**` (never add on your own) and triage it like step 1.
- `[daily-event] pipeline_failed | ...` on a today MR: dispatch a fix agent under the normal autonomy rule per section 2.2-2.3 (ticket brief, done-when: the pipeline on the branch is green; its id recorded in `agent=`), within the cap of 3.
- A tool call fails because GitLab or Jira is unavailable (5xx, timeout, connection refused; not a 401/403 or a 404): do not retry it. Set `waiting=<service>` on the item's run-state line, run `wait-for <service> --detach --key <KEY>` (a no-op when one is already waiting) and move on to the next item. A background agent that hits it reports back instead of retrying; park its item the same way and set its `agent=` or `round=` to `-` (section 3). An item with `waiting=<service>` and no live `wait-for` lock (`~/.local/state/wait-for/<service>.lock` holding the pid of a running `wait-for`) was given up on: treat it as `gave up` below (`needs_you=yes`, `· blocked: <service> down`).
- `[daily-event:info] ...` lines: no action. Mention them only if the user asks what changed.
- `inbox: <N> new` (from the mod): process the inbox, section 7.
- `[daily-idle] no agent running: run Keep busy of /daily:run-day (section 11).` (from the mod, once per idle stretch after 10 minutes with no agent outstanding): run section 11.
- Before handling any other event or agent report, list the inbox (section 7) and process what is waiting. Then re-read the plan block: the user edits the diary too. An item they ticked or removed is theirs; do not touch it.
- No mod (the status line stays empty): there is no watcher and no inbox listing. Start `/loop 5m` with the prompt `check the run-day inbox (section 7), then run changes-since --cursor run-day and handle each line it prints as an event`, and keep the rule above.

## 7. Inbox (hand-offs, report-backs, off-plan work)

Other Claude sessions and the terminal leave messages in `~/.local/state/run-day/inbox/` (`day-note`, `/daily:report-back`). Process them when the prompt line `inbox: <N> new` arrives, when you start or resume, before handling any other event (section 6), and on every `/loop` tick when the mod is not active.

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
kind: done | progress | handback | offplan | service | decision | clarify   # service, decision, clarify: no memory block; decision, clarify carry decision: D-<n>
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

1. **Validate.** The message is malformed when: the frontmatter is missing or has no closing `---`; `kind` is not one of `done`, `progress`, `handback`, `offplan`, `service`, `decision`, `clarify`; `key` (compare case-insensitively; `day-note` upper-cases it) is not `[A-Za-z][A-Za-z0-9]*-[0-9]+` (an empty key is fine for any kind, it makes the message off-plan work, step 2); the summary is empty; or the `memory:` block names a `project` other than `ecfx`, `epicmax` or `personal`. A message with no `memory:` block is not malformed, there is just nothing to apply. A malformed file goes to `~/.local/state/run-day/inbox/bad/`:

```bash
INBOX=~/.local/state/run-day/inbox
f="$INBOX/<name>"
mkdir -p "$INBOX/bad"; mv "$f" "$INBOX/bad/"
```

   Tell the user in one line (file name and the reason), then carry on with the next file. Never repair a file, never stop the queue.
2. **Find the item.** `<key>` is the lowercase `key`. The plan line is the one inside the start-day block whose ticket key equals it exactly, ignoring case (`ecfx-1816` does not match `ecfx-18169`); the run-state line has the same key. A key that is not on the plan, and an empty key, make the message off-plan work whatever its `kind` says (except `handback`, below).
3. **Apply by kind.** For every `[X]` you write, the tick guard needs an MR link, `merged` or `· note: <why>`; the *summary clip* below is the first sentence of the summary, at most 100 characters, with any ` · ` replaced by ` - `. When the message has an `mr`, the run-state `mr=` becomes `<group>/<repo>!<iid>` (derive the path and iid from the url as in section 5).
   - `done`, key on the plan: run the check of section 3 as far as it can be run: `git -C <worktree> diff --stat` when the run-state worktree exists, the MR pipeline status when `mr` is set, the tests the summary names. What cannot be checked (no worktree, no MR) is named to the user as unverified. Checks pass or cannot run: tick `[X]` with `· MR <repo>!<iid>  [↗][<repo>!<iid>]` when `mr` is set, otherwise `· note: <summary clip>` (`done` replaces any existing `· with you:` / `· progress:` suffix); set `owner=main` and `needs_you=no`. A check fails: do not tick, keep `[/]`, set `needs_you=yes`, tell the user what failed (no agent exists to retry). A line that is already `[X]` stays as it is; never downgrade a ticked line.
   - `progress`, key on the plan: `[/]`, suffix `· progress: <summary clip>` (after `· with you: <KEY>` when the owner is external); `owner` stays. A line that is already `[X]` is left entirely as it is (a late `progress` is a no-op; never downgrade a ticked line).
   - A key with no run-state line (a `me` item, or one added to the plan later): skip every run-state edit, apply only the diary line and the memory block.
   - `handback`, key on the plan: `owner=main`, `agent=-`, `needs_you=no`, marker `[ ]`, suffix `· handed back: <summary clip>`; the item goes back into the dispatch queue (section 2.2) in plan order. When it is dispatched, append the message body to the filled brief as a `## Hand-back note` section so the agent starts from it. If `test -d <worktree>` fails, the worktree is gone: take the branch from `~/.local/state/run-day/handoff/<KEY>.md` or from the MR (`glab api "projects/<urlencoded path>/merge_requests/<iid>" | jq -r .source_branch`) and run `wt add <repo> <KEY> <branch>`; if no branch can be found, mark `[!]` with `· blocked: worktree is gone and the branch was not found`, `needs_you=yes`, and tell the user. Tell the user the item was re-queued. A `handback` for a key that is not on the plan, or with an empty key, has no item to queue: tell the user and only apply its memory block.
   - `decision` and `clarify` make no diary change and no Unplanned line, whatever the key.
   - `decision`: run `decide show <id>` (the `decision:` field) and apply the chosen option (`## Answer`, with any note) as if the user had said it here: dispatch, merge, reply to the reviewer, defer. An answer that reads `your words — <text>` (summary `answered in your own words`) picked none of the options: `<text>` is the user's instruction, so follow it as if they had typed it in the thread, and ask back with `decide add` only when it is unclear. Then clear the item's `needs_you` when `decide list --json` shows no other open decision for its key, run `decide close <id>`, and write one line in the thread: `<id>: <what you did>`.
   - `clarify`: answer with `decide reply <id> "<answer>"` (look it up first: code, MR, ticket; a cheap research agent may help). Nothing in the thread but `<id>: answered your question`.
   - `service`: the summary names the service. A summary ending `gave up` means it stayed down: every item whose run-state line has `waiting=<that service>` loses the field, gets `needs_you=yes` and `· blocked: <service> down` on its diary line, and is not resumed. Otherwise (`gitlab is back`) every item whose run-state line has `waiting=<that service>` loses the field and is picked up again where it stopped: re-dispatch into its existing worktree (section 2.2, without `wt add`), or redo the check that failed. No diary line changes, there is no Unplanned line, and no memory block (step 4 does not apply).
   - `offplan`, or `done` / `progress` for a key that is not on the plan, or an empty key: write one line under the `**Unplanned**` group, the last group of the block. Unplanned lines always go immediately above `<!-- start-day:end -->`; when the group does not exist yet, create it in the same Edit (old_string `<!-- start-day:end -->`):

```
<blank line>
**Unplanned**
- [X] ecfx-18200 fix typo in export header · MR dashboard!2250  [↗][dashboard!2250]

[dashboard!2250]: https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2250
<!-- start-day:end -->
```

     The line is `- [X] <key lowercase, if any> <summary clip, 80 characters> · <evidence>`: `[X]` by default, `[/]` when the summary says the work is unfinished (wip, started, in progress, continuing); evidence is `MR <repo>!<iid>  [↗][<repo>!<iid>]` when `mr` is set, else `note: <summary clip>`. No run-state line. If the same key already has an Unplanned line, update that line instead of adding another. An `offplan` message whose key is on the plan means the plan changed after it was written: treat it as `progress`.
   - A second message for the same key is handled in file order, each in full: the later marker and evidence win, except that you never downgrade `[X]`, and both `memory:` blocks are applied (two log entries).
4. **Memory.** For every kind but `service`, `decision` and `clarify`, apply the `memory:` block (section 4) with the `project` it names.
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

When no item is `[ ]` or `[/]` any more, or every open item is the user's (`me`, `wait`, a `[/] · with you: <KEY>` line) and Keep busy (section 11) found nothing, or the user says so: process the inbox once more, then print a summary: done, blocked, deferred, what needs the user. Suggest `/end-day`. The same session runs `/end-day`; do not delete the run-state file, `/end-day` does.

## 9. Decisions (questions for the user)

When an item needs the user's call — fix a review nit or merge, defer, pick between product options, anything an agent reports with `needs_you` — file it and go on:

```bash
decide add --key <KEY, or '' for off-plan> --mr <MR url, optional> --blocks "<what waits: merge, dispatch, reply>" \
  --question "<one line>" --option "<first>" --option "<second>" [--recommend <n>] <<'EOF'
<what the user needs to decide without opening anything: the reviewer's words, what each option costs, links>
EOF
```

- Set the item's `needs_you=yes`, and write one line in the thread: `decision D-<n> queued: <question>`. Never ask the question in the thread and never wait: continue with other items.
- Recommend when one option is clearly better, and say why in the context.
- A decision that stops mattering (the reviewer resolved it, the MR merged, the item went another way): `decide withdraw <id> "<reason>"` and `decide close <id>`; clear `needs_you` when nothing else is open for the item.
- The user answers in the popup (tmux prefix `y`). The answer arrives as an inbox message of kind `decision` or `clarify` (section 7).
- On a resume (section 0), `decide list` shows what is still waiting: leave it; answers arrive through the inbox.

## 10. Wake check

Run it on a `[daily-wake] woke after …` prompt (the mod sends one when the Mac wakes with agents outstanding), on a `[daily-wake] stuck: …` prompt, and on a resume (section 0). Never file a decision from this section and never ask: act, then say what you did. Items whose run-state line says `owner=external:<KEY>` are never touched here.

1. Read the agents file. The mod rewrites it every 30 s while an `owner=main` item has `agent=` or `round=` set:

```bash
date -u +%FT%TZ
cat ~/.local/state/run-day/$(date +%F).agents 2>/dev/null || echo 'no agents file'
```

   Header `# agents <ISO time>`, then one row per agent: `<key> | ticket|round | <id> | <status> | quiet=<minutes|-> | <transcript|->`. The file is stale when it is missing or its header is more than 2 minutes older than the time printed first: then every id in an `agent=` or `round=` field of an `owner=main` run-state line counts as one row with status `unknown` (transcript `-`).
2. Per row:
   - `running`, `pending` or `waiting`: leave it. Never dispatch a second agent for that item.
   - `completed` or `idle`, and the id is still the item's `agent=` or `round=` (otherwise it was processed already: skip it): `agent-report <transcript>` prints its report. Process it exactly as section 3 ("When a ticket agent reports") for a `ticket` row (a `class=review` item: section 2 step 4, "When a review agent reports"), or section 5 step 3 for a `round` row; that sets `agent=-` or `round=-`, so its late completion notification is ignored. No reply (exit 1 or 2, or transcript `-`): treat the row as `failed`.
   - `failed`, `killed` or `unknown`: first `agent-report <transcript>`. A complete final report (it failed, or names what blocks it) is a real failure: process it as section 3 or section 5 step 3, so a failed check takes the normal retry. No reply, or a reply cut off mid-work, means it was interrupted: `SendMessage` to the id: it was interrupted by sleep or a restart; check `git -C <worktree> status` and its last step, then carry on and report as its brief says. If `SendMessage` errors, dispatch a fresh agent into the same worktree (section 2.2 without `wt add`; a `round` row gets the review-round brief, section 5 step 2) with its last reply (`agent-report <transcript>`, or `none`) and `git -C <worktree> log --oneline -5` appended to the brief under `## Resume note`, and record the new id in `agent=` or `round=`. It counts as the same attempt, not a retry: `retries` stays. A worktree that is gone is recreated as for a `handback` (section 7); worktree and branch both gone is the blocker there (`[!]`, `needs_you=yes`).
3. On a `[daily-wake] stuck: <KEY> <id>, …` prompt the named agents are `running` but silent for 15 minutes or more: `SendMessage` each once: the machine slept; check its background commands and carry on, or report what blocks it. If a later stuck prompt names the same id again, say in your reply that it is stuck: no decision, no kill, no second agent.
4. Then process the inbox (section 7) and any `[daily-event]` prompts still unanswered, and redo the event you were handling if your last reply was cut off.
5. End with one line per row: `<KEY>: left running | report processed | continued | re-dispatched` (a stuck agent: `messaged` the first time, `stuck` after).

## 11. Keep busy

Run this after every processed agent report, finished or blocked item and answered decision, at the end of the dispatch in section 2, and on a `[daily-idle] no agent running: …` prompt. While fewer than **3** agents run (ticket, review and round agents all count), fill the free slots in this order:

1. Queued `auto` and `review` items, in plan order (section 2).
2. Open `wait` and `me` items whose state moved: a `wait` item whose blocker cleared (the pipeline, the other person's push or reply) is dispatched; for a merge item with a green pipeline and approvals and no decision open, file the merge decision with the MR link.
3. The sprint: the user's tickets first, then the team's unassigned To-Do tickets, highest rank first. Each line is `KEY<TAB>status<TAB>summary`:

```bash
jt --list -m
jt --list -u
```

   Skip keys already on the plan or in the run state, the user's tickets whose status is not `To-Do` or `In Progress` (in review, QA or done), epics, and tickets an agent cannot finish alone: read each candidate with `jira-issue <KEY>`; it needs a description that says what done looks like, and one repo you can name. Take as many as there are free slots. For each: add `- [ ] <key> <summary> (sprint: yours|unassigned)` under a `**From the sprint**` group (create it after the last group, above the link definitions), track it `class=auto`, and dispatch it as section 2 step 2.
   - An unassigned ticket is not the user's yet: add `## Not yours yet` to its brief with `Commit locally; do not push and do not open an MR.`, and file a decision (section 9): `Take <KEY> from the sprint?`, context its summary, its rank and what the agent is doing; options `Take it` (assigns it to you in Jira; the agent pushes and opens the Draft MR) and `Leave it`. On `Take it`: `jira-api GET myself | jq -r .accountId`, then `jira-api PUT "issue/<KEY>/assignee" '{"accountId":"<id>"}'`, and tell the agent with `SendMessage` (if it already reported, a fresh agent in its worktree) to push and open the Draft MR. On `Leave it`: stop the agent and mark the line `[>] · note: left in the sprint`.
     Its report before `Take it` (also when the Wake check processes it): run section 3 steps 1-2 without the MR and pipeline parts, since there is none yet. Passing: set `agent=-` and mark the line `[/] · ready locally, waiting on Take it` (no tick, no retry); `Take it` then sends a fresh agent into the worktree to push and open the Draft MR, and that report gets the full section 3. A failing check takes the normal retry.
   - `jt` fails (Jira down, a missing secret): say so in one line and try again at the next Keep busy.
4. Nothing in steps 1-3: Finish (section 8), naming what each step found empty.

Never end a turn saying the rest is the user's while a slot is free and one of steps 1-3 has something. A review, a merge check or a sprint ticket is not the user's work because what comes out of it is posted under their name: an agent drafts it, and a decision asks before anything is posted.
