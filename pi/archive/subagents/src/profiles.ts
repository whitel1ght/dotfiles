import { existsSync, readdirSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";

// A named persona from agents/*.md: its body is added to the child's system
// prompt, and `permission: edit: deny` keeps it from changing files.
export interface Profile {
  readonly name: string;
  readonly description: string;
  readonly prompt: string;
  readonly readOnly: boolean;
}

export type FrontmatterParser = (content: string) => { frontmatter: Record<string, unknown>; body: string };

const EDIT_TOOLS = new Set(["edit", "write"]);
const SUMMARY_CHARS = 160;

export function loadProfiles(dir: string, parse: FrontmatterParser): Map<string, Profile> {
  const profiles = new Map<string, Profile>();
  if (!existsSync(dir)) return profiles;
  for (const file of readdirSync(dir).filter((f) => f.endsWith(".md")).sort()) {
    const name = basename(file, ".md");
    try {
      const { frontmatter, body } = parse(readFileSync(join(dir, file), "utf8"));
      const permission = frontmatter.permission as Record<string, unknown> | undefined;
      profiles.set(name, {
        name,
        description: typeof frontmatter.description === "string" ? frontmatter.description : "",
        prompt: body.trim(),
        readOnly: permission?.edit === "deny",
      });
    } catch {
      // One malformed profile must not hide the rest.
    }
  }
  return profiles;
}

export function profileTools(tools: readonly string[], profile: Profile | undefined): string[] {
  return profile?.readOnly ? tools.filter((t) => !EDIT_TOOLS.has(t)) : [...tools];
}

// First sentence of the description, without the long "Examples:" tail most of them carry.
export function summarise(profile: Profile): string {
  const flat = profile.description.replace(/\\n/g, " ").replace(/\s+/g, " ").trim();
  const cut = flat.split(/(?<=\.)\s|\s+Examples?:/)[0] ?? flat;
  return cut.length > SUMMARY_CHARS ? `${cut.slice(0, SUMMARY_CHARS)}…` : cut;
}
