// ~/.secrets/secrets.env, the one place secrets live (bin/secret reads the
// same file). Nothing exports it into the shell any more, so the MCP config's
// ${VAR}s are looked up here as well as in the environment.
import { existsSync, readFileSync } from "node:fs";
import type { Env } from "./expand.ts";

export function parseSecrets(text: string): Env {
  const out: Env = {};
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) continue;
    const at = line.indexOf("=");
    const key = line.slice(0, at).trim().replace(/^export\s+/, "").trim();
    let value = line.slice(at + 1).trim();
    if (value.length >= 2 && value[0] === value.at(-1) && (value[0] === '"' || value[0] === "'")) {
      value = value.slice(1, -1);
    }
    if (value) out[key] = value;
  }
  return out;
}

export function readSecrets(path: string): Env {
  return existsSync(path) ? parseSecrets(readFileSync(path, "utf8")) : {};
}
