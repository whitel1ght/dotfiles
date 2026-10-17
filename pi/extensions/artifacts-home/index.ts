import { existsSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { ensureLink } from "./home.ts";

// pi-artifacts' `artifact` tool writes to <cwd>/.pi/artifacts; point that at ~/artifacts first.
// A project that already has a real folder is moved over at session start; any other project is
// linked only when it first makes an artifact, so pi sessions elsewhere leave no .pi folder.
export default function artifactsHome(pi: ExtensionAPI) {
  const store = process.env.ARTIFACTS_DIR;
  const link = (ctx: { ui?: { notify?: (m: string, t?: "info" | "warning" | "error") => void } }) => {
    try {
      const r = ensureLink(process.cwd(), store);
      if (r.action === "linked" && r.moved.length) ctx.ui?.notify?.(`artifacts: moved ${r.moved.length} file(s) to ${r.target}`, "info");
      if (r.action === "skipped" && r.reason && !r.reason.includes("inside the artifacts store")) {
        ctx.ui?.notify?.(`artifacts stay in .pi/artifacts: ${r.reason}`, "warning");
      }
    } catch (err) {
      ctx.ui?.notify?.(`artifacts link failed: ${err instanceof Error ? err.message : String(err)}`, "warning");
    }
  };
  pi.on("session_start", (_e, ctx) => {
    if (existsSync(join(process.cwd(), ".pi", "artifacts"))) link(ctx as never);
  });
  pi.on("tool_call", (event, ctx) => {
    if (event.toolName === "artifact") link(ctx as never);
  });
}
