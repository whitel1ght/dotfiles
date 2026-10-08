---
name: obsidian-cli
description: >-
  Create, append to, search, and manage notes in an Obsidian vault via the obsidian CLI. Use when the user wants to write to a daily note, capture a thought to their vault, search notes, list/toggle tasks, read note contents, manage tags or properties, or otherwise drive their Obsidian vault from the conversation.
---


# Obsidian CLI

Drive Obsidian vault operations via the `obsidian` CLI. The CLI talks to the running Obsidian desktop app, so the app must be open; there is no headless mode.

For commands beyond the tier-1 list in this file, see `reference.md` (full catalog) and `examples.md` (end-to-end workflows). For anything else, run `obsidian help <command>`.

## Environment

- **Binary**: `/usr/local/bin/obsidian` (symlink to `/Applications/Obsidian.app/Contents/MacOS/obsidian-cli`). If `command -v obsidian` returns empty in a non-login shell, fall back to the absolute path.
- **Tested against**: v1.12.7 — verify with `obsidian version`. Flag any major version drift to the user before relying on this reference.
- **Vault discovery**: `obsidian vaults` lists known vaults. Quote names with spaces.
- **No auth, no headless**: the desktop app must be running.

## Preflight (once per session)

On the first Obsidian-touching call in a conversation:

```sh
obsidian vaults
```

- If exit 0 and one vault: use it.
- If exit 0 and multiple vaults: ask the user which to target.
- If exit non-zero or empty output: tell the user "Obsidian app must be running — launch it and retry" and **stop**. Do not retry in a loop.

Cache the result for the rest of the session. Only re-probe if a later command fails with a not-running signature (connection refused / no response from app).

## Command Pattern

```
obsidian <command> [key=value ...] [vault="<name>"]
```

All arguments are `key=value` pairs — **not** POSIX `--flags`. Always include `vault=` explicitly; don't rely on default selection.

### Global conventions

- **`file=<name>` vs `path=<folder/note.md>`**: `file=` resolves wiki-link style (fuzzy by basename, can match the wrong note silently). Use `path=` when you know the exact location.
- **`content="..."`**: use literal `\n` for newline, `\t` for tab. Heredoc is **not** supported by the CLI. Always quote values containing spaces.
- **`format=json|tsv|csv|md`**: machine-parseable output. Default to `format=json` when piping to `jq` or downstream processing.
- **Boolean flags**: pass the bare key (no `=value`). Examples: `inline`, `open`, `newtab`, `overwrite`, `verbose`, `total`, `permanent`.
- **Read-only vs write commands**: list, read, search, files, folders, backlinks, links, orphans, tags, properties, outline are safe to run anytime. Write commands (create, append, prepend, delete, move, rename) need explicit user intent.

## Tier-1 Quick Reference

Auth/vault flag omitted for brevity — append `vault="Obsidian Vault"` (or whatever the user's vault is) to every command.

### Note CRUD

```sh
obsidian create name="2026-05-20 Meeting" content="Notes:\n- ..." open       # New file
obsidian create name="..." template="meeting" content="..."                    # From template
obsidian read file="2026-05-20 Meeting"                                        # Fuzzy lookup
obsidian read path="Meetings/2026-05-20.md"                                    # Exact path
obsidian append file="Daily/2026-05-20" content="\n- Follow-up sent"           # Append (adds newline)
obsidian append path="..." content="status: shipped" inline                    # Append no newline
obsidian prepend file="..." content="UPDATE 2026-05-20: ..."                   # Prepend
obsidian delete file="Scratchpad"                                              # → Trash
obsidian delete path="Inbox/old.md" permanent                                  # Skip Trash (confirm!)
obsidian move file="Inbox Note" to="Projects/Acme/"                            # Move folder
obsidian rename file="old name" name="new name"                                # Rename in place
obsidian open file="2026-05-20 Meeting" newtab                                 # Open in editor
```

### Daily journaling

`daily:*` commands respect the user's Obsidian Daily Notes plugin settings (date format, folder).

```sh
obsidian daily                                          # Open today's daily note
obsidian daily:path                                     # Print today's daily-note path
obsidian daily:read                                     # Read today's daily-note contents
obsidian daily:append content="- Shipped X\n- Met Y"    # Append a journal line
obsidian daily:append content="task done" inline        # Append without trailing newline
obsidian daily:prepend content="### Morning intent\n..."# Prepend a section
```

### Search & analysis

```sh
obsidian search query="invoice template" format=json                   # Full-text vault search
obsidian search query="@urgent" path="Projects/" limit=20 format=json  # Scoped + limited
obsidian search:context query="..." format=json                        # Search with matching-line context
obsidian files folder="Meetings/" ext=md                               # List files in folder
obsidian folders folder="Projects/"                                    # List subfolders
obsidian backlinks file="Acme Project" counts format=json              # Who links here?
obsidian links file="Acme Project" total                               # Outgoing link count
obsidian orphans format=json                                           # Notes with no incoming links
obsidian outline path="Meetings/2026-05-20.md" format=json             # Headings tree
obsidian tags counts sort=count format=json                            # All vault tags by frequency
obsidian properties counts format=json                                 # All frontmatter properties
obsidian wordcount file="Some Note"                                    # Words + characters
```

### Tasks

```sh
obsidian tasks todo verbose format=json                  # All open tasks, grouped by file
obsidian tasks done format=json                          # Completed tasks
obsidian tasks status="/" format=json                    # In-progress (custom status char)
obsidian tasks path="Projects/" todo format=json         # Scoped to a folder
obsidian tasks daily todo                                # Tasks in today's daily note
obsidian task ref="Projects/Acme.md:42" toggle           # Toggle a specific task
obsidian task ref="Projects/Acme.md:42" done             # Mark done
obsidian task ref="..." status="x"                       # Set explicit status char
```

## Gotchas

- **Obsidian must be running.** Every command fails until the app launches.
- **`file=` is fuzzy.** It can match the wrong note silently — prefer `path=` when accuracy matters.
- **Editor race**: writing to a note the user has open with unsaved buffer can collide. Warn the user before `append`/`prepend` on a file they may be editing live.
- **Vault name with spaces** (e.g. `"Obsidian Vault"`) must be quoted: `vault="Obsidian Vault"`.
- **`delete` defaults to Trash.** Adding `permanent` skips Trash — never use it without explicit user confirmation.
- **Content escapes**: `\n` and `\t` only; no heredoc, no real newlines inside `content="..."`.
- **`format=json` only on commands that document it** — check `obsidian help <command>` for the supported list per command.
- **Sync commands** (`sync:*`) interact only with Obsidian Sync, not Git.

## Destructive Command Confirmation Gate

Before running any of these, restate the target and action and get explicit user confirmation:

- `delete` (especially with `permanent`)
- `move` (changes paths, may break backlinks)
- `rename`
- `history:restore` / `sync:restore` (overwrites current content)
- `plugin:uninstall`, `theme:uninstall`
- `template:insert` into the active file (modifies whatever's open)

## Quality Checklist

- [ ] Preflight done (or cached) for this session
- [ ] `vault="..."` included on every command, quoted
- [ ] `file=` (fuzzy) vs `path=` (exact) chosen deliberately
- [ ] `content="..."` uses literal `\n`, not real newlines
- [ ] `format=json` added on any output that will be parsed
- [ ] Destructive command got explicit user confirmation
- [ ] Output presented to the user, not just consumed silently

## Supporting Files

- **`examples.md`** — five end-to-end workflow recipes (daily append, meeting note, search-and-read, task triage, find orphans).
- **`reference.md`** — full ~100-command catalog grouped by category. Read on demand when tier-1 isn't enough.
