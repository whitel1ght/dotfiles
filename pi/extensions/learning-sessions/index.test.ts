import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import learningSessions from "./index.ts";

type Handler = (...args: unknown[]) => unknown;

function setup(opts: { marked?: boolean; fail?: boolean } = {}) {
  const root = mkdtempSync(join(tmpdir(), "learning-sessions-"));
  const log = join(root, "argv.log");
  const stub = join(root, "session-save");
  writeFileSync(
    stub,
    [
      "#!/bin/bash",
      `echo "$*" >> ${JSON.stringify(log)}`,
      opts.fail ? "exit 1" : "",
      `[ "$1" = is-marked ] && exit ${opts.marked ? 0 : 1}`,
      `[ "$1" = save ] && echo /wiki/learning/sessions/x.md`,
      `[ "$1" = mark ] && echo marked`,
      "exit 0",
    ].join("\n"),
  );
  chmodSync(stub, 0o755);
  process.env.SESSION_SAVE_BIN = stub;
  delete process.env.PI_SUBAGENT;

  const commands: Record<string, { handler: Handler }> = {};
  const events: Record<string, Handler> = {};
  learningSessions({
    registerCommand(name: string, spec: { handler: Handler }) {
      commands[name] = spec;
    },
    on(event: string, cb: Handler) {
      events[event] = cb;
    },
  } as never);
  const notes: string[] = [];
  const ctx = {
    hasUI: true,
    ui: { notify: (msg: string) => notes.push(msg) },
    sessionManager: { getSessionId: () => "pi-sid-1", getSessionFile: () => "/sessions/pi-sid-1.jsonl" },
  };
  const calls = () => (existsSync(log) ? readFileSync(log, "utf8").trim().split("\n") : []);
  return { root, commands, events, ctx, notes, calls };
}

test("/learn-mark marks the session and says so", async () => {
  const t = setup();
  await t.commands["learn-mark"].handler("", t.ctx);
  assert.deepEqual(t.calls(), ["mark --harness pi pi-sid-1"]);
  assert.match(t.notes.join("\n"), /Marked/);
  rmSync(t.root, { recursive: true });
});

test("/learn-save marks, saves with the session file and shows the path", async () => {
  const t = setup();
  await t.commands["learn-save"].handler("", t.ctx);
  assert.deepEqual(t.calls(), [
    "mark --harness pi pi-sid-1",
    "save --harness pi --session pi-sid-1 --transcript /sessions/pi-sid-1.jsonl",
  ]);
  assert.match(t.notes.join("\n"), /\/wiki\/learning\/sessions\/x\.md/);
  rmSync(t.root, { recursive: true });
});

test("/learn-save passes its argument as the title", async () => {
  const t = setup();
  await t.commands["learn-save"].handler("Go scheduler", t.ctx);
  assert.equal(t.calls()[1], "save --harness pi --session pi-sid-1 --transcript /sessions/pi-sid-1.jsonl --title Go scheduler");
  rmSync(t.root, { recursive: true });
});

test("session_shutdown saves a marked session", async () => {
  const t = setup({ marked: true });
  await t.events.session_shutdown({ reason: "quit" }, t.ctx);
  assert.deepEqual(t.calls(), [
    "is-marked pi-sid-1",
    "save --harness pi --session pi-sid-1 --transcript /sessions/pi-sid-1.jsonl",
  ]);
  rmSync(t.root, { recursive: true });
});

test("session_shutdown leaves an unmarked session alone", async () => {
  const t = setup({ marked: false });
  await t.events.session_shutdown({ reason: "quit" }, t.ctx);
  assert.deepEqual(t.calls(), ["is-marked pi-sid-1"]);
  rmSync(t.root, { recursive: true });
});

test("session_shutdown in a subagent does nothing", async () => {
  const t = setup({ marked: true });
  process.env.PI_SUBAGENT = "1";
  await t.events.session_shutdown({ reason: "quit" }, t.ctx);
  delete process.env.PI_SUBAGENT;
  assert.deepEqual(t.calls(), []);
  rmSync(t.root, { recursive: true });
});

test("a failing session-save never throws out of a handler", async () => {
  const t = setup({ fail: true, marked: true });
  await t.events.session_shutdown({ reason: "quit" }, t.ctx);
  await t.commands["learn-save"].handler("", t.ctx);
  await t.commands["learn-mark"].handler("", t.ctx);
  assert.match(t.notes.join("\n"), /failed/);
  rmSync(t.root, { recursive: true });
});
