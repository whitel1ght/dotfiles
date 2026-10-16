# wiki-search

Two tools for the local-model profile (`pigm` in `zsh/.zshrc`), which runs pi
with `-ne -nc`: no extensions or context files, so the model would not know the
qmd commands. Loaded explicitly with `-e`; it is not under `pi/extensions/`, so
the full pi setup does not pick it up.

| Tool | Does |
| --- | --- |
| `wiki_search(query, scope?)` | `qmd query --json`, top 5 hits with path and snippet. `scope`: `all` (default: notes, diary, ecfx, epicmax, personal, reviews, saved), `notes`, `diary`, `projects`, `articles` (saved web articles). `pi-memory` is never searched, per `~/wiki/AGENTS.md`. |
| `wiki_read(path, from?)` | `qmd get <qmd:// path>:<from> -l 200` |

A query takes 15–30 s: qmd runs local models to expand and rerank it.

Tests: `node --test *.test.ts` (a fake `qmd` records the calls).
