import assert from "node:assert/strict";
import { lstatSync, mkdirSync, mkdtempSync, readlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import artifactsHome from "./index.ts";

test("the artifact tool call links .pi/artifacts into the store first; other tools do nothing", () => {
  const root = mkdtempSync(join(tmpdir(), "art-home-idx-"));
  const project = join(root, "proj");
  mkdirSync(project);
  const handlers: Record<string, (e: unknown, c: unknown) => unknown> = {};
  process.env.ARTIFACTS_DIR = join(root, "store");
  const cwd = process.cwd();
  process.chdir(project);
  try {
    artifactsHome({ on: (n: string, cb: (e: unknown, c: unknown) => unknown) => void (handlers[n] = cb) } as never);
    handlers.session_start({}, {});
    assert.throws(() => lstatSync(join(project, ".pi")), "no .pi folder until an artifact is made");
    handlers.tool_call({ toolName: "bash", input: {} }, {});
    assert.throws(() => lstatSync(join(project, ".pi")), "other tools leave it alone");
    handlers.tool_call({ toolName: "artifact", input: { action: "create" } }, {});
    const link = join(project, ".pi", "artifacts");
    assert.ok(lstatSync(link).isSymbolicLink());
    assert.match(readlinkSync(link), /store\/pi\//);
  } finally {
    process.chdir(cwd);
    delete process.env.ARTIFACTS_DIR;
  }
});
