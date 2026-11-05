import { test, expect } from 'claude-code/testing'
import { agentMrKeys, agentMrUrls, agentPath, commentId, hasDoneEvidence, itemKey, parseAgent } from './agentfile.ts'
import { parseItems } from './diary.ts'
import { AGENT, DIARY_NEW } from './fixtures.ts'

test('agentPath puts the file in .agent beside the diary', async () => {
  expect(agentPath('/u/wiki/diary/2026-11-05.md')).toBe('/u/wiki/diary/.agent/2026-11-05.md')
})

test('parseAgent reads mr, progress and done entries per section', async () => {
  const e = parseAgent(AGENT).get('ecfx-17482')
  expect(e).toEqual([
    { kind: 'mr', time: '', text: 'dashboard!2289 https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289' },
    { kind: 'progress', time: '09:12', text: 'O2, N1 fixed, pushed at 811e370a3' },
    { kind: 'done', time: '11:40', text: 'merged dec5a42eb2' },
  ])
  expect(parseAgent(AGENT).get('p3')?.length).toBe(1)
})

test('parseAgent ignores unknown kinds, malformed lines and the header', async () => {
  const m = parseAgent('# agent notes\n## a1\n- 09:00 bogus: x\n- 9:00 note: y\nrandom\n- 09:01 note: ok\n')
  expect(m.size).toBe(1)
  expect(m.get('a1')).toEqual([{ kind: 'note', time: '09:01', text: 'ok' }])
})

test('agentMrKeys and agentMrUrls normalise the repo', async () => {
  expect(agentMrKeys(AGENT)).toEqual(['dashboard!2289'])
  expect(agentMrKeys('## k\n- mr: ecfx-dashboard!2289 https://x/y\n')).toEqual(['dashboard!2289'])
  expect(agentMrUrls(AGENT).get('dashboard!2289')).toBe('https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2289')
})

test('hasDoneEvidence needs a done entry in that section', async () => {
  expect(hasDoneEvidence(AGENT, 'ecfx-17482')).toBe(true)
  expect(hasDoneEvidence(AGENT, 'p3')).toBe(false)
  expect(hasDoneEvidence(AGENT, 'nope')).toBe(false)
})

test('commentId reads the trailing marker', async () => {
  expect(commentId('- [ ] reply to Levi <!-- p3 -->')).toBe('p3')
  expect(commentId('- [ ] x')).toBe('')
})

test('itemKey prefers the ticket key, then the comment id', async () => {
  const items = parseItems(DIARY_NEW)
  expect(items.map(itemKey)).toEqual(['ecfx-17482', 'ecfx-18778', 'p3'])
})
