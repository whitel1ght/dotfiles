// The /run-day watcher for pi: the same work as the Claude plugin's
// hooks/register.tsx (watch, watchInbox), on the same harness-free parsers, so
// both harnesses turn changes-since output into identical [daily-event] lines.
// The session that runs the day starts it with the run_day_watch tool (index.ts).
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";

import { mrKeyFromRef, mrKeysOf, parseItems, ticketKey } from "./mod/diary.ts";
import { classify, formatNote, formatPrompt, parseEvents } from "./mod/events.ts";
import { inboxPrompt, nextInbox } from "./mod/inbox.ts";
import { parseRunState } from "./mod/runstate.ts";

export const WATCH_MS = 180_000;
export const INBOX_MS = 30_000;

export type Exec = { code: number; stdout: string; stderr: string };

export type WatchDeps = {
  paths: () => { runState: string; diary: string };
  /** changes-since --cursor run-day */
  changes: () => Promise<Exec>;
  listInbox: () => string[];
  /** Add a message and start a turn on it. */
  wake: (text: string) => void;
  /** Add a message for the next turn, without starting one. */
  note: (text: string) => void;
  notify: (message: string, level: "info" | "warning") => void;
  friction: (kind: string, msg: string, source: string) => void;
};

const firstLine = (s: string) => s.split("\n")[0].trim();
const readOr = (path: string) => (existsSync(path) ? readFileSync(path, "utf8") : "");

export class DayWatcher {
  private checking = false;
  private failed = false;
  private seen: string[] = [];
  private deps: WatchDeps;

  constructor(deps: WatchDeps) {
    this.deps = deps;
  }

  active(): boolean {
    return existsSync(this.deps.paths().runState);
  }

  async checkEvents(): Promise<void> {
    if (this.checking || !this.active()) return;
    this.checking = true;
    try {
      const ran = await this.deps.changes();
      if (ran.code !== 0) {
        if (!this.failed) {
          const why = `changes-since failed (exit ${ran.code}): ${firstLine(ran.stderr)}`;
          this.deps.notify(`run-day: ${why}. Events are not reaching this session.`, "warning");
          // changes-since logs its own service_down; only its timeout is invisible to it
          if (ran.code === 124 || /timed? ?out/i.test(ran.stderr)) this.deps.friction("timeout", why, "changes-since");
        }
        this.failed = true;
        return;
      }
      if (this.failed) this.deps.notify("run-day: changes-since is working again", "info");
      this.failed = false;

      const p = this.deps.paths();
      const items = parseItems(readOr(p.diary));
      const runs = parseRunState(readOr(p.runState));
      const ctx = {
        mrKeys: new Set([
          ...items.flatMap((i) => mrKeysOf(i.line)),
          ...runs.flatMap((r) => r.mrs.map(mrKeyFromRef)).filter((k) => k !== ""),
        ]),
        ticketKeys: new Set(items.map((i) => ticketKey(i.text)).filter((k) => k !== "")),
      };
      const prompts: string[] = [];
      for (const ev of parseEvents(ran.stdout).events) {
        try {
          if (classify(ev, ctx) === "prompt") prompts.push(formatPrompt(ev));
          else this.deps.note(formatNote(ev));
        } catch {
          // one malformed event never costs the others
        }
      }
      if (prompts.length > 0) this.deps.wake(prompts.join("\n"));
    } catch (err) {
      if (!this.failed) {
        const why = err instanceof Error ? err.message : String(err);
        this.deps.notify(`run-day watcher: ${why}`, "warning");
        this.deps.friction(/timed? ?out/i.test(why) ? "timeout" : "tool_error", `daily watcher: ${why}`, "changes-since");
      }
      this.failed = true;
    } finally {
      this.checking = false;
    }
  }

  checkInbox(): void {
    if (!this.active()) return;
    const { fresh, state } = nextInbox(this.deps.listInbox(), this.seen);
    this.seen = state.seen;
    if (fresh.length > 0) this.deps.wake(inboxPrompt(fresh.length));
  }
}

type Holder = { pid: number; session: string };

function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return (err as NodeJS.ErrnoException).code === "EPERM";
  }
}

/** Take the watch lock; returns why not, or null when this session holds it now. */
export function acquireLock(path: string, me: Holder): string | null {
  try {
    const held = JSON.parse(readFileSync(path, "utf8")) as Holder;
    if (held.pid !== me.pid && alive(held.pid)) {
      return `pi session ${held.session} (pid ${held.pid}) is already watching this day`;
    }
  } catch {
    // no lock, or an unreadable one: take it
  }
  writeFileSync(path, `${JSON.stringify({ ...me, started: new Date().toISOString() })}\n`);
  return null;
}

export function releaseLock(path: string, pid: number): void {
  try {
    const held = JSON.parse(readFileSync(path, "utf8")) as Holder;
    if (held.pid === pid) rmSync(path, { force: true });
  } catch {
    // nothing to release
  }
}
