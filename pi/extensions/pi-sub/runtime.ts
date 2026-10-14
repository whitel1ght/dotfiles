// Watching owned subagents and waking the main session: delivery of finished
// runs, idle flags, the hard timeout, and stopping a run by signalling its
// process group. Pure logic plus process signalling — `send` and the clocks
// are parameters, so Task 6 can wire this to the pi extension API.

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, statSync, watch } from "node:fs";
import { join } from "node:path";

import {
  atomicWrite,
  isDelivered,
  listAgents,
  markDelivered,
  owned,
  readExit,
  readMeta,
  stateDir,
  type Exit,
  type Meta,
} from "./state.ts";

const STDERR_CHARS = 200;

export type Send = (text: string) => void;

/** `ps -E -p <pid> -o command=`: the command line plus its environment. */
export type PsRunner = (pid: number) => string;

export type StopOpts = {
  /** How long to wait between SIGTERM and SIGKILL (default 5 s). */
  graceMs?: number;
  ps?: PsRunner;
};

export type WatcherOpts = {
  /** Poll interval for the polling fallback of fs.watch (default 1 s). */
  pollMs?: number;
  graceMs?: number;
  ps?: PsRunner;
  now?: () => number;
};

const defaultPs: PsRunner = (pid) => {
  const r = spawnSync("ps", ["-E", "-p", String(pid), "-o", "command="], { encoding: "utf8" });
  return r.status === 0 ? (r.stdout ?? "") : "";
};

function agentDir(id: string): string {
  return join(stateDir(), id);
}

/** `4m12s` / `2h03m04s` — minutes unpadded, seconds always two digits. */
export function formatDur(ms: number): string {
  const total = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = String(m).padStart(2, "0");
  const ss = String(s).padStart(2, "0");
  return h > 0 ? `${h}h${mm}m${ss}s` : `${m}m${ss}s`;
}

function elapsed(m: Meta, endedAt: string): number {
  return Date.parse(endedAt) - Date.parse(m.started_at);
}

function head(m: Meta, ordinal: number): string {
  return `pi-sub #${ordinal} ${m.role} (${m.model}) "${m.label}"`;
}

/** Last non-empty stderr.log line, capped; undefined when there is none. */
function lastStderrLine(id: string): string | undefined {
  try {
    const lines = readFileSync(join(agentDir(id), "stderr.log"), "utf8").split("\n");
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i].trim();
      if (line.length > 0) return line.slice(0, STDERR_CHARS);
    }
  } catch {
    // No stderr.log yet — nothing to report.
  }
  return undefined;
}

/** The wake message for a finished run: one line plus the result path. */
export function wakeText(m: Meta, x: Exit, ordinal: number): string {
  const dur = formatDur(elapsed(m, x.ended_at));
  const result = `Result: ${join(agentDir(m.id), "result.md")}`;
  if (x.how === "done") {
    return `${head(m, ordinal)} finished in ${dur}. ${result}`;
  }
  if (x.how === "stopped") {
    return `${head(m, ordinal)} stopped by ${x.by ?? "unknown"} after ${dur}.`;
  }
  const exit = x.code !== null ? x.code : x.signal ?? "unknown";
  // A wrapper that vanished (SIGKILL'd) has no exit code and maybe stale
  // stderr: its own error text is the real reason.
  const detail = x.error ?? lastStderrLine(m.id) ?? "no stderr output";
  return `${head(m, ordinal)} failed (exit ${exit}) after ${dur}: ${detail}. ${result}`;
}

/** A user flag forwarded to the main session. */
export function flagText(m: Meta, ordinal: number, note: string): string {
  return `${head(m, ordinal)} flagged by user: ${note}`;
}

/** An idle agent has produced nothing for `minutes`. */
export function idleText(m: Meta, ordinal: number, minutes: number): string {
  return `${head(m, ordinal)} has produced no events for ${minutes} min (still running). Stop it with subagent_stop or let it continue.`;
}

/**
 * Idle: quiet for `idle_minutes` since `lastEventAt` (the events.jsonl mtime),
 * and not already flagged for this quiet spell (`flaggedSince` is the time of
 * the last flag; a new event since then re-arms it). A limit of 0 disables it.
 * Timeout: `max_minutes` since `meta.started_at`, so it survives restarts.
 */
export function checkLimits(
  m: Meta,
  lastEventAt: number,
  now: number,
  flaggedSince?: number,
): { idle: boolean; timeout: boolean } {
  const quietMs = now - lastEventAt;
  const idle =
    m.idle_minutes > 0 &&
    quietMs >= m.idle_minutes * 60_000 &&
    (flaggedSince === undefined || lastEventAt > flaggedSince);
  const timeout = m.max_minutes > 0 && now - Date.parse(m.started_at) >= m.max_minutes * 60_000;
  return { idle, timeout };
}

/**
 * True when `pid` is the wrapper of agent `id`: its ps environment must
 * contain `PI_SUB_ID=<id>`. The wrapper is spawned with that variable, so a
 * reused pid never matches and a dead pid prints nothing.
 */
export function ownsPid(pid: number, id: string, ps: PsRunner = defaultPs): boolean {
  const out = ps(pid);
  return new RegExp(`\\bPI_SUB_ID=${id}\\b`).test(out);
}

/**
 * Write a stop request and signal the wrapper's process group: SIGTERM, then
 * SIGKILL after `graceMs` if it is still alive. Resolves once the group is
 * dead. Refuses (throws) when the pid is not our agent, before writing or
 * signalling anything.
 */
export async function stop(id: string, by: "user" | "main" | "timeout", opts: StopOpts = {}): Promise<void> {
  const ps = opts.ps ?? defaultPs;
  const graceMs = opts.graceMs ?? 5000;
  const m = readMeta(id);
  if (!ownsPid(m.pid, m.id, ps)) {
    throw new Error(`pi-sub: pid ${m.pid} is not agent ${id}; not signalling`);
  }
  atomicWrite(
    join(agentDir(id), "stop-request.json"),
    `${JSON.stringify({ by, at: new Date().toISOString() }, null, 2)}\n`,
  );
  killGroup(m.pgid, "SIGTERM");
  const deadline = Date.now() + graceMs;
  while (Date.now() < deadline && isPidAlive(m.pid)) {
    await sleep(50);
  }
  if (isPidAlive(m.pid)) {
    killGroup(m.pgid, "SIGKILL");
    // Give the SIGKILL time to land before reporting the group dead.
    for (let i = 0; i < 20 && isPidAlive(m.pid); i++) await sleep(50);
  }
}

/**
 * Deliver every owned, exited, undelivered agent, oldest first: `send` the
 * wake message, then mark delivered — immediately, so a crash mid-loop never
 * re-delivers an already-sent one. Returns the messages that were sent.
 */
export function deliverPending(session: string, send: Send): string[] {
  const mine = owned(listAgents(), session);
  const sent: string[] = [];
  mine.forEach((m, i) => {
    const x = readExit(m.id);
    if (x === undefined || isDelivered(m.id)) return;
    const text = wakeText(m, x, i + 1);
    send(text);
    markDelivered(m.id);
    sent.push(text);
  });
  return sent;
}

/**
 * Ruling 6: a SIGKILL'd wrapper cannot write exit.json, so the Watcher writes
 * it for an owned agent whose wrapper pid is not ours any more, then delivers
 * normally.
 */
export function recordWrapperVanished(id: string, now: Date = new Date()): Exit {
  const exit: Exit = {
    code: null,
    signal: null,
    ended_at: now.toISOString(),
    how: "failed",
    error: "wrapper vanished",
  };
  atomicWrite(join(agentDir(id), "exit.json"), `${JSON.stringify(exit, null, 2)}\n`);
  return exit;
}

/** mtime of events.jsonl, or the agent's start when no event ever arrived. */
function lastEventAt(m: Meta): number {
  try {
    return statSync(join(agentDir(m.id), "events.jsonl")).mtimeMs;
  } catch {
    return Date.parse(m.started_at);
  }
}

/**
 * Follows the owned running agents: fs.watch on the state dir plus a poll,
 * delivers any exit as it appears (also ones recorded while this session was
 * down), flags an idle agent once per quiet spell, and stops it at the
 * timeout cap. `onChange` fires whenever anything about the owned agents
 * changed, so the UI layer can redraw.
 */
export class Watcher {
  private readonly session: string;
  private readonly onChange: () => void;
  private readonly send: Send;
  private readonly pollMs: number;
  private readonly graceMs: number;
  private readonly ps: PsRunner;
  private readonly now: () => number;
  private started = false;
  private sweeping = false;
  private interval?: ReturnType<typeof setInterval>;
  private fw?: ReturnType<typeof watch>;
  private readonly flagged = new Map<string, number>();
  private readonly seen = new Map<string, string>();

  constructor(session: string, onChange: () => void, send: Send, opts: WatcherOpts = {}) {
    this.session = session;
    this.onChange = onChange;
    this.send = send;
    this.pollMs = opts.pollMs ?? 1000;
    this.graceMs = opts.graceMs ?? 5000;
    this.ps = opts.ps ?? defaultPs;
    this.now = opts.now ?? Date.now;
  }

  start(): void {
    if (this.started) return;
    this.started = true;
    mkdirSync(stateDir(), { recursive: true });
    try {
      this.fw = watch(stateDir(), () => void this.sweep());
      this.fw.on("error", () => {}); // the poll below is the fallback
    } catch {
      // No fs.watch (or the dir vanished): the poll covers everything.
    }
    this.interval = setInterval(() => void this.sweep(), this.pollMs);
    void this.sweep();
  }

  /** Clears every timer and watcher; safe to call repeatedly. */
  stop(): void {
    if (!this.started) return;
    this.started = false;
    if (this.interval !== undefined) clearInterval(this.interval);
    this.interval = undefined;
    if (this.fw !== undefined) {
      this.fw.close();
      this.fw = undefined;
    }
  }

  private async sweep(): Promise<void> {
    if (this.sweeping) return;
    this.sweeping = true;
    try {
      let changed = false;
      const now = this.now();
      const mine = owned(listAgents(), this.session);
      mine.forEach((m, index) => {
        const ordinal = index + 1;
        if (readExit(m.id) !== undefined) return; // handled by deliverPending below
        if (!ownsPid(m.pid, m.id, this.ps)) {
          recordWrapperVanished(m.id, new Date(now));
          return;
        }
        const last = lastEventAt(m);
        const limits = checkLimits(m, last, now, this.flagged.get(m.id));
        if (limits.timeout) {
          // Fire and forget: the next sweep delivers the exit the wrapper writes.
          stop(m.id, "timeout", { graceMs: this.graceMs, ps: this.ps }).catch(() => {});
          changed = true;
        } else if (limits.idle) {
          this.flagged.set(m.id, now);
          const minutes = Math.max(0, Math.floor((now - last) / 60_000));
          this.send(idleText(m, ordinal, minutes));
          changed = true;
        }
      });
      if (deliverPending(this.session, this.send).length > 0) changed = true;
      // Anything new (events, exits, deliveries, idle flags) notifies the UI.
      for (const m of mine) {
        const sig = `${lastEventAt(m)}|${readExit(m.id)?.how ?? "run"}|${isDelivered(m.id)}`;
        if (this.seen.get(m.id) !== sig) {
          this.seen.set(m.id, sig);
          changed = true;
        }
      }
      if (changed) this.onChange();
    } finally {
      this.sweeping = false;
    }
  }
}

function killGroup(pgid: number, signal: NodeJS.Signals): void {
  try {
    process.kill(-pgid, signal);
  } catch {
    // The group is already gone: nothing to signal.
  }
}

function isPidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: any) {
    return err.code === "EPERM";
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => {
    const t = setTimeout(r, ms);
    t.unref(); // never keep the process alive just to finish a stop()
  });
}
