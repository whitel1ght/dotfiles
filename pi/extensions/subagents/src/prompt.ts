import { describeRoster, type Roster } from "./roster.ts";

export function spawnDescription(roster: Roster): string {
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
    "",
    `Set \`model\` only to start further down a type's list, e.g. after a subagent's answer was poor.${local}`,
  ].join("\n");
}

export const SPAWN_SNIPPET = "agent_spawn: delegate a task to a subagent";

export const SPAWN_GUIDELINES = [
  "Use agent_spawn for self-contained work that does not need this conversation: searching a codebase, a well-specified change, a review, summarising text. Run independent ones in parallel.",
  "Choose agent_spawn's task type carefully; it decides the subagent's tools and models. Leave `model` out unless a subagent already did poorly.",
  "Treat a subagent's result as a colleague's report: check anything you will act on.",
];

export const LIST_DESCRIPTION = "List subagents with their status, task type, model, runtime, fallbacks, tool calls and cost.";

export const OUTPUT_DESCRIPTION =
  "Show a subagent's result if it has finished, or its recent activity if it is still running, and which models it tried. Does not wait.";

export const WAIT_DESCRIPTION =
  "Block until the given subagents (default: all running ones) finish, then return their results. " +
  "Use it only when you cannot continue without them; otherwise end your turn and you will be woken.";

export const STOP_DESCRIPTION = "Stop a running subagent and everything it started. It does not fall back to another model.";
