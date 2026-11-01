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

type Exec = (file: string, args: string[]) => string;

const run: Exec = (file, args) => execFileSync(file, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });

export function listPiModels(exec: Exec = run): string {
  try {
    return exec("pi", ["--list-models"]);
  } catch (error) {
    const { code, message } = error as NodeJS.ErrnoException;
    if (code === "ENOENT") throw new Error("`pi` was not found on PATH; install it to check model availability");
    throw new Error(`\`pi --list-models\` failed: ${message.split("\n")[0]}`);
  }
}

if (import.meta.main) {
  let listing: string;
  try {
    listing = listPiModels();
  } catch (error) {
    console.error((error as Error).message);
    process.exit(1);
  }
  const policy = parseModelPolicy(JSON.parse(readFileSync(POLICY_URL, "utf8")));
  const missing = missingCatalogModels(policy, parseListModels(listing));
  if (missing.length) {
    console.error(`subagent-models.json lists ${missing.length} model(s) missing from pi --list-models:`);
    for (const ref of missing) console.error(`  ${ref}`);
    process.exit(1);
  }
  console.log(`all ${policy.models.size} models are available`);
}
