// Wake detection and the agents file for the day session: pure logic, no harness. Both the Claude
// mod and the pi extension import it, so it must run under plain node with type stripping.
import type { RunItem } from './types.ts'

/** The claude-code API's agent statuses, repeated here so pi need not load that module. */
export type AgentStatus = 'pending' | 'running' | 'waiting' | 'idle' | 'completed' | 'failed' | 'killed'

export const SLEEP_GAP_MS = 60_000
export const STUCK_MS = 15 * 60_000
export const WAKE_PREFIX = '[daily-wake]'

export const sleptBetween = (prevTickAt: number, now: number): boolean => now - prevTickAt > SLEEP_GAP_MS

export function parseLid(ioregOut: string): 'open' | 'closed' | null {
  const m = ioregOut.match(/"AppleClamshellState"\s*=\s*(Yes|No)/)
  return m ? (m[1] === 'Yes' ? 'closed' : 'open') : null
}

export function parseGraphics(systemstateOut: string): boolean | null {
  const m = systemstateOut.match(/Current System Capabilities are:(.*)/)
  return m ? /\bGraphics\b/.test(m[1]) : null
}

export function isFullWake(lid: 'open' | 'closed' | null, graphics: boolean | null): boolean {
  if (lid === null && graphics === null) return false
  return lid !== 'closed' && graphics !== false
}

export const outstanding = (runs: RunItem[]): RunItem[] => runs.filter(r => r.owner === 'main' && (r.agent !== '' || r.round !== ''))

export type AgentRow = {
  key: string
  kind: 'ticket' | 'round'
  id: string
  status: AgentStatus | 'unknown'
  quietMs: number | null
  transcript: string
}

export function agentRows(
  runs: RunItem[],
  listed: { id: string; status: AgentStatus }[],
  quiet: Record<string, { ms: number | null; path: string }>,
): AgentRow[] {
  const rows: AgentRow[] = []
  for (const r of outstanding(runs)) {
    for (const [kind, id] of [['ticket', r.agent], ['round', r.round]] as const) {
      if (!id) continue
      rows.push({
        key: r.key,
        kind,
        id,
        status: listed.find(a => a.id === id)?.status ?? 'unknown',
        quietMs: quiet[id]?.ms ?? null,
        transcript: quiet[id]?.path ?? '',
      })
    }
  }
  return rows
}

export function formatAgents(rows: AgentRow[], now: number): string {
  const lines = rows.map(r => {
    const quiet = r.quietMs === null ? '-' : String(Math.floor(r.quietMs / 60_000))
    return `${r.key} | ${r.kind} | ${r.id} | ${r.status} | quiet=${quiet} | ${r.transcript || '-'}`
  })
  return [`# agents ${new Date(now).toISOString()}`, ...lines].join('\n')
}

export function wakePrompt(sleptMs: number, rows: AgentRow[], agentsPath: string): string {
  return `${WAKE_PREFIX} woke after ${Math.round(sleptMs / 60_000)} min: ${rows.length} background agent(s) outstanding. Their state is in ${agentsPath}. Run the Wake check of /daily:run-day (section 10).`
}

export const stuckRows = (rows: AgentRow[]): AgentRow[] => rows.filter(r => r.status === 'running' && r.quietMs !== null && r.quietMs >= STUCK_MS)

export function stuckPrompt(rows: AgentRow[], agentsPath: string): string {
  return `${WAKE_PREFIX} stuck: ${rows.map(r => `${r.key} ${r.id}`).join(', ')}. Running but silent for ${STUCK_MS / 60_000}+ min; state in ${agentsPath}. Run the Wake check of /daily:run-day (section 10).`
}
