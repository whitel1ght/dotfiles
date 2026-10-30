import { test, expect } from 'claude-code/testing'
import { REPLY, followupPrompt, parseCards, pendingFollowups } from './followup.ts'
import type { Card } from './followup.ts'

const card: Card = { id: 'D-180', kind: 'answer', status: 'open', question: 'Why is CI red?', session: 'sess-me', followup: 'and the flaky one?', discussion_count: 1 }
const none = new Map<string, number>()

test('decide list --json parses into cards; anything else is none', async () => {
  const json = JSON.stringify([{ ...card, age: '2m', options: [] }, { id: 'D-1', kind: 'question', status: 'open' }])
  expect(parseCards(json)).toEqual([card, { id: 'D-1', kind: 'question', status: 'open', question: '', session: '', followup: '', discussion_count: 0 }])
  expect(parseCards('')).toEqual([])
  expect(parseCards('error: no queue')).toEqual([])
  expect(parseCards('{"id":"D-1"}')).toEqual([])
})

test("this session's open answer card with a follow-up is pending", async () => {
  expect(pendingFollowups([card], 'sess-me', none)).toEqual([card])
})

// Captured from `decide list --json` (2026-10-30): it lists open cards only and prints no status.
const LISTED = '[{"age":"0m","asked":"2026-10-30T10:48:04+03:00","blocks":"","context":"Test card.","discussion":[{"at":"10:48","text":"reply ok","who":"you"}],"discussion_count":1,"followup":"reply ok","id":"D-194","key":"","kind":"answer","mr":"","mr_short":"","options":[],"question":"Delivery test","question_back":true,"recommended":null,"session":"5ac23663","source":"claude-code · dotfiles"}]'

test('a card as decide list --json prints it, with no status, is pending', async () => {
  expect(pendingFollowups(parseCards(LISTED), '5ac23663', none).map(c => c.id)).toEqual(['D-194'])
})

test("another session's card, a question card, a closed card or no follow-up is not", async () => {
  const cards = [
    { ...card, session: 'sess-other' },
    { ...card, kind: 'question' },
    { ...card, status: 'seen' },
    { ...card, followup: '' },
  ]
  expect(pendingFollowups(cards, 'sess-me', none)).toEqual([])
  expect(pendingFollowups([{ ...card, session: '' }], '', none)).toEqual([])
})

test('a follow-up is delivered once, and a newer one on the same card again', async () => {
  const delivered = new Map([['D-180', 1]])
  expect(pendingFollowups([card], 'sess-me', delivered)).toEqual([])
  expect(pendingFollowups([{ ...card, discussion_count: 3 }], 'sess-me', delivered)).toHaveLength(1)
})

test('the prompt quotes the question and the whole follow-up, and names the reply tool and id', async () => {
  const long = 'x'.repeat(2000)
  const text = followupPrompt([{ ...card, followup: long }])
  expect(text).toBe(
    `[decisions] The user followed up on your answer card D-180 (their question: "Why is CI red?"): "${long}". Do what it asks, then answer with the decisions reply tool (${REPLY}, id "D-180"; in Claude Code load it with ToolSearch select:${REPLY}); the reply shows on the same card. If the decisions tools are not there, answer in the chat.`,
  )
  expect(REPLY).toBe('mcp__decisions__reply')
})

test('several follow-ups go in one prompt, one paragraph each; no question, no parenthesis', async () => {
  const text = followupPrompt([card, { ...card, id: 'D-181', question: '' }])
  const [first, second] = text.split('\n\n')
  expect(first).toContain('card D-180 (their question')
  expect(second).toContain('card D-181: "and the flaky one?"')
  expect(second).toContain('id "D-181"')
})
