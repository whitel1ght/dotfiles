import { ticketKey, UNPLANNED } from './diary.ts'
import type { AgentLite, Band, Item, PanelGroup, Row, RunItem } from './types.ts'

const LIVE = new Set(['pending', 'running', 'waiting'])
export const BAND_MAX_ROWS = 12
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

export function bandRows(groups: PanelGroup[], max = BAND_MAX_ROWS): Band {
  const all = groups.flatMap(g => g.rows)
  const done = all.filter(r => r.marker === 'x').length
  const open = groups.flatMap(g =>
    g.rows
      .filter(r => r.marker !== 'x' && r.marker !== '>')
      .map((r, i) => ({ group: i === 0 ? g.group : '', marker: r.marker, text: r.text, needsYou: r.needsYou })),
  )
  const room = max - 1
  const fits = open.length <= room
  const shown = fits ? open : open.slice(0, room - 1)
  return {
    header: `plan · ${done}/${all.length} done`,
    rows: shown,
    footer: fits ? null : `+${open.length - shown.length} more · /plan to hide`,
  }
}

export function newlyNeedsYou(before: Set<string>, rows: Row[]): string[] {
  return rows.filter(r => r.needsYou && r.key !== '' && !before.has(r.key)).map(r => r.key)
}
