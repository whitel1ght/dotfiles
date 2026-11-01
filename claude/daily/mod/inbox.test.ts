import { test, expect } from 'claude-code/testing'
import { inboxPrompt, messageFiles, nextInbox, parseListing } from './inbox.ts'

const A = '20261008T154200-ECFX-18169-ab12.md'
const B = '20261008T154300-offplan-cd34.md'
const C = '20261008T160000-ECFX-17992-ef56.md'

test('parseListing trims, drops blank lines and carriage returns', async () => {
  expect(parseListing(`${A}\r\n\n  ${B} \n`)).toEqual([A, B])
  expect(parseListing('')).toEqual([])
})

test('messageFiles keeps only message names, oldest first; tmp files, done/ and bad/ never count', async () => {
  expect(messageFiles([C, 'done', 'bad', `${A}.tmp`, 'README.md', B, A, '.DS_Store'])).toEqual([A, B, C])
})

test('the first listing reports every waiting message as new, oldest first', async () => {
  const { fresh, state } = nextInbox([C, A, B], [])
  expect(fresh).toEqual([A, B, C])
  expect(state).toEqual({ pending: 3, seen: [A, B, C] })
})

test('a message already seen is not reported again but still counts as pending', async () => {
  const first = nextInbox([A, B], [])
  const second = nextInbox([A, B], first.state.seen)
  expect(second.fresh).toEqual([])
  expect(second.state.pending).toBe(2)
})

test('only the new file is reported when the others were seen', async () => {
  expect(nextInbox([A, B, C], [A, B]).fresh).toEqual([C])
})

test('files that left the inbox are forgotten, and an empty inbox is zero pending', async () => {
  const { fresh, state } = nextInbox([C], [A, B, C])
  expect(fresh).toEqual([])
  expect(state).toEqual({ pending: 1, seen: [C] })
  expect(nextInbox([], [A]).state).toEqual({ pending: 0, seen: [] })
})

test('inboxPrompt is the line the main session recognises', async () => {
  expect(inboxPrompt(2)).toBe('inbox: 2 new')
})
