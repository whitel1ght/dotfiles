import { MODEL_TIERS, type ModelPolicy } from "./model-policy.ts";
import { describeRoster, type Roster } from "./roster.ts";

export const MODEL_GUIDE_PATH = "~/.pi/agent/subagent-model-guide.md";

export function spawnDescription(roster: Roster, policy: ModelPolicy): string {
  const local = roster.localModel
    ? ` The local model ${roster.localModel} is free but much weaker; name it only for a simple text task when the user wants it kept local.`
    : "";
  return [
    "Delegate a self-contained task to a subagent: a separate pi run with its own context and a tool set fixed by the task type.",
    "Returns at once with an id; you are woken with the result when it finishes, so keep working or end your turn instead of polling.",
    "The subagent sees only `task`, not this conversation: include every path, fact and constraint it needs, and say what to return.",
    "",
    "Pick the task type; the model is chosen for you. Each type's models are ranked by benchmarks for that kind of work, and each is pinged before it gets the task: one that does not answer, fails, or goes silent is replaced by the next, ending with Claude.",
    "",
    "Task types:",
    describeRoster(roster),
    describeModelProfiles(roster),
    "",
    describeModelTiers(roster, policy),
    "",
    `Set \`model\` to try a compatible curated model first (the rest of the type's list stays as fallback), e.g. one the user chose with agent_select_models, or after a subagent's answer was poor.${local}`,
  ].join("\n");
}

// The named model profiles, as the model reads them in the spawn tool.
export function describeModelProfiles(roster: Roster): string {
  const profiles = [...roster.modelProfiles.values()];
  if (!profiles.length) return "";
  const lines = profiles.map((p) =>
    p.freeOnly ? `- ${p.name}: only models that cost nothing (the subscription fallbacks)` : `- ${p.name}: ${p.models!.join(" → ")}`,
  );
  return ["", "Model profiles, to replace a type's list with `modelProfile`:", ...lines].join("\n");
}

// Every task type's models per cost tier, so a recommendation or `model` can
// name any of them; the guide carries the dated rationale.
export function describeModelTiers(roster: Roster, policy: ModelPolicy): string {
  const lines = [...roster.types.keys()].flatMap((name) => {
    const ranking = policy.rankings.get(name)!;
    return MODEL_TIERS.map((tier) => `- ${name} ${tier}: ${ranking[tier].join(" → ")}`);
  });
  return [`Model tiers per type, for \`model\` and agent_select_models recommendations (rationale and dates: ${MODEL_GUIDE_PATH}):`, ...lines].join("\n");
}

export const SPAWN_SNIPPET = "agent_spawn: delegate a task to a subagent";

export const SPAWN_GUIDELINES = [
  "Use agent_spawn for self-contained work that does not need this conversation: searching a codebase, a well-specified change, a review, summarising text. Run independent ones in parallel.",
  "Choose agent_spawn's task type carefully; it decides the subagent's tools and models. Set `model` only to a model the user chose via agent_select_models, or after a subagent already did poorly.",
  "Use agent_spawn's `modelProfile` to run a subagent on your own model (`current`), on free models (`free`), or locally (`local`) instead of its type's ranking.",
  `Model tiers: budget for bounded, low-risk work, balanced for normal work (the default list), premium for ambiguity, security or architecture. Each type's models per tier are in agent_spawn's description; the dated guide is ${MODEL_GUIDE_PATH}.`,
  "Treat a subagent's result as a colleague's report: check anything you will act on.",
];

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
