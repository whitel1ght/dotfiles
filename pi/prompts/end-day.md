---
description: Standup report of the day's work across commits, MRs, Jira and pi sessions, filed in the diary, then folded into the project memory in ~/wiki
argument-hint: "[yesterday | YYYY-MM-DD]"
---

Sync Jira to the MRs first, so the digest's Jira section is already true:

```bash
~/.local/bin/sync-tickets
```

Report what it did in one line (its last line is the summary).

Collect the day's work:

```bash
SESSIONS=pi ~/.local/bin/end-day collect $ARGUMENTS
```

The digest has four sections: commits, GitLab activity (each MR marked as mine or a
review for someone else), Jira status changes, and pi sessions (my prompts and each
session's last replies). A line in brackets means that source was unavailable; mention it
in one line at the end of the report rather than guessing its contents.

## Process the inbox first

Define the day first:

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
fd -d 1 -e md . ~/.local/state/run-day/inbox 2>/dev/null | sort
```

Then process any messages waiting in `~/.local/state/run-day/inbox/*.md` the way section 7
(Inbox) of `~/.pi/agent/prompts/run-day.md` says — read that file first; when the link is
missing, read `~/projects/dotfiles/pi/prompts/run-day.md` in the main checkout — before the
report is written, so that what was reported counts as reported. This happens whether or not
the day has a plan: a missing `<!-- start-day:start -->` block only skips the comparison under
"Unreported activity", never this step.

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

**Waiting on you**
- D-7 ECFX-18313 Fix the nit, or merge now?
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
  **Waiting on you** lists the open decisions from `decide list` (id, key, question), one
  line each; leave the group out when there are none. They stay open: the next `/run-day`
  picks them up.
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
than appending. Links in the report may be written inline or as trailing `[↗][label]` refs;
`save` converts them to refs. Note the path it printed, then continue with the next section.

## Unreported activity

The safety net for work nobody wrote into the plan. Skip the comparison, in one line, when
`~/wiki/diary/$DAY.md` has no `<!-- start-day:start -->` block (nothing to compare with). The inbox
was already processed above. Otherwise take the ticket keys and MR numbers the plan already
mentions, the plan being the start-day block only (its `**Unplanned**` group included):

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
PLAN="$(awk '/<!-- start-day:start -->/{f=1;next} /<!-- start-day:end -->/{f=0} f' ~/wiki/diary/$DAY.md)"
printf '%s\n' "$PLAN" | rg -oi '\b[a-z]{2,10}-[0-9]{2,6}\b' | tr 'A-Z' 'a-z' | sort -u
printf '%s\n' "$PLAN" | rg -o 'merge_requests/[0-9]+' | sort -u
```

Compare the digest's four sections with those two lists. A digest item is **unreported** when its
ticket key is not among the plan's keys and, for an MR, its `merge_requests/<n>` is not among the
plan's MR numbers. Items with neither a key nor an MR (a commit or a session without a ticket) are
grouped per repo or session topic and shown for me to judge; drop obvious noise (merge commits,
the edits made by this very report). Only the plan block counts, never the diary's report block.

If nothing is unreported, say so in one line. Otherwise show a short list, one line each:
`<key or topic> - <one-line summary> - <evidence: MR link or commit>`. Ask which to add, then stop
and wait for my answer (yes or no per item), and do not continue until answered. Do not go on to
"Consolidate memory", and do not add anything, before the answer arrives. For each yes, add one
line under the plan block's `**Unplanned**` group (create the group as the last group, just
above `<!-- start-day:end -->`, when it is missing):
`- [X] <key> <summary> · MR <repo>!<iid>  [↗][<repo>!<iid>]` (the URL goes in a
`[<repo>!<iid>]: <url>` line above the end marker; an inline `[<repo>!<iid>](<url>)` is fine too),
or `· note: <summary>` when there is no MR, because the diary's tick guard refuses an `[X]` without
an MR link, `merged` or `· note:`. Use `[/]` for work that is clearly unfinished. After the edits
run `~/.local/bin/diary-links ~/wiki/diary/$DAY.md`. Never add a line I did not approve and never
edit a line outside the block.

## Consolidate memory

Skip this step, and say so in one line, when `~/wiki/work/projects` does not exist or the day has
no log entries below (the commit and the end of the run below still happen). It is the only place
project `state.md` files change; during the day `/run-day` only appends logs and decisions.

`$DAY` was defined above (set it again in each command, since shell state may not carry over).
Find which projects were touched — `end-day touched` prints one project name per line, the
projects with a `## <day> <title>` log entry or a decision dated `<day>`; empty output means
none:

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
~/.local/bin/end-day touched "$DAY"
```

For each project `<p>` it prints:

1. Read `~/wiki/work/projects/<p>/state.md`, the day's log entries
   (`~/.local/bin/end-day entries "$DAY" <p>`), the decisions dated that day
   (`rg -l "^date: $DAY" ~/wiki/work/projects/<p>/decisions`), and the `<p>:` lines under `notes:` in
   `~/.local/state/run-day/$DAY.md` if it exists (the `state_change` lines `/run-day` collected).
2. Rewrite `state.md` in full from the old state plus those: current focus, open threads (drop
   what finished, add what started), links to existing notes. Keep the file's frontmatter and
   headings, set its `date` to `$DAY`, and keep it at **60 lines or fewer** (`wc -l` it). It is a
   snapshot, not a history: history lives in the log.
3. If the project's one-line focus changed, update its line in the `## Long-term memory (projects)`
   section of `~/wiki/index.md` (the existing vault index; edit only that section).

## Reflect on friction

Scripts do the bookkeeping and the model only judges new friction. Mine the day and fold it into the ledger (`M` is the miner output, kept for the diary step; the `apply` result goes to `A`, which the subagent reads, so it is never retyped):

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
M="${TMPDIR:-/tmp}/friction-$DAY.json"; A="${M%.json}.apply.json"; R="${M%.json}.reply.json"; K="${M%.json}.concepts.json"
~/.local/bin/friction-mine --date "$DAY" >"$M" && ~/.local/bin/friction-ledger apply --date "$DAY" --mine-json "$M" >"$A" &&
  jq -c '[(.concepts // [])[:15][] | .question |= .[:300] | .answer |= .[:1500]]' "$M" >"$K" &&
  jq -c --slurpfile k "$K" '{new: (.new | length), needs_proposal: (.needs_proposal | length), regressed: (.regressed | length), user_signals: (.user_signals | length), concepts: ($k[0] | length)}' "$A"
```

It writes `{new, needs_proposal, regressed, corrections, user_signals}` to `$A` and the day's concept candidates to `$K` (at most 15 concepts, each question cut to 300 chars and answer to 1500, so the cheap model's input stays small), and prints the counts: `user_signals` are my prompts that may hold a standing direction or a frustration (none once the day was already ingested, so a re-run adds nothing). If either command is missing or fails, say so in one line and go on to the commit: friction never blocks the report. If `new`, `needs_proposal`, `user_signals` and `concepts` are all 0, say so in one line and skip to the diary step: no subagent for nothing. Otherwise launch one subagent, the cheapest suitable model in the live `<subagent_models>` list (per `~/projects/dotfiles/pi/model-selection.md`: bounded reading and classification): `subagent({ role: "researcher", model: <that model>, cwd: "~/projects/dotfiles", label: "friction", task: <the brief below, with the real paths of $A, $K and $R (print them with `echo "$A" "$K" "$R"`) in place of <A>, <K> and <R>> })`. Then end the turn. On the `[pi-sub]` wake-up check that the reply file exists and continue from the next paragraph.

> Classify friction from my daily workflow and propose fixes. Read `<A>` (JSON: `new` items first seen today, `needs_proposal` items that qualify for a fix, `user_signals` my own prompts of the day with their `harness`; items have an id, signature, samples and evidence `path:line`, readable, only when a sample is not enough) and `<K>` (JSON array of `concepts`: explanations I asked for, each with `harness`, `session`, `at`, `question`, `answer`) and run `~/.local/bin/friction-ledger directions render` for the active directions. Write your reply to `<R>` as ONE JSON object and nothing else; write no other file.
> `items` is keyed by F id. For every item in `new`: `class` is `env` (auth, MCP, network, service down), `instruction` (a prompt or skill is wrong), `script` (a bug in our code), `model` (model behaviour) or `external` (a blocker outside us: another ticket, an approval); `diagnosis` is one line of at most 20 words. For every item in `needs_proposal` and not `external`: `rung` and `proposal`. Pick the cheapest rung that works: `script` (retry/backoff, health gate, preflight check, cache, fallback source, background waiter), then `config` (re-auth, env var, settings, dropping a dead step), then `prompt` (prompt/skill/command text, only when the problem is the model's judgement). `proposal` is markdown: the rung, why each lower rung does not fit, the target files in `~/projects/dotfiles` (`bin/`, `claude/`, `pi/`), and a test that proves it (a `bin/<x>.test.sh` case or similar).
> For each `user_signals` item (`text` is what I typed, `prev_assistant` what the model had just said): a standing rule I want kept from now on goes in `directions` (`rule` an imperative one-liner, `scope` one of global, run-day, reviews, a repo, or a skill/command name, `quote` at most 100 chars, `harness` copied from the signal; add `same_as: "D-NNN"` when it restates an active direction). Where I was annoyed at what the system did, add to `frustrations` (`what_went_wrong`, `class` as above, `sig_hint` a short stable phrase naming the failure, so the same failure on another day gets the same hint) and ALWAYS give it `rung` and `proposal` as above. Anything else (a one-off instruction for that task, a question, a plain correction) appears nowhere. Be strict: when in doubt, leave it out.
> Items of kind `repeat` (the same request asked again and again), `restated` (a direction I keep restating) and `secret` (a secret found in a file (location only)) are in `new`/`needs_proposal` like the rest. `repeat`: the proposal names the skill or command to create (rung `prompt` or `script`). `restated`: the proposal says which of two fixes it is: keep it as a standing direction, with a line `Direction: <the rule as an imperative one-liner>` and a line `Scope: <global, run-day, reviews, a repo, or a skill/command name>`; or enforce it in a script, with no `Direction:` line. `secret`: the proposal is user steps (rotate the key, remove the line, use `$(secret NAME)`), never an automatic fix; the model never sees or asks for the value. Any proposal that touches a guard, a permission or allow/deny rule, a hook, auto mode or a settings file must contain the exact change, one line each: `Change: <file or key>: <before> → <after>`.
> For each `<K>` concept that is a real explanation of how something works (not a task request, a status question or debugging of one specific failure), add to `cards` one `{front, back, tags, source}`: `front` a question I could answer from memory, `back` distilled from the answer in at most 4 lines, `tags` from ecfx, tech, setup, `source` the concept's session file plus its date (from `session` and `at`). Be strict: when in doubt, leave it out.
> Reply shape: `{"items":{"F-001":{"class":"env","diagnosis":"...","rung":"config","proposal":"..."}},"directions":[{"rule":"...","scope":"global","quote":"...","harness":"claude"}],"frustrations":[{"what_went_wrong":"...","class":"env","sig_hint":"...","rung":"script","proposal":"..."}],"cards":[{"front":"...","back":"...","tags":["tech"],"source":"<session> 2026-01-01"}]}`; `rung` and `proposal` go together and are omitted for an item without a proposal; empty parts may be left out.

Then apply the whole reply with one command; the script validates it and applies nothing when anything is invalid:

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
~/.local/bin/friction-ledger ingest "${TMPDIR:-/tmp}/friction-$DAY.reply.json" --date "$DAY"
```

It sets class, diagnosis and proposals (`proposed` for an item with one, `wontfix` for `external`), adds directions (active from the next session with no confirmation; the diary lists them so I can retire them) and records frustrations (the script sets `proposed` from their second day), and adds the `cards` to the quiz deck with `cards add` (once per date; an invalid card rejects the whole reply). A `secret` item always gets `safety: true`, and /start-day shows it as the user's own steps, never as a job. Nothing from cards or coach items goes into the diary report. On an error, relaunch the subagent once with the error text appended; a second failure is left for tomorrow. Never retype or edit its data by hand.

Then file the section in the diary and let the commit below pick up `work/friction/`:

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
M="${TMPDIR:-/tmp}/friction-$DAY.json"
S="$(~/.local/bin/friction-ledger diary-section --date "$DAY" --mine-json "$M")"
[ -z "$S" ] || printf '%s\n' "$S" | ~/.local/bin/end-day friction "$DAY"
```

`end-day friction` puts it between its own markers at the end of the diary, so a re-run replaces it and the report is never touched. Mention the counts in one line.

## Words

File the day's word progress in its own diary block, skipped silently when `words` is not installed or there are no word cards yet:

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
command -v ~/.local/bin/words >/dev/null && L="$(~/.local/bin/words stats --date "$DAY" --line)" && [ -n "$L" ] && printf '%s\n' "$L" | ~/.local/bin/end-day words "$DAY"
```

The line reads `Words: R reviewed, N new, K known of T · streak S days`; `end-day words` keeps it between its own markers at the end of the diary, outside the report block. Never tick or write a habit line for words in the diary.

## Check the system

Run `~/.local/bin/system-check --record`; it prints JSON with the findings that are new since its last recorded run, and records them as seen (without `--record` it only looks, so a run by hand leaves them for this step). For each `new` item, fix the page it names (`~/wiki/work/system/` or `~/wiki/tools/`), or ask me before moving a stray script into dotfiles or before adding a line to `known.txt`. An id containing `:failed` means a check itself is broken: report it as "check broken: <detail>" and do not edit a page for it. An `install` finding has no page to fix: list it under the **System** line and ask once, for all of them together, whether to add each to the Brewfile (or `pi/settings.json`, or `install.sh` for a Claude plugin or marketplace), uninstall it, or acknowledge it with an `install <glob>` line in `known.txt` (with a `# reason`); then do what I answer. Commit page fixes with `~/.local/bin/wiki-commit --by pi -m "<msg>" -- <paths>`; if it exits 2 only because there is no wiki, carry on. List what changed under a **System** line in the closing message to me, never in the diary report.

## Index, commit and end the run

This always runs, even when the memory step was skipped: the report and the diary edits still get
committed. Set `DAY` again here (new shell):

```bash
DAY="$(case "$ARGUMENTS" in (yesterday) date -v-1d +%F ;; (20??-??-??) echo "$ARGUMENTS" ;; (*) date +%F ;; esac)"
qmd update && qmd embed
git -C ~/wiki add -A -- diary work index.md tools
git -C ~/wiki diff --cached --quiet || git -C ~/wiki commit -m "wiki: $DAY day"
~/.local/bin/wiki-sync
```

If `qmd` fails, say so in one line and still commit. `wiki-sync` pushes the day (and anything
else changed) to the VPS; if it fails, show its one-line error and point at `wiki-sync status`.
Never touch `*.pdf` or `*.kdbx`.

Finally end the run: move `~/.local/state/run-day/$DAY.md` into `~/.local/state/run-day/done/`
(create the directory). That switches off the run-state injection and the event watcher. Skip it
when there is no such file.

## Land the coach's fixes

The last step that changes anything, after the report is saved and the day committed. It lands the
fixes the coach built in the background today (each one the user said yes to in /start-day).
Landing can re-run a fix's test suites for minutes, so it runs detached and this call returns at
once:

```bash
~/.local/bin/coach-fix land --detach
```

It prints one line: "landing in the background; log: <path>", "a land is already running", or "a
day session is running; landing waits" (leave it: never add `--force-check` here). Put that line
under a **Coach** line in the closing message to me, never in the diary report.
Do not wait for the land or read its log: it writes each result to the ledger, `wiki-sync`'s next
run commits it, and tomorrow's /start-day reports what landed or why it failed.

## Offer reviews

Do not run these; ask whether to:

```bash
d=$(date +%-d); w=$(date +%u)
[ "$w" = 5 ] && echo "offer: /review week"
if { [ "$d" -eq 1 ] && [ "$w" -le 5 ]; } || { [ "$w" -eq 1 ] && [ "$d" -le 3 ]; }; then echo "offer: /review month"; fi
```

Friday offers `/review week`; the first workday of a month offers `/review month`. Print nothing
if neither line appears. End with the diary path, the projects consolidated, and the commit, then print the Standup
paragraph once more (the `**Standup**` line and the paragraph, nothing else) as the very last
thing, so I can copy it.
