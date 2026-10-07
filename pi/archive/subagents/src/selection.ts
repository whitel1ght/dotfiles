// Model selection for a batch of subagents: the requests a caller makes, their
// validation against the roster and policy, and the state the picker edits.
// Kept free of Pi's TUI so it can be tested on its own.
import { selectableModels, type ModelMetadata, type ModelPolicy } from "./model-policy.ts";
import { chainFor, type Roster } from "./roster.ts";

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
  // The chosen model first, then the type's own ranking in order (`chainFor`).
  readonly fallbackChain: readonly string[];
  // Members of the chain that cannot run now.
  readonly unavailableFallbacks: readonly string[];
}

export interface BlockedRole {
  readonly index: number;
  readonly key: string;
  readonly title: string;
  readonly model: string;
  // Whether another compatible model for this role can run now.
  readonly hasAlternative: boolean;
}

export interface LayoutInput {
  readonly rows: number;
  readonly total: number;
  readonly active: number;
  // Wrapped detail lines wanted for the active role.
  readonly detailLines: number;
  readonly notice: boolean;
}

export interface Layout {
  readonly window: VisibleWindow;
  // Whether the "↑ n more" / "↓ n more" lines are shown.
  readonly indicators: boolean;
  // How many of the wanted detail lines are shown, from the first.
  readonly detailLines: number;
  readonly notice: boolean;
  // full: title, three blank lines and the key hint; footer: key hint only.
  readonly chrome: "full" | "footer" | "none";
  readonly lineCount: number;
}

const FULL_CHROME_LINES = 5;
const MIN_ROLE_ROWS = 3;

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

// Splits `rows` terminal lines between the parts of the picker. The active
// role row and the blocking notice come first; chrome, then details, then more
// role rows, are given up as the terminal shrinks. The result never exceeds
// `rows` (at least one line is always used for the active role).
export function planLayout(input: LayoutInput): Layout {
  const rows = Math.max(1, Math.floor(input.rows));
  const notice = input.notice && rows >= 2;
  const afterNotice = rows - (notice ? 1 : 0);
  const chrome = afterNotice >= FULL_CHROME_LINES + 1 ? "full" : afterNotice >= 2 ? "footer" : "none";
  const remaining = afterNotice - (chrome === "full" ? FULL_CHROME_LINES : chrome === "footer" ? 1 : 0);
  const detailLines = Math.min(Math.max(0, input.detailLines), Math.max(0, remaining - Math.min(input.total, MIN_ROLE_ROWS)));
  const roleSpace = remaining - detailLines;

  let window = visibleWindow(input.total, input.active, 1);
  let indicators = false;
  for (let capacity = Math.min(input.total, roleSpace); capacity >= 1; capacity--) {
    const w = visibleWindow(input.total, input.active, capacity);
    const marks = (w.start > 0 ? 1 : 0) + (w.end < input.total ? 1 : 0);
    if (capacity + marks <= roleSpace) {
      window = w;
      indicators = marks > 0;
      break;
    }
  }
  const marks = indicators ? (window.start > 0 ? 1 : 0) + (window.end < input.total ? 1 : 0) : 0;
  const lineCount = (notice ? 1 : 0) + (chrome === "full" ? FULL_CHROME_LINES : chrome === "footer" ? 1 : 0) + detailLines + window.end - window.start + marks;
  return { window, indicators, detailLines, notice, chrome, lineCount };
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
    this.requests = [...validateSelectionRequests(requests, roster, policy)].map((r) => ({ ...r }));
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
    const fallbackChain = chainFor(this.roster, this.roster.types.get(request.type)!, model);
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
      available: this.isAvailable(model),
      fallbackChain,
      unavailableFallbacks: fallbackChain.filter((m) => !this.isAvailable(m)),
    };
  }

  currentDetails(): ModelSelectionDetails {
    return this.detailsAt(this.active);
  }

  canConfirm(): boolean {
    return this.choices.every((_, i) => this.detailsAt(i).available);
  }

  // The first role whose chosen model cannot run now.
  blocked(): BlockedRole | undefined {
    const index = this.choices.findIndex((model) => !this.isAvailable(model));
    if (index < 0) return undefined;
    const request = this.requests[index];
    return {
      index,
      key: request.key,
      title: request.title,
      model: this.choices[index],
      hasAlternative: this.compatible(index).some((m) => this.isAvailable(m.ref)),
    };
  }

  result(): readonly AgentModelSelection[] {
    const blocked = this.blocked();
    if (blocked) throw new Error(`model selection "${blocked.key}": ${blocked.model} is not available`);
    return this.requests.map((r, i) => ({ key: r.key, model: this.choices[i] }));
  }

  private isAvailable(model: string): boolean {
    return this.available?.has(model) ?? true;
  }

  private compatible(index: number): readonly ModelMetadata[] {
    return selectableModels(this.policy, this.requests[index].type);
  }
}

function wrap(value: number, length: number): number {
  return ((value % length) + length) % length;
}
