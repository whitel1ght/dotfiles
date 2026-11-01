import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { resolve } from "node:path";
import { describe, DEFAULT_TAIL_LINES, MAX_TAIL_LINES, renderOutput, wakeMessage } from "./src/format.ts";
import { TerminalManager, type Terminal } from "./src/manager.ts";
import { BG_LIST, BG_OUTPUT, BG_START, BG_STOP } from "./src/prompt.ts";
import { TerminalView } from "./src/ui/view.ts";
import { WakeQueue } from "./src/wake-queue.ts";

const WIDGET = "bg-terminals";
const WAKE_TYPE = "bg-terminal-exit";

const text = (value: string) => ({ type: "text" as const, text: value });

export default function (pi: ExtensionAPI) {
  const manager = new TerminalManager();
  const wake = new WakeQueue<Terminal>();
  // The most recent context, kept to ask whether the agent is idle and to draw
  // the widget. Dropped at shutdown, since a stale context may throw.
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
      { customType: WAKE_TYPE, content: wakeMessage(finished), display: true, details: { ids: finished.map((t) => t.id) } },
      { triggerTurn: true },
    );
  };

  const updateWidget = () => {
    if (!ctx?.hasUI) return;
    const n = manager.running().length;
    ctx.ui.setWidget(WIDGET, n ? [`● ${n} background terminal${n === 1 ? "" : "s"} running • /ps to view`] : undefined);
  };

  manager.onChange(updateWidget);
  manager.onExit((terminal) => {
    // A stop the model asked for is already in its context; only unprompted exits wake it.
    if (terminal.status === "stopped") return;
    wake.defer(terminal);
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

  const lookup = (id: string): Terminal => {
    const terminal = manager.get(id);
    if (!terminal) {
      const known = manager.list().map((t) => t.id).join(", ") || "none";
      throw new Error(`unknown background terminal ${id} (known: ${known})`);
    }
    return terminal;
  };

  pi.registerTool({
    name: "bg_start",
    label: "Background terminal",
    description: BG_START.description,
    promptSnippet: BG_START.snippet,
    promptGuidelines: BG_START.guidelines,
    parameters: Type.Object({
      command: Type.String({ description: "Shell command to run (executed with bash -c)" }),
      title: Type.Optional(Type.String({ description: "Short label shown in /ps and in notifications" })),
      cwd: Type.Optional(Type.String({ description: "Working directory (default: the session directory)" })),
    }),
    async execute(_id, params, _signal, _onUpdate, context) {
      ctx = context;
      const terminal = manager.start({
        command: params.command,
        title: params.title,
        cwd: params.cwd ? resolve(context.cwd, params.cwd) : context.cwd,
      });
      return {
        content: [text(`Started ${describe(terminal)}. You will be told when it exits. Output: bg_output ${terminal.id}.`)],
        details: { id: terminal.id },
      };
    },
  });

  pi.registerTool({
    name: "bg_list",
    label: "Background terminals",
    description: BG_LIST.description,
    parameters: Type.Object({}),
    async execute() {
      const lines = manager.list().map((t) => describe(t));
      return { content: [text(lines.join("\n") || "No background terminals.")], details: undefined };
    },
  });

  pi.registerTool({
    name: "bg_output",
    label: "Background terminal output",
    description: BG_OUTPUT.description,
    parameters: Type.Object({
      id: Type.String({ description: "Terminal id, e.g. bg-1" }),
      stream: Type.Optional(StringEnum(["both", "stdout", "stderr"] as const, { description: "Which stream (default both)" })),
      lines: Type.Optional(
        Type.Number({ description: `How many trailing lines per stream (default ${DEFAULT_TAIL_LINES}, max ${MAX_TAIL_LINES})` }),
      ),
    }),
    async execute(_id, params) {
      const terminal = lookup(params.id);
      if (terminal.status !== "running") wake.consume(terminal.id);
      return {
        content: [text(renderOutput(terminal, params.stream ?? "both", params.lines ?? DEFAULT_TAIL_LINES))],
        details: { id: terminal.id, status: terminal.status },
      };
    },
  });

  pi.registerTool({
    name: "bg_stop",
    label: "Stop background terminal",
    description: BG_STOP.description,
    parameters: Type.Object({
      id: Type.String({ description: "Terminal id, e.g. bg-1" }),
      force: Type.Optional(Type.Boolean({ description: "SIGKILL immediately instead of asking nicely first" })),
    }),
    async execute(_id, params) {
      const terminal = lookup(params.id);
      const was = terminal.status;
      wake.consume(terminal.id);
      await manager.stop(terminal.id, params.force ?? false);
      return {
        content: [text(was === "running" ? `Stopped ${describe(terminal)}` : `${describe(terminal)} had already finished.`)],
        details: { id: terminal.id, status: terminal.status },
      };
    },
  });

  pi.registerCommand("ps", {
    description: "List and inspect background terminals",
    handler: async (_args, context) => {
      ctx = context;
      for (;;) {
        const terminals = manager.list();
        if (!terminals.length) {
          context.ui.notify("No background terminals.", "info");
          return;
        }
        const choice = await context.ui.select("Background terminals", terminals.map((t) => describe(t)));
        if (!choice) return;
        const id = choice.split(" ")[0];
        wake.consume(id);
        await context.ui.custom<void>((tui, theme, _keys, done) => new TerminalView(manager, id, tui, theme, () => done()));
      }
    },
  });
}
