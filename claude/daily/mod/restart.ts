// `day-restart` restarts the running day session on request (decision 0018): it writes
// `<stateDir>/<date>.restart` naming the session, then respawns it (a background session) or
// leaves it running (`--in-place`, or an interactive one). The named session picks the marker up
// on session.start (after a respawn) or on its next inbox tick, claims the day and resumes it with
// the playbook read afresh. Harness-free.

import { parseOwner } from './owner.ts'

// `/daily:run-day resume restarted`: the playbook's resume path, told the user asked for it.
export const RESTART_ARGS = 'resume restarted'

export function restartPath(stateDir: string, day: string): string {
  return `${stateDir}/${day}.restart`
}

/** Whether the marker's text asks this session to restart. */
export function restartFor(text: string | null, sessionId: string): boolean {
  const named = parseOwner(text)
  return named !== '' && named === sessionId
}
