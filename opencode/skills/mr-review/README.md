# MR Review skill

Conduct a tiered code review on a GitLab merge request. Drafts a Blocker / Observation / Nit / What's-good review (or a re-review variant), gates on user approval, then posts via `glab mr note`.

## What it does

When you say *"review MR 5348"* or paste a GitLab MR URL, the skill:

1. Fetches the MR metadata, comments, and diff via `glab`.
2. Auto-discovers the local clone of the repo so Claude can read source files outside the diff.
3. Detects whether *you* have already reviewed this MR (re-review vs first-pass).
4. Drafts a structured review tailored to the case.
5. Presents it to you in chat — **does not auto-post**.
6. After you confirm, posts via `glab mr note` with HEREDOC-safe formatting.

The structure is fixed (so colleagues' reviews look consistent). The judgment is yours.

## Prerequisites

- **`glab` CLI** installed and authenticated: `glab auth login`. Verify with `glab api user`.
- **`jq`** for path-cache reads/writes (most macOS setups have it; `brew install jq` if not).
- **A local clone** of any repo you want to review. The auto-discovery walks `~/Documents/source`, `~/code`, `~/src`, `~/projects`, `~/work`, and `~/dev` (4 levels deep) looking for clones whose `origin` matches the MR's repo.

## Setup

### One-time install (once per machine)

The skill is part of the `shared` plugin of `claude-components`. Register the marketplace
once; the product repositories enable `shared` themselves:

```bash
cd <your claude-components clone>
./setup.sh
```

### Per-repo configuration (only when needed)

Auto-discovery is the default — you don't need to do anything if your clone lives under one of the standard search roots. The script caches successful single matches to `~/.config/mr-review/paths.json` for next time.

Two cases require an explicit entry in that file:

1. **Multiple clones of the same repo.** If you have several clones (e.g. `~/code/myproject` and `~/work/myproject-backup`), the script can't pick. It exits 2 and lists candidates. Pick one and write:

   ```json
   {
     "owner/repo": "/abs/path/to/canonical/clone"
   }
   ```

2. **Clone outside the standard roots.** If you keep clones somewhere unusual (`~/Repositories/`, `/opt/code/`, etc.), add an explicit mapping rather than expanding the search list.

The file is plain JSON, hand-edit-safe. Multiple repos in one file:

```json
{
  "ecfx/ecfx-backend": "/Users/you/Documents/source/ecfx-backend",
  "ecfx/ecfx-admin":   "/Users/you/Documents/source/ecfx-admin",
  "myorg/myproject":   "/Users/you/code/myproject"
}
```

### Verify setup

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/locate-checkout.sh <owner>/<repo>
```

Expected outputs:
- **Single match** → prints absolute path, exits 0, caches the match.
- **No match** → prints diagnostic, exits 1. Add an explicit entry.
- **Multiple matches** → lists candidates, exits 2. Add an explicit entry to disambiguate.

## How to invoke

In a Claude Code session, any of these triggers the skill:

- `review MR 5348`
- `review !5348`
- `do another pass on 5330`
- `https://gitlab.com/myorg/myrepo/-/merge_requests/42`

If you've been working in a particular repo (e.g. it's named in CLAUDE.md or earlier in the conversation), `review MR 5348` is enough; otherwise spell out `<owner>/<repo>!<N>`.

## What the review looks like

**First pass:**

```markdown
[Two- or three-sentence summary + recommendation.]

## Blockers
None.

## Observations
**O1 — [headline]** — [body]
**O2 — [headline]** — [body]

## Nits
**N1 — [headline]** — [body]

## What's good
- [specific thing the MR did well]
- [another thing]
```

**Re-review:**

```markdown
[Two- or three-sentence summary of what's resolved + recommendation.]

## Blockers
None.

## Verified addressed
- **O1** — [what changed, ✓]
- **O2** — [what changed, ✓]

## New observations
**O3 — [headline]** — [body]

## Items deferred (acknowledged)
- **O4** — [author deferred to follow-up ticket; reasonable]

## What's good on this pass
- [specific thing the new revision did well]
```

## How it works

The full instruction set lives in `SKILL.md`. Key design choices:

- **Approval gate before posting.** Claude always shows you the draft and waits for explicit confirmation. You can ask to drop or adjust items before it goes out.
- **Cite file:line.** Reviews name the specific file and line wherever possible — reviewers who can navigate to the spot are more useful than reviewers who say "around the auth method".
- **Verify against the local checkout.** The skill instructs Claude to read actual source files (not just the diff) for any claim that depends on code outside the hunk. That's the main reason auto-discovery of the local clone matters.
- **Calibrate severity.** Blocker / Observation / Nit are distinct tiers; the SKILL.md prose tells Claude how to choose between them and what counts as which.
- **HEREDOC posting.** `glab mr note --message "$(cat <<'EOF' ... EOF)"` preserves backticks, code blocks, and special characters that shell quoting would mangle.

## Files

```
mr-review/
├── SKILL.md                     # Claude-facing instructions (the skill body)
├── scripts/
│   └── locate-checkout.sh       # Auto-discovers local clone path
├── examples.md                  # Worked examples
└── README.md                    # This file
```

## Limitations

- **GitLab only.** `glab` doesn't support GitHub. A future variant could swap in `gh` for the same workflow.
- **One MR at a time.** No batch mode. Run the skill once per MR.
- **Doesn't auto-comment inline.** Posts a single top-level note. Inline comments-on-specific-lines via `glab` are clumsy; the team-conventional pattern of one structured top-level note works better for tiered reviews anyway.
- **No private MCP access.** Doesn't use Atlassian/CloudWatch/Grafana — those are separate tools the user can ask Claude to use independently if useful for verifying a claim.

## Troubleshooting

**"glab: command not found"** — install via `brew install glab` or your package manager, then `glab auth login`.

**"No local clone found for `<repo>`"** — either clone the repo somewhere under a standard root, or add an explicit mapping to `~/.config/mr-review/paths.json`.

**"Multiple local clones found"** — pick one and write to `~/.config/mr-review/paths.json`. Auto-discovery refuses to guess.

**Review draft seems generic / didn't read source files** — the skill instructs Claude to read source for any claim that depends on code outside the diff, but Claude's judgment on *which* files to read is heuristic. If you spot a generic claim, push back: *"verify by reading X.java"* and Claude will re-check.

**Post fails with "permission denied"** — `glab` needs write scope. Re-run `glab auth login` and grant `api` + `write_repository` permissions for the host.
