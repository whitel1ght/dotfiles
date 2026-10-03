import { StringEnum } from "@earendil-works/pi-ai";
import { getAgentDir, parseFrontmatter, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { WakeQueue } from "../background-terminals/src/wake-queue.ts";
import { AgentManager, type Agent } from "./src/agents.ts";
import { oversizedTask } from "./src/budget.ts";
import { describe, renderOutput, wakeMessage } from "./src/format.ts";
import { CHILD_ENV, piCommand } from "./src/invocation.ts";
import { parseModelPolicy } from "./src/model-policy.ts";
import { loadProfiles, profileTools } from "./src/profiles.ts";
import {
  LIST_DESCRIPTION,
  OUTPUT_DESCRIPTION,
  SPAWN_GUIDELINES,
  SPAWN_SNIPPET,
  spawnDescription,
  STOP_DESCRIPTION,
  WAIT_DESCRIPTION,
} from "./src/prompt.ts";
import { chainFor, chainForProfile, isLocal, PARENT_MODEL, parseRoster, type Roster } from "./src/roster.ts";
import { AgentView } from "./src/ui/view.ts";

const WIDGET = "subagents";
const WAKE_TYPE = "subagent-finished";
const DEFAULT_WAIT_SECONDS = 900;

const text = (value: string) => ({ type: "text" as const, text: value });

export default function (pi: ExtensionAPI) {
  // A subagent is a pi run too; it must not delegate further.
  if (process.env[CHILD_ENV]) return;

  const agentDir = getAgentDir();
  const rosterPath = join(agentDir, "subagents.json");
  if (!existsSync(rosterPath)) return;
  const policyPath = join(agentDir, "subagent-models.json");
  if (!existsSync(policyPath)) throw new Error(`subagents: ${rosterPath} exists but the model policy ${policyPath} is missing`);
  let policy;
  try {
    policy = parseModelPolicy(JSON.parse(readFileSync(policyPath, "utf8")));
  } catch (error) {
    throw new Error(`subagents: invalid model policy ${policyPath}: ${error instanceof Error ? error.message : error}`);
  }
  const roster: Roster = parseRoster(JSON.parse(readFileSync(rosterPath, "utf8")), policy);
  const profiles = loadProfiles(join(agentDir, "agents"), parseFrontmatter);

  const manager = new AgentManager({
    piCommand: piCommand(),
    maxRunning: roster.maxRunning,
    timing: roster.timing,
    localModel: roster.localModel,
  });
  const wake = new WakeQueue<Agent>();
  let ctx: ExtensionContext | undefined;

  const isIdle = () => {
    try {
      return ctx?.isIdle() ?? false;
    } catch {
      return false;
    }
  };

  const flush = () => {
    if (!wake.size || !isIdle()) return;
    const finished = wake.drain();
    pi.sendMessage(
      { customType: WAKE_TYPE, content: wakeMessage(finished), display: true, details: { ids: finished.map((a) => a.id) } },
      { triggerTurn: true },
    );
  };

  const updateWidget = () => {
    if (!ctx?.hasUI) return;
    const n = manager.running().length;
    ctx.ui.setWidget(WIDGET, n ? [`● ${n} subagent${n === 1 ? "" : "s"} running • /agents to view`] : undefined);
  };

  manager.onChange(updateWidget);
  manager.onFinish((agent) => {
    if (agent.status === "stopped") return;
    wake.defer(agent);
    flush();
  });

  pi.on("session_start", (_event, context) => {
    ctx = context;
    updateWidget();
  });
  pi.on("agent_settled", (_event, context) => {
    ctx = context;
    flush();
  });
  pi.on("session_shutdown", async () => {
    ctx = undefined;
    await manager.shutdown();
  });

  const lookup = (id: string): Agent => {
    const agent = manager.get(id);
    if (!agent) {
      const known = manager.list().map((a) => a.id).join(", ") || "none";
      throw new Error(`unknown subagent ${id} (known: ${known})`);
    }
    return agent;
  };

  // The models pi can reach whose catalog cost is zero — the subscription
  // fallbacks. What the `free` profile runs on.
  const freeModels = (context: ExtensionContext): ReadonlySet<string> => {
    const free = new Set<string>();
    for (const entry of context.modelRegistry.getAvailable()) {
      const cost = entry.cost;
      if (!cost.input && !cost.output && !cost.cacheRead && !cost.cacheWrite) free.add(`${entry.provider}/${entry.id}`);
    }
    return free;
  };

  // Why `model` cannot run `task` now, or undefined when it can. Cheap checks
  // only; whether the model actually answers is what the ping is for.
  const preflight = (task: string, context: ExtensionContext) => async (model: string) => {
    const entry = context.modelRegistry.getAvailable().find((m) => `${m.provider}/${m.id}` === model);
    if (!entry) return "not available in this pi (no credentials, or its provider is not loaded)";
    if (!isLocal(roster, model)) return undefined;
    const oversized = oversizedTask(model, task, entry);
    if (oversized) return oversized;
    try {
      const response = await fetch(`${entry.baseUrl.replace(/\/$/, "")}/models`, { signal: AbortSignal.timeout(1500) });
      if (!response.ok) return `${entry.baseUrl} answered HTTP ${response.status}`;
    } catch (error) {
      return `${entry.baseUrl} is not answering (${(error as Error).message}); is Ollama running?`;
    }
    return undefined;
  };

  const typeNames = [...roster.types.keys()];
  const profileNames = [...profiles.keys()];
  const modelProfileNames = [...roster.modelProfiles.keys()];

  pi.registerTool({
    name: "agent_spawn",
    label: "Subagent",
    description: spawnDescription(roster),
    promptSnippet: SPAWN_SNIPPET,
    promptGuidelines: SPAWN_GUIDELINES,
    parameters: Type.Object({
      type: StringEnum(typeNames as [string, ...string[]], { description: "Task type; fixes the tools the subagent gets" }),
      task: Type.String({ description: "Everything the subagent needs, and what it should return. It cannot see this conversation." }),
      model: Type.Optional(
        Type.String({ description: "Start at this model on the type's list instead of the top. Leave it out unless a subagent already did poorly." }),
      ),
      ...(profileNames.length
        ? {
            profile: Type.Optional(
              StringEnum(profileNames as [string, ...string[]], { description: "Specialist persona to add to the subagent's system prompt" }),
            ),
          }
        : {}),
      ...(modelProfileNames.length
        ? {
            modelProfile: Type.Optional(
              StringEnum(modelProfileNames as [string, ...string[]], {
                description: "Replace the type's model list with a named profile (see this tool's description); leave it out for the type's own ranking",
              }),
            ),
          }
        : {}),
      title: Type.Optional(Type.String({ description: "Short label for /agents and notifications" })),
      cwd: Type.Optional(Type.String({ description: "Working directory (default: the session directory)" })),
    }),
    async execute(_id, params, _signal, _onUpdate, context) {
      ctx = context;
      const type = roster.types.get(params.type);
      if (!type) throw new Error(`unknown task type ${params.type}; one of: ${typeNames.join(", ")}`);
      const profileName = (params as { profile?: string }).profile;
      const profile = profileName ? profiles.get(profileName) : undefined;
      if (profileName && !profile) throw new Error(`unknown profile ${profileName}`);
      const parentModel = context.model ? `${context.model.provider}/${context.model.id}` : undefined;

      const modelProfileName = (params as { modelProfile?: string }).modelProfile;
      let chain: string[];
      let parentInChain = false;
      if (modelProfileName) {
        const modelProfile = roster.modelProfiles.get(modelProfileName);
        if (!modelProfile) throw new Error(`unknown model profile ${modelProfileName}; one of: ${modelProfileNames.join(", ")}`);
        const free = modelProfile.freeOnly ? freeModels(context) : undefined;
        chain = chainForProfile(roster, modelProfile, type, parentModel, (model) => free?.has(model) ?? false);
        // Only a profile that names @parent runs on the parent's own model; a
        // pool that merely contains it still skips it as the delegating agent's.
        parentInChain = modelProfile.models?.includes(PARENT_MODEL) ?? false;
      } else {
        chain = chainFor(roster, type, params.model?.trim() || undefined);
      }

      const agent = manager.spawn({
        type: type.name,
        chain,
        task: params.task,
        title: params.title,
        cwd: params.cwd ? resolve(context.cwd, params.cwd) : context.cwd,
        tools: profileTools(type.tools, profile),
        profile: profile && { name: profile.name, prompt: profile.prompt },
        parentModel,
        parentInChain,
        preflight: preflight(params.task, context),
      });
      return {
        content: [
          text(
            `Started ${agent.id} (${type.name}); it will try ${chain.join(" → ")}, in that order. ` +
              `You will be woken with its result. Progress: agent_output ${agent.id}.`,
          ),
        ],
        details: { id: agent.id, chain },
      };
    },
  });

  pi.registerTool({
    name: "agent_list",
    label: "Subagents",
    description: LIST_DESCRIPTION,
    parameters: Type.Object({}),
    async execute() {
      return { content: [text(manager.list().map((a) => describe(a)).join("\n") || "No subagents.")], details: undefined };
    },
  });

  pi.registerTool({
    name: "agent_output",
    label: "Subagent output",
    description: OUTPUT_DESCRIPTION,
    parameters: Type.Object({ id: Type.String({ description: "Subagent id, e.g. agent-1" }) }),
    async execute(_id, params) {
      const agent = lookup(params.id);
      if (agent.status !== "running") wake.consume(agent.id);
      return { content: [text(renderOutput(agent))], details: { id: agent.id, status: agent.status } };
    },
  });

  pi.registerTool({
    name: "agent_wait",
    label: "Wait for subagents",
    description: WAIT_DESCRIPTION,
    parameters: Type.Object({
      ids: Type.Optional(Type.Array(Type.String(), { description: "Subagent ids (default: every running one)" })),
      timeout_seconds: Type.Optional(Type.Number({ description: `Give up waiting after this long (default ${DEFAULT_WAIT_SECONDS})` })),
    }),
    async execute(_id, params, signal) {
      const ids = params.ids?.length ? params.ids : manager.running().map((a) => a.id);
      if (!ids.length) return { content: [text("No subagents are running.")], details: undefined };
      const timeout = AbortSignal.timeout(Math.max(1, params.timeout_seconds ?? DEFAULT_WAIT_SECONDS) * 1000);
      const agents = await manager.wait(ids, signal ? AbortSignal.any([signal, timeout]) : timeout);
      for (const agent of agents) if (agent.status !== "running") wake.consume(agent.id);
      const pending = agents.filter((a) => a.status === "running").length;
      const note = pending ? `\n\nStopped waiting with ${pending} still running; you will be woken when they finish.` : "";
      return {
        content: [text(agents.map((a) => renderOutput(a)).join("\n\n") + note)],
        details: { ids: agents.map((a) => a.id) },
      };
    },
  });

  pi.registerTool({
    name: "agent_stop",
    label: "Stop subagent",
    description: STOP_DESCRIPTION,
    parameters: Type.Object({ id: Type.String({ description: "Subagent id, e.g. agent-1" }) }),
    async execute(_id, params) {
      const agent = lookup(params.id);
      const was = agent.status;
      wake.consume(agent.id);
      await manager.stop(agent.id);
      return {
        content: [text(was === "running" ? `Stopped ${describe(agent)}` : `${describe(agent)} had already finished.`)],
        details: { id: agent.id, status: agent.status },
      };
    },
  });

  pi.registerCommand("agents", {
    description: "List and inspect subagents",
    handler: async (_args, context) => {
      ctx = context;
      for (;;) {
        const agents = manager.list();
        if (!agents.length) {
          context.ui.notify("No subagents.", "info");
          return;
        }
        const choice = await context.ui.select("Subagents", agents.map((a) => describe(a)));
        if (!choice) return;
        const id = choice.split(" ")[0];
        wake.consume(id);
        await context.ui.custom<void>((tui, theme, _keys, done) => new AgentView(manager, id, tui, theme, () => done()));
      }
    },
  });
}
