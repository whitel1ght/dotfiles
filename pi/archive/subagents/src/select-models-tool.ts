// The one-time model selector for a named multi-agent flow. It only chooses
// models; it never spawns an agent. Free of Pi's runtime so it can be tested.
import { ModelSelectionState, validateSelectionRequests, type AgentModelRequest, type AgentModelSelection } from "./selection.ts";
import { selectableModels, type ModelPolicy } from "./model-policy.ts";
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
  // The picker currently open per flow; overlapping calls wait on it instead of opening another.
  const inFlight = new Map<string, Promise<readonly AgentModelSelection[] | undefined>>();

  return async (params: SelectModelsParams, env: SelectorEnv): Promise<SelectModelsResult> => {
    const flow = params.flow.trim();
    if (!flow) throw new Error("model selection: flow must be a stable non-empty ID such as mr-review-multi-agent:5348");
    const requests = validateSelectionRequests(params.agents, roster, policy);

    // Without an interactive parent TUI nobody can approve a choice; never return one that looks approved.
    if (env.mode !== "tui" || !env.hasUI || env.isChild) {
      throw new Error("model selection needs the interactive terminal UI of the parent session; it is unavailable in RPC, JSON, print or subagent runs");
    }

    // Known roles keep their choice while it still fits the role's type; new or no-longer-compatible roles get their recommendation.
    const resolve = (): AgentModelSelection[] => {
      const known = confirmed.get(flow);
      return requests.map((r) => {
        const cached = known?.get(r.key);
        const keep = cached !== undefined && selectableModels(policy, r.type).some((m) => m.ref === cached);
        return { key: r.key, model: keep ? cached : r.recommendedModel };
      });
    };
    const result = (note: string): SelectModelsResult => {
      const selections = resolve();
      return { text: `${note}\n${mapping(selections)}`, details: { flow, cancelled: false, selections } };
    };
    const cancelled = (): SelectModelsResult => ({
      text: `The user cancelled model selection for flow ${flow}. Stop this flow: do not start any agents.`,
      details: { flow, cancelled: true, selections: [] },
    });

    if (confirmed.has(flow)) {
      return result(`Models for flow ${flow} were already chosen; pass each as agent_spawn's \`model\`:`);
    }

    let pending = inFlight.get(flow);
    if (!pending) {
      let available: ReadonlySet<string>;
      try {
        available = env.available();
      } catch (error) {
        throw new Error(`model selection: cannot determine available models (${error instanceof Error ? error.message : error})`);
      }
      const state = new ModelSelectionState(requests, roster, policy, available);
      const opened = env.openPicker(state, available).then((selections) => {
        if (selections) confirmed.set(flow, new Map(selections.map((s) => [s.key, s.model])));
        return selections;
      });
      pending = opened;
      inFlight.set(flow, opened);
      const clear = () => {
        if (inFlight.get(flow) === opened) inFlight.delete(flow);
      };
      opened.then(clear, clear);
    }
    const selections = await pending;
    return selections ? result(`The user chose these models for flow ${flow}; pass each as agent_spawn's \`model\`:`) : cancelled();
  };
}
