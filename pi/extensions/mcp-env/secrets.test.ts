import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { parseSecrets, readSecrets } from "./src/secrets.ts";

test("reads KEY=value lines the way bin/secret does", () => {
  const env = parseSecrets(
    ["# Slack app", "SLACK_MCP_CLIENT_SECRET=abc", "export A = 'q x'", 'B="d"', "EMPTY=", "C=a=b", "junk"].join("\n"),
  );
  assert.deepEqual(env, { SLACK_MCP_CLIENT_SECRET: "abc", A: "q x", B: "d", C: "a=b" });
});

test("a missing file is no secrets, not an error", () => {
  assert.deepEqual(readSecrets("/nonexistent/secrets.env"), {});
});

test("reads a real file", () => {
  const path = join(mkdtempSync(join(tmpdir(), "mcp-env-")), "secrets.env");
  writeFileSync(path, "X=1\n");
  assert.deepEqual(readSecrets(path), { X: "1" });
});
