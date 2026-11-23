// `day-restart` restarts the running day session on request (decision 0018): it writes
// `<stateDir>/<date>.restart` naming the session and how it restarts, then respawns it or leaves
// it running. The named session takes the marker and resumes the day with the playbook read
// afresh: a respawned one at its session.start, an in-place one on its next inbox tick. A respawn
// marker is never taken on a tick, so the old process, still running until the respawn lands,
// cannot use it up. Harness-free.

// `/daily:run-day resume restarted`: the playbook's resume path, told the user asked for it.
export const RESTART_ARGS = 'resume restarted'

export type RestartMode = 'respawn' | 'in-place'
export type RestartWhen = 'start' | 'tick'

export function restartPath(stateDir: string, day: string): string {
  return `${stateDir}/${day}.restart`
}

export function formatRestart(sessionId: string, mode: RestartMode): string {
  return `${sessionId}\n${mode}\n`
}

/** Whether the marker asks this session to restart now: its id on the first line, and a respawn
 * only at session.start. An unknown or missing mode counts as in place. */
export function restartFor(text: string | null, sessionId: string, when: RestartWhen): boolean {
  const [named = '', mode = ''] = (text ?? '').split('\n').map(line => line.trim())
  if (named === '' || named !== sessionId) return false
  return mode !== 'respawn' || when === 'start'
}
