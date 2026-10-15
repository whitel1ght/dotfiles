import { test, expect, mock } from 'claude-code/testing'

import { DIARY, RUN_STATE } from '../mod/fixtures.ts'

const WIKI = '/home/t/wiki/diary/2026-10-08.md'
const STATE = '/home/t/.local/state/run-day/2026-10-08.md'

type Run = { exitCode: number; stdout: string; stderr: string }

async function start($: any, on: any, opts: { day: Run; refuse?: boolean; frictionDenied?: boolean }) {
  const clock = mock.clock(on)
  const calls: string[][] = []
  const toasts: string[] = []
  const logs: string[] = []
  const registered: string[] = []
  mock.env(on, { HOME: '/home/t' })
  on('process.run', (_$: any, e: any) => {
    calls.push(e.argv)
    if (opts.frictionDenied && isFriction(e.argv)) return { deny: 'friction exploded' }
    return { value: e.argv[0] === 'date' ? { exitCode: 0, stdout: '2026-10-08\n', stderr: '' } : opts.day } as never
  })
  on('fs.read', (_$: any, e: any) => (e.path === WIKI ? { value: DIARY } : e.path === STATE ? { value: RUN_STATE } : { deny: 'ENOENT' }))
  on('command.register', (_$: any, e: any) => {
    if (opts.refuse) return { deny: `"/${e.name}" refused: it is a built-in` }
    registered.push(e.name)
    return { value: undefined } as never
  })
  on('ui.toast', (_$: any, e: any) => {
    toasts.push(e.text)
    return { value: undefined } as never
  })
  const statuses: Array<string | undefined> = []
  on('ui.status', (_$: any, e: any) => {
    statuses.push(e.text)
    return { value: undefined } as never
  })
  on('ui.log', (_$: any, e: any) => {
    logs.push(e.text)
    return { value: undefined } as never
  })
  on('session.start', (_$: any, e: any) => ({ cwd: e.cwd }))
  on('agent.list', () => ({ value: [] }))
  await $.session.start({ cwd: '/home/t', surface: 'terminal', source: 'startup' } as never)
  return { clock, calls, toasts, logs, registered, statuses }
}

const isFriction = (argv: string[]) => argv[0] === '/bin/sh' && argv[2].includes('friction')
const frictionFor = (calls: string[][], source: string) => calls.filter(a => isFriction(a) && a[7] === source)
const OK: Run = { exitCode: 0, stdout: '', stderr: '' }
const isDayPlan = (argv: string[]) => argv[0] === '/bin/sh' && argv[2].includes('day-plan')

test('/day-plan runs day-plan without blocking and reports it opened', async ($, on) => {
  const s = await start($, on, { day: OK })
  expect(s.registered).toContain('day-plan')
  const out = await $.command.run({ command: 'day-plan' })
  expect(out).toEqual({ text: 'Plan popup opened.' })
  expect(s.calls.filter(isDayPlan).length).toBe(1)
  expect(s.toasts).toEqual([])
})

test('/day-plan toasts the error day-plan prints', async ($, on) => {
  const s = await start($, on, { day: { exitCode: 2, stdout: '', stderr: 'day-plan: needs tmux\n' } })
  const out = await $.command.run({ command: 'day-plan' })
  expect(out).toEqual({ text: 'day-plan: needs tmux' })
  expect(s.toasts).toEqual(['day-plan: needs tmux'])
})

test('a refused command name is logged and the rest of session.start still runs', async ($, on) => {
  const s = await start($, on, { day: OK, refuse: true })
  expect(s.logs.length).toBe(1)
  expect(s.logs[0]).toContain('/day-plan not registered')
  await s.clock.advance(5_000)
  expect(s.statuses.some(t => typeof t === 'string' && t.length > 0)).toBe(true)
})

test('a failing changes-since watch toasts once and leaves service_down to the script', async ($, on) => {
  const s = await start($, on, { day: { exitCode: 1, stdout: '', stderr: 'changes-since: Jira unavailable\n' } })
  await s.clock.advance(180_000)
  await s.clock.advance(180_000)
  expect(frictionFor(s.calls, 'changes-since').length).toBe(0)
  expect(s.toasts.filter(t => t.startsWith('changes-since failed')).length).toBe(1)
})

test('a timed-out changes-since watch is recorded as a timeout', async ($, on) => {
  const s = await start($, on, { day: { exitCode: 124, stdout: '', stderr: '' } })
  await s.clock.advance(180_000)
  expect(frictionFor(s.calls, 'changes-since')[0][8]).toBe('timeout')
})

test('a failing friction call does not change the toast or break the watcher', async ($, on) => {
  const s = await start($, on, { day: { exitCode: 124, stdout: '', stderr: 'boom\n' }, frictionDenied: true })
  await s.clock.advance(180_000)
  expect(frictionFor(s.calls, 'changes-since').length).toBe(1)
  expect(s.toasts).toContain('changes-since failed (exit 124): boom')
})

test('a healthy watch records nothing', async ($, on) => {
  const s = await start($, on, { day: OK })
  await s.clock.advance(180_000)
  expect(s.calls.filter(isFriction).length).toBe(0)
})

test('a failing inbox listing records one tool_error friction event, however often it repeats', async ($, on) => {
  const s = await start($, on, { day: { exitCode: 1, stdout: '', stderr: 'ls: denied\n' } })
  await s.clock.advance(90_000)
  const events = frictionFor(s.calls, 'daily-inbox')
  expect(events.length).toBe(1)
  expect(events[0].slice(8)).toEqual(['tool_error', 'inbox read failed (exit 1): ls: denied'])
})
