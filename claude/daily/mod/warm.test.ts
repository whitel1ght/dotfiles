import { test, expect } from 'claude-code/testing'
import { DAY_WARM_AFTER_MS, isWarm, nextWarm, pingFailure, PING_AFTER_MS, TTL_MS } from './warm.ts'
import type { WarmInput } from './warm.ts'

const MIN = 60_000
const HOUR = 60 * MIN
const T0 = 1_000_000_000
const at = (over: Partial<WarmInput>): WarmInput => ({ isOwner: true, dayEnded: false, startedAt: T0, lastRequestAt: T0 + 6 * HOUR, now: T0 + 6 * HOUR, ...over })

test('the constants match cache-tax: 6 h window, 50 min ping, 1 h TTL', async () => {
  expect([DAY_WARM_AFTER_MS, PING_AFTER_MS, TTL_MS]).toEqual([6 * HOUR, 50 * MIN, HOUR])
})

test('no ping before 6 h: a turn at 4 h waits on cache-tax, a turn at 5:30 waits for the 6 h mark', async () => {
  expect(nextWarm(at({ lastRequestAt: T0 + 4 * HOUR, now: T0 + 4 * HOUR + 10 * MIN }))).toEqual({ do: 'idle' })
  expect(nextWarm(at({ lastRequestAt: T0 + 5 * HOUR + 30 * MIN, now: T0 + 5 * HOUR + 31 * MIN }))).toEqual({ do: 'wait', ms: 49 * MIN })
})

test('after 6 h it waits for 50 idle minutes, then pings', async () => {
  const last = T0 + 7 * HOUR
  expect(nextWarm(at({ lastRequestAt: last, now: last }))).toEqual({ do: 'wait', ms: 50 * MIN })
  expect(nextWarm(at({ lastRequestAt: last, now: last + 50 * MIN }))).toEqual({ do: 'ping' })
  expect(nextWarm(at({ lastRequestAt: last, now: last + 59 * MIN }))).toEqual({ do: 'ping' })
})

test("the hand-over starts from cache-tax's last warm ping: one at 5:40 makes the first daily ping 6:30", async () => {
  const ping = T0 + 5 * HOUR + 40 * MIN
  expect(nextWarm(at({ lastRequestAt: ping, now: ping }))).toEqual({ do: 'wait', ms: 50 * MIN })
  expect(nextWarm(at({ lastRequestAt: ping, now: T0 + 6 * HOUR + 30 * MIN }))).toEqual({ do: 'ping' })
})

test('a non-owner session is idle, whatever the clock says', async () => {
  expect(nextWarm(at({ isOwner: false, now: T0 + 7 * HOUR }))).toEqual({ do: 'idle' })
  expect(nextWarm(at({ isOwner: false, dayEnded: true }))).toEqual({ do: 'idle' })
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
