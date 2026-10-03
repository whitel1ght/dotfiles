import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { describeModelProfiles, spawnDescription } from "./src/prompt.ts";
import { parseModelPolicy } from "./src/model-policy.ts";
import { parseRoster } from "./src/roster.ts";

const read = (name: string) => JSON.parse(readFileSync(new URL(`../../${name}`, import.meta.url), "utf8"));
const committed = read("subagents.json");
const policy = parseModelPolicy(read("subagent-models.json"));

test("the spawn description lists the types and the model profiles", () => {
  const description = spawnDescription(parseRoster(committed, policy));
  assert.match(description, /Task types:/);
  assert.match(description, /Model profiles, to replace a type's list with `modelProfile`:/);
  assert.match(description, /- current: @parent/);
  assert.match(description, /- free: only models that cost nothing/);
  assert.match(description, /- local: ollama\/qwen2\.5-coder:14b-16k/);
  assert.match(description, /- flash: opencode-go\/glm-5\.3-flash → /);
});

test("with no profiles the description says nothing about them", () => {
  const models = ["a/one", "b/two", "c/three", "claude-bridge/c"];
  const tiny = parseModelPolicy({
    evidenceDate: "2026-10-03",
    models: Object.fromEntries(models.map((ref) => [ref, meta(ref)])),
    rankings: { x: { budget: ["a/one"], balanced: models, premium: ["claude-bridge/c"], rationale: { budget: "b", balanced: "m", premium: "p" } } },
  });
  const roster = parseRoster({ localModel: "ollama/small", taskTypes: { x: { use: "u", tools: [] } } }, tiny);
  assert.equal(describeModelProfiles(roster), "");
  assert.doesNotMatch(spawnDescription(roster), /modelProfile/);
});

function meta(ref: string) {
  return { label: ref, provider: ref.split("/")[0], quality: "q", speed: "s", cost: "c", bestFor: ["x"], strengths: ["y"], avoidFor: ["z"] };
}
