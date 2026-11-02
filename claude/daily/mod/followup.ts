// A follow-up the user types on an answer card (filed with tell_user) goes back to the session
// that wrote it, as a prompt, and the session answers on the same card with reply. The card names
// its writer in `session`: DECISIONS_OWNER, else CLAUDE_CODE_SESSION_ID, else `pid:<parent pid>`
// (pi). `followup` is the user's last Discussion entry while it waits for the session's reply.
// Harness-free: the Claude mod and pi's daily extension both use it.

export const FOLLOWUP_MS = 15_000
export const REPLY = 'mcp__decisions__reply'

export type Card = {
  id: string
  kind: string
  status: string
  question: string
  session: string
  followup: string
  discussion_count: number
}

// `decide list --json`; anything else (an older binary, an error) is no cards.
export function parseCards(stdout: string): Card[] {
  let raw: unknown
  try {
    raw = JSON.parse(stdout)
  } catch {
    return []
  }
  if (!Array.isArray(raw)) return []
  const str = (v: unknown) => (typeof v === 'string' ? v : '')
  return raw
    .filter((c): c is Record<string, unknown> => typeof c === 'object' && c !== null)
    .map(c => ({
      id: str(c.id),
      kind: str(c.kind),
      status: str(c.status),
      question: str(c.question),
      session: str(c.session),
      followup: str(c.followup),
      discussion_count: typeof c.discussion_count === 'number' ? c.discussion_count : 0,
    }))
}

// This session's open answer cards with a follow-up it has not been given yet (delivered: card
// id to the discussion_count it was delivered at). `decide list --json` lists open cards only and
// prints no status, so a missing one is open.
export function pendingFollowups(cards: readonly Card[], sessionId: string, delivered: ReadonlyMap<string, number>): Card[] {
  if (!sessionId) return []
  return cards.filter(
    c => c.kind === 'answer' && (c.status === '' || c.status === 'open') && c.session === sessionId && c.followup !== '' && c.discussion_count > (delivered.get(c.id) ?? 0),
  )
}

export function followupPrompt(items: readonly Card[]): string {
  return items
    .map(c => {
      const asked = c.question ? ` (their question: "${c.question}")` : ''
      return `[decisions] The user followed up on your answer card ${c.id}${asked}: "${c.followup}". Do what it asks, then answer with the decisions reply tool (${REPLY}, id "${c.id}"; in Claude Code load it with ToolSearch select:${REPLY}); the reply shows on the same card. If the decisions tools are not there, answer in the chat.`
    })
    .join('\n\n')
}
