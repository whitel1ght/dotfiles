import { test, expect } from 'claude-code/testing'
import { CLAUDE_PLAYBOOK, PI_PLAYBOOK, UPDATE_ARGS, fingerprint, parsePrint, playbookPath, shouldResume } from './update.ts'

const base = { isOwner: true, dayRunning: true, recorded: 'aaaa', current: 'bbbb' }

test('the record sits next to the run state', async () => {
  expect(playbookPath('/s/run-day', '2026-10-29')).toBe('/s/run-day/2026-10-29.playbook')
})

test('a fingerprint is stable, and any change to any file changes it', async () => {
  const a = fingerprint(['# Run the day', 'brief'])
  expect(a).toBe(fingerprint(['# Run the day', 'brief']))
  expect(a).toMatch(/^[0-9a-f]{8}$/)
  expect(fingerprint(['# Run the day!', 'brief'])).not.toBe(a)
  expect(fingerprint(['# Run the day', 'brief', ''])).not.toBe(a)
  expect(fingerprint(['# Run the da', 'ybrief'])).not.toBe(a)
})

test('the record is read back from its first line', async () => {
  expect(parsePrint('1a2b3c4d\n')).toBe('1a2b3c4d')
  expect(parsePrint(null)).toBe(null)
  expect(parsePrint('  \n')).toBe(null)
})

test('a changed playbook resumes the running day in its owner session', async () => {
  expect(shouldResume(base)).toBe(true)
})

test('nothing changed, nothing recorded, another session, or the day over: no resume', async () => {
  expect(shouldResume({ ...base, current: 'aaaa' })).toBe(false)
  expect(shouldResume({ ...base, recorded: null })).toBe(false)
  expect(shouldResume({ ...base, isOwner: false })).toBe(false)
  expect(shouldResume({ ...base, dayRunning: false })).toBe(false)
})

test('each harness fingerprints its own playbook and the shared briefs', async () => {
  expect(CLAUDE_PLAYBOOK).toContain('claude/daily/commands/run-day.md')
  expect(PI_PLAYBOOK).toContain('pi/prompts/run-day.md')
  for (const t of ['ticket-brief.md', 'review-round-brief.md', 'review-brief.md']) {
    expect(CLAUDE_PLAYBOOK).toContain(`claude/daily/templates/${t}`)
    expect(PI_PLAYBOOK).toContain(`claude/daily/templates/${t}`)
  }
  expect(UPDATE_ARGS).toBe('resume updated')
})
