import { ticketKey, UNPLANNED } from './diary.ts'
import type { AgentLite, Band, Item, PanelGroup, Row, RunItem } from './types.ts'

const LIVE = new Set(['pending', 'running', 'waiting'])
export const BAND_WINDOW_ROWS = 16
const ORDER = ['Merge', 'First', 'Today', 'If time', UNPLANNED]

function byKey(agents: AgentLite[], key: string): AgentLite | null {
  const re = new RegExp(`(?<![a-z0-9-])${key.replace(/[^a-z0-9-]/g, '\\$&')}(?![a-z0-9-])`)
  const hits = agents.filter(a => re.test(a.description.toLowerCase()))
  return hits.find(a => LIVE.has(a.status)) ?? hits[0] ?? null
}

export function joinRows(items: Item[], runs: RunItem[], agents: AgentLite[]): Row[] {
  return items.map(item => {
    const key = ticketKey(item.text)
    const run = key ? (runs.find(r => r.key === key) ?? null) : null
    const agent = run
      ? (agents.find(a => run.agent !== '' && a.id === run.agent) ?? byKey(agents, run.key))
      : null
    return {
      key,
      item,
      run,
      agent,
      needsYou: run !== null && run.needsYou && item.marker !== 'x',
      running: agent !== null && LIVE.has(agent.status) && !run?.owner.startsWith('external:'),
    }
  })
}

export function statusLine(rows: Row[], inbox = 0): string {
  const done = rows.filter(r => r.item.marker === 'x').length
  const running = rows.filter(r => r.running).length
  const needs = rows.filter(r => r.needsYou).length
  let line = `day ${done}/${rows.length}`
  if (running > 0) line += ` · ⚙ ${running} running`
  if (needs > 0) line += ` · ✋ ${needs} needs you`
  if (inbox > 0) line += ` · 📥 ${inbox}`
  return line
}

export function panelGroups(rows: Row[]): PanelGroup[] {
  const names = [...new Set(rows.map(r => r.item.group))]
  names.sort((a, b) => {
    const ia = ORDER.indexOf(a)
    const ib = ORDER.indexOf(b)
    return (ia < 0 ? ORDER.length : ia) - (ib < 0 ? ORDER.length : ib)
  })
  return names.map(group => ({
    group: group || 'Other',
    rows: rows
      .filter(r => r.item.group === group)
      .map(r => ({
        marker: r.item.marker,
        text: r.item.text,
        needsYou: r.needsYou,
        badges: [
          ...(r.running ? ['⚙ running'] : []),
          ...(r.needsYou ? ['✋ needs you'] : []),
          ...(r.run && r.run.owner.startsWith('external:') ? ['↗ with you'] : []),
          ...(r.run && r.run.mrs.length > 0 ? [r.run.mrs[0]] : []),
        ],
      })),
  }))
}

const MD_LINK = /\[([^\]]*)\]\([^)\s]*\)/g

export function shortenLinks(text: string): string {
  return text.replace(MD_LINK, '$1')
}

const isOpen = (marker: string) => marker !== 'x' && marker !== '>'

export function planRows(groups: PanelGroup[]): BandRow[] {
  return groups.flatMap(g => [
    { kind: 'group' as const, marker: ' ' as const, text: g.group, needsYou: false },
    ...g.rows.map(r => ({ kind: 'item' as const, marker: r.marker, text: shortenLinks(r.text), needsYou: r.needsYou })),
  ])
}

export function initialOffset(rows: BandRow[]): number {
  const at = rows.findIndex(r => r.kind === 'item' && isOpen(r.marker))
  if (at < 0) return 0
  for (let i = at; i >= 0; i--) if (rows[i].kind === 'group') return i
  return 0
}

export function ownsScroll(isActive: boolean, isExpanded: boolean, maxOffset: number): boolean {
  return isActive && isExpanded && maxOffset > 0
}

export function bandRows(groups: PanelGroup[], offset: number | null = null, max = BAND_WINDOW_ROWS): Band {
  const rows = planRows(groups)
  const items = rows.filter(r => r.kind === 'item')
  const done = items.filter(r => r.marker === 'x').length
  const maxOffset = Math.max(0, rows.length - max)
  const start = Math.min(maxOffset, Math.max(0, offset ?? initialOffset(rows)))
  const shown = rows.slice(start, start + max)
  const position = rows.length > max ? ` · ${start + 1}-${start + shown.length} of ${rows.length} ↕` : ''
  return { header: `plan · ${done}/${items.length} done${position}`, rows: shown, offset: start, maxOffset }
}

export function newlyNeedsYou(before: Set<string>, rows: Row[]): string[] {
  return rows.filter(r => r.needsYou && r.key !== '' && !before.has(r.key)).map(r => r.key)
}
