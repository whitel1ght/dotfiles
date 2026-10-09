import { test, expect, mock } from 'claude-code/testing'

import { DIARY, RUN_STATE } from '../mod/fixtures.ts'

const PROPS = { hasSurvey: false, isWorking: false, maxRows: 30, bodyColumns: 100 }
const WIKI = '/home/t/wiki/diary/2026-10-08.md'
const STATE = '/home/t/.local/state/run-day/2026-10-08.md'

for (const surface of ['terminal', 'desktop'] as const) {
  test(`/plan-band draws the plan band on ${surface}`, async ($, on) => {
    const clock = mock.clock(on)
    mock.env(on, { HOME: '/home/t' })
    on('process.run', () => ({ value: { exitCode: 0, stdout: '2026-10-08\n', stderr: '' } }) as never)
    on('fs.read', (_$, e) => (e.path === WIKI ? { value: DIARY } : e.path === STATE ? { value: RUN_STATE } : { deny: 'ENOENT' }))
    on('command.register', (_$, e) => (e.name === 'plan' ? { deny: `"/plan" refused: it is the built-in /plan` } : ({ value: undefined } as never)))
    on('ui.toast', () => ({ value: undefined }) as never)
    on('ui.status', () => ({ value: undefined }) as never)
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('agent.list', () => ({ value: [] }))
    await $.session.start({ cwd: '/home/t', surface, source: 'startup' } as never)
    await clock.advance(5_000)
    await $.command.run({ command: 'plan-band' })
    const ui = await $.ui.mount({ plugin: 'daily', surface, component: 'AbovePrompt', props: PROPS })
    expect(await ui.find({ type: 'Text', text: /plan · \d+\/\d+ done/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Merge/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /\[!\] ecfx-17992/ })).toBeDefined()
    await ui.unmount()
  })
}
