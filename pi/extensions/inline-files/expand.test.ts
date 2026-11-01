import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { expandMentions, mentions } from "./src/expand.ts";

const cwd = mkdtempSync(join(tmpdir(), "inline-files-test-"));
after(() => rmSync(cwd, { recursive: true, force: true }));
writeFileSync(join(cwd, "README.md"), "\uFEFF# Hello\n");
writeFileSync(join(cwd, "a.ts"), "export const a = 1;\n");
writeFileSync(join(cwd, "blob.bin"), Buffer.from([1, 0, 2]));
writeFileSync(join(cwd, "big.txt"), "x".repeat(2048));
mkdirSync(join(cwd, "src"));

test("finds @mentions at the start or after whitespace, not in emails", () => {
  assert.deepEqual(mentions("@a.ts and @b/c.md, mail me@x.com"), ["a.ts", "b/c.md,"]);
});

test("reads each file into pi's <file> blocks, BOM stripped", () => {
  const out = expandMentions("explain @README.md please", cwd);
  assert.equal(out.content, `<file name="${join(cwd, "README.md")}">\n# Hello\n\n</file>\n`);
  assert.deepEqual(out.attached.map((a) => a.mention), ["README.md"]);
});

test("trailing punctuation is not part of the path", () => {
  const out = expandMentions("compare @a.ts, then @README.md?", cwd);
  assert.deepEqual(out.attached.map((a) => a.mention), ["a.ts", "README.md"]);
});

test("the same file twice is attached once", () => {
  assert.equal(expandMentions("@a.ts vs @./a.ts", cwd).attached.length, 1);
});

test("a mention that is not a file is left alone", () => {
  const out = expandMentions("ping @someone about @Override", cwd);
  assert.equal(out.content, "");
  assert.deepEqual([out.attached.length, out.skipped.length], [0, 0]);
});

test("directories, binaries and big files are skipped with a reason", () => {
  const out = expandMentions("@src @blob.bin @big.txt", cwd, 1024);
  assert.deepEqual(out.skipped.map((s) => `${s.mention}: ${s.reason}`), [
    "src: a directory",
    "blob.bin: not a text file",
    "big.txt: 2KB, over the 1KB limit",
  ]);
  assert.equal(
    out.content,
    "The user mentioned these, which could not be attached:\n- @src: a directory\n- @blob.bin: not a text file\n- @big.txt: 2KB, over the 1KB limit\n",
  );
});

test("absolute paths work", () => {
  assert.equal(expandMentions(`@${join(cwd, "a.ts")}`, "/").attached.length, 1);
});
