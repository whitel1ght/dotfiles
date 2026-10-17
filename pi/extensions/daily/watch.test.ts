import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { acquireLock, DayWatcher, releaseLock, type Exec, type WatchDeps } from "./watch.ts";

const DAY = "2026-01-01";
const PLAN = [
  "<!-- start-day:start -->",
  "#### Plan",
  "- [/] ecfx-1002 address review [↗][backend!870]",
  "- [ ] ecfx-1003 retry button",
  "<!-- start-day:end -->",
  "",
  "[backend!870]: https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/870",
].join("\n");
const RUN_STATE = `# run-day ${DAY}\nmax_agents: 3\n- ecfx-1003 | class=auto | agent=- | worktree=- | mr=ecfx/ecfx-dashboard!2239 | retries=0 | needs_you=no | owner=main\nnotes:\n`;

const ev = (o: Record<string, unknown>) => JSON.stringify({ project: "ecfx", summary: "s", url: "u", at: "t", ...o });

type Calls = { wakes: string[]; notes: string[]; notices: string[]; frictions: string[]; runs: number };

function setup(opts: { runState?: boolean; changes?: Exec[]; inbox?: string[][] } = {}) {
  const root = mkdtempSync(join(tmpdir(), "daily-watch-"));
  const stateDir = join(root, "state");
  mkdirSync(join(stateDir, "inbox"), { recursive: true });
  mkdirSync(join(root, "diary"), { recursive: true });
  writeFileSync(join(root, "diary", `${DAY}.md`), PLAN);
  if (opts.runState !== false) writeFileSync(join(stateDir, `${DAY}.md`), RUN_STATE);
  const calls: Calls = { wakes: [], notes: [], notices: [], frictions: [], runs: 0 };
  const changes = [...(opts.changes ?? [])];
  const listings = [...(opts.inbox ?? [])];
  const deps: WatchDeps = {
    paths: () => ({ runState: join(stateDir, `${DAY}.md`), diary: join(root, "diary", `${DAY}.md`) }),
    changes: async () => {
      calls.runs += 1;
      return changes.shift() ?? { code: 0, stdout: "", stderr: "" };
    },
    listInbox: () => listings.shift() ?? [],
    wake: (t) => calls.wakes.push(t),
    note: (t) => calls.notes.push(t),
    notify: (m) => calls.notices.push(m),
    friction: (kind, msg) => calls.frictions.push(`${kind}: ${msg}`),
  };
  return { root, stateDir, calls, watcher: new DayWatcher(deps) };
}

test("does nothing while no run is active", async () => {
  const { root, calls, watcher } = setup({ runState: false, changes: [{ code: 0, stdout: ev({ kind: "comment" }), stderr: "" }] });
  await watcher.checkEvents();
  watcher.checkInbox();
  assert.equal(calls.runs, 0);
  assert.deepEqual(calls.wakes, []);
  rmSync(root, { recursive: true });
});

test("a thread event on a plan MR wakes the session with Claude's line", async () => {
  const stdout = ev({ kind: "comment", repo: "ecfx-backend", mr: 870, ticket: "ECFX-1002", summary: "please rename" });
  const { root, calls, watcher } = setup({ changes: [{ code: 0, stdout, stderr: "" }] });
  await watcher.checkEvents();
  assert.deepEqual(calls.wakes, ["[daily-event] comment | backend!870 | ECFX-1002 | please rename | u"]);
  assert.deepEqual(calls.notes, []);
  rmSync(root, { recursive: true });
});

test("an MR known only from the run state counts too", async () => {
  const stdout = ev({ kind: "pipeline_failed", repo: "ecfx-dashboard", mr: 2239, ticket: "ECFX-1003" });
  const { root, calls, watcher } = setup({ changes: [{ code: 0, stdout, stderr: "" }] });
  await watcher.checkEvents();
  assert.equal(calls.wakes.length, 1);
  assert.match(calls.wakes[0], /^\[daily-event\] pipeline_failed \| dashboard!2239 /);
  rmSync(root, { recursive: true });
});

test("other events are added as info without a wake, prompts are joined into one", async () => {
  const stdout = [
    ev({ kind: "approved", repo: "ecfx-backend", mr: 870, ticket: "ECFX-1002" }),
    ev({ kind: "comment", repo: "ecfx-admin", mr: 1, ticket: "ECFX-9" }),
    ev({ kind: "comment", repo: "ecfx-backend", mr: 870, ticket: "ECFX-1002" }),
    ev({ kind: "assigned", ticket: "ECFX-7777" }),
    "not json",
  ].join("\n");
  const { root, calls, watcher } = setup({ changes: [{ code: 0, stdout, stderr: "" }] });
  await watcher.checkEvents();
  assert.equal(calls.wakes.length, 1);
  assert.equal(calls.wakes[0].split("\n").length, 2, "the plan comment and the new assignment");
  assert.equal(calls.notes.length, 2);
  assert.ok(calls.notes.every((n) => n.startsWith("[daily-event:info] ")));
  rmSync(root, { recursive: true });
});

test("a failing check is reported once, a timeout logged as friction, and recovery said", async () => {
  const fail: Exec = { code: 124, stdout: "", stderr: "changes-since: timed out\nmore" };
  const { root, calls, watcher } = setup({ changes: [fail, fail, { code: 0, stdout: "", stderr: "" }] });
  await watcher.checkEvents();
  await watcher.checkEvents();
  assert.equal(calls.notices.length, 1);
  assert.match(calls.notices[0], /changes-since failed \(exit 124\): changes-since: timed out/);
  assert.equal(calls.frictions.length, 1);
  assert.match(calls.frictions[0], /^timeout: /);
  await watcher.checkEvents();
  assert.equal(calls.notices.length, 2);
  assert.match(calls.notices[1], /working again/);
  rmSync(root, { recursive: true });
});

test("a non-timeout failure is noticed but not logged (changes-since logs its own)", async () => {
  const { root, calls, watcher } = setup({ changes: [{ code: 1, stdout: "", stderr: "jira down" }] });
  await watcher.checkEvents();
  assert.equal(calls.notices.length, 1);
  assert.deepEqual(calls.frictions, []);
  rmSync(root, { recursive: true });
});

test("only one event check runs at a time", async () => {
  const { root, calls, watcher } = setup();
  await Promise.all([watcher.checkEvents(), watcher.checkEvents()]);
  assert.equal(calls.runs, 1);
  rmSync(root, { recursive: true });
});

test("new inbox messages wake the session once; other files are ignored", () => {
  const a = "20260101T090000-ecfx-1002-ab12.md";
  const b = "20260101T091500-offplan-cd34.md";
  const { root, calls, watcher } = setup({ inbox: [[a, "notes.txt"], [a], [a, b], []] });
  watcher.checkInbox();
  watcher.checkInbox();
  watcher.checkInbox();
  watcher.checkInbox();
  assert.deepEqual(calls.wakes, ["inbox: 1 new", "inbox: 1 new"]);
  rmSync(root, { recursive: true });
});

test("the lock lets one session watch and names the holder to the next", () => {
  const root = mkdtempSync(join(tmpdir(), "daily-lock-"));
  const lock = join(root, "watch.lock");
  assert.equal(acquireLock(lock, { pid: process.pid, session: "s1" }), null);
  const refused = acquireLock(lock, { pid: process.pid + 100000, session: "s2" });
  assert.match(refused ?? "", /s1/);
  assert.equal(acquireLock(lock, { pid: process.pid, session: "s1" }), null, "the holder may start again");
  releaseLock(lock, process.pid);
  assert.equal(acquireLock(lock, { pid: process.pid + 100000, session: "s2" }), null);
  rmSync(root, { recursive: true });
});

test("a lock left by a dead process is taken over", () => {
  const root = mkdtempSync(join(tmpdir(), "daily-lock-"));
  const lock = join(root, "watch.lock");
  writeFileSync(lock, JSON.stringify({ pid: 999999, session: "gone" }));
  assert.equal(acquireLock(lock, { pid: process.pid, session: "s1" }), null);
  rmSync(root, { recursive: true });
});
