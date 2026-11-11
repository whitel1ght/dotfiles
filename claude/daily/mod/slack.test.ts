import { test, expect } from 'claude-code/testing'
import { dueSlot, formatSlot, parseClock, parseSlot, piSlackPrompt, slackDue, slackPrompt } from './slack.ts'

const at = (hhmm: string) => parseClock(hhmm)
const state = (over: Partial<Parameters<typeof slackDue>[0]> = {}) => ({ isOwner: true, dayRunning: true, turnRunning: false, localMinutes: at('15:00'), lastSlot: -1, ...over })

test('no slot before 15:00', async () => {
  expect(dueSlot(at('14:59')!)).toBe(null)
})

test('ten slots, 20 minutes apart, from 15:00 to 18:00', async () => {
  expect(dueSlot(at('15:00')!)).toBe(0)
  expect(dueSlot(at('15:19')!)).toBe(0)
  expect(dueSlot(at('15:20')!)).toBe(1)
  expect(dueSlot(at('18:00')!)).toBe(9)
  expect(dueSlot(at('18:19')!)).toBe(9)
})

test('no slot from 18:20 on', async () => {
  expect(dueSlot(at('18:20')!)).toBe(null)
  expect(dueSlot(at('23:59')!)).toBe(null)
})

test('the clock parses date +%H:%M and rejects anything else', async () => {
  expect(parseClock('09:05\n')).toBe(545)
  expect(parseClock('')).toBe(null)
  expect(parseClock('9 05')).toBe(null)
})

test('the slot file round-trips; missing or junk means none sent', async () => {
  expect(parseSlot(formatSlot(3))).toBe(3)
  expect(parseSlot(null)).toBe(-1)
  expect(parseSlot('junk')).toBe(-1)
})

test('the first due slot is sent', async () => {
  expect(slackDue(state())).toBe(0)
})

test('a slot already sent is not sent again', async () => {
  expect(slackDue(state({ localMinutes: at('15:10'), lastSlot: 0 }))).toBe(null)
})

test('slots missed while asleep are sent once, as the latest due one', async () => {
  expect(slackDue(state({ localMinutes: at('16:05'), lastSlot: 0 }))).toBe(3)
})

test('nothing while a turn runs, outside the owner session, or after the day report', async () => {
  expect(slackDue(state({ turnRunning: true }))).toBe(null)
  expect(slackDue(state({ isOwner: false }))).toBe(null)
  expect(slackDue(state({ dayRunning: false }))).toBe(null)
  expect(slackDue(state({ localMinutes: null }))).toBe(null)
})

test('the prompts name the check and the harness command', async () => {
  expect(slackPrompt(0)).toBe('[daily-slack] check 1/10: run /daily:slack-check.')
  expect(piSlackPrompt(9)).toBe('[daily-slack] check 10/10: run /slack-check.')
})
