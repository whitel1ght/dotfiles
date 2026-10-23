import { test, expect, mock } from 'claude-code/testing'

import { DIARY, RUN_STATE } from '../mod/fixtures.ts'

const WIKI = '/home/t/wiki/diary/2026-10-08.md'
const STATE = '/home/t/.local/state/run-day/2026-10-08.md'
const OWNER = '/home/t/.local/state/run-day/2026-10-08.owner'
const ME = 'sess-me'
const T0 = Date.UTC(2026, 9, 8, 6, 0)
const WARM_REPLY = { isAnswered: true, text: 'warm', usage: { input_tokens: 5, output_tokens: 2, cache_read_input_tokens: 80_000, cache_creation_input_tokens: 40 } }

type Run = { exitCode: number; stdout: string; stderr: string }

type Opts = { day: Run | (() => Run); refuse?: boolean; frictionDenied?: boolean; owner?: string | null; writeFails?: boolean; inbox?: string; diary?: string; fork?: () => unknown }

async function start($: any, on: any, opts: Opts) {
  const clock = mock.clock(on, { now: T0 })
  const files: Record<string, string> = { [WIKI]: opts.diary ?? DIARY, [STATE]: RUN_STATE }
  const owner = opts.owner === undefined ? ME : opts.owner
  if (owner !== null) files[OWNER] = `${owner}\n`
  const prompts: string[] = []
  const calls: string[][] = []
  const toasts: string[] = []
  const logs: string[] = []
  const registered: string[] = []
  mock.env(on, { HOME: '/home/t' })
  on('process.run', (_$: any, e: any) => {
    calls.push(e.argv)
    if (opts.frictionDenied && isFriction(e.argv)) return { deny: 'friction exploded' }
    if (opts.inbox !== undefined && isInboxLs(e.argv)) return { value: { exitCode: 0, stdout: opts.inbox, stderr: '' } } as never
    return { value: e.argv[0] === 'date' ? { exitCode: 0, stdout: '2026-10-08\n', stderr: '' } : typeof opts.day === 'function' ? (isChangesSince(e.argv) ? opts.day() : OK) : opts.day } as never
  })
  const reads: string[] = []
  on('fs.read', (_$: any, e: any) => {
    reads.push(e.path)
    return e.path in files ? { value: files[e.path] } : { deny: 'ENOENT' }
  })
  const forks: number[] = []
  on('model.fork', () => {
    forks.push(clock.now())
    return { value: opts.fork ? opts.fork() : WARM_REPLY } as never
  })
  on('turn.complete', (_$: any, e: any) => ({ text: e.answer }) as never)
  on('turn.step', async function* (_$: any, e: any) {
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null } as never
  })
  on('fs.write', (_$: any, e: any) => {
    if (opts.writeFails) return { deny: 'EACCES' }
    files[e.path] = e.text
    return { value: undefined } as never
  })
  on('session.id', () => ({ value: ME }))
  on('command.run', (_$: any, e: any) => ({ text: `ran ${e.command}` }))
  on('prompt.submit', (_$: any, e: any) => {
    prompts.push(e.text)
    return { text: e.text }
  })
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
  return { clock, calls, toasts, logs, registered, statuses, files, prompts, forks, reads }
}

const isFriction = (argv: string[]) => argv[0] === '/bin/sh' && argv[2].includes('friction')
const frictionFor = (calls: string[][], source: string) => calls.filter(a => isFriction(a) && a[7] === source)
const OK: Run = { exitCode: 0, stdout: '', stderr: '' }
const isChangesSince = (argv: string[]) => argv[0] === '/bin/sh' && argv[2].includes('changes-since')
const TIMED_OUT: Run = { exitCode: 75, stdout: '', stderr: 'changes-since: timed out waiting for Jira or GitLab\n' }
const isInboxLs = (argv: string[]) => argv[0] === '/bin/sh' && argv[2].includes('run-day/inbox')
const INBOX_MSG = '20261008T154200-ECFX-18169-ab12.md'
const EVENT = JSON.stringify({ kind: 'review', repo: 'ecfx/ecfx-backend', mr: 6576, ticket: 'ECFX-9190', summary: 'please fix', url: 'u' })
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

test('a timed-out changes-since tick is skipped quietly and the watcher keeps polling', async ($, on) => {
  const s = await start($, on, { day: TIMED_OUT })
  for (let i = 0; i < 2; i++) await s.clock.advance(180_000)
  expect(s.toasts.filter(t => t.startsWith('changes-since failed')).length).toBe(0)
  expect(frictionFor(s.calls, 'changes-since').length).toBe(0)
  await s.clock.advance(180_000)
  await s.clock.advance(180_000)
  expect(s.calls.filter(isChangesSince).length).toBe(4)
})

test('three timed-out ticks in a row record one timeout, however long it goes on', async ($, on) => {
  const s = await start($, on, { day: TIMED_OUT })
  for (let i = 0; i < 6; i++) await s.clock.advance(180_000)
  const events = frictionFor(s.calls, 'changes-since')
  expect(events.length).toBe(1)
  expect(events[0][8]).toBe('timeout')
})

test('a tick that answers resets the timeout count', async ($, on) => {
  const answers = [TIMED_OUT, TIMED_OUT, OK, TIMED_OUT, TIMED_OUT]
  const s = await start($, on, { day: () => answers.shift() ?? OK })
  for (let i = 0; i < 5; i++) await s.clock.advance(180_000)
  expect(frictionFor(s.calls, 'changes-since').length).toBe(0)
})

test('a failing friction call does not change the toast or break the watcher', async ($, on) => {
  const s = await start($, on, { day: TIMED_OUT, frictionDenied: true })
  for (let i = 0; i < 4; i++) await s.clock.advance(180_000)
  expect(frictionFor(s.calls, 'changes-since').length).toBe(1)
  expect(s.toasts.filter(t => t.startsWith('changes-since failed')).length).toBe(0)
  expect(s.calls.filter(isChangesSince).length).toBe(4)
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

// F-057: inbox and event prompts reach only the session that ran /run-day last.
const pinged = { day: () => ({ exitCode: 0, stdout: `${EVENT}\n`, stderr: '' }), inbox: `${INBOX_MSG}\n` }

test('the owning session gets the inbox and event prompts', async ($, on) => {
  const s = await start($, on, pinged)
  await s.clock.advance(180_000)
  expect(s.prompts).toContain('inbox: 1 new')
  expect(s.prompts.some(p => p.startsWith('[daily-event] review | backend!6576'))).toBe(true)
})

test('another session counts the inbox for its status line but runs no changes-since and gets no prompt or toast', async ($, on) => {
  const s = await start($, on, { ...pinged, owner: 'sess-other' })
  await s.clock.advance(180_000)
  expect(s.calls.filter(isInboxLs).length).toBeGreaterThan(0)
  expect(s.calls.filter(isChangesSince).length).toBe(0)
  expect(s.prompts).toEqual([])
  expect(s.toasts).toEqual([])
  expect(s.statuses.at(-1)).toContain('📥 1 · day runs elsewhere')
})

test('the status line says when the day has no owner, and says nothing extra in the owner', async ($, on) => {
  const none = await start($, on, { day: OK, owner: null })
  await none.clock.advance(5_000)
  expect(none.statuses.at(-1)).toMatch(/^day \d+\/\d+.* · no owner: \/daily:run-day$/)
  await $.command.run({ command: 'daily:run-day', args: '' })
  await none.clock.advance(5_000)
  expect(none.statuses.at(-1)).not.toContain('owner')
  expect(none.statuses.at(-1)).not.toContain('elsewhere')
})

test('with no owner recorded no session is pinged', async ($, on) => {
  const s = await start($, on, { ...pinged, owner: null })
  await s.clock.advance(180_000)
  expect(s.calls.filter(isChangesSince).length).toBe(0)
  expect(s.prompts).toEqual([])
})

test('the status line still shows in a session that does not own the day', async ($, on) => {
  const s = await start($, on, { day: OK, owner: 'sess-other' })
  await s.clock.advance(5_000)
  expect(s.statuses.some(t => typeof t === 'string' && t.startsWith('day '))).toBe(true)
})

test('/daily:run-day records this session as the owner and pings start', async ($, on) => {
  const s = await start($, on, { ...pinged, owner: 'sess-other' })
  await $.command.run({ command: 'daily:run-day', args: 'resume' })
  expect(s.files[OWNER]).toBe(`${ME}\n`)
  await s.clock.advance(30_000)
  expect(s.prompts).toContain('inbox: 1 new')
})

test('/run-day under its bare name records the owner too', async ($, on) => {
  const s = await start($, on, { day: OK, owner: null })
  await $.command.run({ command: 'run-day', args: '' })
  expect(s.files[OWNER]).toBe(`${ME}\n`)
})

test('a dry run leaves the owner alone', async ($, on) => {
  const s = await start($, on, { day: OK, owner: 'sess-other' })
  await $.command.run({ command: 'daily:run-day', args: '--dry' })
  expect(s.files[OWNER]).toBe('sess-other\n')
})

test('a typed /daily:run-day prompt records the owner', async ($, on) => {
  const s = await start($, on, { day: OK, owner: null })
  await $.prompt.submit({ text: '/daily:run-day' })
  expect(s.files[OWNER]).toBe(`${ME}\n`)
})

test('when another session takes the day over, this one stops being pinged', async ($, on) => {
  const s = await start($, on, pinged)
  await s.clock.advance(30_000)
  expect(s.prompts).toEqual(['inbox: 1 new'])
  s.files[OWNER] = 'sess-other\n'
  await s.clock.advance(180_000)
  expect(s.prompts).toEqual(['inbox: 1 new'])
  expect(s.calls.filter(isChangesSince).length).toBe(0)
})

test('a failed owner write toasts, records friction and still runs the command', async ($, on) => {
  const s = await start($, on, { day: OK, owner: null, writeFails: true })
  expect(await $.command.run({ command: 'daily:run-day', args: '' })).toEqual({ text: 'ran daily:run-day' })
  expect(s.toasts.some(t => t.startsWith('daily: run-day owner not recorded'))).toBe(true)
  expect(frictionFor(s.calls, 'daily-owner').length).toBe(1)
})

// The day session stays warm after cache-tax's 6 h window.
const MIN = 60_000
const HOUR = 60 * MIN
const OPEN_DAY = DIARY.replace(/<!-- daily-report:start -->[\s\S]*<!-- daily-report:end -->\n/, '')
const idleDay = { day: OK, diary: OPEN_DAY }
async function step($: any) {
  const stream = $.turn.step({ turnId: 't', index: 0, model: 'm', messageCount: 1 } as never)
  for await (const _ of stream) {
    // drain
  }
  return stream.result
}
const turn = ($: any) => $.turn.complete({ answer: 'ok', reason: 'answer', durationMs: 1000, isAborted: false, turnId: 't' } as never)

test('no keepwarm ping in the first 6 h: cache-tax covers those', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(5 * HOUR)
  await turn($)
  await s.clock.advance(59 * MIN)
  expect(s.forks).toEqual([])
})

test('after 6 h the owning session pings 50 idle minutes after its last turn, then every 50 minutes', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(6 * HOUR)
  await turn($)
  await s.clock.advance(49 * MIN)
  expect(s.forks).toEqual([])
  await s.clock.advance(1 * MIN)
  expect(s.forks).toEqual([T0 + 6 * HOUR + 50 * MIN])
  await s.clock.advance(50 * MIN)
  expect(s.forks.length).toBe(2)
})

test('a session that does not own the day is never kept warm', async ($, on) => {
  const s = await start($, on, { ...idleDay, owner: 'sess-other' })
  await s.clock.advance(6 * HOUR)
  await turn($)
  await s.clock.advance(3 * HOUR)
  expect(s.forks).toEqual([])
})

test('a cold readback stops keepwarm for the session, with one log line', async ($, on) => {
  const cold = { ...WARM_REPLY, usage: { ...WARM_REPLY.usage, cache_read_input_tokens: 0, cache_creation_input_tokens: 80_000 } }
  const s = await start($, on, { ...idleDay, fork: () => cold })
  await s.clock.advance(6 * HOUR)
  await turn($)
  await s.clock.advance(50 * MIN)
  expect(s.forks.length).toBe(1)
  expect(s.logs.filter(l => l.startsWith('daily keepwarm stopped: the ping read 0'))).toHaveLength(1)
  await turn($)
  await s.clock.advance(2 * HOUR)
  expect(s.forks.length).toBe(1)
})

test('an unanswered fork stops keepwarm', async ($, on) => {
  const s = await start($, on, { ...idleDay, fork: () => ({ isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded' }) })
  await s.clock.advance(6 * HOUR)
  await turn($)
  await s.clock.advance(50 * MIN)
  expect(s.logs).toContain('daily keepwarm stopped: the API call failed (529)')
})

test('once the daily report is written keepwarm stops', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(6 * HOUR)
  await turn($)
  await s.clock.advance(50 * MIN)
  expect(s.forks.length).toBe(1)
  s.files[WIKI] = DIARY
  await s.clock.advance(50 * MIN)
  expect(s.forks.length).toBe(1)
  expect(s.logs).toContain("daily keepwarm stopped: today's report is written")
})

test('after midnight the dated owner file no longer matches and keepwarm goes quiet', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(6 * HOUR)
  await turn($)
  delete s.files[OWNER]
  await s.clock.advance(2 * HOUR)
  expect(s.forks).toEqual([])
})

test('re-running /daily:run-day restarts a keepwarm that stopped', async ($, on) => {
  let replies = 0
  const s = await start($, on, { ...idleDay, fork: () => (replies++ === 0 ? { isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded' } : WARM_REPLY) })
  await s.clock.advance(6 * HOUR)
  await turn($)
  await s.clock.advance(50 * MIN)
  expect(s.logs).toContain('daily keepwarm stopped: the API call failed (529)')
  await $.command.run({ command: 'daily:run-day', args: 'resume' })
  await turn($)
  const resumed = s.clock.now()
  await s.clock.advance(3 * HOUR)
  expect(s.forks.slice(1)).toEqual([resumed + 50 * MIN, resumed + 100 * MIN, resumed + 150 * MIN])
})

test('a main-thread model request in a long turn moves the idle clock', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(6 * HOUR)
  await turn($)
  await s.clock.advance(45 * MIN)
  await step($)
  const stepped = s.clock.now()
  await s.clock.advance(10 * MIN)
  expect(s.forks).toEqual([])
  await s.clock.advance(40 * MIN)
  expect(s.forks).toEqual([stepped + 50 * MIN])
})

test('three turns ending together still give one ping', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(6 * HOUR)
  await Promise.all([turn($), turn($), turn($)])
  await s.clock.settle()
  await s.clock.advance(50 * MIN)
  expect(s.forks.length).toBe(1)
})

test('a session that does not own the day reads no diary for keepwarm after a turn', async ($, on) => {
  const s = await start($, on, { ...idleDay, owner: 'sess-other' })
  s.reads.length = 0
  await turn($)
  await s.clock.settle()
  expect(s.reads.filter(p => p === WIKI)).toEqual([])
})
