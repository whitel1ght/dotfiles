import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { describeModelProfiles, SELECT_MODELS_DESCRIPTION, SELECT_MODELS_GUIDELINES, spawnDescription } from "./src/prompt.ts";
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

test("the selector guidance covers named flows only, once, with reuse and auto-assignment", () => {
  const guidance = SELECT_MODELS_GUIDELINES.join("\n");
  assert.match(guidance, /agent_select_models/);
  assert.match(guidance, /named multi-agent flow/);
  assert.match(guidance, /plan the initial roster/i);
  assert.match(guidance, /call agent_select_models once for it/);
  assert.match(guidance, /stable `flow`/);
  assert.match(guidance, /reuse the chosen model for each known role as agent_spawn's `model`/i);
  assert.match(guidance, /later roles yourself/i);
  assert.match(guidance, /fails because there is no interactive terminal, do not pretend the user chose/);
  assert.match(SELECT_MODELS_DESCRIPTION, /fails with an error instead of choosing for the user/);
  assert.match(guidance, /never .*one-off/i);
  assert.match(guidance, /cancelled/);
});

test("agent_spawn's model wording says to try it first, not to start further down", () => {
  assert.match(spawnDescription(parseRoster(committed, policy)), /try .*first/i);
  assert.doesNotMatch(spawnDescription(parseRoster(committed, policy)), /further down/);
});

function meta(ref: string) {
  return { label: ref, provider: ref.split("/")[0], quality: "q", speed: "s", cost: "c", bestFor: ["x"], strengths: ["y"], avoidFor: ["z"] };
}
