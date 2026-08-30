---
name: vendor-skill
description: Vendor a third-party Claude skill from a GitHub/GitLab repo into this dotfiles repo — finds the skill's path in the upstream repo, adds it to claude/vendor.json, and syncs. Use when the user says "vendor <skill> from <repo>", "add this skill from github", "grab the tdd skill from mattpocock/skills", "what skills does <repo> have", or invokes /vendor-skill.
---

# Vendor Skill

Add a third-party skill to `claude/vendor.json` and sync it, so it loads
namespaced as `<author>:<skill>` and cannot collide with the personal skills in
`claude/skills/`.

Read `README.md`'s "Vendored third-party skills" section if you need background
on the mechanism.

## Inputs

A repo, and optionally a skill name:

- repo — `owner/repo` shorthand, or any git URL (HTTPS, SSH, GitLab).
- name — optional. Without it, list what the repo offers and ask which.

## Steps

Work from the dotfiles repo. `find-skill.sh` sits beside this file; call it by
its path in the repo, not through `~/.claude/skills/`.

### 1. Find the skill

```bash
./claude/skills/vendor-skill/find-skill.sh <repo> [name]
```

Exit codes: `0` printed at least one path, `1` nothing matched, `2` the repo
could not be read.

- **`2`** — report that the repo is unreachable. Check the spelling with the
  user rather than guessing at alternatives.
- **`1`** — tell the user nothing matched, then run it again with no name to
  show what the repo *does* offer, and ask which they meant.
- **several lines** — the name was ambiguous. Show the matches and ask which
  one. Do not pick for them.
- **no name given** — show the full list, grouped by their parent directory so
  categories read clearly, and ask which to vendor.

Stop and ask whenever the answer is not exactly one path. Vendoring the wrong
skill is silent — it just quietly appears in every session.

### 2. Resolve the canonical URL and the wrapper

```bash
URL=$(./claude/skills/vendor-skill/find-skill.sh --url <repo>)
```

Always match against this URL, never the shorthand — `claude/vendor.json`
records sources by full URL, so comparing a shorthand would miss and create a
duplicate wrapper for a repo that is already vendored.

```bash
jq -r --arg url "$URL" '.sources[] | select(.repo == $url) | .name' claude/vendor.json
```

- **A name comes back** — that author is already vendored. Add to that source.
- **Nothing comes back** — this is a new source. Propose a wrapper name (the
  repo owner: `mattpocock/skills` → `mattpocock`) and confirm it with the user
  before writing. The name becomes the skill's namespace and its directory, so
  it is worth one question.

### 3. Check it is not already vendored

```bash
jq -r --arg url "$URL" --arg p "<path>" \
  '.sources[] | select(.repo == $url) | .skills[] | select(. == $p)' claude/vendor.json
```

If that prints the path, it is already vendored. Say so and stop — do not add a
duplicate entry.

### 4. Add it to the manifest

Existing source — append the path:

```bash
tmp=$(mktemp)
jq --arg url "$URL" --arg p "<path>" \
  '(.sources[] | select(.repo == $url) | .skills) += [$p]' \
  claude/vendor.json > "$tmp" && mv "$tmp" claude/vendor.json
```

New source — add the whole entry:

```bash
tmp=$(mktemp)
jq --arg name "<wrapper>" --arg url "$URL" --arg p "<path>" \
  '.sources += [{name: $name, repo: $url, ref: "HEAD", skills: [$p]}]' \
  claude/vendor.json > "$tmp" && mv "$tmp" claude/vendor.json
```

`ref` defaults to `HEAD` (the remote's default branch). Use a branch or tag name
instead if the user asks to pin it. A raw commit SHA is not supported.

### 5. Sync

```bash
./claude/vendor-sync.sh
```

**If the wrapper is new, also run `./install.sh`** — the sync writes
`claude/vendor/<wrapper>/`, but it is `install.sh` that symlinks it into
`~/.claude/skills/`. Without that step a brand-new author is vendored but never
loads. An existing wrapper is already linked, so the sync alone is enough.

### 6. Report

```bash
claude plugin details <wrapper>@skills-dir
```

Tell the user what was added, the wrapper's new always-on token cost, and that
the skill is available next session.

Then show them the pending change:

```bash
git status --short claude/vendor claude/vendor.json claude/vendor.lock.json
```

**Do not commit.** Leaving the change unstaged is deliberate throughout this
system: `git diff claude/vendor/` is how the user reviews third-party prompt
content before accepting it. Offer to commit; let them answer.

## Notes

- Vendored directories are byte-exact upstream copies and are destroyed on the
  next sync. To modify one, copy it into `claude/skills/` instead.
- Removing a skill is the reverse: delete its path from `claude/vendor.json` and
  run `./claude/vendor-sync.sh`. Removing a source's last skill leaves an empty
  `skills` array, which the sync rejects — delete the whole source entry instead.
- `find-skill.sh` has tests: `./claude/skills/vendor-skill/find-skill.test.sh`.
