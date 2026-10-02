import type { Theme } from "@earendil-works/pi-coding-agent";
import { matchesKey, truncateToWidth, wrapTextWithAnsi, type Component, type TUI } from "@earendil-works/pi-tui";
import { describe, formatBytes, sliceWindow } from "../format.ts";
import type { TerminalManager } from "../manager.ts";

type Mode = "both" | "stdout" | "stderr";
const MODES: Mode[] = ["both", "stdout", "stderr"];
const REFRESH_MS = 500;

// Full-screen view of one terminal: live tail of its output, scrollable.
export class TerminalView implements Component {
  private mode: Mode = "both";
  private fromBottom = 0;
  private stopping = false;
  private readonly timer: ReturnType<typeof setInterval>;
  private readonly manager: TerminalManager;
  private readonly id: string;
  private readonly tui: TUI;
  private readonly theme: Theme;
  private readonly done: () => void;

  constructor(manager: TerminalManager, id: string, tui: TUI, theme: Theme, done: () => void) {
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
    if (matchesKey(data, "tab")) {
      this.mode = MODES[(MODES.indexOf(this.mode) + 1) % MODES.length];
      this.fromBottom = 0;
    } else if (matchesKey(data, "up") || data === "k") this.fromBottom += 1;
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
    const t = this.manager.get(this.id);
    const th = this.theme;
    if (!t) return [th.fg("error", "terminal no longer exists")];

    const body = this.bodyLines(width);
    const window = sliceWindow(body, this.bodyHeight(), this.fromBottom);
    this.fromBottom = window.offset;

    const scroll = window.offset > 0 ? ` • ${window.offset} lines above the end` : " • following";
    const head = th.fg("accent", th.bold(describe(t)));
    const sub = th.fg("muted", `${this.mode} • ${formatBytes(t.stdout.totalBytes)} out, ${formatBytes(t.stderr.totalBytes)} err${scroll}`);
    const keys = th.fg("dim", `tab stream • ↑↓/jk ctrl+u/d scroll • G follow${t.status === "running" ? " • x stop" : ""} • esc close`);

    return [head, sub, "", ...window.lines, "", keys].map((line) => truncateToWidth(line, width));
  }

  private bodyHeight(): number {
    return Math.max(5, this.tui.terminal.rows - 6);
  }

  private bodyLines(width: number): string[] {
    const t = this.manager.get(this.id)!;
    const section = (name: string, text: string) => [
      this.theme.fg("muted", `── ${name} ──`),
      ...(text ? text.replace(/\n$/, "").split("\n").flatMap((l) => wrapTextWithAnsi(l, width)) : [this.theme.fg("dim", "(empty)")]),
    ];
    return [
      ...(this.mode !== "stderr" ? section("stdout", t.stdout.text()) : []),
      ...(this.mode !== "stdout" ? section("stderr", t.stderr.text()) : []),
    ];
  }
}
