import assert from "node:assert/strict"
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"

import { runDayOwner, save, skipReason, type SkipInput } from "./summary.ts"

const base: SkipInput = {
  reason: "quit",
  subagent: false,
  sessionFile: "/s.jsonl",
  sessionId: "abc",
  runDayOwner: "other",
  userMessages: 3,
}

test("summarizes an ordinary session, on quit and on /new", () => {
  assert.equal(skipReason(base), undefined)
  assert.equal(skipReason({ ...base, reason: "new" }), undefined)
})

test("skips subagents, ephemeral sessions, reloads, the run-day session and short sessions", () => {
  assert.equal(skipReason({ ...base, subagent: true }), "subagent")
  assert.equal(skipReason({ ...base, sessionFile: undefined }), "no session file")
  assert.equal(skipReason({ ...base, reason: "reload" }), "reload")
  assert.equal(skipReason({ ...base, runDayOwner: "abc" }), "run-day session")
  assert.equal(skipReason({ ...base, userMessages: 1 }), "too short")
})

test("runDayOwner reads the session line of today's run state", () => {
  const dir = mkdtempSync(join(tmpdir(), "ss-"))
  process.env.RUN_DAY_STATE_DIR = dir
  try {
    assert.equal(runDayOwner("2026-01-01"), undefined)
    writeFileSync(join(dir, "2026-01-01.md"), "# run-day\nmax_agents: 3\nsession: 01a1-x\nnotes:\n")
    assert.equal(runDayOwner("2026-01-01"), "01a1-x")
  } finally {
    delete process.env.RUN_DAY_STATE_DIR
  }
})

test("save writes one file per session and moves it to the day it last ended", () => {
  const root = mkdtempSync(join(tmpdir(), "ss-"))
  const meta = { sessionId: "abc", cwd: "/p", model: "x/y", sessionFile: "/s.jsonl", ended: new Date(2026, 0, 1, 9) }
  const first = save(meta, "# One\n", root)
  assert.equal(first, join(root, "2026-01-01", "abc.md"))
  assert.match(readFileSync(first, "utf8"), /^---\ntype: session\ndate: 2026-01-01\nsession: abc\n[\s\S]*---\n\n# One\n$/)

  const second = save({ ...meta, ended: new Date(2026, 0, 3, 9) }, "# Two", root)
  assert.equal(second, join(root, "2026-01-03", "abc.md"))
  assert.ok(!existsSync(first))
})
