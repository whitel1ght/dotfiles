import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"
import { execFileSync } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

// Learning sessions (D-1288): /learn-mark and /learn-save keep this session in full in
// ~/wiki/learning/sessions/ through bin/session-save; a marked session saves again on quit.
// Quitting waits for session_shutdown, so every call gets a hard ceiling.
const TIMEOUT_MS = 10_000

type Ctx = {
  hasUI?: boolean
  ui?: { notify(msg: string, level: string): void }
  sessionManager: { getSessionId(): string; getSessionFile(): string | undefined }
}

function run(args: string[]): string {
  const bin = process.env.SESSION_SAVE_BIN || join(homedir(), ".local/bin/session-save")
  return execFileSync(bin, args, { encoding: "utf8", timeout: TIMEOUT_MS, stdio: ["ignore", "pipe", "pipe"] }).trim()
}

function notify(ctx: Ctx, msg: string, level = "info") {
  if (ctx.hasUI) ctx.ui?.notify(msg, level)
}

function save(ctx: Ctx, title?: string): string {
  const sm = ctx.sessionManager
  const args = ["save", "--harness", "pi", "--session", sm.getSessionId(), "--transcript", sm.getSessionFile() ?? ""]
  if (title) args.push("--title", title)
  return run(args)
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("learn-mark", {
    description: "Mark this session as a learning one: it is saved to ~/wiki/learning/sessions/ when it closes",
    handler: async (_args: string, ctx: Ctx) => {
      try {
        run(["mark", "--harness", "pi", ctx.sessionManager.getSessionId()])
        notify(ctx, "Marked: this session saves to ~/wiki/learning/sessions/ when it closes.")
      } catch (e) {
        notify(ctx, `learn-mark failed: ${(e as Error).message}`, "error")
      }
    },
  })

  pi.registerCommand("learn-save", {
    description: "Save this session to ~/wiki/learning/sessions/ now (and again when it closes); optional title",
    handler: async (args: string, ctx: Ctx) => {
      try {
        run(["mark", "--harness", "pi", ctx.sessionManager.getSessionId()])
        const path = save(ctx, args?.trim() || undefined)
        notify(ctx, path ? `Saved: ${path}` : "Nothing to save yet: no message of yours in this session.")
      } catch (e) {
        notify(ctx, `learn-save failed: ${(e as Error).message}`, "error")
      }
    },
  })

  pi.on("session_shutdown", async (_event: unknown, ctx: Ctx) => {
    if (process.env.PI_SUBAGENT) return
    try {
      run(["is-marked", ctx.sessionManager.getSessionId()])
    } catch {
      return
    }
    try {
      save(ctx)
    } catch (e) {
      notify(ctx, `learning session not saved: ${(e as Error).message}`, "error")
    }
  })
}
