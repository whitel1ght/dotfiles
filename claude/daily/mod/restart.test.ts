import { test, expect } from 'claude-code/testing'
import { RESTART_ARGS, formatRestart, restartFor, restartPath } from './restart.ts'

test('restartPath sits beside the run state', async () => {
  expect(restartPath('/home/t/.local/state/run-day', '2026-11-23')).toBe('/home/t/.local/state/run-day/2026-11-23.restart')
})

test('the marker restarts only the session it names', async () => {
  expect(restartFor(formatRestart('s-1', 'in-place'), 's-1', 'tick')).toBe(true)
  expect(restartFor('  s-1  \n in-place \n', 's-1', 'tick')).toBe(true)
  expect(restartFor(formatRestart('s-1', 'in-place'), 's-2', 'tick')).toBe(false)
})

test('a respawn marker is taken only by the new process at its start, never on a tick', async () => {
  expect(restartFor(formatRestart('s-1', 'respawn'), 's-1', 'start')).toBe(true)
  expect(restartFor(formatRestart('s-1', 'respawn'), 's-1', 'tick')).toBe(false)
})

test('an in-place marker is taken at a start or on a tick', async () => {
  expect(restartFor(formatRestart('s-1', 'in-place'), 's-1', 'start')).toBe(true)
  expect(restartFor('s-1\n', 's-1', 'tick')).toBe(true)
})

test('no marker, or an empty one, restarts nothing', async () => {
  expect(restartFor(null, 's-1', 'start')).toBe(false)
  expect(restartFor('', 's-1', 'tick')).toBe(false)
  expect(restartFor('\nrespawn\n', '', 'start')).toBe(false)
})

test('the resume says it was asked for, apart from a playbook update', async () => {
  expect(RESTART_ARGS).toBe('resume restarted')
})
