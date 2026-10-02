import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { AgentManager, currentModel, result, withHistory, type Agent, type SpawnOptions } from "./src/agents.ts";
import type { Timing } from "./src/roster.ts";

const base = mkdtempSync(join(tmpdir(), "agents-test-"));
const fakePi = [process.execPath, join(import.meta.dirname, "test", "fake-pi.mjs")];
const managers: AgentManager[] = [];
after(async () => {
  await Promise.all(managers.map((m) => m.shutdown()));
  rmSync(base, { recursive: true, force: true });
});

const timing: Timing = { pingTimeoutMs: 2000, pingCacheMs: 60_000, stallMs: 400, toolStallMs: 5000, localStallMs: 400 };

function make(extra: { maxRunning?: number; timing?: Partial<Timing> } = {}) {
  const manager = new AgentManager({
    piCommand: fakePi,
    maxRunning: extra.maxRunning ?? 4,
    timing: { ...timing, ...extra.timing },
    localModel: "ollama/small",
    baseDir: base,
    killGraceMs: 300,
    drainMs: 100,
    watchIntervalMs: 100,
  });
  managers.push(manager);
  return manager;
}

const spawnOpts = (extra: Partial<SpawnOptions> = {}): SpawnOptions => ({
  type: "explore",
  chain: ["fake/ok"],
  task: "find the README",
  cwd: base,
  tools: ["read", "bash"],
  ...extra,
});

function finished(manager: AgentManager): Promise<Agent> {
  return new Promise((resolve) => manager.onFinish(resolve));
}

const outcomes = (agent: Agent) => agent.attempts.map((a) => `${a.model}:${a.outcome}`);

test("the first model that answers does the task, with its tools and the child marker", async () => {
  const manager = make();
  const done = finished(manager);
  const agent = manager.spawn(spawnOpts());
  assert.equal(agent.id, "agent-1");
  await done;
  assert.equal(agent.status, "done");
  assert.equal(result(agent), "env=1 tools=read,bash lean=false\nTask:\nfind the README");
  assert.deepEqual(outcomes(agent), ["fake/ok:done"]);
});

test("models that fail their ping are skipped with the reason, and the next one runs", async () => {
  const manager = make();
  const done = finished(manager);
  const agent = manager.spawn(spawnOpts({ chain: ["fake/reject", "fake/crash", "fake/hang", "fake/ok"] }));
  await done;
  assert.equal(agent.status, "done");
  assert.deepEqual(outcomes(agent), ["fake/reject:skipped", "fake/crash:skipped", "fake/hang:skipped", "fake/ok:done"]);
  assert.match(agent.attempts[0].reason!, /ping: 401 Invalid API key/);
  assert.match(agent.attempts[1].reason!, /no API key for provider fake/);
  assert.match(agent.attempts[2].reason!, /no answer within 2s/);
  assert.equal(currentModel(agent), "fake/ok");
});

test("a model that fails mid-run hands over, and the next one is told work may be half done", async () => {
  const manager = make();
  const done = finished(manager);
  const agent = manager.spawn(spawnOpts({ chain: ["fake/fail-run", "fake/ok"] }));
  await done;
  assert.deepEqual(outcomes(agent), ["fake/fail-run:failed", "fake/ok:done"]);
  assert.equal(agent.attempts[0].reason, "500 upstream overloaded");
  assert.match(result(agent), /earlier attempts at this task stopped partway[\s\S]*- fake\/fail-run: 1 tool calls, then 500 upstream overloaded\n\nfind the README$/);
});

test("a silent model is killed as stalled, and the chain moves on", async () => {
  const manager = make();
  const done = finished(manager);
  const agent = manager.spawn(spawnOpts({ chain: ["fake/stall", "fake/ok"] }));
  await done;
  assert.deepEqual(outcomes(agent), ["fake/stall:stalled", "fake/ok:done"]);
  assert.match(agent.attempts[0].reason!, /^stalled: no output for \ds$/);
});

test("a quiet tool call gets the longer tool limit, not the model's", async () => {
  const manager = make();
  const done = finished(manager);
  const agent = manager.spawn(spawnOpts({ chain: ["fake/slow-tool"] }));
  await done;
  assert.deepEqual(outcomes(agent), ["fake/slow-tool:done"]);
  assert.equal(result(agent), "tests pass");
});

test("a tool call that outlives the tool limit is a stall too, and names the command", async () => {
  const manager = make({ timing: { toolStallMs: 500 } });
  const done = finished(manager);
  const agent = manager.spawn(spawnOpts({ chain: ["fake/slow", "fake/ok"] }));
  await done;
  assert.deepEqual(outcomes(agent), ["fake/slow:stalled", "fake/ok:done"]);
  assert.match(agent.attempts[0].reason!, /while a tool call was running \(bash: sleep 30\)/);
});

test("when every model fails, the agent fails with each one's reason", async () => {
  const manager = make();
  const done = finished(manager);
  const agent = manager.spawn(spawnOpts({ chain: ["fake/reject", "fake/fail-run"] }));
  await done;
  assert.equal(agent.status, "failed");
  assert.match(agent.failure!, /^every model failed: fake\/reject: did not answer a ping: 401.*; fake\/fail-run: 500 upstream overloaded$/);
});

test("the parent's own model and models the preflight refuses are skipped without a ping", async () => {
  const manager = make();
  const done = finished(manager);
  const agent = manager.spawn(
    spawnOpts({
      chain: ["fake/parent", "fake/nokey", "fake/ok"],
      parentModel: "fake/parent",
      preflight: async (model) => (model === "fake/nokey" ? "no credentials" : undefined),
    }),
  );
  await done;
  assert.deepEqual(outcomes(agent), ["fake/parent:skipped", "fake/nokey:skipped", "fake/ok:done"]);
  assert.deepEqual(agent.attempts.slice(0, 2).map((a) => a.reason), ["it is the delegating agent's own model", "no credentials"]);
});

test("the local model runs lean and one at a time; a second local task falls through", async () => {
  const manager = make({ timing: { localStallMs: 5000 } });
  const first = manager.spawn(spawnOpts({ type: "text", chain: ["ollama/small"], tools: [], task: "first, SLOWLY" }));
  while (first.attempts[0]?.outcome !== "running") await new Promise((r) => setTimeout(r, 20));
  const done = finished(manager);
  const second = manager.spawn(spawnOpts({ type: "text", chain: ["ollama/small", "fake/ok"], tools: [], task: "second" }));
  await manager.wait([first.id, second.id]);
  await done;
  assert.match(result(first), /^env=1 tools=none lean=true/);
  assert.deepEqual(outcomes(second), ["ollama/small:skipped", "fake/ok:done"]);
  assert.equal(second.attempts[0].reason, "the local model is busy with another subagent");
});

test("stop ends a running agent as stopped, with no fallback", async () => {
  const manager = make({ timing: { toolStallMs: 60_000 } });
  const agent = manager.spawn(spawnOpts({ chain: ["fake/slow", "fake/ok"] }));
  while (agent.attempts[0]?.outcome !== "running") await new Promise((r) => setTimeout(r, 20));
  await manager.stop(agent.id);
  assert.equal(agent.status, "stopped");
  assert.deepEqual(outcomes(agent), ["fake/slow:stopped"]);
});

test("stop during a ping ends the agent at once", async () => {
  const manager = make({ timing: { pingTimeoutMs: 10_000 } });
  const agent = manager.spawn(spawnOpts({ chain: ["fake/hang", "fake/ok"] }));
  while (agent.attempts[0]?.outcome !== "pinging") await new Promise((r) => setTimeout(r, 20));
  const started = Date.now();
  await manager.stop(agent.id);
  assert.ok(Date.now() - started < 500);
  assert.equal(agent.status, "stopped");
});

test("wait resolves when every listed agent is finished, and on abort", async () => {
  const manager = make({ timing: { toolStallMs: 60_000 } });
  const a = manager.spawn(spawnOpts());
  const b = manager.spawn(spawnOpts({ chain: ["fake/reject"] }));
  const both = await manager.wait([a.id, b.id]);
  assert.deepEqual(both.map((x) => x.status), ["done", "failed"]);

  const slow = manager.spawn(spawnOpts({ chain: ["fake/slow"] }));
  const controller = new AbortController();
  setTimeout(() => controller.abort(), 200);
  const [still] = await manager.wait([slow.id], controller.signal);
  assert.equal(still.status, "running");
  await manager.stop(slow.id);
  await assert.rejects(manager.wait(["agent-99"]), /unknown subagent/);
});

test("by the time change listeners hear of a finish, the agent is no longer running", async () => {
  const manager = make();
  const seen: number[] = [];
  manager.onChange(() => seen.push(manager.running().length));
  const done = finished(manager);
  manager.spawn(spawnOpts());
  assert.equal(seen.at(-1), 1);
  await done;
  assert.equal(seen.at(-1), 0);
});

test("enforces the running cap, and rejects an empty or oversized task", async () => {
  const manager = make({ maxRunning: 1, timing: { toolStallMs: 60_000 } });
  manager.spawn(spawnOpts({ chain: ["fake/slow"] }));
  assert.throws(() => manager.spawn(spawnOpts()), /1 subagents are already running/);
  await manager.shutdown();
  const fresh = make();
  assert.throws(() => fresh.spawn(spawnOpts({ task: "  " })), /empty/);
  assert.throws(() => fresh.spawn(spawnOpts({ task: "x".repeat(300 * 1024) })), /put the material in a file/);
});

test("history is added only when an earlier attempt got as far as tools", () => {
  assert.equal(withHistory("t", [{ model: "a/b", outcome: "skipped", reason: "no" }]), "t");
});
