// The overlay's key handling as a pure reducer: (view, key, rows) → next view
// plus an optional action for the caller to perform. No pi imports, so it
// runs under plain `node --test`.

import type { Exit, Meta } from "./state.ts";

export type Mode = "list" | "agent" | "confirm" | "note" | "search";

export type View = {
  mode: Mode;
  /** List: selected row. */
  cursor: number;
  /** Opened agent: first log line shown (ignored while following). */
  scroll: number;
  /** Opened agent: stick to the bottom as the log grows. */
  follow: boolean;
  /** Show finished agents of earlier days too (today's are always shown). */
  showFinished: boolean;
  /** List filter on role/model/label. */
  filter: string;
  /** First key of a two-key chord (gg, zf). */
  pending?: "g" | "z";
  /** The agent opened, or the target of confirm/note. */
  openId?: string;
  /** Where confirm/note/search return to. */
  back?: "list" | "agent";
  /** Text being typed in note or search mode. */
  input?: string;
  /** Opened agent: last search term, for n/N. */
  search?: string;
  /** Opened agent: show the whole task instead of its first line. */
  showTask?: boolean;
  /** Opened agent: wrap long log lines instead of cutting them. */
  expand?: boolean;
};

export type Row = {
  meta: Meta;
  exit?: Exit;
  /** #N for this session's agents; orphans have none. */
  ordinal?: number;
  orphan: boolean;
};

export type Action = { stop?: string; flag?: { id: string; note: string }; close?: true };

export type ReduceOpts = {
  /** Rows (list) or log lines (agent) one screen holds. */
  page?: number;
  /** The opened agent's log lines, for scrolling bounds and search. */
  log?: string[];
};

export function initialView(): View {
  return { mode: "list", cursor: 0, scroll: 0, follow: true, showFinished: false, filter: "" };
}

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n));

export function reduce(
  view: View,
  key: string,
  rows: Row[],
  opts: ReduceOpts = {},
): { view: View; action?: Action } {
  switch (view.mode) {
    case "list":
      return listKey(view, key, rows, opts);
    case "agent":
      return agentKey(view, key, opts);
    case "confirm":
      return confirmKey(view, key);
    case "note":
    case "search":
      return inputKey(view, key, opts);
  }
}

function listKey(view: View, key: string, rows: Row[], opts: ReduceOpts): { view: View; action?: Action } {
  const last = Math.max(0, rows.length - 1);
  const half = Math.max(1, Math.floor((opts.page ?? 10) / 2));
  const v: View = { ...view, pending: undefined };
  const row = rows[clamp(view.cursor, 0, last)];
  if (view.pending === "g" && key === "g") return { view: { ...v, cursor: 0 } };
  if (view.pending === "z" && key === "f") return { view: { ...v, showFinished: !view.showFinished, cursor: 0 } };
  switch (key) {
    case "j":
    case "down":
      return { view: { ...v, cursor: clamp(view.cursor + 1, 0, last) } };
    case "k":
    case "up":
      return { view: { ...v, cursor: clamp(view.cursor - 1, 0, last) } };
    case "g":
      return { view: { ...v, pending: "g" } };
    case "z":
      return { view: { ...v, pending: "z" } };
    case "G":
      return { view: { ...v, cursor: last } };
    case "ctrl+d":
      return { view: { ...v, cursor: clamp(view.cursor + half, 0, last) } };
    case "ctrl+u":
      return { view: { ...v, cursor: clamp(view.cursor - half, 0, last) } };
    case "l":
    case "enter":
      if (!row) return { view: v };
      return { view: { ...v, mode: "agent", openId: row.meta.id, scroll: 0, follow: true, showTask: false, expand: false } };
    case "/":
      return { view: { ...v, mode: "search", back: "list", input: view.filter } };
    case "x":
      if (!row || row.exit) return { view: v };
      return { view: { ...v, mode: "confirm", openId: row.meta.id, back: "list" } };
    case "m":
      if (!row) return { view: v };
      return { view: { ...v, mode: "note", openId: row.meta.id, back: "list", input: "" } };
    case "q":
    case "esc":
      return { view: v, action: { close: true } };
    default:
      return { view: v };
  }
}

function agentKey(view: View, key: string, opts: ReduceOpts): { view: View; action?: Action } {
  const log = opts.log ?? [];
  const page = opts.page ?? 10;
  const maxScroll = Math.max(0, log.length - page);
  const half = Math.max(1, Math.floor(page / 2));
  // While following, the screen shows the bottom: scrolling starts from there.
  const from = view.follow ? maxScroll : clamp(view.scroll, 0, maxScroll);
  const v: View = { ...view, pending: undefined };
  const at = (n: number): View => ({ ...v, follow: false, scroll: clamp(n, 0, maxScroll) });
  if (view.pending === "g" && key === "g") return { view: at(0) };
  switch (key) {
    case "j":
    case "down":
      return { view: at(from + 1) };
    case "k":
    case "up":
      return { view: at(from - 1) };
    case "ctrl+d":
      return { view: at(from + half) };
    case "ctrl+u":
      return { view: at(from - half) };
    case "g":
      return { view: { ...v, pending: "g" } };
    case "G":
      return { view: { ...v, follow: true, scroll: maxScroll } };
    case "l":
    case "enter":
      return { view: { ...v, expand: !view.expand } };
    case "t":
      return { view: { ...v, showTask: !view.showTask } };
    case "/":
      return { view: { ...v, mode: "search", back: "agent", input: "" } };
    case "n":
    case "N": {
      if (!view.search) return { view: v };
      const hit = findMatch(log, view.search, from, key === "n" ? 1 : -1);
      return { view: hit === undefined ? v : at(hit) };
    }
    case "x":
      return { view: { ...v, mode: "confirm", back: "agent" } };
    case "m":
      return { view: { ...v, mode: "note", back: "agent", input: "" } };
    case "h":
    case "q":
    case "esc":
      return { view: { ...v, mode: "list", search: undefined } };
    default:
      return { view: v };
  }
}

/** Next (dir 1) or previous (dir -1) log line containing `term`, wrapping. */
function findMatch(log: string[], term: string, from: number, dir: 1 | -1): number | undefined {
  const t = term.toLowerCase();
  for (let i = 1; i <= log.length; i++) {
    const idx = (((from + dir * i) % log.length) + log.length) % log.length;
    if (log[idx].toLowerCase().includes(t)) return idx;
  }
  return undefined;
}

function confirmKey(view: View, key: string): { view: View; action?: Action } {
  const back: View = { ...view, mode: view.back ?? "list" };
  if (key === "y" && view.openId) return { view: back, action: { stop: view.openId } };
  if (key === "n" || key === "esc" || key === "q") return { view: back };
  return { view };
}

function inputKey(view: View, key: string, opts: ReduceOpts): { view: View; action?: Action } {
  const back: View = { ...view, mode: view.back ?? "list", input: undefined };
  const input = view.input ?? "";
  if (key === "esc") {
    // Cancelling a list filter clears it; cancelling a note or log search keeps state.
    return { view: view.mode === "search" && view.back === "list" ? { ...back, filter: "", cursor: 0 } : back };
  }
  if (key === "enter") {
    if (view.mode === "note") {
      return view.openId ? { view: back, action: { flag: { id: view.openId, note: input.trim() } } } : { view: back };
    }
    if (view.back === "list") return { view: { ...back, filter: input, cursor: 0 } };
    // Log search: jump to the first match from the top of the current screen.
    const hit = input ? findMatch(opts.log ?? [], input, view.scroll - 1, 1) : undefined;
    return { view: { ...back, search: input || undefined, ...(hit !== undefined ? { scroll: hit, follow: false } : {}) } };
  }
  if (key === "backspace") return { view: { ...view, input: [...input].slice(0, -1).join("") } };
  if (key === "space") return { view: { ...view, input: `${input} ` } };
  if ([...key].length === 1) {
    const next = { ...view, input: input + key };
    // The list filter applies as you type.
    return { view: view.mode === "search" && view.back === "list" ? { ...next, filter: next.input, cursor: 0 } : next };
  }
  return { view };
}

/**
 * Raw terminal input → key name ("j", "G", "ctrl+d", "enter", "esc",
 * "backspace", "space", "ctrl+space", "up", "down", or the typed character). Handles
 * legacy sequences and the kitty CSI-u form; undefined for anything else.
 */
export function keyName(data: string): string | undefined {
  switch (data) {
    case "\x1b":
      return "esc";
    case "\r":
    case "\n":
    case "\x1bOM":
      return "enter";
    case "\x7f":
    case "\x08":
      return "backspace";
    case " ":
      return "space";
    case "\x00":
      return "ctrl+space";
    case "\x04":
      return "ctrl+d";
    case "\x15":
      return "ctrl+u";
    case "\x1b[A":
    case "\x1bOA":
      return "up";
    case "\x1b[B":
    case "\x1bOB":
      return "down";
  }
  const csiU = /^\x1b\[(\d+)(?::\d+)*(?:;(\d+)(?::\d+)?)?u$/.exec(data);
  if (csiU) {
    const code = Number(csiU[1]);
    const mods = csiU[2] ? Number(csiU[2]) - 1 : 0;
    if (code === 27) return "esc";
    if (code === 13) return "enter";
    if (code === 127) return "backspace";
    if (code === 32) return mods & 4 ? "ctrl+space" : "space";
    const ch = String.fromCodePoint(code);
    if (mods & 4) return `ctrl+${ch.toLowerCase()}`;
    if (mods & 1) return ch.toUpperCase();
    return ch;
  }
  // A single printable character (including non-ASCII) is itself.
  if ([...data].length === 1 && !/[\x00-\x1f\x7f]/.test(data)) return data;
  return undefined;
}

/**
 * Rebinds from settings (`piSub.keys`: { "<default key>": "<your key>" }),
 * applied before the reducer. A rebound default key stops acting on its own.
 * Text entry (note, search) always takes keys literally.
 */
export function translate(key: string, rebinds: Record<string, string>, mode: Mode): string {
  if (mode === "note" || mode === "search") return key;
  for (const [def, mine] of Object.entries(rebinds)) if (mine === key) return def;
  if (Object.prototype.hasOwnProperty.call(rebinds, key)) return "";
  return key;
}
