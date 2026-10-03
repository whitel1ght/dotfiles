// Renders pi/subagent-model-guide.md from pi/subagent-models.json.
//   npm run generate-guide
import { readFileSync, writeFileSync } from "node:fs";
import { CLAUDE_PREFIX, MODEL_TIERS, parseModelPolicy, type ModelMetadata, type ModelPolicy } from "../src/model-policy.ts";

const POLICY_URL = new URL("../../../subagent-models.json", import.meta.url);
const GUIDE_URL = new URL("../../../subagent-model-guide.md", import.meta.url);

const TIER_TITLES = { budget: "Budget", balanced: "Balanced", premium: "Premium" } as const;

export function renderModelGuide(policy: ModelPolicy): string {
  const out: string[] = [
    "# Subagent model guide",
    "",
    "<!-- Generated from pi/subagent-models.json by `npm run generate-guide` in pi/extensions/subagents. Do not edit. -->",
    "",
    `Evidence date: ${policy.evidenceDate}`,
    "",
    "Quality, speed and cost labels are operational guidance for picking a subagent model, not benchmark results or",
    "prices. Sources and scores are in [subagents-research.md](subagents-research.md). Models are listed best first;",
    `\`${CLAUDE_PREFIX}*\` is Anthropic via Claude Bridge (the subscription), never the \`anthropic/*\` API-billed provider.`,
    "",
  ];
  for (const [task, ranking] of policy.rankings) {
    out.push(`## ${task}`, "");
    for (const tier of MODEL_TIERS) {
      out.push(`### ${TIER_TITLES[tier]}`, "", ranking.rationale[tier], "");
      out.push("| # | Model | Provider | Quality | Speed | Cost |", "| --- | --- | --- | --- | --- | --- |");
      ranking[tier].forEach((ref, i) => {
        const m = policy.models.get(ref)!;
        out.push(`| ${i + 1} | \`${ref}\` (${m.label}) | ${providerName(m)} | ${m.quality} | ${m.speed} | ${m.cost} |`);
      });
      out.push("");
    }
  }
  out.push("## Model reference", "");
  out.push("| Model | Provider | Quality | Speed | Cost | Strengths | Avoid for |", "| --- | --- | --- | --- | --- | --- | --- |");
  const models = [...policy.models.values()].sort((a, b) => a.ref.localeCompare(b.ref));
  for (const m of models) {
    out.push(`| \`${m.ref}\` (${m.label}) | ${providerName(m)} | ${m.quality} | ${m.speed} | ${m.cost} | ${m.strengths.join("; ")} | ${m.avoidFor.join("; ")} |`);
  }
  out.push("", "Best for:", "");
  for (const m of models) out.push(`- \`${m.ref}\`: ${m.bestFor.join(", ")}`);
  out.push("", "## Changing the policy", "");
  out.push("Edit `pi/subagent-models.json` (move a line to change priority), then run `npm run generate-guide` and `npm run check-models`.", "");
  return out.join("\n");
}

function providerName(m: ModelMetadata): string {
  return m.ref.startsWith(CLAUDE_PREFIX) ? "Anthropic via Claude Bridge" : m.provider;
}

if (import.meta.main) {
  writeFileSync(GUIDE_URL, renderModelGuide(parseModelPolicy(JSON.parse(readFileSync(POLICY_URL, "utf8")))));
}
