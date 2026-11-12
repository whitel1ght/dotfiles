import { mrKeyFromRef, ticketKey } from './diary.ts'
import type { Item } from './types.ts'

export type AgentEntry = { kind: string; time: string; text: string }

const KINDS = new Set(['progress', 'done', 'note', 'blocked', 'with-you', 'handed-back', 'carried', 'dismissed', 'deferred', 'expired'])
const SECTION = /^## (\S+)\s*$/
const MR_LINE = /^- mr: (\S+) (\S+)\s*$/
const ENTRY = /^- (\d\d:\d\d) ([a-z-]+): (.+)$/
const COMMENT = /<!-- (p\d+) -->\s*$/

export function agentPath(diaryPath: string): string {
  const i = diaryPath.lastIndexOf('/')
  return `${diaryPath.slice(0, i + 1)}.agent/${diaryPath.slice(i + 1)}`
}

export function parseAgent(md: string): Map<string, AgentEntry[]> {
  const out = new Map<string, AgentEntry[]>()
  let cur: AgentEntry[] | null = null
  for (const line of md.split('\n')) {
    const s = SECTION.exec(line)
    if (s) {
      const key = s[1].toLowerCase()
      cur = out.get(key) ?? []
      out.set(key, cur)
      continue
    }
    if (cur === null) continue
    const m = MR_LINE.exec(line)
    if (m) {
      cur.push({ kind: 'mr', time: '', text: `${m[1]} ${m[2]}` })
      continue
    }
    const e = ENTRY.exec(line)
    if (e && KINDS.has(e[2])) cur.push({ kind: e[2], time: e[1], text: e[3] })
  }
  return out
}

function mrLines(md: string): { key: string; url: string }[] {
  const out: { key: string; url: string }[] = []
  for (const entries of parseAgent(md).values()) {
    for (const e of entries) {
      if (e.kind !== 'mr') continue
      const [ref, url] = e.text.split(' ')
      const key = mrKeyFromRef(ref)
      if (key !== '') out.push({ key, url })
    }
  }
  return out
}

export function agentMrKeys(md: string): string[] {
  return mrLines(md).map(m => m.key)
}

export function agentMrUrls(md: string): Map<string, string> {
  return new Map(mrLines(md).map(m => [m.key, m.url]))
}

export function hasEntry(md: string, key: string, kind: string): boolean {
  return (parseAgent(md).get(key.toLowerCase()) ?? []).some(e => e.kind === kind && e.text.trim() !== '')
}

export function hasDoneEvidence(md: string, key: string): boolean {
  return hasEntry(md, key, 'done')
}

export function commentId(line: string): string {
  return COMMENT.exec(line)?.[1] ?? ''
}

export function itemKey(item: Item): string {
  return commentId(item.line) || ticketKey(item.text)
}
