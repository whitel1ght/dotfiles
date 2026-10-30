// pi's half of answer-card follow-ups (claude/daily/mod/followup.ts holds the shared rules): the
// user's follow-ups on this session's answer cards come back as a message that starts a turn, once
// each per process.
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { followupPrompt, parseCards, pendingFollowups } from "./mod/followup.ts";

// The id the decisions MCP server stamps on this session's cards. mcp-env registers it as a stdio
// child of this process, with this process's env under the server's own (DECISIONS_WAIT only).
export function decisionsSession(env: NodeJS.ProcessEnv = process.env, pid = process.pid): string {
  return env.DECISIONS_OWNER || env.CLAUDE_CODE_SESSION_ID || `pid:${pid}`;
}

/** `decide list --json`; any failure is "". */
export function decideList(): Promise<string> {
  return new Promise((resolve) => {
    const bin = existsSync(join(homedir(), ".local/bin/decide")) ? join(homedir(), ".local/bin/decide") : "decide";
    execFile(bin, ["list", "--json"], { timeout: 10_000 }, (err, stdout) => resolve(err ? "" : String(stdout)));
  });
}

export type FollowupDeps = {
  list: () => Promise<string>;
  session: string;
  send: (text: string) => void;
};

export class FollowupDelivery {
  private delivered = new Map<string, number>();
  private isChecking = false;
  private deps: FollowupDeps;

  constructor(deps: FollowupDeps) {
    this.deps = deps;
  }

  async tick() {
    if (this.isChecking) return;
    this.isChecking = true;
    try {
      const due = pendingFollowups(parseCards(await this.deps.list()), this.deps.session, this.delivered);
      if (due.length === 0) return;
      for (const c of due) this.delivered.set(c.id, c.discussion_count);
      this.deps.send(followupPrompt(due));
    } finally {
      this.isChecking = false;
    }
  }
}
