import { spawn, type ChildProcess } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { StreamCapture } from "./output.ts";

export type TerminalStatus = "running" | "exited" | "failed" | "stopped" | "error";

export interface Terminal {
  readonly id: string;
  readonly title: string;
  readonly command: string;
  readonly cwd: string;
  readonly startedAt: number;
  readonly stdout: StreamCapture;
  readonly stderr: StreamCapture;
  pid?: number;
  status: TerminalStatus;
  exitCode?: number | null;
  signal?: NodeJS.Signals | null;
  endedAt?: number;
  error?: string;
}

export interface StartOptions {
  command: string;
  cwd: string;
  title?: string;
  // Sees every stdout chunk as it arrives, for callers that parse the stream.
  onStdout?: (chunk: Buffer) => void;
}

export interface ManagerOptions {
  maxRunning?: number;
  maxTracked?: number;
  shell?: string;
  killGraceMs?: number;
  // How long to wait for stdio to drain after the process exits. A background
  // grandchild can hold the pipes open forever, so this must be bounded.
  drainMs?: number;
  baseDir?: string;
}

const TITLE_MAX = 120;

export class TerminalManager {
  private readonly terminals = new Map<string, Terminal>();
  private readonly children = new Map<string, ChildProcess>();
  private readonly stopRequested = new Set<string>();
  private readonly settled = new Map<string, Promise<void>>();
  private readonly changeListeners = new Set<() => void>();
  private readonly exitListeners = new Set<(terminal: Terminal) => void>();
  private dir: string | undefined;
  private counter = 0;
  private readonly opts: Required<Omit<ManagerOptions, "baseDir">> & { baseDir?: string };

  constructor(options: ManagerOptions = {}) {
    this.opts = {
      maxRunning: options.maxRunning ?? 8,
      maxTracked: options.maxTracked ?? 64,
      shell: options.shell ?? "/bin/bash",
      killGraceMs: options.killGraceMs ?? 3000,
      drainMs: options.drainMs ?? 300,
      baseDir: options.baseDir,
    };
  }

  start({ command, cwd, title, onStdout }: StartOptions): Terminal {
    if (!command.trim()) throw new Error("command is empty");
    if (!existsSync(cwd) || !statSync(cwd).isDirectory()) {
      throw new Error(`cwd is not a directory: ${cwd}`);
    }
    if (this.running().length >= this.opts.maxRunning) {
      throw new Error(
        `${this.opts.maxRunning} background terminals are already running; stop one with bg_stop first`,
      );
    }
    this.prune();

    const id = `bg-${++this.counter}`;
    const dir = this.spillDir();
    const terminal: Terminal = {
      id,
      title: (title?.trim() || command.split("\n")[0]).slice(0, TITLE_MAX),
      command,
      cwd,
      startedAt: Date.now(),
      stdout: new StreamCapture(join(dir, `${id}.stdout`)),
      stderr: new StreamCapture(join(dir, `${id}.stderr`)),
      status: "running",
    };
    this.terminals.set(id, terminal);

    // stdin is closed: a background process can never wait on the model for input.
    // detached gives it its own process group, so stop can signal the whole tree.
    const child = spawn(this.opts.shell, ["-c", command], {
      cwd,
      stdio: ["ignore", "pipe", "pipe"],
      detached: true,
    });
    this.children.set(id, child);
    terminal.pid = child.pid;

    child.stdout?.on("data", (chunk: Buffer) => {
      terminal.stdout.write(chunk);
      onStdout?.(chunk);
    });
    child.stderr?.on("data", (chunk: Buffer) => terminal.stderr.write(chunk));

    let finished = false;
    let resolveSettled!: () => void;
    this.settled.set(id, new Promise<void>((resolve) => (resolveSettled = resolve)));

    const finish = async (patch: Partial<Terminal>) => {
      if (finished) return;
      finished = true;
      Object.assign(terminal, patch, { endedAt: Date.now() });
      this.children.delete(id);
      // Stop reading: a grandchild that inherited the pipes would otherwise keep
      // them (and the event loop) open long after the process itself is gone.
      child.stdout?.destroy();
      child.stderr?.destroy();
      await Promise.all([terminal.stdout.end(), terminal.stderr.end()]);
      resolveSettled();
      this.emitChange();
      for (const listener of this.exitListeners) listener(terminal);
    };

    child.on("error", (error) => {
      void finish({ status: "error", error: error.message });
    });
    child.on("exit", (code, signal) => {
      const status: TerminalStatus = this.stopRequested.has(id)
        ? "stopped"
        : code === 0
          ? "exited"
          : "failed";
      const done = () => void finish({ status, exitCode: code, signal });
      // Prefer 'close' (stdio fully drained) but never wait on it indefinitely.
      const timer = setTimeout(done, this.opts.drainMs);
      child.once("close", () => {
        clearTimeout(timer);
        done();
      });
    });

    this.emitChange();
    return terminal;
  }

  get(id: string): Terminal | undefined {
    return this.terminals.get(id);
  }

  list(): Terminal[] {
    return [...this.terminals.values()];
  }

  running(): Terminal[] {
    return this.list().filter((t) => t.status === "running");
  }

  // SIGTERM the whole process group, escalate to SIGKILL after the grace period.
  async stop(id: string, force = false): Promise<Terminal> {
    const terminal = this.terminals.get(id);
    if (!terminal) throw new Error(`unknown terminal ${id}`);
    if (terminal.status !== "running") return terminal;

    this.stopRequested.add(id);
    this.signal(terminal, force ? "SIGKILL" : "SIGTERM");

    const settled = this.settled.get(id)!;
    const timer = setTimeout(() => this.signal(terminal, "SIGKILL"), this.opts.killGraceMs);
    await settled;
    clearTimeout(timer);
    return terminal;
  }

  onChange(listener: () => void): () => void {
    this.changeListeners.add(listener);
    return () => this.changeListeners.delete(listener);
  }

  onExit(listener: (terminal: Terminal) => void): () => void {
    this.exitListeners.add(listener);
    return () => this.exitListeners.delete(listener);
  }

  // Idempotent: kills everything and removes the spill files.
  async shutdown(): Promise<void> {
    this.exitListeners.clear();
    await Promise.all(this.running().map((t) => this.stop(t.id, true)));
    this.changeListeners.clear();
    if (this.dir) rmSync(this.dir, { recursive: true, force: true });
    this.dir = undefined;
  }

  private signal(terminal: Terminal, signal: NodeJS.Signals): void {
    if (terminal.pid === undefined) return;
    try {
      process.kill(-terminal.pid, signal);
    } catch {
      // Already gone (ESRCH), or never became a group leader.
      try {
        process.kill(terminal.pid, signal);
      } catch {}
    }
  }

  private spillDir(): string {
    this.dir ??= mkdtempSync(join(this.opts.baseDir ?? tmpdir(), "pi-bg-"));
    return this.dir;
  }

  // Drop the oldest finished terminals once too many are tracked.
  private prune(): void {
    const finished = this.list().filter((t) => t.status !== "running");
    let excess = this.terminals.size - this.opts.maxTracked + 1;
    for (const terminal of finished) {
      if (excess <= 0) break;
      this.terminals.delete(terminal.id);
      this.settled.delete(terminal.id);
      this.stopRequested.delete(terminal.id);
      rmSync(terminal.stdout.path, { force: true });
      rmSync(terminal.stderr.path, { force: true });
      excess--;
    }
  }

  private emitChange(): void {
    for (const listener of this.changeListeners) listener();
  }
}
