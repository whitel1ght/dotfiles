// Pure helpers for the tool layer (index.ts): parameter schemas, ordinals,
// result tails, and the small state operations the tools perform. Kept apart
// from the entry point so index.ts stays wiring-only.

import { readFileSync } from "node:fs";
import { join } from "node:path";

import type { TSchema } from "typebox";

import { listAgents, owned, readMeta, stateDir, writeMeta, type Meta } from "./state.ts";

export type SubagentParams = {
  role: string;
  model: string;
  task: string;
  cwd?: string;
  skills?: string[];
  with?: string[];
  label?: string;
  idle_minutes?: number;
  max_minutes?: number;
};

export type IdParams = { id: string };
export type ResultParams = { id: string; lines?: number };
export type AdoptParams = { id?: string; from?: string };

/**
 * Parameter schemas as plain JSON-schema objects — the same JSON that
 * typebox's Type.Object emits, which pi round-trips into tool declarations
 * and validates with its own typebox copy. Built by hand because the
 * `typebox` bare specifier only resolves inside pi's extension loader, not
 * under plain `node --test`.
 */
export const str = (description: string) => ({ type: "string", description });
export const num = (description: string) => ({ type: "number", description });
export const strArr = (description: string) => ({ type: "array", items: { type: "string" }, description });
export const obj = (properties: Record<string, unknown>, required: string[]): TSchema =>
  ({ type: "object", properties, required }) as TSchema;

export const agentFolder = (id: string) => join(stateDir(), id);

/** Agents in started_at order (tie-break id): the one ordinal-scheme order. */
export function byStartedAt<T extends { started_at: string; id: string }>(a: T, b: T): number {
  return a.started_at === b.started_at ? a.id.localeCompare(b.id) : a.started_at.localeCompare(b.started_at);
}

/** #N of an agent among its owner's agents, in started_at order, 1-based. */
export function ordinalOf(session: string, id: string): number {
  const rank = owned(listAgents(), session)
    .sort(byStartedAt)
    .findIndex((m) => m.id === id);
  if (rank === -1) throw new Error(`pi-sub: agent ${id} is not owned by this session`);
  return rank + 1;
}

/** The last `lines` lines of a text, ignoring one trailing newline. */
export function tailLines(text: string, lines: number): string {
  const all = text.split("\n");
  if (all.length > 0 && all[all.length - 1] === "") all.pop();
  return all.slice(Math.max(0, all.length - lines)).join("\n");
}

/**
 * The events.jsonl records of an agent, or [] when there are none yet. The
 * wrapper appends mid-record, so a partial (or otherwise bad) line is
 * expected: only that line is skipped, the rest are kept.
 */
export function readEvents(id: string): object[] {
  let raw: string;
  try {
    raw = readFileSync(join(agentFolder(id), "events.jsonl"), "utf8");
  } catch {
    return [];
  }
  const events: object[] = [];
  for (const line of raw.split("\n")) {
    if (line.trim() === "") continue;
    try {
      events.push(JSON.parse(line) as object);
    } catch {
      // Unparseable line: skip only this one.
    }
  }
  return events;
}

/** The text of a file in an agent dir, or undefined when it is not there yet. */
export function readFileOrNull(path: string): string | undefined {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return undefined;
  }
}

/** The agent's meta, or a tool error naming the folder we looked in. */
export function requireAgent(id: string): Meta {
  try {
    return readMeta(id);
  } catch {
    throw new Error(`pi-sub: unknown agent "${id}" (no folder ${agentFolder(id)})`);
  }
}

/** Move an agent to this session: rewrite the owner in its meta. */
export function reown(m: Meta, session: string): Meta {
  const next = { ...m, owner_session: session, owner_pid: process.pid };
  writeMeta(next);
  return next;
}
