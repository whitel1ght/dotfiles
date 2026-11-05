import { test, expect } from 'claude-code/testing'
import { applyEdit, checkTicks, denyMessage, isTodaysDiary } from './guard.ts'
import { AGENT, DIARY, DIARY_NEW, DIARY_UNPLANNED } from './fixtures.ts'

const tick = (from: string, to: string) => DIARY.replace(from, to)

test('ticking with an MR link is allowed', async () => {
  const after = tick(
    '- [ ] ecfx-6659 sync with @smtsuchi',
    '- [x] ecfx-6659 sync with @smtsuchi · draft MR [dashboard!2240](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2240)',
  )
  expect(checkTicks(DIARY, after, null).ok).toBe(true)
})

test('ticking with a trailing [↗][repo!N] ref is allowed', async () => {
  const ref = '- [x] ecfx-6659 sync with @smtsuchi · draft MR dashboard!2240  [↗][dashboard!2240]'
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', ref), null).ok).toBe(true)
  const collided = '- [x] ecfx-6659 sync with @smtsuchi  [↗][dashboard!2240~2]'
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', collided), null).ok).toBe(true)
})

test('a [↗] ref that is not an MR does not count as evidence', async () => {
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi  [↗][ECFX-6659]'), null).ok).toBe(false)
})

test('ticking with "merged" or "· note:" is allowed', async () => {
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi · merged'), null).ok).toBe(true)
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi · note: agreed to ship'), null).ok).toBe(true)
})

test('a bare tick is refused and the line is reported', async () => {
  const res = checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi'), null)
  expect(res.ok).toBe(false)
  if (!res.ok) expect(res.lines.join('|')).toBe('- [x] ecfx-6659 sync with @smtsuchi')
})

test('a capital [X] tick without evidence is refused too', async () => {
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [X] ecfx-6659 sync with @smtsuchi'), null).ok).toBe(false)
})

test('lines already [x] stay allowed, and other markers never need evidence', async () => {
  expect(checkTicks(DIARY, DIARY, null).ok).toBe(true)
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [!] ecfx-6659 sync with @smtsuchi · blocked: x'), null).ok).toBe(true)
  expect(checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [>] ecfx-6659 sync with @smtsuchi'), null).ok).toBe(true)
})

test('an already-ticked line keeps passing when its evidence is edited away', async () => {
  expect(checkTicks(DIARY, tick(' · note: approved', ''), null).ok).toBe(true)
})

test('a brand-new [x] line without evidence is refused', async () => {
  expect(checkTicks(DIARY, tick('**Today**', '**Today**\n- [x] ecfx-1111 sneaky'), null).ok).toBe(false)
})

test('habit checkboxes outside the block are not policed', async () => {
  expect(checkTicks(DIARY, tick('- [ ] drawing', '- [x] drawing'), null).ok).toBe(true)
})

test('two identical lines are matched one to one', async () => {
  const two = '<!-- start-day:start -->\n- [x] same · merged\n- [ ] same\n<!-- start-day:end -->'
  const bad = '<!-- start-day:start -->\n- [x] same · merged\n- [x] same\n<!-- start-day:end -->'
  expect(checkTicks(two, bad, null).ok).toBe(false)
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
  expect(isTodaysDiary('/Users/d/wiki/work/projects/ecfx/state.md', '2026-10-08')).toBe(false)
})

test('denyMessage names the offending lines', async () => {
  expect(denyMessage(['- [x] a']).includes('- [x] a')).toBe(true)
})

test('an Unplanned line ticked with a note or an MR link passes, a bare one does not', async () => {
  const open = '- [/] retro prep · note: started the outline'
  expect(checkTicks(DIARY_UNPLANNED, DIARY_UNPLANNED.replace(open, '- [x] retro prep'), null).ok).toBe(false)
  expect(checkTicks(DIARY_UNPLANNED, DIARY_UNPLANNED.replace(open, '- [x] retro prep · note: outline done'), null).ok).toBe(true)
  expect(checkTicks(DIARY, DIARY_UNPLANNED, null).ok).toBe(true)
})

const END_MARK = '<!-- start-day:end -->'
const START_MARK = '<!-- start-day:start -->'

test('deleting the end marker together with a bare tick is refused', async () => {
  const after = tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi').replace(END_MARK, '')
  const res = checkTicks(DIARY, after, null)
  expect(res.ok).toBe(false)
  if (!res.ok) expect(res.lines.join('|').includes('markers')).toBe(true)
})

test('deleting a marker without any tick change is refused too', async () => {
  expect(checkTicks(DIARY, DIARY.replace(END_MARK, ''), null).ok).toBe(false)
  expect(checkTicks(DIARY, DIARY.replace(START_MARK, ''), null).ok).toBe(false)
})

test('a diary with no valid block before still passes', async () => {
  expect(checkTicks('# no block\n- [ ] a', '# no block\n- [x] a', null).ok).toBe(true)
  expect(checkTicks(`${START_MARK}\n- [ ] a`, '- [x] a', null).ok).toBe(true)
})

test('applyEdit with an empty old_string returns null', async () => {
  expect(applyEdit(DIARY, { tool: 'Edit', old_string: '', new_string: 'x' })).toBe(null)
})

test('a blocked tick reports one line through onBlock, and an allowed one does not', async () => {
  const seen: string[] = []
  const bad = tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi')
  const verdict = checkTicks(DIARY, bad, null, m => seen.push(m))
  expect(verdict.ok).toBe(false)
  expect(seen.length).toBe(1)
  expect(seen[0]).toContain('diary guard blocked')
  expect(seen[0]).toContain('ecfx-6659')
  expect(seen[0]).not.toContain('\n')
  checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi · merged'), null, m => seen.push(m))
  expect(seen.length).toBe(1)
})

test('a throwing onBlock never changes the verdict', async () => {
  const bad = tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [x] ecfx-6659 sync with @smtsuchi')
  const boom = () => {
    throw new Error('boom')
  }
  expect(checkTicks(DIARY, bad, null, boom)).toEqual(checkTicks(DIARY, bad, null))
})

const L17482 = '- [/] ecfx-17482 retrieve picker: merge after its pipeline'
const L18778 = '- [ ] ecfx-18778 release: deploy, then dashboard to prod'
const P3 = '- [ ] reply to Levi about the QA date <!-- p3 -->'
const newEdit = (from: string, to: string) => DIARY_NEW.replace(from, to)

test('old format: a tick without evidence is refused and reported as old', async () => {
  const res = checkTicks(DIARY, tick('- [ ] ecfx-6659 sync with @smtsuchi', '- [X] ecfx-6659 sync with @smtsuchi'), null)
  expect(res.ok).toBe(false)
  if (!res.ok) expect(res.format).toBe('old')
})

test('new format: a tick with a done entry passes, one without is refused', async () => {
  expect(checkTicks(DIARY_NEW, newEdit(L17482, '- [X] ecfx-17482 retrieve picker: merge after its pipeline'), AGENT).ok).toBe(true)
  const res = checkTicks(DIARY_NEW, newEdit(L18778, '- [X] ecfx-18778 release: deploy, then dashboard to prod'), AGENT)
  expect(res.ok).toBe(false)
  if (!res.ok) {
    expect(res.format).toBe('new')
    expect(res.lines.join('|')).toContain('ecfx-18778')
    expect(denyMessage(res.lines, 'new')).toContain('day-agent note ecfx-18778 done')
    expect(denyMessage(res.lines, 'new').startsWith('daily: refusing this plan edit (lines stay short;')).toBe(true)
  }
})

test('new format: reword plus tick in one edit passes with evidence', async () => {
  expect(checkTicks(DIARY_NEW, newEdit(L17482, '- [X] ecfx-17482 retrieve picker merged'), AGENT).ok).toBe(true)
})

test('new format: keyless lines need a pN done entry, lines with no key or id are refused', async () => {
  const ticked = P3.replace('[ ]', '[X]')
  expect(checkTicks(DIARY_NEW, newEdit(P3, ticked), AGENT).ok).toBe(false)
  const withDone = `${AGENT}- 10:30 done: replied\n`
  expect(checkTicks(DIARY_NEW, newEdit(P3, ticked), withDone, null).ok).toBe(true)
  expect(checkTicks(DIARY_NEW, newEdit(P3, `${P3}\n- [X] something with no key`), withDone, null).ok).toBe(false)
})

test('new format: children are not tick-guarded', async () => {
  expect(checkTicks(DIARY_NEW, newEdit('  - [ ] A3 deploy', '  - [X] A3 deploy'), AGENT).ok).toBe(true)
})

test('new format: line rules refuse new violations with the reason', async () => {
  const cases: [string, string][] = [
    [newEdit(L17482, `${L17482} · progress: x`), '" · "'],
    [newEdit(L17482, `${L17482}  [↗][dashboard!2289]`), '[↗]'],
    [newEdit(END_MARK, `[dashboard!2289]: https://gitlab.com/x\n${END_MARK}`), 'definition'],
    [newEdit(L18778, `${L18778}\n  - [ ] ${'c'.repeat(101)}`), '100'],
  ]
  for (const [after, reason] of cases) {
    const res = checkTicks(DIARY_NEW, after, AGENT)
    expect(res.ok).toBe(false)
    if (!res.ok) expect(res.lines.join('|')).toContain(reason)
  }
})

test('new format: a 100-char line plus a comment id passes, an untouched old violation passes', async () => {
  const long = `- [ ] ${'w'.repeat(94)}`
  expect(checkTicks(DIARY_NEW, newEdit(L18778, `${L18778}\n${long} <!-- p12 -->`), AGENT).ok).toBe(true)
  const bad = newEdit(L18778, `${L18778} · old`)
  expect(checkTicks(bad, bad, AGENT).ok).toBe(true)
})

test('new format: broken block markers are refused', async () => {
  expect(checkTicks(DIARY_NEW, DIARY_NEW.replace(END_MARK, ''), AGENT).ok).toBe(false)
})
