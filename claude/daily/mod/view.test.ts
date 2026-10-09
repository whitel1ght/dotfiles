import { test, expect } from 'claude-code/testing'
import { parseItems } from './diary.ts'
import { parseRunState } from './runstate.ts'
import { joinRows, newlyNeedsYou, panelGroups, statusLine } from './view.ts'
import { DIARY, DIARY_UNPLANNED, RUN_STATE } from './fixtures.ts'

const items = parseItems(DIARY)
const runs = parseRunState(RUN_STATE)

test('joinRows matches an agent by id first, then by description', async () => {
  const byId = joinRows(items, runs, [{ id: 'a1b2c3', description: 'whatever', status: 'running' }])
  expect(byId.find(r => r.key === 'ecfx-18169')?.running).toBe(true)
  const byDesc = joinRows(items, [{ ...runs[0], agent: '' }], [{ id: 'zzz', description: 'ECFX-18169 fix', status: 'running' }])
  expect(byDesc.find(r => r.key === 'ecfx-18169')?.running).toBe(true)
})

test('an idle or completed agent is not running', async () => {
  const rows = joinRows(items, runs, [{ id: 'a1b2c3', description: '', status: 'completed' }])
  expect(rows.find(r => r.key === 'ecfx-18169')?.running).toBe(false)
})

test('needsYou drops once the item is ticked', async () => {
  const ticked = items.map(i => (i.text.startsWith('ecfx-18169') ? { ...i, marker: 'x' as const } : i))
  expect(joinRows(items, runs, []).find(r => r.key === 'ecfx-18169')?.needsYou).toBe(true)
  expect(joinRows(ticked, runs, []).find(r => r.key === 'ecfx-18169')?.needsYou).toBe(false)
})

test('statusLine shows day done/total and only non-zero segments', async () => {
  const rows = joinRows(items, runs, [{ id: 'a1b2c3', description: '', status: 'running' }])
  expect(statusLine(rows)).toBe('day 1/7 · ⚙ 1 running · ✋ 1 needs you')
  expect(statusLine(joinRows(items, [], []))).toBe('day 1/7')
  expect(statusLine([])).toBe('day 0/0')
})

test('panelGroups orders Merge, First, Today, If time and badges rows', async () => {
  const groups = panelGroups(joinRows(items, runs, [{ id: 'a1b2c3', description: '', status: 'running' }]))
  expect(groups.map(g => g.group).join(',')).toBe('Merge,First,Today,If time')
  const today = groups[2].rows[0]
  expect(today.needsYou).toBe(true)
  expect(today.badges.join('|')).toBe('⚙ running|✋ needs you|ecfx/ecfx-dashboard!2231')
})

test('items outside the known groups sort last', async () => {
  const md = '<!-- start-day:start -->\n**Extra**\n- [ ] x\n**Merge**\n- [ ] y\n<!-- start-day:end -->'
  expect(panelGroups(joinRows(parseItems(md), [], [])).map(g => g.group).join(',')).toBe('Merge,Extra')
})

test('newlyNeedsYou reports only keys that were not already flagged', async () => {
  const rows = joinRows(items, runs, [])
  expect(newlyNeedsYou(new Set(), rows).join(',')).toBe('ecfx-18169')
  expect(newlyNeedsYou(new Set(['ecfx-18169']), rows).length).toBe(0)
})

test('statusLine appends the inbox count only when it is above zero', async () => {
  const rows = joinRows(items, runs, [])
  expect(statusLine(rows, 2)).toBe('day 1/7 · ✋ 1 needs you · 📥 2')
  expect(statusLine(rows, 0)).toBe('day 1/7 · ✋ 1 needs you')
  expect(statusLine([], 1)).toBe('day 0/0 · 📥 1')
})

test('the Unplanned group comes after the known groups and its rows count in the day total', async () => {
  const rows = joinRows(parseItems(DIARY_UNPLANNED), [], [])
  expect(panelGroups(rows).map(g => g.group).join(',')).toBe('Merge,First,Today,If time,Unplanned')
  expect(statusLine(rows)).toBe('day 2/9')
})

test('an item handed to a side session carries an external badge and is not running', async () => {
  const handed = runs.map(r => (r.key === 'ecfx-18171' ? { ...r, owner: 'external:ECFX-18171' } : r))
  const rows = joinRows(items, handed, [])
  expect(panelGroups(rows).find(g => g.group === 'If time')?.rows[0].badges.join('|')).toBe('↗ with you')
  expect(rows.find(r => r.key === 'ecfx-18171')?.running).toBe(false)
})

test('an external-owned item is never running, even with a live joined agent', async () => {
  const ext = [{ ...runs[0], owner: 'external:ECFX-18169' }]
  const byId = joinRows(items, ext, [{ id: 'a1b2c3', description: '', status: 'running' }])
  const byDesc = joinRows(items, [{ ...ext[0], agent: '' }], [{ id: 'zzz', description: 'ECFX-18169 fix', status: 'running' }])
  for (const rows of [byId, byDesc]) {
    expect(rows.find(r => r.key === 'ecfx-18169')?.running).toBe(false)
    expect(statusLine(rows).includes('running')).toBe(false)
  }
})

test('description fallback matches the ticket key on a boundary only', async () => {
  const run = { ...runs[0], key: 'ecfx-1817', agent: '' }
  const it = [{ ...items[0], text: 'ECFX-1817 thing' }]
  const join = (d: string) => joinRows(it, [run], [{ id: 'x', description: d, status: 'running' }])[0].agent
  expect(join('ECFX-18171 other')).toBe(null)
  expect(join('preECFX-1817')).toBe(null)
  expect(join('ECFX-1817 fix')?.id).toBe('x')
  expect(join('fix (ECFX-1817)')?.id).toBe('x')
})

test('description fallback prefers a live agent among several with the same key', async () => {
  const run = { ...runs[0], agent: '' }
  const rows = joinRows(items, [run], [
    { id: 'old', description: 'ECFX-18169 first', status: 'completed' },
    { id: 'live', description: 'ECFX-18169 second', status: 'running' },
  ])
  expect(rows.find(r => r.key === 'ecfx-18169')?.agent?.id).toBe('live')
})
