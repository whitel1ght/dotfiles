import { test, expect } from 'claude-code/testing'
import { BUSY_IDLE_MS, BUSY_PROMPT, PI_BUSY_PROMPT, nextNudged, shouldNudgeBusy } from './busy.ts'

const base = { isOwner: true, dayRunning: true, now: 10 * BUSY_IDLE_MS, lastActiveAt: 0, outstanding: 0, agentsRunning: 0, nudged: false }

test('an idle day session with no agent is nudged', async () => {
  expect(shouldNudgeBusy(base)).toBe(true)
})

test('not before it has been idle for the whole window', async () => {
  expect(shouldNudgeBusy({ ...base, lastActiveAt: base.now - BUSY_IDLE_MS + 1 })).toBe(false)
  expect(shouldNudgeBusy({ ...base, lastActiveAt: base.now - BUSY_IDLE_MS })).toBe(true)
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
