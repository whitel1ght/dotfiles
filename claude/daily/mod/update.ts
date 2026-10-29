// A system change reaches the running day (decision 0005). The day session follows the playbook
// it read when /run-day ran; when the playbook or a brief template changes on disk (a merge into
// dotfiles main), the session resumes the day once with the new text. The fingerprint of what
// the day was claimed with sits in `<date>.playbook`; Claude compares it on every session.start
// (each plugin reload runs it), pi's watcher on its 30 s tick. Harness-free: both harnesses use it.

// Paths relative to the dotfiles checkout.
const BRIEFS = ['claude/daily/templates/ticket-brief.md', 'claude/daily/templates/review-round-brief.md', 'claude/daily/templates/review-brief.md']
export const CLAUDE_PLAYBOOK = ['claude/daily/commands/run-day.md', ...BRIEFS]
export const PI_PLAYBOOK = ['pi/prompts/run-day.md', ...BRIEFS]

// `/daily:run-day resume updated` (pi: `/run-day resume updated`): the playbook's resume path,
// told that the plugin started it because the playbook changed.
export const UPDATE_ARGS = 'resume updated'

export function playbookPath(stateDir: string, day: string): string {
  return `${stateDir}/${day}.playbook`
}

// FNV-1a over each text's length and characters, so moving text between files changes it too.
export function fingerprint(texts: string[]): string {
  let h = 0x811c9dc5
  const mix = (code: number) => {
    h ^= code
    h = Math.imul(h, 0x01000193) >>> 0
  }
  for (const t of texts) {
    for (const ch of `${t.length}:`) mix(ch.charCodeAt(0))
    for (let i = 0; i < t.length; i++) mix(t.charCodeAt(i))
  }
  return h.toString(16).padStart(8, '0')
}

export function parsePrint(text: string | null): string | null {
  const line = (text ?? '').split('\n')[0].trim()
  return line === '' ? null : line
}

export type UpdateState = {
  isOwner: boolean
  // today's run state exists and the day has no report yet
  dayRunning: boolean
  recorded: string | null
  current: string
}

export function shouldResume(s: UpdateState): boolean {
  return s.isOwner && s.dayRunning && s.recorded !== null && s.recorded !== s.current
}
