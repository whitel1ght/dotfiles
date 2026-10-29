import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

type Calls = { wakes: string[]; notes: string[]; notices: string[]; frictions: string[]; runs: number; probes: number };

const WORKING = RUN_STATE.replace("agent=-", "agent=a1b2");
const OPEN = { lid: '"AppleClamshellState" = No', systemstate: "Current System Capabilities are: CPU Graphics Audio Network" };
const DARK = { lid: '"AppleClamshellState" = No', systemstate: "Current System Capabilities are: CPU Network" };
const BLIND = { lid: "", systemstate: "" };
type Probe = { lid: string; systemstate: string };

function setup(
  opts: { runState?: boolean; state?: string; changes?: Exec[]; inbox?: string[][]; held?: boolean; probes?: Probe[]; report?: boolean } = {},
) {
  const root = mkdtempSync(join(tmpdir(), "daily-watch-"));
  const stateDir = join(root, "state");
  mkdirSync(join(stateDir, "inbox"), { recursive: true });
  mkdirSync(join(root, "diary"), { recursive: true });
  writeFileSync(join(root, "diary", `${DAY}.md`), PLAN);
  if (opts.report) writeFileSync(join(root, "diary", `${DAY}.md`), `${PLAN}\n<!-- daily-report:start -->\n`);
  if (opts.runState !== false) writeFileSync(join(stateDir, `${DAY}.md`), opts.state ?? RUN_STATE);
  const calls: Calls = { wakes: [], notes: [], notices: [], frictions: [], runs: 0, probes: 0 };
  const changes = [...(opts.changes ?? [])];
  const listings = [...(opts.inbox ?? [])];
  const probes = [...(opts.probes ?? [])];
  const deps: WatchDeps = {
    paths: () => ({ runState: join(stateDir, `${DAY}.md`), diary: join(root, "diary", `${DAY}.md`), playbook: join(stateDir, `${DAY}.playbook`) }),
    changes: async () => {
      calls.runs += 1;
      return changes.shift() ?? { code: 0, stdout: "", stderr: "" };
    },
    listInbox: () => listings.shift() ?? [],
    holdsLock: () => opts.held !== false,
    lidAndGraphics: async () => {
      calls.probes += 1;
      return probes.shift() ?? OPEN;
    },
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

const MIN = 60_000;
const T0 = 1_000_000_000;
const NUDGE = "[daily-wake] woke after 10 min: run the Wake check of /run-day (section 10).";

test("a full wake after a tick gap gives one prompt, with the minutes slept", async () => {
  const { root, watcher } = setup({ state: WORKING });
  assert.equal(await watcher.checkWake(T0), null);
  assert.equal(await watcher.checkWake(T0 + 10 * MIN), NUDGE);
  assert.equal(await watcher.checkWake(T0 + 10 * MIN + 30_000), null);
  rmSync(root, { recursive: true });
});

test("no probe runs while no gap is pending", async () => {
  const { root, calls, watcher } = setup({ state: WORKING });
  await watcher.checkWake(T0);
  await watcher.checkWake(T0 + 30_000);
  assert.equal(calls.probes, 0);
  rmSync(root, { recursive: true });
});

test("a dark wake gives nothing, and the next full-wake tick still nudges", async () => {
  const { root, watcher } = setup({ state: WORKING, probes: [DARK, OPEN] });
  await watcher.checkWake(T0);
  assert.equal(await watcher.checkWake(T0 + 10 * MIN), null);
  assert.equal(await watcher.checkWake(T0 + 10 * MIN + 30_000), "[daily-wake] woke after 11 min: run the Wake check of /run-day (section 10).");
  rmSync(root, { recursive: true });
});

test("no outstanding work and an empty inbox: no nudge", async () => {
  const { root, watcher } = setup();
  await watcher.checkWake(T0);
  assert.equal(await watcher.checkWake(T0 + 10 * MIN), null);
  rmSync(root, { recursive: true });
});

test("inbox messages alone are enough", async () => {
  const msg = "20260101T090000-ecfx-1002-ab12.md";
  const { root, watcher } = setup({ inbox: [[msg]] });
  await watcher.checkWake(T0);
  assert.equal(await watcher.checkWake(T0 + 10 * MIN), NUDGE);
  rmSync(root, { recursive: true });
});

test("another session's lock, a finished report or no run state: no nudge", async () => {
  for (const o of [{ held: false }, { report: true }, { runState: false }]) {
    const { root, calls, watcher } = setup({ state: WORKING, ...o });
    await watcher.checkWake(T0);
    assert.equal(await watcher.checkWake(T0 + 10 * MIN), null);
    assert.equal(calls.probes, 0);
    rmSync(root, { recursive: true });
  }
});

test("a gap during a time the lock was not held is forgotten", async () => {
  const { root, watcher } = setup({ state: WORKING });
  let held = false;
  (watcher as unknown as { deps: WatchDeps }).deps.holdsLock = () => held;
  await watcher.checkWake(T0);
  assert.equal(await watcher.checkWake(T0 + 10 * MIN), null);
  held = true;
  assert.equal(await watcher.checkWake(T0 + 10 * MIN + 30_000), null);
  rmSync(root, { recursive: true });
});

test("a probe that throws never loses the sleep", async () => {
  const { root, watcher } = setup({ state: WORKING });
  const deps = (watcher as unknown as { deps: WatchDeps }).deps;
  const real = deps.lidAndGraphics;
  deps.lidAndGraphics = async () => {
    throw new Error("boom");
  };
  await watcher.checkWake(T0);
  await assert.rejects(watcher.checkWake(T0 + 10 * MIN));
  deps.lidAndGraphics = real;
  assert.match((await watcher.checkWake(T0 + 10 * MIN + 30_000)) ?? "", /^\[daily-wake\] woke after 11 min/);
  rmSync(root, { recursive: true });
});

test("three blind probes in a row clear the wake with one notice; a known probe resets the count", async () => {
  const { root, calls, watcher } = setup({ state: WORKING, probes: [BLIND, BLIND, OPEN] });
  await watcher.checkWake(T0);
  // two blind probes, then a known one: the count resets and no notice is given
  await watcher.checkWake(T0 + 10 * MIN);
  await watcher.checkWake(T0 + 10 * MIN + 30_000);
  assert.ok((await watcher.checkWake(T0 + 11 * MIN)) !== null);
  assert.deepEqual(calls.notices, []);
  rmSync(root, { recursive: true });

  const b = setup({ state: WORKING, probes: [BLIND, BLIND, BLIND] });
  await b.watcher.checkWake(T0);
  await b.watcher.checkWake(T0 + 10 * MIN);
  await b.watcher.checkWake(T0 + 10 * MIN + 30_000);
  assert.equal(await b.watcher.checkWake(T0 + 11 * MIN), null);
  assert.deepEqual(b.calls.notices, ["daily wake: cannot read lid or display state; no wake nudge for this sleep"]);
  assert.equal(await b.watcher.checkWake(T0 + 12 * MIN), null);
  assert.equal(b.calls.probes, 3, "no more probes once cleared");
  rmSync(b.root, { recursive: true });
});

const BUSY = "[daily-idle] no agent running: run Keep busy of /run-day (section 11).";
const quiet = (o: Partial<{ lastActiveAt: number; turnRunning: boolean; userWrote: boolean }> = {}) => ({
  lastActiveAt: T0,
  turnRunning: false,
  userWrote: false,
  ...o,
});

test("an idle day with no agent gets one Keep busy prompt per idle stretch", async () => {
  const { root, watcher } = setup();
  assert.equal(watcher.checkBusy(T0 + 9 * MIN, quiet()), null);
  assert.equal(watcher.checkBusy(T0 + 10 * MIN, quiet()), BUSY);
  assert.equal(watcher.checkBusy(T0 + 30 * MIN, quiet()), null);
  rmSync(root, { recursive: true });
});

test("checkInbox says whether it sent a prompt, so the tick sends one turn at most", async () => {
  const { root, watcher } = setup({ inbox: [["20260101T090000-ECFX-1-abcd.md"], ["20260101T090000-ECFX-1-abcd.md"]] });
  assert.equal(watcher.checkInbox(), true);
  assert.equal(watcher.checkInbox(), false);
  rmSync(root, { recursive: true });
});

test("the user writing starts a new idle stretch", async () => {
  const { root, watcher } = setup();
  assert.equal(watcher.checkBusy(T0 + 10 * MIN, quiet()), BUSY);
  assert.equal(watcher.checkBusy(T0 + 20 * MIN, quiet({ lastActiveAt: T0 + 10 * MIN, userWrote: true })), BUSY);
  rmSync(root, { recursive: true });
});

test("no Keep busy prompt while an agent is outstanding, a turn runs, or outside the watching session", async () => {
  for (const [opts, a] of [
    [{ state: WORKING }, quiet()],
    [{}, quiet({ turnRunning: true })],
    [{ held: false }, quiet()],
    [{ report: true }, quiet()],
    [{ runState: false }, quiet()],
  ] as const) {
    const { root, watcher } = setup(opts);
    assert.equal(watcher.checkBusy(T0 + 60 * MIN, a), null, JSON.stringify(opts));
    rmSync(root, { recursive: true });
  }
});

test("an agent outstanding ends the stretch: idle again later gives a new prompt", async () => {
  const { root, stateDir, watcher } = setup();
  assert.equal(watcher.checkBusy(T0 + 10 * MIN, quiet()), BUSY);
  writeFileSync(join(stateDir, `${DAY}.md`), WORKING);
  assert.equal(watcher.checkBusy(T0 + 20 * MIN, quiet()), null);
  writeFileSync(join(stateDir, `${DAY}.md`), RUN_STATE);
  assert.equal(watcher.checkBusy(T0 + 40 * MIN, quiet({ lastActiveAt: T0 + 25 * MIN })), BUSY);
  rmSync(root, { recursive: true });
});

test("the playbook the day was started with is recorded, and a change is reported once", async () => {
  const { root, stateDir, watcher } = setup();
  assert.equal(watcher.checkUpdate("aaaa1111"), false, "nothing recorded yet");
  watcher.recordPlaybook("aaaa1111");
  assert.equal(readFileSync(join(stateDir, `${DAY}.playbook`), "utf8"), "aaaa1111\n");
  assert.equal(watcher.checkUpdate("aaaa1111"), false, "unchanged");
  assert.equal(watcher.checkUpdate("bbbb2222"), true);
  assert.equal(watcher.checkUpdate("bbbb2222"), false, "once until the day is recorded again");
  watcher.recordPlaybook("bbbb2222");
  assert.equal(watcher.checkUpdate("cccc3333"), true);
  rmSync(root, { recursive: true });
});

test("no update outside the watching session or after the daily report", async () => {
  for (const opts of [{ held: false }, { report: true }, { runState: false }]) {
    const { root, stateDir, watcher } = setup(opts);
    writeFileSync(join(stateDir, `${DAY}.playbook`), "aaaa1111\n");
    assert.equal(watcher.checkUpdate("bbbb2222"), false, JSON.stringify(opts));
    rmSync(root, { recursive: true });
  }
});
