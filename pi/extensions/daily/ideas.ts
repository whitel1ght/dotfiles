// pi's half of the idle idea review (claude/daily/mod/ideas.ts holds the shared rules): typing
// /system marks this session as "the system" session, and an idle marked session gets one
// "[ideas] idle review" message per idle stretch while `ideas due` has something.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

import { PI_NUDGE_TEXT, claimsSystemPrompt, shouldNudge, systemMarkerPath } from "./mod/ideas.ts";

export type IdeasDeps = {
  now: () => number;
  stateHome: () => string;
  session: () => string;
  due: () => Promise<boolean>;
  send: (text: string) => void;
};

export class IdeasNudger {
  private lastUserAt: number;
  private lastTurnEndAt = 0;
  private waiting = false;
  private busy = false;
  private checking = false;
  private deps: IdeasDeps;

  constructor(deps: IdeasDeps) {
    this.deps = deps;
    this.lastUserAt = deps.now();
  }

  onInput(text: string, source: string) {
    if (source === "extension") return;
    this.lastUserAt = this.deps.now();
    this.waiting = false;
    if (claimsSystemPrompt(text)) this.mark();
  }

  onAgentStart() {
    this.busy = true;
  }

  onAgentEnd() {
    this.busy = false;
    this.lastTurnEndAt = this.deps.now();
  }

  private markerPath() {
    return systemMarkerPath(this.deps.stateHome());
  }

  private mark() {
    const path = this.markerPath();
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, `${this.deps.session()}\n`);
  }

  private isSystem(): boolean {
    try {
      return readFileSync(this.markerPath(), "utf8").split("\n")[0].trim() === this.deps.session();
    } catch {
      return false;
    }
  }

  async tick() {
    if (this.checking) return;
    this.checking = true;
    try {
      const idle = {
        isSystem: this.isSystem(),
        now: this.deps.now(),
        lastUserAt: this.lastUserAt,
        lastTurnEndAt: this.lastTurnEndAt,
        agentsRunning: this.busy ? 1 : 0,
        waiting: this.waiting,
      };
      if (!shouldNudge(idle) || !(await this.deps.due())) return;
      // the user may have written while `ideas due` ran
      if (this.waiting || this.lastUserAt !== idle.lastUserAt) return;
      this.waiting = true;
      this.deps.send(PI_NUDGE_TEXT);
    } finally {
      this.checking = false;
    }
  }
}
