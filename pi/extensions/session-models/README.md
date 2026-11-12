# Session model list

At the start of every turn, inject the intersection of `ctx.scopedModels` and
`ctx.modelRegistry.getAvailable()` as exact provider/model IDs in a named system
section (`<subagent_models>`). No provider calls, model choice, retries, or subagent
execution. Changing `/scoped-models` takes effect on the next turn.

An empty scope permits only the available parent model, matching pi-subagents'
`modelScope.allow: ["scoped"]` behavior. No usable models means no delegation.
Availability reflects Pi's registry/auth configuration, not a health check.
Upstream remains responsible for strict launch-time scope enforcement.

Uses `before_agent_start` and its mutable `systemPromptOptions.sections`. The
`context_with_system` route this extension originally used stopped reaching the
provider request somewhere between Pi 1.0.3 and 1.2.0 — measured on 1.2.0, a section
added to the system message there is dropped when Pi rebuilds the system head.

Because that break was silent, the extension now checks itself: on the first provider
request of a session it looks for its own wording in the outgoing payload and, if it is
missing, prints an error and raises an `error` notification. A future Pi update that
drops the section again therefore fails loudly instead of quietly leaving every subagent
launch unguided. The check keys on the section text, not on the `<subagent_models>` tag,
because `pi/APPEND_SYSTEM.md` mentions that tag in prose and would fake a pass.

Verified against Pi 1.2.0. Run `npm test` in this directory.
