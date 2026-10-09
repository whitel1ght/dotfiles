import type { RunItem } from './types.ts'

const blank = (v: string | undefined): string => (v === undefined || v === '-' ? '' : v)

export function parseRunState(text: string): RunItem[] {
  const out: RunItem[] = []
  for (const line of text.split('\n')) {
    if (!line.startsWith('- ')) continue
    const [head, ...rest] = line.slice(2).split(' | ')
    const key = head.trim().toLowerCase()
    if (!key) continue
    const f: Record<string, string> = {}
    for (const part of rest) {
      const i = part.indexOf('=')
      if (i > 0) f[part.slice(0, i).trim()] = part.slice(i + 1).trim()
    }
    const mr = blank(f.mr)
    out.push({
      key,
      cls: blank(f.class),
      agent: blank(f.agent),
      worktree: blank(f.worktree),
      mrs: mr ? mr.split(',').map(s => s.trim()).filter(Boolean) : [],
      retries: Number(f.retries ?? 0) || 0,
      needsYou: f.needs_you === 'yes',
      owner: blank(f.owner) || 'main',
    })
  }
  return out
}

export function externalKey(owner: string): string {
  return owner.startsWith('external:') ? owner.slice('external:'.length) : ''
}
