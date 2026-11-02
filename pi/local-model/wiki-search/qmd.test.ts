import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { collectionsFor, readNote, searchWiki } from "./src/qmd.ts";

// A fake qmd: records its argv, prints canned output, fails on demand.
const dir = mkdtempSync(join(tmpdir(), "wiki-search-test-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const bin = join(dir, "qmd");
const calls = join(dir, "calls.jsonl");
const out = join(dir, "out.txt");
writeFileSync(
  bin,
  `#!/usr/bin/env node
const fs = require("node:fs");
fs.appendFileSync(${JSON.stringify(calls)}, JSON.stringify(process.argv.slice(2)) + "\\n");
if (fs.existsSync(${JSON.stringify(join(dir, "fail"))})) { process.stderr.write("boom"); process.exit(1); }
process.stdout.write(fs.readFileSync(${JSON.stringify(out)}, "utf8"));
`,
);
chmodSync(bin, 0o755);
const lastCall = () => JSON.parse(readFileSync(calls, "utf8").trim().split("\n").at(-1)!);

test("scopes map to collections; all excludes pi-memory", () => {
  assert.deepEqual(collectionsFor("articles"), ["saved"]);
  assert.deepEqual(collectionsFor("projects"), ["ecfx", "epicmax", "personal"]);
  assert.ok(!collectionsFor("all").includes("pi-memory"));
  assert.deepEqual(collectionsFor("all"), ["notes", "diary", "ecfx", "epicmax", "personal", "reviews", "saved"]);
});

test("search runs qmd query with one -c per collection and formats the hits", async () => {
  writeFileSync(
    out,
    "Searching...\n" +
      JSON.stringify([
        { file: "qmd://saved/2026-10-16-trolley.md", title: "Jev Meets the Trolley Problem", score: 0.81, snippet: "@@ -3,4 @@\nmodels respond\n" },
        { file: "qmd://notes/keyboard.md", title: "Keyboard", score: 0.4, snippet: "caps lock" },
      ]),
  );
  const text = await searchWiki("ai ethics", "all", { bin });
  assert.deepEqual(lastCall(), [
    "query", "ai ethics", "--json", "-n", "5",
    "-c", "notes", "-c", "diary", "-c", "ecfx", "-c", "epicmax", "-c", "personal", "-c", "reviews", "-c", "saved",
  ]);
  assert.match(text, /1\. Jev Meets the Trolley Problem — qmd:\/\/saved\/2026-10-16-trolley\.md \(saved article, score 0\.81\)/);
  assert.match(text, /models respond/);
  assert.doesNotMatch(text, /@@/);
  assert.match(text, /2\. Keyboard — qmd:\/\/notes\/keyboard\.md \(note, score 0\.40\)/);
  assert.match(text, /wiki_read/);
});

test("no hits says so, without claiming anything", async () => {
  writeFileSync(out, "[]");
  assert.match(await searchWiki("nothing", "notes", { bin }), /No matches in notes/);
});

test("qmd failure becomes a readable error, not a throw", async () => {
  writeFileSync(join(dir, "fail"), "");
  try {
    assert.match(await searchWiki("x", "all", { bin }), /search failed: .*boom/);
  } finally {
    rmSync(join(dir, "fail"));
  }
});

test("read passes path, start line and line count, and caps output", async () => {
  writeFileSync(out, "line\n".repeat(50));
  const text = await readNote("qmd://saved/a.md", { from: 10, lines: 500, bin });
  assert.deepEqual(lastCall(), ["get", "qmd://saved/a.md:10", "-l", "200"]);
  assert.match(text, /^line/);
});

test("read rejects paths outside qmd://", async () => {
  assert.match(await readNote("/etc/passwd", { bin }), /qmd:\/\/ path/);
});
