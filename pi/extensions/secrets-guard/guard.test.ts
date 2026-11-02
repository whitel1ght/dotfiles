import assert from "node:assert/strict";
import test from "node:test";

import { blockReason } from "./guard.ts";

test("file tools are kept out of ~/.secrets", () => {
  assert.ok(blockReason("read", { path: "/Users/x/.secrets/secrets.env" }));
  assert.ok(blockReason("read", { path: "~/.secrets/recovery.md" }));
  assert.ok(blockReason("edit", { path: ".secrets/secrets.env", oldText: "a", newText: "b" }));
  assert.ok(blockReason("grep", { pattern: "TOKEN", path: "/Users/x/.secrets" }));
  assert.ok(blockReason("ls", { path: "/Users/x/.secrets/" }));
});

test("the team jira.env link counts as the folder", () => {
  assert.ok(blockReason("read", { path: "/Users/x/.config/ecfx/jira.env" }));
});

test("ordinary paths pass", () => {
  assert.equal(blockReason("read", { path: "/Users/x/projects/dotfiles/bin/secret" }), undefined);
  assert.equal(blockReason("grep", { pattern: "secrets", path: "." }), undefined);
  assert.equal(blockReason("write", { path: "notes.md", content: "see ~/.secrets for tokens" }), undefined);
});

test("bash is left to the claude-hooks extension", () => {
  assert.equal(blockReason("bash", { command: "cat ~/.secrets/secrets.env" }), undefined);
});
