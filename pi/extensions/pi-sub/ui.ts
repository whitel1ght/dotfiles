// The agents overlay: pure rendering (list, opened agent, footer) plus the
// component class pi shows with ctx.ui.custom. No pi imports at runtime, so
// everything here runs under plain `node --test`.

import { activity, stats } from "./events.ts";
import { byStartedAt } from "./helpers.ts";
import { initialView, reduce, translate, type Action, type Row, type View } from "./keys.ts";
import { formatDur } from "./runtime.ts";
import { orphans, owned, readExit, type Exit, type Meta } from "./state.ts";

const GLYPH: Record<string, string> = { run: "● run", done: "✓ done", failed: "✗ fail", stopped: "■ stop" };

/** Rows the list shows: this session's agents (by #N), then orphans. */
export function visibleRows(
  all: Meta[],
  session: string,
  view: Pick<View, "showFinished" | "filter">,
  now: Date,
  alive: (pid: number) => boolean,
): Row[] {
  const today = now.toDateString();
  const keep = (m: Meta, x: Exit | undefined) => {
    if (x && !view.showFinished && new Date(x.ended_at).toDateString() !== today) return false;
    const f = view.filter.toLowerCase();
    return !f || [m.role, m.model, m.label].some((s) => s.toLowerCase().includes(f));
  };
  const mine = owned(all, session)
    .sort(byStartedAt)
    .map((meta, i): Row => ({ meta, exit: readExit(meta.id), ordinal: i + 1, orphan: false }));
  const lost = orphans(all, session, alive)
    .sort(byStartedAt)
    .map((meta): Row => ({ meta, exit: readExit(meta.id), orphan: true }));
  return [...mine, ...lost].filter((r) => keep(r.meta, r.exit));
}

/** Cut or pad to exactly `width` columns (one column per code point). */
export function fit(s: string, width: number): string {
  const cps = [...s.replace(/[\x00-\x1f\x7f]/g, " ")];
  if (cps.length > width) return width <= 0 ? "" : `${cps.slice(0, width - 1).join("")}…`;
  return cps.join("") + " ".repeat(width - cps.length);
}

/** Wrap into lines of at most `width` columns. */
function wrap(s: string, width: number): string[] {
  const cps = [...s.replace(/[\x00-\x1f\x7f]/g, " ")];
  if (cps.length === 0) return [""];
  const out: string[] = [];
  for (let i = 0; i < cps.length; i += width) out.push(cps.slice(i, i + width).join(""));
  return out;
}

/** Pi's theme, narrowed to what the overlay paints with; `plain` leaves text as is. */
export type Paint = {
  fg: (color: string, s: string) => string;
  bg: (color: string, s: string) => string;
  bold: (s: string) => string;
};
export const plain: Paint = { fg: (_c, s) => s, bg: (_c, s) => s, bold: (s) => s };

/** A run of text with its theme colour and weight. */
type Seg = [text: string, color?: string, bold?: boolean];

const STATE_COLOR: Record<string, string> = { run: "accent", done: "success", failed: "error", stopped: "warning" };

/** Lay segments out in exactly `width` columns, then colour each piece that survived the cut. */
function paint(parts: Seg[], width: number, p: Paint): string {
  const cps = [...fit(parts.map(([t]) => t).join(""), width)];
  let at = 0;
  let out = "";
  for (const [t, color, strong] of parts) {
    const piece = cps.slice(at, at + [...t].length).join("");
    at += [...t].length;
    if (!piece) continue;
    const c = color ? p.fg(color, piece) : piece;
    out += strong ? p.bold(c) : c;
  }
  return out + cps.slice(at).join("");
}

const edge = (s: string, p: Paint) => p.fg("borderMuted", s);
const top = (title: Seg[], width: number, p: Paint) => {
  const inner = Math.max(0, width - 2);
  const tw = Math.min([...title.map(([t]) => t).join("")].length, Math.max(0, inner - 4));
  return `${edge("╭─ ", p)}${paint(title, tw, p)}${edge(` ${"─".repeat(Math.max(0, inner - tw - 3))}╮`, p)}`;
};
const rule = (width: number, p: Paint) => edge(`├${"─".repeat(Math.max(0, width - 2))}┤`, p);
const bottom = (width: number, p: Paint) => edge(`╰${"─".repeat(Math.max(0, width - 2))}╯`, p);
const line = (s: string | Seg[], width: number, p: Paint, bg?: string) => {
  const body = paint([[" "], ...(typeof s === "string" ? [[s] as Seg] : s)], Math.max(0, width - 2), p);
  return `${edge("│", p)}${bg ? p.bg(bg, body) : body}${edge("│", p)}`;
};
const centered = (s: string, color: string, width: number, bold = false): Seg[] => [
  [" ".repeat(Math.max(0, Math.floor((width - 3 - [...s].length) / 2)))],
  [s, color, bold],
];

/** "j/k move · l open" → keys in the accent colour, their meaning dimmed. */
function help(text: string): Seg[] {
  return text.split(" · ").flatMap((item, i): Seg[] => {
    const sp = item.indexOf(" ");
    const key = sp < 0 ? item : item.slice(0, sp);
    return [...(i ? [[" · ", "dim"] as Seg] : []), [key, "accent"], [sp < 0 ? "" : item.slice(sp), "dim"]];
  });
}

function state(r: Row): string {
  return GLYPH[r.exit ? r.exit.how : "run"];
}

function stateColor(r: Row): string {
  return STATE_COLOR[r.exit ? r.exit.how : "run"];
}

function took(r: Row, now: number): string {
  const end = r.exit ? Date.parse(r.exit.ended_at) : now;
  return formatDur(end - Date.parse(r.meta.started_at));
}

/** Show the bare model id unless another row has the same id under another provider. */
function modelLabel(model: string, rows: Row[]): string {
  const bare = model.split("/").slice(1).join("/") || model;
  const clash = rows.some((r) => r.meta.model !== model && r.meta.model.endsWith(`/${bare}`));
  return clash ? model : bare;
}

export function counts(rows: Row[]): Record<"run" | "done" | "failed" | "stopped", number> {
  const c = { run: 0, done: 0, failed: 0, stopped: 0 };
  for (const r of rows) c[r.exit ? r.exit.how : "run"]++;
  return c;
}

/** Bottom line for confirm / note / search; undefined in plain list/agent mode. */
function promptLine(view: View, rows: Row[], events: object[] | undefined, now: number): string | undefined {
  const target = rows.find((r) => r.meta.id === view.openId);
  const who = target ? `${target.ordinal !== undefined ? `#${target.ordinal}` : target.meta.id} ${target.meta.role}` : view.openId ?? "";
  if (view.mode === "confirm") {
    const touched = events ? filesTouched(events) : 0;
    const t = target ? ` (${modelLabel(target.meta.model, rows)}, ${took(target, now)})` : "";
    return `Stop ${who}${t}? It has edited ${touched} file${touched === 1 ? "" : "s"}. y stop · n cancel`;
  }
  if (view.mode === "note") return `Flag ${who} to main · note: ${view.input ?? ""}▍ · enter send · esc cancel`;
  if (view.mode === "search") return `/${view.input ?? ""}▍ · enter ${view.back === "list" ? "keep filter" : "search"} · esc cancel`;
  return undefined;
}

/** The bottom line: a prompt coloured by its mode, else the key help. */
function promptRow(view: View, rows: Row[], events: object[] | undefined, now: number, keys: string): Seg[] {
  const prompt = promptLine(view, rows, events, now);
  if (prompt === undefined) return help(keys);
  return [[prompt, view.mode === "confirm" ? "warning" : "accent"]];
}

const LIST_KEYS = "j/k move · l open · x stop · m flag to main · / filter · zf finished · q close";

export function renderList(
  view: View,
  rows: Row[],
  width: number,
  height: number,
  now: number,
  session: string,
  p: Paint = plain,
  events?: object[],
): string[] {
  const mine = rows.filter((r) => !r.orphan);
  const c = counts(mine);
  const title: Seg[] = [["Subagents", "accent", true], [` · session ${session.slice(0, 8)}`, "dim"]];
  const count = (n: number, what: string, color: string, always = false) => {
    if (n || always) title.push([" · ", "dim"], [`${n} ${what}`, n ? color : "dim"]);
  };
  if (mine.length) {
    count(c.run, "running", "accent", true);
    count(c.done, "done", "success", true);
    count(c.failed, "failed", "error");
    count(c.stopped, "stopped", "warning");
  }
  if (view.filter) title.push([" · ", "dim"], [`filter "${view.filter}"`, "warning"]);
  const out = [top(title, width, p)];
  const cols = (n: string, st: string, role: string, model: string, time: string, task: string, r?: Row): Seg[] => [
    [`${n.padStart(3)}  `, "dim"],
    [fit(st, 7), r && stateColor(r)],
    ["  "],
    [fit(role, 20), r && "text", !!r],
    ["  "],
    [fit(model, 24), "muted"],
    ["  "],
    [time.padStart(8), "dim"],
    ["  "],
    [task, r && "text"],
  ];
  if (rows.length) out.push(line([[" "], ...cols("#", "state", "role", "model", "time", "task").map(([t]): Seg => [t, "dim"])], width, p));
  const body: { segs: Seg[]; cursor?: boolean }[] = [];
  const cursor = Math.min(view.cursor, Math.max(0, rows.length - 1));
  let cursorLine = 0;
  rows.forEach((r, i) => {
    if (r.orphan && (i === 0 || !rows[i - 1].orphan))
      body.push({ segs: [["orphans — owner session gone (x stops; subagent_adopt takes over)", "warning"]] });
    if (i === cursor) cursorLine = body.length;
    const n = r.ordinal !== undefined ? String(r.ordinal) : "·";
    body.push({
      segs: [[i === cursor ? "▸" : " ", "accent", true], ...cols(n, state(r), r.meta.role, modelLabel(r.meta.model, rows), took(r, now), r.meta.label, r)],
      cursor: i === cursor,
    });
  });
  if (rows.length === 0) {
    const [head, hint] = view.filter
      ? [`No agents match "${view.filter}"`, "press / to change the filter"]
      : ["No agents active", "agents launched with the subagent tool show up here"];
    body.push({ segs: [] }, { segs: centered(head, "text", width, true) }, { segs: centered(hint, "dim", width) }, { segs: [] });
  }
  const room = Math.max(1, height - 5);
  const start = Math.max(0, Math.min(cursorLine - room + 1, body.length - room));
  for (const b of body.slice(start, start + room)) out.push(line(b.segs, width, p, b.cursor ? "selectedBg" : undefined));
  out.push(rule(width, p));
  out.push(line(promptRow(view, rows, events, now, LIST_KEYS), width, p));
  out.push(bottom(width, p));
  return out;
}

/** Distinct files a write-capable agent has edited or written, from its tool calls. */
export function filesTouched(events: object[]): number {
  const paths = new Set<string>();
  for (const ev of events as Record<string, any>[]) {
    if (ev?.type !== "tool_execution_start") continue;
    if (ev.toolName !== "edit" && ev.toolName !== "write") continue;
    const p = ev.args?.path ?? ev.args?.file_path;
    if (typeof p === "string") paths.add(p);
  }
  return paths.size;
}

/** The opened agent's log as logical lines: activity, then the result once finished. */
export function agentLog(events: object[], result: string | undefined): string[] {
  const label: Record<string, string> = { tool: "tool ", think: "think", text: "text ", stream: "▍    " };
  const out = activity(events).map((a) => `${label[a.kind]} ${a.text.replace(/\s*\n\s*/g, " ⏎ ")}`);
  if (result !== undefined) {
    out.push("── result ──");
    out.push(...result.replace(/\n$/, "").split("\n"));
  }
  return out;
}

/** Log lines one screen of the opened agent holds at this height. */
export function agentPage(view: View, task: string, height: number, width: number): number {
  const taskLines = view.showTask ? wrap(task, Math.max(1, width - 9)).length : 1;
  return Math.max(1, height - 6 - taskLines);
}

export function renderAgent(
  view: View,
  row: Row,
  rows: Row[],
  events: object[],
  log: string[],
  width: number,
  height: number,
  now: number,
  p: Paint = plain,
): string[] {
  const m = row.meta;
  const s = stats(events);
  const st = row.exit ? row.exit.how : "running";
  const n = row.ordinal !== undefined ? `#${row.ordinal}` : m.id;
  const tok = s.tokensIn >= 1000 ? `${Math.round(s.tokensIn / 1000)}k` : String(s.tokensIn);
  const out = [
    top(
      [
        [n, "accent", true],
        [` ${m.role}`, "text", true],
        [` · ${modelLabel(m.model, rows)}`, "muted"],
        [" · ", "dim"],
        [`${st} ${took(row, now)}`, stateColor(row)],
        [` · ${s.toolCalls} tool calls · ${tok} tok in`, "dim"],
      ],
      width,
      p,
    ),
  ];
  const inner = Math.max(1, width - 4);
  out.push(line([["cwd  ", "dim"], [m.cwd]], width, p));
  if (view.showTask) {
    for (const [i, t] of wrap(m.task, Math.max(1, inner - 5)).entries()) out.push(line([[i === 0 ? "task " : "     ", "dim"], [t]], width, p));
  } else {
    out.push(line([["task ", "dim"], [fit(m.task.split("\n")[0], Math.max(1, inner - 10)).trimEnd()], ["  [t] full", "dim"]], width, p));
  }
  out.push(rule(width, p));
  const page = agentPage(view, m.task, height, width);
  const shown = view.expand ? log.flatMap((l) => wrap(l, inner)) : log;
  const maxScroll = Math.max(0, shown.length - page);
  const start = view.follow ? maxScroll : Math.min(view.scroll, maxScroll);
  const slice = shown.slice(start, start + page);
  for (const l of slice) out.push(line(logSegs(l), width, p));
  for (let i = slice.length; i < page; i++) out.push(line(i === 0 && shown.length === 0 ? [["(no activity yet)", "dim"]] : "", width, p));
  out.push(rule(width, p));
  const keys = `j/k scroll · G follow${view.follow ? " (on)" : ""} · l wrap · / search · t task · x stop · m flag · h back`;
  out.push(line(promptRow(view, rows, events, now, keys), width, p));
  out.push(bottom(width, p));
  return out;
}

/** Colour a log line by the kind label agentLog gave it. */
function logSegs(l: string): Seg[] {
  if (l === "── result ──") return [[l, "success", true]];
  if (l.startsWith("tool ")) return [["tool ", "accent"], [l.slice(5)]];
  if (l.startsWith("think ")) return [[l, "dim"]];
  if (l.startsWith("text ")) return [["text ", "muted"], [l.slice(5)]];
  if (l.startsWith("▍")) return [[l, "muted"]];
  return [[l]];
}

/** Footer status for this session's agents; undefined (cleared) when it has none. */
export function footerText(mine: Row[], hotkey = "ctrl+space"): string | undefined {
  if (mine.length === 0) return undefined;
  const c = counts(mine);
  return `subagents ●${c.run} run ✓${c.done} ✗${c.failed} ■${c.stopped}  ${hotkey}`;
}

export type OverlayDeps = {
  session: string;
  /** All agents on disk, re-read on every render. */
  agents: () => Meta[];
  alive: (pid: number) => boolean;
  events: (id: string) => object[];
  result: (id: string) => string | undefined;
  /** Raw terminal input → key name (keys.ts keyName, or pi-tui's parser). */
  parse: (data: string) => string | undefined;
  rebinds: Record<string, string>;
  rowsOnScreen: () => number;
  onAction: (a: Action) => void;
  done: () => void;
  requestRender: () => void;
  now?: () => number;
  /** Pi's theme; plain text without it. */
  paint?: Paint;
};

/** The component ctx.ui.custom shows; redraws every second while open. */
export class AgentsOverlay {
  view: View;
  private readonly deps: OverlayDeps;
  private timer?: ReturnType<typeof setInterval>;

  constructor(deps: OverlayDeps, openId?: string) {
    this.deps = deps;
    this.view = initialView();
    if (openId) this.view = { ...this.view, mode: "agent", openId };
    this.timer = setInterval(() => deps.requestRender(), 1000);
    this.timer.unref?.();
  }

  private rows(): Row[] {
    return visibleRows(this.deps.agents(), this.deps.session, this.view, new Date(this.now()), this.deps.alive);
  }

  private now(): number {
    return (this.deps.now ?? Date.now)();
  }

  /** The opened agent's row: from the list, or read directly if filtered out. */
  private opened(rows: Row[]): Row | undefined {
    const id = this.view.openId;
    if (!id) return undefined;
    const r = rows.find((x) => x.meta.id === id);
    if (r) return r;
    const m = this.deps.agents().find((x) => x.id === id);
    return m ? { meta: m, exit: readExit(m.id), orphan: m.owner_session !== this.deps.session } : undefined;
  }

  private inAgent(): boolean {
    return this.view.mode === "agent" || (this.view.back === "agent" && this.view.mode !== "list");
  }

  handleInput(data: string): void {
    const raw = this.deps.parse(data);
    if (raw === undefined) return;
    const key = translate(raw, this.deps.rebinds, this.view.mode);
    const rows = this.rows();
    const h = this.deps.rowsOnScreen();
    let log: string[] | undefined;
    let page = Math.max(1, h - 5);
    const r = this.inAgent() ? this.opened(rows) : undefined;
    if (r) {
      log = agentLog(this.deps.events(r.meta.id), r.exit ? this.deps.result(r.meta.id) : undefined);
      page = agentPage(this.view, r.meta.task, h, 80);
    }
    const next = reduce(this.view, key, rows, { page, log });
    this.view = next.view;
    if (next.action?.close) {
      this.dispose();
      this.deps.done();
      return;
    }
    if (next.action) this.deps.onAction(next.action);
    this.deps.requestRender();
  }

  render(width: number): string[] {
    const rows = this.rows();
    const h = this.deps.rowsOnScreen();
    const r = this.inAgent() ? this.opened(rows) : undefined;
    if (r) {
      const events = this.deps.events(r.meta.id);
      const log = agentLog(events, r.exit ? this.deps.result(r.meta.id) : undefined);
      return renderAgent(this.view, r, rows, events, log, width, h, this.now(), this.deps.paint);
    }
    if (this.view.mode === "agent") this.view = { ...this.view, mode: "list" };
    const events = this.view.mode === "confirm" && this.view.openId ? this.deps.events(this.view.openId) : undefined;
    return renderList(this.view, rows, width, h, this.now(), this.deps.session, this.deps.paint, events);
  }

  invalidate(): void {}

  dispose(): void {
    if (this.timer !== undefined) clearInterval(this.timer);
    this.timer = undefined;
  }
}
