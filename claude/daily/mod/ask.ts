// Every session's questions go to the decisions deck, and an answer to a question the user sent
// while the session was busy goes there too (2026-10-29: only the day session used the deck, and
// late answers had to be found by scrolling). claude/CLAUDE.md "Questions" is the rule; these are
// its backstops: the question form is refused, a prompt typed while busy carries a note to file
// the answer with tell_user, and a main turn that ends asking with no card filed is nudged once.
// Harness-free: the Claude mod and pi's daily extension both use it.

// pi names MCP tools as Claude Code does: mcp__<server>__<tool>.
export const ASK_USER = 'mcp__decisions__ask_user'
export const TELL_USER = 'mcp__decisions__tell_user'
// Claude Code's question popup, and pi's (@juicesharp/rpiv-ask-user-question).
export const FORM_TOOLS = ['AskUserQuestion', 'ask_user_question'] as const

export const FORM_DENY =
  'Questions go to the decisions deck, not the question form: call ask_user (decisions MCP; in Claude Code load it first with ToolSearch select:mcp__decisions__ask_user,mcp__decisions__wait_for_answer), then say one line in the chat: "asked in decisions: D-<n>". If the decisions tools are not there, ask in the chat.'

export const BUSY_NOTE =
  '[decisions] The user sent this while you were busy (a turn or agents still running). When you answer it, give the answer in the chat and also file it with tell_user (decisions MCP; in Claude Code load it with ToolSearch select:mcp__decisions__tell_user), so it waits for them in the deck.'

export const ASK_NUDGE =
  '[decisions] Your last message asks the user something, but no card is open for it. File it with ask_user (decisions MCP; in Claude Code load it with ToolSearch select:mcp__decisions__ask_user,mcp__decisions__wait_for_answer), then say one line: "asked in decisions: D-<n>". If it needs no answer, or the decisions tools are not there, carry on.'

export function isBusyPrompt(s: { inTurn: boolean; agentsRunning: number }): boolean {
  return s.inTurn || s.agentsRunning > 0
}

// The last line of prose, outside code fences, ends with a question mark (markdown and closing
// brackets around it aside).
export function endsWithQuestion(text: string): boolean {
  let fenced = false
  let last = ''
  for (const line of text.split('\n')) {
    if (/^\s*(```|~~~)/.test(line)) {
      fenced = !fenced
      continue
    }
    if (!fenced && line.trim() !== '') last = line.trim()
  }
  return /\?[*_`)\]"'»”\s]*$/.test(last)
}

export type AskTurn = {
  // the main thread, not a subagent
  isMain: boolean
  reason: string
  // the turn's final text
  text: string
  // ask_user was called since the user last wrote
  asked: boolean
  // already nudged since the user last wrote
  nudged: boolean
}

export function shouldNudgeAsk(t: AskTurn): boolean {
  return t.isMain && t.reason === 'answer' && !t.asked && !t.nudged && endsWithQuestion(t.text)
}

export type AskState = { asked: boolean; nudged: boolean }

export function nextAsk(s: AskState, what: 'user' | 'tool' | 'nudged', tool = ''): AskState {
  if (what === 'user') return { asked: false, nudged: false }
  if (what === 'nudged') return { ...s, nudged: true }
  return tool === ASK_USER ? { ...s, asked: true } : s
}
