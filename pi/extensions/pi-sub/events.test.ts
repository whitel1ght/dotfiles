import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

import { LineBuffer, activity, finalText, stats, toActivity } from "./events.ts";

// Fixture captured from a real pi 1.2.0 child run (2026-10-14):
//   cd /tmp && PI_SUBAGENT=1 pi --mode json --no-session --no-extensions \
//     --no-skills --no-context-files --no-prompt-templates --tools read,bash \
//     --provider qwen-token-plan --model qwen3.8-flash \
//     "Run: ls /tmp | head -3, then reply DONE" \
//     > test/fixtures/events.jsonl
const FIXTURE = readFileSync(join(import.meta.dirname, "test", "fixtures", "events.jsonl"), "utf8");

function event(partial: Record<string, unknown>): object {
  return partial;
}

test("holds an incomplete last line", () => {
  const buffer = new LineBuffer();
  assert.deepEqual(buffer.push('{"type":"message_sta'), []);
  // The record completes once its LF arrives: one line, nothing lost.
  assert.deepEqual(buffer.push('rt"}\n{"type":"next"}\n'), [
    '{"type":"message_start"}',
    '{"type":"next"}',
  ]);
  // A trailing fragment with no LF stays held, neither returned nor dropped.
  assert.deepEqual(buffer.push("no newline"), []);
});

test("splits on LF only (CR kept in text)", () => {
  const buffer = new LineBuffer();
  assert.deepEqual(buffer.push("one\rtwo\r\nthree\r\nlast"), ["one\rtwo\r", "three\r"]);
});

test("tool call becomes one line with short arg", () => {
  const long = `x`.repeat(120);
  const line = toActivity(
    event({ type: "tool_execution_start", toolName: "bash", args: { command: `ls /tmp | ${long}` } }),
  );
  assert.ok(line);
  assert.equal(line.kind, "tool");
  assert.equal(line.text.includes("\n"), false);
  // "bash: " plus at most 60 chars of the command.
  assert.ok(line.text.length <= "bash: ".length + 60);
  assert.ok(line.text.startsWith("bash: ls /tmp"));
  const before = Date.now();
  const at = toActivity(
    event({ type: "tool_execution_start", toolName: "read", args: { path: "/tmp/x" } }),
  )?.at;
  assert.ok(at !== undefined && at >= before && at <= Date.now());
});

test("thinking truncated to 100 chars", () => {
  const delta = "d".repeat(150);
  const line = toActivity(
    event({ type: "message_update", assistantMessageEvent: { type: "thinking_delta", delta } }),
  );
  assert.ok(line);
  assert.equal(line.kind, "think");
  assert.equal(line.text.length, 100);
});

test("text deltas collapse to one stream line", () => {
  const lines = activity([
    event({ type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "Don" } }),
    event({ type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "e " } }),
    event({ type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "yet." } }),
  ]);
  assert.deepEqual(lines.map((l) => [l.kind, l.text]), [["stream", "Done yet."]]);
});

test("finalText is last assistant message", () => {
  const events = new LineBuffer().push(FIXTURE).map((l) => JSON.parse(l));
  assert.ok(events.length > 0);
  assert.equal(finalText(events), "DONE");
});

test("stats counts tool calls and input tokens", () => {
  const events = new LineBuffer().push(FIXTURE).map((l) => JSON.parse(l));
  const s = stats(events);
  assert.equal(s.toolCalls, 1);
  assert.equal(s.tokensIn, 1563 + 639);
});
