// pi's half of the decisions-deck backstops (claude/daily/mod/ask.ts holds the shared rules):
// pi's question form is blocked, input sent while a run or pi-sub agents are going gets a hidden
// note to file the answer with tell_user, and a run that ends asking with no card filed is nudged
// once per user message.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { ASK_NUDGE, BUSY_NOTE, FORM_DENY, FORM_TOOLS, isBusyPrompt, nextAsk, shouldNudgeAsk } from "./mod/ask.ts";

// This session's pi-sub agents still running: a meta.json it owns and no exit.json yet (the layout
// of pi/extensions/pi-sub/state.ts, read here rather than imported across extensions).
export function piSubRunning(session: string, dir = process.env.PI_SUB_STATE_DIR ?? join(homedir(), ".local/state/pi-sub")): number {
  if (!session || !existsSync(dir)) return 0;
  let n = 0;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (!e.isDirectory() || existsSync(join(dir, e.name, "exit.json"))) continue;
    try {
      if (JSON.parse(readFileSync(join(dir, e.name, "meta.json"), "utf8")).owner_session === session) n++;
    } catch {
      // a missing or half-written meta.json is not this session's agent
    }
  }
  return n;
}

export type AskDeps = {
  agentsRunning: () => number;
  // a hidden message for the model beside the user's input
  note: (text: string) => void;
  nudge: (text: string) => void;
};

type Message = { role?: string; content?: unknown };

function lastAssistantText(messages: readonly Message[]): string {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m.role !== "assistant") continue;
    if (typeof m.content === "string") return m.content;
    if (!Array.isArray(m.content)) return "";
    return m.content
      .filter((c): c is { type: "text"; text: string } => c?.type === "text" && typeof c.text === "string")
      .map((c) => c.text)
      .join("\n");
  }
  return "";
}

export class AskBackstop {
  private state = { asked: false, nudged: false };
  private deps: AskDeps;

  constructor(deps: AskDeps) {
    this.deps = deps;
  }

  onInput(source: string, streamingBehavior: string | undefined) {
    if (source === "extension") return;
    this.state = nextAsk(this.state, "user");
    if (isBusyPrompt({ inTurn: streamingBehavior !== undefined, agentsRunning: this.deps.agentsRunning() })) {
      this.deps.note(BUSY_NOTE);
    }
  }

  onToolCall(toolName: string): { block: true; reason: string } | undefined {
    if ((FORM_TOOLS as readonly string[]).includes(toolName)) return { block: true, reason: FORM_DENY };
    this.state = nextAsk(this.state, "tool", toolName);
    return undefined;
  }

  onAgentEnd(messages: readonly Message[]) {
    const text = lastAssistantText(messages);
    if (!shouldNudgeAsk({ isMain: true, reason: "answer", text, ...this.state })) return;
    this.state = nextAsk(this.state, "nudged");
    this.deps.nudge(ASK_NUDGE);
  }
}
