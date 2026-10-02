import { spawn, type ChildProcess } from "node:child_process";
import { CHILD_ENV } from "./invocation.ts";
import { RunStream } from "./stream.ts";

// Before a model is handed a task it must answer a one-line prompt, through the
// same pi, provider and credentials the subagent will use. A model that does not
// answer (401, expired token, region-locked, overloaded, Ollama down) is skipped
// in seconds instead of leaving a subagent hanging.

export interface PingResult {
  readonly ok: boolean;
  readonly reason?: string;
  readonly ms: number;
}

export type PingFn = (model: string) => Promise<PingResult>;

export const PING_PROMPT = "Reply with exactly: ok";
// A failure is remembered for less time than a success: a provider that was
// briefly down should get another chance soon.
const FAILURE_CACHE_MS = 60_000;

export function pingArgs(model: string): string[] {
  // Extensions stay on: claude-bridge models need theirs.
  return ["--mode", "json", "-p", "--no-session", "--model", model, "--no-tools", "-ns", "-nc", "-np", PING_PROMPT];
}

// Pings in child pi processes. shutdown() kills any still running.
export class ProcessPing {
  private readonly command: string[];
  private readonly timeoutMs: number;
  private readonly children = new Set<ChildProcess>();

  constructor(command: string[], timeoutMs: number) {
    this.command = command;
    this.timeoutMs = timeoutMs;
  }

  readonly ping: PingFn = (model) =>
    new Promise((resolve) => {
      const started = Date.now();
      const run = new RunStream();
      let stderr = "";
      let timedOut = false;
      const child = spawn(this.command[0], [...this.command.slice(1), ...pingArgs(model)], {
        stdio: ["ignore", "pipe", "pipe"],
        detached: true,
        env: { ...process.env, [CHILD_ENV]: "1" },
      });
      this.children.add(child);
      child.stdout?.on("data", (chunk: Buffer) => run.write(chunk));
      child.stderr?.on("data", (chunk: Buffer) => {
        stderr = (stderr + chunk.toString()).slice(-2000);
      });
      const timer = setTimeout(() => {
        timedOut = true;
        kill(child);
      }, this.timeoutMs);
      const done = (spawnError?: Error) => {
        clearTimeout(timer);
        this.children.delete(child);
        run.end();
        const ms = Date.now() - started;
        if (spawnError) return resolve({ ok: false, reason: `could not start pi: ${spawnError.message}`, ms });
        if (timedOut) return resolve({ ok: false, reason: `no answer within ${Math.round(this.timeoutMs / 1000)}s`, ms });
        const failure = run.failure();
        if (!failure) return resolve({ ok: true, ms });
        const why = run.turns ? failure : stderr.trim().split("\n").slice(-3).join(" ") || failure;
        resolve({ ok: false, reason: why, ms });
      };
      child.once("error", (error) => done(error));
      child.once("close", () => done());
    });

  shutdown(): void {
    for (const child of this.children) kill(child);
    this.children.clear();
  }
}

// Remembers results per model and shares one ping between callers that ask at once.
export class Pinger {
  private readonly fn: PingFn;
  private readonly cacheMs: number;
  private readonly now: () => number;
  private readonly cache = new Map<string, { result: PingResult; at: number }>();
  private readonly inFlight = new Map<string, Promise<PingResult>>();

  constructor(fn: PingFn, cacheMs: number, now: () => number = Date.now) {
    this.fn = fn;
    this.cacheMs = cacheMs;
    this.now = now;
  }

  ping(model: string): Promise<PingResult> {
    const cached = this.cache.get(model);
    if (cached && this.now() - cached.at < (cached.result.ok ? this.cacheMs : Math.min(this.cacheMs, FAILURE_CACHE_MS))) {
      return Promise.resolve(cached.result);
    }
    const pending = this.inFlight.get(model);
    if (pending) return pending;
    const promise = this.fn(model).then((result) => {
      this.cache.set(model, { result, at: this.now() });
      this.inFlight.delete(model);
      return result;
    });
    this.inFlight.set(model, promise);
    return promise;
  }

  // A model that failed mid-run is not worth a cached "ok" any more.
  forget(model: string): void {
    this.cache.delete(model);
  }
}

function kill(child: ChildProcess): void {
  if (child.pid === undefined) return;
  try {
    process.kill(-child.pid, "SIGKILL");
  } catch {
    try {
      child.kill("SIGKILL");
    } catch {}
  }
}
