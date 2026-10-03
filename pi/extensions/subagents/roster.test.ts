import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { chainFor, chainForProfile, describeRoster, parseRoster, splitModel } from "./src/roster.ts";

const committed = JSON.parse(readFileSync(new URL("../../subagents.json", import.meta.url), "utf8"));

const open3 = ["a/one", "b/two", "c/three"];
const list = [...open3, "claude-bridge/claude-sonnet-5-5"];

function rosterWith(taskTypes: unknown, extra = {}) {
  return parseRoster({ localModel: "ollama/small", taskTypes, ...extra });
}

test("the committed subagents.json is valid, and every list ends with Claude", () => {
  const roster = parseRoster(committed);
  assert.equal(roster.localModel, "ollama/qwen2.5-coder:14b-16k");
  assert.equal(roster.timing.stallMs, 120_000);
  assert.ok(roster.types.size >= 5);
  for (const type of roster.types.values()) {
    assert.ok(type.models.length >= 4, type.name);
    assert.match(type.models.at(-1)!, /^claude-bridge\//, type.name);
  }
});

test("each list needs three models and then exactly one Claude fallback, last", () => {
  assert.throws(() => rosterWith({ x: { use: "u", tools: [], models: ["a/one", "b/two", "claude-bridge/c"] } }), /at least 3/);
  assert.throws(() => rosterWith({ x: { use: "u", tools: [], models: open3 } }), /must end with exactly one claude-bridge/);
  assert.throws(
    () => rosterWith({ x: { use: "u", tools: [], models: ["claude-bridge/c", ...list] } }),
    /must end with exactly one claude-bridge/,
  );
});

test("anthropic/* is refused, since it bills the API key", () => {
  assert.throws(() => rosterWith({ x: { use: "u", tools: [], models: [...open3, "anthropic/claude-opus-5-5"] } }), /bills the API key/);
});

test("the local model may not sit in a list, and duplicates are refused", () => {
  assert.throws(() => rosterWith({ x: { use: "u", tools: [], models: ["ollama/small", ...list] } }), /only used when asked for by name/);
  assert.throws(() => rosterWith({ x: { use: "u", tools: [], models: ["a/one", ...list] } }), /twice/);
});

test("timing defaults, and refuses nonsense", () => {
  const roster = rosterWith({ x: { use: "u", tools: [], models: list } });
  assert.deepEqual(roster.timing, {
    pingTimeoutMs: 20_000,
    pingCacheMs: 300_000,
    stallMs: 120_000,
    toolStallMs: 900_000,
    localStallMs: 300_000,
  });
  assert.throws(() => rosterWith({ x: { use: "u", tools: [], models: list } }, { timing: { stallSeconds: 0 } }), /positive/);
});

test("models must be provider/id", () => {
  assert.throws(() => rosterWith({ x: { use: "u", tools: [], models: ["bare", ...list] } }), /provider\/id/);
  assert.deepEqual(splitModel("ollama/qwen2.5-coder:14b-16k"), { provider: "ollama", id: "qwen2.5-coder:14b-16k" });
});

test("the chain is the whole list, starts at a named model, or puts the local model first", () => {
  const roster = rosterWith({
    text: { use: "u", tools: [], models: list },
    explore: { use: "u", tools: ["read"], models: list },
  });
  const text = roster.types.get("text")!;
  const explore = roster.types.get("explore")!;
  assert.deepEqual(chainFor(roster, explore), list);
  assert.deepEqual(chainFor(roster, explore, "b/two"), list.slice(1));
  assert.deepEqual(chainFor(roster, text, "ollama/small"), ["ollama/small", ...list]);
  assert.throws(() => chainFor(roster, explore, "ollama/small"), /cannot use tools/);
  assert.throws(() => chainFor(roster, explore, "z/other"), /not on the explore list/);
  assert.throws(() => chainFor(roster, text, "z/other"), /, or ollama\/small$/);
});

test("the description lists every type, its tools and its chain", () => {
  const text = describeRoster(parseRoster(committed));
  assert.match(text, /- text: .*\n  tools: none\n  models, best first: opencode-go\/glm-5\.3-flash → /);
  assert.match(text, /- implement: .*\n  tools: read, grep, find, ls, bash, edit, write\n  models, best first: .* → claude-bridge\/claude-sonnet-5-5/);
});

test("the committed subagents.json carries the four model profiles", () => {
  const roster = parseRoster(committed);
  assert.deepEqual([...roster.modelProfiles.keys()], ["current", "free", "local", "flash"]);
  assert.deepEqual(roster.modelProfiles.get("current")!.models, ["@parent"]);
  assert.equal(roster.modelProfiles.get("free")!.freeOnly, true);
  assert.deepEqual(roster.modelProfiles.get("local")!.models, ["ollama/qwen2.5-coder:14b-16k"]);
});

test("a model profile sets exactly one of models or freeOnly, and its list is well formed", () => {
  const types = { x: { use: "u", tools: [], models: list } };
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
    text: { use: "u", tools: [], models: list },
    explore: { use: "u", tools: ["read"], models: list },
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
  const types = {
    text: { use: "u", tools: [], models: ["a/one", "b/two", "c/three", "claude-bridge/haiku"] },
    reason: { use: "u", tools: ["read"], models: ["a/one", "b/two", "c/three", "claude-bridge/opus"] },
  };
  const roster = rosterWith(types, { modelProfiles: { free: { freeOnly: true } } });
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
