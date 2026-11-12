import { test, expect } from 'claude-code/testing'
import { BUSY_IDLE_MS, BUSY_PROMPT, PI_BUSY_PROMPT, nextAgentAt, nextNudged, shouldNudgeBusy } from './busy.ts'

const base = { isOwner: true, dayRunning: true, now: 10 * BUSY_IDLE_MS, lastAgentAt: 1, outstanding: 0, agentsRunning: 0, nudged: false }

test('a day session with no agent for the whole window is nudged', async () => {
  expect(shouldNudgeBusy(base)).toBe(true)
})

test('not before the whole window has passed with no agent', async () => {
  expect(shouldNudgeBusy({ ...base, lastAgentAt: base.now - BUSY_IDLE_MS + 1 })).toBe(false)
  expect(shouldNudgeBusy({ ...base, lastAgentAt: base.now - BUSY_IDLE_MS })).toBe(true)
})

test('the clock restarts only on an agent, so the user chatting does not hold the nudge back', async () => {
  expect(nextAgentAt(0, 500, 0)).toBe(500)
  expect(nextAgentAt(300, 500, 0)).toBe(300)
  expect(nextAgentAt(300, 500, 2)).toBe(500)
})

test('never outside the owner session or a running day', async () => {
  expect(shouldNudgeBusy({ ...base, isOwner: false })).toBe(false)
  expect(shouldNudgeBusy({ ...base, dayRunning: false })).toBe(false)
})

test('never while an agent is outstanding or running', async () => {
  expect(shouldNudgeBusy({ ...base, outstanding: 1 })).toBe(false)
  expect(shouldNudgeBusy({ ...base, agentsRunning: 1 })).toBe(false)
})

test('once per idle stretch', async () => {
  expect(shouldNudgeBusy({ ...base, nudged: true })).toBe(false)
})

test('a stretch ends when an agent is outstanding or the user writes', async () => {
  expect(nextNudged(true, { outstanding: 1, userWrote: false })).toBe(false)
  expect(nextNudged(true, { outstanding: 0, userWrote: true })).toBe(false)
  expect(nextNudged(true, { outstanding: 0, userWrote: false })).toBe(true)
  expect(nextNudged(false, { outstanding: 0, userWrote: false })).toBe(false)
})

test('the prompts name the Keep busy section of each playbook', async () => {
  expect(BUSY_PROMPT).toBe('[daily-idle] no agent running: run Keep busy of /daily:run-day (section 11).')
  expect(PI_BUSY_PROMPT).toBe('[daily-idle] no agent running: run Keep busy of /run-day (section 11).')
})
