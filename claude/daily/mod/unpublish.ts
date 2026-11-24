// The artifacts site (artifacts.localhost) queues claude.ai pages to unpublish when their source
// is removed (D-1337). Only a Claude session can delete a published page, so the system session's
// idle check, after ideas, asks `artifacts-site queue` and nudges /daily:unpublish when it is not
// empty. Ideas go first: one nudge per idle stretch.

export const UNPUBLISH_NUDGE = '[artifacts] unpublish queue: run /daily:unpublish'
export const ARTIFACTS_QUEUE = 'A="$(command -v artifacts-site || echo "$HOME/.local/bin/artifacts-site")"; [ -x "$A" ] && exec "$A" queue || echo "[]"'

const NON_EMPTY = /^\s*\[\s*\{/

export function pickNudge(ideasJson: string, queueJson: string | null, ideasNudge: string): string | null {
  if (NON_EMPTY.test(ideasJson)) return ideasNudge
  if (queueJson !== null && NON_EMPTY.test(queueJson)) return UNPUBLISH_NUDGE
  return null
}
