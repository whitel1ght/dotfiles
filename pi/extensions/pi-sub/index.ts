// Extension entry point: registers the subagent tools, wires the lifecycle
// (deliver pending runs, watch owned agents, report orphans), and keeps the
// acp_delegate tools out of the model's hands — pi-sub replaces them.

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { activity } from "./events.ts";
import {
  agentFolder,
  num,
  obj,
  ordinalOf,
  readFileOrNull,
  readEvents,
  reown,
  requireAgent,
  str,
  strArr,
  tailLines,
  type AdoptParams,
  type IdParams,
  type ResultParams,
  type SubagentParams,
} from "./helpers.ts";
import { keyName, type Action } from "./keys.ts";
import { launch } from "./launch.ts";
import { loadRole } from "./roles.ts";
import { deliverPending, flagText, isPidAlive, stop, Watcher } from "./runtime.ts";
import { isDelivered, listAgents, orphans, owned, readExit, writeMeta } from "./state.ts";
import { AgentsOverlay, footerText, visibleRows } from "./ui.ts";
import { liveModels } from "../session-models/index.ts";

const WAKE_TYPE = "pi-sub";

/** Delegation is pi-sub's job; these never reach the model. */
const DELEGATE_TOOLS = new Set(["acp_delegate", "acp_delegate_wait", "acp_delegate_cancel"]);

const EXTRAS = ["web", "playwright"] as const;

/** Idle-flag threshold unless the caller passes another; 0 disables it. */
const DEFAULT_IDLE_MINUTES = 10;

/** Hard cap for a subagent run unless the caller asks for another. */
const DEFAULT_MAX_MINUTES = 60;

/** Default tail length of subagent_result. */
const DEFAULT_LINES = 40;

const text = (value: string) => ({ type: "text" as const, text: value });

const HOTKEY = "ctrl+space";

/**
 * pi's --skill wants a path. A bare name means a skill installed in pi's own
 * skills dir; anything with a slash is a path relative to the session cwd.
 */
/** A path the model wrote: `~/x` is under home, anything else is relative to `base`. */
export function resolvePath(base: string, p: string): string {
  return p === "~" || p.startsWith("~/") ? join(homedir(), p.slice(1)) : resolve(base, p);
}

export function resolveSkill(skill: string, cwd: string): string {
  const path = skill.includes("/")
    ? resolvePath(cwd, skill)
    : join(process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent"), "skills", skill);
  if (!existsSync(path)) throw new Error(`pi-sub: skill not found: ${skill} (looked at ${path})`);
  return path;
}

/** `piSub.keys` from pi's settings: overlay key rebinds, { "<default>": "<yours>" }. */
function rebinds(): Record<string, string> {
  const dir = process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
  try {
    const keys = JSON.parse(readFileSync(join(dir, "settings.json"), "utf8"))?.piSub?.keys;
    if (keys && typeof keys === "object") {
      return Object.fromEntries(Object.entries(keys).filter(([, v]) => typeof v === "string")) as Record<string, string>;
    }
  } catch {
    // No settings or unreadable: defaults.
  }
  return {};
}

export default function piSub(pi: ExtensionAPI) {
  // We are a subagent child (launch sets PI_SUBAGENT): no tools, no watcher.
  if (process.env.PI_SUBAGENT === "1") return;

  let watcher: Watcher | undefined;
  let session = "";
  let refreshFooter: () => void = () => {};

  const send = (text: string) => {
    pi.sendMessage({ customType: WAKE_TYPE, content: text, display: true }, { triggerTurn: true, deliverAs: "followUp" });
  };

  pi.on("session_start", (_event, ctx) => {
    session = ctx.sessionManager.getSessionId();
    refreshFooter = () => {
      if (!ctx.hasUI) return;
      const mine = visibleRows(listAgents(), session, { showFinished: false, filter: "" }, new Date(), isPidAlive)
        .filter((r) => !r.orphan);
      ctx.ui.setStatus("pi-sub", footerText(mine, HOTKEY));
    };
    // A reload fires session_start again: stop and clear any watcher from a
    // previous start so its timers are never orphaned.
    watcher?.stop();
    watcher = undefined;
    // Exits recorded while this session was down are delivered right away.
    deliverPending(session, send);
    watcher = new Watcher(session, () => refreshFooter(), send);
    watcher.start();
    refreshFooter();
    const found = orphans(listAgents(), session, isPidAlive);
    if (found.length > 0) {
      const lines = found.map((m) => `- ${m.id} ${m.role} (${m.model}) · ${m.label}`);
      send(`[pi-sub] ${found.length} orphaned agent(s) from dead sessions (adopt with subagent_adopt):\n${lines.join("\n")}`);
    }
  });

  pi.on("before_agent_start", () => {
    const active = pi.getActiveTools();
    const kept = active.filter((name) => !DELEGATE_TOOLS.has(name));
    if (kept.length !== active.length) pi.setActiveTools(kept);
  });

  // Stop watching only: the children outlive the session by design.
  pi.on("session_shutdown", () => {
    watcher?.stop();
    watcher = undefined;
    refreshFooter = () => {};
  });

  const onAction = (ctx: { ui: { notify(msg: string, type?: "info" | "warning" | "error"): void } }) => (a: Action) => {
    if (a.stop) {
      stop(a.stop, "user")
        .then(() => refreshFooter())
        .catch((err: unknown) => ctx.ui.notify(String((err as Error)?.message ?? err), "error"));
    }
    if (a.flag) {
      const m = listAgents().find((x) => x.id === a.flag!.id);
      if (m) send(flagText(m, ordinalOf(session, m.id), a.flag.note || "(no note)"));
    }
  };

  const openOverlay = async (ctx: any, openId?: string) => {
    if (!ctx.hasUI) return;
    await ctx.ui.custom(
      (tui: any, _theme: unknown, _kb: unknown, done: (r: undefined) => void) =>
        new AgentsOverlay(
          {
            session,
            agents: listAgents,
            alive: isPidAlive,
            events: readEvents,
            result: (id) => readFileOrNull(join(agentFolder(id), "result.md")),
            parse: keyName,
            rebinds: rebinds(),
            rowsOnScreen: () => Math.max(10, Math.floor((tui.terminal?.rows ?? 30) * 0.8)),
            onAction: onAction(ctx),
            done: () => done(undefined),
            requestRender: () => tui.requestRender(),
          },
          openId,
        ),
      { overlay: true, overlayOptions: { width: "90%", maxHeight: "80%", anchor: "center" } },
    );
    refreshFooter();
  };

  pi.registerShortcut(HOTKEY, {
    description: "Subagents: list, open, stop, flag",
    handler: (ctx) => openOverlay(ctx),
  });

  pi.registerCommand("agents", {
    description: "Subagents overlay; `/agents <id>` opens one, `/agents adopt <session>` adopts a handoff",
    handler: async (args: string, ctx: any) => {
      const [first, second] = args.trim().split(/\s+/).filter(Boolean);
      if (first === "adopt") {
        if (!second) return ctx.ui.notify("usage: /agents adopt <session id>", "warning");
        const moved = listAgents()
          .filter((m) => m.handoff_from === second || (m.owner_session === second && m.handoff_from !== undefined))
          .map((m) => reown(m, session));
        ctx.ui.notify(moved.length ? `Adopted ${moved.length} agent(s) from ${second}` : `No handed-off agents from ${second}`);
        refreshFooter();
        return;
      }
      if (first && !listAgents().some((m) => m.id === first)) {
        return ctx.ui.notify(`pi-sub: no agent ${first}`, "warning");
      }
      await openOverlay(ctx, first);
    },
  });

  pi.registerTool({
    name: "subagent",
    label: "Subagent",
    description:
      "Launch a subagent that runs a task in the background and wakes this session with the result when it finishes. " +
      "Give it a complete, self-contained task; you will be told when it is done — do not poll it.",
    promptSnippet: "subagent: launch a background subagent for a self-contained task",
    parameters: obj(
      {
        role: str("Subagent role, e.g. reviewer, researcher, planner, oracle, worker"),
        model: str('Model id, "provider/model", from this session\'s live model list; pass it explicitly'),
        task: str("Complete task instructions for the subagent"),
        cwd: str("Working directory (default: this session's cwd)"),
        skills: strArr("Skills to enable in the child: a name from ~/.pi/agent/skills, or a path"),
        with: strArr('Extra capabilities: "web" (web access) or "playwright" (browser)'),
        label: str("Short label shown in wake messages"),
        idle_minutes: num("Flag this session when the agent has been quiet this long (default 10; 0 disables it)"),
        max_minutes: num("Hard timeout: stop the agent after this many minutes (default 60)"),
      },
      ["role", "model", "task"],
    ),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const p = params as unknown as SubagentParams;
      const session = ctx.sessionManager.getSessionId();
      const role = loadRole(p.role); // throws with the available roles
      const models = liveModels(ctx);
      if (!models.includes(p.model)) {
        throw new Error(
          `pi-sub: model "${p.model}" is not in this session's live model list (${models.join(", ") || "none available"})`,
        );
      }
      for (const extra of p.with ?? []) {
        if (!EXTRAS.includes(extra as (typeof EXTRAS)[number])) {
          throw new Error(`pi-sub: unknown extra "${extra}"; expected web or playwright`);
        }
      }
      const meta = launch({
        role,
        model: p.model,
        label: p.label ?? (p.task.split("\n")[0].slice(0, 60) || "subagent task"),
        task: p.task,
        cwd: p.cwd ? resolvePath(ctx.cwd, p.cwd) : ctx.cwd,
        skills: (p.skills ?? []).map((sk) => resolveSkill(sk, ctx.cwd)),
        extras: p.with ?? [],
        ownerSession: session,
        ownerPid: process.pid,
        idleMinutes: p.idle_minutes ?? DEFAULT_IDLE_MINUTES,
        maxMinutes: p.max_minutes ?? DEFAULT_MAX_MINUTES,
      });
      const ordinal = ordinalOf(session, meta.id);
      return {
        content: [
          text(
            [
              `#${ordinal} ${meta.role} (${meta.model}) started · ${meta.label}`,
              `id: ${meta.id}`,
              `folder: ${agentFolder(meta.id)}`,
              "You will be woken when it finishes; do not poll.",
            ].join("\n"),
          ),
        ],
        details: { id: meta.id },
      };
    },
  });

  pi.registerTool({
    name: "subagent_stop",
    label: "Stop subagent",
    description: "Stop a running subagent (graceful SIGTERM, then SIGKILL). The wake message follows when it exits.",
    parameters: obj({ id: str("Agent id from the subagent launch result") }, ["id"]),
    async execute(_id, params) {
      const p = params as unknown as IdParams;
      requireAgent(p.id);
      await stop(p.id, "main");
      return { content: [text(`Stopped ${p.id}. The wake message follows when it exits.`)], details: { id: p.id } };
    },
  });

  pi.registerTool({
    name: "subagent_result",
    label: "Subagent result",
    description:
      "The tail of a subagent's result (when it has finished) or of its live activity (while it runs). " +
      "Unnecessary while a run is healthy: you are woken with the result.",
    parameters: obj(
      {
        id: str("Agent id from the subagent launch result"),
        lines: num(`How many trailing lines to show (default ${DEFAULT_LINES})`),
      },
      ["id"],
    ),
    async execute(_id, params) {
      const p = params as unknown as ResultParams;
      const m = requireAgent(p.id);
      const lines = Math.max(1, p.lines ?? DEFAULT_LINES);
      const x = readExit(m.id);
      const head = `#${ordinalOf(m.owner_session, m.id)} ${m.role} (${m.model}) ${x ? x.how : "running"} · ${m.label}`;
      let body: string;
      if (x !== undefined) {
        body = tailLines(readFileOrNull(join(agentFolder(m.id), "result.md")) ?? "(no result.md)", lines);
      } else {
        const acts = activity(readEvents(m.id)).map((a) => a.text);
        body = acts.length > 0 ? tailLines(acts.join("\n"), lines) : "(no activity yet)";
      }
      return { content: [text(`${head}\n${body}`)], details: { id: m.id } };
    },
  });

  pi.registerTool({
    name: "subagent_adopt",
    label: "Adopt subagent",
    description:
      "Take over agents from another session: one by id, or every agent a session handed off. " +
      "After adopting, this session is woken when they finish.",
    parameters: obj(
      {
        id: str("Adopt exactly this agent, whatever session owns it"),
        from: str("Adopt every agent handed off by this session id (from subagent_handoff)"),
      },
      [],
    ),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const p = params as unknown as AdoptParams;
      const session = ctx.sessionManager.getSessionId();
      if ((p.id === undefined) === (p.from === undefined)) {
        throw new Error("pi-sub: pass exactly one of id or from");
      }
      let adopted;
      if (p.id !== undefined) {
        adopted = [reown(requireAgent(p.id), session)];
      } else {
        adopted = listAgents()
          .filter(
            (m) => m.handoff_from === p.from || (m.owner_session === p.from && m.handoff_from !== undefined),
          )
          .map((m) => reown(m, session));
      }
      if (adopted.length === 0) {
        const who = p.id ?? p.from;
        return {
          content: [text(`No agents to adopt for "${who}" (they may have finished and been delivered elsewhere).`)],
        };
      }
      const lines = adopted.map((m) => {
        const x = readExit(m.id);
        const state = x ? `${x.how}, undelivered` : "running";
        return `- #${ordinalOf(session, m.id)} ${m.role} (${m.model}) ${state} · ${m.label} · ${agentFolder(m.id)}`;
      });
      return {
        content: [
          text(
            `Adopted ${adopted.length} agent(s) into this session:\n${lines.join("\n")}\nYou will be woken when they finish.`,
          ),
        ],
      };
    },
  });

  pi.registerTool({
    name: "subagent_handoff",
    label: "Hand off subagents",
    description:
      "Hand this session's unfinished work to the next session: every running or undelivered agent is marked. " +
      "Prints the subagent_adopt call to run in the next session.",
    parameters: obj({}, []),
    async execute(_id, _params, _signal, _onUpdate, ctx) {
      const session = ctx.sessionManager.getSessionId();
      const mine = owned(listAgents(), session).filter((m) => readExit(m.id) === undefined || !isDelivered(m.id));
      for (const m of mine) writeMeta({ ...m, handoff_from: session });
      const lines = mine.map((m) => `- #${ordinalOf(session, m.id)} ${m.role} (${m.model}) · ${m.label}`);
      const parts = [
        mine.length > 0 ? `Handed off ${mine.length} agent(s) to the next session:` : "No agents to hand off.",
        ...lines,
      ];
      // With nothing to hand off there is no pickup command to print.
      if (mine.length > 0) parts.push(`In the next session, run: subagent_adopt({ from: "${session}" })`);
      return { content: [text(parts.join("\n"))] };
    },
  });
}
