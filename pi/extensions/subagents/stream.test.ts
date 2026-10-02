import assert from "node:assert/strict";
import { test } from "node:test";
import { RunStream } from "./src/stream.ts";

const jsonl = (...events: unknown[]) => Buffer.from(events.map((e) => JSON.stringify(e) + "\n").join(""));

const assistant = (content: unknown[], extra = {}) => ({
  type: "message_end",
  message: { role: "assistant", model: "m", content, stopReason: "stop", usage: { cost: { total: 0.01 } }, ...extra },
});

test("keeps the last thing the model said as the answer, and adds up cost", () => {
  const run = new RunStream();
  run.write(
    jsonl(
      { type: "session" },
      assistant([{ type: "text", text: "Looking." }, { type: "toolCall", name: "bash" }], { stopReason: "toolUse" }),
      { type: "tool_execution_start", toolName: "bash", args: { command: "ls -1" } },
      assistant([{ type: "toolCall", name: "read" }], { stopReason: "toolUse" }),
      assistant([{ type: "text", text: "There are 3 files." }]),
      { type: "agent_settled" },
    ),
  );
  assert.equal(run.finalText, "There are 3 files.");
  assert.equal(run.turns, 3);
  assert.equal(run.toolCalls, 1);
  assert.equal(run.cost.toFixed(2), "0.03");
  assert.equal(run.settled, true);
  assert.equal(run.failure(), undefined);
  assert.deepEqual(run.activity.map((a) => a.text), ["Looking.", "bash: ls -1", "There are 3 files."]);
});

test("a provider error is a failure even though pi exits 0", () => {
  const run = new RunStream();
  run.write(jsonl(assistant([], { stopReason: "error", errorMessage: "401 Invalid API key." })));
  assert.equal(run.failure(), "401 Invalid API key.");
});

test("no final text is a failure", () => {
  const run = new RunStream();
  run.write(jsonl(assistant([{ type: "toolCall", name: "bash" }], { stopReason: "toolUse" })));
  assert.match(run.failure()!, /without a final answer/);
});

test("records split across chunks, and multibyte characters split across chunks", () => {
  const run = new RunStream();
  const bytes = jsonl(assistant([{ type: "text", text: "héllo — ✓" }]));
  for (let i = 0; i < bytes.length; i += 3) run.write(bytes.subarray(i, i + 3));
  run.end();
  assert.equal(run.finalText, "héllo — ✓");
});

test("only LF ends a record, so U+2028 inside a string is kept", () => {
  const run = new RunStream();
  run.write(jsonl(assistant([{ type: "text", text: "a\u2028b" }])));
  assert.equal(run.finalText, "a\u2028b");
});

test("non-JSON lines are kept as noise, bounded", () => {
  const run = new RunStream();
  run.write(Buffer.from("Error: cannot find module\n".repeat(60)));
  assert.equal(run.noise.length, 50);
  assert.equal(run.noise[0], "Error: cannot find module");
});

test("a trailing record without LF is read at end()", () => {
  const run = new RunStream();
  run.write(Buffer.from(JSON.stringify(assistant([{ type: "text", text: "done" }]))));
  assert.equal(run.finalText, "");
  run.end();
  assert.equal(run.finalText, "done");
});

test("every record moves lastEventAt, and tools are counted while they run", () => {
  let clock = 1000;
  const run = new RunStream(() => clock);
  assert.equal(run.lastEventAt, 1000);
  clock = 2000;
  run.write(jsonl({ type: "tool_execution_start", toolName: "bash", args: { command: "npm test" } }));
  assert.deepEqual([run.lastEventAt, run.toolsRunning], [2000, 1]);
  clock = 3000;
  run.write(jsonl({ type: "tool_execution_end", toolName: "bash" }, { type: "tool_execution_end", toolName: "bash" }));
  assert.deepEqual([run.lastEventAt, run.toolsRunning], [3000, 0]);
  clock = 4000;
  run.write(Buffer.from("not json\n"));
  assert.equal(run.lastEventAt, 3000);
});
