# Jira CLI — examples

End-to-end recipes. Read-only commands run freely; anything that writes goes
through the confirmation gate in `SKILL.md` first.

## 1. What am I working on?

```sh
jira me
jira issue list -a"$(jira me)" -s"In Progress" -s"In MR" -s"In QA" --plain --no-truncate
```

Narrow it: `--updated -7d`, `-yHigh`, `-tBug`, `--order-by updated --reverse`.
The default project is `ECFX`; use `-p CSR` for another.

## 2. Read a ticket and its discussion

```sh
jira issue view ECFX-1114 --comments 20
```

The default shows only one comment. For structured use, `--raw` returns the full
Jira JSON (fields, comments, changelog), which is easier to parse than the
table.

## 3. Comment on a ticket

Restate the ticket and the exact text, get confirmation, then:

```sh
jira issue comment add ECFX-1114 "Fixed in !5348 — moving to QA."
```

For a long or templated body, write it to a file and pass `-T file`
(or `-T -` and pipe stdin). `--internal` marks it internal (Service Desk).

## 4. Move a ticket between states

The state is the exact status name; confirm before transitioning:

```sh
jira issue move ECFX-1114 "In QA"
jira issue move ECFX-1114 Done --comment "Merged"
jira issue move ECFX-1114 "In Progress" -a"$(jira me)"
```

## 5. File a bug

Confirm type, summary, project and description, then:

```sh
jira issue create \
  -t Bug -s "Login 500 for roles with a granular inbox permission block" \
  -b "Steps to reproduce...\n\nExpected: ...\nActual: ..." \
  -y High -a"$(jira me)" -l backend
```

`--raw` prints the created issue as JSON (grab the key from it); `--web` opens
it. Use `-P EPIC-KEY` to attach to an epic, or `-P PARENT-KEY` for a sub-task.

## 6. Search with JQL

```sh
jira issue list -q "project in (ECFX, CSR) AND status = 'In QA' ORDER BY updated DESC" \
  --plain --no-truncate
```

`-q` still sits inside the project context — put `project = ...` in the JQL to
cross projects.

## 7. Sprint overview

```sh
jira board list
jira sprint list --table --plain --state active
jira sprint list --current --plain --columns KEY,SUMMARY,STATUS,ASSIGNEE
```

**Heads-up:** the sprint commands need a board mapped to the project, and this
config has none (`board: ""`), so `jira sprint list` currently returns "No
result found". Set `board:` in `~/.config/.jira/.config.yml` (or run
`jira init`) to a scrum board from `jira board list` to turn them on. Until
then, find sprint work with JQL instead:

```sh
jira issue list -q "project = ECFX AND sprint in openSprints()" --plain --no-truncate
```

Moving issues into a sprint (confirm first):

```sh
jira sprint add 123 ECFX-1114 ECFX-1115
```

## 8. Log work

Confirm the time and ticket, then:

```sh
jira issue worklog add ECFX-1114 "1h 30m" --comment "Investigated retry path" --no-input
```

Add `--started "2022-01-01 09:30:00" --timezone "America/Los_Angeles"` when the
work was not done now.
