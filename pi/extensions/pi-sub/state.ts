import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export type Meta = {
  id: string;
  role: string;
  model: string;
  label: string;
  task: string;
  cwd: string;
  skills: string[];
  extras: string[];
  pid: number;
  pgid: number;
  started_at: string;
  owner_session: string;
  owner_pid: number;
  handoff_from?: string;
  idle_minutes: number;
  max_minutes: number;
  argv: string[];
};

export type Exit = {
  code: number | null;
  signal: string | null;
  ended_at: string;
  how: "done" | "failed" | "stopped";
  by?: "user" | "main" | "timeout";
};

export function stateDir(): string {
  return process.env.PI_SUB_STATE_DIR ?? join(homedir(), ".local/state/pi-sub");
}

/** `<yyyymmdd-hhmmss>-<4 hex>`: short, sortable, unique. */
export function newId(now: Date): string {
  const p = (n: number) => String(n).padStart(2, "0");
  const hex = Math.floor(Math.random() * 0x10000).toString(16).padStart(4, "0");
  const date = `${now.getFullYear()}${p(now.getMonth() + 1)}${p(now.getDate())}`;
  const time = `${p(now.getHours())}${p(now.getMinutes())}${p(now.getSeconds())}`;
  return `${date}-${time}-${hex}`;
}

function agentDir(id: string): string {
  return join(stateDir(), id);
}

/** Write via a tmp file + rename, so readers never see a partial file. */
function atomicWrite(path: string, data: string): void {
  const tmp = `${path}.tmp`;
  try {
    writeFileSync(tmp, data);
    renameSync(tmp, path);
  } catch (err) {
    rmSync(tmp, { force: true, recursive: true });
    throw err;
  }
}

export function writeMeta(m: Meta): void {
  mkdirSync(agentDir(m.id), { recursive: true });
  atomicWrite(join(agentDir(m.id), "meta.json"), `${JSON.stringify(m, null, 2)}\n`);
}

export function readMeta(id: string): Meta {
  return JSON.parse(readFileSync(join(agentDir(id), "meta.json"), "utf8")) as Meta;
}

export function readExit(id: string): Exit | undefined {
  const path = join(agentDir(id), "exit.json");
  return existsSync(path) ? (JSON.parse(readFileSync(path, "utf8")) as Exit) : undefined;
}

export function isDelivered(id: string): boolean {
  return existsSync(join(agentDir(id), "delivered"));
}

export function markDelivered(id: string): void {
  atomicWrite(join(agentDir(id), "delivered"), "");
}

export function listAgents(): Meta[] {
  const dir = stateDir();
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isDirectory() && existsSync(join(dir, e.name, "meta.json")))
    .map((e) => readMeta(e.name))
    .sort((a, b) => a.id.localeCompare(b.id));
}

export function owned(all: Meta[], session: string): Meta[] {
  return all.filter((m) => m.owner_session === session);
}

/**
 * Agents this session could adopt: not ours, whose owner process is dead, and
 * that are still running (no exit.json) or whose exit was never delivered.
 * A handed-off agent whose owner is still alive stays that owner's business.
 */
export function orphans(all: Meta[], session: string, alive: (pid: number) => boolean): Meta[] {
  return all.filter((m) => {
    if (m.owner_session === session) return false;
    if (m.handoff_from !== undefined && alive(m.owner_pid)) return false;
    return !alive(m.owner_pid) && (readExit(m.id) === undefined || !isDelivered(m.id));
  });
}
