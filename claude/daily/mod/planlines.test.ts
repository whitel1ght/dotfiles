import { test, expect } from 'claude-code/testing'
import { parseItems } from './diary.ts'
import { parseRunState } from './runstate.ts'
import { nextPlanLines, piPlanPrompt, planPrompt, untracked } from './planlines.ts'

const plan = (...lines: string[]) => ['<!-- start-day:start -->', '**First**', ...lines, '<!-- start-day:end -->'].join('\n')
const runs = parseRunState('# run-day\n- ecfx-100 | class=auto | agent=-\n- p1 | class=review | agent=-\nnotes:\n')
const lines = (...l: string[]) => untracked(parseItems(plan(...l)), runs).map(i => i.text)

test('a new top-level line with no ticket key is untracked', async () => {
  expect(lines('- [ ] figure out the state of ecfx-devbox')).toEqual(['figure out the state of ecfx-devbox'])
})

test('a new line with a ticket key not in the run state is untracked', async () => {
  expect(lines('- [ ] ecfx-200 new ticket')).toEqual(['ecfx-200 new ticket'])
})

test('a line the run state already tracks is not, by ticket key or by pN id', async () => {
  expect(lines('- [ ] ecfx-100 tracked', '- [ ] re-review <!-- p1 -->')).toEqual([])
})

test('only todo lines count: done, in progress, blocked and deferred lines were handled', async () => {
  expect(lines('- [X] a', '- [/] b', '- [!] c', '- [>] d')).toEqual([])
})

test('a child step is not a new line', async () => {
  expect(lines('- [ ] ecfx-100 tracked', '  - [ ] a new child')).toEqual([])
})

test('each line is fresh once, and a further new line is fresh on its own', async () => {
  const a = parseItems(plan('- [ ] one'))
  const first = nextPlanLines(a, [])
  expect(first.fresh.map(i => i.text)).toEqual(['one'])
  expect(nextPlanLines(a, first.seen).fresh).toEqual([])
  const b = parseItems(plan('- [ ] one', '- [ ] two'))
  expect(nextPlanLines(b, first.seen).fresh.map(i => i.text)).toEqual(['two'])
})

test('the prompts name the Keep busy section of each playbook', async () => {
  expect(planPrompt(1)).toBe('[daily-plan] 1 new plan line: run Keep busy of /daily:run-day (section 11).')
  expect(piPlanPrompt(2)).toBe('[daily-plan] 2 new plan lines: run Keep busy of /run-day (section 11).')
})
