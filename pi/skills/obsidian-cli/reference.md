# Reference — Obsidian CLI Full Command Catalog

Distilled from `obsidian help` (v1.12.7). Read this file when the tier-1 quick reference in `SKILL.md` doesn't cover the command you need. For exact flag signatures, run `obsidian help <command>` — that's always authoritative against the installed CLI version.

Global conventions (apply to every command):
- All args are `key=value` pairs, plus bare-key boolean flags.
- `vault="<name>"` selects the target vault.
- `file=<name>` is fuzzy wiki-link lookup; `path=<folder/note.md>` is exact.
- `content="..."` supports `\n` and `\t`; quote values with spaces.
- `format=` controls output encoding where supported (`json`, `tsv`, `csv`, `md`, `text`, `yaml` — per command).

---

## Notes — File Operations

| Command | Purpose | Key args |
|---|---|---|
| `create` | Create a new file | `name=`, `path=`, `content=`, `template=`, `overwrite`, `open`, `newtab` |
| `read` | Read file contents | `file=`, `path=` |
| `append` | Append content to a file | `file=`, `path=`, `content=` (req), `inline` |
| `prepend` | Prepend content to a file | `file=`, `path=`, `content=` (req), `inline` |
| `delete` | Delete a file | `file=`, `path=`, `permanent` |
| `move` | Move or rename a file | `file=`, `path=`, `to=` (req) |
| `rename` | Rename a file in place | `file=`, `path=`, `name=` (req) |
| `open` | Open file in editor | `file=`, `path=`, `newtab` |
| `file` | Show file info | `file=`, `path=` |
| `files` | List files in vault | `folder=`, `ext=`, `total` |
| `folder` | Show folder info | `path=` (req), `info=files\|folders\|size` |
| `folders` | List folders | `folder=`, `total` |
| `random` | Open a random note | `folder=`, `newtab` |
| `random:read` | Read a random note | `folder=` |
| `recents` | List recently opened files | `total` |
| `vault` | Show vault info | `info=name\|path\|files\|folders\|size` |
| `vaults` | List known vaults | `total`, `verbose` |
| `workspace` | Show workspace tree | `ids` |

---

## Daily Notes

| Command | Purpose | Key args |
|---|---|---|
| `daily` | Open today's daily note | `paneType=tab\|split\|window` |
| `daily:read` | Read today's daily note | — |
| `daily:path` | Print today's daily-note path | — |
| `daily:append` | Append to today's daily note | `content=` (req), `inline`, `open`, `paneType=` |
| `daily:prepend` | Prepend to today's daily note | `content=` (req), `inline`, `open`, `paneType=` |

All `daily:*` commands respect the user's Daily Notes plugin settings (date format, folder, template).

---

## Search & Vault Analysis

| Command | Purpose | Key args |
|---|---|---|
| `search` | Full-text vault search | `query=` (req), `path=`, `limit=`, `total`, `case`, `format=text\|json` |
| `search:context` | Search with matching-line context | `query=` (req), `path=`, `limit=`, `case`, `format=text\|json` |
| `search:open` | Open the search view in app | `query=` |
| `backlinks` | Notes linking to this file | `file=`, `path=`, `counts`, `total`, `format=json\|tsv\|csv` |
| `links` | Outgoing links from a file | `file=`, `path=`, `total` |
| `orphans` | Notes with no incoming links | `total`, `all` |
| `deadends` | Notes with no outgoing links | `total`, `all` |
| `unresolved` | Unresolved links in vault | `total`, `counts`, `verbose`, `format=json\|tsv\|csv` |
| `outline` | Headings for a file | `file=`, `path=`, `format=tree\|md\|json`, `total` |
| `wordcount` | Word + character count | `file=`, `path=`, `words`, `characters` |

---

## Tasks

| Command | Purpose | Key args |
|---|---|---|
| `tasks` | List tasks in vault | `file=`, `path=`, `total`, `done`, `todo`, `status="<char>"`, `verbose`, `format=json\|tsv\|csv`, `active`, `daily` |
| `task` | Show/update a single task | `ref="<path:line>"`, `file=`, `path=`, `line=`, `toggle`, `done`, `todo`, `daily`, `status="<char>"` |

Task status characters: ` ` = todo, `x` = done, `/` = in progress, `-` = cancelled (Obsidian conventions; custom characters supported via the Tasks plugin).

---

## Tags & Properties

| Command | Purpose | Key args |
|---|---|---|
| `tags` | List tags in vault | `file=`, `path=`, `total`, `counts`, `sort=count`, `format=json\|tsv\|csv`, `active` |
| `tag` | Get info for a single tag | `name=` (req), `total`, `verbose` |
| `properties` | List frontmatter properties | `file=`, `path=`, `name=`, `total`, `sort=count`, `counts`, `format=yaml\|json\|tsv`, `active` |
| `property:read` | Read a property value | `name=` (req), `file=`, `path=` |
| `property:set` | Set a property | `name=` (req), `value=` (req), `type=text\|list\|number\|checkbox\|date\|datetime`, `file=`, `path=` |
| `property:remove` | Remove a property | `name=` (req), `file=`, `path=` |
| `aliases` | List aliases in vault | `file=`, `path=`, `total`, `verbose`, `active` |

---

## Templates

| Command | Purpose | Key args |
|---|---|---|
| `templates` | List templates | `total` |
| `template:read` | Read template content | `name=` (req), `resolve`, `title=` |
| `template:insert` | Insert template into active file | `name=` (req) |

---

## Bookmarks

| Command | Purpose | Key args |
|---|---|---|
| `bookmarks` | List bookmarks | `total`, `verbose`, `format=json\|tsv\|csv` |
| `bookmark` | Add a bookmark | one of: `file=`, `folder=`, `search=`, `url=`; optional `subpath=`, `title=` |

---

## Bases (Obsidian Bases plugin)

| Command | Purpose | Key args |
|---|---|---|
| `bases` | List base files | — |
| `base:views` | List views in current base | — |
| `base:query` | Query a base | `file=`, `path=`, `view=`, `format=json\|csv\|tsv\|md\|paths` |
| `base:create` | Create item in a base | `file=`, `path=`, `view=`, `name=`, `content=`, `open`, `newtab` |

---

## Plugins

| Command | Purpose | Key args |
|---|---|---|
| `plugins` | List installed plugins | `filter=core\|community`, `versions`, `format=json\|tsv\|csv` |
| `plugins:enabled` | List enabled plugins | `filter=core\|community`, `versions`, `format=` |
| `plugins:restrict` | Toggle restricted mode | `on`, `off` |
| `plugin` | Get plugin info | `id=` (req) |
| `plugin:install` | Install a community plugin | `id=` (req), `enable` |
| `plugin:uninstall` | Uninstall a community plugin | `id=` (req) |
| `plugin:enable` | Enable a plugin | `id=` (req), `filter=core\|community` |
| `plugin:disable` | Disable a plugin | `id=` (req), `filter=core\|community` |
| `plugin:reload` | Reload a plugin (dev) | `id=` (req) |

---

## Themes & Snippets

| Command | Purpose | Key args |
|---|---|---|
| `themes` | List installed themes | `versions` |
| `theme` | Show active theme / get info | `name=` |
| `theme:set` | Set active theme | `name=` (req — empty for default) |
| `theme:install` | Install a community theme | `name=` (req), `enable` |
| `theme:uninstall` | Uninstall a theme | `name=` (req) |
| `snippets` | List installed CSS snippets | — |
| `snippets:enabled` | List enabled CSS snippets | — |
| `snippet:enable` | Enable a CSS snippet | `name=` (req) |
| `snippet:disable` | Disable a CSS snippet | `name=` (req) |

---

## Sync & History

| Command | Purpose | Key args |
|---|---|---|
| `sync` | Pause or resume sync | `on`, `off` |
| `sync:status` | Show sync status | — |
| `sync:deleted` | List deleted files in sync | `total` |
| `sync:history` | Sync version history for a file | `file=`, `path=`, `total` |
| `sync:read` | Read a sync version | `file=`, `path=`, `version=` (req) |
| `sync:restore` | Restore a sync version | `file=`, `path=`, `version=` (req) |
| `sync:open` | Open sync history UI | `file=`, `path=` |
| `history` | List file history versions | `file=`, `path=` |
| `history:list` | List files with history | — |
| `history:read` | Read a history version | `file=`, `path=`, `version=` (default 1) |
| `history:restore` | Restore a history version | `file=`, `path=`, `version=` (req) |
| `history:open` | Open file recovery UI | `file=`, `path=` |
| `diff` | List or diff local/sync versions | `file=`, `path=`, `from=`, `to=`, `filter=local\|sync` |

---

## Tabs & UI

| Command | Purpose | Key args |
|---|---|---|
| `tabs` | List open tabs | `ids` |
| `tab:open` | Open a new tab | `group=`, `file=`, `view=` |
| `command` | Execute an Obsidian command | `id=` (req) |
| `commands` | List available Obsidian commands | `filter=` |
| `hotkey` | Get hotkey for a command | `id=` (req), `verbose` |
| `hotkeys` | List hotkeys | `total`, `verbose`, `format=json\|tsv\|csv`, `all` |
| `reload` | Reload the vault | — |
| `restart` | Restart the app | — |

---

## Developer Tools

These expose Electron / Chrome DevTools APIs. Use sparingly — they're for plugin debugging, not for note workflows.

| Command | Purpose | Key args |
|---|---|---|
| `eval` | Execute JavaScript in the app | `code=` (req) |
| `dev:screenshot` | Take a screenshot | `path=` |
| `dev:dom` | Query DOM elements | `selector=` (req), `total`, `text`, `inner`, `all`, `attr=`, `css=` |
| `dev:css` | Inspect CSS with source locations | `selector=` (req), `prop=` |
| `dev:console` | Show captured console messages | `clear`, `limit=`, `level=log\|warn\|error\|info\|debug` |
| `dev:errors` | Show captured errors | `clear` |
| `dev:debug` | Attach/detach CDP debugger | `on`, `off` |
| `dev:cdp` | Run a Chrome DevTools Protocol command | `method=` (req), `params=<json>` |
| `dev:mobile` | Toggle mobile emulation | `on`, `off` |
| `devtools` | Toggle Electron dev tools | — |

---

## Meta

| Command | Purpose |
|---|---|
| `help` | Show command list (or `obsidian help <command>` for one) |
| `version` | Show Obsidian version |

For any command not listed here or with unfamiliar flags, run `obsidian help <command>` against the installed CLI — that output is authoritative.
