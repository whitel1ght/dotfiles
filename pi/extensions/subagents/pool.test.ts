import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { AgentManager } from "./src/agents.ts";
import { parseModelPolicy } from "./src/model-policy.ts";
import { describePool, resolveSpawnModel, sessionModelPool } from "./src/pool.ts";
import { parseRoster } from "./src/roster.ts";

const ref = (model: string) => {
  const [provider, ...id] = model.split("/");
  return { provider, id: id.join("/") };
};
const scoped = (...models: string[]) => models.map((m) => ({ model: ref(m) }));
const available = (...models: string[]) => models.map(ref);

const read = (name: string) => JSON.parse(readFileSync(new URL(`../../${name}`, import.meta.url), "utf8"));
const policy = parseModelPolicy(read("subagent-models.json"));
const roster = parseRoster(read("subagents.json"), policy);
const explore = roster.types.get("explore")!;
const text = roster.types.get("text")!;

test("an empty scope means every authenticated model", () => {
  assert.deepEqual(sessionModelPool([], available("a/one", "b/two")), ["a/one", "b/two"]);
});

test("a scope narrows the pool, and a scoped model without credentials is not in it", () => {
  const pool = sessionModelPool(scoped("a/one", "c/gone", "b/two"), available("a/one", "b/two", "d/other"));
  assert.deepEqual(pool, ["a/one", "b/two"]);
});

test("the pool follows the live scope and credentials on every call", () => {
  const registry = available("a/one", "b/two", "c/three");
  const live = { scope: scoped("a/one") };
  const pool = () => sessionModelPool(live.scope, registry);
  assert.deepEqual(pool(), ["a/one"]);
  live.scope = scoped("a/one", "c/three");
  assert.deepEqual(pool(), ["a/one", "c/three"]);
  live.scope = [];
  assert.deepEqual(pool(), ["a/one", "b/two", "c/three"]);
});

test("model is required and must be in the session pool; the error names the pool", () => {
  const pool = ["a/one", "b/two"];
  assert.equal(resolveSpawnModel(roster, explore, pool, " b/two "), "b/two");
  assert.throws(() => resolveSpawnModel(roster, explore, pool, undefined), /model is required.*a\/one, b\/two/);
  assert.throws(() => resolveSpawnModel(roster, explore, pool, "  "), /model is required/);
  assert.throws(() => resolveSpawnModel(roster, explore, pool, "z/other"), /z\/other is not in this session's model pool.*a\/one, b\/two/);
  assert.throws(() => resolveSpawnModel(roster, explore, [], "a/one"), /no usable models/);
});

test("a model is never rejected for the type's old ranking, only for the session pool", () => {
  const outsider = "z/unlisted";
  assert.ok(!explore.compatible.includes(outsider));
  assert.equal(resolveSpawnModel(roster, explore, [outsider], outsider), outsider);
});

test("the local model cannot run a type with tools but can run a tool-less one", () => {
  const local = roster.localModel!;
  assert.throws(() => resolveSpawnModel(roster, explore, [local], local), /cannot use tools/);
  assert.equal(resolveSpawnModel(roster, text, [local], local), local);
});

test("the pool listing shows catalogue notes without ranking, and marks unknown models", () => {
  const known = [...policy.models.keys()][0];
  const listing = describePool([known, "z/unlisted"], policy);
  assert.ok(listing.includes(known));
  assert.match(listing, /z\/unlisted.*no notes/);
  assert.doesNotMatch(listing, /best first|fallback|\brank|→/i);
});

const base = mkdtempSync(join(tmpdir(), "pool-test-"));
const fakePi = [process.execPath, join(import.meta.dirname, "test", "fake-pi.mjs")];
const manager = new AgentManager({
  piCommand: fakePi,
  timing: { pingTimeoutMs: 2000, pingCacheMs: 60_000, stallMs: 400, toolStallMs: 5000, localStallMs: 400 },
  baseDir: base,
  killGraceMs: 300,
  drainMs: 100,
  watchIntervalMs: 100,
});
after(async () => {
  await manager.shutdown();
  rmSync(base, { recursive: true, force: true });
});

test("a failing chosen model fails the agent; no other model is tried", async () => {
  const done = new Promise<void>((resolve) => manager.onFinish(() => resolve()));
  const agent = manager.spawn({ type: "explore", chain: ["fake/reject"], task: "t", cwd: base, tools: ["read"] });
  await done;
  assert.equal(agent.status, "failed");
  assert.deepEqual(agent.attempts.map((a) => a.model), ["fake/reject"]);
  assert.match(agent.failure!, /^fake\/reject failed: did not answer a ping: 401/);
  assert.doesNotMatch(agent.failure!, /every model/);
});
