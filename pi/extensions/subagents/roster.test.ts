import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { parseModelPolicy } from "./src/model-policy.ts";
import { chainFor, chainForProfile, describeRoster, parseRoster, splitModel } from "./src/roster.ts";

const read = (name: string) => JSON.parse(readFileSync(new URL(`../../${name}`, import.meta.url), "utf8"));
const committed = read("subagents.json");
const committedPolicy = parseModelPolicy(read("subagent-models.json"));

const open3 = ["a/one", "b/two", "c/three"];
const list = [...open3, "claude-bridge/claude-sonnet-5-5"];

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

// A policy whose every named task ranks `balanced` and, optionally, other tiers.
function policyFor(rankings: Record<string, { balanced: string[]; budget?: string[]; premium?: string[] }>) {
  const refs = new Set<string>();
  const ranked = Object.fromEntries(
    Object.entries(rankings).map(([name, r]) => {
      const full = { budget: r.budget ?? [r.balanced[0]], balanced: r.balanced, premium: r.premium ?? [r.balanced.at(-1)!] };
      for (const ref of [...full.budget, ...full.balanced, ...full.premium]) refs.add(ref);
      return [name, { ...full, rationale: { budget: "b", balanced: "m", premium: "p" } }];
    }),
  );
  return parseModelPolicy({
    evidenceDate: "2026-10-03",
    models: Object.fromEntries([...refs].map((r) => [r, meta(r)])),
    rankings: ranked,
  });
}

// Every task type named in `taskTypes` ranks `models` (default `list`).
function rosterWith(taskTypes: Record<string, unknown>, extra = {}, models: string[] = list) {
  const policy = policyFor(Object.fromEntries(Object.keys(taskTypes).map((name) => [name, { balanced: models }])));
  return parseRoster({ localModel: "ollama/small", taskTypes, ...extra }, policy);
}
const typeOf = (tools: string[] = []) => ({ use: "u", tools });

test("the committed subagents.json is valid, and every list ends with Claude", () => {
  const roster = parseRoster(committed, committedPolicy);
  assert.equal(roster.localModel, "ollama/qwen2.5-coder:14b-16k");
  assert.equal(roster.timing.stallMs, 120_000);
  assert.ok(roster.types.size >= 5);
  for (const type of roster.types.values()) {
    assert.ok(type.models.length >= 4, type.name);
    assert.match(type.models.at(-1)!, /^claude-bridge\//, type.name);
  }
});

test("a roster type needs a ranking in the policy, and the local model may not be in it", () => {
  const policy = policyFor({ x: { balanced: list } });
  assert.throws(() => parseRoster({ taskTypes: { y: typeOf() } }, policy), /no ranking for y/);
  assert.throws(() => parseRoster({ localModel: "a/one", taskTypes: { x: typeOf() } }, policy), /only used when asked for by name/);
});

test("timing defaults, and refuses nonsense", () => {
  const roster = rosterWith({ x: typeOf() });
  assert.deepEqual(roster.timing, {
    pingTimeoutMs: 20_000,
    pingCacheMs: 300_000,
    stallMs: 120_000,
    toolStallMs: 900_000,
    localStallMs: 300_000,
  });
  assert.throws(() => rosterWith({ x: typeOf() }, { timing: { stallSeconds: 0 } }), /positive/);
});

test("models must be provider/id", () => {
  assert.deepEqual(splitModel("ollama/qwen2.5-coder:14b-16k"), { provider: "ollama", id: "qwen2.5-coder:14b-16k" });
});

test("the chain is the balanced list, led by a selected compatible model, or by the local model", () => {
  const policy = policyFor({
    text: { balanced: list, budget: ["d/four"], premium: ["claude-bridge/opus"] },
    explore: { balanced: list, budget: ["d/four"], premium: ["claude-bridge/opus"] },
  });
  const roster = parseRoster({ localModel: "ollama/small", taskTypes: { text: typeOf(), explore: typeOf(["read"]) } }, policy);
  const text = roster.types.get("text")!;
  const explore = roster.types.get("explore")!;
  assert.deepEqual(chainFor(roster, explore), list);
  assert.deepEqual(chainFor(roster, explore, "claude-bridge/opus"), ["claude-bridge/opus", ...list]);
  assert.deepEqual(chainFor(roster, explore, "d/four"), ["d/four", ...list]);
  assert.deepEqual(chainFor(roster, explore, "b/two"), ["b/two", "a/one", "c/three", "claude-bridge/claude-sonnet-5-5"]);
  assert.deepEqual(chainFor(roster, text, "ollama/small"), ["ollama/small", ...list]);
  assert.deepEqual([...explore.compatible].sort(), ["a/one", "b/two", "c/three", "claude-bridge/claude-sonnet-5-5", "claude-bridge/opus", "d/four"]);
  assert.throws(() => chainFor(roster, explore, "ollama/small"), /cannot use tools/);
  assert.throws(() => chainFor(roster, explore, "z/other"), /not compatible with explore/);
  assert.throws(() => chainFor(roster, text, "z/other"), /, or ollama\/small$/);
});

test("a catalog model outside a task's tiers is rejected for that task", () => {
  const policy = parseModelPolicy({
    evidenceDate: "2026-10-03",
    models: Object.fromEntries([...list, "e/five"].map((r) => [r, meta(r)])),
    rankings: { x: { budget: ["a/one"], balanced: list, premium: ["claude-bridge/claude-sonnet-5-5"], rationale: { budget: "b", balanced: "m", premium: "p" } } },
  });
  const roster = parseRoster({ taskTypes: { x: typeOf() } }, policy);
  assert.throws(() => chainFor(roster, roster.types.get("x")!, "e/five"), /not compatible with x/);
});

test("the description lists every type, its tools and its chain", () => {
  const text = describeRoster(parseRoster(committed, committedPolicy));
  assert.match(text, /- text: .*\n  tools: none\n  models, best first: opencode-go\/glm-5\.3-flash → /);
  assert.match(text, /- implement: .*\n  tools: read, grep, find, ls, bash, edit, write\n  models, best first: .* → claude-bridge\/claude-sonnet-5-5/);
});

test("the committed subagents.json carries the four model profiles", () => {
  const roster = parseRoster(committed, committedPolicy);
  assert.deepEqual([...roster.modelProfiles.keys()], ["current", "free", "local", "flash"]);
  assert.deepEqual(roster.modelProfiles.get("current")!.models, ["@parent"]);
  assert.equal(roster.modelProfiles.get("free")!.freeOnly, true);
  assert.deepEqual(roster.modelProfiles.get("local")!.models, ["ollama/qwen2.5-coder:14b-16k"]);
});

test("a model profile sets exactly one of models or freeOnly, and its list is well formed", () => {
  const types = { x: typeOf() };
  const withProfiles = (modelProfiles: unknown) => rosterWith(types, { modelProfiles });
  assert.throws(() => withProfiles({ p: {} }), /exactly one of models or freeOnly/);
  assert.throws(() => withProfiles({ p: { models: ["a/one"], freeOnly: true } }), /exactly one of models or freeOnly/);
  assert.throws(() => withProfiles({ p: { freeOnly: false } }), /freeOnly must be true/);
  assert.throws(() => withProfiles({ p: { models: [] } }), /is empty/);
  assert.throws(() => withProfiles({ p: { models: ["bare"] } }), /provider\/id/);
  assert.throws(() => withProfiles({ p: { models: ["a/one", "a/one"] } }), /twice/);
  assert.throws(() => withProfiles({ p: { models: ["anthropic/x"] } }), /bills the API key/);
  assert.throws(() => withProfiles([]), /modelProfiles must be an object/);
});

test("a profile replaces the type's list: @parent, a fixed list, or the zero-cost pool", () => {
  const types = {
    text: typeOf(),
    explore: typeOf(["read"]),
  };
  const roster = rosterWith(types, {
    modelProfiles: { current: { models: ["@parent"] }, local: { models: ["ollama/small"] }, free: { freeOnly: true } },
  });
  const text = roster.types.get("text")!;
  const explore = roster.types.get("explore")!;
  const profile = (name: string) => roster.modelProfiles.get(name)!;
  const free = (model: string) => model === "claude-bridge/claude-sonnet-5-5";

  assert.deepEqual(chainForProfile(roster, profile("current"), explore, "opencode-go/x", free), ["opencode-go/x"]);
  assert.deepEqual(chainForProfile(roster, profile("local"), text, "opencode-go/x", free), ["ollama/small"]);
  assert.deepEqual(chainForProfile(roster, profile("free"), explore, "opencode-go/x", free), ["claude-bridge/claude-sonnet-5-5"]);
  assert.deepEqual(
    chainForProfile(roster, { name: "p", models: ["@parent", "z/fallback"], freeOnly: false }, text, "opencode-go/x", free),
    ["opencode-go/x", "z/fallback"],
  );
  assert.throws(() => chainForProfile(roster, profile("current"), explore, undefined, free), /no current model/);
  assert.throws(() => chainForProfile(roster, profile("local"), explore, "opencode-go/x", free), /cannot use tools/);
  assert.throws(() => chainForProfile(roster, profile("free"), explore, "opencode-go/x", () => false), /cost nothing/);
});

test("the free pool keeps the type's own free model first, then the rest", () => {
  const policy = policyFor({
    text: { balanced: [...open3, "claude-bridge/haiku"] },
    reason: { balanced: [...open3, "claude-bridge/opus"] },
  });
  const roster = parseRoster(
    { localModel: "ollama/small", taskTypes: { text: typeOf(), reason: typeOf(["read"]) }, modelProfiles: { free: { freeOnly: true } } },
    policy,
  );
  const profile = roster.modelProfiles.get("free")!;
  const free = (model: string) => model.startsWith("claude-bridge/");
  assert.deepEqual(chainForProfile(roster, profile, roster.types.get("reason")!, "x/y", free), [
    "claude-bridge/opus",
    "claude-bridge/haiku",
  ]);
  assert.deepEqual(chainForProfile(roster, profile, roster.types.get("text")!, "x/y", free), [
    "claude-bridge/haiku",
    "claude-bridge/opus",
  ]);
});
