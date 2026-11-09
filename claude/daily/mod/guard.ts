import { hasDoneEvidence, hasEntry, itemKey } from './agentfile.ts'
import { extractBlock, parseItems } from './diary.ts'
import type { Item, Marker } from './types.ts'

const EVIDENCE = /merge_requests\/\d+|\[↗\]\[[^\]]*![0-9]+[^\]]*\]|\bmerged\b|· note:/i

export type GuardResult = { ok: true } | { ok: false; lines: string[]; format: 'old' | 'new' }
export type EditInput =
  | { tool: 'Edit'; old_string: string; new_string: string; replace_all?: boolean }
  | { tool: 'Write'; content: string }

export function isTodaysDiary(path: string, today: string): boolean {
  return path.endsWith(`/wiki/diary/${today}.md`)
}

export function applyEdit(current: string, input: EditInput): string | null {
  if (input.tool === 'Write') return input.content
  if (input.old_string === '' || !current.includes(input.old_string)) return null
  return input.replace_all
    ? current.split(input.old_string).join(input.new_string)
    : current.replace(input.old_string, () => input.new_string)
}

// Fired with a one-line description whenever the guard blocks; a throwing hook never changes the verdict.
export type OnBlock = (msg: string) => void

export function checkTicks(before: string, after: string, agent: string | null, onBlock?: OnBlock): GuardResult {
  const result = checkTicksPure(before, after, agent)
  if (!result.ok && onBlock) {
    try {
      onBlock(`diary guard blocked: ${result.lines.join(' | ')}`.replace(/\s+/g, ' ').slice(0, 300))
    } catch {
      // capture must never change the verdict
    }
  }
  return result
}

function checkTicksPure(before: string, after: string, agent: string | null): GuardResult {
  const format = agent === null ? 'old' : 'new'
  if (extractBlock(before) !== null && extractBlock(after) === null) {
    return { ok: false, lines: ['the start-day block markers (<!-- start-day:start --> / <!-- start-day:end -->) are broken or missing'], format }
  }
  if (agent !== null) return checkNew(before, after, agent)
  const pool = new Map<string, Marker[]>()
  for (const it of parseItems(before)) pool.set(it.text, [...(pool.get(it.text) ?? []), it.marker])
  const bad: string[] = []
  for (const it of parseItems(after)) {
    const prior = pool.get(it.text)?.shift()
    if (it.marker !== 'x' || prior === 'x') continue
    if (!EVIDENCE.test(it.line)) bad.push(it.line)
  }
  return bad.length > 0 ? { ok: false, lines: bad, format } : { ok: true }
}

const ITEM_LINE = /^\s*- \[[ xX/!>-]\] /
const COMMENT_TAIL = /\s*<!-- p\d+ -->\s*$/
const DEFINITION = /^\[[^\]]+\]: \S/
const MAX_LINE = 100

function checkNew(before: string, after: string, agent: string): GuardResult {
  const bad: string[] = []
  const pool = new Map<string, Marker[]>()
  const slot = (it: Item) => itemKey(it) || it.text
  for (const it of parseItems(before)) pool.set(slot(it), [...(pool.get(slot(it)) ?? []), it.marker])
  for (const it of parseItems(after)) {
    const prior = pool.get(slot(it))?.shift()
    if (it.marker === '-' && prior !== '-') {
      // Dismissing is the user's call: an agent writes [-] only after recording the user's word.
      const key = itemKey(it)
      if (key === '') bad.push(`${it.line.trim()}: no ticket key or <!-- pN --> id to dismiss against`)
      else if (!hasEntry(agent, key, 'dismissed')) bad.push(`${key} ${it.text.replace(COMMENT_TAIL, '').slice(0, 40)}: no dismissed entry; only on the user's word (day-agent note ${key} dismissed "the user said: <what>")`)
      continue
    }
    if (it.marker !== 'x' || prior === 'x') continue
    const key = itemKey(it)
    if (key === '') bad.push(`${it.line.trim()}: no ticket key or <!-- pN --> id to tick against`)
    else if (!hasDoneEvidence(agent, key)) bad.push(`${key} ${it.text.replace(COMMENT_TAIL, '').slice(0, 40)}: no done entry in the agent file (day-agent note ${key} done "<evidence>")`)
  }
  const old = new Set((extractBlock(before) ?? '').split('\n'))
  for (const line of (extractBlock(after) ?? '').split('\n')) {
    if (old.has(line) || old.has(line.replace(COMMENT_TAIL, ''))) continue
    if (DEFINITION.test(line)) bad.push(`${line}: a [label]: url definition line`)
    else if (ITEM_LINE.test(line)) {
      if (line.includes(' · ')) bad.push(`${line}: has " · "`)
      else if (line.includes('[↗]')) bad.push(`${line}: has [↗]`)
      else if (line.replace(COMMENT_TAIL, '').length > MAX_LINE) bad.push(`${line}: longer than ${MAX_LINE} characters`)
    }
  }
  return bad.length > 0 ? { ok: false, lines: bad, format: 'new' } : { ok: true }
}

export function denyMessage(lines: string[], format: 'old' | 'new' = 'old'): string {
  if (format === 'new') {
    return `daily: refusing this plan edit (lines stay short; notes and evidence go to the agent file with day-agent, e.g. day-agent note <key> done "<evidence>"):\n${lines.join('\n')}`
  }
  return `daily: refusing to tick [X] without evidence (an MR link or [↗][repo!N] ref, "merged", or "· note: <why>"):\n${lines.join('\n')}`
}
