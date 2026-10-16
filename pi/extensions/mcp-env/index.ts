import { getAgentDir, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { expandServers, type Skipped } from "./src/expand.ts";
import { readSecrets } from "./src/secrets.ts";

// Registers the servers in ~/.pi/agent/mcp-servers.json (pi/mcp-servers.json)
// with ${VAR} expanded everywhere; see src/expand.ts for why. Not mcp.json: a
// server there would take precedence over the one registered here.
export default function (pi: ExtensionAPI) {
  // Subagents run fixed tool allowlists, so MCP would only slow them down.
  if (process.env.PI_SUBAGENT) return;
  const path = join(getAgentDir(), "mcp-servers.json");
  if (!existsSync(path)) return;

  const { servers, skipped } = expandServers(JSON.parse(readFileSync(path, "utf8")), {
    ...readSecrets(process.env.SECRETS_FILE ?? join(homedir(), ".secrets", "secrets.env")),
    ...process.env,
  });
  for (const { name, config } of servers) pi.registerMcpServer(name, config as Parameters<ExtensionAPI["registerMcpServer"]>[1]);

  if (!skipped.length) return;
  pi.on("session_start", (_event, ctx) => {
    if (ctx.hasUI) ctx.ui.notify(skippedNote(skipped), "warning");
  });
}

function skippedNote(skipped: readonly Skipped[]): string {
  const lines = skipped.map((s) => `${s.name}: ${s.missing.join(", ")} not set`);
  return `MCP servers left out, set them in ~/.secrets/secrets.env (run "secrets") and restart pi:\n${lines.join("\n")}`;
}
