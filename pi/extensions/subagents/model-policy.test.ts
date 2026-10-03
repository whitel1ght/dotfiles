import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { modelsFor, parseModelPolicy, selectableModels } from "./src/model-policy.ts";
import { parseRoster } from "./src/roster.ts";

const read = (name: string) => JSON.parse(readFileSync(new URL(`../../${name}`, import.meta.url), "utf8"));
const committed = read("subagent-models.json");
const roster = read("subagents.json");

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
const open3 = ["a/one", "b/two", "c/three"];
const balanced = [...open3, "claude-bridge/c"];

function policyWith(ranking: Record<string, unknown> = {}, top: Record<string, unknown> = {}) {
  const refs = ["a/one", "b/two", "c/three", "d/four", "claude-bridge/c", "claude-bridge/d"];
  return {
    evidenceDate: "2026-10-03",
    models: Object.fromEntries(refs.map((r) => [r, meta(r)])),
    rankings: { x: { budget: ["d/four"], balanced, premium: ["claude-bridge/d"], rationale, ...ranking } },
    ...top,
  };
}

test("the committed model policy is valid", () => {
  const policy = parseModelPolicy(committed);
  assert.match(policy.evidenceDate, /^\d{4}-\d{2}-\d{2}$/);
  assert.ok(policy.models.size > 0);
  for (const [ref, model] of policy.models) assert.equal(model.ref, ref);
  parseRoster(roster, policy);
});

test("evidence date and every tier rationale are required", () => {
  assert.throws(() => parseModelPolicy(policyWith({}, { evidenceDate: undefined })), /evidenceDate/);
  assert.throws(() => parseModelPolicy(policyWith({}, { evidenceDate: "last week" })), /evidenceDate/);
  for (const tier of ["budget", "balanced", "premium"]) {
    const partial = { ...rationale, [tier]: undefined };
    assert.throws(() => parseModelPolicy(policyWith({ rationale: partial })), new RegExp(`rationale\\.${tier}`));
  }
});

test("every task has budget balanced and premium rankings", () => {
  for (const tier of ["budget", "balanced", "premium"]) {
    assert.throws(() => parseModelPolicy(policyWith({ [tier]: undefined })), new RegExp(`rankings\\.x\\.${tier}`));
    assert.throws(() => parseModelPolicy(policyWith({ [tier]: [] })), new RegExp(`rankings\\.x\\.${tier}`));
  }
  const policy = parseModelPolicy(committed);
  const types = Object.keys(roster.taskTypes);
  assert.deepEqual([...policy.rankings.keys()].sort(), [...types].sort());
  for (const type of types) for (const tier of ["budget", "balanced", "premium"] as const) assert.ok(modelsFor(policy, type, tier).length > 0);
});

test("ranked models must exist in the catalog", () => {
  assert.throws(() => parseModelPolicy(policyWith({ budget: ["z/missing"] })), /rankings\.x\.budget.*z\/missing.*catalog/);
  assert.throws(() => parseModelPolicy(policyWith({ premium: ["z/missing"] })), /rankings\.x\.premium/);
});

test("direct anthropic models are rejected", () => {
  const withAnthropic = policyWith({ premium: ["anthropic/claude-opus-5-5"] });
  (withAnthropic.models as Record<string, unknown>)["anthropic/claude-opus-5-5"] = meta("anthropic/claude-opus-5-5");
  assert.throws(() => parseModelPolicy(withAnthropic), /bills the API key/);
  const inCatalog = policyWith();
  (inCatalog.models as Record<string, unknown>)["anthropic/x"] = meta("anthropic/x");
  assert.throws(() => parseModelPolicy(inCatalog), /bills the API key/);
});

test("duplicate ranked models identify their field", () => {
  assert.throws(() => parseModelPolicy(policyWith({ budget: ["d/four", "d/four"] })), /rankings\.x\.budget lists d\/four twice/);
  assert.throws(() => parseModelPolicy(policyWith({ balanced: ["a/one", ...balanced] })), /rankings\.x\.balanced lists a\/one twice/);
});

test("balanced rankings end in one Claude Bridge fallback", () => {
  assert.throws(() => parseModelPolicy(policyWith({ balanced: open3 })), /rankings\.x\.balanced.*exactly one claude-bridge/);
  assert.throws(() => parseModelPolicy(policyWith({ balanced: ["claude-bridge/d", ...balanced] })), /exactly one claude-bridge/);
  assert.throws(() => parseModelPolicy(policyWith({ balanced: ["a/one", "b/two", "claude-bridge/c"] })), /at least 3/);
  // Budget and premium are not held to the balanced invariant.
  parseModelPolicy(policyWith({ budget: ["d/four"], premium: ["claude-bridge/c", "claude-bridge/d"] }));
});

test("the local model is absent from policy rankings", () => {
  const policy = parseModelPolicy(committed);
  assert.ok(roster.localModel);
  for (const type of policy.rankings.keys()) {
    for (const tier of ["budget", "balanced", "premium"] as const) assert.ok(!modelsFor(policy, type, tier).includes(roster.localModel));
  }
  assert.ok(!policy.models.has(roster.localModel));
  const local = parseModelPolicy(policyWith({ budget: ["d/four"] }));
  assert.throws(() => parseRoster({ localModel: "d/four", taskTypes: { x: { use: "u", tools: [] } } }, local), /only used when asked for by name/);
});

test("all curated provider families appear in the committed catalog", () => {
  const providers = new Set([...parseModelPolicy(committed).models.values()].map((m) => m.provider));
  for (const family of ["opencode-go", "claude-bridge", "openai"]) assert.ok(providers.has(family), family);
});

test("selectable models run budget, balanced, premium with duplicates removed", () => {
  const policy = parseModelPolicy(policyWith({ budget: ["d/four", "a/one"], premium: ["claude-bridge/d", "b/two"] }));
  assert.deepEqual(
    selectableModels(policy, "x").map((m) => m.ref),
    ["d/four", "a/one", "b/two", "c/three", "claude-bridge/c", "claude-bridge/d"],
  );
  assert.throws(() => modelsFor(policy, "nope", "budget"), /nope/);
});
