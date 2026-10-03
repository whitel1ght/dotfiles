// Model selection for a batch of subagents: the requests a caller makes, their
// validation against the roster and policy, and the state the picker edits.
// Kept free of Pi's TUI so it can be tested on its own.
import { selectableModels, type ModelMetadata, type ModelPolicy } from "./model-policy.ts";
import type { Roster } from "./roster.ts";

export interface AgentModelRequest {
  readonly key: string;
  readonly title: string;
  readonly type: string;
  readonly recommendedModel: string;
  readonly recommendation: string;
}

export interface AgentModelSelection {
  readonly key: string;
  readonly model: string;
}

export interface ModelSelectionDetails {
  readonly index: number;
  readonly key: string;
  readonly title: string;
  readonly type: string;
  readonly model: string;
  readonly metadata: ModelMetadata;
  readonly recommendedModel: string;
  readonly recommendation: string;
  readonly overridden: boolean;
  readonly available: boolean;
  // The chosen model first, then the type's own ranking in order.
  readonly fallbackChain: readonly string[];
}

export interface VisibleWindow {
  readonly start: number;
  readonly end: number;
}

export function validateSelectionRequests(
  requests: readonly AgentModelRequest[],
  roster: Roster,
  policy: ModelPolicy,
): readonly AgentModelRequest[] {
  if (!requests.length) throw new Error("model selection needs at least one agent");
  const keys = new Set<string>();
  for (const request of requests) {
    if (!request.key.trim()) throw new Error("model selection: key must not be blank");
    if (keys.has(request.key)) throw new Error(`model selection: duplicate key "${request.key}"`);
    keys.add(request.key);
    const where = `model selection "${request.key}"`;
    if (!roster.types.has(request.type)) throw new Error(`${where}: unknown task type "${request.type}"`);
    if (!request.recommendation.trim()) throw new Error(`${where}: recommendation must not be blank`);
    const compatible = selectableModels(policy, request.type).some((m) => m.ref === request.recommendedModel);
    if (!compatible) throw new Error(`${where}: ${request.recommendedModel} is not compatible with ${request.type}`);
  }
  return requests;
}

// The rows to show: `capacity` of them, with the active row inside.
export function visibleWindow(total: number, active: number, capacity: number): VisibleWindow {
  const size = Math.min(total, Math.max(1, capacity));
  const start = Math.max(0, Math.min(active - Math.floor(size / 2), total - size));
  return { start, end: start + size };
}

export class ModelSelectionState {
  private readonly requests: readonly AgentModelRequest[];
  private readonly roster: Roster;
  private readonly policy: ModelPolicy;
  private readonly available: ReadonlySet<string> | undefined;
  private readonly choices: string[];
  private active = 0;

  // `available`, when given, lists the models that can run now; any other
  // model is shown as unavailable and blocks confirmation while it is chosen.
  constructor(requests: readonly AgentModelRequest[], roster: Roster, policy: ModelPolicy, available?: ReadonlySet<string>) {
    this.requests = validateSelectionRequests(requests, roster, policy);
    this.roster = roster;
    this.policy = policy;
    this.available = available;
    this.choices = requests.map((r) => r.recommendedModel);
  }

  moveAgent(delta: number): void {
    this.active = wrap(this.active + delta, this.requests.length);
  }

  moveModel(delta: number): void {
    const models = this.compatible(this.active);
    const at = models.findIndex((m) => m.ref === this.choices[this.active]);
    this.choices[this.active] = models[wrap(at + delta, models.length)].ref;
  }

  window(capacity: number): VisibleWindow {
    return visibleWindow(this.requests.length, this.active, capacity);
  }

  size(): number {
    return this.requests.length;
  }

  detailsAt(index: number): ModelSelectionDetails {
    const request = this.requests[index];
    const model = this.choices[index];
    const ranking = this.roster.types.get(request.type)!.models;
    return {
      index,
      key: request.key,
      title: request.title,
      type: request.type,
      model,
      metadata: this.policy.models.get(model)!,
      recommendedModel: request.recommendedModel,
      recommendation: request.recommendation,
      overridden: model !== request.recommendedModel,
      available: this.available?.has(model) ?? true,
      fallbackChain: [model, ...ranking.filter((m) => m !== model)],
    };
  }

  currentDetails(): ModelSelectionDetails {
    return this.detailsAt(this.active);
  }

  canConfirm(): boolean {
    return this.choices.every((_, i) => this.detailsAt(i).available);
  }

  result(): readonly AgentModelSelection[] {
    const blocked = this.requests.find((_, i) => !this.detailsAt(i).available);
    if (blocked) throw new Error(`model selection "${blocked.key}": ${this.choices[this.requests.indexOf(blocked)]} is not available`);
    return this.requests.map((r, i) => ({ key: r.key, model: this.choices[i] }));
  }

  private compatible(index: number): readonly ModelMetadata[] {
    return selectableModels(this.policy, this.requests[index].type);
  }
}

function wrap(value: number, length: number): number {
  return ((value % length) + length) % length;
}
