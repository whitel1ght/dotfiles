// The one-time model selector for a named multi-agent flow. It only chooses
// models; it never spawns an agent. Free of Pi's runtime so it can be tested.
import { ModelSelectionState, validateSelectionRequests, type AgentModelRequest, type AgentModelSelection } from "./selection.ts";
import type { ModelPolicy } from "./model-policy.ts";
import type { Roster } from "./roster.ts";

export interface SelectorEnv {
  readonly mode: string;
  readonly hasUI: boolean;
  // A subagent process; it may never open the picker.
  readonly isChild: boolean;
  // The models that can run now. Throws when they cannot be determined.
  readonly available: () => ReadonlySet<string>;
  // Resolves to the confirmed choices, or undefined when the user pressed Escape.
  readonly openPicker: (
    state: ModelSelectionState,
    available: ReadonlySet<string>,
  ) => Promise<readonly AgentModelSelection[] | undefined>;
}

export interface SelectModelsParams {
  readonly flow: string;
  readonly agents: readonly AgentModelRequest[];
}

export interface SelectModelsResult {
  readonly text: string;
  readonly details: { flow: string; cancelled: boolean; selections: readonly AgentModelSelection[] };
}

// Registry entries become the "provider/id" strings the policy uses.
export function registryModels(entries: readonly { provider: string; id: string }[]): ReadonlySet<string> {
  return new Set(entries.map((e) => `${e.provider}/${e.id}`));
}

const mapping = (selections: readonly AgentModelSelection[]) => selections.map((s) => `${s.key}: ${s.model}`).join("\n");

export function createModelSelector(roster: Roster, policy: ModelPolicy) {
  // Confirmed choices per stable flow ID, for this extension session.
  const confirmed = new Map<string, Map<string, string>>();

  return async (params: SelectModelsParams, env: SelectorEnv): Promise<SelectModelsResult> => {
    const flow = params.flow.trim();
    if (!flow) throw new Error("model selection: flow must be a stable non-empty ID such as mr-review-multi-agent:5348");
    const requests = validateSelectionRequests(params.agents, roster, policy);
    const result = (selections: readonly AgentModelSelection[], note: string): SelectModelsResult => ({
      text: `${note}\n${mapping(selections)}`,
      details: { flow, cancelled: false, selections },
    });

    const known = confirmed.get(flow);
    if (known) {
      // Known roles keep their choice; roles added later get their recommendation.
      const selections = requests.map((r) => ({ key: r.key, model: known.get(r.key) ?? r.recommendedModel }));
      return result(selections, `Models for flow ${flow} were already chosen; pass each as agent_spawn's \`model\`:`);
    }

    if (env.mode !== "tui" || !env.hasUI || env.isChild) {
      const selections = requests.map((r) => ({ key: r.key, model: r.recommendedModel }));
      return result(selections, `No interactive picker here; using the recommended models. Pass each as agent_spawn's \`model\`:`);
    }

    let available: ReadonlySet<string>;
    try {
      available = env.available();
    } catch (error) {
      throw new Error(`model selection: cannot determine available models (${error instanceof Error ? error.message : error})`);
    }
    const state = new ModelSelectionState(requests, roster, policy, available);
    const selections = await env.openPicker(state, available);
    if (!selections) {
      return {
        text: `The user cancelled model selection for flow ${flow}. Stop this flow: do not start any agents.`,
        details: { flow, cancelled: true, selections: [] },
      };
    }
    confirmed.set(flow, new Map(selections.map((s) => [s.key, s.model])));
    return result(selections, `The user chose these models for flow ${flow}; pass each as agent_spawn's \`model\`:`);
  };
}
