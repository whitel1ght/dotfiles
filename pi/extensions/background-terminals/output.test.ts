import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { StreamCapture } from "./src/output.ts";

const dir = mkdtempSync(join(tmpdir(), "bg-output-test-"));
after(() => rmSync(dir, { recursive: true, force: true }));

test("keeps small output whole in memory and on disk", async () => {
  const capture = new StreamCapture(join(dir, "a"));
  capture.write(Buffer.from("one\ntwo\n"));
  await capture.end();
  assert.equal(capture.text(), "one\ntwo\n");
  assert.equal(capture.tailIsPartial, false);
  assert.equal(readFileSync(capture.path, "utf8"), "one\ntwo\n");
});

test("bounds the in-memory tail but spills everything", async () => {
  const capture = new StreamCapture(join(dir, "b"), 16);
  const lines = Array.from({ length: 10 }, (_, i) => `line-${i}\n`).join("");
  capture.write(Buffer.from(lines));
  await capture.end();
  assert.equal(capture.tailIsPartial, true);
  assert.equal(capture.totalBytes, lines.length);
  // 16 bytes starts mid-line ("7\n..."); the stub is dropped, whole lines remain.
  assert.equal(capture.text(), "line-8\nline-9\n");
  assert.equal(readFileSync(capture.path, "utf8"), lines);
});

test("a tail with no newline in it yields nothing rather than half a line", async () => {
  const capture = new StreamCapture(join(dir, "c"), 4);
  capture.write(Buffer.from("abcdefghij"));
  await capture.end();
  assert.equal(capture.text(), "");
});

test("caps the spill file but keeps counting and tailing", async () => {
  const capture = new StreamCapture(join(dir, "d"), 1024, 10);
  capture.write(Buffer.from("0123456789"));
  capture.write(Buffer.from("abcdef\n"));
  await capture.end();
  assert.equal(capture.fileTruncated, true);
  assert.equal(readFileSync(capture.path, "utf8"), "0123456789");
  assert.equal(capture.totalBytes, 17);
  assert.match(capture.text(), /abcdef/);
});

test("end is idempotent", async () => {
  const capture = new StreamCapture(join(dir, "e"));
  await capture.end();
  await capture.end();
});
