import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type ModelId = { provider: string; id: string };

export type ModelCtx = {
  scopedModels: readonly { model: ModelId }[];
  model: ModelId | undefined;
  modelRegistry: { getAvailable: () => ModelId[] };
};

/** Phrases that exist only in the injected section. The payload check looks for these and not
 * for the `<subagent_models>` tag: pi/APPEND_SYSTEM.md mentions that tag in prose, so the tag
 * alone would fake a pass. */
export const LANDED = [
  "Choose subagent models only from this live session list",
  "Do not launch subagents",
];

/** The model ids subagents may use: the scoped (or current) models that are still available. */
export function liveModels(ctx: ModelCtx): string[] {
  const fullId = (model: ModelId) => `${model.provider}/${model.id}`;
  const available = new Set(ctx.modelRegistry.getAvailable().map(fullId));
  // Match pi-subagents modelScope.allow=["scoped"] when Pi has no scope.
  const selected = ctx.scopedModels.length
    ? ctx.scopedModels.map(({ model }) => model)
    : ctx.model
      ? [ctx.model]
      : [];
  return [...new Set(selected.map(fullId))].filter((id) => available.has(id)).sort();
}

export function sectionText(ctx: ModelCtx): string {
  const ids = liveModels(ctx);
  const instructions = ids.length
    ? `Choose subagent models only from this live session list. Pass an exact provider/id explicitly.\n${ids.map((id) => `- ${id}`).join("\n")}`
    : "No selected models are currently available. Do not launch subagents; ask the user to repair the session model pool.";
  return `${instructions}\nThe broader registry returned by upstream discovery is not permission to use unlisted models.`;
}

export default function sessionModels(pi: ExtensionAPI) {
  // before_agent_start, not context_with_system: a section added to the system message there
  // no longer reaches the provider request in Pi 1.2.0 (measured); mutating
  // systemPromptOptions.sections does, and Pi wraps it in <subagent_models> itself.
  pi.on("before_agent_start", (event, ctx) => {
    event.systemPromptOptions.sections.subagent_models = sectionText(ctx);
  });

  // Pi has dropped an injected system section silently before (context_with_system, 1.2.0),
  // which left every subagent launch unguided and nobody noticed for days. So confirm on the
  // first request of each session that the list really is in the payload, and shout if not.
  let checked = false;
  pi.on("before_provider_request", (event, ctx) => {
    if (checked) return;
    checked = true;
    try {
      const payload = JSON.stringify(event.payload ?? "");
      if (LANDED.some((mark) => payload.includes(mark))) return;
      const message =
        "session-models: the model list is NOT in the provider request — subagent model selection is unguided. Pi's system-prompt hooks probably changed; re-check pi/extensions/session-models.";
      console.error(message);
      ctx.ui?.notify(message, "error");
    } catch {
      // a failing self-check must never fail a request
    }
  });
}
