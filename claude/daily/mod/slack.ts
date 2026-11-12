// Slack messages arrive and get sent all day, but /start-day reads Slack once in the morning, so a
// plan line like "send the draft in Dave's DM (you)" stayed open after it went out, and a DM that
// came in at 16:00 reached no plan (2026-11-11, D-753). From 15:00 local time the owner session
// gets a [daily-slack] prompt every 20 min, 10 checks (15:00 to 18:00), between turns, to run
// /daily:slack-check. A slot missed while the Mac slept or a turn ran fires once, as the latest
// due slot. The last slot sent is kept in <date>.slack, so a reloaded mod does not send it again.
// Harness-free: the Claude mod and pi's daily extension both use it.

export const SLACK_START_MIN = 15 * 60
export const SLACK_EVERY_MIN = 20
export const SLACK_CHECKS = 10

const prompt = (cmd: string, slot: number) => `[daily-slack] check ${slot + 1}/${SLACK_CHECKS}: run ${cmd}.`
export const slackPrompt = (slot: number) => prompt('/daily:slack-check', slot)
export const piSlackPrompt = (slot: number) => prompt('/slack-check', slot)

export const slackPath = (stateDir: string, day: string) => `${stateDir}/${day}.slack`

// minutes since local midnight → the slot due now (0-based), or null outside 15:00-18:19
export function dueSlot(localMinutes: number): number | null {
  if (localMinutes < SLACK_START_MIN) return null
  const slot = Math.floor((localMinutes - SLACK_START_MIN) / SLACK_EVERY_MIN)
  return slot < SLACK_CHECKS ? slot : null
}

// "HH:MM" (date +%H:%M) → minutes since local midnight
export function parseClock(text: string): number | null {
  const m = /^\s*(\d{1,2}):(\d{2})\s*$/.exec(text)
  return m ? Number(m[1]) * 60 + Number(m[2]) : null
}

// the last slot sent, -1 when none (a missing or unreadable file)
export function parseSlot(text: string | null): number {
  const m = /^slot=(\d+)$/m.exec(text ?? '')
  return m ? Number(m[1]) : -1
}

export const formatSlot = (slot: number) => `slot=${slot}\n`

export type SlackState = {
  isOwner: boolean
  dayRunning: boolean
  turnRunning: boolean
  localMinutes: number | null
  lastSlot: number
}

// the slot to send now, or null
export function slackDue(s: SlackState): number | null {
  if (!s.isOwner || !s.dayRunning || s.turnRunning || s.localMinutes === null) return null
  const slot = dueSlot(s.localMinutes)
  return slot !== null && slot > s.lastSlot ? slot : null
}
