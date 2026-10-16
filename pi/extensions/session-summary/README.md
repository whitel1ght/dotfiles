# session-summary

When a pi session ends, writes a short summary to `~/wiki/work/sessions/<date>/<session-id>.md`, so random and personal sessions leave a trace without `/end-day`.

- **When:** on quit and on `/new`, `/resume` and `/fork` (the old session ends). Not on `/reload`.
- **Skipped:** subagents (`PI_SUBAGENT`), sessions without a file (`--no-session`), sessions with fewer than 2 user messages, and the session that owns today's `/run-day` (the `session:` line of `~/.local/state/run-day/<today>.md`); its work already lands in the diary and `/end-day`.
- **Model:** the session model, given the same ≤30K-character digest as `/recap` (`../recap/digest.ts`), capped at 800 output tokens and 20s. Quitting waits for it; any error is swallowed.
- **File:** frontmatter `type: session`, `date`, `session`, `cwd`, `model`, `file`, then `# title`, **Did**, **Decisions**, **Open**. One file per session: resuming a session on a later day moves its file to that day.

These are an inbox. Nothing edits the diary or project files; fold what matters into `work/projects/<p>/` by hand or during `/end-day`.

Env overrides (tests and `bin/pi-contract`): `WIKI_DIR`, `RUN_DAY_STATE_DIR`.

Tests: `node --test *.test.ts`.
