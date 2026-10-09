import { test, expect } from 'claude-code/testing'
import { externalKey, parseRunState } from './runstate.ts'
import { RUN_STATE } from './fixtures.ts'

test('parseRunState reads every field and lowercases the key', async () => {
  const runs = parseRunState(RUN_STATE)
  expect(runs.length).toBe(3)
  expect(runs[0]).toEqual({
    key: 'ecfx-18169',
    cls: 'auto',
    agent: 'a1b2c3',
    worktree: '/Users/dmitry/projects/worktrees/ecfx-dashboard/ECFX-18169',
    mrs: ['ecfx/ecfx-dashboard!2231'],
    retries: 1,
    needsYou: true,
    owner: 'main',
  })
})

test('a dash means empty, and missing fields default', async () => {
  const [, queued, me] = parseRunState(RUN_STATE)
  expect(queued.agent).toBe('')
  expect(queued.mrs.length).toBe(0)
  expect(queued.needsYou).toBe(false)
  expect(me.key).toBe('ecfx-9190')
  expect(me.retries).toBe(0)
})

test('header lines, blanks and junk are skipped', async () => {
  expect(parseRunState('# run-day\nmax_agents: 3\n\nrandom').length).toBe(0)
  expect(parseRunState('').length).toBe(0)
})

test('a garbled retries value reads as 0', async () => {
  expect(parseRunState('- ecfx-1 | retries=abc')[0].retries).toBe(0)
})

test('owner reads external:KEY and externalKey extracts the key', async () => {
  const [handed] = parseRunState('- ecfx-17992 | class=auto | agent=- | worktree=- | mr=- | retries=0 | needs_you=no | owner=external:ECFX-17992')
  expect(handed.owner).toBe('external:ECFX-17992')
  expect(externalKey(handed.owner)).toBe('ECFX-17992')
  expect(externalKey('main')).toBe('')
})

test('an absent, empty or dash owner reads as main', async () => {
  expect(parseRunState('- ecfx-1 | class=auto')[0].owner).toBe('main')
  expect(parseRunState('- ecfx-1 | owner=')[0].owner).toBe('main')
  expect(parseRunState('- ecfx-1 | owner=-')[0].owner).toBe('main')
})
