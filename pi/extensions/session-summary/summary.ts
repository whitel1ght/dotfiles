import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

// The harness-free half: when to skip, where the file goes, what it says.

export const MIN_USER_MESSAGES = 2

export type SkipInput = {
  reason: string
  subagent: boolean
  sessionFile: string | undefined
  sessionId: string
  runDayOwner: string | undefined
  userMessages: number
}

/** Why this session gets no summary, or undefined when it gets one. */
export function skipReason(i: SkipInput): string | undefined {
  if (i.subagent) return "subagent"
  if (!i.sessionFile) return "no session file"
  if (i.reason === "reload") return "reload"
  if (i.runDayOwner && i.runDayOwner === i.sessionId) return "run-day session"
  if (i.userMessages < MIN_USER_MESSAGES) return "too short"
  return undefined
}

export const localDate = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`

export function sessionsDir(): string {
  return join(process.env.WIKI_DIR ?? join(homedir(), "wiki"), "work", "sessions")
}

/** The `session:` line of today's run state: the session that owns /run-day. */
export function runDayOwner(today: string): string | undefined {
  const stateDir = process.env.RUN_DAY_STATE_DIR ?? join(homedir(), ".local/state/run-day")
  const file = join(stateDir, `${today}.md`)
  if (!existsSync(file)) return undefined
  return /^session:\s*(\S+)/m.exec(readFileSync(file, "utf8"))?.[1]
}

export type Meta = { sessionId: string; cwd: string; model: string; sessionFile: string; ended: Date }

export function render(meta: Meta, body: string): string {
  const front = [
    "---",
    "type: session",
    `date: ${localDate(meta.ended)}`,
    `session: ${meta.sessionId}`,
    `cwd: ${meta.cwd}`,
    `model: ${meta.model}`,
    `file: ${meta.sessionFile}`,
    "---",
  ]
  return `${front.join("\n")}\n\n${body.trim()}\n`
}

/**
 * Writes sessions/<end date>/<id>.md, one file per session: a session resumed
 * on a later day moves to that day, carrying its whole history.
 */
export function save(meta: Meta, body: string, root = sessionsDir()): string {
  const name = `${meta.sessionId}.md`
  if (existsSync(root))
    for (const day of readdirSync(root)) rmSync(join(root, day, name), { force: true })
  const dir = join(root, localDate(meta.ended))
  mkdirSync(dir, { recursive: true })
  const path = join(dir, name)
  writeFileSync(path, render(meta, body))
  return path
}

export const SYSTEM_PROMPT = `You write the record of a finished coding-agent session for the user's notes.
Reply in markdown, nothing else, in exactly this shape:

# <what the session was about, under 10 words>

**Did:** 1-5 bullets of what was done, with exact file paths, commits, MR links and ticket keys from the transcript.
**Decisions:** bullets of choices made and why, or "none".
**Open:** bullets of what is unfinished or next, or "none".

Use only facts from the transcript. No preamble.`
