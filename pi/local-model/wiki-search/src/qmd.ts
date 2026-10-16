import { execFile } from "node:child_process";

export const SCOPES = ["all", "notes", "diary", "projects", "articles"] as const;
export type Scope = (typeof SCOPES)[number];

// pi-memory is left out on purpose: ~/wiki/AGENTS.md says unscoped searches
// must not hit it.
const COLLECTIONS: Record<Exclude<Scope, "all">, string[]> = {
  notes: ["notes"],
  diary: ["diary"],
  projects: ["ecfx", "epicmax", "personal"],
  articles: ["saved"],
};
const ALL = ["notes", "diary", "ecfx", "epicmax", "personal", "reviews", "saved"];
const KIND: Record<string, string> = { saved: "saved article", notes: "note", diary: "diary entry", reviews: "review" };

const MAX_HITS = 5;
const MAX_READ_LINES = 200;

export interface Options {
  bin?: string;
  signal?: AbortSignal;
}

export function collectionsFor(scope: Scope): string[] {
  return scope === "all" ? ALL : COLLECTIONS[scope];
}

function run(args: string[], { bin = "qmd", signal }: Options): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(bin, args, { signal, timeout: 120_000, maxBuffer: 8 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) reject(new Error((stderr.trim() || error.message).split("\n").slice(-3).join(" ")));
      else resolve(stdout);
    });
  });
}

interface Hit {
  file?: string;
  title?: string;
  score?: number;
  snippet?: string;
}

function cleanSnippet(snippet = ""): string {
  return snippet
    .split("\n")
    .filter((line) => line.trim() && !line.startsWith("@@"))
    .join(" ")
    .replace(/\s+/g, " ")
    .slice(0, 300);
}

export async function searchWiki(query: string, scope: Scope, options: Options = {}): Promise<string> {
  const args = ["query", query, "--json", "-n", String(MAX_HITS), ...collectionsFor(scope).flatMap((c) => ["-c", c])];
  let out: string;
  try {
    out = await run(args, options);
  } catch (error) {
    return `wiki search failed: ${(error as Error).message}`;
  }
  const start = out.indexOf("[");
  const hits: Hit[] = start === -1 ? [] : JSON.parse(out.slice(start));
  if (!hits.length) return `No matches in ${scope === "all" ? "the wiki or saved articles" : scope}.`;
  const lines = hits.map((hit, i) => {
    const collection = hit.file?.split("/")[2] ?? "";
    const kind = KIND[collection] ?? `${collection} note`;
    return `${i + 1}. ${hit.title || hit.file} — ${hit.file} (${kind}, score ${(hit.score ?? 0).toFixed(2)})\n   ${cleanSnippet(hit.snippet)}`;
  });
  return `${lines.join("\n")}\n\nRead a result in full with wiki_read and its qmd:// path before quoting it.`;
}

export async function readNote(path: string, { from = 1, lines = MAX_READ_LINES, ...options }: Options & { from?: number; lines?: number } = {}): Promise<string> {
  if (!path.startsWith("qmd://")) return "wiki_read needs a qmd:// path from wiki_search.";
  const count = Math.min(Math.max(1, lines), MAX_READ_LINES);
  try {
    return await run(["get", `${path}:${Math.max(1, from)}`, "-l", String(count)], options);
  } catch (error) {
    return `wiki read failed: ${(error as Error).message}`;
  }
}
