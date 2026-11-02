import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { blockReason } from "./guard.ts";

// pi's file tools stay out of ~/.secrets. Bash goes through claude-hooks, which
// runs the same bin/secrets-guard hook Claude Code does.
export default function secretsGuard(pi: ExtensionAPI) {
  pi.on("tool_call", (event) => {
    const reason = blockReason(event.toolName, event.input as Record<string, unknown>);
    if (reason) return { block: true, reason };
  });
}
