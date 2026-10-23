// Keeps the day session's prompt cache warm after cache-tax's `keepwarm always` window (its first
// 6 h) ends: same ping period, TTL, prompt and warm test as cache-tax, so the two never ping in
// the same window. Claude only.

export const DAY_WARM_AFTER_MS = 6 * 60 * 60 * 1000
export const PING_AFTER_MS = 50 * 60 * 1000
export const TTL_MS = 60 * 60 * 1000
export const WARM_PROMPT = 'Reply with the single word: warm'
export const REPORT_MARK = '<!-- daily-report:start -->'

export type WarmInput = {
  /** This session owns today's day (the owner file is dated, so it turns false at midnight). */
  isOwner: boolean
  /** Today's diary has the end-of-day report. */
  dayEnded: boolean
  startedAt: number
  /** The main thread's last request, or a warm ping's; null before the first. */
  lastRequestAt: number | null
  now: number
}

/**
 * ping: send one now. wait: check again in `ms`. idle: nothing until the next turn or ping.
 * cold: the cache already lapsed, nothing until the next turn. stop: never again this session.
 */
export type WarmStep =
  | { do: 'ping' }
  | { do: 'wait'; ms: number }
  | { do: 'idle' }
  | { do: 'cold' }
  | { do: 'stop'; why: string }

export function nextWarm(i: WarmInput): WarmStep {
  if (!i.isOwner) return { do: 'idle' }
  if (i.dayEnded) return { do: 'stop', why: "today's report is written" }
  if (i.lastRequestAt === null) return { do: 'idle' }
  const coldAt = i.lastRequestAt + TTL_MS
  if (i.now >= coldAt) return { do: 'cold' }
  const due = Math.max(i.startedAt + DAY_WARM_AFTER_MS, i.lastRequestAt + PING_AFTER_MS)
  if (due >= coldAt) return { do: 'idle' }
  return i.now >= due ? { do: 'ping' } : { do: 'wait', ms: due - i.now }
}

export type ForkUsage = { cache_read_input_tokens: number; cache_creation_input_tokens: number }

// A warm ping reads the prefix and writes only its own message (cache-tax's test).
export function isWarm(u: ForkUsage): boolean {
  return u.cache_read_input_tokens > 0 && u.cache_creation_input_tokens < 0.1 * u.cache_read_input_tokens
}

type Reply =
  | { isAnswered: true; usage: ForkUsage }
  | { isAnswered: false; reason: string; status?: number | null }
  | null
  | undefined

/** Why the ping did not keep the cache warm, or null when it did. */
export function pingFailure(reply: Reply): string | null {
  if (!reply) return 'the engine did not send the ping'
  if (!reply.isAnswered) {
    if (reply.reason === 'api-error') return `the API call failed${reply.status == null ? '' : ` (${reply.status})`}`
    return `the ping got no reply (${reply.reason})`
  }
  const u = reply.usage
  return isWarm(u) ? null : `the ping read ${u.cache_read_input_tokens} and wrote ${u.cache_creation_input_tokens} tokens: the cache was already gone`
}
