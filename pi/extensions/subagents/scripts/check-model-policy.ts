// Fails when a model in pi/subagent-models.json is missing from `pi --list-models`.
//   npm run check-models
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { missingCatalogModels, parseModelPolicy } from "../src/model-policy.ts";

const POLICY_URL = new URL("../../../subagent-models.json", import.meta.url);

// The listing is columnar: a header row, then `provider  model  context ...`.
export function parseListModels(output: string): Set<string> {
  const refs = new Set<string>();
  for (const line of output.split("\n").slice(1)) {
    const [provider, model] = line.trim().split(/\s+/);
    if (provider && model) refs.add(`${provider}/${model}`);
  }
  return refs;
}

if (import.meta.main) {
  const listing = execFileSync("pi", ["--list-models"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  const policy = parseModelPolicy(JSON.parse(readFileSync(POLICY_URL, "utf8")));
  const missing = missingCatalogModels(policy, parseListModels(listing));
  if (missing.length) {
    console.error(`subagent-models.json lists ${missing.length} model(s) missing from pi --list-models:`);
    for (const ref of missing) console.error(`  ${ref}`);
    process.exit(1);
  }
  console.log(`all ${policy.models.size} models are available`);
}
