# Subagent model selection

The parent chooses an explicit exact `provider/model` on each `subagent` launch.
The `session-models` extension injects the live **selected ∩ available** list before
every model request. Choose only from that list, not from the broader registry
shown by upstream `subagent({action: "models"})`. Available means configured with
credentials according to Pi, not health-tested. If no IDs are listed, do not
launch; ask the user to repair the pool. An empty session scope narrows to the
available parent model, matching upstream's `allow: ["scoped"]` behavior.

Choose the least expensive model likely to succeed:
- Simple extraction, supplied-text transformations, and bounded reading: a cheap
  model that supports the required tools and context.
- Implementation and debugging: a capable coding model; weigh test complexity,
  repository size, and ambiguity rather than provider name alone.
- Security-sensitive review, architecture, and subtle root-cause analysis: stronger
  reasoning and sufficient context. Do not save cost by guessing about capability.

There are no fixed provider tiers. Model names are not evidence of performance.
Use known capabilities and user preferences; if these are unknown, choose a
capable listed model conservatively. DeepSeek/LongCat are options only if actually
listed; this migration does not enable extra providers. Tool-incapable models are
suitable only for supplied-text work with the `text` agent.

Named agents define expertise and tools, not model routing. One launch uses one
chosen model. If it fails, inspect the error and make an explicit informed retry
(or report the failure); do not cycle through providers or run ping probes. There
is no model-selection questionnaire or hidden fallback ladder. Strict upstream
scope enforcement remains a safety net, not a discovery mechanism.

Use `subagents_enable` if the upstream launcher is not yet active. See upstream
`subagent` tool help for launch/status/stop fields. Specialist agents are
read-only by default; use `worker` with the relevant specialist guidance for
implementation. Shell access is not a filesystem sandbox. No shared child
extension allowlist is configured; agents use upstream's normal extension
discovery unless they declare their own extension policy. Verify that required
tool/provider extensions are available before relying on them.
