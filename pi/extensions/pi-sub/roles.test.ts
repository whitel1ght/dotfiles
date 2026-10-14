import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { agentsDir, listRoles, loadRole } from "./roles.ts";

/** This test file lives in pi/extensions/pi-sub, so the worktree roles are two levels up. */
const WORKTREE_AGENTS = join(import.meta.dirname, "..", "..", "agents");

function sandbox(): string {
  const dir = mkdtempSync(join(tmpdir(), "pi-sub-roles-"));
  process.env.PI_SUB_AGENTS_DIR = dir;
  return dir;
}

function cleanup(root: string) {
  rmSync(root, { recursive: true, force: true });
  delete process.env.PI_SUB_AGENTS_DIR;
}

function fixture(root: string, name: string, text: string) {
  writeFileSync(join(root, `${name}.md`), text);
}

test("parses tools and body", () => {
  const root = sandbox();
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

  cleanup(root);
});

test("missing tools key defaults to read,grep,find,ls", () => {
  const root = sandbox();
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

  cleanup(root);
});

test("ignores inherit*/model keys", () => {
  const root = sandbox();
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

  cleanup(root);
});

test("worker is write-capable, reviewer is not", () => {
  const saved = process.env.PI_SUB_AGENTS_DIR;
  process.env.PI_SUB_AGENTS_DIR = WORKTREE_AGENTS;

  assert.equal(loadRole("worker").writeCapable, true);
  const reviewer = loadRole("reviewer");
  assert.equal(reviewer.writeCapable, false);
  assert.ok(reviewer.tools.includes("bash"));

  if (saved === undefined) delete process.env.PI_SUB_AGENTS_DIR;
  else process.env.PI_SUB_AGENTS_DIR = saved;
});

test("unknown role lists available", () => {
  const root = sandbox();
  mkdirSync(join(root, "empty-dir"), { recursive: true });
  fixture(root, "alpha", "---\nname: alpha\ndescription: a.\n---\n\nA.\n");
  fixture(root, "beta", "---\nname: beta\ndescription: b.\n---\n\nB.\n");

  assert.throws(() => loadRole("gamma"), /unknown role "gamma"; available: alpha, beta$/);

  cleanup(root);
});

test("all five generic roles load from pi/agents", () => {
  const saved = process.env.PI_SUB_AGENTS_DIR;
  process.env.PI_SUB_AGENTS_DIR = WORKTREE_AGENTS;

  for (const name of ["reviewer", "researcher", "planner", "oracle", "worker"]) {
    const role = loadRole(name);
    assert.equal(role.name, name);
    assert.ok(role.body.length > 0);
    assert.ok(role.tools.includes("read"));
  }

  if (saved === undefined) delete process.env.PI_SUB_AGENTS_DIR;
  else process.env.PI_SUB_AGENTS_DIR = saved;
});

test("listRoles returns role names without extension", () => {
  const root = sandbox();
  fixture(root, "alpha", "---\nname: alpha\ndescription: a.\n---\n\nA.\n");
  fixture(root, "beta", "---\nname: beta\ndescription: b.\n---\n\nB.\n");
  writeFileSync(join(root, "not-a-role.txt"), "ignore me");

  assert.deepEqual(listRoles(), ["alpha", "beta"]);

  cleanup(root);
});

test("agentsDir honors PI_SUB_AGENTS_DIR", () => {
  const saved = process.env.PI_SUB_AGENTS_DIR;
  process.env.PI_SUB_AGENTS_DIR = "/tmp/custom-agents";
  assert.equal(agentsDir(), "/tmp/custom-agents");

  if (saved === undefined) delete process.env.PI_SUB_AGENTS_DIR;
  else process.env.PI_SUB_AGENTS_DIR = saved;
});
