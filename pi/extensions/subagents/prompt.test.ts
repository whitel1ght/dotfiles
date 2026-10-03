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

const repoFile = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8");
const workflows = [
  "pi/prompts/orchestrate.md",
  "pi/prompts/review-local.md",
  "pi/prompts/watch-mrs.md",
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
  "pi/prompts/orchestrate.md": ["2. **Plan.**", "3. **Execute.**"],
  "pi/prompts/review-local.md": ["## 3. Panel", "## 4. Round 1"],
  "pi/prompts/watch-mrs.md": ["1. **Worktree.**", "2. **Fixer.**"],
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
    assert.match(gate, /stable flow ID/);
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

test("watch-mrs gates after dirty filtering, once per session, with collision-free keys", () => {
  const text = repoFile("pi/prompts/watch-mrs.md");
  const gate = gateOf(text);
  assert.match(text.slice(at(text, "1. **Worktree.**"), at(text, "**Model gate")), /`DIRTY`: .*leave the MR alone/s);
  assert.match(gate, /every non-DIRTY MR/);
  assert.match(gate, /session's first round that spawns a fixer/);
  assert.match(gate, /stable flow ID `watch-mrs:<start>`/);
  assert.match(gate, /UTC time of the session's first `check`.*chosen once.*`watch-mrs-models\.md`.*re-read it after compaction/s);
  assert.match(gate, /role key `fixer:<project>!<iid>` with the full project path/);
  assert.match(gate, /one MR per key/);
  assert.match(gate, /stop the watch loop: spawn nothing, ack nothing, start no wait, and tell me/);
  assert.match(gate, /Later rounds reuse the recorded choice for a known role, and roles that were not selected get an automatic model from the usual policy, without another prompt/);
});

test("orchestrate skips a single-agent roster and lists every role known from the plan", () => {
  const gate = gateOf(repoFile("pi/prompts/orchestrate.md"));
  assert.match(gate, /unless the roster is a single agent, which skips the gate/);
  assert.match(gate, /one role key per piece, plus `reviewer` when the plan includes the step 5 review/);
  assert.match(gate, /Selected models override the type's default list and any model you named in the plan/);
  assert.match(gate, /Later roles that were not known at this point get an automatic model/);
});

test("review-local replaces the skill's own gate and passes the selected model", () => {
  const text = repoFile("pi/prompts/review-local.md");
  const gate = gateOf(text);
  assert.match(gate, /one role key per reviewer \(its `profile`\)/);
  assert.match(text, /ignore its `Model gate` paragraph/);
  assert.match(text.slice(at(text, "## 4. Round 1")), /`model` from the gate for each reviewer/);
});

test("no workflow tells the parent not to pass a model", () => {
  for (const path of workflows) {
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
