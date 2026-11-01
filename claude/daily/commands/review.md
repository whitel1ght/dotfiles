---
description: Write a weekly, monthly, quarterly or yearly review of past work into ~/wiki/reviews
argument-hint: week|month|quarter|year [period, e.g. 2026-W40, 2026-09, 2026-Q3, 2025]
disable-model-invocation: true
---

# Review

Arguments: $ARGUMENTS

The review is for the user (a retrospective and a brag doc), built from the record in `~/wiki`. Numbers come from `daily-stats` and are copied verbatim by this session; a subagent writes the prose. Subagents never write to the vault: they write to the scratchpad, and this session copies the checked result in.

## 1. Resolve the period

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-period" <level> [period]
```

It prints one JSON object: `level`, `id`, `from`, `to`, `file` (relative to `~/wiki`), `ended`, and `children` (the lower-level periods it is built from, same fields). With no period it is the one that just ended. Exit 2 means the arguments are wrong: show its message and stop. When `ended` is false, say so and ask whether to continue.

## 2. Find what is missing

A review is built from the level below it: week from diary files, log entries and decisions; month from its weeks; quarter from its months; year from its quarters. `review-period` returns one level of `children`: for each child run `review-period <child level> <child id>` to get its own children (quarter to month to week; year to quarter to month to week), and so on down to weeks. Month and quarter children are ISO weeks by their Thursday, so a month's first or last days may fall outside its week children; those days are covered by the period's own `daily-stats` range.

Make a list of the periods to generate, lowest level first: skip children whose file already exists under `~/wiki` (their file is read as an input as it stands); include each child whose file is missing; always include the requested period, replacing its existing file only after the user says so. If the list has more than 4 missing lower-level periods (excluding the requested period itself), show it and ask before going on.

## 3. Generate each period, in list order

For one period with `from`, `to`, `id`, `level`:

1. Numbers (the `daily-stats` CLI; output is one JSON object, see the spec for its fields):

```bash
STATS="$(daily-stats <from> <to>)"
printf '%s' "$STATS" | jq -r '"## Numbers\n\n\(.from) to \(.to): \(.days) planned day(s).\n\n- Planned: \(.items.planned)\n- Done: \(.items.done)\n- Blocked: \(.items.blocked)\n- Deferred: \(.items.deferred)\n- Still open: \(.items.open)\n- MRs merged: \(.merged_mrs | length)"' > <scratchpad>/numbers-<id>.md
```

   If `daily-stats` fails, stop and show its error: never estimate numbers.
2. Inputs, as a list of paths (the subagent reads them itself). Write the extraction output to scratchpad files, not the terminal:

```bash
X="${CLAUDE_PLUGIN_ROOT}/scripts/review-extract"
"$X" logs ~/wiki <from> <to> > <scratchpad>/logs-<id>.txt
"$X" decisions ~/wiki <from> <to> > <scratchpad>/decisions-<id>.txt
"$X" diary ~/wiki <from> <to> > <scratchpad>/diary-<id>.txt
```

   - week: the paths in `diary-<id>.txt`.
   - month, quarter, year: the child review files, in full (existing ones as they stand, the ones just generated included).
   - every level: `logs-<id>.txt` (its first line gives the date range and paths, then each file under a `--- path` line) and the decision files listed in `decisions-<id>.txt`.

3. Spawn a `sonnet` subagent (foreground) with this brief, filled in:

> Write the `<level>` review `<id>` (<from> to <to>) for the user's own retrospective. Read `~/wiki/AGENTS.md` and `~/wiki/_templates/review-<level>.md` first and follow the template's section headings and order. Do not write frontmatter, a title or a Numbers section: this session adds them. Read these inputs: <paths>. The numbers are already written in `<scratchpad>/numbers-<id>.md`: do not state any count that is not in that file or in the inputs you can count directly. Output only these sections, with these exact `## ` headings, in this order: **Shipped** (MRs as markdown links, `[repo!iid](url)`, only those in the `done_mr_links` or `merged_mrs` of the stats below), **Per project** (one short paragraph each for ecfx, epicmax, personal where there is anything), **Decisions** (one line each; every line links its decision file or is omitted), **Carry-over & time sinks** (items deferred two or more times, and where time went, from the stats below), **Brag bullets** (3 to 7, impact-phrased: what changed for whom). Every MR link anywhere in the file must appear in `daily-stats` output below or in a decision or log file you were given: never construct a link. When there are no inputs at all, still write every section, each as `Nothing this period.`; do not ask or stop. Plain, specific, no filler; every claim traceable to an input. Write the result to `<scratchpad>/review-<id>.md` and reply with only that path. Repeat-deferred items and MR links from `daily-stats`: <the `repeat_deferred`, `done_mr_links` and `merged_mrs` fields of STATS>.

4. Assemble and check. The review's shape is fixed by `~/wiki/_templates/review-<level>.md` (plan-wiki Task 3): frontmatter, then `# {{period}} review`, then `## Numbers`, then the five sections. This session fills the template's tokens and builds the file; the subagent contributes only the sections after Numbers:

```bash
TPL=~/wiki/_templates/review-<level>.md
OUT=<scratchpad>/review-<id>.full.md
"${CLAUDE_PLUGIN_ROOT}/scripts/review-extract" frontmatter "$TPL" <to> <id> > "$OUT"
printf '\n# <id> review\n\n' >> "$OUT"
cat <scratchpad>/numbers-<id>.md >> "$OUT"
printf '\n' >> "$OUT"
cat <scratchpad>/review-<id>.md >> "$OUT"
```

   `{{date}}` is the period's end date (`to`), `{{period}}` its id; any extra frontmatter keys the template carries (a `qmd.metadata` block) are kept. Verify each of these and fix or re-brief if one fails: the frontmatter has `type: review`, `date` and `period`, and no `{{` remains in the file; the `## Numbers` heading appears once and its figures equal `jq '.items'` of `daily-stats <from> <to>` (run it again: shell variables do not carry between Bash calls); every `[...](https://...)` link anywhere in the file appears in `done_mr_links` or `merged_mrs` or in a decision or log file given to the subagent; no section is empty (write `Nothing this period.` instead). A period with no inputs is still written, without asking: zeros in Numbers and `Nothing this period.` in every section. Copy `<scratchpad>/review-<id>.full.md` to `~/wiki/<file>` (`mkdir -p ~/wiki/reviews` first).

## 4. Index and commit

```bash
qmd update && qmd embed
git -C ~/wiki add reviews
git -C ~/wiki commit -m "wiki: review <id>[, <id>...]"
```

When a regenerated review is identical to the committed one, nothing to commit is fine: say so and go on.

If `qmd` fails, say so in one line and still commit. Print the path of the requested review and its Brag bullets.
