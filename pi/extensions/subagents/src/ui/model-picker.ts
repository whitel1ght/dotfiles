import type { Theme } from "@earendil-works/pi-coding-agent";
import { matchesKey, truncateToWidth, wrapTextWithAnsi, type Component, type TUI } from "@earendil-works/pi-tui";
import type { ModelSelectionDetails, ModelSelectionState, AgentModelSelection } from "../selection.ts";

// Lines the frame uses besides the role rows: title, blank, blank, footer keys.
const FRAME_LINES = 4;
const DETAIL_LINES = 12;
const MIN_ROWS = 3;

// One screen to choose a model for every agent of a batch. Enter confirms all
// choices at once; Escape cancels them all (the callback gets undefined).
export class ModelPicker implements Component {
  private notice = "";
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

  handleInput(data: string): void {
    if (matchesKey(data, "escape")) return this.done(undefined);
    if (matchesKey(data, "enter")) {
      if (this.state.canConfirm()) return this.done(this.state.result());
      this.notice = "a chosen model is not available; pick another before confirming";
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
    const window = this.state.window(this.rowCapacity());
    const rows: string[] = [];
    if (window.start > 0) rows.push(th.fg("dim", `  ↑ ${window.start} more`));
    for (let i = window.start; i < window.end; i++) rows.push(this.row(this.state.detailsAt(i), i === this.state.currentDetails().index));
    if (window.end < this.state.size()) rows.push(th.fg("dim", `  ↓ ${this.state.size() - window.end} more`));

    const keys = "↑↓ agent • ←→ model • enter confirm all • esc cancel";
    const lines = [
      th.fg("accent", th.bold(`Choose models for ${this.state.size()} subagent${this.state.size() === 1 ? "" : "s"}`)),
      "",
      ...rows,
      "",
      ...this.detailLines(this.state.currentDetails()).flatMap(wrap),
      ...(this.notice ? [th.fg("warning", this.notice)] : []),
      "",
      th.fg("dim", keys),
    ];
    return lines.map((line) => truncateToWidth(line, width));
  }

  // Rows left for roles once the frame, hint lines and the detail block are counted.
  private rowCapacity(): number {
    return Math.max(MIN_ROWS, this.tui.terminal.rows - FRAME_LINES - DETAIL_LINES - 2);
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
      `fallback: ${d.fallbackChain.join(" → ")}`,
    ];
  }
}
