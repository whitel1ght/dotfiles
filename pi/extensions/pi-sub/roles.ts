import { readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export type Role = {
  name: string;
  tools: string[];
  body: string;
  writeCapable: boolean;
};

export function agentsDir(): string {
  return process.env.PI_SUB_AGENTS_DIR || join(homedir(), ".pi", "agent", "agents");
}

const DEFAULT_TOOLS = ["read", "grep", "find", "ls"];

/** tools line split on commas and trimmed; read/grep/find/ls when absent or empty. */
function parseTools(frontmatter: string[]): string[] {
  const line = frontmatter.find((l) => l.startsWith("tools:"));
  if (line === undefined) return [...DEFAULT_TOOLS];
  const tools = line
    .slice("tools:".length)
    .split(",")
    .map((t) => t.trim())
    .filter((t) => t.length > 0);
  return tools.length > 0 ? tools : [...DEFAULT_TOOLS];
}

/** Split a role file into frontmatter lines and the body after the closing `---`. */
function splitFrontmatter(text: string): { frontmatter: string[]; body: string } {
  const lines = text.split("\n");
  // Frontmatter only when the file starts with a fence: a --- anywhere else
  // is body text that must not be mistaken for the closing fence.
  if (lines[0] === undefined || lines[0].trim() !== "---") {
    return { frontmatter: [], body: text.trim() };
  }
  const close = lines.indexOf("---", 1);
  if (close === -1) return { frontmatter: [], body: text.trim() };
  return { frontmatter: lines.slice(1, close), body: lines.slice(close + 1).join("\n").trim() };
}

export function loadRole(name: string): Role {
  if (!/^[a-z0-9][a-z0-9-]*$/i.test(name)) {
    throw new Error(`unknown role "${name}"; available: ${listRoles().join(", ")}`);
  }
  const path = join(agentsDir(), `${name}.md`);
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    throw new Error(`unknown role "${name}"; available: ${listRoles().join(", ")}`);
  }
  const { frontmatter, body } = splitFrontmatter(text);
  const tools = parseTools(frontmatter);
  return {
    name,
    tools,
    body,
    writeCapable: tools.includes("edit") || tools.includes("write"),
  };
}

export function listRoles(): string[] {
  const dir = agentsDir();
  try {
    return readdirSync(dir)
      .filter((f) => f.endsWith(".md"))
      .map((f) => f.slice(0, -3))
      .sort();
  } catch {
    return [];
  }
}
