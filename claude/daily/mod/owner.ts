// Which Claude session runs the day. The mod writes `<stateDir>/<date>.owner` (one line, the
// session id) when /run-day starts or resumes, and only that session is pinged.

const RUN_DAY = new Set(['run-day', 'daily:run-day'])
const SLASH = /^\s*\/(\S+)(?:\s+([\s\S]*))?$/

export function ownerPath(stateDir: string, day: string): string {
  return `${stateDir}/${day}.owner`
}

export function claimsDay(command: string, args: string): boolean {
  return RUN_DAY.has(command) && !/(^|\s)--dry(\s|$)/.test(args)
}

export function claimsDayPrompt(text: string): boolean {
  const m = SLASH.exec(text)
  return m !== null && claimsDay(m[1], m[2] ?? '')
}

export function formatOwner(sessionId: string): string {
  return `${sessionId}\n`
}

export function parseOwner(text: string | null): string {
  return (text ?? '').split('\n').map(line => line.trim()).find(line => line !== '') ?? ''
}

export function receivesPings(owner: string, sessionId: string): boolean {
  return owner !== '' && owner === sessionId
}
