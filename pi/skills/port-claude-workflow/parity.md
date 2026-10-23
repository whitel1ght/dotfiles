# Claude Code → pi parity

Every Claude Code surface `scripts/inventory` lists that has no pi file of the same name,
with where it lives in pi or why it is not ported. One line each, in the form
``- `<kind>:<name>` — <reason>``; the inventory reads the backticked key.

## Adapted skills

pi copies that differ from their Claude source on purpose. The digest is
`scripts/skill-digest <claude skill dir>` at the time of the adaptation; when Claude's source
changes, the digest stops matching and the skill shows as `stale` until the update is ported
and the digest renewed.

- `adapted:commit-msg` 78de777149b7 — Claude's `` !`cmd` `` context injection becomes "run `cmd`".
- `adapted:shipit` 03029dcb423c — as commit-msg.
- `adapted:mr-description` 67df83382616 — as commit-msg; `${CLAUDE_PLUGIN_ROOT}` becomes the claude-components checkout path; Atlassian MCP tool named generically.
- `adapted:mr-review-multi-agent` faa9b7d41e59 — Claude agents (`shared:…`, `general-purpose`, `Task`, `SendMessage`) become pi-sub roles and `subagent`; model choice from `<subagent_models>`.
- `adapted:jira-write` 0b9ddbc9e4c0 — script called in place from the dotfiles; Ready for QA rule (wiki decision 0005); scratch path.

## Hooks

- `hook:superpowers/SessionStart[startup|clear|compact]` — the superpowers pi package (`git:github.com/obra/superpowers`) ships its own `.pi/extensions/superpowers.ts`.
- `hook:shared/PreToolUse[Bash]` — `pi/extensions/claude-hooks` runs it on pi's `bash` tool.
- `hook:cache-tax/module:register.ts` — keeps Anthropic's prompt cache warm in Claude Code; Claude-only (pi's providers and caching differ).
- `hook:daily/SessionStart[compact|resume]` — `pi/extensions/daily` injects run state on every turn (`before_agent_start`).
- `hook:daily/module:register.tsx` — `pi/extensions/daily`: diary tick guard (`tool_call`), needs-you announcements; plan view is `day-plan`; agents are pi-sub's footer and `/agents`.
- `hook:user/WorktreeCreate` — Claude's own worktree tool only; pi has none, and prompts create worktrees with `wt add`.
- `hook:user/WorktreeRemove` — as WorktreeCreate; `wt rm` / `/clean-worktrees`.
- `hook:user/SessionStart` — herdr's pi integration (`pi/extensions/herdr-agent-state.ts`, managed by herdr).

## claude.ai synced skills

These come from the claude.ai account, not the dotfiles, and drive claude.ai's own tools
(artifacts, Drive, computer use). pi has its own equivalents or no use for them.

- `skill:docx` — claude.ai document tooling; not used in the pi workflow.
- `skill:pdf` — as docx.
- `skill:pptx` — as docx.
- `skill:xlsx` — as docx.
- `skill:docs` — claude.ai editable docs; not used in the pi workflow.
- `skill:google-workspace` — claude.ai Google connector; pi has no such connector.
- `skill:import-memory` — imports into Claude's account memory; pi's memory is `~/wiki`.
- `skill:morning` — claude.ai morning-brief artifact; the pi day starts with `/start-day`.
- `skill:skill-creator` — the `writing-skills` superpowers skill covers it in pi.
- `skill:built-in-browser` — claude.ai's browser; pi uses `playwright-browser` / `playwright-skill`.
- `skill:chrome-browser` — as built-in-browser.
- `skill:computer-use` — claude.ai computer use; no pi equivalent wanted.
- `skill:deep-research` — claude.ai research mode; pi has `fusion_research` and the web tools.
