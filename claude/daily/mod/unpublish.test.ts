import { test, expect } from 'claude-code/testing'
import { ARTIFACTS_QUEUE, UNPUBLISH_NUDGE, pickNudge } from './unpublish.ts'

const IDEAS = '[ideas] idle review: run /daily:ideas'
const ONE_IDEA = '[{"id":"I-001","text":"x","section":"loose","status":"new"}]'
const ONE_PAGE = '[{"id":"c/x","title":"X","url":"https://claude.ai/artifact/X","state":"queued"}]'

test('ideas due win over the unpublish queue', async () => {
  expect(pickNudge(ONE_IDEA, ONE_PAGE, IDEAS)).toBe(IDEAS)
})

test('no ideas but queued pages nudge /daily:unpublish', async () => {
  expect(pickNudge('[]', ONE_PAGE, IDEAS)).toBe(UNPUBLISH_NUDGE)
  expect(pickNudge('[]\n', ` ${ONE_PAGE}\n`, IDEAS)).toBe(UNPUBLISH_NUDGE)
})

test('nothing due and nothing queued means no nudge', async () => {
  expect(pickNudge('[]', '[]', IDEAS)).toBe(null)
  expect(pickNudge('[]', null, IDEAS)).toBe(null)
  expect(pickNudge('', 'artifacts-site: error', IDEAS)).toBe(null)
})

test('the nudge names the command and the queue falls back to []', async () => {
  expect(UNPUBLISH_NUDGE).toContain('/daily:unpublish')
  expect(ARTIFACTS_QUEUE).toContain('queue || echo "[]"')
})
