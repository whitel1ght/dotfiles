import assert from "node:assert/strict";
import test from "node:test";

import { initialView, keyName, reduce, translate, type Row, type View } from "./keys.ts";
import type { Exit, Meta } from "./state.ts";

const meta = (id: string, over: Partial<Meta> = {}): Meta => ({
  id,
  role: "worker",
  model: "p/m",
  label: id,
  task: "do it",
  cwd: "/tmp",
  skills: [],
  extras: [],
  pid: 1,
  pgid: 1,
  started_at: "2026-10-14T10:00:00Z",
  owner_session: "s",
  owner_pid: 2,
  idle_minutes: 10,
  max_minutes: 60,
  argv: [],
  ...over,
});
const done: Exit = { code: 0, signal: null, ended_at: "2026-10-14T10:30:00Z", how: "done" };
const rows: Row[] = [
  { meta: meta("a"), ordinal: 1, orphan: false },
  { meta: meta("b"), exit: done, ordinal: 2, orphan: false },
  { meta: meta("c"), ordinal: 3, orphan: false },
];

/** Feed keys through reduce, returning the final view and every action. */
function run(keys: string[], view: View = initialView(), log?: string[], page = 4) {
  const actions = [];
  for (const k of keys) {
    const r = reduce(view, k, rows, { page, log });
    view = r.view;
    if (r.action) actions.push(r.action);
  }
  return { view, actions };
}

test("list: j/k move and clamp at both ends", () => {
  assert.equal(run(["j", "j", "j", "j"]).view.cursor, 2);
  assert.equal(run(["j", "k", "k"]).view.cursor, 0);
  assert.equal(run(["down", "up", "down"]).view.cursor, 1);
});

test("list: gg, G, ctrl+d/u", () => {
  assert.equal(run(["G"]).view.cursor, 2);
  assert.equal(run(["G", "g", "g"]).view.cursor, 0);
  assert.equal(run(["G", "g", "j"]).view.cursor, 2, "g then j is not gg");
  assert.equal(run(["ctrl+d"]).view.cursor, 2);
  assert.equal(run(["G", "ctrl+u"]).view.cursor, 0);
});

test("list: l opens the selected agent following; h returns", () => {
  const opened = run(["j", "l"]).view;
  assert.equal(opened.mode, "agent");
  assert.equal(opened.openId, "b");
  assert.equal(opened.follow, true);
  assert.equal(run(["enter", "h"]).view.mode, "list");
});

test("list: x confirms only running agents; y stops, n cancels", () => {
  assert.equal(run(["j", "x"]).view.mode, "list", "b is done");
  const c = run(["x"]).view;
  assert.equal(c.mode, "confirm");
  assert.deepEqual(run(["x", "y"]).actions, [{ stop: "a" }]);
  const cancelled = run(["x", "n"]);
  assert.equal(cancelled.view.mode, "list");
  assert.deepEqual(cancelled.actions, []);
});

test("list: m collects a note and flags on enter", () => {
  const r = run(["G", "m", "l", "o", "o", "k", "space", "!", "backspace", "enter"]);
  assert.deepEqual(r.actions, [{ flag: { id: "c", note: "look" } }]);
  assert.equal(r.view.mode, "list");
  assert.deepEqual(run(["m", "x", "esc"]).actions, [], "esc drops the note");
});

test("list: / filters live, esc clears, enter keeps", () => {
  const typing = run(["/", "w", "o"]).view;
  assert.equal(typing.filter, "wo");
  assert.equal(run(["/", "w", "esc"]).view.filter, "");
  const kept = run(["/", "w", "enter"]).view;
  assert.equal(kept.mode, "list");
  assert.equal(kept.filter, "w");
});

test("list: zf toggles finished; q and esc close", () => {
  assert.equal(run(["z", "f"]).view.showFinished, true);
  assert.equal(run(["z", "f", "z", "f"]).view.showFinished, false);
  assert.deepEqual(run(["q"]).actions, [{ close: true }]);
  assert.deepEqual(run(["esc"]).actions, [{ close: true }]);
});

test("agent: scrolling leaves follow, G resumes it", () => {
  const log = Array.from({ length: 10 }, (_, i) => `line ${i}`);
  const open = run(["l"]).view;
  const up = run(["k"], open, log).view;
  assert.equal(up.follow, false);
  assert.equal(up.scroll, 5, "from the bottom (6) up one");
  assert.equal(run(["g", "g"], open, log).view.scroll, 0);
  assert.equal(run(["g", "g", "j", "j"], open, log).view.scroll, 2);
  assert.equal(run(["g", "g", "ctrl+d"], open, log).view.scroll, 2);
  const back = run(["k", "G"], open, log).view;
  assert.equal(back.follow, true);
  assert.equal(run(["k", "j", "j", "j"], open, log).view.scroll, 6, "clamped at the bottom");
});

test("agent: / searches, n/N cycle, t and l toggle", () => {
  const log = ["alpha", "beta", "gamma", "beta two", "delta", "eps"];
  const open = { ...run(["l"]).view, follow: false, scroll: 0 };
  const found = run(["/", "b", "e", "t", "enter"], open, log, 2).view;
  assert.equal(found.mode, "agent");
  assert.equal(found.search, "bet");
  assert.equal(found.scroll, 1);
  assert.equal(run(["n"], found, log, 2).view.scroll, 3);
  assert.equal(run(["n", "n"], found, log, 2).view.scroll, 1, "wraps");
  assert.equal(run(["N"], found, log, 2).view.scroll, 3, "N wraps backwards");
  assert.equal(run(["t"], open).view.showTask, true);
  assert.equal(run(["enter"], open).view.expand, true);
});

test("agent: x and m act on the opened agent and come back", () => {
  const open = run(["G", "l"]).view;
  const stop = run(["x", "y"], open);
  assert.deepEqual(stop.actions, [{ stop: "c" }]);
  assert.equal(stop.view.mode, "agent");
  const flag = run(["m", "h", "i", "enter"], open);
  assert.deepEqual(flag.actions, [{ flag: { id: "c", note: "hi" } }]);
  assert.equal(flag.view.mode, "agent");
});

test("note mode takes command letters literally", () => {
  const r = run(["m", "q", "j", "x", "enter"]);
  assert.deepEqual(r.actions, [{ flag: { id: "a", note: "qjx" } }]);
});

test("keyName: legacy, kitty CSI-u, and printable", () => {
  assert.equal(keyName("j"), "j");
  assert.equal(keyName("G"), "G");
  assert.equal(keyName("\r"), "enter");
  assert.equal(keyName("\x1b"), "esc");
  assert.equal(keyName("\x7f"), "backspace");
  assert.equal(keyName("\x04"), "ctrl+d");
  assert.equal(keyName("\x15"), "ctrl+u");
  assert.equal(keyName("\x1b[A"), "up");
  assert.equal(keyName("\x1b[B"), "down");
  assert.equal(keyName("\x1b[106u"), "j");
  assert.equal(keyName("\x1b[106;2u"), "J");
  assert.equal(keyName("\x1b[100;5u"), "ctrl+d");
  assert.equal(keyName("\x1b[27u"), "esc");
  assert.equal(keyName("\x1b[13u"), "enter");
  assert.equal(keyName("é"), "é");
  assert.equal(keyName("\x1b[1;5C"), undefined);
});

test("translate: rebinds swap keys outside text entry only", () => {
  const rb = { j: "n", k: "e" };
  assert.equal(translate("n", rb, "list"), "j");
  assert.equal(translate("e", rb, "agent"), "k");
  assert.equal(translate("j", rb, "list"), "", "the default no longer acts");
  assert.equal(translate("x", rb, "list"), "x");
  assert.equal(translate("n", rb, "note"), "n");
  assert.equal(translate("j", rb, "search"), "j");
});
