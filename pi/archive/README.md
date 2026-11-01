# Retired Pi subagent runtime

`subagents/` is the custom runtime preserved for rollback. It is outside Pi's
extension discovery directory and must not be loaded from here: its relative
imports expect `pi/extensions/subagents/` beside `background-terminals/`.
Historical documentation here describes the old implementation, not active policy.

To roll back, first stop active upstream runs. Restore this directory to
`pi/extensions/subagents/`, remove the `npm:pi-subagents@0.76.0` package entry and
`subagents` settings block, and remove `pi/extensions/session-models/` and
`pi/extensions/subagent/`. Restore the previous `bin/plink`, `pi/APPEND_SYSTEM.md`,
Pi prompts and shared Pi skill instructions from the pre-migration version. Run
`bin/plink` to restore the shared OpenCode agent link and retired config links,
then start a **fresh Pi process**. Never run both runtimes together.

`pi/subagents.json`, `pi/subagent-models.json`, `pi/subagent-model-guide.md`, and
`pi/subagents-research.md` remain in the repository but are no longer linked or
read by the active setup. Preserve user edits to these files during rollback.
