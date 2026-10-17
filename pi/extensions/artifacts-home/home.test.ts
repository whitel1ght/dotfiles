import assert from "node:assert/strict";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { ensureLink, slugFor } from "./home.ts";

function sandbox() {
  const root = mkdtempSync(join(tmpdir(), "art-home-"));
  const home = join(root, "home");
  const store = join(home, "artifacts");
  const project = join(home, "projects", "ECFX-Categorization");
  mkdirSync(project, { recursive: true });
  return { root, home, store, project };
}

test("the folder name comes from the project path under home", () => {
  assert.equal(slugFor("/Users/d/projects/ECFX-Categorization", "/Users/d"), "projects-ECFX-Categorization");
  assert.equal(slugFor("/Users/d/wiki", "/Users/d"), "wiki");
  assert.equal(slugFor("/Users/d", "/Users/d"), "home");
  assert.equal(slugFor("/tmp/x", "/Users/d"), "tmp-x");
});

test("a project without artifacts gets a link into the store", () => {
  const { home, store, project } = sandbox();
  const r = ensureLink(project, store, home);
  const link = join(project, ".pi", "artifacts");
  assert.equal(r.action, "linked");
  assert.ok(lstatSync(link).isSymbolicLink());
  assert.equal(readlinkSync(link), join(store, "pi", "projects-ECFX-Categorization"));
  assert.ok(existsSync(join(store, "pi", "projects-ECFX-Categorization")));
});

test("existing artifacts move into the store, then the folder becomes a link", () => {
  const { home, store, project } = sandbox();
  const dir = join(project, ".pi", "artifacts");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "review.html"), "<title>Review</title>");
  writeFileSync(join(dir, "review.annotations.json"), "{}");
  const r = ensureLink(project, store, home);
  assert.deepEqual(r.moved.sort(), ["review.annotations.json", "review.html"]);
  assert.ok(lstatSync(dir).isSymbolicLink());
  assert.equal(readFileSync(join(dir, "review.html"), "utf8"), "<title>Review</title>", "readable through the link");
});

test("a second run is a no-op", () => {
  const { home, store, project } = sandbox();
  ensureLink(project, store, home);
  assert.equal(ensureLink(project, store, home).action, "ok");
});

test("a name already in the store is never overwritten: the folder stays as it is", () => {
  const { home, store, project } = sandbox();
  const target = join(store, "pi", "projects-ECFX-Categorization");
  mkdirSync(target, { recursive: true });
  writeFileSync(join(target, "a.html"), "kept");
  const dir = join(project, ".pi", "artifacts");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "a.html"), "local");
  const r = ensureLink(project, store, home);
  assert.equal(r.action, "skipped");
  assert.equal(readFileSync(join(target, "a.html"), "utf8"), "kept");
  assert.equal(readFileSync(join(dir, "a.html"), "utf8"), "local");
  assert.ok(!lstatSync(dir).isSymbolicLink());
});

test("a link someone else made is left alone", () => {
  const { home, store, project } = sandbox();
  mkdirSync(join(project, ".pi"), { recursive: true });
  symlinkSync("/somewhere/else", join(project, ".pi", "artifacts"));
  assert.equal(ensureLink(project, store, home).action, "skipped");
  assert.equal(readlinkSync(join(project, ".pi", "artifacts")), "/somewhere/else");
});

test("never links the store into itself", () => {
  const { home, store } = sandbox();
  mkdirSync(store, { recursive: true });
  assert.equal(ensureLink(store, store, home).action, "skipped");
});
