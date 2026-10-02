import type { Theme } from "@earendil-works/pi-coding-agent";
import { matchesKey, truncateToWidth, wrapTextWithAnsi, type Component, type TUI } from "@earendil-works/pi-tui";
import { sliceWindow } from "../../../background-terminals/src/format.ts";
import { result, type AgentManager } from "../agents.ts";
import { attemptLine, describe } from "../format.ts";

const REFRESH_MS = 500;

// Full-screen view of one subagent: its task, what it has done, and its answer.
export class AgentView implements Component {
  private fromBottom = 0;
  private stopping = false;
  private readonly timer: ReturnType<typeof setInterval>;
  private readonly manager: AgentManager;
  private readonly id: string;
  private readonly tui: TUI;
  private readonly theme: Theme;
  private readonly done: () => void;

  constructor(manager: AgentManager, id: string, tui: TUI, theme: Theme, done: () => void) {
    this.manager = manager;
    this.id = id;
    this.tui = tui;
    this.theme = theme;
    this.done = done;
    this.timer = setInterval(() => this.tui.requestRender(), REFRESH_MS);
  }

  dispose(): void {
    clearInterval(this.timer);
  }

  invalidate(): void {}

  handleInput(data: string): void {
    const page = Math.max(1, this.bodyHeight() - 1);
    if (matchesKey(data, "escape") || data === "q") return this.done();
    if (matchesKey(data, "up") || data === "k") this.fromBottom += 1;
    else if (matchesKey(data, "down") || data === "j") this.fromBottom -= 1;
    else if (matchesKey(data, "pageUp") || matchesKey(data, "ctrl+u")) this.fromBottom += page;
    else if (matchesKey(data, "pageDown") || matchesKey(data, "ctrl+d")) this.fromBottom -= page;
    else if (matchesKey(data, "end") || data === "G") this.fromBottom = 0;
    else if (data === "x" && !this.stopping && this.manager.get(this.id)?.status === "running") {
      this.stopping = true;
      void this.manager.stop(this.id).finally(() => {
        this.stopping = false;
        this.tui.requestRender();
      });
    }
    this.fromBottom = Math.max(0, this.fromBottom);
    this.tui.requestRender();
  }

  render(width: number): string[] {
    const agent = this.manager.get(this.id);
    const th = this.theme;
    if (!agent) return [th.fg("error", "subagent no longer exists")];

    const window = sliceWindow(this.bodyLines(width), this.bodyHeight(), this.fromBottom);
    this.fromBottom = window.offset;
    const scroll = window.offset > 0 ? `${window.offset} lines above the end` : "following";
    const keys = th.fg("dim", `↑↓/jk ctrl+u/d scroll • G follow${agent.status === "running" ? " • x stop" : ""} • esc close • ${scroll}`);
    return [th.fg("accent", th.bold(describe(agent))), "", ...window.lines, "", keys].map((line) => truncateToWidth(line, width));
  }

  private bodyHeight(): number {
    return Math.max(5, this.tui.terminal.rows - 5);
  }

  private bodyLines(width: number): string[] {
    const agent = this.manager.get(this.id)!;
    const th = this.theme;
    const wrap = (text: string) => text.split("\n").flatMap((l) => wrapTextWithAnsi(l, width));
    const lines = [th.fg("muted", "── task ──"), ...wrap(agent.task)];
    for (const attempt of agent.attempts) {
      const head = attemptLine(attempt).slice(2);
      const colour = attempt.outcome === "done" ? "success" : attempt.outcome === "running" || attempt.outcome === "pinging" ? "accent" : "warning";
      lines.push(...wrap(th.fg(colour, `── ${head}`)));
      for (const a of attempt.run?.activity ?? []) lines.push(...wrap(a.kind === "tool" ? th.fg("dim", `→ ${a.text}`) : a.text));
    }
    if (agent.status === "done") lines.push(th.fg("muted", "── result ──"), ...wrap(result(agent)));
    if (agent.failure) lines.push(th.fg("error", `failed: ${agent.failure}`));
    return lines;
  }
}
