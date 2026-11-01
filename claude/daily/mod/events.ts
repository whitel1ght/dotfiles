import { mrKey } from './diary.ts'
import type { DayEvent } from './types.ts'

export type EventContext = { mrKeys: Set<string>; ticketKeys: Set<string> }
export type Disposition = 'prompt' | 'note'

const THREAD_KINDS = new Set(['review', 'comment', 'pipeline_failed'])

export function parseEvents(stdout: string): { events: DayEvent[]; bad: number } {
  const events: DayEvent[] = []
  let bad = 0
  for (const line of stdout.split('\n')) {
    if (line.trim() === '') continue
    try {
      const v: unknown = JSON.parse(line)
      if (typeof v === 'object' && v !== null && typeof (v as { kind?: unknown }).kind === 'string') {
        events.push(v as DayEvent)
      } else {
        bad += 1
      }
    } catch {
      bad += 1
    }
  }
  return { events, bad }
}

export function eventMrKey(ev: DayEvent): string {
  if (ev.mr === undefined || ev.mr === null || ev.mr === '' || !ev.repo) return ''
  const iid = Number(String(ev.mr).replace(/^!/, ''))
  return Number.isFinite(iid) ? mrKey(str(ev.repo), iid) : ''
}

export function classify(ev: DayEvent, ctx: EventContext): Disposition {
  const ticket = str(ev.ticket).toLowerCase()
  if (ev.kind === 'assigned') return ticket !== '' && ctx.ticketKeys.has(ticket) ? 'note' : 'prompt'
  if (!THREAD_KINDS.has(ev.kind)) return 'note'
  const key = eventMrKey(ev)
  if (key !== '') return ctx.mrKeys.has(key) ? 'prompt' : 'note'
  return ticket !== '' && ctx.ticketKeys.has(ticket) ? 'prompt' : 'note'
}

const str = (x: unknown): string => String(x ?? '')

const clean = (s: unknown, max: number): string => {
  const one = str(s).replace(/\s*\|\s*/g, ' / ').replace(/\s+/g, ' ').trim()
  return one.length > max ? `${one.slice(0, max - 1)}…` : one
}

export function formatPrompt(ev: DayEvent, tag = 'daily-event'): string {
  const mr = eventMrKey(ev) || '-'
  return `[${tag}] ${ev.kind} | ${mr} | ${str(ev.ticket) || '-'} | ${clean(ev.summary, 160)} | ${str(ev.url) || '-'}`
}

export function formatNote(ev: DayEvent): string {
  return formatPrompt(ev, 'daily-event:info')
}

export function formatToast(ev: DayEvent): string {
  const where = [str(ev.ticket), eventMrKey(ev)].filter(Boolean).join(' ')
  const head = `${ev.kind.replace(/_/g, ' ')}${where ? ` ${where}` : ''}`
  const text = str(ev.summary) ? `${head}: ${clean(ev.summary, 100)}` : head
  return text.length > 140 ? `${text.slice(0, 139)}…` : text
}
