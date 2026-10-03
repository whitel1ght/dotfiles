import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { missingCatalogModels, parseModelPolicy } from "./src/model-policy.ts";
import { parseListModels } from "./scripts/check-model-policy.ts";
import { renderModelGuide } from "./scripts/generate-model-guide.ts";

const read = (name: string) => readFileSync(new URL(`../../${name}`, import.meta.url), "utf8");
const policy = parseModelPolicy(JSON.parse(read("subagent-models.json")));

test("the guide is deterministic and matches the committed file", () => {
  assert.equal(renderModelGuide(policy), renderModelGuide(policy));
  assert.equal(read("subagent-model-guide.md"), renderModelGuide(policy));
});

test("the guide has task tables per tier, rationale, evidence date and metadata", () => {
  const guide = renderModelGuide(policy);
  for (const task of policy.rankings.keys()) assert.match(guide, new RegExp(`^## ${task}$`, "m"));
  for (const tier of ["Budget", "Balanced", "Premium"]) assert.match(guide, new RegExp(`^### ${tier}$`, "m"));
  assert.match(guide, /Evidence date: 2026-10-03/);
  for (const ranking of policy.rankings.values()) {
    for (const text of Object.values(ranking.rationale)) assert.ok(guide.includes(text), text);
  }
  assert.match(guide, /\| Model \| Provider \| Quality \| Speed \| Cost \| Strengths \| Avoid for \|/);
  assert.match(guide, /operational guidance/i);
});

test("the guide covers all three provider families and names the Claude Bridge", () => {
  const guide = renderModelGuide(policy);
  assert.match(guide, /opencode-go/);
  assert.match(guide, /openai\/gpt-5\.4/);
  assert.match(guide, /Anthropic via Claude Bridge/);
  assert.doesNotMatch(guide, /anthropic\/claude/);
});

test("a budget tier is a lower-cost choice than balanced", () => {
  for (const [task, ranking] of policy.rankings) {
    const lead = policy.models.get(ranking.budget[0])!;
    assert.equal(lead.cost, "low", `${task} budget leads with ${lead.label}`);
    assert.ok(!ranking.budget.some((ref) => ref.startsWith("claude-bridge/")), `${task} budget uses the subscription`);
  }
});

const listing = [
  "provider       model              context  max-out  thinking  images",
  "anthropic      claude-sonnet-5-5  1M       128K     yes       yes   ",
  "claude-bridge  claude-haiku-4-5   200K     64K      yes       yes   ",
  "openai         gpt-5.4-mini       400K     128K     yes       yes   ",
  "ollama         qwen3.6:35b        128K     16.4K    yes       yes   ",
  "",
].join("\n");

test("parseListModels reads the columnar listing", () => {
  assert.deepEqual(
    [...parseListModels(listing)].sort(),
    ["anthropic/claude-sonnet-5-5", "claude-bridge/claude-haiku-4-5", "ollama/qwen3.6:35b", "openai/gpt-5.4-mini"],
  );
});

test("missingCatalogModels reports every absent model, sorted, and never accepts anthropic/*", () => {
  const available = parseListModels(listing);
  const missing = missingCatalogModels(policy, available);
  assert.deepEqual(missing, [...missing].sort());
  assert.ok(missing.includes("claude-bridge/claude-sonnet-5-5"), "anthropic/claude-sonnet-5-5 must not stand in for the bridge");
  assert.ok(missing.includes("opencode-go/glm-5.3"));
  assert.ok(!missing.includes("openai/gpt-5.4-mini"));
  assert.ok(!missing.includes("claude-bridge/claude-haiku-4-5"));
  assert.deepEqual(missingCatalogModels(policy, new Set(policy.models.keys())), []);
});
