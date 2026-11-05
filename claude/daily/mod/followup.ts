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
  // Opened by the user's own message from the deck's prompt line, not by an answer.
  prompt: boolean
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
      prompt: c.prompt === true,
    }))
}

// This session's open answer cards with a follow-up it has not been given yet (delivered: card
// id to the discussion_count it was delivered at). `decide list --json` lists open cards only and
// prints no status, so a missing one is open.
export function pendingFollowups(cards: readonly Card[], session: string | ReadonlySet<string>, delivered: ReadonlyMap<string, number>): Card[] {
  const mine = (id: string) => id !== '' && (typeof session === 'string' ? id === session : session.has(id))
  return cards.filter(
    c => c.kind === 'answer' && (c.status === '' || c.status === 'open') && mine(c.session) && c.followup !== '' && c.discussion_count > (delivered.get(c.id) ?? 0),
  )
}

// A mod's prompt gets no `@file` or image expansion from the harness, so the deck sends paths.
const NAMES_FILES = /(^|\s)@\S|\[image: /
const READ_FILES = ' A path after an @ is relative to your working directory (it may end in a line range such as #L10-20), and [image: …] gives an image file by its absolute path: read them with your file tool first.'

export function followupPrompt(items: readonly Card[]): string {
  return items
    .map(c => {
      const asked = c.question ? ` (their question: "${c.question}")` : ''
      const said = c.prompt && c.discussion_count <= 1
        ? `The user sent you this message from the decisions deck (card ${c.id}): "${c.followup}".`
        : `The user followed up on your answer card ${c.id}${asked}: "${c.followup}".`
      const read = NAMES_FILES.test(c.followup) ? READ_FILES : ''
      return `[decisions] ${said}${read} Do what it asks, then answer with the decisions reply tool (${REPLY}, id "${c.id}"; in Claude Code load it with ToolSearch select:${REPLY}); the reply shows on the same card. If the decisions tools are not there, answer in the chat.`
    })
    .join('\n\n')
}
