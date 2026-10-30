import { test, expect, mock } from 'claude-code/testing'

import { DIARY, RUN_STATE } from '../mod/fixtures.ts'
import { ASK_NUDGE, BUSY_NOTE, FORM_DENY } from '../mod/ask.ts'
import { FOLLOWUP_MS, followupPrompt } from '../mod/followup.ts'

const WIKI = '/home/t/wiki/diary/2026-10-08.md'
const STATE = '/home/t/.local/state/run-day/2026-10-08.md'
const OWNER = '/home/t/.local/state/run-day/2026-10-08.owner'
const ME = 'sess-me'
const T0 = Date.UTC(2026, 9, 8, 6, 0)
const WARM_REPLY = { isAnswered: true, text: 'warm', usage: { input_tokens: 5, output_tokens: 2, cache_read_input_tokens: 80_000, cache_creation_input_tokens: 40 } }

type Run = { exitCode: number; stdout: string; stderr: string }

type Opts = { day: Run | (() => Run); rejectWith?: string; refuse?: boolean; frictionDenied?: boolean; owner?: string | null; writeFails?: boolean; inbox?: string; diary?: string; state?: string | null; fork?: () => unknown; files?: Record<string, string>; decide?: Run }

async function start($: any, on: any, opts: Opts) {
  // A closed lid stops the 5 s refresh tick: while asleep its next period waits for the wake.
  let sleepUntil = 0
  on('clock.every', { ms: 5_000 }, (_$: any, e: any, next: any) => {
    const now = clock.now()
    return now < sleepUntil ? next({ ...e, ms: sleepUntil - now }) : next(e)
  })
  const clock = mock.clock(on, { now: T0 })
  const sleep = (ms: number) => {
    sleepUntil = clock.now() + ms
    return clock.advance(ms)
  }
  const world = { lid: 'open' as 'open' | 'closed' | null, graphics: true as boolean | null, agentListFails: false, decide: opts.decide ?? null }
  const agents: { id: string; status: string; description: string }[] = []
  const mtimes: Record<string, number> = {}
  const state = opts.state === undefined ? RUN_STATE : opts.state
  const files: Record<string, string> = { [WIKI]: opts.diary ?? DIARY, ...opts.files }
  if (state !== null) files[STATE] = state
  const owner = opts.owner === undefined ? ME : opts.owner
  if (owner !== null) files[OWNER] = `${owner}\n`
  const prompts: string[] = []
  const origins: unknown[] = []
  const contexts: unknown[] = []
  const calls: string[][] = []
  const toasts: string[] = []
  const logs: string[] = []
  const registered: string[] = []
  mock.env(on, { HOME: '/home/t' })
  on('process.run', (_$: any, e: any) => {
    calls.push(e.argv)
    if (opts.frictionDenied && isFriction(e.argv)) return { deny: 'friction exploded' }
    if (opts.rejectWith && isChangesSince(e.argv)) return { deny: opts.rejectWith }
    if (world.decide !== null && isDecideList(e.argv)) return { value: world.decide } as never
    if (opts.inbox !== undefined && isInboxLs(e.argv)) return { value: { exitCode: 0, stdout: opts.inbox, stderr: '' } } as never
    if (e.argv[0].endsWith('/ioreg')) return { value: { exitCode: 0, stdout: world.lid === null ? '' : `| |   "AppleClamshellState" = ${world.lid === 'closed' ? 'Yes' : 'No'}\n`, stderr: '' } } as never
    if (e.argv[0].endsWith('/pmset')) return { value: { exitCode: 0, stdout: world.graphics === null ? '' : `Current System Capabilities are: CPU${world.graphics ? ' Graphics Audio' : ''} Network\n`, stderr: '' } } as never
    if (isSubagentsLs(e.argv)) return { value: { exitCode: 0, stdout: `${SUBAGENTS}\n`, stderr: '' } } as never
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
  const commands: string[] = []
  on('command.run', (_$: any, e: any) => {
    commands.push(`${e.command} ${e.args ?? ''}`.trim())
    return { text: `ran ${e.command}` }
  })
  on('prompt.submit', (_$: any, e: any) => {
    prompts.push(e.text)
    origins.push(e.origin)
    contexts.push(e.context)
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
  const tools: string[] = []
  on('tool.call', (_$: any, e: any) => {
    tools.push(e.tool)
    return { result: 'ran', text: 'ran' } as never
  })
  on('agent.list', () => (world.agentListFails ? { deny: 'agent list unavailable' } : { value: agents }) as never)
  on('fs.stat', (_$: any, e: any) => (e.path in mtimes ? { value: { kind: 'file', size: 1, mtimeMs: mtimes[e.path], isLink: false } } : { deny: 'ENOENT' }) as never)
  await $.session.start({ cwd: '/home/t', surface: 'terminal', source: 'startup' } as never)
  return { clock, sleep, world, agents, mtimes, calls, toasts, logs, registered, statuses, files, prompts, origins, contexts, tools, forks, reads, commands }
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
const SUBAGENTS = `/home/t/.claude/projects/-home-t/${ME}/subagents`
const isDecideList = (argv: string[]) => argv[0] === '/bin/sh' && argv[2].includes('list --json')
const isSubagentsLs = (argv: string[]) => argv[0] === '/bin/sh' && argv[2].includes('/subagents')

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

test('a rejected changes-since run that is still running after the timeout is skipped like exit 75 (F-012)', async ($, on) => {
  const s = await start($, on, { day: OK, rejectWith: 'daily: $.process.run(/bin/sh) aborted: still running after 60000ms' })
  for (let i = 0; i < 2; i++) await s.clock.advance(180_000)
  expect(s.toasts.filter(t => t.startsWith('daily watcher'))).toEqual([])
  expect(frictionFor(s.calls, 'changes-since').length).toBe(0)
  await s.clock.advance(180_000)
  const events = frictionFor(s.calls, 'changes-since')
  expect(events.length).toBe(1)
  expect(events[0][8]).toBe('timeout')
  for (let i = 0; i < 3; i++) await s.clock.advance(180_000)
  expect(frictionFor(s.calls, 'changes-since').length).toBe(1)
  expect(s.calls.filter(isFriction).some(a => a[8] === 'tool_error')).toBe(false)
  expect(s.toasts.filter(t => t.startsWith('daily watcher'))).toEqual([])
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
  expect(s.statuses.at(-1)).toContain('\u{f01c} 1 · day runs elsewhere')
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

// Waking from sleep: one [daily-wake] prompt on a full wake (lid open, display on), never on a dark wake.
const AGENTS = '/home/t/.local/state/run-day/2026-10-08.agents'
const isWakeProbe = (argv: string[]) => argv[0].endsWith('/ioreg') || argv[0].endsWith('/pmset')
const wakes = (prompts: string[]) => prompts.filter(p => p.startsWith('[daily-wake]'))
const agentLines = (text: string) => text.split('\n').filter(l => l !== '' && !l.startsWith('#'))
const TWO_AGENTS = `# run-day 2026-10-08
max_agents: 3
- ecfx-18169 | class=auto | agent=a1 | worktree=- | mr=- | retries=0 | needs_you=no
- ecfx-18171 | class=auto | agent=b2 | worktree=- | mr=- | retries=0 | needs_you=no
`

async function sleepThenOpen(s: any, ms: number) {
  await s.clock.advance(10_000)
  s.world.lid = 'closed'
  s.world.graphics = false
  await s.sleep(ms)
  s.world.lid = 'open'
  s.world.graphics = true
  await s.clock.advance(5_000)
}

test('full wake after a gap nudges once', async ($, on) => {
  const s = await start($, on, idleDay)
  s.agents.push({ id: 'a1b2c3', status: 'running', description: 'ecfx-18169' })
  s.mtimes[`${SUBAGENTS}/agent-a1b2c3.jsonl`] = T0
  await sleepThenOpen(s, 95 * MIN)
  await s.clock.advance(60_000)
  expect(wakes(s.prompts)).toHaveLength(1)
  expect(wakes(s.prompts)[0].startsWith('[daily-wake] woke after 95 min:')).toBe(true)
  expect(wakes(s.prompts)[0]).toContain(AGENTS)
  const lines = agentLines(s.files[AGENTS])
  expect(lines).toHaveLength(1)
  expect(lines[0]).toMatch(/^ecfx-18169 \| ticket \| a1b2c3 \| running \| quiet=\d+ \| .*agent-a1b2c3\.jsonl$/)
})

test('dark wakes never nudge', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(10_000)
  s.world.lid = 'closed'
  s.world.graphics = false
  for (let i = 0; i < 3; i++) await s.sleep(15 * MIN)
  expect(s.calls.filter(isWakeProbe).length).toBeGreaterThan(0)
  expect(wakes(s.prompts)).toEqual([])
  s.world.lid = 'open'
  s.world.graphics = true
  await s.clock.advance(5_000)
  await s.clock.advance(60_000)
  expect(wakes(s.prompts)).toHaveLength(1)
  expect(wakes(s.prompts)[0].startsWith('[daily-wake] woke after 45 min:')).toBe(true)
})

test('no wake probe runs without a gap', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(10 * MIN)
  expect(s.calls.filter(isWakeProbe)).toEqual([])
})

test('no outstanding work, no nudge', async ($, on) => {
  const idle = RUN_STATE.replace('agent=a1b2c3', 'agent=-').replace('ECFX-9190 | class=me', 'ECFX-9190 | class=me | agent=- | round=-')
  const s = await start($, on, { ...idleDay, state: idle, inbox: '' })
  await sleepThenOpen(s, 95 * MIN)
  expect(s.calls.filter(isWakeProbe).length).toBeGreaterThan(0)
  expect(wakes(s.prompts)).toEqual([])
  expect(s.files[AGENTS]).toBeUndefined()
})

test('a session that does not own the day gets no wake prompt and no agents file', async ($, on) => {
  const s = await start($, on, { ...idleDay, owner: 'sess-other' })
  await sleepThenOpen(s, 95 * MIN)
  expect(wakes(s.prompts)).toEqual([])
  expect(s.files[AGENTS]).toBeUndefined()
  expect(s.calls.filter(isWakeProbe)).toEqual([])
})

test('after the daily report there is no wake prompt and no agents file', async ($, on) => {
  const s = await start($, on, { day: OK })
  await sleepThenOpen(s, 95 * MIN)
  expect(wakes(s.prompts)).toEqual([])
  expect(s.files[AGENTS]).toBeUndefined()
  expect(s.calls.filter(isWakeProbe)).toEqual([])
})

test('without a run state there is no wake prompt and no agents file', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: null })
  await sleepThenOpen(s, 95 * MIN)
  expect(wakes(s.prompts)).toEqual([])
  expect(s.files[AGENTS]).toBeUndefined()
  expect(s.calls.filter(isWakeProbe)).toEqual([])
})

test('the agents file is refreshed on the inbox tick while agents are outstanding', async ($, on) => {
  const s = await start($, on, idleDay)
  s.agents.push({ id: 'a1b2c3', status: 'running', description: 'ecfx-18169' })
  await s.clock.advance(30_000)
  expect(agentLines(s.files[AGENTS])).toEqual(['ecfx-18169 | ticket | a1b2c3 | running | quiet=- | -'])
})

test('after a restart /daily:run-day rewrites the agents file the dead process left', async ($, on) => {
  const s = await start($, on, { ...idleDay, owner: 'sess-dead' })
  s.files[AGENTS] = `# agents 2026-10-08T05:59:00Z\necfx-18169 | ticket | a1b2c3 | running | quiet=0 | -\n`
  await $.command.run({ command: 'daily:run-day', args: 'resume' })
  expect(agentLines(s.files[AGENTS])).toEqual(['ecfx-18169 | ticket | a1b2c3 | unknown | quiet=- | -'])
})

test('stuck follow-up names a running agent silent for 15+ min, once', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: TWO_AGENTS })
  s.agents.push({ id: 'a1', status: 'running', description: 'ecfx-18169' }, { id: 'b2', status: 'completed', description: 'ecfx-18171' })
  await sleepThenOpen(s, 95 * MIN)
  expect(wakes(s.prompts)).toHaveLength(1)
  s.mtimes[`${SUBAGENTS}/agent-a1.jsonl`] = s.clock.now() - MIN
  s.mtimes[`${SUBAGENTS}/agent-b2.jsonl`] = s.clock.now() - MIN
  await s.clock.advance(15 * MIN)
  const stuck = s.prompts.filter(p => p.startsWith('[daily-wake] stuck:'))
  expect(stuck).toHaveLength(1)
  expect(stuck[0]).toContain('ecfx-18169 a1')
  expect(stuck[0]).not.toContain('b2')
  await s.clock.advance(60 * MIN)
  expect(s.prompts.filter(p => p.startsWith('[daily-wake] stuck:'))).toHaveLength(1)
})

test('no stuck follow-up while the running agent keeps writing', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: TWO_AGENTS })
  s.agents.push({ id: 'a1', status: 'running', description: 'ecfx-18169' })
  await sleepThenOpen(s, 95 * MIN)
  await s.clock.advance(14 * MIN)
  s.mtimes[`${SUBAGENTS}/agent-a1.jsonl`] = s.clock.now()
  await s.clock.advance(2 * MIN)
  expect(s.prompts.filter(p => p.startsWith('[daily-wake] stuck:'))).toEqual([])
})

test('no stuck follow-up when the machine sleeps again before it is due', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: TWO_AGENTS })
  s.agents.push({ id: 'a1', status: 'running', description: 'ecfx-18169' })
  s.mtimes[`${SUBAGENTS}/agent-a1.jsonl`] = T0
  await sleepThenOpen(s, 95 * MIN)
  s.world.lid = 'closed'
  s.world.graphics = false
  await s.sleep(20 * MIN)
  expect(s.prompts.filter(p => p.startsWith('[daily-wake] stuck:'))).toEqual([])
  expect(wakes(s.prompts)).toHaveLength(1)
})

const NOTE = '<task-notification>agent a1 completed</task-notification>'
const notify = ($: any) => $.prompt.submit({ text: NOTE, origin: { kind: 'task-notification' } } as never)

test('a cold task-notification is relayed as a plugin prompt', async ($, on) => {
  const s = await start($, on, idleDay)
  await turn($)
  await s.clock.advance(61 * MIN)
  const out = await notify($)
  await s.clock.settle()
  expect(out).toEqual({ drop: 'daily: relayed past the cold-cache guard' })
  expect(s.prompts).toEqual([NOTE])
  expect((s.origins[0] as { kind: string }).kind).toBe('plugin')
})

test('a warm task-notification passes unchanged', async ($, on) => {
  const s = await start($, on, idleDay)
  await turn($)
  await s.clock.advance(10 * MIN)
  expect(await notify($)).toEqual({ text: NOTE })
  expect(s.origins).toEqual([{ kind: 'task-notification' }])
})

test('a task-notification in a session that does not own the day passes unchanged', async ($, on) => {
  const s = await start($, on, { ...idleDay, owner: 'sess-other' })
  await turn($)
  await s.clock.advance(61 * MIN)
  expect(await notify($)).toEqual({ text: NOTE })
  expect(s.origins).toEqual([{ kind: 'task-notification' }])
})

test('a typed prompt in a cold owner session passes unchanged', async ($, on) => {
  const s = await start($, on, idleDay)
  await turn($)
  await s.clock.advance(61 * MIN)
  expect(await $.prompt.submit({ text: 'hello', origin: { kind: 'composer' } } as never)).toEqual({ text: 'hello' })
  expect(s.prompts).toEqual(['hello'])
})

test('clamshell: lid closed with the display on is a full wake', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(10_000)
  s.world.lid = 'closed'
  s.world.graphics = false
  await s.sleep(95 * MIN)
  s.world.graphics = true
  await s.clock.advance(5_000)
  expect(wakes(s.prompts)).toHaveLength(1)
  expect(wakes(s.prompts)[0].startsWith('[daily-wake] woke after 95 min:')).toBe(true)
})

test('three probes that read neither lid nor display give up on that sleep, with one log line', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(10_000)
  s.world.lid = 'closed'
  s.world.graphics = false
  await s.sleep(95 * MIN)
  s.world.lid = null
  s.world.graphics = null
  await s.clock.advance(15_000)
  const probes = s.calls.filter(isWakeProbe).length
  expect(s.logs.filter(l => l.startsWith('daily wake: cannot read lid or display state'))).toHaveLength(1)
  await s.clock.advance(60_000)
  expect(s.calls.filter(isWakeProbe).length).toBe(probes)
  expect(s.logs.filter(l => l.startsWith('daily wake: cannot read lid or display state'))).toHaveLength(1)
  expect(wakes(s.prompts)).toEqual([])
})

test('a refresh tick that fails right after the sleep does not lose the wake', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.advance(10_000)
  s.world.lid = 'closed'
  s.world.graphics = false
  s.world.agentListFails = true
  await s.sleep(95 * MIN)
  s.world.agentListFails = false
  s.world.lid = 'open'
  s.world.graphics = true
  await s.clock.advance(10_000)
  expect(wakes(s.prompts)).toHaveLength(1)
  expect(wakes(s.prompts)[0].startsWith('[daily-wake] woke after 95 min:')).toBe(true)
})

test('a failed agents-file write logs once and the wake prompt still goes out', async ($, on) => {
  const s = await start($, on, { ...idleDay, writeFails: true })
  s.agents.push({ id: 'a1b2c3', status: 'running', description: 'ecfx-18169' })
  await sleepThenOpen(s, 95 * MIN)
  await s.clock.advance(60_000)
  expect(wakes(s.prompts)).toHaveLength(1)
  expect(s.logs.filter(l => l.startsWith('daily: agents file not written'))).toHaveLength(1)
})

test('a full wake with no outstanding agents but inbox messages still nudges', async ($, on) => {
  const idle = RUN_STATE.replace('agent=a1b2c3', 'agent=-')
  const s = await start($, on, { ...idleDay, state: idle, inbox: `${INBOX_MSG}\n` })
  await sleepThenOpen(s, 95 * MIN)
  expect(wakes(s.prompts)).toHaveLength(1)
  expect(wakes(s.prompts)[0]).toContain('0 background agent(s) outstanding')
})

// A merge that changed the playbook reloads the mod: session.start resumes the day once (mod/update.ts).
const PLAYBOOK = '/home/t/.local/state/run-day/2026-10-08.playbook'
const resumes = (commands: string[]) => commands.filter(c => c === 'daily:run-day resume updated')

test('a changed playbook resumes the running day once, in its owner session', async ($, on) => {
  const s = await start($, on, { ...idleDay, files: { [PLAYBOOK]: '00000000\n' } })
  await s.clock.settle()
  expect(resumes(s.commands)).toHaveLength(1)
  expect(s.logs).toContain('daily: the run-day playbook changed; resuming the day with it')
  expect(s.files[PLAYBOOK]).not.toBe('00000000\n')
  await $.session.start({ cwd: '/home/t', surface: 'terminal', source: 'startup' } as never)
  await s.clock.settle()
  expect(resumes(s.commands)).toHaveLength(1)
})

test('no record, or the playbook the day was claimed with: no resume', async ($, on) => {
  const s = await start($, on, idleDay)
  await s.clock.settle()
  expect(resumes(s.commands)).toHaveLength(0)
  await $.command.run({ command: 'daily:run-day' })
  expect(s.files[PLAYBOOK]).toMatch(/^[0-9a-f]{8}\n$/)
  await $.session.start({ cwd: '/home/t', surface: 'terminal', source: 'startup' } as never)
  await s.clock.settle()
  expect(resumes(s.commands)).toHaveLength(0)
})

test('a session that does not own the day never resumes it', async ($, on) => {
  const s = await start($, on, { ...idleDay, owner: 'sess-other', files: { [PLAYBOOK]: '00000000\n' } })
  await s.clock.settle()
  expect(resumes(s.commands)).toHaveLength(0)
  expect(s.files[PLAYBOOK]).toBe('00000000\n')
})

test('after the daily report a changed playbook resumes nothing', async ($, on) => {
  const s = await start($, on, { day: OK, files: { [PLAYBOOK]: '00000000\n' } })
  await s.clock.settle()
  expect(resumes(s.commands)).toHaveLength(0)
})

// Every session's questions go to the decisions deck (mod/ask.ts).
const answer = ($: any, text: string, extra: object = {}) =>
  $.turn.complete({ answer: text, reason: 'answer', durationMs: 1000, isAborted: false, turnId: 't', ...extra } as never)
const typed = ($: any, text: string, extra: object = {}) => $.prompt.submit({ text, origin: { kind: 'composer' }, ...extra } as never)

test('the question form is refused and points to the deck, in any session', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: null })
  for (const tool of ['AskUserQuestion', 'ask_user_question']) {
    expect(await $.tool.call({ tool, questions: [] } as never)).toEqual({ deny: FORM_DENY })
  }
  expect(s.tools).toEqual([])
})

test('a prompt typed into a running turn carries the tell_user note', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: null })
  await typed($, 'why is CI red?', { turnId: 't' })
  expect(s.contexts).toEqual([[BUSY_NOTE]])
})

test('a prompt typed while agents run carries it too; an idle one does not', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: null })
  await typed($, 'first')
  s.agents.push({ id: 'a1', status: 'running', description: 'review' })
  await typed($, 'and the second?')
  expect(s.contexts).toEqual([undefined, [BUSY_NOTE]])
})

test('a turn that ends asking with no card filed is nudged once', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: null })
  await typed($, 'go')
  await answer($, 'Built. Shall I merge it?')
  await s.clock.settle()
  expect(s.prompts.filter(p => p === ASK_NUDGE).length).toBe(1)
  expect((s.origins[s.prompts.indexOf(ASK_NUDGE)] as { kind: string }).kind).toBe('plugin')
  await answer($, 'Still: shall I merge it?')
  await s.clock.settle()
  expect(s.prompts.filter(p => p === ASK_NUDGE).length).toBe(1)
  await typed($, 'hm')
  await answer($, 'Merge now?')
  await s.clock.settle()
  expect(s.prompts.filter(p => p === ASK_NUDGE).length).toBe(2)
})

test('no nudge when the turn filed a card, ended without asking, or was a subagent', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: null })
  await typed($, 'go')
  await answer($, 'Merged.')
  await answer($, 'Which one?', { agentId: 'a1' })
  await $.tool.call({ tool: 'mcp__decisions__ask_user', question: 'Merge?', options: ['yes', 'no'] } as never)
  await answer($, 'Asked in decisions: D-7. Merge it?')
  await s.clock.settle()
  expect(s.prompts).not.toContain(ASK_NUDGE)
  expect(s.tools).toEqual(['mcp__decisions__ask_user'])
})

// Every session gets the user's follow-ups on its own answer cards (mod/followup.ts).
const CARD = { id: 'D-180', kind: 'answer', status: 'open', question: 'Why is CI red?', session: ME, followup: 'and the flaky one?', discussion_count: 1 }
const listed = (...cards: object[]): Run => ({ exitCode: 0, stdout: JSON.stringify(cards), stderr: '' })

test('a follow-up on this session’s answer card arrives as one prompt, once', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: null, owner: 'sess-other', decide: listed(CARD) })
  await s.clock.advance(FOLLOWUP_MS)
  await s.clock.settle()
  expect(s.prompts).toEqual([followupPrompt([CARD])])
  await s.clock.advance(FOLLOWUP_MS * 3)
  await s.clock.settle()
  expect(s.prompts).toHaveLength(1)
  const next = { ...CARD, followup: 'and the other test?', discussion_count: 3 }
  s.world.decide = listed(next)
  await s.clock.advance(FOLLOWUP_MS)
  await s.clock.settle()
  expect(s.prompts).toEqual([followupPrompt([CARD]), followupPrompt([next])])
})

test('another session’s card, a failing decide or an empty list prompt nothing and toast nothing', async ($, on) => {
  const s = await start($, on, { ...idleDay, state: null, decide: listed({ ...CARD, session: 'sess-other' }) })
  await s.clock.advance(FOLLOWUP_MS)
  s.world.decide = { exitCode: 1, stdout: '', stderr: 'decide: no queue' }
  await s.clock.advance(FOLLOWUP_MS)
  s.world.decide = { exitCode: 0, stdout: '', stderr: '' }
  await s.clock.advance(FOLLOWUP_MS)
  await s.clock.settle()
  expect(s.calls.filter(isDecideList)).toHaveLength(3)
  expect(s.prompts).toEqual([])
  expect(s.toasts).toEqual([])
})
