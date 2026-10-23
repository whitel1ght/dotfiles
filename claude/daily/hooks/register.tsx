import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import { mrKeyFromRef, mrKeysOf, parseItems, ticketKey } from '../mod/diary.ts'
import { classify, formatNote, formatPrompt, formatToast, parseEvents } from '../mod/events.ts'
import { EMPTY_INBOX, inboxPrompt, nextInbox, parseListing } from '../mod/inbox.ts'
import { applyEdit, checkTicks, denyMessage, isTodaysDiary } from '../mod/guard.ts'
import type { EditInput } from '../mod/guard.ts'
import { claimsDay, claimsDayPrompt, formatOwner, ownerNote, ownerPath, parseOwner, receivesPings } from '../mod/owner.ts'
import { parseRunState } from '../mod/runstate.ts'
import { isWarm, nextWarm, pingFailure, REPORT_MARK, WARM_PROMPT } from '../mod/warm.ts'
import type { InboxState, ViewState } from '../mod/types.ts'
import { joinRows, newlyNeedsYou, panelGroups, statusLine } from '../mod/view.ts'

const REFRESH_MS = 5_000
const WATCH_MS = 180_000
const TIMEOUTS_BEFORE_FRICTION = 3
const CHANGES_SINCE_TIMED_OUT = 75
const INBOX_MS = 30_000
const DAY_PLAN = 'exec "$(command -v day-plan || echo "$HOME/.local/bin/day-plan")"'
const INBOX_LS = 'ls -1 "$HOME/.local/state/run-day/inbox" 2>/dev/null; true'
const FRICTION = 'F="$(command -v friction || echo "$HOME/.local/bin/friction")"; [ -x "$F" ] && exec "$F" "$@" || true'
const EMPTY: ViewState = { active: false, status: '', groups: [] }
const view = atom({ plugin: 'daily', key: 'view' } as const, EMPTY)
const inbox = atom({ plugin: 'daily', key: 'inbox' } as const, EMPTY_INBOX as InboxState)

type Day = { home: string; today: string; diaryPath: string; statePath: string; ownerPath: string }

async function today($: EngineInterface): Promise<Day | null> {
  const home = await $.env.get('HOME')
  if (!home) return null
  const ran = await $.process.run(['date', '+%F'])
  if (ran.exitCode !== 0) return null
  const day = ran.stdout.trim()
  const stateDir = `${home}/.local/state/run-day`
  return {
    home,
    today: day,
    diaryPath: `${home}/wiki/diary/${day}.md`,
    statePath: `${stateDir}/${day}.md`,
    ownerPath: ownerPath(stateDir, day),
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

// Inbox and event prompts go only to the session that ran /run-day last (F-057); the others
// count the inbox for their status line only and never move the changes-since cursor.
async function isOwner($: EngineInterface, day: Day): Promise<boolean> {
  return receivesPings(parseOwner(await readOr($, day.ownerPath)), await $.session.id())
}

async function claimDay($: EngineInterface) {
  try {
    const day = await today($)
    if (day) await $.fs.write(day.ownerPath, formatOwner(await $.session.id()))
    // Re-running /daily:run-day restarts a keepwarm that stopped (a failed ping, yesterday's report).
    warm.stopped = null
    warm.wasCold = false
  } catch (err) {
    const why = `run-day owner not recorded: ${err instanceof Error ? err.message : String(err)}`
    $.ui.toast(`daily: ${why}`)
    friction($, 'tool_error', why, 'daily-owner')
  }
}

// Keepwarm for the day session after cache-tax's 6 h window (mod/warm.ts). One timer at a time,
// re-armed after every main-thread turn and every warm ping; a late timer (sleep) re-checks first.
const warm = {
  startedAt: 0,
  lastRequestAt: null as number | null,
  timer: null as { cancel: () => void } | null,
  stopped: null as string | null,
  wasCold: false,
  isPinging: false,
  hasFollowed: false,
  gen: 0,
}

function disarmWarm() {
  warm.timer?.cancel()
  warm.timer = null
}

function stopWarm($: EngineInterface, why: string) {
  disarmWarm()
  warm.stopped = why
  $.ui.log(`daily keepwarm stopped: ${why}`)
}

// The newest call wins: one started while another awaited supersedes it, so only one timer lives.
async function armWarm($: EngineInterface) {
  const gen = ++warm.gen
  disarmWarm()
  if (warm.stopped !== null || warm.isPinging) return
  const day = await today($)
  if (!day || (await readOr($, day.statePath)) === null || !(await isOwner($, day))) return
  const step = nextWarm({
    isOwner: true,
    dayEnded: ((await readOr($, day.diaryPath)) ?? '').includes(REPORT_MARK),
    startedAt: warm.startedAt,
    lastRequestAt: warm.lastRequestAt,
    now: await $.clock.now(),
  })
  if (gen !== warm.gen) return
  disarmWarm()
  if (step.do === 'cold' && !warm.wasCold) $.ui.log('daily keepwarm: the cache went cold while idle; warming resumes after the next turn')
  warm.wasCold = step.do === 'cold'
  if (step.do === 'stop') stopWarm($, step.why)
  else if (step.do === 'wait') warm.timer = $.clock.after(step.ms, () => void safeArmWarm($))
  else if (step.do === 'ping') await pingWarm($)
}

async function pingWarm($: EngineInterface) {
  warm.isPinging = true
  let why: string | null
  try {
    why = pingFailure(await $.model.fork({ prompt: WARM_PROMPT }))
  } catch (err) {
    why = `the ping failed: ${err instanceof Error ? err.message : String(err)}`
  } finally {
    warm.isPinging = false
  }
  if (why !== null) return stopWarm($, why)
  warm.lastRequestAt = await $.clock.now()
  await armWarm($)
}

async function safeArmWarm($: EngineInterface) {
  try {
    await armWarm($)
  } catch (err) {
    stopWarm($, err instanceof Error ? err.message : String(err))
  }
}

const flags = { lastNeeds: null as Set<string> | null, isWatching: false, timeouts: 0, hasWatchFailed: false, hasRefreshFailed: false, isListing: false, hasInboxFailed: false }

// Fire-and-forget: a missing or failing friction must never slow or change the caller.
function friction($: EngineInterface, kind: string, msg: string, source = 'changes-since') {
  try {
    const argv = ['/bin/sh', '-c', FRICTION, 'friction', '--harness', 'claude', '--source', source, kind, msg.replace(/\s+/g, ' ').slice(0, 300)]
    void $.process.run(argv, { timeoutMs: 5_000 }).catch(() => undefined)
  } catch {
    // swallowed on purpose
  }
}

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
  const note = ownerNote(parseOwner(await readOr($, ctx.day.ownerPath)), await $.session.id())
  const status = statusLine(rows, (await read($, inbox)).pending) + (note ? ` · ${note}` : '')
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

// A timed-out tick is not a failure: the next tick tries again, and friction is
// recorded once when it keeps happening.
function skipTick($: EngineInterface, why: string) {
  flags.timeouts++
  if (flags.timeouts === TIMEOUTS_BEFORE_FRICTION) friction($, 'timeout', `${why} (${flags.timeouts} ticks in a row)`)
}

async function watch($: EngineInterface) {
  if (flags.isWatching) return
  flags.isWatching = true
  try {
    const ctx = await load($)
    if (!ctx || !ctx.active || !(await isOwner($, ctx.day))) return
    const ran = await $.process.run(
      ['/bin/sh', '-c', 'exec "$(command -v changes-since || echo "$HOME/.local/bin/changes-since")" --cursor run-day'],
      { timeoutMs: 60_000 },
    )
    if (ran.exitCode === CHANGES_SINCE_TIMED_OUT || ran.exitCode === 124) {
      skipTick($, `changes-since timed out (exit ${ran.exitCode}): ${ran.stderr.split('\n')[0]}`)
      return
    }
    flags.timeouts = 0
    if (ran.exitCode !== 0) {
      // changes-since logs its own service_down
      if (!flags.hasWatchFailed) $.ui.toast(`changes-since failed (exit ${ran.exitCode}): ${ran.stderr.split('\n')[0]}`)
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
    const why = err instanceof Error ? err.message : String(err)
    if (/timed? ?out|still running after/i.test(why)) {
      skipTick($, `daily watcher: ${why}`)
    } else {
      if (!flags.hasWatchFailed) {
        $.ui.toast(`daily watcher: ${why}`)
        friction($, 'tool_error', `daily watcher: ${why}`)
      }
      flags.hasWatchFailed = true
    }
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
    // Every session counts the inbox for its status line; only the owner is told.
    const owns = await isOwner($, ctx.day)
    const ran = await $.process.run(['/bin/sh', '-c', INBOX_LS], { timeoutMs: 10_000 })
    if (ran.exitCode !== 0) {
      if (!flags.hasInboxFailed) friction($, 'tool_error', `inbox read failed (exit ${ran.exitCode}): ${ran.stderr.split('\n')[0]}`, 'daily-inbox')
      flags.hasInboxFailed = true
      return
    }
    flags.hasInboxFailed = false
    const before = await read($, inbox)
    const { fresh, state } = nextInbox(parseListing(ran.stdout), before.seen)
    await update($, inbox, () => state)
    if (owns && fresh.length > 0) {
      $.ui.toast(`inbox: ${fresh.length} new`)
      void $.prompt.submit({ text: inboxPrompt(fresh.length) }).catch(() => $.ui.toast('daily inbox: prompt submit failed'))
    }
  } catch (err) {
    if (!flags.hasInboxFailed) friction($, 'tool_error', `inbox read failed: ${err instanceof Error ? err.message : String(err)}`, 'daily-inbox')
    flags.hasInboxFailed = true
    return
  } finally {
    flags.isListing = false
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    warm.startedAt = await $.clock.now()
    try {
      await $.command.register({ name: 'day-plan', description: "Open today's plan in nvim in a tmux popup" })
    } catch (err) {
      $.ui.log(`daily: /day-plan not registered: ${err instanceof Error ? err.message : String(err)}`)
    }
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

  on('command.run', { command: 'day-plan' }, async $ => {
    const ran = await $.process.run(['/bin/sh', '-c', DAY_PLAN], { timeoutMs: 5_000 })
    if (ran.exitCode === 0) return { text: 'Plan popup opened.' }
    const line = (ran.stderr || ran.stdout).split('\n')[0].trim() || `exit ${ran.exitCode}`
    const why = line.startsWith('day-plan') ? line : `day-plan: ${line}`
    $.ui.toast(why)
    return { text: why }
  }).catch($ => {
    $.ui.toast('day-plan failed')
    return { text: 'day-plan failed.' }
  })

  for (const command of ['run-day', 'daily:run-day'] as const) {
    on('command.run', { command }, async ($, e, next) => {
      if (claimsDay(e.command, e.args)) await claimDay($)
      return next(e)
    })
  }

  // Backup for a build where a plugin's markdown command does not raise command.run.
  on('prompt.submit', async ($, e, next) => {
    if (e.origin?.kind !== 'plugin' && claimsDayPrompt(e.text)) await claimDay($)
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    if (!e.agentId) warm.lastRequestAt = await $.clock.now()
    yield* next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (!e.agentId) {
      warm.lastRequestAt = await $.clock.now()
      void safeArmWarm($)
    }
    return r
  })

  // cache-tax's pings are forks too: a warm one moves the clock the hand-over at 6 h starts from.
  on('model.fork', async ($, e, next) => {
    const r = await next(e)
    if (r && r.isAnswered && isWarm(r.usage) && !warm.isPinging) {
      if (!warm.hasFollowed) $.ui.log("daily keepwarm: following another plugin's warm ping")
      warm.hasFollowed = true
      warm.lastRequestAt = await $.clock.now()
      void safeArmWarm($)
    }
    return r
  })

  on('session.compact', async ($, e, next) => {
    const r = await next(e)
    if (!e.agentId) {
      warm.lastRequestAt = null
      disarmWarm()
    }
    return r
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
      const verdict = checkTicks(current, after, msg => friction($, 'guard', msg, 'daily-guard'))
      return verdict.ok ? next(e) : { deny: denyMessage(verdict.lines) }
    }).catch(($, e, next) => next(e))
  }
}
