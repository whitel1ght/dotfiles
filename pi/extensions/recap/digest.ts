// What a recap needs is "what was I doing, where am I, what's next": the user's words,
// the assistant's visible replies, and the compaction summary. Tool output and
// thinking are most of a session's bytes and none of that, so they never go out.

type Block = { type: string; text?: string; name?: string; arguments?: Record<string, unknown> }
export type DigestMessage = { role: string; content: string | Block[] }

export const DIGEST_MAX_CHARS = 30_000
const HEAD_MAX_CHARS = 12_000
const ENTRY_MAX_CHARS = 4_000
const TOOL_CALL_MAX_CHARS = 100

const cut = (text: string, max: number) => (text.length > max ? `${text.slice(0, max - 1)}…` : text)

const textOf = (content: string | Block[]) =>
  typeof content === "string"
    ? content
    : content
        .filter((b) => b.type === "text" && b.text)
        .map((b) => b.text)
        .join("\n")

/** `→ bash: git commit -m …` — the first argument says what the call did. */
function toolLine(block: Block): string {
  const first = Object.values(block.arguments ?? {})[0]
  const arg = typeof first === "string" ? first : first === undefined ? "" : JSON.stringify(first)
  return cut(`→ ${block.name}: ${arg.replace(/\s+/g, " ")}`, TOOL_CALL_MAX_CHARS)
}

function entry(msg: DigestMessage): string | undefined {
  if (msg.role === "user") {
    const text = textOf(msg.content).trim()
    return text ? `[User]: ${text}` : undefined
  }
  if (msg.role !== "assistant" || typeof msg.content === "string") return undefined
  const parts: string[] = []
  const text = textOf(msg.content).trim()
  if (text) parts.push(`[Assistant]: ${cut(text, ENTRY_MAX_CHARS)}`)
  for (const b of msg.content) if (b.type === "toolCall") parts.push(toolLine(b))
  return parts.length ? parts.join("\n") : undefined
}

/**
 * The first entry (the goal, or the compaction summary that now holds it) plus as
 * many of the newest entries as fit in `max` characters, oldest first.
 */
export function digest(messages: DigestMessage[], max = DIGEST_MAX_CHARS): string {
  const entries = messages.map(entry).filter((e): e is string => e !== undefined)
  if (entries.length === 0) return ""
  const head = cut(entries[0], HEAD_MAX_CHARS)
  const tail: string[] = []
  let used = head.length
  for (let i = entries.length - 1; i > 0; i--) {
    const e = cut(entries[i], ENTRY_MAX_CHARS)
    if (used + e.length + 2 > max) break
    tail.unshift(e)
    used += e.length + 2
  }
  const skipped = entries.length - 1 - tail.length
  return [head, ...(skipped > 0 ? [`[… ${skipped} earlier entries omitted …]`] : []), ...tail].join("\n\n")
}
