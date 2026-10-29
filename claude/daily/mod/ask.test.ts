import { test, expect } from 'claude-code/testing'
import { ASK_NUDGE, ASK_USER, BUSY_NOTE, FORM_DENY, FORM_TOOLS, TELL_USER, endsWithQuestion, isBusyPrompt, nextAsk, shouldNudgeAsk } from './ask.ts'

test('the decisions tools have the same name in Claude Code and pi', async () => {
  expect(ASK_USER).toBe('mcp__decisions__ask_user')
  expect(TELL_USER).toBe('mcp__decisions__tell_user')
  expect(FORM_TOOLS).toEqual(['AskUserQuestion', 'ask_user_question'])
  expect(FORM_DENY).toContain('ask_user')
})

test('a prompt typed into a running turn or beside running agents is a busy one', async () => {
  expect(isBusyPrompt({ inTurn: true, agentsRunning: 0 })).toBe(true)
  expect(isBusyPrompt({ inTurn: false, agentsRunning: 2 })).toBe(true)
  expect(isBusyPrompt({ inTurn: false, agentsRunning: 0 })).toBe(false)
  expect(BUSY_NOTE).toContain('tell_user')
})

test('a message ending in a question asks something', async () => {
  expect(endsWithQuestion('Done.\n\nShall I build it?')).toBe(true)
  expect(endsWithQuestion('**Merge it now?**')).toBe(true)
  expect(endsWithQuestion('Which one: `a` or `b`?\n')).toBe(true)
  expect(endsWithQuestion('Do you want 1) a or 2) b?)')).toBe(true)
})

test('a question earlier, a code block or a statement at the end does not', async () => {
  expect(endsWithQuestion('Why? Because the lockfile was stale.')).toBe(false)
  expect(endsWithQuestion('Run:\n```\nls -la?\n```')).toBe(false)
  expect(endsWithQuestion('')).toBe(false)
  expect(endsWithQuestion('result: shipped')).toBe(false)
})

const turn = { isMain: true, reason: 'answer', text: 'Shall I merge it?', asked: false, nudged: false }

test('a main turn that ends asking, with no card filed, is nudged once', async () => {
  expect(shouldNudgeAsk(turn)).toBe(true)
  expect(shouldNudgeAsk({ ...turn, nudged: true })).toBe(false)
  expect(ASK_NUDGE).toContain('ask_user')
})

test('not when the turn filed a card, was a subagent, or did not end with an answer', async () => {
  expect(shouldNudgeAsk({ ...turn, asked: true })).toBe(false)
  expect(shouldNudgeAsk({ ...turn, isMain: false })).toBe(false)
  expect(shouldNudgeAsk({ ...turn, reason: 'aborted' })).toBe(false)
  expect(shouldNudgeAsk({ ...turn, text: 'Merged.' })).toBe(false)
})

test('the user writing starts a fresh stretch; a nudge or a filed card ends it', async () => {
  const fresh = { asked: false, nudged: false }
  expect(nextAsk(fresh, 'tool', ASK_USER)).toEqual({ asked: true, nudged: false })
  expect(nextAsk(fresh, 'tool', 'Bash')).toEqual(fresh)
  expect(nextAsk({ asked: true, nudged: true }, 'user')).toEqual(fresh)
  expect(nextAsk(fresh, 'nudged')).toEqual({ asked: false, nudged: true })
})
