import assert from "node:assert/strict";
import { test } from "node:test";
import { parseModelPolicy } from "./src/model-policy.ts";
import { chainFor, parseRoster } from "./src/roster.ts";
import { ModelSelectionState, planLayout, validateSelectionRequests, visibleWindow, type AgentModelRequest } from "./src/selection.ts";

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
const rationale = { budget: "b", balanced: "m", premium: "p" };
const refs = ["a/one", "b/two", "c/three", "d/four", "claude-bridge/c", "claude-bridge/d", "e/outside"];
const policy = parseModelPolicy({
  evidenceDate: "2026-10-03",
  models: Object.fromEntries(refs.map((r) => [r, meta(r)])),
  rankings: {
    x: { budget: ["d/four"], balanced: ["a/one", "b/two", "c/three", "claude-bridge/c"], premium: ["claude-bridge/d"], rationale },
  },
});
const roster = parseRoster({ taskTypes: { x: { use: "u", tools: [] } } }, policy);

const request = (key: string, over: Partial<AgentModelRequest> = {}): AgentModelRequest => ({
  key,
  title: `Agent ${key}`,
  type: "x",
  recommendedModel: "a/one",
  recommendation: "fits",
  ...over,
});
const state = (requests: readonly AgentModelRequest[], available?: ReadonlySet<string>) =>
  new ModelSelectionState(requests, roster, policy, available);

test("validation accepts a well-formed batch and returns it", () => {
  const requests = [request("a"), request("b", { recommendedModel: "d/four" })];
  assert.deepEqual(validateSelectionRequests(requests, roster, policy), requests);
});

test("validation rejects empty batches, bad keys, unknown types and bad recommendations", () => {
  const bad = (requests: AgentModelRequest[], pattern: RegExp) =>
    assert.throws(() => validateSelectionRequests(requests, roster, policy), pattern);
  bad([], /at least one/);
  bad([request("a"), request("a")], /duplicate key "a"/);
  bad([request("  ")], /key must not be blank/);
  bad([request("a", { type: "nope" })], /unknown task type "nope"/);
  bad([request("a", { recommendedModel: "e/outside" })], /not compatible/);
  bad([request("a", { recommendedModel: "z/missing" })], /not compatible/);
  bad([request("a", { recommendation: " " })], /recommendation must not be blank/);
});

test("every role starts on its recommendation and reports no override", () => {
  const s = state([request("a"), request("b", { recommendedModel: "d/four" })]);
  assert.deepEqual(s.result(), [
    { key: "a", model: "a/one" },
    { key: "b", model: "d/four" },
  ]);
  const details = s.currentDetails();
  assert.equal(details.key, "a");
  assert.equal(details.overridden, false);
  assert.equal(details.metadata.provider, "a");
  assert.equal(details.recommendation, "fits");
});

test("moving models wraps and flags an override; each role keeps its own choice", () => {
  const s = state([request("a"), request("b")]);
  s.moveModel(1);
  assert.equal(s.currentDetails().model, "b/two");
  assert.equal(s.currentDetails().overridden, true);
  s.moveModel(-2);
  assert.equal(s.currentDetails().model, "d/four");
  s.moveModel(-1);
  assert.equal(s.currentDetails().model, "claude-bridge/d");
  s.moveModel(1);
  s.moveModel(-1);
  s.moveAgent(1);
  assert.equal(s.currentDetails().model, "a/one");
  assert.equal(s.currentDetails().overridden, false);
  s.moveModel(3);
  assert.deepEqual(s.result(), [
    { key: "a", model: "claude-bridge/d" },
    { key: "b", model: "claude-bridge/c" },
  ]);
});

test("moving back to the recommendation clears the override", () => {
  const s = state([request("a")]);
  s.moveModel(1);
  s.moveModel(-1);
  assert.equal(s.currentDetails().overridden, false);
});

test("agent movement wraps", () => {
  const s = state([request("a"), request("b")]);
  s.moveAgent(-1);
  assert.equal(s.currentDetails().key, "b");
  s.moveAgent(1);
  assert.equal(s.currentDetails().key, "a");
});

test("details carry the effective fallback chain with the choice first", () => {
  const s = state([request("a")]);
  s.moveModel(1);
  assert.deepEqual(s.currentDetails().fallbackChain, ["b/two", "a/one", "c/three", "claude-bridge/c"]);
});

test("an unavailable recommendation is shown but cannot be confirmed", () => {
  const s = state([request("a")], new Set(["b/two"]));
  assert.equal(s.currentDetails().available, false);
  assert.equal(s.canConfirm(), false);
  assert.throws(() => s.result(), /not available/);
  s.moveModel(1);
  assert.equal(s.currentDetails().available, true);
  assert.equal(s.canConfirm(), true);
  assert.deepEqual(s.result(), [{ key: "a", model: "b/two" }]);
});

test("a 20-role roster keeps the active row inside the visible window", () => {
  const requests = Array.from({ length: 20 }, (_, i) => request(`r${i}`));
  const s = state(requests);
  for (let step = 0; step < 25; step++) {
    const w = s.window(6);
    assert.equal(w.end - w.start, 6);
    assert.ok(s.currentDetails().index >= w.start && s.currentDetails().index < w.end);
    s.moveAgent(1);
  }
});

test("visibleWindow clamps to the list and the capacity", () => {
  assert.deepEqual(visibleWindow(3, 1, 10), { start: 0, end: 3 });
  assert.deepEqual(visibleWindow(20, 19, 5), { start: 15, end: 20 });
  assert.deepEqual(visibleWindow(20, 10, 5), { start: 8, end: 13 });
  assert.deepEqual(visibleWindow(20, 0, 0), { start: 0, end: 1 });
});

test("the layout never exceeds the available rows and keeps the active role visible", () => {
  for (let rows = 1; rows <= 45; rows++) {
    for (const total of [1, 2, 5, 20]) {
      for (const active of [0, Math.floor(total / 2), total - 1]) {
        for (const detailLines of [0, 6, 14, 40]) {
          for (const notice of [false, true]) {
            const plan = planLayout({ rows, total, active, detailLines, notice });
            const where = JSON.stringify({ rows, total, active, detailLines, notice });
            assert.ok(plan.lineCount <= rows, `${where} used ${plan.lineCount} lines`);
            assert.ok(plan.window.end - plan.window.start >= 1, where);
            assert.ok(active >= plan.window.start && active < plan.window.end, where);
            assert.ok(plan.detailLines <= detailLines, where);
          }
        }
      }
    }
  }
});

test("short terminals shed details and chrome before role rows; roomy ones keep everything", () => {
  const tight = planLayout({ rows: 5, total: 20, active: 0, detailLines: 6, notice: false });
  assert.equal(tight.detailLines, 1);
  assert.equal(tight.lineCount, 5);
  assert.equal(tight.chrome, "footer");
  const roomy = planLayout({ rows: 40, total: 3, active: 0, detailLines: 6, notice: true });
  assert.deepEqual([roomy.chrome, roomy.detailLines, roomy.window], ["full", 6, { start: 0, end: 3 }]);
  assert.equal(roomy.lineCount, 5 + 3 + 6 + 1);
});

test("the blocking notice survives short terminals when there are at least two rows", () => {
  assert.equal(planLayout({ rows: 2, total: 5, active: 0, detailLines: 6, notice: true }).notice, true);
  assert.equal(planLayout({ rows: 1, total: 5, active: 0, detailLines: 6, notice: true }).notice, false);
});

test("the fallback chain is exactly what chainFor gives spawn, for every compatible model", () => {
  const type = roster.types.get("x")!;
  const s = state([request("a")]);
  const seen = new Set<string>();
  for (let i = 0; i < type.compatible.length; i++) {
    const d = s.currentDetails();
    seen.add(d.model);
    assert.deepEqual(d.fallbackChain, chainFor(roster, type, d.model));
    s.moveModel(1);
  }
  assert.deepEqual([...seen].sort(), [...type.compatible].sort());
});

test("details flag unavailable fallbacks", () => {
  const s = state([request("a")], new Set(["a/one", "c/three"]));
  assert.deepEqual(s.currentDetails().unavailableFallbacks, ["b/two", "claude-bridge/c"]);
});

test("blocked() names the affected role and says whether any alternative exists", () => {
  assert.equal(state([request("a")]).blocked(), undefined);
  const s = state([request("a"), request("b")], new Set(["a/one", "c/three"]));
  s.moveModel(1);
  assert.deepEqual(
    { ...s.blocked()! },
    { index: 0, key: "a", title: "Agent a", model: "b/two", hasAlternative: true },
  );
  const none = state([request("z")], new Set(["e/outside"]));
  assert.equal(none.blocked()!.hasAlternative, false);
});

test("the state copies the caller's requests", () => {
  const requests = [request("a"), request("b")];
  const s = state(requests);
  requests.pop();
  requests[0] = request("changed", { recommendedModel: "b/two" });
  assert.equal(s.size(), 2);
  assert.equal(s.detailsAt(0).key, "a");
  assert.deepEqual(s.result(), [
    { key: "a", model: "a/one" },
    { key: "b", model: "a/one" },
  ]);
});
