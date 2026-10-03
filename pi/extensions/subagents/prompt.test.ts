import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { describeModelProfiles, spawnDescription } from "./src/prompt.ts";
import { parseRoster } from "./src/roster.ts";

const committed = JSON.parse(readFileSync(new URL("../../subagents.json", import.meta.url), "utf8"));

test("the spawn description lists the types and the model profiles", () => {
  const description = spawnDescription(parseRoster(committed));
  assert.match(description, /Task types:/);
  assert.match(description, /Model profiles, to replace a type's list with `modelProfile`:/);
  assert.match(description, /- current: @parent/);
  assert.match(description, /- free: only models that cost nothing/);
  assert.match(description, /- local: ollama\/qwen2\.5-coder:14b-16k/);
  assert.match(description, /- flash: opencode-go\/glm-5\.3-flash → /);
});

test("with no profiles the description says nothing about them", () => {
  const roster = parseRoster({
    localModel: "ollama/small",
    taskTypes: { x: { use: "u", tools: [], models: ["a/one", "b/two", "c/three", "claude-bridge/c"] } },
  });
  assert.equal(describeModelProfiles(roster), "");
  assert.doesNotMatch(spawnDescription(roster), /modelProfile/);
});
