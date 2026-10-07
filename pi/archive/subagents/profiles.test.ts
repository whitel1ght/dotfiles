import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { loadProfiles, profileTools, summarise, type FrontmatterParser } from "./src/profiles.ts";

const dir = mkdtempSync(join(tmpdir(), "profiles-test-"));
after(() => rmSync(dir, { recursive: true, force: true }));

// A stand-in for pi's parser covering the shapes the opencode agents use.
const parse: FrontmatterParser = (content) => {
  const [, head, body] = content.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/) ?? [];
  if (head === undefined) throw new Error("no frontmatter");
  const frontmatter: Record<string, unknown> = {};
  let parent: Record<string, unknown> | undefined;
  for (const line of head.split("\n")) {
    const nested = line.match(/^  (\w+): (.*)$/);
    const top = line.match(/^(\w+):\s*(.*)$/);
    if (nested && parent) parent[nested[1]] = nested[2];
    else if (top) frontmatter[top[1]] = top[2] || (parent = {});
  }
  return { frontmatter, body };
};

writeFileSync(join(dir, "reviewer.md"), "---\ndescription: Reviews code. Examples: lots\nmode: subagent\npermission:\n  edit: deny\n---\nYou review.\n");
writeFileSync(join(dir, "writer.md"), "---\ndescription: Writes things\npermission:\n  edit: allow\n---\nYou write.\n");
writeFileSync(join(dir, "broken.md"), "no frontmatter here");
writeFileSync(join(dir, "notes.txt"), "ignored");

test("loads every .md profile and skips a malformed one", () => {
  const profiles = loadProfiles(dir, parse);
  assert.deepEqual([...profiles.keys()], ["reviewer", "writer"]);
  assert.equal(profiles.get("reviewer")!.prompt, "You review.");
});

test("edit: deny makes a profile read-only and strips the edit tools", () => {
  const profiles = loadProfiles(dir, parse);
  const tools = ["read", "bash", "edit", "write"];
  assert.deepEqual(profileTools(tools, profiles.get("reviewer")), ["read", "bash"]);
  assert.deepEqual(profileTools(tools, profiles.get("writer")), tools);
  assert.deepEqual(profileTools(tools, undefined), tools);
});

test("summary is the first sentence, without the examples", () => {
  assert.equal(summarise(loadProfiles(dir, parse).get("reviewer")!), "Reviews code.");
});

test("a missing directory means no profiles", () => {
  assert.equal(loadProfiles(join(dir, "nope"), parse).size, 0);
});
