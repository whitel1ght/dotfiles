import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";

// Reads every @path in a message into the <file> blocks `pi @file` uses on the
// command line. In the editor @ only inserts a path, which helps a model that
// can read files and nothing else.

export const MAX_FILE_BYTES = 200 * 1024;

export interface Attached {
  readonly mention: string;
  readonly path: string;
  readonly bytes: number;
}

export interface Skipped {
  readonly mention: string;
  readonly reason: string;
}

export interface Expansion {
  // What the model is sent alongside the message: the file blocks, then a note
  // on any mention that could not be attached. Empty when there is nothing.
  readonly content: string;
  readonly attached: readonly Attached[];
  readonly skipped: readonly Skipped[];
}

// `@path` at the start or after whitespace, up to the next whitespace. An email
// address has no whitespace before its @, so it is not a mention.
const MENTION = /(?<=^|\s)@(\S+)/g;
const TRAILING_PUNCTUATION = /[.,;:!?)\]}'"`]+$/;

export function mentions(text: string): string[] {
  return [...text.matchAll(MENTION)].map((m) => m[1]);
}

export function resolvePath(raw: string, cwd: string): string {
  const path = raw === "~" ? homedir() : raw.startsWith("~/") ? `${homedir()}${raw.slice(1)}` : raw;
  return isAbsolute(path) ? path : resolve(cwd, path);
}

export function expandMentions(text: string, cwd: string, maxBytes = MAX_FILE_BYTES): Expansion {
  const attached: Attached[] = [];
  const skipped: Skipped[] = [];
  const blocks: string[] = [];
  const seen = new Set<string>();

  for (const raw of mentions(text)) {
    // "see @README.md." means README.md; try the mention as written first.
    const candidates = [raw, raw.replace(TRAILING_PUNCTUATION, "")].filter((c, i, all) => c && all.indexOf(c) === i);
    const found = candidates.map((c) => ({ mention: c, path: resolvePath(c, cwd) })).find((c) => exists(c.path));
    if (!found) continue; // Not a file: an @handle, a decorator, prose.
    if (seen.has(found.path)) continue;
    seen.add(found.path);

    const stat = statSync(found.path);
    if (stat.isDirectory()) {
      skipped.push({ mention: found.mention, reason: "a directory" });
      continue;
    }
    if (stat.size > maxBytes) {
      skipped.push({ mention: found.mention, reason: `${kb(stat.size)}, over the ${kb(maxBytes)} limit` });
      continue;
    }
    const content = readFileSync(found.path);
    if (content.includes(0)) {
      skipped.push({ mention: found.mention, reason: "not a text file" });
      continue;
    }
    const body = content.toString("utf8").replace(/^\uFEFF/, "");
    blocks.push(`<file name="${found.path}">\n${body}\n</file>\n`);
    attached.push({ mention: found.mention, path: found.path, bytes: stat.size });
  }

  if (skipped.length) {
    const lines = skipped.map((s) => `- @${s.mention}: ${s.reason}`).join("\n");
    blocks.push(`The user mentioned these, which could not be attached:\n${lines}\n`);
  }
  return { content: blocks.join(""), attached, skipped };
}

export function kb(bytes: number): string {
  return bytes < 1024 ? `${bytes}B` : `${Math.round(bytes / 1024)}KB`;
}

function exists(path: string): boolean {
  try {
    statSync(path);
    return true;
  } catch {
    return false;
  }
}
