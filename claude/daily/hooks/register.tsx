import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import { mrKeyFromRef, mrKeysOf, parseItems, ticketKey } from '../mod/diary.ts'
import { classify, formatNote, formatPrompt, formatToast, parseEvents } from '../mod/events.ts'
import { EMPTY_INBOX, inboxPrompt, nextInbox, parseListing } from '../mod/inbox.ts'
import { applyEdit, checkTicks, denyMessage, isTodaysDiary } from '../mod/guard.ts'
import type { EditInput } from '../mod/guard.ts'
import { parseRunState } from '../mod/runstate.ts'
import type { InboxState, ViewState } from '../mod/types.ts'
import { BAND_WINDOW_ROWS, bandRows, joinRows, newlyNeedsYou, panelGroups, statusLine } from '../mod/view.ts'

const REFRESH_MS = 5_000
const WATCH_MS = 180_000
const INBOX_MS = 30_000
const INBOX_LS = 'ls -1 "$HOME/.local/state/run-day/inbox" 2>/dev/null; true'
const EMPTY: ViewState = { active: false, status: '', groups: [] }
const view = atom({ plugin: 'daily', key: 'view' } as const, EMPTY)
const isExpanded = atom({ plugin: 'daily', key: 'isExpanded' } as const, false)
const bandOffset = atom({ plugin: 'daily', key: 'bandOffset' } as const, null as number | null)
const inbox = atom({ plugin: 'daily', key: 'inbox' } as const, EMPTY_INBOX as InboxState)

type Day = { home: string; today: string; diaryPath: string; statePath: string }

async function today($: EngineInterface): Promise<Day | null> {
  const home = await $.env.get('HOME')
  if (!home) return null
  const ran = await $.process.run(['date', '+%F'])
  if (ran.exitCode !== 0) return null
  const day = ran.stdout.trim()
  return {
    home,
    today: day,
    diaryPath: `${home}/wiki/diary/${day}.md`,
    statePath: `${home}/.local/state/run-day/${day}.md`,
  }
}

async function readOr($: EngineInterface, path: string): Promise<string | null> {
  return $.fs.read(path).then(
    text => text,
    () => null,
  )
}

async function load($: EngineInterface) {
  const day = await today($)
  if (!day) return null
  const state = await readOr($, day.statePath)
  if (state === null) return { day, active: false as const }
  const diary = (await readOr($, day.diaryPath)) ?? ''
  return { day, active: true as const, items: parseItems(diary), runs: parseRunState(state) }
}

const flags = { lastNeeds: null as Set<string> | null, isWatching: false, hasWatchFailed: false, hasRefreshFailed: false, isListing: false }

async function refresh($: EngineInterface) {
  const ctx = await load($)
  if (!ctx || !ctx.active) {
    $.ui.status(undefined)
    flags.lastNeeds = null
    await update($, view, () => EMPTY)
    return
  }
  const agents = (await $.agent.list()).map(a => ({ id: a.id, description: a.description, status: a.status }))
  const rows = joinRows(ctx.items, ctx.runs, agents)
  const status = statusLine(rows, (await read($, inbox)).pending)
  $.ui.status(status)
  await update($, view, () => ({ active: true, status, groups: panelGroups(rows) }))
  const fresh = flags.lastNeeds === null ? [] : newlyNeedsYou(flags.lastNeeds, rows)
  flags.lastNeeds = new Set(rows.filter(r => r.needsYou && r.key !== '').map(r => r.key))
  if (fresh.length > 0) {
    $.ui.toast(`needs you: ${fresh.join(', ')}`)
    await $.audio.play({ asset: 'sounds/needs-you.wav' }).catch(() => undefined)
  }
}

async function safeRefresh($: EngineInterface) {
  try {
    await refresh($)
    flags.hasRefreshFailed = false
  } catch (err) {
    if (!flags.hasRefreshFailed) $.ui.toast(`daily refresh: ${err instanceof Error ? err.message : String(err)}`)
    flags.hasRefreshFailed = true
  }
}

async function watch($: EngineInterface) {
  if (flags.isWatching) return
  flags.isWatching = true
  try {
    const ctx = await load($)
    if (!ctx || !ctx.active) return
    const ran = await $.process.run(
      ['/bin/sh', '-c', 'exec "$(command -v changes-since || echo "$HOME/.local/bin/changes-since")" --cursor run-day'],
      { timeoutMs: 60_000 },
    )
    if (ran.exitCode !== 0) {
      if (!flags.hasWatchFailed) {
        $.ui.toast(`changes-since failed (exit ${ran.exitCode}): ${ran.stderr.split('\n')[0]}`)
      }
      flags.hasWatchFailed = true
      return
    }
    flags.hasWatchFailed = false
    const { events } = parseEvents(ran.stdout)
    const eventCtx = {
      mrKeys: new Set([
        ...ctx.items.flatMap(i => mrKeysOf(i.line)),
        ...ctx.runs.flatMap(r => r.mrs.map(mrKeyFromRef)).filter(k => k !== ''),
      ]),
      ticketKeys: new Set(ctx.items.map(i => ticketKey(i.text)).filter(k => k !== '')),
    }
    const prompts: string[] = []
    const notes: string[] = []
    for (const ev of events) {
      try {
        const toast = formatToast(ev)
        const isPrompt = classify(ev, eventCtx) === 'prompt'
        const text = isPrompt ? formatPrompt(ev) : formatNote(ev)
        $.ui.toast(toast)
        if (isPrompt) prompts.push(text)
        else notes.push(text)
      } catch {
        $.ui.toast('daily watcher: skipped a malformed event')
      }
    }
    if (prompts.length > 0) {
      void $.prompt.submit({ text: prompts.join('\n') }).catch(() => $.ui.toast('daily watcher: prompt submit failed'))
    }
    for (const text of notes) {
      try {
        await $.session.append({ message: { type: 'user', content: [{ type: 'text', text }] } })
      } catch {
        $.ui.toast(text)
      }
    }
  } catch (err) {
    if (!flags.hasWatchFailed) $.ui.toast(`daily watcher: ${err instanceof Error ? err.message : String(err)}`)
    flags.hasWatchFailed = true
  } finally {
    flags.isWatching = false
  }
}

async function watchInbox($: EngineInterface) {
  if (flags.isListing) return
  flags.isListing = true
  try {
    const ctx = await load($)
    if (!ctx || !ctx.active) return
    const ran = await $.process.run(['/bin/sh', '-c', INBOX_LS], { timeoutMs: 10_000 })
    if (ran.exitCode !== 0) return
    const before = await read($, inbox)
    const { fresh, state } = nextInbox(parseListing(ran.stdout), before.seen)
    await update($, inbox, () => state)
    if (fresh.length > 0) {
      $.ui.toast(`inbox: ${fresh.length} new`)
      void $.prompt.submit({ text: inboxPrompt(fresh.length) }).catch(() => $.ui.toast('daily inbox: prompt submit failed'))
    }
  } catch {
    return
  } finally {
    flags.isListing = false
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'plan', description: 'Toggle the run-day plan band above the prompt' })
    $.clock.every(REFRESH_MS, () => {
      void safeRefresh($)
    })
    $.clock.every(WATCH_MS, () => {
      void watch($)
    })
    $.clock.every(INBOX_MS, () => {
      void watchInbox($)
    })
    return next(e)
  })

  on('command.run', { command: 'plan' }, async $ => {
    const next = !(await read($, isExpanded))
    await update($, isExpanded, () => next)
    await update($, bandOffset, () => null)
    return { text: next ? 'Plan band expanded.' : 'Plan band collapsed.' }
  }).catch(() => ({ text: 'Plan band toggle failed.' }))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const v = await read($, view)
    if (e.props.hasSurvey || !v.active || !(await read($, isExpanded))) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const band = bandRows(v.groups, await read($, bandOffset))
    return (
      <Box flexDirection="column">
        <Text bold wrap="truncate">
          {band.header}
        </Text>
        {band.rows.map((r, i) =>
          r.kind === 'group' ? (
            <Text key={i} bold wrap="truncate">
              {r.text}
            </Text>
          ) : (
            <Text
              key={i}
              color={r.needsYou ? 'yellow' : undefined}
              dimColor={r.marker === 'x' || r.marker === '>'}
              wrap="truncate"
            >
              [{r.marker}] {r.text}
            </Text>
          ),
        )}
      </Box>
    )
  })

  on('ui.scroll', { component: 'AbovePrompt' }, async ($, e) => {
    const v = await read($, view)
    if (!v.active || !(await read($, isExpanded))) return {}
    const band = bandRows(v.groups, await read($, bandOffset))
    const to = Math.min(band.maxOffset, Math.max(0, band.offset + e.by))
    await update($, bandOffset, () => to)
    $.ui.invalidate('ui.render')
    return {}
  })

  for (const tool of ['Edit', 'Write'] as const) {
    on('tool.call', { tool }, async ($, e, next) => {
      if (!/\/wiki\/diary\/\d{4}-\d{2}-\d{2}\.md$/.test(e.file_path)) return next(e)
      const day = await today($)
      if (!day || !isTodaysDiary(e.file_path, day.today)) return next(e)
      if (!(await $.fs.exists(day.statePath))) return next(e)
      const current = (await readOr($, e.file_path)) ?? ''
      const after = applyEdit(current, e as unknown as EditInput)
      if (after === null) return next(e)
      const verdict = checkTicks(current, after)
      return verdict.ok ? next(e) : { deny: denyMessage(verdict.lines) }
    }).catch(($, e, next) => next(e))
  }
}
