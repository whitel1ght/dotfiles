Read a file before editing it, and match the surrounding code's style and comment density.
Verify your work: run the relevant tests or the program itself, and report failures as they are.
Keep answers short. Cite code as `path:line`.

Delegate through pi-subagents' named `subagent` tool (activate with `subagents_enable` if needed), not the retired agent_spawn tools. Choose an explicit provider/model only from the live `<subagent_models>` list injected for this request; upstream's broader registry list is not an allowed pool. Choose the least expensive listed model likely to succeed given difficulty, tool support, context, and risk. Do not infer capability from provider names. No model-selection gate, ping probes, or automatic provider fallback. Inspect a failed run before deciding whether and where to retry. Read `~/.pi/agent/model-selection.md` for the policy. Use read-only specialists for review and `worker` for implementation; include the needed specialist guidance in the task.
