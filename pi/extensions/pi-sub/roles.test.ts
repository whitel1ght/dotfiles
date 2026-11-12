import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { agentsDir, listRoles, loadRole } from "./roles.ts";

/** This test file lives in pi/extensions/pi-sub, so the worktree roles are two levels up. */
const WORKTREE_AGENTS = join(import.meta.dirname, "..", "..", "agents");

/** A sandboxed agents dir, restored however the test ends. */
function sandbox(t: test.TestContext): string {
  const dir = mkdtempSync(join(tmpdir(), "pi-sub-roles-"));
  const saved = process.env.PI_SUB_AGENTS_DIR;
  process.env.PI_SUB_AGENTS_DIR = dir;
  t.after(() => {
    rmSync(dir, { recursive: true, force: true });
    if (saved === undefined) delete process.env.PI_SUB_AGENTS_DIR;
    else process.env.PI_SUB_AGENTS_DIR = saved;
  });
  return dir;
}

/** Point the agents dir at the worktree roles, restored however the test ends. */
function useWorktreeAgents(t: test.TestContext): void {
  const saved = process.env.PI_SUB_AGENTS_DIR;
  process.env.PI_SUB_AGENTS_DIR = WORKTREE_AGENTS;
  t.after(() => {
    if (saved === undefined) delete process.env.PI_SUB_AGENTS_DIR;
    else process.env.PI_SUB_AGENTS_DIR = saved;
  });
}

function fixture(root: string, name: string, text: string) {
  writeFileSync(join(root, `${name}.md`), text);
}

test("parses tools and body", (t) => {
  const root = sandbox(t);
  fixture(
    root,
    "tester",
    `---
name: tester
description: A fixture role.
tools: read, grep , find ,ls
---

Read the code.
Note the details.
`,
  );

  const role = loadRole("tester");

  assert.equal(role.name, "tester");
  assert.deepEqual(role.tools, ["read", "grep", "find", "ls"]);
  assert.equal(role.body, "Read the code.\nNote the details.");
  assert.equal(role.writeCapable, false);
});

test("missing tools key defaults to read,grep,find,ls", (t) => {
  const root = sandbox(t);
  fixture(
    root,
    "minimal",
    `---
name: minimal
description: No tools listed.
---

Do things.
`,
  );

  const role = loadRole("minimal");

  assert.deepEqual(role.tools, ["read", "grep", "find", "ls"]);
  assert.equal(role.writeCapable, false);
});

test("a present-but-empty tools line falls back to the default tools", (t) => {
  const root = sandbox(t);
  fixture(
    root,
    "blank",
    `---
name: blank
description: An empty tools value.
tools:
---

Do things.
`,
  );

  const role = loadRole("blank");

  assert.deepEqual(role.tools, ["read", "grep", "find", "ls"]);
  assert.equal(role.writeCapable, false);
});

test("a file that does not start with --- has no frontmatter", (t) => {
  const root = sandbox(t);
  // A --- later in the file must not be mistaken for a frontmatter fence,
  // and a tools: line in the body must not be parsed as one either.
  fixture(
    root,
    "plain",
    "No frontmatter here.\ntools: read, edit\n---\nafter a fence\n",
  );

  const role = loadRole("plain");

  assert.deepEqual(role.tools, ["read", "grep", "find", "ls"]);
  assert.equal(role.body, "No frontmatter here.\ntools: read, edit\n---\nafter a fence");
  assert.equal(role.writeCapable, false);
});

test("ignores inherit*/model keys", (t) => {
  const root = sandbox(t);
  fixture(
    root,
    "loaded",
    `---
name: loaded
description: Extra frontmatter must not break parsing.
model: qwen3.8-flash
inheritProjectContext: true
inheritGlobalContext: true
inheritSkills: true
systemPromptMode: append
tools: read, bash, grep, find, ls
---

Investigate.
`,
  );

  const role = loadRole("loaded");

  assert.deepEqual(role.tools, ["read", "bash", "grep", "find", "ls"]);
  assert.equal(role.body, "Investigate.");
});

test("worker is write-capable, reviewer is not", (t) => {
  useWorktreeAgents(t);

  assert.equal(loadRole("worker").writeCapable, true);
  const reviewer = loadRole("reviewer");
  assert.equal(reviewer.writeCapable, false);
  assert.ok(reviewer.tools.includes("bash"));
});

test("unknown role lists available", (t) => {
  const root = sandbox(t);
  mkdirSync(join(root, "empty-dir"), { recursive: true });
  fixture(root, "alpha", "---\nname: alpha\ndescription: a.\n---\n\nA.\n");
  fixture(root, "beta", "---\nname: beta\ndescription: b.\n---\n\nB.\n");

  assert.throws(() => loadRole("gamma"), /unknown role "gamma"; available: alpha, beta$/);
});

test("all five generic roles load from pi/agents", (t) => {
  useWorktreeAgents(t);

  for (const name of ["reviewer", "researcher", "planner", "oracle", "worker"]) {
    const role = loadRole(name);
    assert.equal(role.name, name);
    assert.ok(role.body.length > 0);
    assert.ok(role.tools.includes("read"));
  }
});

test("listRoles returns role names without extension", (t) => {
  const root = sandbox(t);
  fixture(root, "alpha", "---\nname: alpha\ndescription: a.\n---\n\nA.\n");
  fixture(root, "beta", "---\nname: beta\ndescription: b.\n---\n\nB.\n");
  writeFileSync(join(root, "not-a-role.txt"), "ignore me");

  assert.deepEqual(listRoles(), ["alpha", "beta"]);
});

test("agentsDir honors PI_SUB_AGENTS_DIR", (t) => {
  const saved = process.env.PI_SUB_AGENTS_DIR;
  process.env.PI_SUB_AGENTS_DIR = "/tmp/custom-agents";
  t.after(() => {
    if (saved === undefined) delete process.env.PI_SUB_AGENTS_DIR;
    else process.env.PI_SUB_AGENTS_DIR = saved;
  });
  assert.equal(agentsDir(), "/tmp/custom-agents");
});

test("an empty PI_SUB_AGENTS_DIR falls back to the default agents dir", (t) => {
  const saved = process.env.PI_SUB_AGENTS_DIR;
  process.env.PI_SUB_AGENTS_DIR = "";
  t.after(() => {
    if (saved === undefined) delete process.env.PI_SUB_AGENTS_DIR;
    else process.env.PI_SUB_AGENTS_DIR = saved;
  });
  assert.equal(agentsDir(), join(homedir(), ".pi", "agent", "agents"));
});
