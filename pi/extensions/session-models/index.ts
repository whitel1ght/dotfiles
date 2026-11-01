import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function sessionModels(pi: ExtensionAPI) {
  pi.on("context_with_system", (event, ctx) => {
    const first = event.messages[0];
    if (first?.role !== "system") {
      throw new Error("Session model injection requires a leading system message");
    }
    const fullId = (model: { provider: string; id: string }) => `${model.provider}/${model.id}`;
    const available = new Set(ctx.modelRegistry.getAvailable().map(fullId));
    // Match pi-subagents modelScope.allow=["scoped"] when Pi has no scope.
    const selected = ctx.scopedModels.length
      ? ctx.scopedModels.map(({ model }) => model)
      : ctx.model ? [ctx.model] : [];
    const ids = [...new Set(selected.map(fullId))].filter((id) => available.has(id)).sort();
    const instructions = ids.length
      ? `Choose subagent models only from this live session list. Pass an exact provider/id explicitly.\n${ids.map((id) => `- ${id}`).join("\n")}`
      : "No selected models are currently available. Do not launch subagents; ask the user to repair the session model pool.";
    return {
      messages: [
        {
          ...first,
          sections: {
            ...first.sections,
            subagent_models: `<subagent_models>\n${instructions}\nThe broader registry returned by upstream discovery is not permission to use unlisted models.\n</subagent_models>`,
          },
        },
        ...event.messages.slice(1),
      ],
    };
  });
}
