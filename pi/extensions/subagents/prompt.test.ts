import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { SELECT_MODELS_DESCRIPTION, SELECT_MODELS_GUIDELINES, SPAWN_GUIDELINES, spawnDescription } from "./src/prompt.ts";
import { parseModelPolicy } from "./src/model-policy.ts";
import { parseRoster } from "./src/roster.ts";

const read = (name: string) => JSON.parse(readFileSync(new URL(`../../${name}`, import.meta.url), "utf8"));
const committed = read("subagents.json");
const policy = parseModelPolicy(read("subagent-models.json"));

test("the selector guidance covers named flows only, once, with reuse and auto-assignment", () => {
  const guidance = SELECT_MODELS_GUIDELINES.join("\n");
  assert.match(guidance, /agent_select_models/);
  assert.match(guidance, /named multi-agent flow/);
  assert.match(guidance, /plan the initial roster/i);
  assert.match(guidance, /call agent_select_models once for it/);
  assert.match(guidance, /stable `flow`/);
  assert.match(guidance, /reuse the chosen model for each known role as agent_spawn's `model`/i);
  assert.match(guidance, /later roles yourself/i);
  assert.match(guidance, /fails because there is no interactive terminal, stop the named flow, start no agents and do not pretend the user chose/);
  assert.doesNotMatch(guidance, /pick models yourself or ask the user/);
  assert.match(SELECT_MODELS_DESCRIPTION, /fails with an error instead of choosing for the user/);
  assert.match(guidance, /never .*one-off/i);
  assert.match(guidance, /cancelled/);
});

function meta(ref: string) {
  return { label: ref, provider: ref.split("/")[0], quality: "q", speed: "s", cost: "c", bestFor: ["x"], strengths: ["y"], avoidFor: ["z"] };
}

const repoFile = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8");
const workflows = [
  ...["mr-review-multi-agent", "backend-panel", "frontend-panel", "python-panel", "handle-ticket", "fix-jira-bug"].map(
    (s) => `opencode/skills/${s}/SKILL.md`,
  ),
];

// The gate is one paragraph starting at "**Model gate"; every assertion about it reads that paragraph only.
const gateOf = (text: string) => {
  const start = text.indexOf("**Model gate");
  assert.notEqual(start, -1, "has a model gate paragraph");
  const end = text.indexOf("\n\n", start);
  return text.slice(start, end === -1 ? undefined : end).replace(/\s+/g, " ");
};
const at = (text: string, marker: string) => {
  const index = text.indexOf(marker);
  assert.notEqual(index, -1, `marker present: ${marker}`);
  return index;
};
// [file, marker the gate must follow, marker of the first relevant spawn it must precede]
const placement: Record<string, [string, string]> = {
  "opencode/skills/mr-review-multi-agent/SKILL.md": ["Announce the panel:", "### 3. Round 1"],
  "opencode/skills/backend-panel/SKILL.md": ["State the selection before spawning.", "### 3. Round 1"],
  "opencode/skills/frontend-panel/SKILL.md": ["State the selected panel and the reason before spawning.", "### 3. Round 1"],
  "opencode/skills/python-panel/SKILL.md": ["and the reason before spawning.", "### 3. Round 1"],
  "opencode/skills/handle-ticket/SKILL.md": ["**Add by change type:**", "Each agent brief must carry:"],
  "opencode/skills/fix-jira-bug/SKILL.md": ["Add `shared:prod-readiness`", "Each agent gets the full proposal"],
};
const inherited = [
  /Unless a parent flow already gated/,
  /do not call `agent_select_models` again/,
  /reuse the matching inherited choices as `model`/,
  /leave newly discovered roles automatic/,
];

for (const path of workflows) {
  const text = repoFile(path);
  const gate = gateOf(text);
  const isSkill = path.startsWith("opencode/skills/");

  test(`${path}: gate block states the selection contract`, () => {
    assert.equal(text.match(/Call\s+`agent_select_models`/g)?.length, 1, "one call instruction in the file");
    assert.match(gate, /Call\s+`agent_select_models` once/);
    assert.match(gate, /stable\s+flow\s+ID/);
    assert.match(gate, /`[a-z-]+:<[^`]+`/, "a concrete flow ID shape");
    assert.match(gate, /role key/);
    assert.match(gate, /recommendedModel/);
    assert.match(gate, /If it is cancelled or errors, stop/);
    assert.match(gate, /nothing/);
    assert.match(gate, /Pass each returned model as/);
    assert.match(gate, /reuse/);
    assert.match(gate, /automatic model from the usual policy, without another prompt/);
    assert.doesNotMatch(gate, /(?:[:,]) Use the/, "no template capitalisation artefact");
    const withoutInheritance = gate.replace(/(?:do|must) not call `agent_select_models` again/g, "");
    assert.doesNotMatch(withoutInheritance, /(?:prompt|select|gate)\w* again/, "never asks to prompt again");
  });

  test(`${path}: the gate sits before the first relevant spawn`, () => {
    const [after, before] = placement[path];
    const g = at(text, "**Model gate");
    assert.ok(g > at(text, after), `gate follows ${after}`);
    assert.ok(g < at(text, before), `gate precedes ${before}`);
  });

  if (isSkill) {
    test(`${path}: the skill gate is Pi-only`, () => {
      assert.ok(gate.startsWith("**Model gate (Pi, when `agent_select_models` is available; otherwise skip).**"));
    });
  }
}

test("nested panel and review skills defer to a parent that already gated", () => {
  for (const s of ["mr-review-multi-agent", "backend-panel", "frontend-panel", "python-panel"]) {
    const gate = gateOf(repoFile(`opencode/skills/${s}/SKILL.md`));
    for (const rule of inherited) assert.match(gate, rule, `${s}: ${rule}`);
    assert.match(gate, /already gated.*flow ID and role choices/s);
  }
});

test("handle-ticket gates known Phase 1 roles only and passes its context to nested skills", () => {
  const text = repoFile("opencode/skills/handle-ticket/SKILL.md");
  const gate = gateOf(text);
  assert.match(gate, /one role key per Phase 1 agent/);
  assert.doesNotMatch(gate, /planned implementation|review agents/);
  assert.match(gate, /stable flow ID `handle-ticket:<TICKET>`/);
  assert.match(gate, /nested panel or review skill[^.]*pass[^.]*flow ID and the role choices[^.]*must not call `agent_select_models` again/s);
  const phase8 = text.slice(at(text, "## Phase 8"), at(text, "## Phase 9"));
  assert.match(phase8, /handle-ticket:<TICKET>/);
  assert.match(phase8, /role choices/);
  assert.match(phase8, /Do NOT call `agent_select_models`/);
});

test("fix-jira-bug gates the reviewers once and Phase 10 reuses them", () => {
  const text = repoFile("opencode/skills/fix-jira-bug/SKILL.md");
  const gate = gateOf(text);
  assert.match(gate, /stable flow ID `fix-jira-bug:<TICKET>`/);
  const phase10 = text.slice(at(text, "## Phase 10"));
  assert.match(phase10, /model chosen at the Phase 8 gate \(do not call `agent_select_models` again\)/);
});

test("mr-review-multi-agent gates a batch once with a batch-level flow ID", () => {
  const gate = gateOf(repoFile("opencode/skills/mr-review-multi-agent/SKILL.md"));
  assert.match(gate, /single MR: `mr-review-multi-agent:<project>!<iid>`/);
  assert.match(gate, /batch: one flow ID for the whole invocation, `mr-review-multi-agent:<project>:<author>:<since>`/);
  assert.match(gate, /explicit list of MRs: `mr-review-multi-agent:<project>!<iid>\+<project>!<iid>/);
  assert.match(gate, /Gate once, before the first MR's Round 1 spawn, and never per MR/);
  assert.match(gate, /If the gate is cancelled or errors in a batch, stop the whole batch and post nothing/);
  assert.match(gate, /later MRs in the batch reuse that same context, pass the same stored model for the same role and leave roles that were not selected automatic/);
});

test("no workflow tells the parent not to pass a model", () => {
  for (const path of [...workflows, "pi/prompts/orchestrate.md", "pi/prompts/review-local.md", "pi/prompts/watch-mrs.md"]) {
    const text = repoFile(path);
    assert.doesNotMatch(text, /Do not pass `model`/i, path);
    assert.doesNotMatch(text, /No model — the extension picks/, path);
  }
});

test("the global guidance covers the external Superpowers flows and excludes single-agent ones", () => {
  const guidance = SELECT_MODELS_GUIDELINES.join("\n");
  assert.match(guidance, /superpowers:subagent-driven-development/);
  assert.match(guidance, /superpowers:dispatching-parallel-agents/);
  assert.match(guidance, /expected implementer\/reviewer roster/);
  assert.match(guidance, /before the first worker/);
  assert.match(guidance, /superpowers:writing-plans/);
  assert.match(guidance, /superpowers:executing-plans/);
  assert.match(guidance, /superpowers:requesting-code-review/);
});

test("failure guidance ties the non-TUI error to the named flow", () => {
  assert.match(SELECT_MODELS_DESCRIPTION, /named flow/);
});

test("the spawn description makes the parent choose from the live pool, with no ranking or fallback", () => {
  const description = spawnDescription(parseRoster(committed, policy));
  assert.match(description, /`model` is required/);
  assert.match(description, /agent_models/);
  assert.match(description, /your judgment/i);
  assert.match(description, /no fallback|never switches|does not switch/i);
  for (const stale of [/best first/i, /ranked by benchmarks/i, /replaced by the next/i, /ending with Claude/i, /stays as fallback/i, /Model tiers per type/, /modelProfile/]) {
    assert.doesNotMatch(description, stale);
  }
  const guidance = SPAWN_GUIDELINES.join("\n");
  assert.match(guidance, /agent_models/);
  assert.match(guidance, /judgment/);
  assert.match(guidance, /overlap/i);
  assert.match(guidance, /no automatic fallback|does not fall back/i);
  assert.match(guidance, /older workflow.*choose explicitly from agent_models/);
  assert.match(guidance, /never omit model/);
  assert.match(description, /completion notification and agent_output report the failure/);
  for (const stale of [/budget for bounded/i, /modelProfile/, /only to a model the user chose/i, /type's ranking/i]) {
    assert.doesNotMatch(guidance, stale);
  }
});

test("agent_spawn takes a required model and no modelProfile; agent_select_models is not offered to the model", () => {
  const index = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
  assert.match(index, /resolveSpawnModel\(/);
  assert.match(index, /sessionModelPool\(/);
  assert.match(index, /context\.scopedModels/);
  assert.match(index, /name: "agent_models"/);
  assert.match(index, /model: Type\.String\(/);
  assert.doesNotMatch(index, /model: Type\.Optional/);
  assert.doesNotMatch(index, /modelProfile/);
  assert.doesNotMatch(index, /planSpawnChain|chainFor\(/);
  assert.match(index, /name: "agent_select_models"[\s\S]*?exposure: "hidden"/);
});

test("the pi prompts leave model choice to the parent and the README no longer promises rankings or fallback", () => {
  for (const path of ["pi/prompts/orchestrate.md", "pi/prompts/review-local.md", "pi/prompts/watch-mrs.md"]) {
    const doc = repoFile(path);
    assert.doesNotMatch(doc, /agent_select_models/, path);
    assert.doesNotMatch(doc, /stays behind it as fallback|usual policy|premium-tier model/, path);
    assert.match(doc, /agent_models/, path);
  }
  const readme = repoFile("pi/extensions/subagents/README.md");
  assert.match(readme, /`agent_models`/);
  assert.doesNotMatch(readme, /models, best first|Fall back\*\* when|Selected model, then balanced fallback/);
  assert.match(readme, /scoped models/i);
});
