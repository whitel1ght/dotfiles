import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"
import { buildSessionContext, convertToLlm } from "@earendil-works/pi-coding-agent"
import { digest, type DigestMessage } from "../recap/digest.ts"
import { localDate, runDayOwner, save, skipReason, SYSTEM_PROMPT } from "./summary.ts"

const MAX_TOKENS = 800
// Quitting waits for this handler, so it gets a hard ceiling.
const TIMEOUT_MS = 20_000

export default function (pi: ExtensionAPI) {
  pi.on("session_shutdown", async (event, ctx) => {
    const sm = ctx.sessionManager
    const messages = buildSessionContext(sm.getEntries(), sm.getLeafId()).messages
    const skip = skipReason({
      reason: event.reason,
      subagent: !!process.env.PI_SUBAGENT,
      sessionFile: sm.getSessionFile(),
      sessionId: sm.getSessionId(),
      runDayOwner: runDayOwner(localDate(new Date())),
      userMessages: messages.filter((m) => m.role === "user").length,
    })
    const model = ctx.model
    if (skip || !model) return

    const auth = await ctx.modelRegistry.getProviderAuth(model.provider)
    if (!auth?.auth.apiKey) return

    try {
      if (ctx.hasUI) ctx.ui.notify("Writing session summary…", "info")
      const response = await ctx.modelRegistry.complete(
        model,
        {
          systemPrompt: SYSTEM_PROMPT,
          messages: [
            {
              role: "user",
              content: [{ type: "text", text: digest(convertToLlm(messages) as DigestMessage[]) }],
              timestamp: Date.now(),
            },
          ],
        },
        { maxTokens: MAX_TOKENS, maxRetries: 0, cacheRetention: "none", timeoutMs: TIMEOUT_MS },
      )
      const body = response.content
        .filter((c): c is { type: "text"; text: string } => c.type === "text")
        .map((c) => c.text)
        .join("\n")
      if (response.stopReason !== "stop" || !body.trim()) return
      save(
        {
          sessionId: sm.getSessionId(),
          cwd: sm.getCwd(),
          model: `${model.provider}/${model.id}`,
          sessionFile: sm.getSessionFile()!,
          ended: new Date(),
        },
        body,
      )
    } catch {
      // A summary is a convenience; never let it stop pi from quitting.
    }
  })
}
