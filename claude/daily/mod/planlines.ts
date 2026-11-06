// A line the user adds to the plan mid-day has no run-state line, so nothing finds it: triage runs
// once, and Keep busy's steps read the run state and children (2026-11-06: a pass reported nothing
// to do five minutes after the user added an item). The owner session gets one prompt per new line.
// Harness-free: the Claude mod and pi's daily extension both use it.

import { itemKey } from './agentfile.ts'
import type { Item, RunItem } from './types.ts'

const prompt = (cmd: string, n: number) => `[daily-plan] ${n} new plan line${n === 1 ? '' : 's'}: run Keep busy of ${cmd} (section 11).`
export const planPrompt = (n: number) => prompt('/daily:run-day', n)
export const piPlanPrompt = (n: number) => prompt('/run-day', n)

export function untracked(items: Item[], runs: RunItem[]): Item[] {
  const keys = new Set(runs.map(r => r.key))
  return items.filter(i => i.marker === ' ' && !keys.has(itemKey(i)))
}

export function nextPlanLines(lines: Item[], seen: string[]): { fresh: Item[]; seen: string[] } {
  return { fresh: lines.filter(l => !seen.includes(l.line)), seen: [...new Set([...seen, ...lines.map(l => l.line)])] }
}
