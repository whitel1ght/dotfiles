import { test, expect } from 'claude-code/testing'
import { claimsDay, claimsDayPrompt, formatOwner, ownerNote, ownerPath, parseOwner, receivesPings } from './owner.ts'

test('ownerPath sits beside the run state', async () => {
  expect(ownerPath('/home/t/.local/state/run-day', '2026-10-08')).toBe('/home/t/.local/state/run-day/2026-10-08.owner')
})

test('run-day under either name claims the day, a start or a resume', async () => {
  expect(claimsDay('run-day', '')).toBe(true)
  expect(claimsDay('daily:run-day', '')).toBe(true)
  expect(claimsDay('daily:run-day', 'resume')).toBe(true)
})

test('a dry run and other commands never claim the day', async () => {
  expect(claimsDay('daily:run-day', '--dry')).toBe(false)
  expect(claimsDay('run-day', 'resume --dry')).toBe(false)
  expect(claimsDay('daily:pickup', 'ECFX-1')).toBe(false)
  expect(claimsDay('end-day', '')).toBe(false)
  expect(claimsDay('run-day-x', '')).toBe(false)
})

test('a typed /run-day prompt claims the day; prose that mentions it does not', async () => {
  expect(claimsDayPrompt('/daily:run-day')).toBe(true)
  expect(claimsDayPrompt('  /run-day resume\n')).toBe(true)
  expect(claimsDayPrompt('/daily:run-day --dry')).toBe(false)
  expect(claimsDayPrompt('please run /daily:run-day')).toBe(false)
  expect(claimsDayPrompt('/daily:pickup ECFX-1')).toBe(false)
  expect(claimsDayPrompt('inbox: 2 new')).toBe(false)
})

test('parseOwner reads the first non-blank line; formatOwner writes one', async () => {
  expect(parseOwner(formatOwner('abc-123'))).toBe('abc-123')
  expect(parseOwner('\n  abc-123  \nignored\n')).toBe('abc-123')
  expect(parseOwner('')).toBe('')
  expect(parseOwner(null)).toBe('')
})

test('only the owning session receives pings; no owner means nobody', async () => {
  expect(receivesPings('abc-123', 'abc-123')).toBe(true)
  expect(receivesPings('abc-123', 'other')).toBe(false)
  expect(receivesPings('', 'abc-123')).toBe(false)
  expect(receivesPings('', '')).toBe(false)
})

test('ownerNote: nothing for the owner, a hint when nobody owns the day, a pointer elsewhere otherwise', async () => {
  expect(ownerNote('abc-123', 'abc-123')).toBe('')
  expect(ownerNote('', 'abc-123')).toBe('no owner: /daily:run-day')
  expect(ownerNote('abc-123', 'other')).toBe('day runs elsewhere')
})
