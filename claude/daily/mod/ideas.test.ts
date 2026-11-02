import { test, expect } from 'claude-code/testing'
import { IDLE_MS, NUDGE_TEXT, PI_NUDGE_TEXT, claimsSystem, claimsSystemPrompt, shouldNudge, systemMarkerPath } from './ideas.ts'

const base = { isSystem: true, now: 10 * IDLE_MS, lastUserAt: 0, lastTurnEndAt: 0, agentsRunning: 0, waiting: false }

test('the marker sits in the ideas state folder', async () => {
  expect(systemMarkerPath('/home/t/.local/state')).toBe('/home/t/.local/state/ideas/system.session')
})

test('system under either name claims the system session', async () => {
  expect(claimsSystem('system')).toBe(true)
  expect(claimsSystem('daily:system')).toBe(true)
  expect(claimsSystemPrompt('/daily:system')).toBe(true)
  expect(claimsSystemPrompt('  /system extra words')).toBe(true)
})

test('other commands never claim it', async () => {
  expect(claimsSystem('systemd')).toBe(false)
  expect(claimsSystem('daily:system-x')).toBe(false)
  expect(claimsSystem('daily:run-day')).toBe(false)
  expect(claimsSystemPrompt('tell me about the system')).toBe(false)
})

test('an idle system session with nothing running is nudged', async () => {
  expect(shouldNudge(base)).toBe(true)
})

test('never outside the system session', async () => {
  expect(shouldNudge({ ...base, isSystem: false })).toBe(false)
})

test('not before IDLE_MS since the later of the last user message and the last turn', async () => {
  expect(shouldNudge({ ...base, lastUserAt: base.now - IDLE_MS + 1 })).toBe(false)
  expect(shouldNudge({ ...base, lastTurnEndAt: base.now - IDLE_MS + 1 })).toBe(false)
  expect(shouldNudge({ ...base, lastUserAt: base.now - IDLE_MS, lastTurnEndAt: base.now - IDLE_MS })).toBe(true)
})

test('not while agents run', async () => {
  expect(shouldNudge({ ...base, agentsRunning: 1 })).toBe(false)
})

test('not while a round waits on the user', async () => {
  expect(shouldNudge({ ...base, waiting: true })).toBe(false)
})

test('the nudge names each harness its own command', async () => {
  expect(NUDGE_TEXT).toContain('/daily:ideas')
  expect(PI_NUDGE_TEXT).toContain('/ideas')
  expect(PI_NUDGE_TEXT.includes('/daily:')).toBe(false)
})
