import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import { mrKeyFromRef, mrKeysOf, parseItems, ticketKey } from '../mod/diary.ts'
import { classify, formatNote, formatPrompt, formatToast, isTimeout, parseEvents } from '../mod/events.ts'
import { EMPTY_INBOX, inboxPrompt, nextInbox, parseListing } from '../mod/inbox.ts'
import { applyEdit, checkTicks, denyMessage, isTodaysDiary } from '../mod/guard.ts'
import type { EditInput } from '../mod/guard.ts'
import { claimsDay, claimsDayPrompt, formatOwner, ownerNote, ownerPath, parseOwner, receivesPings } from '../mod/owner.ts'
import { parseRunState } from '../mod/runstate.ts'
import { isWarm, nextWarm, pingFailure, REPORT_MARK, TTL_MS, WARM_PROMPT } from '../mod/warm.ts'
import { agentRows, formatAgents, isFullWake, outstanding, parseGraphics, parseLid, sleptBetween, STUCK_MS, stuckPrompt, stuckRows, wakePrompt } from '../mod/wake.ts'
import type { AgentRow } from '../mod/wake.ts'
import type { InboxState, RunItem, ViewState } from '../mod/types.ts'
import { joinRows, newlyNeedsYou, panelGroups, statusLine } from '../mod/view.ts'
import { NUDGE_TEXT, claimsSystem, claimsSystemPrompt, shouldNudge, systemMarkerPath } from '../mod/ideas.ts'
import { BUSY_PROMPT, nextNudged, shouldNudgeBusy } from '../mod/busy.ts'
import { CLAUDE_PLAYBOOK, UPDATE_ARGS, fingerprint, parsePrint, playbookPath, shouldResume } from '../mod/update.ts'
import { ASK_NUDGE, BUSY_NOTE, FORM_DENY, FORM_TOOLS, isBusyPrompt, nextAsk, shouldNudgeAsk } from '../mod/ask.ts'
import { FOLLOWUP_MS, followupPrompt, parseCards, pendingFollowups } from '../mod/followup.ts'

const REFRESH_MS = 5_000
const WATCH_MS = 180_000
const TIMEOUTS_BEFORE_FRICTION = 3
const CHANGES_SINCE_TIMED_OUT = 75
const INBOX_MS = 30_000
const DAY_PLAN = 'exec "$(command -v day-plan || echo "$HOME/.local/bin/day-plan")"'
const INBOX_LS = 'ls -1 "$HOME/.local/state/run-day/inbox" 2>/dev/null; true'
const FRICTION = 'F="$(command -v friction || echo "$HOME/.local/bin/friction")"; [ -x "$F" ] && exec "$F" "$@" || true'
const LID = ['/usr/sbin/ioreg', '-r', '-k', 'AppleClamshellState', '-d', '1']
const SYSTEM_STATE = ['/usr/bin/pmset', '-g', 'systemstate']
const COLD_RELAY = 'daily: relayed past the cold-cache guard'
const IDEAS_MS = 60_000
const IDEAS_DUE = 'I="$(command -v ideas || echo "$HOME/.local/bin/ideas")"; [ -x "$I" ] && exec "$I" due --sync --limit 3 || echo "[]"'
const BLIND_PROBES = 3
const DECIDE_LIST = 'D="$(command -v decide || echo "$HOME/.local/bin/decide")"; [ -x "$D" ] && exec "$D" list --json || true'
const EMPTY: ViewState = { active: false, status: '', groups: [] }
const view = atom({ plugin: 'daily', key: 'view' } as const, EMPTY)
const inbox = atom({ plugin: 'daily', key: 'inbox' } as const, EMPTY_INBOX as InboxState)

type Day = { home: string; today: string; diaryPath: string; statePath: string; ownerPath: string; agentsPath: string; playbookPath: string }

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
    agentsPath: `${stateDir}/${day}.agents`,
    playbookPath: playbookPath(stateDir, day),
  }
}

// The playbook and briefs as the plugin folder holds them now (mod/update.ts).
async function currentPrint($: EngineInterface): Promise<string> {
  const top = $.plugin.root.replace(/\/claude\/daily\/?$/, '')
  return fingerprint(await Promise.all(CLAUDE_PLAYBOOK.map(async p => (await readOr($, `${top}/${p}`)) ?? '')))
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
  return { day, active: true as const, items: parseItems(diary), runs: parseRunState(state), dayEnded: diary.includes(REPORT_MARK) }
}

type DayCtx = Extract<NonNullable<Awaited<ReturnType<typeof load>>>, { active: true }>

// Inbox and event prompts go only to the session that ran /run-day last (F-057); the others
// count the inbox for their status line only and never move the changes-since cursor.
async function isOwner($: EngineInterface, day: Day): Promise<boolean> {
  return receivesPings(parseOwner(await readOr($, day.ownerPath)), await $.session.id())
}

// The day session while the day runs: today's run state, this session owns it, no report yet.
async function runningDay($: EngineInterface): Promise<DayCtx | null> {
  const ctx = await load($)
  if (!ctx || !ctx.active || ctx.dayEnded || !(await isOwner($, ctx.day))) return null
  return ctx
}

async function claimDay($: EngineInterface) {
  try {
    const day = await today($)
    if (day) await $.fs.write(day.ownerPath, formatOwner(await $.session.id()))
    if (day) await $.fs.write(day.playbookPath, `${await currentPrint($)}\n`)
    // Re-running /daily:run-day restarts a keepwarm that stopped (a failed ping, yesterday's report).
    warm.stopped = null
    warm.wasCold = false
    // After a restart the agents file is the dead process's: the resume's Wake check reads this one.
    const ctx = await runningDay($)
    if (ctx) await refreshAgents($, ctx)
  } catch (err) {
    const why = `run-day owner not recorded: ${err instanceof Error ? err.message : String(err)}`
    $.ui.toast(`daily: ${why}`)
    friction($, 'tool_error', why, 'daily-owner')
  }
}

// A merge that changed the playbook or a brief reloads this mod (the plugin folder is watched,
// CLAUDE_CODE_PLUGIN_DIRS) and so reaches session.start: the day session resumes the day once
// with the new text (mod/update.ts). The new print is written first, so it resumes only once.
async function resumeIfUpdated($: EngineInterface) {
  try {
    const day = await today($)
    if (!day || !(await isOwner($, day))) return
    const ctx = await runningDay($)
    if (!ctx) return
    const recorded = parsePrint(await readOr($, ctx.day.playbookPath))
    const current = await currentPrint($)
    if (!shouldResume({ isOwner: true, dayRunning: true, recorded, current })) return
    await $.fs.write(ctx.day.playbookPath, `${current}\n`)
    $.ui.log('daily: the run-day playbook changed; resuming the day with it')
    $.clock.after(0, () => void $.command.run({ command: 'daily:run-day', args: UPDATE_ARGS }).catch(() => $.ui.toast('daily: resuming the day after a playbook change failed: run /daily:run-day')))
  } catch (err) {
    $.ui.log(`daily: playbook check failed: ${err instanceof Error ? err.message : String(err)}`)
  }
}

// The system session (marked by /daily:system) reviews ideas when idle (mod/ideas.ts): one nudge
// per idle stretch, then none until the user writes again.
const idle = { lastUserAt: 0, lastTurnEndAt: 0, waiting: false, isChecking: false }

async function markerPath($: EngineInterface): Promise<string | null> {
  const home = await $.env.get('HOME')
  return home ? systemMarkerPath(`${home}/.local/state`) : null
}

async function claimSystem($: EngineInterface) {
  try {
    const path = await markerPath($)
    if (!path) return
    await $.process.run(['mkdir', '-p', path.slice(0, path.lastIndexOf('/'))])
    await $.fs.write(path, formatOwner(await $.session.id()))
  } catch (err) {
    const why = `system session not recorded: ${err instanceof Error ? err.message : String(err)}`
    $.ui.toast(`daily: ${why}`)
    friction($, 'tool_error', why, 'daily-ideas')
  }
}

async function nudgeIdeas($: EngineInterface) {
  if (idle.isChecking) return
  idle.isChecking = true
  try {
    const path = await markerPath($)
    const isSystem = path !== null && parseOwner(await readOr($, path)) === (await $.session.id())
    const running = (await $.agent.list().catch(() => [])).filter(a => a.status === 'running').length
    const now = await $.clock.now()
    if (!shouldNudge({ isSystem, now, lastUserAt: idle.lastUserAt, lastTurnEndAt: idle.lastTurnEndAt, agentsRunning: running, waiting: idle.waiting })) return
    const userAt = idle.lastUserAt
    const ran = await $.process.run(['/bin/sh', '-c', IDEAS_DUE], { timeoutMs: 30_000 })
    if (ran.exitCode !== 0 || !/^\s*\[\s*\{/.test(ran.stdout)) return
    // the user may have written while `ideas due` ran
    if (idle.waiting || idle.lastUserAt !== userAt) return
    idle.waiting = true
    void $.prompt.submit({ text: NUDGE_TEXT }).catch(() => $.ui.toast('daily ideas: prompt submit failed'))
  } catch (err) {
    $.ui.log(`daily ideas: idle check failed: ${err instanceof Error ? err.message : String(err)}`)
  } finally {
    idle.isChecking = false
  }
}

// The day session idle with no agent gets one Keep busy prompt per idle stretch (mod/busy.ts).
// A turn counts as running between its first step and turn.complete (a long tool call makes no
// requests); a turn that never completes stops counting after TURN_STALE_MS.
const TURN_STALE_MS = 30 * 60 * 1000
const busy = { nudged: false, inTurn: false }

// Every session, not only the day's: questions go to the decisions deck (mod/ask.ts).
let ask = { asked: false, nudged: false }

// Every session: the user's follow-ups on its answer cards come back as a prompt, once each
// (mod/followup.ts). A failing or missing decide is no follow-ups.
const followups = { delivered: new Map<string, number>(), isChecking: false }

async function deliverFollowups($: EngineInterface) {
  if (followups.isChecking) return
  followups.isChecking = true
  try {
    const ran = await $.process.run(['/bin/sh', '-c', DECIDE_LIST], { timeoutMs: 10_000 })
    if (ran.exitCode !== 0) return
    const due = pendingFollowups(parseCards(ran.stdout), await $.session.id(), followups.delivered)
    if (due.length === 0) return
    const sent = await $.prompt.submit({ text: followupPrompt(due) }).then(
      () => true,
      () => false,
    )
    if (sent) for (const c of due) followups.delivered.set(c.id, c.discussion_count)
    else $.ui.toast('daily: delivering a decisions follow-up failed; the next check retries')
  } catch {
    // the next tick tries again
  } finally {
    followups.isChecking = false
  }
}

async function runningAgents($: EngineInterface): Promise<number> {
  return (await $.agent.list().catch(() => [])).filter(a => a.status === 'running').length
}

async function nudgeBusy($: EngineInterface, ctx: DayCtx) {
  const out = outstanding(ctx.runs).length
  busy.nudged = nextNudged(busy.nudged, { outstanding: out, userWrote: false })
  const now = await $.clock.now()
  const lastActiveAt = Math.max(idle.lastUserAt, idle.lastTurnEndAt, warm.lastRequestAt ?? 0)
  const turnRunning = busy.inTurn && now - lastActiveAt < TURN_STALE_MS
  const running = (await $.agent.list().catch(() => [])).filter(a => a.status === 'running').length + (turnRunning ? 1 : 0)
  const state = { isOwner: true, dayRunning: !ctx.dayEnded, now, lastActiveAt, outstanding: out, agentsRunning: running, nudged: busy.nudged }
  if (!shouldNudgeBusy(state)) return
  busy.nudged = true
  void $.prompt.submit({ text: BUSY_PROMPT }).catch(() => $.ui.toast('daily idle: prompt submit failed'))
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

// Waking from sleep (mod/wake.ts). With the lid closed macOS dark-wakes every ~15 min and the
// timers run in slices, so a gap between refresh ticks only arms the probe; the day session is
// nudged once, on the first tick that finds a full wake (lid open, display on).
const wake = {
  lastTickAt: null as number | null,
  pending: null as { since: number } | null,
  timer: null as { cancel: () => void } | null,
  gen: 0,
  subagents: null as { sessionId: string; dir: string } | null,
  hasAgentsFailed: false,
  blindProbes: 0,
}

async function probeWake($: EngineInterface) {
  const out = (argv: string[]) => $.process.run(argv, { timeoutMs: 2_000 }).then(r => (r.exitCode === 0 ? r.stdout : ''), () => '')
  const [lid, state] = await Promise.all([out(LID), out(SYSTEM_STATE)])
  return { lid: parseLid(lid), graphics: parseGraphics(state) }
}

// A session's transcripts sit under ~/.claude/projects/<slug>/<id>/subagents; the folder appears
// with its first subagent, so only a found one is cached (per session id: /clear makes a new one).
async function subagentsDir($: EngineInterface): Promise<string> {
  const sessionId = await $.session.id()
  if (wake.subagents?.sessionId === sessionId) return wake.subagents.dir
  if (!/^[\w-]+$/.test(sessionId)) return ''
  const ls = `ls -d "$HOME"/.claude/projects/*/${sessionId}/subagents 2>/dev/null | head -1`
  const ran = await $.process.run(['/bin/sh', '-c', ls], { timeoutMs: 2_000 }).catch(() => null)
  const dir = ran?.exitCode === 0 ? ran.stdout.trim() : ''
  if (dir) wake.subagents = { sessionId, dir }
  return dir
}

// Never rejects: what cannot be read shows as unknown or '-' in the file.
async function agentState($: EngineInterface, runs: RunItem[], now: number): Promise<AgentRow[]> {
  const ids = outstanding(runs).flatMap(r => [r.agent, r.round]).filter(id => id !== '')
  if (ids.length === 0) return []
  const listed = (await $.agent.list().catch(() => [])).map(a => ({ id: a.id, status: a.status }))
  const dir = await subagentsDir($)
  const quiet: Record<string, { ms: number | null; path: string }> = {}
  for (const id of ids) {
    const path = dir ? `${dir}/agent-${id}.jsonl` : ''
    const stat = path ? await $.fs.stat(path).catch(() => null) : null
    quiet[id] = stat ? { ms: now - stat.mtimeMs, path } : { ms: null, path: '' }
  }
  return agentRows(runs, listed, quiet)
}

async function writeAgents($: EngineInterface, day: Day, rows: AgentRow[], now: number) {
  try {
    await $.fs.write(day.agentsPath, `${formatAgents(rows, now)}\n`)
    wake.hasAgentsFailed = false
  } catch (err) {
    if (!wake.hasAgentsFailed) $.ui.log(`daily: agents file not written: ${err instanceof Error ? err.message : String(err)}`)
    wake.hasAgentsFailed = true
  }
}

function submitWake($: EngineInterface, text: string) {
  void $.prompt.submit({ text }).catch(() => $.ui.toast('daily wake: prompt submit failed'))
}

// Runs early on every refresh tick with the tick's time and the one before it, so a failure later
// in the tick cannot lose the sleep. Probes that read neither lid nor display give up on it.
async function checkWake($: EngineInterface, ctx: DayCtx, owns: boolean, prevTickAt: number | null, now: number) {
  if (!owns || ctx.dayEnded) {
    wake.pending = null
    wake.blindProbes = 0
    return
  }
  if (prevTickAt !== null && sleptBetween(prevTickAt, now)) wake.pending ??= { since: prevTickAt }
  if (wake.pending === null) return
  const { lid, graphics } = await probeWake($)
  if (lid === null && graphics === null) {
    if (++wake.blindProbes < BLIND_PROBES) return
    wake.blindProbes = 0
    wake.pending = null
    $.ui.log('daily wake: cannot read lid or display state; no wake nudge for this sleep')
    return
  }
  wake.blindProbes = 0
  if (!isFullWake(lid, graphics)) return
  // Another tick may have taken this wake while the probe ran.
  const taken = wake.pending
  if (taken === null) return
  wake.pending = null
  if (outstanding(ctx.runs).length === 0 && (await read($, inbox)).pending === 0) return
  const rows = await agentState($, ctx.runs, now)
  await writeAgents($, ctx.day, rows, now)
  submitWake($, wakePrompt(now - taken.since, rows, ctx.day.agentsPath))
  const gen = ++wake.gen
  wake.timer?.cancel()
  wake.timer = $.clock.after(STUCK_MS, () => void stuckFollowUp($, gen))
}

// One look, STUCK_MS after a nudge. Skipped when the machine slept again meanwhile: the next full
// wake nudges afresh.
async function stuckFollowUp($: EngineInterface, gen: number) {
  if (gen !== wake.gen) return
  wake.timer = null
  try {
    const now = await $.clock.now()
    if (wake.pending !== null || (wake.lastTickAt !== null && sleptBetween(wake.lastTickAt, now))) return
    const ctx = await runningDay($)
    if (!ctx) return
    const rows = await agentState($, ctx.runs, now)
    const stuck = stuckRows(rows)
    if (stuck.length === 0) return
    await writeAgents($, ctx.day, rows, now)
    submitWake($, stuckPrompt(stuck, ctx.day.agentsPath))
  } catch (err) {
    $.ui.log(`daily wake follow-up: ${err instanceof Error ? err.message : String(err)}`)
  }
}

async function refreshAgents($: EngineInterface, ctx: DayCtx) {
  const now = await $.clock.now()
  await writeAgents($, ctx.day, await agentState($, ctx.runs, now), now)
}

// A background task's notification in a cold day session (last request past the cache TTL).
async function isColdNotification($: EngineInterface, kind: string | undefined): Promise<boolean> {
  if (kind !== 'task-notification' || warm.lastRequestAt === null) return false
  if ((await $.clock.now()) - warm.lastRequestAt <= TTL_MS) return false
  return (await runningDay($)) !== null
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
  const now = await $.clock.now()
  const prevTickAt = wake.lastTickAt
  wake.lastTickAt = now
  const ctx = await load($)
  if (!ctx || !ctx.active) {
    wake.pending = null
    $.ui.status(undefined)
    flags.lastNeeds = null
    await update($, view, () => EMPTY)
    return
  }
  const owner = parseOwner(await readOr($, ctx.day.ownerPath))
  const sessionId = await $.session.id()
  await checkWake($, ctx, receivesPings(owner, sessionId), prevTickAt, now)
  const agents = (await $.agent.list()).map(a => ({ id: a.id, description: a.description, status: a.status }))
  const rows = joinRows(ctx.items, ctx.runs, agents)
  const note = ownerNote(owner, sessionId)
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
    if (isTimeout(why)) {
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
    if (owns && !ctx.dayEnded && outstanding(ctx.runs).length > 0) await refreshAgents($, ctx)
    if (owns && fresh.length > 0) {
      $.ui.toast(`inbox: ${fresh.length} new`)
      void $.prompt.submit({ text: inboxPrompt(fresh.length) }).catch(() => $.ui.toast('daily inbox: prompt submit failed'))
    } else if (owns) {
      await nudgeBusy($, ctx)
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
    idle.lastUserAt = await $.clock.now()
    $.clock.every(IDEAS_MS, () => {
      void nudgeIdeas($)
    })
    $.clock.every(FOLLOWUP_MS, () => {
      void deliverFollowups($)
    })
    void resumeIfUpdated($)
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

  for (const command of ['system', 'daily:system'] as const) {
    on('command.run', { command }, async ($, e, next) => {
      if (claimsSystem(e.command)) await claimSystem($)
      return next(e)
    })
  }

  // A cold task-notification is re-sent as this plugin's own prompt, past a cold-cache guard that
  // would hold it (cache-tax's, when it runs first); the Wake check covers the order not working.
  // The host refuses a submit from inside a prompt.submit hook, so it goes out on the next clock turn.
  // The claim is the backup for a build where a plugin's markdown command does not raise command.run.
  on('prompt.submit', async ($, e, next) => {
    if (await isColdNotification($, e.origin?.kind)) {
      const { text } = e
      $.clock.after(0, () => void $.prompt.submit({ text }).catch(() => $.ui.toast('daily: relaying a task notification failed')))
      return { drop: COLD_RELAY }
    }
    if (e.origin?.kind !== 'plugin' && claimsDayPrompt(e.text)) await claimDay($)
    if (e.origin?.kind !== 'plugin' && e.origin?.kind !== 'task-notification') {
      idle.lastUserAt = await $.clock.now()
      idle.waiting = false
      busy.nudged = false
      if (claimsSystemPrompt(e.text)) await claimSystem($)
      ask = nextAsk(ask, 'user')
      if (isBusyPrompt({ inTurn: e.turnId !== undefined, agentsRunning: await runningAgents($) })) {
        return next({ ...e, context: [...(e.context ?? []), BUSY_NOTE] })
      }
    }
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    if (!e.agentId) {
      warm.lastRequestAt = await $.clock.now()
      busy.inTurn = true
    }
    yield* next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (!e.agentId) {
      warm.lastRequestAt = await $.clock.now()
      idle.lastTurnEndAt = warm.lastRequestAt
      busy.inTurn = false
      void safeArmWarm($)
      if (shouldNudgeAsk({ isMain: true, reason: e.reason, text: r.text, ...ask })) {
        ask = nextAsk(ask, 'nudged')
        $.clock.after(0, () => void $.prompt.submit({ text: ASK_NUDGE }).catch(() => $.ui.toast('daily: the ask_user nudge failed')))
      }
    }
    return r
  })

  on('tool.call', async ($, e, next) => {
    if ((FORM_TOOLS as readonly string[]).includes(e.tool)) return { deny: FORM_DENY }
    ask = nextAsk(ask, 'tool', e.tool)
    return next(e)
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
