import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { check, loadHooks, type Hook } from "./hooks.ts";

export default function claudeHooks(pi: ExtensionAPI) {
  let hooks: Hook[] = [];
  pi.on("session_start", () => {
    hooks = loadHooks();
  });
  pi.on("tool_call", (event, ctx) => {
    if (event.toolName !== "bash" || hooks.length === 0) return;
    const command = String((event.input as { command?: unknown }).command ?? "");
    const v = check(hooks, command, ctx.cwd, ctx.sessionManager.getSessionId());
    if (v.block) return { block: true, reason: v.reason };
  });
}
