import type { DailyInbox, DailyView } from '../types/index.d.ts'

export type Marker = ' ' | '/' | 'x' | '!' | '>'

export type Item = {
  group: string
  marker: Marker
  text: string
  evidence: string
  line: string
  index: number
}

export type RunItem = {
  key: string
  cls: string
  agent: string
  worktree: string
  mrs: string[]
  retries: number
  needsYou: boolean
  owner: string
}

export type AgentLite = { id: string; description: string; status: string }

export type Row = {
  key: string
  item: Item
  run: RunItem | null
  agent: AgentLite | null
  needsYou: boolean
  running: boolean
}

export type PanelRow = { marker: Marker; text: string; badges: string[]; needsYou: boolean }
export type PanelGroup = { group: string; rows: PanelRow[] }
export type ViewState = DailyView
export type InboxState = DailyInbox

export type DayEvent = {
  kind: string
  project?: string
  ticket?: string | null
  mr?: number | string | null
  repo?: string | null
  summary?: string
  url?: string | null
  at?: string
}
