// When "the system" session (the parallel session that improves the setup) gets an idle nudge to
// review ideas from ~/wiki/IDEA.md. `/daily:system` (pi: `/system`) marks the session by writing
// its id to `<stateHome>/ideas/system.session`; only that session is ever nudged. Harness-free:
// the Claude mod and pi's daily extension both use it.

export const IDLE_MS = 15 * 60 * 1000
// Claude runs the plugin command itself (it allows model invocation); pi cannot run a prompt
// template, so its nudge points at the template file to follow.
export const NUDGE_TEXT = '[ideas] idle review: run /daily:ideas'
export const PI_NUDGE_TEXT = '[ideas] idle review: read ~/.pi/agent/prompts/ideas.md and follow it (the /ideas prompt)'

const SYSTEM = new Set(['system', 'daily:system'])
const SLASH = /^\s*\/(\S+)(?:\s+[\s\S]*)?$/

export function systemMarkerPath(stateHome: string): string {
  return `${stateHome}/ideas/system.session`
}

export function claimsSystem(command: string): boolean {
  return SYSTEM.has(command)
}

export function claimsSystemPrompt(text: string): boolean {
  const m = SLASH.exec(text)
  return m !== null && claimsSystem(m[1])
}

export type IdleState = {
  isSystem: boolean
  now: number
  lastUserAt: number
  lastTurnEndAt: number
  agentsRunning: number
  // a round was sent and the user has not written since
  waiting: boolean
}

export function shouldNudge(s: IdleState): boolean {
  if (!s.isSystem || s.waiting || s.agentsRunning > 0) return false
  return s.now - Math.max(s.lastUserAt, s.lastTurnEndAt) >= IDLE_MS
}
