import { execFile, execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
// The Claude Code plugin's harness-free parsers, imported in place so both
// harnesses read and write byte-identical state. Only the glue is pi-specific.
import { extractBlock } from "./mod/diary.ts";
import { applyEdit, checkTicks, denyMessage, isTodaysDiary } from "./mod/guard.ts";
import type { OnBlock } from "./mod/guard.ts";
import { messageFiles } from "./mod/inbox.ts";
import { parseRunState } from "./mod/runstate.ts";
import { acquireLock, DayWatcher, INBOX_MS, releaseLock, WATCH_MS, type Exec, type WakeProbe } from "./watch.ts";
import { IdeasNudger } from "./ideas.ts";
import { AskBackstop, piSubRunning } from "./ask.ts";
import { FollowupDelivery, decideList, decisionsSession } from "./followup.ts";
import { FOLLOWUP_MS } from "./mod/followup.ts";
import { PI_PLAYBOOK, UPDATE_ARGS, fingerprint } from "./mod/update.ts";
import { resumedBetween } from "./mod/wake.ts";
import type { SuspendSample } from "./mod/wake.ts";

const IDEAS_MS = 60_000;

/** `ideas due --sync --limit 3` has something; any failure counts as nothing due. */
function ideasDue(): Promise<boolean> {
  return new Promise((resolve) => {
    const bin = existsSync(join(homedir(), ".local/bin/ideas")) ? join(homedir(), ".local/bin/ideas") : "ideas";
    execFile(bin, ["due", "--sync", "--limit", "3"], { timeout: 30_000 }, (err, stdout) => {
      try {
        resolve(!err && (JSON.parse(String(stdout)) as unknown[]).length > 0);
      } catch {
        resolve(false);
      }
    });
  });
}

const MAX_CHARS = 6000;
const BLOCK_MAX = 3000;

type Paths = {
  stateDir: string;
  runState: string;
  diary: string;
  inbox: string;
  today: string;
  playbook: string;
  resumeMarker: string;
};

function paths(): Paths {
  const stateDir = process.env.RUN_DAY_STATE_DIR ?? join(homedir(), ".local/state/run-day");
  const wiki = process.env.WIKI_DIR ?? join(homedir(), "wiki");
  const now = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  const today =
    process.env.RUN_DAY_DATE ?? `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`;
  return {
    stateDir,
    today,
    runState: join(stateDir, `${today}.md`),
    diary: join(wiki, "diary", `${today}.md`),
    inbox: join(stateDir, "inbox"),
    // pi's own record: it fingerprints other files than Claude's `<date>.playbook`
    playbook: join(stateDir, `${today}.pi-playbook`),
    resumeMarker: join(stateDir, `${today}.pi-resume`),
  };
}

// The pi playbook, the briefs and this extension's code as the dotfiles checkout holds them now
// (mod/update.ts): a change to any of them means the day should reload and resume.
function piPrint(): string {
  const top = process.env.DOTFILES_DIR ?? join(homedir(), "projects", "dotfiles");
  const code = ["pi/extensions/daily", "claude/daily/mod"].flatMap((dir) => {
    try {
      return readdirSync(join(top, dir))
        .filter((f) => f.endsWith(".ts") && !f.endsWith(".test.ts"))
        .sort()
        .map((f) => `${dir}/${f}`);
    } catch {
      return [];
    }
  });
  const read = (p: string) => {
    try {
      return readFileSync(join(top, p), "utf8");
    } catch {
      return "";
    }
  };
  return fingerprint([...PI_PLAYBOOK, ...code].map(read));
}

/** Fire-and-forget: a missing or failing friction must never slow or change the caller. */
export function friction(kind: string, msg: string, source = "daily-guard"): void {
  try {
    const args = ["--harness", "pi", "--source", source, kind, msg.replace(/\s+/g, " ").slice(0, 300)];
    spawn("friction", args, { detached: true, stdio: "ignore" }).on("error", () => {}).unref();
  } catch {
    // swallowed on purpose
  }
}

const cut = (s: string, n: number) => [...s].slice(0, n).join("");

function readIfExists(path: string): string {
  return existsSync(path) ? readFileSync(path, "utf8") : "";
}

/** The run-state context, rebuilt every request so a compaction cannot lose the day. */
export function runStateSection(): string | null {
  const p = paths();
  if (!existsSync(p.runState)) return null;

  const pending = existsSync(p.inbox) ? messageFiles(readdirSync(p.inbox)).length : 0;
  const inboxLine = pending
    ? `\n${pending} pending inbox message(s) in ${p.inbox}: process them first (run-day.md, section 7).`
    : "";
  const head =
    `A /run-day session is active for ${p.today}. Playbook: ~/.pi/agent/prompts/run-day.md (re-read it before acting on events).\n` +
    `Write rules: subagents never write ~/wiki, except ~/wiki/work/system/ and ~/wiki/tools/ when they change a system repo (dotfiles, decisions, articles), committed with wiki-commit; only this session writes diary markers, ~/wiki/work/projects/<p>/log entries and decisions; /end-day consolidates state.md.\n` +
    `owner=external:KEY in the run state means that item is in a side session: never dispatch it or start a review round for it.${inboxLine}`;

  const blockHead = `\n\n## Diary plan block (${p.diary})\n`;
  let stateText = `\n\n## Run state (${p.runState})\n${readFileSync(p.runState, "utf8")}`;
  let block = extractBlock(readIfExists(p.diary)) ?? "";

  // The run state is the tail and must survive: trim the diary block first.
  let room = MAX_CHARS - head.length - stateText.length - blockHead.length - 40;
  if (room > BLOCK_MAX) room = BLOCK_MAX;
  if (room <= 0) {
    block = "";
    stateText = cut(stateText, MAX_CHARS - head.length);
  } else if ([...block].length > room) {
    block = `${cut(block, room)}\n[plan block truncated]`;
  }

  return cut(`${head}${blockHead}${block}${stateText}`, MAX_CHARS);
}

let directionsCache: { key: string; text: string } | null = null;

/**
 * The standing directions friction-ledger renders from ~/wiki/work/friction/directions.md,
 * cached until the file's mtime changes. A missing file or script, or a failing one,
 * is no section and never an error.
 */
export function directionsSection(): string | null {
  const file = join(process.env.FRICTION_WIKI ?? join(homedir(), "wiki/work/friction"), "directions.md");
  let key: string;
  try {
    key = `${file}:${statSync(file).mtimeMs}`;
  } catch {
    directionsCache = null;
    return null;
  }
  if (directionsCache?.key !== key) {
    const bin = process.env.FRICTION_LEDGER_BIN ?? join(homedir(), ".local/bin/friction-ledger");
    let text = "";
    try {
      if (existsSync(bin)) {
        text = execFileSync(bin, ["directions", "render"], {
          encoding: "utf8",
          timeout: 5000,
          stdio: ["ignore", "pipe", "ignore"],
        }).trim();
      }
    } catch {
      text = "";
    }
    directionsCache = {
      key,
      text: text
        ? `## Standing directions\nRules the user gave in earlier sessions, active until retired. Follow them.\n${text}`
        : "",
    };
  }
  return directionsCache.text || null;
}

const MAP_MAX_BYTES = 3072;
let mapCache: { key: string; text: string } | null = null;

/**
 * The system map ($SYSTEM_MAP, else $WIKI_DIR/work/system/map.md, WIKI_DIR defaulting to ~/wiki), cut to 3072 bytes and cached until the
 * file's mtime changes. A leading "# …" title is dropped: the section has its own heading. A missing, empty or unreadable file is no section and never an error.
 */
export function systemMapSection(): string | null {
  const file = process.env.SYSTEM_MAP ?? join(process.env.WIKI_DIR ?? join(homedir(), "wiki"), "work/system/map.md");
  try {
    const key = `${file}:${statSync(file).mtimeMs}`;
    if (mapCache?.key !== key) {
      const body = new TextDecoder("utf-8")
        .decode(readFileSync(file).subarray(0, MAP_MAX_BYTES))
        .replace(/�+$/, "")
        .replace(/^# [^\n]*(\n|$)/, "");
      mapCache = { key, text: body.trim() ? `## System map\n${body}` : "" };
    }
    return mapCache.text || null;
  } catch {
    mapCache = null;
    return null;
  }
}

const TOTAL_MAX = 9000;
const CUT_MARK = "\n(cut)";

function fit(text: string | null, room: number): string | null {
  if (!text) return null;
  const chars = [...text];
  if (chars.length <= room) return text;
  return room > CUT_MARK.length ? chars.slice(0, room - CUT_MARK.length).join("") + CUT_MARK : null;
}

/**
 * The three injected sections within TOTAL_MAX characters, as Claude's session-start hook
 * keeps them: the run state is never cut (it is at most MAX_CHARS), the map takes what is
 * left, then the directions; each cut is marked.
 */
export function fitSections(runState: string | null, directions: string | null, systemMap: string | null) {
  let room = TOTAL_MAX - [...(runState ?? "")].length;
  const map = fit(systemMap, room);
  room -= [...(map ?? "")].length;
  return { runState, directions: fit(directions, room), systemMap: map };
}

/** Items whose needs_you flipped on since the last request. */
const announced = new Set<string>();

export function newlyNeedsYou(runState: string): string[] {
  const fresh: string[] = [];
  for (const item of parseRunState(runState)) {
    if (!item.needsYou || announced.has(item.key)) continue;
    announced.add(item.key);
    fresh.push(item.key);
  }
  return fresh;
}

type PiEdit = { oldText?: unknown; newText?: unknown };

/** The diary tick guard, or undefined when this call is none of its business. */
export function guardVerdict(
  toolName: string,
  input: Record<string, unknown>,
  today: string,
  active: boolean,
  onBlock?: OnBlock,
): string | undefined {
  if (!active) return undefined;
  if (toolName !== "edit" && toolName !== "write") return undefined;
  const path = String(input.path ?? "");
  if (!isTodaysDiary(path, today)) return undefined;

  const before = readIfExists(path);
  let after: string | null;
  if (toolName === "write") {
    after = applyEdit(before, { tool: "Write", content: String(input.content ?? "") });
  } else {
    const edits = Array.isArray(input.edits) ? (input.edits as PiEdit[]) : [];
    after = before;
    for (const e of edits) {
      // An oldText that does not match is the edit tool's own failure, not a tick.
      const next = applyEdit(after, {
        tool: "Edit",
        old_string: String(e?.oldText ?? ""),
        new_string: String(e?.newText ?? ""),
      });
      if (next === null) return undefined;
      after = next;
    }
  }
  if (after === null) return undefined;

  const result = checkTicks(before, after, onBlock);
  return result.ok ? undefined : denyMessage(result.lines);
}

/** changes-since --cursor run-day, without blocking pi; a timeout reports exit 124. */
function changesSince(): Promise<Exec> {
  const cmd = 'exec "$(command -v changes-since || echo "$HOME/.local/bin/changes-since")" --cursor run-day';
  return new Promise((resolve) => {
    execFile("/bin/sh", ["-c", cmd], { timeout: 60_000, maxBuffer: 4 << 20 }, (err, stdout, stderr) => {
      const e = err as (NodeJS.ErrnoException & { killed?: boolean; code?: number | string }) | null;
      const code = !e ? 0 : e.killed ? 124 : typeof e.code === "number" ? e.code : 1;
      resolve({ code, stdout: String(stdout), stderr: String(stderr || e?.message || "") });
    });
  });
}

/** Raw lid and display state, macOS only; unreadable output is an empty string. */
function macLidAndGraphics(): Promise<{ lid: string; systemstate: string }> {
  const out = (bin: string, args: string[]) =>
    new Promise<string>((resolve) => {
      execFile(bin, args, { timeout: 2_000 }, (err, stdout) => resolve(err ? "" : String(stdout)));
    });
  return Promise.all([
    out("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "1"]),
    out("/usr/bin/pmset", ["-g", "systemstate"]),
  ]).then(([lid, systemstate]) => ({ lid, systemstate }));
}

/**
 * The Linux suspend sample: CLOCK_BOOTTIME advances during suspend, CLOCK_MONOTONIC does not
 * (mod/wake.ts resumedBetween). The same one-liner the Claude plugin uses.
 */
const LINUX_SUSPEND_SAMPLE = `python3 -c 'import json,time; print(json.dumps({"bootId":open("/proc/sys/kernel/random/boot_id").read().strip(),"bootMs":time.clock_gettime(time.CLOCK_BOOTTIME)*1000,"monotonicMs":time.clock_gettime(time.CLOCK_MONOTONIC)*1000}))'`;

/** A sample is usable only with a boot id and finite clocks; anything else fails closed. */
export function parseSuspendSample(stdout: string): SuspendSample | null {
  try {
    const { bootId, bootMs, monotonicMs } = (JSON.parse(stdout) ?? {}) as Partial<SuspendSample>;
    if (typeof bootId !== "string" || bootId === "") return null;
    if (!Number.isFinite(bootMs) || !Number.isFinite(monotonicMs)) return null;
    return { bootId, bootMs: Number(bootMs), monotonicMs: Number(monotonicMs) };
  } catch {
    return null;
  }
}

/** One shell command for the wake probe: a 2 s timeout, and unreadable output as an empty string. */
function shell2s(cmd: string): Promise<string> {
  return new Promise((resolve) => {
    execFile("/bin/sh", ["-c", cmd], { timeout: 2_000 }, (err, stdout) => resolve(err ? "" : String(stdout)));
  });
}

/** The host answers the same way for the life of this process, so a good answer is kept. */
let wakePlatform: WakeProbe["platform"] | null = null;

async function platform(): Promise<WakeProbe["platform"]> {
  if (wakePlatform !== null) return wakePlatform;
  const ran = (await shell2s("uname -s")).trim();
  if (ran === "") return "unsupported"; // no answer yet: never cached, so the next tick retries
  wakePlatform = ran === "Linux" ? "linux" : ran === "Darwin" ? "darwin" : "unsupported";
  return wakePlatform;
}

/**
 * The wake probe (watch.ts). Linux compares CLOCK_BOOTTIME with CLOCK_MONOTONIC across ticks, so
 * only a suspend-offset delta counts as a resume and no lid or display is needed; macOS keeps its
 * lid and display probe, run only when a verdict may be needed.
 */
function makeWakeProbe(): { probe: (needed: boolean) => Promise<WakeProbe>; reset: () => void } {
  let sample: SuspendSample | null = null;
  return {
    reset: () => {
      sample = null;
    },
    probe: async (needed) => {
      const plat = await platform();
      if (plat === "linux") {
        const current = parseSuspendSample(await shell2s(LINUX_SUSPEND_SAMPLE));
        const resumed = resumedBetween(sample, current);
        sample = current;
        return { platform: "linux", resumed, sampled: current !== null, lid: "", systemstate: "" };
      }
      if (plat === "unsupported") return { platform: "unsupported", resumed: false, sampled: false, lid: "", systemstate: "" };
      const mac = needed ? await macLidAndGraphics() : { lid: "", systemstate: "" };
      return { platform: "darwin", resumed: false, sampled: true, ...mac };
    },
  };
}

type Ui = { notify?: (message: string, type?: "info" | "warning" | "error") => void } | undefined;

/**
 * The run_day_watch tool: /run-day starts the watcher in its own session, so other pi
 * sessions open the same day (side sessions, unrelated work) are never woken by it. A lock
 * file in the state dir keeps a second pi session from consuming the same event cursor.
 */
function registerWatch(pi: ExtensionAPI, getUi: () => Ui, getSession: () => string) {
  let timers: ReturnType<typeof setInterval>[] = [];
  const lockPath = () => join(paths().stateDir, "watch.lock");
  const send = (content: string, wake: boolean) =>
    pi.sendMessage(
      { customType: "daily-event", content, display: true },
      wake ? { triggerTurn: true, deliverAs: "followUp" } : { deliverAs: "nextTurn" },
    );
  const wake = makeWakeProbe();
  const watcher = new DayWatcher({
    paths: () => paths(),
    changes: changesSince,
    listInbox: () => {
      try {
        return readdirSync(paths().inbox);
      } catch {
        return [];
      }
    },
    holdsLock: () => {
      try {
        return (JSON.parse(readFileSync(lockPath(), "utf8")) as { pid: number }).pid === process.pid;
      } catch {
        return false;
      }
    },
    probe: wake.probe,
    wake: (t) => send(t, true),
    note: (t) => send(t, false),
    notify: (m, level) => getUi()?.notify?.(m, level),
    friction: (kind, msg, source) => friction(kind, msg, source),
  });

  // for the Keep busy prompt (watch.ts checkBusy, mod/busy.ts)
  const activity = { lastActiveAt: Date.now(), turnRunning: false, userWrote: false };
  pi.on("input", (event) => {
    if (event.source === "extension") return;
    activity.lastActiveAt = Date.now();
    activity.userWrote = true;
  });
  pi.on("agent_start", () => {
    activity.turnRunning = true;
  });
  pi.on("agent_end", () => {
    activity.turnRunning = false;
    activity.lastActiveAt = Date.now();
  });

  const stop = () => {
    for (const t of timers) clearInterval(t);
    timers = [];
    wake.reset(); // a later start samples afresh instead of judging against a sample from hours ago
    releaseLock(lockPath(), process.pid);
  };
  const tick = (fn: () => unknown) => () => {
    if (!watcher.active()) {
      stop(); // /end-day moved the run state away: the day is over
      getUi()?.notify?.("run-day ended: watcher stopped", "info");
      return;
    }
    void fn();
  };
  const start = (): string => {
    if (!watcher.active()) return `No run state for ${paths().today}: nothing to watch. /run-day creates it.`;
    if (timers.length > 0) return "Already watching this day in this session.";
    const refused = acquireLock(lockPath(), { pid: process.pid, session: getSession() });
    if (refused) return `Not started: ${refused}. Only one pi session watches a day.`;
    try {
      watcher.recordPlaybook(piPrint());
    } catch {
      // without a record no update is ever detected; the day itself runs on
    }
    const every = (ms: number, fn: () => unknown) => {
      const t = setInterval(tick(fn), ms);
      t.unref?.();
      timers.push(t);
    };
    every(INBOX_MS, async () => {
      // the wake check first: it records the tick gap, and an inbox failure must not lose it
      const nudge = await watcher.checkWake(Date.now()).catch(() => null);
      if (nudge) send(nudge, true);
      const told = watcher.checkInbox();
      const busy = told ? null : watcher.checkBusy(Date.now(), activity);
      if (!told) activity.userWrote = false;
      if (busy) send(busy, true);
      // a merge changed the playbook or this extension: reload and resume the day with it
      if (watcher.checkUpdate(piPrint())) void pi.sendUserMessage("/daily-update", { expandPromptTemplates: true, deliverAs: "followUp" });
    });
    every(WATCH_MS, () => watcher.checkEvents());
    return (
      "Watching: the inbox every 30 s, GitLab/Jira events every 3 min. New inbox messages arrive " +
      'as "inbox: N new"; events for today\'s MRs and tickets as [daily-event] lines that start a ' +
      "turn; the rest as [daily-event:info] lines without one. It stops when the run state goes."
    );
  };

  pi.registerTool({
    name: "run_day_watch",
    label: "Run-day watch",
    description:
      "Start, stop or check the /run-day watcher in this session: it wakes you with new inbox messages and " +
      "GitLab/Jira events for today's plan. Only the session running /run-day starts it.",
    promptSnippet: "run_day_watch: start/stop/status of the /run-day inbox and event watcher",
    parameters: {
      type: "object",
      properties: { action: { type: "string", enum: ["start", "stop", "status"], description: "start, stop or status" } },
      required: ["action"],
    } as never,
    async execute(_id: string, params: unknown) {
      const action = String((params as { action?: unknown })?.action ?? "status");
      let text: string;
      if (action === "start") text = start();
      else if (action === "stop") {
        const was = timers.length > 0;
        stop();
        text = was ? "Watcher stopped." : "Watcher was not running.";
      } else text = timers.length > 0 ? "Watching this day in this session." : "Not watching in this session.";
      return { content: [{ type: "text" as const, text }], details: { action } };
    },
  } as never);

  return stop;
}

export default function daily(pi: ExtensionAPI) {
  let ui: Ui;
  let session = "unknown";
  pi.on("session_start", (event, ctx) => {
    ui = ctx?.ui as Ui;
    session = ctx?.sessionManager?.getSessionId?.() ?? session;
    // The fresh copy after /daily-update's reload resumes the day with the new playbook, once.
    if ((event as { reason?: string })?.reason !== "reload") return;
    const marker = paths().resumeMarker;
    try {
      if (readFileSync(marker, "utf8").trim() !== session) return;
      rmSync(marker, { force: true });
    } catch {
      return;
    }
    void pi.sendUserMessage(`/run-day ${UPDATE_ARGS}`, { expandPromptTemplates: true, deliverAs: "followUp" });
  });

  // Sent by the watcher when a merge changed the playbook, the briefs or this extension.
  pi.registerCommand("daily-update", {
    description: "Reload the daily extension and resume today's run with the new playbook",
    handler: async (_args, ctx) => {
      writeFileSync(paths().resumeMarker, `${session}\n`);
      await ctx.reload();
    },
  });
  const stopWatch = registerWatch(pi, () => ui, () => session);

  // "the system" session reviews ideas when idle (ideas.ts, mod/ideas.ts)
  const ideas = new IdeasNudger({
    now: () => Date.now(),
    stateHome: () => join(homedir(), ".local", "state"),
    session: () => session,
    due: ideasDue,
    send: (content) =>
      pi.sendMessage({ customType: "ideas", content, display: true }, { triggerTurn: true, deliverAs: "followUp" }),
  });
  pi.on("input", (event) => {
    try {
      ideas.onInput(event.text, event.source);
    } catch {
      // never lose the user's input because the ideas mark failed
    }
  });
  pi.on("agent_start", () => ideas.onAgentStart());
  pi.on("agent_end", () => ideas.onAgentEnd());
  const ideasTimer = setInterval(() => void ideas.tick().catch(() => {}), IDEAS_MS);
  ideasTimer.unref?.();

  // Every session's questions go to the decisions deck (ask.ts, mod/ask.ts); subagents ask nobody.
  let followupTimer: ReturnType<typeof setInterval> | undefined;
  if (!process.env.PI_SUBAGENT) {
    let deliverAs: "steer" | "followUp" | "nextTurn" = "nextTurn";
    const ask = new AskBackstop({
      agentsRunning: () => piSubRunning(session),
      note: (content) => pi.sendMessage({ customType: "decisions", content, display: false }, { deliverAs }),
      nudge: (content) => pi.sendMessage({ customType: "decisions", content, display: true }, { triggerTurn: true, deliverAs: "followUp" }),
    });
    pi.on("input", (event) => {
      try {
        deliverAs = event.streamingBehavior ?? "nextTurn";
        ask.onInput(event.source, event.streamingBehavior);
      } catch {
        // never lose the user's input because the note failed
      }
    });
    pi.on("agent_end", (event) => {
      try {
        ask.onAgentEnd(event.messages as never);
      } catch {
        // a failed check only skips the nudge
      }
    });
    pi.on("tool_call", (event) => ask.onToolCall(event.toolName));

    // and the user's follow-ups on its answer cards come back to it (followup.ts, mod/followup.ts)
    const followups = new FollowupDelivery({
      list: decideList,
      session: decisionsSession(),
      send: (content) => pi.sendMessage({ customType: "decisions", content, display: true }, { triggerTurn: true, deliverAs: "followUp" }),
    });
    followupTimer = setInterval(() => void followups.tick().catch(() => {}), FOLLOWUP_MS);
    followupTimer.unref?.();
  }

  pi.on("session_shutdown", () => {
    stopWatch();
    clearInterval(ideasTimer);
    clearInterval(followupTimer);
  });

  // before_agent_start, not context_with_system: measured on pi 1.2.0, a section added to the
  // system message there never reaches the provider request — pi rebuilds the system head from
  // its own sections. Mutating systemPromptOptions.sections does reach it.
  pi.on("before_agent_start", (event, ctx) => {
    let section: string | null = null;
    try {
      section = runStateSection();
      if (section) {
        for (const key of newlyNeedsYou(readIfExists(paths().runState))) {
          ctx.ui?.notify?.(`run-day needs you: ${key}`, "warning");
        }
      }
    } catch {
      section = null; // never lose a turn because the day context failed
    }
    let directions: string | null = null;
    try {
      directions = directionsSection();
    } catch {
      directions = null;
    }

    let systemMap: string | null = null;
    try {
      systemMap = systemMapSection();
    } catch {
      systemMap = null;
    }

    const fitted = fitSections(section, directions, systemMap);
    // Omitting a key on a later turn is what removes it: pi diffs sections by name.
    const sections = event.systemPromptOptions.sections;
    if (fitted.runState) sections.daily_run_state = fitted.runState;
    if (fitted.directions) sections.standing_directions = fitted.directions;
    if (fitted.systemMap) sections.system_map = fitted.systemMap;
  });

  pi.on("tool_call", (event, _ctx) => {
    let reason: string | undefined;
    try {
      const p = paths();
      reason = guardVerdict(
        event.toolName,
        event.input as Record<string, unknown>,
        p.today,
        existsSync(p.runState),
        (msg) => friction("guard", msg),
      );
    } catch {
      return; // a throwing guard must never block an unrelated edit
    }
    return reason ? { block: true, reason } : undefined;
  });
}
