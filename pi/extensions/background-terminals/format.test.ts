import assert from "node:assert/strict";
import { test } from "node:test";
import { describe, formatBytes, formatDuration, sliceWindow, tailLines } from "./src/format.ts";
import type { Terminal } from "./src/manager.ts";

test("formatDuration", () => {
  assert.equal(formatDuration(4_000), "4s");
  assert.equal(formatDuration(125_000), "2m05s");
  assert.equal(formatDuration(3_900_000), "1h05m");
});

test("formatBytes", () => {
  assert.equal(formatBytes(10), "10B");
  assert.equal(formatBytes(2048), "2.0KB");
});

test("tailLines keeps the last lines and reports a cut", () => {
  assert.deepEqual(tailLines("a\nb\nc\n", 2), { text: "b\nc", cut: true });
  assert.deepEqual(tailLines("a\nb\n", 5), { text: "a\nb", cut: false });
});

test("tailLines enforces the byte bound on whole lines", () => {
  const { text, cut } = tailLines("x".repeat(50) + "\n" + "y".repeat(5) + "\n", 10, 20);
  assert.equal(text, "yyyyy");
  assert.equal(cut, true);
});

test("sliceWindow follows the tail and clamps scrolling", () => {
  const lines = ["1", "2", "3", "4", "5"];
  assert.deepEqual(sliceWindow(lines, 2, 0), { lines: ["4", "5"], offset: 0, maxOffset: 3 });
  assert.deepEqual(sliceWindow(lines, 2, 1).lines, ["3", "4"]);
  assert.equal(sliceWindow(lines, 2, 99).offset, 3);
  assert.deepEqual(sliceWindow(lines, 10, 4).lines, lines);
});

test("describe names status, pid and title", () => {
  const t = {
    id: "bg-1", title: "dev server", cwd: "/app", pid: 42, status: "failed",
    exitCode: 2, startedAt: 0, endedAt: 5_000,
  } as Terminal;
  assert.equal(describe(t), 'bg-1 [exited 2] "dev server" (pid 42, 5s, /app)');
});
