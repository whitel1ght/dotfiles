import { test, expect } from 'claude-code/testing'
import { isWarm, nextWarm, pingFailure, PING_AFTER_MS, TRAIL_MS, TTL_MS } from './warm.ts'
import type { WarmInput } from './warm.ts'

const MIN = 60_000
const HOUR = 60 * MIN
const T0 = 1_000_000_000
const at = (over: Partial<WarmInput>): WarmInput => ({ dayRunning: true, dayEnded: false, lastRequestAt: T0, now: T0, ...over })

test("the constants: cache-tax's 50 min ping and 1 h TTL, trailed by 5 min", async () => {
  expect([PING_AFTER_MS, TRAIL_MS, TTL_MS]).toEqual([50 * MIN, 5 * MIN, HOUR])
})

test("it waits 55 idle minutes, after cache-tax's 50, then pings while the cache is still warm", async () => {
  expect(nextWarm(at({}))).toEqual({ do: 'wait', ms: 55 * MIN })
  expect(nextWarm(at({ now: T0 + 50 * MIN }))).toEqual({ do: 'wait', ms: 5 * MIN })
  expect(nextWarm(at({ now: T0 + 55 * MIN }))).toEqual({ do: 'ping' })
  expect(nextWarm(at({ now: T0 + 59 * MIN }))).toEqual({ do: 'ping' })
})

test("a warm ping from cache-tax at 50 min moves the clock: the next daily ping is 55 min after it", async () => {
  const ping = T0 + 50 * MIN
  expect(nextWarm(at({ lastRequestAt: ping, now: ping }))).toEqual({ do: 'wait', ms: 55 * MIN })
})

test('with no run state for today it is idle, whatever the clock says', async () => {
  expect(nextWarm(at({ dayRunning: false, now: T0 + 7 * HOUR }))).toEqual({ do: 'idle' })
  expect(nextWarm(at({ dayRunning: false, dayEnded: true }))).toEqual({ do: 'idle' })
})

test('no request yet is idle', async () => {
  expect(nextWarm(at({ lastRequestAt: null, now: T0 + 8 * HOUR }))).toEqual({ do: 'idle' })
})

test('a cold cache is never pinged: a timer that wakes after sleep finds it cold', async () => {
  const last = T0 + 7 * HOUR
  expect(nextWarm(at({ lastRequestAt: last, now: last + TTL_MS }))).toEqual({ do: 'cold' })
  expect(nextWarm(at({ lastRequestAt: last, now: last + 3 * HOUR }))).toEqual({ do: 'cold' })
})

test('the daily report ends it for good', async () => {
  expect(nextWarm(at({ dayEnded: true, now: T0 + 7 * HOUR }))).toEqual({ do: 'stop', why: "today's report is written" })
})

test("isWarm is cache-tax's test: a read, and a write under a tenth of it", async () => {
  expect(isWarm({ cache_read_input_tokens: 80_000, cache_creation_input_tokens: 40 })).toBe(true)
  expect(isWarm({ cache_read_input_tokens: 80_000, cache_creation_input_tokens: 8_000 })).toBe(false)
  expect(isWarm({ cache_read_input_tokens: 0, cache_creation_input_tokens: 0 })).toBe(false)
})

test('pingFailure says why a reply did not keep the cache warm', async () => {
  expect(pingFailure({ isAnswered: true, usage: { cache_read_input_tokens: 80_000, cache_creation_input_tokens: 40 } })).toBe(null)
  expect(pingFailure({ isAnswered: true, usage: { cache_read_input_tokens: 0, cache_creation_input_tokens: 80_000 } })).toContain('the cache was already gone')
  expect(pingFailure({ isAnswered: false, reason: 'api-error', status: 529 })).toBe('the API call failed (529)')
  expect(pingFailure({ isAnswered: false, reason: 'nothing-to-fork' })).toBe('the ping got no reply (nothing-to-fork)')
  expect(pingFailure(null)).toBe('the engine did not send the ping')
})
