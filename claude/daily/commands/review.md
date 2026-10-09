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

A review is built from the level below it: week from diary files, log entries and decisions; month from its weeks; quarter from its months; year from its quarters. Make a list of the periods to generate, children first: for the period and then recursively for each child, include it when `~/wiki/<file>` does not exist (always include the requested period, replacing an existing file only after the user says so). If the list has more than 4 periods, show it and ask before going on.

## 3. Generate each period, in list order

For one period with `from`, `to`, `id`, `level`:

1. Numbers (the `daily-stats` CLI; output is one JSON object, see the spec for its fields):

```bash
STATS="$(daily-stats <from> <to>)"
printf '%s' "$STATS" | jq -r '"## Numbers\n\n\(.from) to \(.to): \(.days) planned day(s).\n\n- Planned: \(.items.planned)\n- Done: \(.items.done)\n- Blocked: \(.items.blocked)\n- Deferred: \(.items.deferred)\n- Still open: \(.items.open)\n- MRs merged: \(.merged_mrs | length)"' > <scratchpad>/numbers-<id>.md
```

   If `daily-stats` fails, stop and show its error: never estimate numbers.
2. Inputs, as a list of paths (the subagent reads them itself):
   - week: diary files in range (`ls ~/wiki/diary/20??-??-??.md | awk -F/ -v from=<from> -v to=<to> '{n=$NF; sub(/\.md$/,"",n); if (n>=from && n<=to) print}'`)
   - month, quarter, year: the child review files, in full.
   - every level: log entries dated in range, and decisions dated in range:

```bash
awk -v from="<from>" -v to="<to>" '/^## 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { d = substr($2,1,10); on = (d >= from && d <= to); if (on) print "--- " FILENAME } on' ~/wiki/projects/*/log/*.md
for f in ~/wiki/projects/*/decisions/*.md; do d="$(sed -n 's/^date: *//p' "$f" | head -1)"; if [[ "$d" > "<from>" || "$d" == "<from>" ]] && [[ "$d" < "<to>" || "$d" == "<to>" ]]; then echo "$f"; fi; done
```

3. Spawn a `sonnet` subagent (foreground) with this brief, filled in:

> Write the `<level>` review `<id>` (<from> to <to>) for the user's own retrospective. Read `~/wiki/AGENTS.md` and `~/wiki/_templates/review-<level>.md` first and follow the template's section headings and order. Do not write frontmatter, a title or a Numbers section: this session adds them. Read these inputs: <paths>. The numbers are already written in `<scratchpad>/numbers-<id>.md`: do not state any count that is not in that file or in the inputs you can count directly. Output only these sections, with these exact `## ` headings, in this order: **Shipped** (merged and draft MRs as markdown links, `[repo!iid](url)`), **Per project** (one short paragraph each for ecfx, epicmax, personal where there is anything), **Decisions** (links to the decision files, one line each), **Carry-over & time sinks** (items deferred two or more times, and where time went, from the stats below), **Brag bullets** (3 to 7, impact-phrased: what changed for whom). Plain, specific, no filler; every claim traceable to an input. Write the result to `<scratchpad>/review-<id>.md` and reply with only that path. Repeat-deferred items and MR links from `daily-stats`: <the `repeat_deferred` and `done_mr_links` fields of STATS>.

4. Assemble and check. The review's shape is fixed by `~/wiki/_templates/review-<level>.md` (plan-wiki Task 3): frontmatter, then `# {{period}} review`, then `## Numbers`, then the five sections. This session fills the template's tokens and builds the file; the subagent contributes only the sections after Numbers:

```bash
TPL=~/wiki/_templates/review-<level>.md
OUT=<scratchpad>/review-<id>.full.md
awk 'NR==1 && $0=="---"{f=1} f{print} f && NR>1 && $0=="---"{exit}' "$TPL" | sed "s/{{date}}/<to>/; s/{{period}}/<id>/" > "$OUT"
printf '\n# <id> review\n\n' >> "$OUT"
cat <scratchpad>/numbers-<id>.md >> "$OUT"
printf '\n' >> "$OUT"
cat <scratchpad>/review-<id>.md >> "$OUT"
```

   `{{date}}` is the period's end date (`to`), `{{period}}` its id; any extra frontmatter keys the template carries (a `qmd.metadata` block) are kept. Verify each of these and fix or re-brief if one fails: the frontmatter has `type: review`, `date` and `period`, and no `{{` remains in the file; the `## Numbers` heading appears once and its figures equal `jq '.items'` of STATS; every `[...](https://...)` link in Shipped appears in `done_mr_links` or `merged_mrs`; no section is empty (write `Nothing this period.` instead). Copy `$OUT` to `~/wiki/<file>` (`mkdir -p ~/wiki/reviews` first).

## 4. Index and commit

```bash
qmd update && qmd embed
git -C ~/wiki add reviews
git -C ~/wiki commit -m "wiki: review <id>[, <id>...]"
```

If `qmd` fails, say so in one line and still commit. Print the path of the requested review and its Brag bullets.
