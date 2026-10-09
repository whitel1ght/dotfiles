import type { Item, Marker } from './types.ts'

const START = '<!-- start-day:start -->'
const END = '<!-- start-day:end -->'
const ITEM = /^- \[([ xX/!>])\] (.*)$/
const GROUP = /^\*\*(.+?)\*\*\s*$/
const TICKET = /\b([a-z]{2,10}-\d{2,6})\b/i
const MR_LINK = /\/([^/\s)]+)\/-\/merge_requests\/(\d+)/g
const MR_REF = /\[↗\]\[([^\]~]+)(?:~\d+)?\]/g

export const UNPLANNED = 'Unplanned'

export function extractBlock(md: string): string | null {
  const a = md.indexOf(START)
  if (a < 0) return null
  const from = a + START.length
  const b = md.indexOf(END, from)
  return b < 0 ? null : md.slice(from, b)
}

export function parseItems(md: string): Item[] {
  const block = extractBlock(md)
  if (block === null) return []
  const items: Item[] = []
  let group = ''
  for (const line of block.split('\n')) {
    const g = GROUP.exec(line)
    if (g) {
      group = g[1]
      continue
    }
    const m = ITEM.exec(line)
    if (!m) continue
    const marker = (m[1] === 'X' ? 'x' : m[1]) as Marker
    const body = m[2]
    const cut = body.indexOf(' · ')
    items.push({
      group,
      marker,
      text: cut < 0 ? body : body.slice(0, cut),
      evidence: cut < 0 ? '' : body.slice(cut + 3),
      line,
      index: items.length,
    })
  }
  return items
}

export function ticketKey(text: string): string {
  const m = TICKET.exec(text)
  return m ? m[1].toLowerCase() : ''
}

export function normRepo(repo: string): string {
  return (repo.split('/').pop() ?? '').replace(/^ecfx-/, '')
}

export function mrKey(repo: string, mr: number | string): string {
  return `${normRepo(repo)}!${Number(String(mr).replace(/^!/, ''))}`
}

export function mrKeysOf(text: string): string[] {
  const out: string[] = []
  for (const m of text.matchAll(MR_LINK)) out.push(mrKey(m[1], m[2]))
  for (const m of text.matchAll(MR_REF)) {
    const k = mrKeyFromRef(m[1])
    if (k !== '') out.push(k)
  }
  return out
}

export function mrKeyFromRef(ref: string): string {
  const i = ref.lastIndexOf('!')
  return i < 0 ? '' : mrKey(ref.slice(0, i), ref.slice(i + 1))
}
