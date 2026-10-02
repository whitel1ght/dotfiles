import { TerminalManager, type ManagerOptions, type Terminal } from "../../background-terminals/src/manager.ts";
import { childArgs, shellLine } from "./invocation.ts";
import { Pinger, ProcessPing, type PingFn } from "./ping.ts";
import type { Timing } from "./roster.ts";
import { RunStream } from "./stream.ts";

export type AgentStatus = "running" | "done" | "failed" | "stopped";
export type AttemptOutcome = "pinging" | "running" | "done" | "failed" | "stalled" | "stopped" | "skipped";

// One model's turn at the task. Skipped models never started a child.
export interface Attempt {
  readonly model: string;
  outcome: AttemptOutcome;
  reason?: string;
  terminal?: Terminal;
  run?: RunStream;
}

export interface Agent {
  readonly id: string;
  readonly type: string;
  readonly profile: string | undefined;
  readonly task: string;
  readonly title: string;
  readonly startedAt: number;
  readonly attempts: Attempt[];
  status: AgentStatus;
  endedAt?: number;
  failure?: string;
}

export interface SpawnOptions {
  type: string;
  // Models to try, in order; the first that answers its ping and finishes wins.
  chain: readonly string[];
  task: string;
  cwd: string;
  tools: readonly string[];
  title?: string;
  profile?: { name: string; prompt: string };
  // The delegating agent's own model, which a subagent never runs on.
  parentModel?: string;
  // Why `model` cannot be used right now (no credentials, Ollama down, task too
  // big for it), checked before its ping. Undefined when it can.
  preflight?: (model: string) => Promise<string | undefined>;
}

export interface AgentManagerOptions extends Omit<ManagerOptions, "maxRunning"> {
  piCommand: string[];
  timing: Timing;
  maxRunning?: number;
  localModel?: string;
  // Replaces the real ping, for tests.
  ping?: PingFn;
  watchIntervalMs?: number;
}

const MAX_TASK_BYTES = 200 * 1024;
const TITLE_MAX = 80;

// Subagents are child pi processes run by a TerminalManager of their own:
// process groups, spill files, kill escalation and shutdown come from there.
export class AgentManager {
  private readonly terminals: TerminalManager;
  private readonly pinger: Pinger;
  private readonly processPing: ProcessPing;
  private readonly agents = new Map<string, Agent>();
  private readonly byTerminal = new Map<string, { agent: Agent; attempt: Attempt; settle: (o: AttemptOutcome) => void }>();
  private readonly stallReasons = new Map<string, string>();
  private readonly finishListeners = new Set<(agent: Agent) => void>();
  private readonly changeListeners = new Set<() => void>();
  private readonly waiters = new Set<() => void>();
  private readonly options: AgentManagerOptions;
  private readonly maxRunning: number;
  private readonly watchdog: ReturnType<typeof setInterval>;
  private counter = 0;

  constructor(options: AgentManagerOptions) {
    const { maxRunning = 4, piCommand, timing, localModel, ping, watchIntervalMs, ...terminalOptions } = options;
    this.options = options;
    this.maxRunning = maxRunning;
    // The terminal manager's own cap is never the one that bites.
    this.terminals = new TerminalManager({ ...terminalOptions, maxRunning: maxRunning + 1 });
    this.terminals.onExit((terminal) => this.attemptExited(terminal));
    this.terminals.onChange(() => this.emitChange());
    this.processPing = new ProcessPing(piCommand, timing.pingTimeoutMs);
    this.pinger = new Pinger(ping ?? this.processPing.ping, timing.pingCacheMs);
    this.watchdog = setInterval(() => this.checkStalls(), watchIntervalMs ?? 5000);
    this.watchdog.unref();
  }

  spawn(options: SpawnOptions): Agent {
    if (!options.task.trim()) throw new Error("task is empty");
    if (Buffer.byteLength(options.task) > MAX_TASK_BYTES) {
      throw new Error(`task is over ${MAX_TASK_BYTES / 1024}KB; put the material in a file and give the subagent its path`);
    }
    if (!options.chain.length) throw new Error("no models to try");
    if (this.running().length >= this.maxRunning) {
      throw new Error(`${this.maxRunning} subagents are already running; wait for one or stop it with agent_stop`);
    }
    const agent: Agent = {
      id: `agent-${++this.counter}`,
      type: options.type,
      profile: options.profile?.name,
      task: options.task,
      title: (options.title?.trim() || options.task.trim().split("\n")[0]).slice(0, TITLE_MAX),
      startedAt: Date.now(),
      attempts: [],
      status: "running",
    };
    this.agents.set(agent.id, agent);
    this.emitChange();
    void this.runChain(agent, options).catch((error) => this.settle(agent, "failed", `internal error: ${(error as Error).message}`));
    return agent;
  }

  get(id: string): Agent | undefined {
    return this.agents.get(id);
  }

  list(): Agent[] {
    return [...this.agents.values()];
  }

  running(): Agent[] {
    return this.list().filter((a) => a.status === "running");
  }

  async stop(id: string): Promise<Agent> {
    const agent = this.agents.get(id);
    if (!agent) throw new Error(`unknown subagent ${id}`);
    if (agent.status !== "running") return agent;
    const live = currentAttempt(agent);
    if (live?.outcome === "running" && live.terminal) {
      await this.terminals.stop(live.terminal.id);
    } else {
      // Still pinging: the chain sees the status and goes no further.
      if (live?.outcome === "pinging") Object.assign(live, { outcome: "stopped" });
      this.settle(agent, "stopped");
    }
    return agent;
  }

  // Resolves once every listed agent has finished, or when the signal aborts.
  async wait(ids: string[], signal?: AbortSignal): Promise<Agent[]> {
    const agents = ids.map((id) => {
      const agent = this.agents.get(id);
      if (!agent) throw new Error(`unknown subagent ${id}`);
      return agent;
    });
    while (!signal?.aborted && agents.some((a) => a.status === "running")) {
      await new Promise<void>((resolve) => {
        const wake = () => {
          this.waiters.delete(wake);
          signal?.removeEventListener("abort", wake);
          resolve();
        };
        this.waiters.add(wake);
        signal?.addEventListener("abort", wake, { once: true });
      });
    }
    return agents;
  }

  onChange(listener: () => void): () => void {
    this.changeListeners.add(listener);
    return () => this.changeListeners.delete(listener);
  }

  onFinish(listener: (agent: Agent) => void): () => void {
    this.finishListeners.add(listener);
    return () => this.finishListeners.delete(listener);
  }

  async shutdown(): Promise<void> {
    clearInterval(this.watchdog);
    this.finishListeners.clear();
    for (const agent of this.running()) agent.status = "stopped";
    this.processPing.shutdown();
    await this.terminals.shutdown();
    this.changeListeners.clear();
    for (const wake of [...this.waiters]) wake();
  }

  private async runChain(agent: Agent, options: SpawnOptions): Promise<void> {
    for (const model of options.chain) {
      if (agent.status !== "running") return;
      const skip = (reason: string) => {
        agent.attempts.push({ model, outcome: "skipped", reason });
        this.emitChange();
      };
      if (model === options.parentModel) {
        skip("it is the delegating agent's own model");
        continue;
      }
      const local = model === this.options.localModel;
      if (local && this.localBusy(agent)) {
        skip("the local model is busy with another subagent");
        continue;
      }
      const unusable = await options.preflight?.(model);
      if (agent.status !== "running") return;
      if (unusable) {
        skip(unusable);
        continue;
      }

      const attempt: Attempt = { model, outcome: "pinging" };
      agent.attempts.push(attempt);
      this.emitChange();
      const ping = await this.pinger.ping(model);
      if (agent.status !== "running") return;
      if (!ping.ok) {
        Object.assign(attempt, { outcome: "skipped", reason: `did not answer a ping: ${ping.reason}` });
        this.emitChange();
        continue;
      }

      const outcome = await this.runAttempt(agent, attempt, options, local);
      if (outcome === "done") return this.settle(agent, "done");
      if (outcome === "stopped") return this.settle(agent, "stopped");
      // A model that broke mid-run must be pinged again before it is trusted.
      this.pinger.forget(model);
    }
    this.settle(agent, "failed", `every model failed: ${agent.attempts.map((a) => `${a.model}: ${a.reason ?? a.outcome}`).join("; ")}`);
  }

  private runAttempt(agent: Agent, attempt: Attempt, options: SpawnOptions, local: boolean): Promise<AttemptOutcome> {
    const run = new RunStream();
    const args = childArgs({
      model: attempt.model,
      task: withHistory(options.task, agent.attempts),
      tools: options.tools,
      lean: local && !options.tools.length,
      profilePrompt: options.profile?.prompt,
    });
    return new Promise((settle) => {
      const terminal = this.terminals.start({
        command: shellLine(this.options.piCommand, args),
        cwd: options.cwd,
        title: agent.title,
        onStdout: (chunk) => run.write(chunk),
      });
      Object.assign(attempt, { outcome: "running", terminal, run });
      this.byTerminal.set(terminal.id, { agent, attempt, settle });
      this.emitChange();
    });
  }

  private attemptExited(terminal: Terminal): void {
    const entry = this.byTerminal.get(terminal.id);
    if (!entry) return;
    this.byTerminal.delete(terminal.id);
    const { attempt, settle } = entry;
    const run = attempt.run!;
    run.end();
    const stall = this.stallReasons.get(terminal.id);
    this.stallReasons.delete(terminal.id);
    if (stall) {
      Object.assign(attempt, { outcome: "stalled", reason: stall });
    } else if (terminal.status === "stopped") {
      attempt.outcome = "stopped";
    } else if (terminal.status === "error") {
      Object.assign(attempt, { outcome: "failed", reason: `could not start pi: ${terminal.error}` });
    } else {
      let failure = run.failure() ?? exitFailure(terminal);
      if (failure && terminal.status === "failed" && !run.turns) {
        // Died before any model call: pi's own stderr says why.
        const stderr = terminal.stderr.text().trim().split("\n").slice(-5).join("\n");
        if (stderr) failure = `${failure}\n${stderr}`;
      }
      Object.assign(attempt, failure ? { outcome: "failed", reason: failure } : { outcome: "done" });
    }
    this.emitChange();
    settle(attempt.outcome);
  }

  // Kills a child that has been silent for too long; its chain then moves on.
  private checkStalls(): void {
    const { timing, localModel } = this.options;
    const now = Date.now();
    for (const [terminalId, { attempt }] of this.byTerminal) {
      if (attempt.outcome !== "running" || this.stallReasons.has(terminalId)) continue;
      const run = attempt.run!;
      const inTool = run.toolsRunning > 0;
      const limit = inTool ? timing.toolStallMs : attempt.model === localModel ? timing.localStallMs : timing.stallMs;
      const quiet = now - run.lastEventAt;
      if (quiet <= limit) continue;
      const tool = inTool ? ` while a tool call was running (${run.activity.findLast((a) => a.kind === "tool")?.text ?? "?"})` : "";
      this.stallReasons.set(terminalId, `stalled: no output for ${Math.round(quiet / 1000)}s${tool}`);
      void this.terminals.stop(terminalId);
    }
  }

  private localBusy(except: Agent): boolean {
    return this.running().some((a) => {
      if (a === except) return false;
      const live = currentAttempt(a);
      return live?.model === this.options.localModel && (live.outcome === "running" || live.outcome === "pinging");
    });
  }

  private settle(agent: Agent, status: Exclude<AgentStatus, "running">, failure?: string): void {
    if (agent.status !== "running") return;
    agent.status = status;
    agent.failure = failure;
    agent.endedAt = Date.now();
    this.emitChange();
    for (const listener of this.finishListeners) listener(agent);
    for (const wake of [...this.waiters]) wake();
  }

  private emitChange(): void {
    for (const listener of this.changeListeners) listener();
  }
}

// The attempt that is running now, or that ended the agent.
export function currentAttempt(agent: Agent): Attempt | undefined {
  return agent.attempts.findLast((a) => a.outcome !== "skipped") ?? agent.attempts.at(-1);
}

export function currentModel(agent: Agent): string {
  return currentAttempt(agent)?.model ?? "?";
}

export function totalCost(agent: Agent): number {
  return agent.attempts.reduce((sum, a) => sum + (a.run?.cost ?? 0), 0);
}

export function totalToolCalls(agent: Agent): number {
  return agent.attempts.reduce((sum, a) => sum + (a.run?.toolCalls ?? 0), 0);
}

export function result(agent: Agent): string {
  return agent.status === "done" ? (currentAttempt(agent)?.run?.finalText ?? "") : "";
}

// The task as the next model sees it. When an earlier model got as far as
// calling tools, it may have left work half done; the next one must know.
export function withHistory(task: string, attempts: readonly Attempt[]): string {
  const touched = attempts.filter((a) => a.run && a.run.toolCalls > 0);
  if (!touched.length) return task;
  const lines = touched.map((a) => `- ${a.model}: ${a.run!.toolCalls} tool calls, then ${a.reason ?? a.outcome}`);
  return (
    `Note: earlier attempts at this task stopped partway, so files may already be partly changed. ` +
    `Check the current state before you continue.\n${lines.join("\n")}\n\n${task}`
  );
}

function exitFailure(terminal: Terminal): string | undefined {
  if (terminal.status !== "failed") return undefined;
  return terminal.signal ? `pi was killed by ${terminal.signal}` : `pi exited ${terminal.exitCode}`;
}
