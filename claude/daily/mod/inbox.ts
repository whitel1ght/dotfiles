import type { InboxState } from './types.ts'

const MESSAGE = /^\d{8}T\d{6}-[A-Za-z0-9-]+-[A-Za-z0-9]{4}\.md$/

export const EMPTY_INBOX: InboxState = { pending: 0, seen: [] }

export function parseListing(stdout: string): string[] {
  return stdout
    .split('\n')
    .map(line => line.trim())
    .filter(line => line !== '')
}

export function messageFiles(names: string[]): string[] {
  return names.filter(name => MESSAGE.test(name)).sort()
}

export function nextInbox(listing: string[], seen: string[]): { fresh: string[]; state: InboxState } {
  const files = messageFiles(listing)
  const known = new Set(seen)
  return { fresh: files.filter(f => !known.has(f)), state: { pending: files.length, seen: files } }
}

export function inboxPrompt(n: number): string {
  return `inbox: ${n} new`
}
