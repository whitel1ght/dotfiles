import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { chainFor, describeRoster, parseRoster, splitModel } from "./src/roster.ts";

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
