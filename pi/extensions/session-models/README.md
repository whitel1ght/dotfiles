# Session model list

Before each parent model request, inject the intersection of `ctx.scopedModels`
and `ctx.modelRegistry.getAvailable()` as exact provider/model IDs in a named
system section. No provider calls, model choice, retries, or subagent execution.
Changing `/scoped-models` takes effect on the next request.

An empty scope permits only the available parent model, matching pi-subagents'
`modelScope.allow: ["scoped"]` behavior. No usable models means no delegation.
Availability reflects Pi's registry/auth configuration, not a health check.
Upstream remains responsible for strict launch-time scope enforcement.

Requires Pi's `context_with_system` event and structured system sections (tested
against 1.0.3). Run `npm test` in this directory.
