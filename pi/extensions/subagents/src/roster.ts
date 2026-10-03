// The roster: the task types and their tools from subagents.json, joined with
// the model rankings from subagent-models.json (see model-policy.ts). A type's
// own list is its balanced ranking, which ends in a Claude model (through
// claude-bridge, on the subscription) as the last fallback;
// pi/subagents-research.md says why the lists are in this order.
import { MODEL_TIERS, modelsFor, type ModelPolicy } from "./model-policy.ts";

export interface TaskType {
  readonly name: string;
  readonly use: string;
  // An empty list runs the child with no tools at all.
  readonly tools: readonly string[];
  // The balanced ranking, best first, ending in the Claude fallback.
  readonly models: readonly string[];
  // Every model any tier of the policy allows for this type.
  readonly compatible: readonly string[];
}

// A named way to pick models instead of a task type's own ranking: either a
// fixed list, or every roster model that costs nothing. It replaces the type's
// list; the type still fixes the tools.
export interface ModelProfile {
  readonly name: string;
  // "@parent" stands for the delegating agent's own model, filled in at spawn.
  readonly models: readonly string[] | undefined;
  readonly freeOnly: boolean;
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
  readonly modelProfiles: ReadonlyMap<string, ModelProfile>;
}

export const CLAUDE_PREFIX = "claude-bridge/";
export const PARENT_MODEL = "@parent";

const TIMING_DEFAULTS = {
  pingTimeoutSeconds: 20,
  pingCacheSeconds: 300,
  stallSeconds: 120,
  toolStallSeconds: 900,
  localStallSeconds: 300,
};

export function parseRoster(raw: unknown, policy: ModelPolicy): Roster {
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
    const ranking = policy.rankings.get(name);
    if (!ranking) throw new Error(`subagents.json: ${where} has no ranking for ${name} in subagent-models.json`);
    const models = [...ranking.balanced];
    const compatible = [...new Set(MODEL_TIERS.flatMap((tier) => modelsFor(policy, name, tier)))];
    if (localModel && compatible.includes(localModel)) {
      throw new Error(`subagent-models.json: rankings.${name} lists ${localModel}; the local model is only used when asked for by name`);
    }
    types.set(name, { name, use, tools, models, compatible });
  }
  if (!types.size) throw new Error("subagents.json: taskTypes is empty");
  const modelProfiles = parseModelProfiles(raw.modelProfiles ?? {});
  return { localModel, maxRunning, timing, types, modelProfiles };
}

// The named model profiles. Each replaces a type's list, so it may name the
// local model, which the type lists themselves may not.
function parseModelProfiles(raw: unknown): Map<string, ModelProfile> {
  if (!isObject(raw)) throw new Error("subagents.json: modelProfiles must be an object");
  const profiles = new Map<string, ModelProfile>();
  for (const [name, entry] of Object.entries(raw)) {
    const where = `modelProfiles.${name}`;
    if (!isObject(entry)) throw new Error(`subagents.json: ${where} must be an object`);
    const hasModels = entry.models !== undefined;
    const hasFree = entry.freeOnly !== undefined;
    if (hasModels === hasFree) {
      throw new Error(`subagents.json: ${where} must set exactly one of models or freeOnly`);
    }
    if (hasFree) {
      if (entry.freeOnly !== true) throw new Error(`subagents.json: ${where}.freeOnly must be true`);
      profiles.set(name, { name, models: undefined, freeOnly: true });
      continue;
    }
    const models = stringList(entry.models, `${where}.models`);
    if (!models.length) throw new Error(`subagents.json: ${where}.models is empty`);
    for (const model of models) if (model !== PARENT_MODEL) splitModel(model);
    if (new Set(models).size !== models.length) throw new Error(`subagents.json: ${where}.models lists a model twice`);
    if (models.some((m) => m.startsWith("anthropic/"))) {
      throw new Error(`subagents.json: ${where} uses anthropic/*, which bills the API key; use ${CLAUDE_PREFIX}* instead`);
    }
    profiles.set(name, { name, models, freeOnly: false });
  }
  return profiles;
}

export function splitModel(ref: string): { provider: string; id: string } {
  const slash = ref.indexOf("/");
  if (slash <= 0 || slash === ref.length - 1) throw new Error(`model must be "provider/id", got "${ref}"`);
  return { provider: ref.slice(0, slash), id: ref.slice(slash + 1) };
}

export function isLocal(roster: Roster, model: string): boolean {
  return model === roster.localModel;
}

// The models a subagent tries, in order: the type's balanced list, led by
// `selected` when given. `selected` must be on one of the type's policy tiers,
// or be the local model on a tool-less type.
export function chainFor(roster: Roster, type: TaskType, selected?: string): string[] {
  if (!selected) return [...type.models];
  if (isLocal(roster, selected)) {
    if (type.tools.length) throw new Error(`${selected} runs locally and cannot use tools, so it cannot run ${type.name} tasks`);
  } else if (!type.compatible.includes(selected)) {
    const local = roster.localModel && !type.tools.length ? `, or ${roster.localModel}` : "";
    throw new Error(`${selected} is not compatible with ${type.name}: ${type.compatible.join(", ")}${local}`);
  }
  return [selected, ...type.models.filter((m) => m !== selected)];
}

// The models a profile stands for, replacing the type's own list. "@parent"
// becomes the delegating agent's model; `freeOnly` becomes every roster model
// that costs nothing.
export function chainForProfile(
  roster: Roster,
  profile: ModelProfile,
  type: TaskType,
  parentModel: string | undefined,
  isFree: (model: string) => boolean,
): string[] {
  const models: string[] = [];
  if (profile.freeOnly) {
    models.push(...freeModels(roster, type, isFree));
    if (!models.length) throw new Error(`profile "${profile.name}" found no models that cost nothing`);
  } else {
    for (const model of profile.models!) {
      if (model !== PARENT_MODEL) {
        models.push(model);
        continue;
      }
      if (!parentModel) throw new Error(`profile "${profile.name}" uses ${PARENT_MODEL}, but this session has no current model`);
      models.push(parentModel);
    }
  }
  if (type.tools.length && roster.localModel && models.includes(roster.localModel)) {
    throw new Error(`${roster.localModel} runs locally and cannot use tools, so it cannot run ${type.name} tasks`);
  }
  return models;
}

// The zero-cost models, the type's own ranking first and then the rest of the
// roster, deduped. The local model is in no list, so it is never in this pool.
function freeModels(roster: Roster, type: TaskType, isFree: (model: string) => boolean): string[] {
  const pool: string[] = [];
  const seen = new Set<string>();
  const add = (model: string) => {
    if (seen.has(model) || !isFree(model)) return;
    seen.add(model);
    pool.push(model);
  };
  for (const model of type.models) add(model);
  for (const other of roster.types.values()) for (const model of other.models) add(model);
  return pool;
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
