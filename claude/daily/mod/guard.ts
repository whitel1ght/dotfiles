import { extractBlock, parseItems } from './diary.ts'
import type { Marker } from './types.ts'

const EVIDENCE = /merge_requests\/\d+|\[↗\]\[[^\]]*![0-9]+[^\]]*\]|\bmerged\b|· note:/i

export type GuardResult = { ok: true } | { ok: false; lines: string[] }
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

export function checkTicks(before: string, after: string): GuardResult {
  if (extractBlock(before) !== null && extractBlock(after) === null) {
    return { ok: false, lines: ['the start-day block markers (<!-- start-day:start --> / <!-- start-day:end -->) are broken or missing'] }
  }
  const pool = new Map<string, Marker[]>()
  for (const it of parseItems(before)) pool.set(it.text, [...(pool.get(it.text) ?? []), it.marker])
  const bad: string[] = []
  for (const it of parseItems(after)) {
    const prior = pool.get(it.text)?.shift()
    if (it.marker !== 'x' || prior === 'x') continue
    if (!EVIDENCE.test(it.line)) bad.push(it.line)
  }
  return bad.length > 0 ? { ok: false, lines: bad } : { ok: true }
}

export function denyMessage(lines: string[]): string {
  return `daily: refusing to tick [x] without evidence (an MR link or [↗][repo!N] ref, "merged", or "· note: <why>"):\n${lines.join('\n')}`
}
