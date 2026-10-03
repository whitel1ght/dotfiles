// The editable model policy: a catalog of models and, per task type, which of
// them to prefer at each cost tier. It lives in subagent-models.json next to
// subagents.json, which keeps the task types, tools and timing.

export type ModelTier = "budget" | "balanced" | "premium";

export const MODEL_TIERS: readonly ModelTier[] = ["budget", "balanced", "premium"];

export interface ModelMetadata {
  readonly ref: string;
  readonly label: string;
  readonly provider: string;
  readonly quality: string;
  readonly speed: string;
  readonly cost: string;
  readonly bestFor: readonly string[];
  readonly strengths: readonly string[];
  readonly avoidFor: readonly string[];
}

export interface TaskRanking {
  readonly budget: readonly string[];
  readonly balanced: readonly string[];
  readonly premium: readonly string[];
  readonly rationale: Readonly<Record<ModelTier, string>>;
}

export interface ModelPolicy {
  readonly evidenceDate: string;
  readonly models: ReadonlyMap<string, ModelMetadata>;
  readonly rankings: ReadonlyMap<string, TaskRanking>;
}

const FILE = "subagent-models.json";
export const CLAUDE_PREFIX = "claude-bridge/";
const MIN_OPEN_MODELS = 3;

export function parseModelPolicy(raw: unknown): ModelPolicy {
  if (!isObject(raw)) throw new Error(`${FILE}: expected an object`);
  const evidenceDate = raw.evidenceDate;
  if (typeof evidenceDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(evidenceDate)) {
    throw new Error(`${FILE}: evidenceDate must be a YYYY-MM-DD date`);
  }
  if (!isObject(raw.models)) throw new Error(`${FILE}: models must be an object`);
  const models = new Map<string, ModelMetadata>();
  for (const [ref, entry] of Object.entries(raw.models)) {
    checkRef(ref, `models.${ref}`);
    models.set(ref, parseMetadata(ref, entry));
  }
  if (!models.size) throw new Error(`${FILE}: models is empty`);

  if (!isObject(raw.rankings)) throw new Error(`${FILE}: rankings must be an object`);
  const rankings = new Map<string, TaskRanking>();
  for (const [name, entry] of Object.entries(raw.rankings)) rankings.set(name, parseRanking(name, entry, models));
  if (!rankings.size) throw new Error(`${FILE}: rankings is empty`);
  return { evidenceDate, models, rankings };
}

export function modelsFor(policy: ModelPolicy, taskType: string, tier: ModelTier): readonly string[] {
  const ranking = policy.rankings.get(taskType);
  if (!ranking) throw new Error(`${FILE}: no ranking for ${taskType}`);
  return ranking[tier];
}

// Every model a task may be given: budget, then balanced, then premium.
export function selectableModels(policy: ModelPolicy, taskType: string): readonly ModelMetadata[] {
  const refs = new Set<string>();
  for (const tier of MODEL_TIERS) for (const ref of modelsFor(policy, taskType, tier)) refs.add(ref);
  return [...refs].map((ref) => policy.models.get(ref)!);
}

// Catalog models absent from the `provider/id` set `pi --list-models` reports,
// sorted. Exact match: anthropic/* never stands in for claude-bridge/*.
export function missingCatalogModels(policy: ModelPolicy, available: ReadonlySet<string>): string[] {
  return [...policy.models.keys()].filter((ref) => !available.has(ref)).sort();
}

function parseRanking(name: string, entry: unknown, catalog: ReadonlyMap<string, ModelMetadata>): TaskRanking {
  const where = `rankings.${name}`;
  if (!isObject(entry)) throw new Error(`${FILE}: ${where} must be an object`);
  const tiers = {} as Record<ModelTier, string[]>;
  for (const tier of MODEL_TIERS) {
    const field = `${where}.${tier}`;
    const refs = stringList(entry[tier], field);
    if (!refs.length) throw new Error(`${FILE}: ${field} must not be empty`);
    for (const ref of refs) {
      checkRef(ref, field);
      if (!catalog.has(ref)) throw new Error(`${FILE}: ${field} lists ${ref}, which is not in the models catalog`);
    }
    const seen = new Set<string>();
    for (const ref of refs) {
      if (seen.has(ref)) throw new Error(`${FILE}: ${field} lists ${ref} twice`);
      seen.add(ref);
    }
    tiers[tier] = refs;
  }
  const balanced = tiers.balanced;
  const claude = balanced.filter((m) => m.startsWith(CLAUDE_PREFIX));
  if (claude.length !== 1 || !balanced.at(-1)!.startsWith(CLAUDE_PREFIX)) {
    throw new Error(`${FILE}: ${where}.balanced must end with exactly one ${CLAUDE_PREFIX}* model, the last fallback`);
  }
  if (balanced.length - 1 < MIN_OPEN_MODELS) {
    throw new Error(`${FILE}: ${where}.balanced needs at least ${MIN_OPEN_MODELS} models before the Claude fallback`);
  }
  if (!isObject(entry.rationale)) throw new Error(`${FILE}: ${where}.rationale must be an object`);
  const rationale = {} as Record<ModelTier, string>;
  for (const tier of MODEL_TIERS) {
    const text = entry.rationale[tier];
    if (typeof text !== "string" || !text.trim()) throw new Error(`${FILE}: ${where}.rationale.${tier} must be a non-empty string`);
    rationale[tier] = text.trim();
  }
  return { ...tiers, rationale };
}

function parseMetadata(ref: string, entry: unknown): ModelMetadata {
  const where = `models.${ref}`;
  if (!isObject(entry)) throw new Error(`${FILE}: ${where} must be an object`);
  const text = (key: string) => {
    const value = entry[key];
    if (typeof value !== "string" || !value.trim()) throw new Error(`${FILE}: ${where}.${key} must be a non-empty string`);
    return value.trim();
  };
  return {
    ref,
    label: text("label"),
    provider: text("provider"),
    quality: text("quality"),
    speed: text("speed"),
    cost: text("cost"),
    bestFor: stringList(entry.bestFor, `${where}.bestFor`),
    strengths: stringList(entry.strengths, `${where}.strengths`),
    avoidFor: stringList(entry.avoidFor, `${where}.avoidFor`),
  };
}

function checkRef(ref: string, where: string): void {
  if (ref.startsWith("anthropic/")) {
    throw new Error(`${FILE}: ${where} uses anthropic/*, which bills the API key; use ${CLAUDE_PREFIX}* instead`);
  }
  const slash = ref.indexOf("/");
  if (slash <= 0 || slash === ref.length - 1) throw new Error(`${FILE}: ${where} must be "provider/id", got "${ref}"`);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringList(value: unknown, where: string): string[] {
  if (!Array.isArray(value) || value.some((v) => typeof v !== "string" || !v.trim())) {
    throw new Error(`${FILE}: ${where} must be a list of strings`);
  }
  return value.map((v: string) => v.trim());
}
