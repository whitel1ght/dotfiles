import { test, expect } from 'claude-code/testing'
import { applyEdit, checkTicks, denyMessage, isTodaysDiary } from './guard.ts'
import { DIARY, DIARY_UNPLANNED } from './fixtures.ts'

const tick = (from: string, to: string) => DIARY.replace(from, to)

test('ticking with an MR link is allowed', async () => {
  const after = tick(
    '- [ ] ecfx-6659 sync with @smtsuchi',
    '- [x] ecfx-6659 sync with @smtsuchi · draft MR [dashboard!2240](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2240)',
  )
  expect(checkTicks(DIARY, after).ok).toBe(true)
})

test('ticking with "merged" or "· note:" is allowed', async () => {
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi · merged')).ok).toBe(true)
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi · note: agreed to ship')).ok).toBe(true)
})

test('a bare tick is refused and the line is reported', async () => {
  const res = checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi'))
  expect(res.ok).toBe(false)
  if (!res.ok) expect(res.lines.join('|')).toBe('- [x] ecfx-6659 sync with @smtsuchi')
})

test('a capital [X] tick without evidence is refused too', async () => {
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [X] ecfx-6659 sync with @smtsuchi')).ok).toBe(false)
})

test('lines already [x] stay allowed, and other markers never need evidence', async () => {
  expect(checkTicks(DIARY, DIARY).ok).toBe(true)
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [!] ecfx-6659 sync with @smtsuchi · blocked: x')).ok).toBe(true)
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [>] ecfx-6659 sync with @smtsuchi')).ok).toBe(true)
})

test('an already-ticked line keeps passing when its evidence is edited away', async () => {
  expect(checkTicks(DIARY, tick(' · note: approved', '')).ok).toBe(true)
})

test('a brand-new [x] line without evidence is refused', async () => {
  expect(checkTicks(DIARY, tick('**Today**', '**Today**\n- [x] ecfx-1111 sneaky')).ok).toBe(false)
})

test('habit checkboxes outside the block are not policed', async () => {
  expect(checkTicks(DIARY, tick('- [ ] drawing', '- [x] drawing')).ok).toBe(true)
})

test('two identical lines are matched one to one', async () => {
  const two = '<!-- start-day:start -->\n- [x] same · merged\n- [ ] same\n<!-- start-day:end -->'
  const bad = '<!-- start-day:start -->\n- [x] same · merged\n- [x] same\n<!-- start-day:end -->'
  expect(checkTicks(two, bad).ok).toBe(false)
})

test('applyEdit mirrors Edit and Write, and gives up on a missing old_string', async () => {
  expect(applyEdit('a b a', { tool: 'Edit', old_string: 'a', new_string: 'c' })).toBe('c b a')
  expect(applyEdit('a b a', { tool: 'Edit', old_string: 'a', new_string: 'c', replace_all: true })).toBe('c b c')
  expect(applyEdit('a', { tool: 'Edit', old_string: 'zzz', new_string: 'c' })).toBe(null)
  expect(applyEdit('a', { tool: 'Edit', old_string: 'a', new_string: '$&' })).toBe('$&')
  expect(applyEdit('old', { tool: 'Write', content: 'new' })).toBe('new')
})

test('only today\'s diary file is guarded', async () => {
  expect(isTodaysDiary('/Users/d/wiki/diary/2026-10-08.md', '2026-10-08')).toBe(true)
  expect(isTodaysDiary('/Users/d/wiki/diary/2026-10-07.md', '2026-10-08')).toBe(false)
  expect(isTodaysDiary('/Users/d/wiki/projects/ecfx/state.md', '2026-10-08')).toBe(false)
})

test('denyMessage names the offending lines', async () => {
  expect(denyMessage(['- [x] a']).includes('- [x] a')).toBe(true)
})

test('an Unplanned line ticked with a note or an MR link passes, a bare one does not', async () => {
  const open = '- [/] retro prep · note: started the outline'
  expect(checkTicks(DIARY_UNPLANNED, DIARY_UNPLANNED.replace(open, '- [x] retro prep')).ok).toBe(false)
  expect(checkTicks(DIARY_UNPLANNED, DIARY_UNPLANNED.replace(open, '- [x] retro prep · note: outline done')).ok).toBe(true)
  expect(checkTicks(DIARY, DIARY_UNPLANNED).ok).toBe(true)
})

const END_MARK = '<!-- start-day:end -->'
const START_MARK = '<!-- start-day:start -->'

test('deleting the end marker together with a bare tick is refused', async () => {
  const after = tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi').replace(END_MARK, '')
  const res = checkTicks(DIARY, after)
  expect(res.ok).toBe(false)
  if (!res.ok) expect(res.lines.join('|').includes('markers')).toBe(true)
})

test('deleting a marker without any tick change is refused too', async () => {
  expect(checkTicks(DIARY, DIARY.replace(END_MARK, '')).ok).toBe(false)
  expect(checkTicks(DIARY, DIARY.replace(START_MARK, '')).ok).toBe(false)
})

test('a diary with no valid block before still passes', async () => {
  expect(checkTicks('# no block\n- [ ] a', '# no block\n- [x] a').ok).toBe(true)
  expect(checkTicks(`${START_MARK}\n- [ ] a`, '- [x] a').ok).toBe(true)
})

test('applyEdit with an empty old_string returns null', async () => {
  expect(applyEdit(DIARY, { tool: 'Edit', old_string: '', new_string: 'x' })).toBe(null)
})
