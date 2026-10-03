# Interactive Subagent Model Selection Design

**Date:** 2026-10-03
**Status:** Approved

## Goal

Add one model-selection gate at the start of named multi-agent workflows. After the
main model has inspected the task and planned the initial roster, Pi presents every
planned agent in one screen, recommends a model for each agent, and lets the user
change those choices before any subagent starts.

The picker appears only once per workflow. Agents discovered later are assigned a
model automatically using the same task policy, balancing output quality against
speed and token cost. Every explicit or automatic choice retains ranked fallbacks
when the preferred model is unavailable.

The initial workflows include multi-agent review, orchestration, local expert
panels, ticket workflows, and applicable Superpowers planning and execution flows.
Ordinary single-agent spawns remain automatic and non-interactive.

## Requirements

- Show one coordinated picker for the complete initial roster.
- Delay the picker until the parent has done enough inexpensive preparation to
  select an accurate roster.
- Let the parent recommend a model per agent and explain the recommendation.
- Let the user override each recommendation before confirming the whole roster.
- Launch no agents if the picker is cancelled.
- Reuse the user's selection when an initially planned role is invoked again.
- Do not prompt for agents discovered after the initial selection gate.
- Automatically select later models from the task policy.
- Try the selected model first, then suitable ranked fallbacks.
- Include curated models from OpenAI, OpenCode Go, and Anthropic models accessed
  through Claude Bridge.
- Never use direct `anthropic/*` API-billed models.
- Make task rankings easy to reorder without editing generated documentation or
  TypeScript source.
- Preserve the existing model profiles and normal `agent_spawn` workflow.

## Configuration layout

Separate frequently edited model policy from runtime subagent settings:

```text
pi/subagents.json
    Runtime settings: task tools, timing, concurrency, and model profiles.

pi/subagent-models.json
    Hand-edited model catalog and ordered task rankings.

pi/subagent-model-guide.md
    Generated human-readable task and model tables.

pi/subagents-research.md
    Benchmark evidence, source links, exclusions, and ranking rationale.
```

`pi/subagent-models.json` is the single source of truth for model metadata,
evidence date, task/tier rationale, compatibility, and priority. Priority is
top-to-bottom in short JSON arrays so changing defaults and fallback order only
requires moving model lines:

```json
{
  "evidenceDate": "2026-10-03",
  "rankings": {
    "review": {
      "budget": [
        "opencode-go/qwen3.8-flash",
        "openai/gpt-5.4-mini",
        "claude-bridge/claude-haiku-4-5"
      ],
      "balanced": [
        "opencode-go/qwen3.8-max",
        "openai/gpt-5.4",
        "opencode-go/glm-5.3",
        "claude-bridge/claude-sonnet-5-5"
      ],
      "premium": [
        "claude-bridge/claude-opus-5-5",
        "openai/gpt-5.5-pro"
      ],
      "rationale": {
        "budget": "Fast, economical models suit bounded review passes.",
        "balanced": "Strong code analysis with resilient provider fallbacks.",
        "premium": "Use when ambiguity or failure cost justifies deeper reasoning."
      }
    }
  },
  "models": {
    "openai/gpt-5.4": {
      "label": "GPT-5.4",
      "provider": "OpenAI",
      "quality": "high",
      "speed": "medium",
      "cost": "medium",
      "bestFor": ["review", "reason"],
      "strengths": ["code analysis", "structured reasoning"]
    }
  }
}
```

Each task defines explicit `budget`, `balanced`, and `premium` arrays plus one
rationale per tier. This lets the parent choose a cost/quality tier without
inferring one from prose or model names; top-to-bottom order within the selected
tier determines preference. A model is compatible with a task exactly when it
appears in any of that task's three arrays; catalog `bestFor` and `avoidFor`
values remain descriptive. The existing “three open models followed by exactly
one Claude Bridge fallback” invariant applies to the balanced array only.

The exact curated OpenAI entries and cross-provider rankings must be researched
and availability-tested during implementation. They must not be inferred from
model names alone.

## Human-readable model guide

Generate `pi/subagent-model-guide.md` from `pi/subagent-models.json`. It contains:

1. A task-oriented table with balanced, budget/fast, and premium choices plus the
   reason each tier fits the task.
2. A model-oriented table with provider, quality, speed, cost tier, best uses,
   and tasks to avoid.
3. The evidence date and a link to `pi/subagents-research.md`.
4. A short explanation that Anthropic models are accessed through
   `claude-bridge/*`, not direct API billing.

The generated guide is descriptive, not independently editable. A generation
check prevents it from drifting from the JSON policy. `bin/plink` links the guide
and model policy into `~/.pi/agent/` so the extension and parent model can find
stable paths.

## Selection interface

Add a selection-only tool, tentatively named `agent_select_models`. It does not
spawn agents.

```ts
agent_select_models({
  flow: "mr-review-multi-agent:5348",
  agents: [
    {
      key: "security",
      title: "Security reviewer",
      type: "review",
      recommendedModel: "claude-bridge/claude-opus-5-5",
      recommendation:
        "High-impact security review benefits from premium reasoning."
    }
  ]
})
```

Each `key` is stable within the workflow and lets later rounds reuse the user's
choice for the same role. `flow` is a stable invocation ID, not only a workflow
name; this lets the extension cache a confirmed mapping and return it if the same
flow accidentally calls the tool twice without reopening the picker. The
extension validates task types, model identifiers, and compatibility before
rendering the picker. Custom picker UI is TUI-only; RPC, JSON, and print modes
fail clearly rather than pretending to select models.

The batch picker shows every planned agent, its current model, and a detail panel
containing:

- recommendation rationale;
- provider;
- quality, speed, and cost tiers;
- model strengths;
- whether the choice is recommended or overridden; and
- the effective fallback chain.

Controls:

```text
Up/Down       Move between agents
Left/Right    Move through compatible curated models
Enter         Confirm the complete roster
Escape        Cancel the flow before any agent starts
```

Cancellation is atomic. The tool returns a cancellation result and the workflow
stops without launching an agent.

On confirmation the tool returns a role-to-model mapping, for example:

```json
{
  "security": "claude-bridge/claude-opus-5-5",
  "production": "openai/gpt-5.3-codex",
  "micronaut": "opencode-go/glm-5.3"
}
```

## Workflow behavior

A participating skill follows this sequence:

1. Gather inexpensive task context in the main session.
2. Determine the complete initial agent roster.
3. Choose a recommended model for every role from the model policy.
4. Give a one-sentence reason for each recommendation.
5. Call `agent_select_models` once.
6. Stop if the user cancels.
7. Spawn the initial agents with the returned model choices.
8. Reuse a role's selected model if that planned role is invoked again.
9. Automatically choose a model for any new role discovered later.
10. Never open another picker during that workflow.

The parent prompt receives a concise form of the policy and follows these rules:

- use budget/fast models for bounded, low-risk tasks;
- use balanced models for normal implementation and review;
- use premium models when ambiguity, security, architecture, or failure cost
  warrants the additional expense;
- explain recommendations shown at the initial gate;
- choose silently for later agents; and
- preserve ranked availability fallbacks.

Current child subagents cannot delegate. If nested delegation is enabled later,
children inherit the automatic-selection policy but not the interactive picker.

## Spawning and fallback chains

`agent_spawn` remains the launch mechanism. Initial and repeated planned roles
pass the selected model explicitly. New later roles may pass a parent-selected
model or omit it to use the balanced default for their task type.

An explicit compatible choice changes the first attempt, not the set of
fallbacks. Compatibility means membership in any tier for that task. The
configured `localModel` remains outside the catalog and tier arrays; it keeps the
existing special case for tool-less tasks and is checked before curated-policy
compatibility. Named model profiles remain replacement chains and keep their
existing `@parent`, free-only, and local-model semantics. Build the normal chain
as:

```text
explicitly selected or automatically chosen model
-> balanced task ranking in configured order
-> configured Claude Bridge fallback
```

Remove duplicates while preserving order. This replaces the current suffix-only
behavior, where selecting a model midway through a ranking discards suitable
models above it.

At spawn time the existing model preflight checks each candidate. If a candidate
is unavailable or fails to start, proceed to the next candidate and report which
model actually started.

The picker can contain more agents than `maxRunning`. Existing workflows launch
large panels in waves while retaining the one confirmed selection mapping. This
design does not require a new scheduler.

## Initial workflow migration

Update these named flows where they establish an initial multi-agent roster:

- `pi/prompts/orchestrate.md`
- `pi/prompts/review-local.md`
- `pi/prompts/watch-mrs.md`
- `mr-review-multi-agent`
- `backend-panel`
- `frontend-panel`
- `python-panel`
- `handle-ticket`
- `fix-jira-bug`
- applicable Superpowers planning and agent-execution skills

Each workflow owns its specialist roster and task briefs. The shared subagent
extension owns model policy loading, validation, selection UI, and fallback
construction.

## Validation and failure handling

Reject configuration when:

- a ranking references a model missing from the catalog;
- a model identifier uses direct `anthropic/*`;
- a task has no balanced ranking;
- a balanced fallback chain lacks its required Claude Bridge endpoint;
- a selected model does not appear in any tier for that task; or
- duplicate or malformed role keys are submitted to the picker.

A configured model that is temporarily absent from Pi's available catalog is a
runtime availability failure, not necessarily a configuration parse failure. The
spawn preflight should continue through the fallback chain. A separate validation
or generation command reports unavailable catalog entries so policy maintenance
remains explicit.

In interactive TUI mode, named flows use the picker. If a named interactive flow
is invoked where UI selection is unavailable, fail clearly rather than silently
pretending the user approved the recommendations. Ordinary automatic
`agent_spawn` remains usable in non-interactive operation.

## Verification strategy

Add tests for:

- loading and validating `pi/subagent-models.json`;
- rejecting direct `anthropic/*` models;
- rejecting unknown ranked models and malformed policy;
- ranking order determining automatic defaults;
- reordering an array changing fallback order;
- explicit selections being attempted first;
- appending and deduplicating balanced fallbacks;
- preserving a final Claude Bridge fallback;
- picker confirmation returning every role selection;
- picker cancellation launching nothing;
- prompt text distinguishing one-time initial selection from later automatic
  selection;
- generated Markdown matching the committed guide;
- current model profiles and ordinary `agent_spawn` remaining compatible; and
- the migrated skills calling the selector once before their initial panel.

Run the extension's existing test suite plus the new focused tests. Manually run
at least one representative flow, preferably `orchestrate` or
`mr-review-multi-agent`, to verify the complete TUI interaction and fallback
reporting.

## Non-goals

- Prompting for every `agent_spawn` call.
- Showing every model returned by `pi --list-models`.
- Enabling direct Anthropic API billing.
- Adding nested delegation to child agents.
- Replacing existing specialist profiles or task tool restrictions.
- Building a new agent scheduler solely for panels larger than four agents.
