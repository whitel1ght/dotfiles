import assert from "node:assert/strict";
import { test } from "node:test";
import { parseModelPolicy } from "./src/model-policy.ts";
import { parseRoster } from "./src/roster.ts";
import type { AgentModelRequest } from "./src/selection.ts";
import { createModelSelector, registryModels, type SelectorEnv } from "./src/select-models-tool.ts";

const meta = (ref: string) => ({
  label: ref,
  provider: ref.split("/")[0],
  quality: "q",
  speed: "s",
  cost: "c",
  bestFor: ["x"],
  strengths: ["y"],
  avoidFor: ["z"],
});
const refs = ["a/one", "b/two", "c/three", "d/four", "claude-bridge/c", "claude-bridge/d"];
const policy = parseModelPolicy({
  evidenceDate: "2026-10-03",
  models: Object.fromEntries(refs.map((r) => [r, meta(r)])),
  rankings: {
    x: {
      budget: ["d/four"],
      balanced: ["a/one", "b/two", "c/three", "claude-bridge/c"],
      premium: ["claude-bridge/d"],
      rationale: { budget: "b", balanced: "m", premium: "p" },
    },
  },
});
const roster = parseRoster({ taskTypes: { x: { use: "u", tools: [] } } }, policy);
const request = (key: string, recommendedModel = "a/one"): AgentModelRequest => ({
  key,
  title: `Agent ${key}`,
  type: "x",
  recommendedModel,
  recommendation: "fits",
});

function setup(over: Partial<SelectorEnv> = {}, result: "confirm" | "escape" = "confirm") {
  let opened = 0;
  const env: SelectorEnv = {
    mode: "tui",
    hasUI: true,
    isChild: false,
    available: () => new Set(refs),
    openPicker: async (state) => {
      opened++;
      if (result === "escape") return undefined;
      state.moveModel(1);
      return state.result();
    },
    ...over,
  };
  const select = createModelSelector(roster, policy);
  return { select, env, opened: () => opened };
}

test("confirmation returns every role's chosen model and caches it by flow", async () => {
  const { select, env, opened } = setup();
  const result = await select({ flow: "f:1", agents: [request("a"), request("b")] }, env);
  assert.deepEqual(result.details, {
    flow: "f:1",
    cancelled: false,
    selections: [
      { key: "a", model: "b/two" },
      { key: "b", model: "a/one" },
    ],
  });
  assert.match(result.text, /a: b\/two/);
  assert.equal(opened(), 1);
  const again = await select({ flow: "f:1", agents: [request("a"), request("b")] }, env);
  assert.deepEqual(again.details, result.details);
  assert.equal(opened(), 1);
});

test("a repeat flow keeps known roles and auto-assigns new ones without prompting", async () => {
  const { select, env, opened } = setup();
  await select({ flow: "f:1", agents: [request("a")] }, env);
  const again = await select({ flow: "f:1", agents: [request("a"), request("late", "c/three")] }, env);
  assert.deepEqual(again.details.selections, [
    { key: "a", model: "b/two" },
    { key: "late", model: "c/three" },
  ]);
  assert.equal(opened(), 1);
});

test("a new flow opens a fresh picker", async () => {
  const { select, env, opened } = setup();
  await select({ flow: "f:1", agents: [request("a")] }, env);
  await select({ flow: "f:2", agents: [request("a")] }, env);
  assert.equal(opened(), 2);
});

test("Escape cancels, returns no selections and caches nothing", async () => {
  const cancelled = setup({}, "escape");
  const result = await cancelled.select({ flow: "f:1", agents: [request("a")] }, cancelled.env);
  assert.deepEqual(result.details, { flow: "f:1", cancelled: true, selections: [] });
  assert.match(result.text, /stop/i);
  await cancelled.select({ flow: "f:1", agents: [request("a")] }, cancelled.env);
  assert.equal(cancelled.opened(), 2);
});

test("outside the interactive parent TUI the call fails clearly and opens no picker", async () => {
  for (const over of [
    { mode: "rpc" as const },
    { mode: "print" as const },
    { mode: "json" as const },
    { hasUI: false },
    { isChild: true },
  ]) {
    const { select, env, opened } = setup(over);
    await assert.rejects(select({ flow: "f:1", agents: [request("a", "c/three"), request("b")] }, env), /interactive terminal UI/);
    assert.equal(opened(), 0);
  }
});

test("a cached model that no longer fits a role's changed type falls back to the recommendation without prompting", async () => {
  const two = parseModelPolicy({
    evidenceDate: "2026-10-03",
    models: Object.fromEntries(refs.map((r) => [r, meta(r)])),
    rankings: {
      x: { budget: ["d/four"], balanced: ["a/one", "b/two", "c/three", "claude-bridge/c"], premium: ["claude-bridge/d"], rationale: { budget: "b", balanced: "m", premium: "p" } },
      y: { budget: ["d/four"], balanced: ["a/one", "c/three", "d/four", "claude-bridge/c"], premium: ["claude-bridge/d"], rationale: { budget: "b", balanced: "m", premium: "p" } },
    },
  });
  const r2 = parseRoster({ taskTypes: { x: { use: "u", tools: [] }, y: { use: "u", tools: [] } } }, two);
  const select = createModelSelector(r2, two);
  let opened = 0;
  const env: SelectorEnv = {
    mode: "tui",
    hasUI: true,
    isChild: false,
    available: () => new Set(refs),
    openPicker: async (state) => {
      opened++;
      state.moveModel(1);
      return state.result();
    },
  };
  const first = await select({ flow: "f", agents: [request("a")] }, env);
  assert.deepEqual(first.details.selections, [{ key: "a", model: "b/two" }]);
  const again = await select({ flow: "f", agents: [{ ...request("a", "c/three"), type: "y" }] }, env);
  assert.deepEqual(again.details.selections, [{ key: "a", model: "c/three" }]);
  assert.equal(opened, 1);
});

function gate() {
  let release!: (value: "confirm" | "cancel" | Error) => void;
  const done = new Promise<"confirm" | "cancel" | Error>((resolve) => (release = resolve));
  return { done, release };
}

test("overlapping first calls for one flow open a single picker; each payload keeps known choices and auto-fills new roles", async () => {
  const g = gate();
  let opened = 0;
  const { select, env } = setup({
    openPicker: async (state) => {
      opened++;
      await g.done;
      state.moveModel(1);
      return state.result();
    },
  });
  const one = select({ flow: "f", agents: [request("a")] }, env);
  const two = select({ flow: "f", agents: [request("a"), request("late", "c/three")] }, env);
  await new Promise((r) => setImmediate(r));
  g.release("confirm");
  const [r1, r2] = await Promise.all([one, two]);
  assert.equal(opened, 1);
  assert.deepEqual(r1.details.selections, [{ key: "a", model: "b/two" }]);
  assert.deepEqual(r2.details.selections, [
    { key: "a", model: "b/two" },
    { key: "late", model: "c/three" },
  ]);
});

test("overlapping calls all see the cancellation and nothing is cached or left in flight", async () => {
  const g = gate();
  let opened = 0;
  const { select, env } = setup({
    openPicker: async () => {
      opened++;
      await g.done;
      return undefined;
    },
  });
  const calls = [select({ flow: "f", agents: [request("a")] }, env), select({ flow: "f", agents: [request("a")] }, env)];
  await new Promise((r) => setImmediate(r));
  g.release("cancel");
  for (const r of await Promise.all(calls)) assert.equal(r.details.cancelled, true);
  assert.equal(opened, 1);
  await select({ flow: "f", agents: [request("a")] }, env);
  assert.equal(opened, 2);
});

test("a failing picker rejects every overlapping call and leaves no cache or stuck in-flight entry", async () => {
  const g = gate();
  let opened = 0;
  let fail = true;
  const { select, env } = setup({
    openPicker: async (state) => {
      opened++;
      if (fail) {
        await g.done;
        throw new Error("tui crashed");
      }
      return state.result();
    },
  });
  const calls = [select({ flow: "f", agents: [request("a")] }, env), select({ flow: "f", agents: [request("a")] }, env)];
  const settled = Promise.allSettled(calls);
  await new Promise((r) => setImmediate(r));
  g.release("cancel");
  for (const r of await settled) {
    assert.equal(r.status, "rejected");
    assert.match(String((r as PromiseRejectedResult).reason), /tui crashed/);
  }
  fail = false;
  const retry = await select({ flow: "f", agents: [request("a")] }, env);
  assert.equal(retry.details.cancelled, false);
  assert.equal(opened, 2);
});

test("a blank flow and invalid requests are rejected before any picker opens", async () => {
  const { select, env, opened } = setup();
  await assert.rejects(select({ flow: "  ", agents: [request("a")] }, env), /flow/);
  await assert.rejects(select({ flow: "f", agents: [request("a"), request("a")] }, env), /duplicate/);
  assert.equal(opened(), 0);
});

test("when availability cannot be determined the picker is not opened and the error says so", async () => {
  const { select, env, opened } = setup({
    available: () => {
      throw new Error("registry down");
    },
  });
  await assert.rejects(select({ flow: "f", agents: [request("a")] }, env), /cannot determine available models.*registry down/);
  assert.equal(opened(), 0);
});

test("the picker is given the real available set so unavailable models block", async () => {
  let seen: ReadonlySet<string> | undefined;
  const { select, env } = setup({
    available: () => new Set(["a/one"]),
    openPicker: async (state, available) => {
      seen = available;
      return state.result();
    },
  });
  await select({ flow: "f", agents: [request("a")] }, env);
  assert.deepEqual([...seen!], ["a/one"]);
});

test("registry models become provider/id strings", () => {
  assert.deepEqual([...registryModels([{ provider: "a", id: "one" }, { provider: "claude-bridge", id: "c" }])], ["a/one", "claude-bridge/c"]);
});
