export type DailyPanelRow = { marker: string; text: string; badges: string[]; needsYou: boolean }
export type DailyPanelGroup = { group: string; rows: DailyPanelRow[] }
export type DailyView = { active: boolean; status: string; groups: DailyPanelGroup[] }
export type DailyInbox = { pending: number; seen: string[] }

declare module 'claude-code' {
  interface PluginState {
    daily: { view: DailyView; inbox: DailyInbox }
  }
}
