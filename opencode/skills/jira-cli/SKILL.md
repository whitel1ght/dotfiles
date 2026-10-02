---
name: jira-cli
description: >-
  Interact with Jira through the `jira` command-line tool — list, view, create, edit, comment on, transition, link, assign, clone, delete and log work on issues, and inspect sprints, epics, boards, projects and releases. Use whenever the user asks anything about Jira tickets or issues (e.g. ECFX-NNNN), their tickets or backlog, a sprint or board, an epic, JQL, or wants to find, open, file, update, comment on, move, or report on a Jira issue. Prefer this CLI for any interactive Jira request.
---

# Jira CLI

Drive Jira from the shell with the `jira` CLI (`ankitpokhrel/jira-cli`). It is
already authenticated and pointed at the team instance, so there is nothing to
configure per call. This is the default way to read and change Jira in a
session.

Use it for anything Jira: finding and viewing tickets (`ECFX-NNNN`), "my
tickets", JQL search, sprints, boards and epics, comments, transitions,
assignment, worklogs, and creating or editing issues.

For the specific analytics reports and the EML-driven ticket workflow, defer to
the dedicated skills instead — see **Interop** below.

## Environment

- **Binary**: `jira` (Homebrew). This reference was written against **v1.7.0** —
  check with `jira version` and flag major drift to the user before trusting the
  flags here.
- **Config**: `~/.config/.jira/.config.yml` — server
  `https://ecfxdev.atlassian.net`, default project `ECFX`, basic auth, login
  `dmitry.mamyrev@epicmax.co`. Override the file with `-c/--config` or
  `JIRA_CONFIG_FILE`; override the project with `-p/--project`.
- **Credentials**: the API token comes from `JIRA_API_TOKEN` (with
  `JIRA_EMAIL`), exported from `~/.config/mrglass/secrets.env`. **Never print or
  echo the token.**
- **Projects on this instance** include `ECFX` (default), `CSR`, `ER`, `INFRA`.

## Preflight (once per session)

Run `jira me` on the first Jira-touching call. It prints the login email.

- If it fails with an authentication error, tell the user that `JIRA_EMAIL` /
  `JIRA_API_TOKEN` are not set in the shell and **stop** — do not retry in a
  loop.
- `$(jira me)` is also the value for "me" as an assignee or reporter. Cache the
  result for the rest of the session.

## Output modes — read this before any list command

The CLI's default view for `list` commands is an **interactive TUI**. There is
no TTY in this environment, so always ask for a non-interactive format:

- **`--plain`** — table output. Add `--no-headers` and either `--no-truncate`
  (all columns) or `--columns KEY,SUMMARY,STATUS,...` to narrow. Default column
  delimiter is a tab; change it with `--delimiter '|'`.
- **`--csv`** — CSV (sprint/epic lists).
- **`--raw`** — raw JSON (issue view/create; sprint/epic lists).
- **`--paginate 0:100`** — page large result sets.

```sh
jira issue list -a"$(jira me)" --plain --no-truncate
```

## Read commands

```sh
jira me                                                               # login email
jira issue list -a"$(jira me)" --plain --no-truncate                  # my issues
jira issue list -s"In Progress" -yHigh --plain                        # by status/priority
jira issue list -q"project = ECFX AND status = 'In QA' ORDER BY updated DESC" --plain
jira issue list --created -7d --plain                                 # recent window
jira issue view ECFX-1114 --comments 10                               # with comments
jira issue view ECFX-1114 --raw                                       # raw JSON
jira sprint list --table --plain                                      # sprints on the board
jira sprint list --current --plain                                    # issues in the active sprint
jira epic list --table --plain                                        # epics
jira epic list ECFX-100 --plain                                       # issues in an epic
jira board list                                                       # boards in the project
jira project list                                                     # projects I can see
jira release list                                                     # versions
jira open ECFX-1114                                                   # open in browser
```

Issue-list filters (combine freely): `-t/--type`, `-s/--status` (repeatable),
`-y/--priority`, `-r/--reporter`, `-a/--assignee`, `-C/--component`,
`-l/--label` (repeatable), `-P/--parent`, `--history`, `-w/--watching`,
`--created`, `--updated`, `--created-after/-before`, `--updated-after/-before`,
`-q/--jql`, `--order-by`, `--reverse`.

## Write commands (require the confirmation gate)

```sh
jira issue create -tBug -s"Summary" -b"Description" -yHigh -lbug -a"$(jira me)"
jira issue create -tTask -s"Summary" -b"Body" --template /path/to/body.tmpl
jira issue edit ECFX-1114 -s"New summary" -yHigh --no-input
jira issue edit ECFX-1114 --label -stale                              # remove a label
jira issue comment add ECFX-1114 "Comment body"
jira issue move ECFX-1114 "In QA" --comment "Ready for QA"
jira issue assign ECFX-1114 "$(jira me)"                              # or: default | x (unassign)
jira issue link ECFX-1114 ECFX-1200 Blocks
jira issue worklog add ECFX-1114 "2h 30m" --comment "Fix + tests" --no-input
jira issue clone ECFX-1114 -s"Copy of ..." -H"old:new"
jira issue delete ECFX-1114                                           # --cascade to include subtasks
jira sprint add 123 ECFX-1114 ECFX-1115                               # add issues to a sprint
jira sprint close 123
```

Notes:

- `create` needs at least `-t` and `-s`; pass `--no-input` to suppress prompts
  for everything else. `--raw` returns JSON; `--web` opens the new issue.
- `edit`: `-l/--label` **appends**, `-C/--component` **replaces**; prefix a value
  with `-` to remove it (`--label -stale`, `--component -Backend`).
- `move` takes the **exact state name** (`"In Progress"`, `"In MR"`, `"In QA"`,
  `Done`), not a transition id.
- Assignee must be an exact email or display name; `default` and `x`
  (unassign) are special.
- Comment bodies and issue descriptions accept `-T -` or a pipe to read stdin;
  a positional argument wins over `--template`.
- `--internal` on `comment add` marks the comment internal (Service Desk).

## Destructive-action gate

Restate the target and the action and get **explicit user confirmation** before
running any of:

- `issue delete` (especially `--cascade`)
- `issue move` (transition), `issue edit`, `issue assign`, `issue clone`
- `issue comment add` and `issue worklog add`
- `issue link` / `issue unlink`, `sprint add` / `sprint close`,
  `epic add` / `epic remove`

The read commands in the previous section are safe to run anytime.

## Interop with the metrics skills

These keep their own Python scripts (REST + `jira_metrics.py`) and are the right
tool for their narrow job — do not reimplement them with the CLI:

- `jira-linked-bugs`, `jira-bug-cycle-time`, `jira-sprint-cycle-time` — the
  bug/sprint metrics reports and CSVs.
- `research-jira-bug`, `fix-jira-bug` — the EML-driven ticket investigation and
  fix workflow.
- `verify-release` — post-release verification against production logs.

For everything interactive — looking up, filing, updating, commenting on,
moving, or reporting on an issue — use this CLI.

## Gotchas

- **Always `--plain` / `--raw` / `--csv`** for list commands; the default is an
  interactive TUI that will not render here.
- `issue view` shows only **1 comment** by default — add `--comments N` or use
  `--raw` for the full thread.
- `issue list` scopes to the default project (`ECFX`). Pass `-p CSR` (etc.) or a
  `-q` JQL with an explicit `project = ...` to look elsewhere.
- Sprint commands need a board mapped to the project. This config has **no
  default board** (`board: ""`), so `jira sprint list` returns "No result
  found". `jira board list` shows the boards; setting `board:` in
  `~/.config/.jira/.config.yml` (or `jira init`) to a scrum board enables the
  sprint commands.
- `-q/--jql` still applies the project context — include `project = ...` in the
  JQL when you want to cross projects.
- **Never print `JIRA_API_TOKEN`** or paste it into output, tickets, or files.

## Quality checklist

- [ ] Preflight done (`jira me`) and cached for the session
- [ ] Non-interactive output requested (`--plain` / `--raw` / `--csv`)
- [ ] The right project selected (`ECFX` default, or `-p` / JQL `project =`)
- [ ] Destructive action restated and explicitly confirmed
- [ ] Token never echoed
- [ ] Output presented to the user, not just consumed silently

## Supporting files

- **`reference.md`** — full per-command flag catalog, grouped by command.
- **`examples.md`** — end-to-end recipes (my board, view a ticket, comment and
  transition, file a bug, JQL search, sprint overview).
