import { test, expect } from 'claude-code/testing'
import { extractBlock, mrKey, mrKeyFromRef, mrKeysOf, parseItems, ticketKey, UNPLANNED } from './diary.ts'
import { DIARY, DIARY_UNPLANNED } from './fixtures.ts'

test('extractBlock returns only what sits between the start-day markers', async () => {
  const block = extractBlock(DIARY) ?? ''
  expect(block.includes('#### Plan')).toBe(true)
  expect(block.includes('drawing')).toBe(false)
  expect(block.includes('not a plan line')).toBe(false)
})

test('extractBlock is null without both markers', async () => {
  expect(extractBlock('no block here')).toBe(null)
  expect(extractBlock('<!-- start-day:start -->\n- [ ] a')).toBe(null)
})

test('parseItems reads group, marker, text and evidence; habits and the report block are ignored', async () => {
  const items = parseItems(DIARY)
  expect(items.length).toBe(7)
  expect(items.map(i => i.marker).join('')).toBe(' x /!> ')
  const done = items[1]
  expect(done.group).toBe('First')
  expect(done.marker).toBe('x')
  expect(done.evidence).toBe('note: approved')
  const blocked = items[4]
  expect(blocked.marker).toBe('!')
  expect(blocked.text).toBe('ecfx-17992 Box access question')
  expect(blocked.evidence).toBe('blocked: waiting on bkeeling')
})

test('parseItems normalises [X] to x and never counts the Meetings line', async () => {
  const md = '<!-- start-day:start -->\n**Today**\n- [X] a\n**Meetings:** 10:00 x · y\n<!-- start-day:end -->'
  const items = parseItems(md)
  expect(items.length).toBe(1)
  expect(items[0].marker).toBe('x')
})

test('parseItems is empty for a diary without a block', async () => {
  expect(parseItems('- [ ] loose item').length).toBe(0)
})

test('ticketKey finds lowercase keys and ignores things like utf-8', async () => {
  expect(ticketKey('ecfx-18169 fix the thing')).toBe('ecfx-18169')
  expect(ticketKey('ECFX-6659 sync')).toBe('ecfx-6659')
  expect(ticketKey('utf-8 safe')).toBe('')
  expect(ticketKey('merge backend then dashboard')).toBe('')
})

test('mr keys normalise repo names from URLs, run-state refs and events alike', async () => {
  expect(mrKeysOf(parseItems(DIARY)[0].line).join(',')).toBe('backend!6576,dashboard!2224')
  expect(mrKeyFromRef('ecfx/ecfx-dashboard!2231')).toBe('dashboard!2231')
  expect(mrKeyFromRef('no-bang')).toBe('')
  expect(mrKey('ecfx/ecfx-backend', '!6576')).toBe('backend!6576')
  expect(mrKey('dashboard', 2231)).toBe('dashboard!2231')
})

test('parseItems reads the Unplanned group like any other and leaves the planned items alone', async () => {
  const items = parseItems(DIARY_UNPLANNED)
  expect(items.length).toBe(9)
  expect(items[6].group).toBe('If time')
  const unplanned = items.filter(i => i.group === UNPLANNED)
  expect(unplanned.map(i => i.marker).join('')).toBe('x/')
  expect(unplanned[0].evidence.startsWith('MR [dashboard!2250]')).toBe(true)
  expect(mrKeysOf(unplanned[0].line).join(',')).toBe('dashboard!2250')
  expect(mrKeysOf('- [x] a dashboard!2231 and admin!305  [↗][dashboard!2231] [↗][admin!305] [↗][dashboard!9~2] [↗][ECFX-1]').join(',')).toBe('dashboard!2231,admin!305,dashboard!9')
})
