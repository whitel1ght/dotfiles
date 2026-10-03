import type { Theme } from "@earendil-works/pi-coding-agent";
import { matchesKey, truncateToWidth, wrapTextWithAnsi, type Component, type TUI } from "@earendil-works/pi-tui";
import { planLayout, type AgentModelSelection, type ModelSelectionDetails, type ModelSelectionState } from "../selection.ts";

// One screen to choose a model for every agent of a batch. Enter confirms all
// choices at once; Escape cancels them all (the callback gets undefined).
export class ModelPicker implements Component {
  private notice = "";
  private finished = false;
  private readonly state: ModelSelectionState;
  private readonly tui: TUI;
  private readonly theme: Theme;
  private readonly done: (result: readonly AgentModelSelection[] | undefined) => void;

  constructor(
    state: ModelSelectionState,
    tui: TUI,
    theme: Theme,
    done: (result: readonly AgentModelSelection[] | undefined) => void,
  ) {
    this.state = state;
    this.tui = tui;
    this.theme = theme;
    this.done = done;
  }

  invalidate(): void {}

  private finish(result: readonly AgentModelSelection[] | undefined): void {
    if (this.finished) return;
    this.finished = true;
    this.done(result);
  }

  handleInput(data: string): void {
    if (this.finished) return;
    if (matchesKey(data, "escape")) return this.finish(undefined);
    if (matchesKey(data, "enter")) {
      const blocked = this.state.blocked();
      if (!blocked) return this.finish(this.state.result());
      this.notice = blocked.hasAlternative
        ? `${blocked.title}: ${blocked.model} is not available; pick another model`
        : `${blocked.title}: no compatible model is available; esc to cancel`;
    } else {
      this.notice = "";
      if (matchesKey(data, "up")) this.state.moveAgent(-1);
      else if (matchesKey(data, "down")) this.state.moveAgent(1);
      else if (matchesKey(data, "left")) this.state.moveModel(-1);
      else if (matchesKey(data, "right")) this.state.moveModel(1);
    }
    this.tui.requestRender();
  }

  render(width: number): string[] {
    const th = this.theme;
    const wrap = (text: string) => text.split("\n").flatMap((l) => wrapTextWithAnsi(l, width));
    const current = this.state.currentDetails();
    const details = this.detailLines(current).flatMap(wrap);
    const plan = planLayout({
      rows: this.tui.terminal.rows,
      total: this.state.size(),
      active: current.index,
      detailLines: details.length,
      notice: this.notice !== "",
    });
    const { window } = plan;
    const lines: string[] = [];
    if (plan.chrome === "full") {
      const count = this.state.size();
      lines.push(th.fg("accent", th.bold(`Choose models for ${count} subagent${count === 1 ? "" : "s"}`)), "");
    }
    if (plan.indicators && window.start > 0) lines.push(th.fg("dim", `  ↑ ${window.start} more`));
    for (let i = window.start; i < window.end; i++) lines.push(this.row(this.state.detailsAt(i), i === current.index));
    if (plan.indicators && window.end < this.state.size()) lines.push(th.fg("dim", `  ↓ ${this.state.size() - window.end} more`));
    if (plan.chrome === "full") lines.push("");
    lines.push(...details.slice(0, plan.detailLines));
    if (plan.notice) lines.push(th.fg("warning", this.notice));
    if (plan.chrome === "full") lines.push("");
    if (plan.chrome !== "none") lines.push(th.fg("dim", "↑↓ agent • ←→ model • enter confirm all • esc cancel"));
    return lines.map((line) => truncateToWidth(line, width));
  }

  private row(d: ModelSelectionDetails, active: boolean): string {
    const th = this.theme;
    const mark = d.available ? (d.overridden ? th.fg("warning", "override") : th.fg("success", "recommended")) : th.fg("error", "unavailable");
    const text = `${active ? "▶" : " "} ${d.title} [${d.type}] → ${d.metadata.label} (${mark})`;
    return active ? th.bold(text) : text;
  }

  private detailLines(d: ModelSelectionDetails): string[] {
    const th = this.theme;
    const m = d.metadata;
    const state = !d.available
      ? th.fg("error", "unavailable now")
      : d.overridden
        ? th.fg("warning", `override of recommended ${d.recommendedModel}`)
        : th.fg("success", "recommended");
    return [
      th.fg("muted", `── ${d.key} ──`),
      `${d.model} • ${state}`,
      `provider ${m.provider} • quality ${m.quality} • speed ${m.speed} • cost ${m.cost}`,
      `strengths: ${m.strengths.join(", ") || "none listed"}`,
      `rationale: ${d.recommendation}`,
      `fallback: ${d.fallbackChain.map((m) => (d.unavailableFallbacks.includes(m) ? `${m} (unavailable)` : m)).join(" → ")}`,
    ];
  }
}
