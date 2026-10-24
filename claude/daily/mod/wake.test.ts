import { test, expect } from 'claude-code/testing'
import { agentRows, formatAgents, isFullWake, outstanding, parseGraphics, parseLid, sleptBetween, STUCK_MS, stuckPrompt, stuckRows, wakePrompt } from './wake.ts'
import type { AgentRow } from './wake.ts'
import { parseRunState } from './runstate.ts'

const MIN = 60_000
const T = 1_000_000_000
const RUNS = parseRunState(
  [
    '- ecfx-1 | class=auto | agent=a1 | round=- | owner=main',
    '- ecfx-2 | class=auto | agent=- | round=r2 | owner=main',
    '- ecfx-3 | class=auto | agent=a3 | round=- | owner=external:ECFX-3',
    '- ecfx-4 | class=auto | agent=- | round=- | owner=main',
  ].join('\n'),
)
const ROWS: AgentRow[] = agentRows(RUNS, [{ id: 'a1', status: 'running' }], { a1: { ms: 20 * MIN, path: '/t/a1.jsonl' } })

test('sleptBetween is true only past the 60 s gap', async () => {
  expect(sleptBetween(T, T + 60_000)).toBe(false)
  expect(sleptBetween(T, T + 60_001)).toBe(true)
})

test('parseLid reads AppleClamshellState', async () => {
  expect(parseLid('"AppleClamshellState" = No')).toBe('open')
  expect(parseLid('"AppleClamshellState" = Yes')).toBe('closed')
  expect(parseLid('')).toBe(null)
})

test('parseGraphics looks for Graphics on the capabilities line', async () => {
  expect(parseGraphics('Current System Capabilities are: CPU Graphics Audio Network')).toBe(true)
  expect(parseGraphics('Current System Capabilities are: CPU Network')).toBe(false)
  expect(parseGraphics('')).toBe(null)
})

test('isFullWake: the display state decides, the lid only when the display state is unknown', async () => {
  expect(isFullWake('open', true)).toBe(true)
  expect(isFullWake('closed', true)).toBe(true)
  expect(isFullWake(null, true)).toBe(true)
  expect(isFullWake('open', false)).toBe(false)
  expect(isFullWake('closed', false)).toBe(false)
  expect(isFullWake(null, false)).toBe(false)
  expect(isFullWake('open', null)).toBe(true)
  expect(isFullWake('closed', null)).toBe(false)
  expect(isFullWake(null, null)).toBe(false)
})

test('outstanding keeps main-owned items with an agent or a round', async () => {
  expect(outstanding(RUNS).map(r => r.key)).toEqual(['ecfx-1', 'ecfx-2'])
})

test('agentRows makes one row per agent id, unknown when not listed', async () => {
  expect(ROWS).toEqual([
    { key: 'ecfx-1', kind: 'ticket', id: 'a1', status: 'running', quietMs: 20 * MIN, transcript: '/t/a1.jsonl' },
    { key: 'ecfx-2', kind: 'round', id: 'r2', status: 'unknown', quietMs: null, transcript: '' },
  ])
})

test('formatAgents writes a header and one line per row', async () => {
  expect(formatAgents(ROWS, T)).toBe(
    [
      `# agents ${new Date(T).toISOString()}`,
      'ecfx-1 | ticket | a1 | running | quiet=20 | /t/a1.jsonl',
      'ecfx-2 | round | r2 | unknown | quiet=- | -',
    ].join('\n'),
  )
})

test('wakePrompt names the sleep, the agents file and the Wake check', async () => {
  const p = wakePrompt(95 * MIN, ROWS, '/p/2026-10-08.agents')
  expect(p.startsWith('[daily-wake] woke after 95 min:')).toBe(true)
  expect(p).toContain('/p/2026-10-08.agents')
  expect(p).toContain('section 10')
})

test('stuckRows keeps running agents quiet for at least STUCK_MS', async () => {
  const row = (status: AgentRow['status'], quietMs: number | null): AgentRow => ({ key: 'k', kind: 'ticket', id: 'i', status, quietMs, transcript: '' })
  expect(stuckRows([row('running', STUCK_MS), row('completed', STUCK_MS), row('running', STUCK_MS - 1)])).toEqual([row('running', STUCK_MS)])
})

test('stuckPrompt starts with the stuck tag and lists key and id', async () => {
  const p = stuckPrompt([{ key: 'ecfx-1', kind: 'ticket', id: 'a1', status: 'running', quietMs: STUCK_MS, transcript: '' }], '/p/x.agents')
  expect(p.startsWith('[daily-wake] stuck:')).toBe(true)
  expect(p).toContain('ecfx-1 a1')
  expect(p).toContain('/p/x.agents')
})
