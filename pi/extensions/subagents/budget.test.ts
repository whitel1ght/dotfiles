import assert from "node:assert/strict";
import { test } from "node:test";
import { estimateTokens, LEAN_PROMPT_TOKENS, oversizedTask } from "./src/budget.ts";

const window = { contextWindow: 16384, maxTokens: 4096 };
const room = window.contextWindow - window.maxTokens - LEAN_PROMPT_TOKENS;

test("estimates by bytes, so multibyte text counts for more", () => {
  assert.equal(estimateTokens("abc"), 1);
  assert.equal(estimateTokens("abcd"), 2);
  assert.equal(estimateTokens("✓✓✓"), 3);
});

test("a task that fits is accepted, right up to the edge", () => {
  assert.equal(oversizedTask("ollama/m", "x".repeat(room * 3), window), undefined);
});

test("one token over is refused, with the numbers and what to do", () => {
  const why = oversizedTask("ollama/m", "x".repeat(room * 3 + 1), window)!;
  assert.match(why, new RegExp(`about ${room + 1} tokens, and ollama/m has room for about ${room} `));
  assert.match(why, /16384-token window, less 4096 for its answer/);
  assert.match(why, /cloud model/);
});

test("a window smaller than the reserve refuses everything without a negative room", () => {
  assert.match(oversizedTask("ollama/m", "hi", { contextWindow: 4096, maxTokens: 4096 })!, /room for about 0 /);
});
