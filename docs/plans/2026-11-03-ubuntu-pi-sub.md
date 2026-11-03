# Brief: move the `ubuntu` branch onto pi-sub

For the coding agent on the ThinkPad (Ubuntu, `dmitry-ThinkPad-T480`) that fixes pi on
the `ubuntu` branch of `~/projects/dotfiles`. Written 2026-11-03 on the Mac from `main` at
`f371660` and `origin/ubuntu` at `801635e`. The "Facts" section was checked on the laptop
over SSH that day. Re-check anything that may have changed since.

## Goal

Delegation on Ubuntu runs on our own extension, `pi/extensions/pi-sub`, the same as on the
Mac, and nothing on the branch or the machine still uses the npm `pi-subagents` package.
Both machines then have one subagent runtime, one tool API in the prompts, and one set of
docs.

## Ground rules

- Work in a worktree branched from `ubuntu`: `wt add dotfiles <name> ubuntu`. Never merge
  `main` into `ubuntu` or the reverse. `main` deletes Ubuntu's Linux setup and `ubuntu`
  deletes the Mac's. Take files from `main` one path at a time.
- The live checkout has the user's uncommitted work; leave it alone.
  `proxy/config.template.json` adds `192.168.0.0/16` to `route_exclude_address`, which
  is what lets the Mac SSH in. There is also an untracked `.gitconfig`. Ask the user
  before committing the proxy line, as its own commit. Never commit `.gitconfig`.
- Do not push to `main`. Push your branch and report it. The user merges it into
  `ubuntu`.
- Questions to the user go through the decisions deck (`ask_user`), as `CLAUDE.md` says.

## Why the branch is on the npm package

`ubuntu` imported `main`'s portable config in October 2026 while `main` was mid-switch. The
README and `pi/agents.test.mjs` still required `pi-subagents@0.76.0`, but
`pi/settings.json` had already dropped it (`9d158cb`, 2026-10-08).
`docs/plans/ubuntu-main-migration.md` step 4 settled that by pinning the package again.
`main` then finished `pi-sub` and deleted the old runtime, its tests and the pin. Ubuntu
is the one behind.

## Read first (on `origin/main`; the laptop already has it fetched)

- `git show origin/main:pi/README.md`, section "Delegation": how pi-sub, `session-models`
  and the role files fit together.
- `pi/extensions/pi-sub/README.md`: tools, state dir, wake-up, timeouts, keys.
- `pi/model-selection.md` and `pi/APPEND_SYSTEM.md`: the policy and the tool contract
  the model is told about.
- `bin/pi-contract`: the only check that runs a real pi. It fails when a prompt names a
  tool that does not exist.

## Facts on the laptop (checked 2026-11-03)

- pi 1.5.0 (`~/.pi/agent/install/releases/` has 1.4.0 and 1.5.0). pi-sub was verified
  against Pi 1.2.0 on the Mac, so `bin/pi-contract` is the proof here.
- Node v24.22.0 comes from nvm and is on PATH only in an interactive zsh. In a
  non-interactive shell `node` is missing, and even `pi --version` fails with
  `/usr/bin/env: 'node': No such file or directory`. Run tests through `zsh -ic '…'` or
  load nvm first. pi-sub starts `run.mjs` with the host's `process.execPath` and the
  child with `pi` from the inherited PATH, so a child launched from an interactive pi
  session is fine. Anything started by systemd or cron is not.
- `ps -E` does not exist on Ubuntu: `ps -E -p $$ -o command=` prints `error: unsupported
  SysV option` and exits 1. `/proc/<pid>/environ` is readable. See step 1.
- `~/.pi/agent/extensions` → `~/projects/dotfiles/pi/extensions` and
  `~/.pi/agent/agents` → `~/projects/dotfiles/pi/agents` are symlinks. So the extensions
  and roles of whatever is checked out in the live repo are what pi loads. Your
  worktree's files are not loaded until `ubuntu` is updated in that checkout.
- `~/.pi/agent/settings.json` is a regular per-host file (seeded by the branch's `plink`),
  not a link. Editing `pi/settings.json` in the repo does not change the live file:
  apply the same package edits to `~/.pi/agent/settings.json` by hand.
- Installed npm packages (`~/.pi/agent/npm/node_modules`) include `pi-subagents` 0.76.0,
  `pi-memory`, `pi-background-tasks`, `billion-context`, `pi-lens`, `pi-web-access`,
  `pi-playwright`.
- claude-components is at `~/projects/ecfx/claude-components`, not
  `~/projects/claude-components`. `main`'s `bin/plink` reads `CLAUDE_COMPONENTS_DIR`, and
  `pi/gen/*.py` take `--src`.

## What is wrong on `ubuntu`

- `pi/settings.json` declares `{"source": "npm:pi-subagents@0.76.0", "skills": [], "prompts": []}`
  and a `subagents.modelScope` block (pi-subagents config).
- `pi/extensions/subagent/config.json`, `pi/archive/` (old custom runtime) and
  `pi/agents.test.mjs` exist; `main` deleted all three.
- `pi/APPEND_SYSTEM.md` tells the model to use pi-subagents' `subagent` tool and
  `subagents_enable`.
- `pi/extensions/session-models/` is an older variant that mentions pi-subagents.
- The prompts are mixed. `fix-friction.md`, `start-day.md` and `review-local.md` already
  use pi-sub's API (`subagent({ role, model, task, cwd, label })`, `subagent_result`,
  `[pi-sub]` wake-ups). `orchestrate.md` and `watch-mrs.md` use pi-subagents' API
  (`agent:`, `action: "status" | "stop" | "resume" | "models"`, `workflow: true`). Those
  calls fail under pi-sub.
- `bin/pi-autoupdate` has a "chord guard" (installs `@earendil-works/chord` into pi's
  release tree). It exists only because pi-subagents runs background children as a node
  process with pi's host packages aliased in. pi-sub runs the `pi` binary itself
  (`run.mjs` spawns `$PI_SUB_PI_BIN ?? "pi"`), so it should not need chord. Confirm by
  reading `launch.ts` and `run.mjs` before deleting the guard.
- `pi/agents/` holds hand-copied team agents. On `main`, `pi/gen/pi_agents.py` generates
  them through `plink`, with the header pi-sub expects. `planner.md` and `researcher.md`
  were removed on `ubuntu` but are pi-sub roles named in `APPEND_SYSTEM.md`.
- Out of scope unless the user asks: `main` also has `pi/extensions/recap`,
  `session-summary`, `claude-hooks`, `pi/gen/` and `pi/billion-context.json`, which
  `ubuntu` lacks. `pi/gen` is the exception if you use it for the agents (step 5).

## Steps

1. **Fix pi-sub's process check for Linux first.** `pi/extensions/pi-sub/runtime.ts`,
   `defaultPs`, runs `ps -E -p <pid> -o command=`, and `ownsPid` looks for
   `PI_SUB_ID=<id>` in the output before anything signals the agent. On Ubuntu that
   command fails, so `ownsPid` is always false and `stop()` throws: neither `/agents` stop
   nor the `max_minutes` timeout can kill an agent. On Linux, read
   `/proc/<pid>/environ` (NUL-separated); keep `ps -E` on Darwin. `PsRunner` is
   injectable; add tests for both platforms. Make it one self-contained commit touching
   only `pi/extensions/pi-sub/`, so `main` can cherry-pick it. Tell the user its SHA.
2. Take from `origin/main` with `git checkout origin/main -- <path>`. Then diff each
   path against the previous `ubuntu` version and re-apply any Linux-specific edit:
   - `pi/extensions/pi-sub/`
   - `pi/extensions/session-models/`
   - `pi/APPEND_SYSTEM.md` (keep the `<daily_run_state>` paragraph; Ubuntu's `daily`
     extension injects it)
   - `pi/model-selection.md`
   - `pi/prompts/orchestrate.md`
   - `pi/prompts/watch-mrs.md`

   Then check every prompt and skill for a leftover pi-subagents call:
   `rg -n 'action: "|agent:|workflow: true|subagents_enable|pi-subagents' pi/`.
3. Delete the old runtime:
   - in `pi/settings.json`, the pi-subagents object and the `subagents.modelScope` block;
   - `pi/extensions/subagent/`, `pi/archive/` and `pi/agents.test.mjs`;
   - the chord guard in `bin/pi-autoupdate` and its tests (after the check above).
4. Roles. Every role pi-sub launches must exist in `~/.pi/agent/agents/` with pi-sub's
   header, including its `tools:` allowlist. Restore `planner.md` and `researcher.md`
   from `main`. Then pick one:
   - (a) add pi-sub's header to the hand-copied team agents in `pi/agents/`; or
   - (b) port `pi/gen/` and `main`'s agent step in `bin/plink`, with
     `CLAUDE_COMPONENTS_DIR=~/projects/ecfx/claude-components` in `~/.zshrc.local`. That
     replaces the `agents` symlink with a generated folder.

   (b) matches the Mac. Ask the user which one.
5. Keep what `ubuntu` does better: `settings.json` as a per-host seed in `bin/plink` and
   `install.sh`, with no `deviceId` or changelog keys committed. `main` should take this
   later, not in this task; its `plink` uses GNU `readlink -m`, which macOS lacks. Keep
   the Linux daily wake port and the other Ubuntu adaptations.
6. Update `pi/README.md` on `ubuntu`: its Delegation section and pinned-package paragraphs
   become `main`'s text, plus the Linux notes above (nvm PATH, `/proc` ownership check).

## Switch the machine over (after the user approves the branch)

1. With the branch in the live checkout, edit `~/.pi/agent/settings.json` the same way as
   the repo seed: drop pi-subagents and `subagents`.
2. `pi remove npm:pi-subagents@0.76.0` (check the exact form with `pi --help`), or
   `pi update --extensions` to reconcile. Then delete the stale `~/.pi/agent/pi-subagents/`
   state folder. Never have both runtimes loaded in one session.
3. Start a fresh pi session.

## Verify

- From `zsh -ic` (Node 24): `node --test *.test.ts` in `pi/extensions/pi-sub` and
  `pi/extensions/session-models`, plus `bin/plink.test.sh` and `bin/pi-autoupdate.test.sh`.
- `bin/pi-contract` against the installed pi 1.5.0.
- In a real session:
  - `pi list` shows no pi-subagents;
  - the model has `subagent`, `subagent_result`, `subagent_stop`, `subagent_handoff`,
    `subagent_adopt`, and no `acp_delegate*`;
  - launch a child, close the window, reopen: one `[pi-sub]` wake-up;
  - stop a child from `/agents`. This proves step 1: before the fix it fails with
    `pid … is not agent …; not signalling`;
  - suspend the laptop mid-run and resume: the child is not killed for the time it slept
    (a sweep gap over 60 s counts as sleep).

## Docs and the user's lines

- Wiki pages: `~/wiki/tools/pi.md` and `~/wiki/work/system/pi-mirroring.md`. Their
  `covers:` lines include `pi/settings.json`, `bin/pi-autoupdate*` and
  `pi/extensions/pi-sub/*`. The commit hook (`docs-check`) stops a commit that touches
  those paths without a page edit, unless the message has `Docs: none` or
  `Docs: internal`. Off trunk, a `- \`dotfiles:<branch>\` …` line under the page's
  `## Unfinished` also satisfies it.
- `pi-mirroring.md` has two lines about the chord guard: "Chord heal (2026-11-02)" in
  Moving parts, and the pitfall "Background subagent children fail on a pi 1.x host
  without chord". They came through an autosync from this laptop (`7bfec0e`) with no
  `Agent-edit:` trailer, so they count as the user's lines. Do not rewrite them: ask the
  user whether to remove them once the guard is gone.
- Commit wiki edits with `wiki-commit --by <claude|pi> --session <id> -m … -- <paths>`.
