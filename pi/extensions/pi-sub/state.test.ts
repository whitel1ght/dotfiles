import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  isDelivered,
  listAgents,
  markDelivered,
  newId,
  orphans,
  owned,
  readExit,
  readMeta,
  stateDir,
  writeMeta,
  type Exit,
  type Meta,
} from "./state.ts";

function sandbox() {
  const root = mkdtempSync(join(tmpdir(), "pi-sub-state-"));
  process.env.PI_SUB_STATE_DIR = join(root, "pi-sub");
  return root;
}

function cleanup(root: string) {
  rmSync(root, { recursive: true, force: true });
  delete process.env.PI_SUB_STATE_DIR;
}

function meta(overrides: Partial<Meta> = {}): Meta {
  return {
    id: "20261014-101500-00aa",
    role: "worker",
    model: "qwen3.8-flash",
    label: "implement state store",
    task: "Task 1",
    cwd: "/tmp/worktree",
    skills: ["test-driven-development"],
    extras: [],
    pid: 1111,
    pgid: 1111,
    started_at: "2026-10-14T10:15:00Z",
    owner_session: "sess-a",
    owner_pid: 2222,
    idle_minutes: 0,
    max_minutes: 30,
    argv: ["pi", "-p", "do it"],
    ...overrides,
  };
}

function writeExit(id: string, exit: Exit) {
  writeFileSync(join(stateDir(), id, "exit.json"), JSON.stringify(exit));
}

test("newId sorts by time", () => {
  const root = sandbox();
  const early = newId(new Date(2026, 9, 14, 9, 0, 0));
  const late = newId(new Date(2026, 9, 14, 9, 0, 1));
  assert.match(early, /^\d{8}-\d{6}-[0-9a-f]{4}$/);
  assert.ok(early < late, `${early} should sort before ${late}`);
  assert.notEqual(newId(new Date()), newId(new Date()));
  assert.equal(stateDir(), join(root, "pi-sub"));
  cleanup(root);
});

test("atomicWrite: unique tmp name per write, nothing partial, tmp cleaned on failure", () => {
  const root = sandbox();
  const first = meta();
  writeMeta(first);
  assert.deepEqual(readMeta(first.id), first);

  // A concurrent writer's tmp file (a directory, so writing that exact name
  // would fail) never blocks this write: every write picks a unique tmp name.
  const id = "20261014-101500-00bb";
  const dir = join(stateDir(), id);
  mkdirSync(dir, { recursive: true });
  mkdirSync(join(dir, "meta.json.99999.concurrent.tmp"));
  writeMeta(meta({ id }));
  assert.deepEqual(readMeta(id), meta({ id }));
  assert.ok(existsSync(join(dir, "meta.json.99999.concurrent.tmp")), "the other writer's tmp is untouched");

  // A rename onto an occupied path fails; the write's own tmp is cleaned up.
  const blocked = "20261014-101500-00cc";
  mkdirSync(join(stateDir(), blocked), { recursive: true });
  mkdirSync(join(stateDir(), blocked, "meta.json"));
  assert.throws(() => writeMeta(meta({ id: blocked })));
  assert.deepEqual(readdirSync(join(stateDir(), blocked)).filter((f) => f.endsWith(".tmp")), []);

  writeMeta(first); // still readable, and no tmp residue on the good path
  assert.deepEqual(readMeta(first.id), first);
  assert.deepEqual(readdirSync(join(stateDir(), first.id)).filter((f) => f.endsWith(".tmp")), []);
  cleanup(root);
});

test("listAgents skips an agent whose meta.json is missing or unparseable", () => {
  const root = sandbox();
  const good = meta({ id: "20261014-101500-01aa" });
  const corrupt = meta({ id: "20261014-101500-02bb" });
  const empty = meta({ id: "20261014-101500-03cc" });
  writeMeta(good);
  writeMeta(corrupt);
  writeFileSync(join(stateDir(), corrupt.id, "meta.json"), "{ half-written");
  mkdirSync(join(stateDir(), empty.id), { recursive: true }); // dir with no meta.json
  assert.deepEqual(listAgents().map((m) => m.id), [good.id]);
  cleanup(root);
});

test("readExit returns undefined for an unparseable exit.json", () => {
  const root = sandbox();
  const m = meta();
  writeMeta(m);
  writeExit(m.id, { code: 0, signal: null, ended_at: "2026-10-14T10:20:00Z", how: "done" });
  assert.ok(readExit(m.id) !== undefined);
  // A half-written exit.json is not an exit: the agent is still running.
  writeFileSync(join(stateDir(), m.id, "exit.json"), `{"how":"done","cod`);
  assert.equal(readExit(m.id), undefined);
  cleanup(root);
});

test("listAgents returns every agent sorted by id", () => {
  const root = sandbox();
  const c = meta({ id: "20261014-101500-00cc" });
  const a = meta({ id: "20261014-093000-00aa" });
  const b = meta({ id: "20261014-101500-00bb" });
  for (const m of [c, a, b]) writeMeta(m);
  assert.deepEqual(listAgents().map((m) => m.id), [a.id, b.id, c.id]);
  assert.deepEqual(owned(listAgents(), "sess-a"), [a, b, c]);
  assert.deepEqual(owned(listAgents(), "sess-b"), []);
  assert.equal(readExit(a.id), undefined);
  assert.equal(isDelivered(a.id), false);
  writeExit(a.id, { code: 0, signal: null, ended_at: "2026-10-14T10:20:00Z", how: "done" });
  assert.deepEqual(readExit(a.id), { code: 0, signal: null, ended_at: "2026-10-14T10:20:00Z", how: "done" });
  markDelivered(a.id);
  assert.equal(isDelivered(a.id), true);
  cleanup(root);
});

test("orphans excludes live owners and delivered exits", () => {
  const root = sandbox();
  const live = meta({ id: "20261014-101500-01aa" }); // owner alive
  const deadRunning = meta({ id: "20261014-101500-02aa", owner_pid: 3333 });
  const deadDelivered = meta({ id: "20261014-101500-03aa", owner_pid: 4444 });
  const deadUndelivered = meta({ id: "20261014-101500-04aa", owner_pid: 5555 });
  for (const m of [live, deadRunning, deadDelivered, deadUndelivered]) writeMeta(m);
  writeExit(deadDelivered.id, { code: 1, signal: null, ended_at: "2026-10-14T10:30:00Z", how: "failed" });
  markDelivered(deadDelivered.id);
  writeExit(deadUndelivered.id, { code: null, signal: "SIGTERM", ended_at: "2026-10-14T10:31:00Z", how: "stopped", by: "user" });

  const alive = (pid: number) => pid === 2222;
  const found = orphans([live, deadRunning, deadDelivered, deadUndelivered], "sess-b", alive);
  assert.deepEqual(found.map((m) => m.id), [deadRunning.id, deadUndelivered.id]);
  cleanup(root);
});

test("handed-off agents are not orphans of the old owner while it lives", () => {
  const root = sandbox();
  const handedOff = meta({ id: "20261014-101500-06aa", handoff_from: "sess-old" });
  writeMeta(handedOff);

  // Old owner process still alive: no other session may list the agent as an orphan.
  const liveOwner = (pid: number) => pid === 2222;
  assert.deepEqual(orphans([handedOff], "sess-new", liveOwner), []);

  // Once the old owner dies, the undelivered agent is adoptable as an orphan.
  const deadOwner = () => false;
  assert.deepEqual(orphans([handedOff], "sess-new", deadOwner), [handedOff]);
  cleanup(root);
});
