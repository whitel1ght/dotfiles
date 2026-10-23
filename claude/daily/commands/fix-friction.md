---
description: Turn a proposed friction-ledger entry into a tested fix on a branch, stop for your test, and fast-forward it into local main on your approval (or, with --auto, build it unattended for coach-fix to land)
argument-hint: <F-NNN> [--auto]
disable-model-invocation: true
---

# Fix a friction entry

Arguments: $ARGUMENTS

You orchestrate one fix. Follow `/orchestrate`'s rules (`~/.claude/commands/orchestrate.md`) for models, briefs and checking results. The fix ladder is the rule: a failure is handled by a **script** first (retry, health gate, preflight, cache, fallback, background waiter), then **config** (re-auth, env var, setting, dropping a dead step), and only then **prompt** text, when the problem is the model's judgement. Runtime handling spends no model tokens.

Write rules: the implementer never touches `~/wiki` except `~/wiki/work/system/` and `~/wiki/tools/` (only those), which it updates when the fix changes the system and commits with `~/.local/bin/wiki-commit --by claude -m "<msg>" -- <paths>` (if it exits 2 only because there is no wiki, carry on); only this session writes the ledger, and only in step 5. Never push. Never merge before the user's explicit approval in step 4. `F` is the argument (`F-007`), `W=~/projects/worktrees/dotfiles/friction-$F`.

When the arguments include `--auto`, skip steps 1–5 and follow **Auto mode** at the end instead.

## 1. Check

Read `~/wiki/work/friction/$F.md` (frontmatter, `## Evidence`, `## Diagnosis`, `## Proposal`). Refuse, saying why, and stop, when the file is missing or `status` is not `proposed`, `regressed` or `open`. If `$W` or branch `friction-$F` already exists, say so and ask whether to continue in it or start over.

## 2. Worktree

Local main is ahead of origin, so the branch starts from local main, not origin's default:

```bash
git -C ~/projects/dotfiles branch friction-$F main && wt add dotfiles friction-$F
```

## 3. Implement

Dispatch one implementer with the `Agent` tool: `model: "sonnet"` (explicit), cwd `$W`. Brief (write it to the scratchpad first):

- **Goal:** implement the F-file's proposal, pasting its full content.
- **Rung:** use the lowest rung that works (script > config > prompt). Say which rung you chose and why each lower rung does not fit; a prompt-only fix needs that justification written out.
- **Test:** add a test that fails without the fix and passes with it. No test, no fix.
- **Suites:** run what the change touches: `bin/<x>.test.sh` for a changed script, `claude/daily/tests/run-all.sh` for the plugin, `node --test` in a touched pi extension, `bin/pi-contract` if pi prompts changed (it needs a live model; say if it could not run).
- **Constraints:** work only in `$W`, touch `~/wiki` only in `work/system/` and `tools/` (commit those with `wiki-commit --by claude`), never push, Conventional Commits, commit on the branch.
- **Report:** rung and justification, files changed, commit sha, how to test by hand, suite results.

Check the report yourself: `git -C $W log --oneline main..`, `git -C $W diff --stat main`, and re-run the suites. A failure goes back to a fresh implementer with the failure in the brief; a second failure escalates one tier.

## 4. Stop

Show the user: the rung and why, what changed (diff stat, the commit subjects), the manual test steps, the suite results. Then **stop and wait**. Merge nothing until the user says to.

## 5. On approval

1. If main moved, rebase the branch onto it in `$W` and re-run the suites.
2. Merge, never push:

```bash
git -C ~/projects/dotfiles merge --ff-only friction-$F
SHA="$(git -C ~/projects/dotfiles rev-parse --short HEAD)"
```

3. Clean up: `git -C ~/projects/dotfiles worktree remove $W && git -C ~/projects/dotfiles branch -d friction-$F`.
4. Wiki (this session writes): in `~/wiki/work/friction/ledger.md` set the row's `status` to `fixed` and `fix` to `$SHA`; in `$F.md` set frontmatter `status: fixed`, `fix: $SHA`, `rung:` to the rung used, and add a `## History` line `- <date>: fixed in <sha> (<rung>)`. Then `git -C ~/wiki add work/friction && git -C ~/wiki commit -m "wiki: friction $F fixed"`.
5. Tell the user it is in local main and not pushed.

If the user rejects the change, leave the worktree and branch, set nothing in the ledger, and ask what to change.

## Auto mode (`--auto`)

`coach-fix` starts this in a tmux window `coach-$F` after the user said yes to the coach's suggestion in /start-day. It runs unattended: it never asks the user anything (nobody is watching), never merges, and never pushes (the claude-components branch below is the one exception). It ends with exactly one of these, and only this session calls them:

- built: `~/.local/bin/coach-fix built $F --repo <repo> --branch coach-$F --worktree $W --test-cmd "<cmd>"`, or `~/.local/bin/coach-fix built $F --mr <url>` for claude-components;
- anything else: `~/.local/bin/coach-fix fail $F --reason "<one line: why>"`.

`coach-fix land` merges a built branch after the day and writes the ledger; the next /start-day reports the result. Do not write the ledger yourself. `F` is the first argument.

1. **Check.** Read `~/wiki/work/friction/$F.md` and `~/.local/state/coach/queue/$F.json`. Go on only when the entry's `status` is `landing` and the queue `state` is `running`; otherwise say so and stop without calling `coach-fix`. Then pick the repo from the proposal:
   - `dotfiles`, `decisions` or `articles` (main checkout `~/projects/<repo>`): steps 2–5.
   - `claude-components`: the draft MR path below.
   - anything that needs the user: a `secret` entry (signature `…:secret:…`; its fix is user steps), rotating or revoking a secret, an ECFX repo, a change in an outside account (GitHub, GitLab or Atlassian settings, the Chrome extension's own settings UI), a `brew` or package install, or any other repo. Do not start it: `~/.local/bin/coach-fix fail $F --reason "needs the user: <the exact steps, in order>"`, then stop.
2. **Worktree.** Read the system page for the part being changed (`~/wiki/work/system/`). Branch from local main, not origin's default, with `wt add <repo> coach-$F`:

   ```bash
   git -C ~/projects/<repo> branch coach-$F main && wt add <repo> coach-$F
   ```

   `W=~/projects/worktrees/<repo>/coach-$F`. If the branch or `$W` already exists, fail with "coach-$F already exists" instead of reusing it.
3. **Implement** as in step 3 above, with cwd `$W` (implementer `model: "sonnet"`, the same brief: lowest rung, a test that fails before the fix, the covering suites, commits on the branch). Add to the brief: change nothing the proposal does not ask for, and never loosen a guard, hook or permission rule it does not name. Check the report yourself as in step 3.
4. **Review.** One fresh reviewer on a different model tier from the implementer: the `Agent` tool with `model: "opus"`, read-only, given the F-file, `git -C $W log --oneline main..` and `git -C $W diff main...`. It answers `approved` or numbered findings. Findings go to an implementer (the brief plus the findings), then the suites again, then the same review. At most two fix rounds; not approved after the second, or suites still red → `coach-fix fail $F --reason "<the open findings or the failing suite>"`.
5. **Built.** Green and approved: `--test-cmd` is the covering suites as one shell command run from `$W`, with no live model or network (for example `bin/coach-fix.test.sh && bin/friction-ledger.test.sh`); landing re-runs it if main moved. Then:

   ```bash
   ~/.local/bin/coach-fix built $F --repo <repo> --branch coach-$F --worktree $W --test-cmd "<cmd>"
   ```

   If it exits non-zero it has already marked the entry failed: say its message and stop.

**claude-components** (the team's repo; nothing from the fix is copied into dotfiles): `wt add claude-components coach-$F` (it branches from origin's default), `W=~/projects/worktrees/claude-components/coach-$F`; steps 3 and 4 there with that repo's tests. Then write the description with the `mr-description` skill, push the branch (`git -C $W push -u origin coach-$F`, the only push in this mode) and open a draft MR assigned to the user, with no reviewers:

```bash
glab mr create --draft --assignee "$(glab api user | jq -r .username)" --title "Draft: <subject>" --description "$(cat <description file>)" --yes
```

Never undraft it, merge it or request reviewers. Then `~/.local/bin/coach-fix built $F --mr <the MR url>`.

Whatever blocks you (a missing tool, an unclear proposal, a failed command), fail with the reason rather than wait for an answer.
