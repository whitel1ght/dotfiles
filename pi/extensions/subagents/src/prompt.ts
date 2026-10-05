import { describeRoster, type Roster } from "./roster.ts";

export const MODEL_GUIDE_PATH = "~/.pi/agent/subagent-model-guide.md";

export function spawnDescription(roster: Roster): string {
  const local = roster.localModel
    ? ` The local model ${roster.localModel} is free but much weaker and cannot use tools; it suits only a simple text task when the user wants it kept local.`
    : "";
  return [
    "Delegate a self-contained task to a subagent: a separate pi run with its own context and a tool set fixed by the task type.",
    "Returns at once with an id; you are woken with the result when it finishes, so keep working or end your turn instead of polling.",
    "The subagent sees only `task`, not this conversation: include every path, fact and constraint it needs, and say what to return.",
    "",
    "The task type fixes the tools and nothing else. `model` is required: you choose it, by your judgment of the task, from the models this session has enabled and can reach. Call agent_models for that live list, with notes on each model; its roles overlap, so more than one model can fit.",
    "The subagent runs on exactly that model, with no fallback. If it fails, stalls or does not answer, its completion notification and agent_output report the failure and nothing else is tried: decide whether to spawn again, on the same model or another from the list.",
    "",
    "Task types:",
    describeRoster(roster),
    "",
    `A model outside the list is refused.${local}`,
  ].join("\n");
}

export const SPAWN_SNIPPET = "agent_spawn: delegate a task to a subagent on a model you choose";

export const SPAWN_GUIDELINES = [
  "Use agent_spawn for self-contained work that does not need this conversation: searching a codebase, a well-specified change, a review, summarising text. Run independent ones in parallel.",
  "Choose agent_spawn's task type for the tools the subagent needs, and its `model` by your own judgment of the work: call agent_models to see the models this session may use. Their strengths overlap, so weigh the task's difficulty, risk and cost; there is no fixed ranking to follow.",
  "A subagent runs on the one model you give it, with no automatic fallback. When one fails or answers poorly, decide yourself whether to retry on the same model or another, and put what went wrong in the new brief.",
  "If an older workflow says to use automatic model selection, choose explicitly from agent_models instead; never omit model. The legacy agent_select_models user gate is not exposed by this extension.",
  `The dated catalogue notes behind agent_models are in ${MODEL_GUIDE_PATH}.`,
  "Treat a subagent's result as a colleague's report: check anything you will act on.",
];

// agent_select_models is registered hidden: the parent chooses models itself
// (see SPAWN_GUIDELINES), so these are not shown to it. They stay with the tool.
export const SELECT_MODELS_SNIPPET = "agent_select_models: let the user choose models for a named multi-agent flow";

export const SELECT_MODELS_DESCRIPTION =
  "Ask the user once to choose a model for each agent of a named multi-agent flow. Selects only; it starts no agents. " +
  "Give `flow` (a stable ID for this invocation, e.g. mr-review-multi-agent:5348) and one entry per planned agent: key, title, task type, your recommended model and why. " +
  "Returns a model per key to pass as agent_spawn's `model`, or `cancelled: true` when the user declined. Outside the interactive parent terminal (RPC, JSON, print, subagents) it fails with an error instead of choosing for the user, and the named flow stops.";

export const SELECT_MODELS_GUIDELINES = [
  "In a named multi-agent flow (a skill or workflow that runs several agents), plan the initial roster first, then call agent_select_models once for it with a stable `flow` ID for this invocation.",
  "After agent_select_models, reuse the chosen model for each known role as agent_spawn's `model`; choose models for later roles yourself (or repeat the same `flow` for them, which prompts nothing).",
  "If agent_select_models returns cancelled, stop the flow and start no agents.",
  "If agent_select_models fails because there is no interactive terminal, stop the named flow, start no agents and do not pretend the user chose. Outside a named flow, just spawn with automatic models.",
  `In agent_select_models recommendations, name a budget, balanced or premium model for each role by that tier's rule (see ${MODEL_GUIDE_PATH}) and say why in one sentence.`,
  "When superpowers:subagent-driven-development is about to execute a written plan, derive the expected implementer/reviewer roster from that plan and call agent_select_models once before the first worker. Apply the same one-gate rule to superpowers:dispatching-parallel-agents.",
  "superpowers:writing-plans and inline superpowers:executing-plans spawn no parallel agents, and ordinary superpowers:requesting-code-review is a one-off agent_spawn: none of them calls agent_select_models.",
  "Never call agent_select_models for an ordinary one-off agent_spawn; just spawn it.",
];

export const LIST_DESCRIPTION = "List subagents with their status, task type, model, runtime, fallbacks, tool calls and cost.";

export const OUTPUT_DESCRIPTION =
  "Show a subagent's result if it has finished, or its recent activity if it is still running, and which models it tried. Does not wait.";

export const WAIT_DESCRIPTION =
  "Block until the given subagents (default: all running ones) finish, then return their results. " +
  "Use it only when you cannot continue without them; otherwise end your turn and you will be woken.";

export const STOP_DESCRIPTION = "Stop a running subagent and everything it started. It does not fall back to another model.";

export const MODELS_DESCRIPTION =
  "List the models you may give a subagent right now: those this session has enabled (its scoped models; all authenticated models when none are scoped) that pi has credentials for, with catalogue notes. Read it fresh before choosing agent_spawn's `model`; it changes when the user changes the session's models.";
