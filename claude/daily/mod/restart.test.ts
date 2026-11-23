import { test, expect } from 'claude-code/testing'
import { RESTART_ARGS, restartFor, restartPath } from './restart.ts'

test('restartPath sits beside the run state', async () => {
  expect(restartPath('/home/t/.local/state/run-day', '2026-11-23')).toBe('/home/t/.local/state/run-day/2026-11-23.restart')
})

test('the marker restarts only the session it names', async () => {
  expect(restartFor('s-1\n', 's-1')).toBe(true)
  expect(restartFor('  s-1  \n', 's-1')).toBe(true)
  expect(restartFor('s-1\n', 's-2')).toBe(false)
})

test('no marker, or an empty one, restarts nothing', async () => {
  expect(restartFor(null, 's-1')).toBe(false)
  expect(restartFor('', 's-1')).toBe(false)
  expect(restartFor('\n', '')).toBe(false)
})

test('the resume says it was asked for, apart from a playbook update', async () => {
  expect(RESTART_ARGS).toBe('resume restarted')
})
