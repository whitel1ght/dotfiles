// Backstop for the day session going idle with work left (2026-10-29: it reported "what's left is
// yours" with three reviews on the plan). After BUSY_IDLE_MS with no agent outstanding or running,
// the owner session gets one prompt to run Keep busy (playbook section 11: queued items, then the
// sprint). One per idle stretch: the next waits until an agent was outstanding or the user wrote.
// Harness-free: the Claude mod and pi's daily extension both use it.

export const BUSY_IDLE_MS = 10 * 60 * 1000
export const BUSY_PROMPT = '[daily-idle] no agent running: run Keep busy of /daily:run-day (section 11).'
export const PI_BUSY_PROMPT = '[daily-idle] no agent running: run Keep busy of /run-day (section 11).'

export type BusyState = {
  isOwner: boolean
  // today's run state exists and the day has no report yet
  dayRunning: boolean
  now: number
  // latest of: the user's last prompt, the last turn's end, the last request of a turn in progress
  lastActiveAt: number
  // owner=main items with agent= or round= set
  outstanding: number
  agentsRunning: number
  nudged: boolean
}

export function shouldNudgeBusy(s: BusyState): boolean {
  if (!s.isOwner || !s.dayRunning || s.nudged) return false
  if (s.outstanding > 0 || s.agentsRunning > 0) return false
  return s.now - s.lastActiveAt >= BUSY_IDLE_MS
}

export function nextNudged(nudged: boolean, seen: { outstanding: number; userWrote: boolean }): boolean {
  return nudged && seen.outstanding === 0 && !seen.userWrote
}
