# Jira CLI — reference

Full per-command flag catalog, captured from `jira <command> --help` on
**v1.7.0**. Run `jira <command> <subcommand> --help` for the live version.

## Global / inherited flags

Every command accepts:

| Flag | Meaning |
| --- | --- |
| `-c, --config string` | Config file (default `~/.config/.jira/.config.yml`; `JIRA_CONFIG_FILE` env overrides) |
| `-p, --project string` | Project to operate on (defaults to the config's `project.key`, `ECFX`) |
| `--debug` | Debug output |
| `-h, --help` | Help |

## Misc

| Command | Purpose |
| --- | --- |
| `jira me` | Print the configured login email |
| `jira serverinfo` (`systeminfo`) | Info about the Jira instance |
| `jira version` | Version info |
| `jira open [ISSUE-KEY]` (`browse`, `navigate`) | Open an issue (or the project) in a browser. `-n/--no-browser` skips opening |
| `jira init` (`initialize`, `configure`, `config`, `setup`) | Interactive config; flags `--installation`, `--server`, `--login`, `--auth-type`, `--project`, `--board`, `--force`, `--insecure` |

## `jira issue`

### `list` (`ls`)

`jira issue list [optional search text] [flags]`

| Flag | Meaning |
| --- | --- |
| `-t, --type string` | Issue type |
| `-R, --resolution string` | Resolution |
| `-s, --status stringArray` | Status (repeatable) |
| `-y, --priority string` | Priority |
| `-r, --reporter string` | Reporter (email or display name) |
| `-a, --assignee string` | Assignee (email or display name) |
| `-C, --component string` | Component |
| `-l, --label stringArray` | Label (repeatable) |
| `-P, --parent string` | Parent issue key |
| `--history` | Issues accessed recently |
| `-w, --watching` | Issues you watch |
| `--created` / `--updated` | `today`, `week`, `month`, `year`, `yyyy-mm-dd`, `yyyy/mm/dd`, or `-10d`/`-2w` |
| `--created-after` / `--created-before` | Date bounds |
| `--updated-after` / `--updated-before` | Date bounds |
| `-q, --jql string` | Raw JQL (still in project context) |
| `--order-by string` | Sort field (default `created`) |
| `--reverse` | Reverse order (default `DESC`) |
| `--paginate from:limit` | Page results (max 100) |
| `--plain` | Table output |
| `--no-headers` | Drop headers in plain mode |
| `--no-truncate` | All columns in plain mode |
| `--delimiter string` | Column separator in plain mode (default tab) |
| `--comments uint` | Comments shown when viewing (default 1) |

### `view` (`show`)

`jira issue view ISSUE-KEY [flags]` — `--comments N`, `--plain`, `--raw`.

### `create`

`jira issue create [flags]`

`-t/--type`, `-P/--parent` (required for sub-tasks), `-s/--summary`,
`-b/--body`, `-y/--priority`, `-r/--reporter`, `-a/--assignee`, `-l/--label`
(repeatable), `-C/--component` (repeatable), `--fix-version`,
`--affects-version`, `-e/--original-estimate`, `--custom k=v` (repeatable),
`-T/--template <file|->`, `--web`, `--no-input`, `--raw`.

`-b` wins over `--template`; a pipe is read when no body/template is given.

### `edit` (`update`, `modify`)

`jira issue edit ISSUE-KEY [flags]`

`-P/--parent`, `-s/--summary`, `-b/--body`, `-y/--priority`, `-a/--assignee`,
`-l/--label` (**appends**), `-C/--component` (**replaces**), `--fix-version`,
`--affects-version`, `--custom`, `--skip-notify`, `--web`, `--no-input`.

Prefix a value with `-` to remove it: `--label -urgent`, `--component -BE`,
`--fix-version -v1.0`.

### `comment`

`jira issue comment add ISSUE-KEY [COMMENT_BODY] [flags]` — `--internal`,
`--no-input`, `-T/--template`, `--web`. Alias group `comments`.

### `move` (`transition`, `mv`)

`jira issue move ISSUE-KEY STATE [flags]` — `--comment`, `-a/--assignee`,
`-R/--resolution`, `--web`. `STATE` is the exact status name.

### `assign` (`asg`)

`jira issue assign ISSUE-KEY ASSIGNEE` — ASSIGNEE is email/display name,
`default`, or `x` (unassign).

### `link` (`ln`)

`jira issue link INWARD_ISSUE_KEY OUTWARD_ISSUE_KEY ISSUE_LINK_TYPE [flags]` —
`--web`. Subcommand `remote ISSUE_KEY WEBLINK_URL WEBLINK_TITLE` (`rmln`) adds a
web link.

### `unlink` (`uln`)

`jira issue unlink INWARD_ISSUE_KEY OUTWARD_ISSUE_KEY [flags]` — `--web`.

### `watch` (`wat`)

`jira issue watch ISSUE-KEY WATCHER` — email/display name, `$(jira me)`.

### `worklog`

`jira issue worklog add ISSUE-KEY TIME_SPENT [flags]`

`--started "2022-01-01 09:30:00"`, `--timezone` (IANA, default UTC),
`--comment`, `--new-estimate`, `--no-input`. `TIME_SPENT` is `2d 1h 30m` style.

### `clone`

`jira issue clone ISSUE-KEY [flags]` — `-P/--parent`, `-s/--summary`,
`-y/--priority`, `-a/--assignee`, `-l/--label`, `-C/--component`,
`-H/--replace "search:replace"` (repeatable), `--web`.

### `delete` (`remove`, `rm`, `del`)

`jira issue delete ISSUE-KEY [flags]` — `--cascade` deletes subtasks too.

## `jira sprint`

| Command | Usage |
| --- | --- |
| `list` (`ls`) `[SPRINT_ID]` | List sprints, or (with an ID) their issues. Flags: `-C/--component`, `-P/--parent`, `-q/--jql`, `--order-by`, `--paginate`, `--plain`, `--no-headers`, `--no-truncate`, `--delimiter`, `--comments`, `--raw`, `--csv`, `--state future,active,closed`, `--show-all-issues`, `--table`, `--columns`, `--fixed-columns`, `--current`, `--prev`, `--next` |
| `add` (`assign`) `SPRINT_ID ISSUE-1 [...ISSUE-N]` | Add up to 50 issues to a sprint |
| `close` (`complete`) `SPRINT_ID` | Close a sprint |

## `jira epic`

| Command | Usage |
| --- | --- |
| `list` (`ls`) `[EPIC-KEY]` | List epics, or (with a KEY) their issues. Flags mirror `issue list` plus `--raw`, `--csv`, `--table`, `--columns`, `--fixed-columns` |
| `create` | `-n/--name`, `-s/--summary`, `-b/--body`, `-y/--priority`, `-r/--reporter`, `-a/--assignee`, `-l/--label`, `-C/--component`, `--fix-version`, `--affects-version`, `-e/--original-estimate`, `--custom`, `-T/--template`, `--web`, `--no-input` |
| `add` (`assign`) `EPIC-KEY ISSUE-1 [...ISSUE-N]` | Attach up to 50 issues to an epic |
| `remove` (`rm`, `unassign`) `ISSUE-1 [...ISSUE-N]` | Detach issues from their epic |

## `jira board`

`jira board list` (`ls`) — boards in the project.

## `jira project`

`jira project list` (`ls`) — projects the user can access. Columns: KEY, NAME,
TYPE, LEAD.

## `jira release`

`jira release list` (`ls`) — project versions.
