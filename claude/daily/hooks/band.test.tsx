import { test, expect, mock } from 'claude-code/testing'

import { DIARY, RUN_STATE } from '../mod/fixtures.ts'

const WIKI = '/home/t/wiki/diary/2026-10-08.md'
const STATE = '/home/t/.local/state/run-day/2026-10-08.md'

type Run = { exitCode: number; stdout: string; stderr: string }

async function start($: any, on: any, opts: { day: Run; refuse?: boolean }) {
  const clock = mock.clock(on)
  const calls: string[][] = []
  const toasts: string[] = []
  const logs: string[] = []
  const registered: string[] = []
  mock.env(on, { HOME: '/home/t' })
  on('process.run', (_$: any, e: any) => {
    calls.push(e.argv)
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
