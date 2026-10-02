// The roster: which models run each task type, best first, with a Claude model
// (through claude-bridge, on the subscription) as the last fallback. It lives
// in subagents.json next to settings.json; pi/subagents-research.md says why
// the lists are in this order.

export interface TaskType {
  readonly name: string;
  readonly use: string;
  // An empty list runs the child with no tools at all.
  readonly tools: readonly string[];
  readonly models: readonly string[];
}

export interface Timing {
  readonly pingTimeoutMs: number;
  readonly pingCacheMs: number;
  // Silence that counts as a stall: while the model is generating, while one
  // of its tools is running, and for the local model, which loads slowly.
  readonly stallMs: number;
  readonly toolStallMs: number;
  readonly localStallMs: number;
}

export interface Roster {
  readonly localModel: string | undefined;
  readonly maxRunning: number;
  readonly timing: Timing;
  readonly types: ReadonlyMap<string, TaskType>;
}

export const CLAUDE_PREFIX = "claude-bridge/";
const MIN_OPEN_MODELS = 3;

const TIMING_DEFAULTS = {
  pingTimeoutSeconds: 20,
  pingCacheSeconds: 300,
  stallSeconds: 120,
  toolStallSeconds: 900,
  localStallSeconds: 300,
};

export function parseRoster(raw: unknown): Roster {
  if (!isObject(raw)) throw new Error("subagents.json: expected an object");
  const localModel = optionalString(raw.localModel, "localModel");
  if (localModel) splitModel(localModel);
  const maxRunning = raw.maxRunning ?? 4;
  if (typeof maxRunning !== "number" || !Number.isInteger(maxRunning) || maxRunning < 1) {
    throw new Error("subagents.json: maxRunning must be a positive integer");
  }
  const timing = parseTiming(raw.timing ?? {});
  if (!isObject(raw.taskTypes)) throw new Error("subagents.json: taskTypes must be an object");

  const types = new Map<string, TaskType>();
  for (const [name, entry] of Object.entries(raw.taskTypes)) {
    const where = `taskTypes.${name}`;
    if (!isObject(entry)) throw new Error(`subagents.json: ${where} must be an object`);
    const use = optionalString(entry.use, `${where}.use`);
    if (!use) throw new Error(`subagents.json: ${where}.use is required`);
    const tools = stringList(entry.tools, `${where}.tools`);
    const models = stringList(entry.models, `${where}.models`);
    for (const model of models) splitModel(model);
    if (new Set(models).size !== models.length) throw new Error(`subagents.json: ${where}.models lists a model twice`);
    if (models.some((m) => m.startsWith("anthropic/"))) {
      throw new Error(`subagents.json: ${where} uses anthropic/*, which bills the API key; use ${CLAUDE_PREFIX}* instead`);
    }
    const claude = models.filter((m) => m.startsWith(CLAUDE_PREFIX));
    if (claude.length !== 1 || !models.at(-1)!.startsWith(CLAUDE_PREFIX)) {
      throw new Error(`subagents.json: ${where}.models must end with exactly one ${CLAUDE_PREFIX}* model, the last fallback`);
    }
    if (models.length - 1 < MIN_OPEN_MODELS) {
      throw new Error(`subagents.json: ${where}.models needs at least ${MIN_OPEN_MODELS} models before the Claude fallback`);
    }
    if (localModel && models.includes(localModel)) {
      throw new Error(`subagents.json: ${where} lists ${localModel}; the local model is only used when asked for by name`);
    }
    types.set(name, { name, use, tools, models });
  }
  if (!types.size) throw new Error("subagents.json: taskTypes is empty");
  return { localModel, maxRunning, timing, types };
}

export function splitModel(ref: string): { provider: string; id: string } {
  const slash = ref.indexOf("/");
  if (slash <= 0 || slash === ref.length - 1) throw new Error(`model must be "provider/id", got "${ref}"`);
  return { provider: ref.slice(0, slash), id: ref.slice(slash + 1) };
}

export function isLocal(roster: Roster, model: string): boolean {
  return model === roster.localModel;
}

// The models a subagent tries, in order. `start` skips ahead to a model on the
// type's list, or puts the local model in front of a tool-less type's list.
export function chainFor(roster: Roster, type: TaskType, start?: string): string[] {
  if (!start) return [...type.models];
  if (isLocal(roster, start)) {
    if (type.tools.length) throw new Error(`${start} runs locally and cannot use tools, so it cannot run ${type.name} tasks`);
    return [start, ...type.models];
  }
  const index = type.models.indexOf(start);
  if (index < 0) {
    const local = roster.localModel && !type.tools.length ? `, or ${roster.localModel}` : "";
    throw new Error(`${start} is not on the ${type.name} list: ${type.models.join(", ")}${local}`);
  }
  return type.models.slice(index);
}

// The roster as the model reads it in the spawn tool's description.
export function describeRoster(roster: Roster): string {
  return [...roster.types.values()]
    .map((t) => {
      const tools = t.tools.length ? t.tools.join(", ") : "none";
      return `- ${t.name}: ${t.use}\n  tools: ${tools}\n  models, best first: ${t.models.join(" → ")}`;
    })
    .join("\n");
}

function parseTiming(raw: unknown): Timing {
  if (!isObject(raw)) throw new Error("subagents.json: timing must be an object");
  const seconds = (key: keyof typeof TIMING_DEFAULTS) => {
    const value = raw[key] ?? TIMING_DEFAULTS[key];
    if (typeof value !== "number" || !(value > 0)) throw new Error(`subagents.json: timing.${key} must be a positive number`);
    return value * 1000;
  };
  return {
    pingTimeoutMs: seconds("pingTimeoutSeconds"),
    pingCacheMs: seconds("pingCacheSeconds"),
    stallMs: seconds("stallSeconds"),
    toolStallMs: seconds("toolStallSeconds"),
    localStallMs: seconds("localStallSeconds"),
  };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function optionalString(value: unknown, where: string): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || !value.trim()) throw new Error(`subagents.json: ${where} must be a non-empty string`);
  return value.trim();
}

function stringList(value: unknown, where: string): string[] {
  if (!Array.isArray(value) || value.some((v) => typeof v !== "string" || !v.trim())) {
    throw new Error(`subagents.json: ${where} must be a list of strings`);
  }
  return value.map((v: string) => v.trim());
}
