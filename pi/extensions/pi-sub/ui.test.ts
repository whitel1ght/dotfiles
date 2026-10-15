import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { initialView, type Row } from "./keys.ts";
import { stateDir, writeMeta, type Exit, type Meta } from "./state.ts";
import {
  agentLog,
  AgentsOverlay,
  filesTouched,
  fit,
  footerText,
  renderAgent,
  renderList,
  visibleRows,
} from "./ui.ts";

const NOW = Date.parse("2026-10-14T10:12:03Z");

const meta = (id: string, over: Partial<Meta> = {}): Meta => ({
  id,
  role: "worker",
  model: "qwen-token-plan/qwen3.8-flash",
  label: `label ${id}`,
  task: "first line of the task\nsecond line",
  cwd: "/repo",
  skills: [],
  extras: [],
  pid: 4_194_304,
  pgid: 4_194_304,
  started_at: "2026-10-14T10:00:00Z",
  owner_session: "sess-main",
  owner_pid: 2,
  idle_minutes: 10,
  max_minutes: 60,
  argv: [],
  ...over,
});
const exit = (how: Exit["how"], ended_at = "2026-10-14T10:05:00Z"): Exit => ({ code: 0, signal: null, ended_at, how });

function sandbox(t: test.TestContext): void {
  const root = mkdtempSync(join(tmpdir(), "pi-sub-ui-"));
  process.env.PI_SUB_STATE_DIR = root;
  t.after(() => {
    rmSync(root, { recursive: true, force: true });
    delete process.env.PI_SUB_STATE_DIR;
  });
}

function put(m: Meta, x?: Exit): Meta {
  writeMeta(m);
  if (x) writeFileSync(join(stateDir(), m.id, "exit.json"), JSON.stringify(x));
  return m;
}

const toolEv = (toolName: string, args: object) => ({ type: "tool_execution_start", toolName, args });

test("fit cuts with an ellipsis and pads to the width", () => {
  assert.equal(fit("abc", 5), "abc  ");
  assert.equal(fit("abcdef", 4), "abc…");
  assert.equal(fit("a\nb", 3), "a b");
  assert.equal([...fit("ééééé", 3)].length, 3);
});

test("visibleRows: own agents numbered by start, orphans after, old finished hidden", (t) => {
  sandbox(t);
  const all = [
    put(meta("b", { started_at: "2026-10-14T10:01:00Z" })),
    put(meta("a"), exit("done")),
    put(meta("old", { started_at: "2026-10-12T10:00:00Z" }), exit("done", "2026-10-12T11:00:00Z")),
    put(meta("orph", { owner_session: "gone", owner_pid: 4_194_304 })),
    put(meta("other", { owner_session: "live", owner_pid: process.pid })),
  ];
  const alive = (pid: number) => pid === process.pid;
  const rows = visibleRows(all, "sess-main", { showFinished: false, filter: "" }, new Date(NOW), alive);
  assert.deepEqual(
    rows.map((r) => [r.meta.id, r.ordinal, r.orphan]),
    [
      ["a", 2, false], // the hidden "old" agent is #1: numbers never shift
      ["b", 3, false],
      ["orph", undefined, true],
    ],
  );
  const all2 = visibleRows(all, "sess-main", { showFinished: true, filter: "" }, new Date(NOW), alive);
  assert.ok(all2.some((r) => r.meta.id === "old"));
  const filtered = visibleRows(all, "sess-main", { showFinished: false, filter: "LABEL B" }, new Date(NOW), alive);
  assert.deepEqual(filtered.map((r) => r.meta.id), ["b"]);
});

test("renderList: title counts, columns, cursor, orphan header, exact width", () => {
  const rows: Row[] = [
    { meta: meta("a"), ordinal: 1, orphan: false },
    { meta: meta("b", { role: "reviewer" }), exit: exit("done"), ordinal: 2, orphan: false },
    { meta: meta("c"), orphan: true },
  ];
  const out = renderList({ ...initialView(), cursor: 1 }, rows, 120, 20, NOW, "01a134d9-f178");
  assert.match(out[0], /Subagents · session 01a134d9 · 1 running · 1 done/);
  assert.ok(out.every((l) => [...l].length === 120), "every line is exactly the width");
  const body = out.join("\n");
  assert.match(body, /1  ● run  +worker +qwen3\.8-flash +12m03s +label a/);
  assert.match(body, /▸ +2  ✓ done +reviewer +qwen3\.8-flash +5m00s/);
  assert.match(body, /orphans — owner session gone/);
  assert.match(body, /j\/k move · l open · x stop · m flag to main/);
});

test("renderList: themed lines keep the exact width once colour codes are stripped", () => {
  const tag = (c: string, s: string) => `\x1b[${c.length}m${s}\x1b[0m`;
  const p = { fg: tag, bg: tag, bold: (s: string) => `\x1b[1m${s}\x1b[22m` };
  const rows: Row[] = [
    { meta: meta("a"), ordinal: 1, orphan: false },
    { meta: meta("b", { label: "x".repeat(300) }), exit: exit("failed"), ordinal: 2, orphan: false },
  ];
  for (const r of [rows, []]) {
    const out = renderList(initialView(), r, 90, 12, NOW, "s", p);
    assert.ok(out.some((l) => l.includes("\x1b[")), "something is coloured");
    for (const l of out) assert.equal([...l.replace(/\x1b\[\d+m/g, "")].length, 90, l);
  }
});

test("renderList: empty list says so without a column header; prompts replace the help line", () => {
  const empty = renderList(initialView(), [], 80, 10, NOW, "s").join("\n");
  assert.match(empty, /No agents active/);
  assert.doesNotMatch(empty, /state +role/);
  assert.doesNotMatch(empty, /0 running/);
  assert.match(renderList({ ...initialView(), filter: "zz" }, [], 80, 10, NOW, "s").join("\n"), /No agents match "zz"/);
  const rows: Row[] = [{ meta: meta("a"), ordinal: 1, orphan: false }];
  const note = renderList({ ...initialView(), mode: "note", openId: "a", back: "list", input: "hey" }, rows, 100, 10, NOW, "s");
  assert.match(note.join("\n"), /Flag #1 worker to main · note: hey/);
  const confirm = renderList({ ...initialView(), mode: "confirm", openId: "a", back: "list" }, rows, 120, 10, NOW, "s");
  assert.match(confirm.join("\n"), /Stop #1 worker \(qwen3\.8-flash, 12m03s\)\? It has edited 0 files\. y stop · n cancel/);
});

test("model column keeps the provider when two providers share an id", () => {
  const rows: Row[] = [
    { meta: meta("a", { model: "p/x" }), ordinal: 1, orphan: false },
    { meta: meta("b", { model: "q/x" }), ordinal: 2, orphan: false },
  ];
  const body = renderList(initialView(), rows, 120, 10, NOW, "s").join("\n");
  assert.match(body, /p\/x/);
  assert.match(body, /q\/x/);
});

test("filesTouched counts distinct edit/write paths", () => {
  const evs = [
    toolEv("edit", { path: "a.ts" }),
    toolEv("write", { path: "b.ts" }),
    toolEv("edit", { path: "a.ts" }),
    toolEv("read", { path: "c.ts" }),
  ];
  assert.equal(filesTouched(evs), 2);
});

test("renderAgent: header stats, task toggle, follow shows the tail", () => {
  const row: Row = { meta: meta("a"), ordinal: 1, orphan: false };
  const log = Array.from({ length: 30 }, (_, i) => `l${i}`);
  const evs = [toolEv("bash", { command: "ls" })];
  const view = { ...initialView(), mode: "agent" as const, openId: "a" };
  const out = renderAgent(view, row, [row], evs, log, 100, 15, NOW);
  assert.match(out[0], /#1 worker · qwen3\.8-flash · running 12m03s · 1 tool calls · 0 tok in/);
  assert.match(out.join("\n"), /task first line of the task +\[t\] full/);
  assert.ok(out.some((l) => l.includes("l29")), "follow shows the last line");
  assert.ok(!out.some((l) => l.includes("l0 ")));
  assert.equal(out.length, 15);
  const top = renderAgent({ ...view, follow: false, scroll: 0 }, row, [row], evs, log, 100, 15, NOW);
  assert.ok(top.some((l) => l.includes("l0 ")));
  const full = renderAgent({ ...view, showTask: true }, row, [row], evs, log, 100, 15, NOW).join("\n");
  assert.match(full, /second line/);
});

test("agentLog: activity lines, then the result once finished", () => {
  const evs = [toolEv("bash", { command: "ls" })];
  const log = agentLog(evs, "all done\n");
  assert.equal(log[log.length - 2], "── result ──");
  assert.equal(log[log.length - 1], "all done");
  assert.ok(log[0].startsWith("tool "));
});

test("footerText: counts, cleared when empty", () => {
  assert.equal(footerText([]), undefined);
  const rows: Row[] = [
    { meta: meta("a"), ordinal: 1, orphan: false },
    { meta: meta("b"), exit: exit("done"), ordinal: 2, orphan: false },
    { meta: meta("c"), exit: exit("stopped"), ordinal: 3, orphan: false },
  ];
  assert.equal(footerText(rows), "subagents ●1 run ✓1 ✗0 ■1  ctrl+space");
});

test("AgentsOverlay: keys drive actions; q closes and stops the timer", (t) => {
  sandbox(t);
  put(meta("a"));
  put(meta("b", { started_at: "2026-10-14T10:01:00Z" }));
  const actions: object[] = [];
  let closed = 0;
  let renders = 0;
  const o = new AgentsOverlay({
    session: "sess-main",
    agents: () => [meta("a"), meta("b", { started_at: "2026-10-14T10:01:00Z" })],
    alive: () => false,
    events: () => [],
    result: () => undefined,
    parse: (d) => d,
    rebinds: {},
    rowsOnScreen: () => 20,
    onAction: (a) => actions.push(a),
    done: () => closed++,
    requestRender: () => renders++,
    now: () => NOW,
  });
  o.handleInput("j");
  o.handleInput("x");
  assert.match(o.render(120).join("\n"), /Stop #2 worker/);
  o.handleInput("y");
  assert.deepEqual(actions, [{ stop: "b" }]);
  o.handleInput("l");
  assert.match(o.render(120)[0], /#2 worker/);
  o.handleInput("h");
  o.handleInput("q");
  assert.equal(closed, 1);
  assert.ok(renders >= 4);
});

test("AgentsOverlay: opened by id, an agent missing from the list falls back", (t) => {
  sandbox(t);
  mkdirSync(stateDir(), { recursive: true });
  const o = new AgentsOverlay(
    {
      session: "sess-main",
      agents: () => [],
      alive: () => false,
      events: () => [],
      result: () => undefined,
      parse: (d) => d,
      rebinds: {},
      rowsOnScreen: () => 20,
      onAction: () => {},
      done: () => {},
      requestRender: () => {},
      now: () => NOW,
    },
    "ghost",
  );
  assert.match(o.render(80)[0], /Subagents/, "unknown id drops back to the list");
  o.dispose();
});

function hotkeyOverlay(hotkey: string | undefined, rebinds: Record<string, string> = {}) {
  const state = { closed: 0 };
  const o = new AgentsOverlay({
    session: "sess-main",
    agents: () => [meta("a")],
    alive: () => false,
    events: () => [],
    result: () => undefined,
    parse: (d) => d,
    rebinds,
    hotkey,
    rowsOnScreen: () => 20,
    onAction: () => {},
    done: () => state.closed++,
    requestRender: () => {},
    now: () => NOW,
  });
  return { o, state };
}

test("AgentsOverlay: the hotkey closes from list, agent, search and confirm", (t) => {
  sandbox(t);
  put(meta("a"));
  for (const keys of [[], ["l"], ["/"], ["l", "/"], ["x"], ["m"]]) {
    const { o, state } = hotkeyOverlay("ctrl+space");
    for (const k of keys) o.handleInput(k);
    o.handleInput("ctrl+space");
    assert.equal(state.closed, 1, keys.join(" "));
  }
});

test("AgentsOverlay: the hotkey follows the configured key; no hotkey, no toggle", (t) => {
  sandbox(t);
  put(meta("a"));
  const { o, state } = hotkeyOverlay("ctrl+g");
  o.handleInput("ctrl+space");
  assert.equal(state.closed, 0);
  o.handleInput("ctrl+g");
  assert.equal(state.closed, 1);
  const bare = hotkeyOverlay(undefined, { q: "ctrl+g" });
  bare.o.handleInput("ctrl+space");
  assert.equal(bare.state.closed, 0);
});
