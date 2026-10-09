import { test, expect } from 'claude-code/testing'
import { classify, eventMrKey, formatNote, formatPrompt, formatToast, parseEvents } from './events.ts'

const ctx = { mrKeys: new Set(['dashboard!2231']), ticketKeys: new Set(['ecfx-18169']) }
const review = { kind: 'review', ticket: 'ECFX-18169', mr: 2231, repo: 'ecfx/ecfx-dashboard', summary: 'bkeeling requested changes', url: 'https://x/2231' }

test('parseEvents keeps good lines and counts the bad ones', async () => {
  const out = parseEvents(`${JSON.stringify(review)}\n\nnot json\n{"no":"kind"}\n[1]\n`)
  expect(out.events.length).toBe(1)
  expect(out.bad).toBe(3)
})

test('parseEvents of empty output is empty', async () => {
  expect(parseEvents('').events.length).toBe(0)
})

test('a review on a today MR is a prompt, on any other MR a note', async () => {
  expect(classify(review, ctx)).toBe('prompt')
  expect(classify({ ...review, mr: 9999 }, ctx)).toBe('note')
})

test('repo spelling does not matter: full path, ecfx- prefix or short', async () => {
  for (const repo of ['ecfx/ecfx-dashboard', 'ecfx-dashboard', 'dashboard']) {
    expect(eventMrKey({ ...review, repo })).toBe('dashboard!2231')
  }
  expect(eventMrKey({ ...review, mr: '!2231' })).toBe('dashboard!2231')
})

test('without an MR the ticket decides', async () => {
  expect(classify({ ...review, mr: null, repo: null }, ctx)).toBe('prompt')
  expect(classify({ ...review, mr: null, repo: null, ticket: 'ECFX-1' }, ctx)).toBe('note')
  expect(classify({ ...review, mr: null, repo: null, ticket: null }, ctx)).toBe('note')
})

test('pipeline_failed and comment follow the same rule as review', async () => {
  expect(classify({ ...review, kind: 'pipeline_failed' }, ctx)).toBe('prompt')
  expect(classify({ ...review, kind: 'comment' }, ctx)).toBe('prompt')
})

test('assigned is a prompt unless the ticket is already in the plan', async () => {
  expect(classify({ kind: 'assigned', ticket: 'ECFX-5', summary: 's' }, ctx)).toBe('prompt')
  expect(classify({ kind: 'assigned', ticket: 'ECFX-18169', summary: 's' }, ctx)).toBe('note')
})

test('informational kinds are notes even on a today MR', async () => {
  for (const kind of ['approved', 'merged', 'pipeline_fixed', 'ticket_updated', 'mention']) {
    expect(classify({ ...review, kind }, ctx)).toBe('note')
  }
})

test('formatPrompt is one compact pipe line with a fixed shape', async () => {
  expect(formatPrompt(review)).toBe('[daily-event] review | dashboard!2231 | ECFX-18169 | bkeeling requested changes | https://x/2231')
})

test('formatPrompt flattens newlines and pipes, truncates, and fills gaps with a dash', async () => {
  const line = formatPrompt({ kind: 'comment', summary: `a | b\nc ${'x'.repeat(300)}` })
  expect(line.includes('\n')).toBe(false)
  expect(line.startsWith('[daily-event] comment | - | - | a / b c ')).toBe(true)
  expect(line.endsWith('… | -')).toBe(true)
  expect(line.split(' | ').length).toBe(5)
})

test('formatNote uses the info tag; formatToast is short and readable', async () => {
  expect(formatNote(review).startsWith('[daily-event:info] review')).toBe(true)
  expect(formatToast(review)).toBe('review ECFX-18169 dashboard!2231: bkeeling requested changes')
  expect(formatToast({ kind: 'pipeline_failed' })).toBe('pipeline failed')
  expect(formatToast({ ...review, summary: 'y'.repeat(500) }).length <= 140).toBe(true)
})
