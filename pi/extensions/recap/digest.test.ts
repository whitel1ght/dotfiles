import assert from "node:assert/strict"
import test from "node:test"

import { digest, type DigestMessage } from "./digest.ts"

const user = (text: string): DigestMessage => ({ role: "user", content: text })
const assistant = (text: string, ...calls: [string, Record<string, unknown>][]): DigestMessage => ({
  role: "assistant",
  content: [
    { type: "thinking", text: "secret reasoning" },
    ...(text ? [{ type: "text", text }] : []),
    ...calls.map(([name, args]) => ({ type: "toolCall", name, arguments: args })),
  ],
})
const result = (text: string): DigestMessage => ({ role: "toolResult", content: [{ type: "text", text }] })

test("keeps user and assistant text, one line per tool call, drops results and thinking", () => {
  const out = digest([
    user("fix the recap"),
    assistant("Looking.", ["bash", { command: "rg -n\n  recap", timeout: 5 }]),
    result("x".repeat(50_000)),
    assistant("Done."),
  ])
  assert.equal(out, "[User]: fix the recap\n\n[Assistant]: Looking.\n→ bash: rg -n recap\n\n[Assistant]: Done.")
})

test("tool lines are cut to 100 characters", () => {
  const out = digest([user("go"), assistant("", ["write", { path: "a".repeat(300) }])])
  const line = out.split("\n").find((l) => l.startsWith("→"))!
  assert.equal(line.length, 100)
  assert.ok(line.endsWith("…"))
})

test("over budget: keeps the first entry and the newest, marks the gap", () => {
  const msgs = [user("THE GOAL"), ...Array.from({ length: 50 }, (_, i) => assistant(`step ${i} ${"y".repeat(200)}`))]
  const out = digest(msgs, 2_000)
  assert.ok(out.length <= 2_000)
  assert.ok(out.startsWith("[User]: THE GOAL"))
  assert.match(out, /\[… \d+ earlier entries omitted …\]/)
  assert.ok(out.includes("step 49"))
  assert.ok(!out.includes("step 0 "))
})

test("nothing to say gives an empty digest", () => {
  assert.equal(digest([result("only output")]), "")
})
