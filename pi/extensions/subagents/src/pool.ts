// The models a parent may give a subagent: the ones the session has enabled
// (its scope) that pi can actually reach (authenticated). The parent picks one
// per subagent; nothing here ranks them or chooses for it.
import type { ModelPolicy } from "./model-policy.ts";
import { isLocal, type Roster, type TaskType } from "./roster.ts";

interface ModelRef {
  readonly provider: string;
  readonly id: string;
}

const refOf = (m: ModelRef) => `${m.provider}/${m.id}`;

// An empty scope means no scoping: every authenticated model. Read both inputs
// afresh for each call, so a changed scope or login shows at once.
export function sessionModelPool(scoped: readonly { readonly model: ModelRef }[], available: readonly ModelRef[]): string[] {
  const reachable = [...new Set(available.map(refOf))];
  if (!scoped.length) return reachable;
  const enabled = new Set(scoped.map((s) => refOf(s.model)));
  return reachable.filter((m) => enabled.has(m));
}

// The one model a subagent runs on. It is not tried against any other.
export function resolveSpawnModel(roster: Roster, type: TaskType, pool: readonly string[], requested: string | undefined): string {
  const names = pool.join(", ");
  if (!pool.length) throw new Error("no usable models: this session has no authenticated model in its scope");
  const model = requested?.trim();
  if (!model) throw new Error(`model is required; choose one from this session's pool: ${names}`);
  if (!pool.includes(model)) throw new Error(`${model} is not in this session's model pool: ${names}`);
  if (isLocal(roster, model) && type.tools.length) {
    throw new Error(`${model} runs locally and cannot use tools, so it cannot run ${type.name} tasks`);
  }
  return model;
}

// The pool as the parent reads it, with the catalogue's notes where there are
// any. The notes describe each model; they are not an order.
export function describePool(pool: readonly string[], policy: ModelPolicy): string {
  if (!pool.length) return "No usable models: this session has no authenticated model in its scope.";
  const lines = pool.map((ref) => {
    const m = policy.models.get(ref);
    if (!m) return `- ${ref}: no notes`;
    return `- ${ref} (${m.label}): quality ${m.quality}, speed ${m.speed}, cost ${m.cost}; strengths: ${m.strengths.join("; ")}; avoid for: ${m.avoidFor.join("; ")}`;
  });
  return ["Models you may give a subagent in this session (in no order):", ...lines].join("\n");
}
