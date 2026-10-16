import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
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

const MAX_CHARS = 6000;
const BLOCK_MAX = 3000;

type Paths = {
  stateDir: string;
  runState: string;
  diary: string;
  inbox: string;
  today: string;
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
  };
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
    `Write rules: subagents never write ~/wiki; only this session writes diary markers, ~/wiki/work/projects/<p>/log entries and decisions; /end-day consolidates state.md.\n` +
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

export default function daily(pi: ExtensionAPI) {
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
    // Omitting the key on a later turn is what removes it: pi diffs sections by name.
    if (section) event.systemPromptOptions.sections.daily_run_state = section;

    let directions: string | null = null;
    try {
      directions = directionsSection();
    } catch {
      directions = null;
    }
    if (directions) event.systemPromptOptions.sections.standing_directions = directions;
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
