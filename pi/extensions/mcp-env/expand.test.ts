import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { expandConfig, expandServers } from "./src/expand.ts";

test("expands ${VAR} in every string, url and oauth.clientId included", () => {
  const { config, missing } = expandConfig(
    { url: "https://x/tenants/${TENANT}/mcp", oauth: { clientId: "${ID}", callbackPort: 1 }, args: ["--k=${ID}"] },
    { TENANT: "t1", ID: "c1" },
  );
  assert.deepEqual(config, { url: "https://x/tenants/t1/mcp", oauth: { clientId: "c1", callbackPort: 1 }, args: ["--k=c1"] });
  assert.deepEqual(missing, []);
});

test("reports unset and empty variables", () => {
  assert.deepEqual(expandConfig({ a: "${A}", b: "${B}-${A}" }, { B: "" }).missing, ["A", "B"]);
});

test("leaves !command values and $plain text alone", () => {
  const { config } = expandConfig({ h: "!echo ${X}", p: "$5 or $X" }, { X: "x" });
  assert.deepEqual(config, { h: "!echo ${X}", p: "$5 or $X" });
});

test("a server with an unset variable is skipped, the rest are kept", () => {
  const out = expandServers({ mcpServers: { a: { url: "https://${OK}" }, b: { url: "https://${NOPE}" } } }, { OK: "a.dev" });
  assert.deepEqual(out.servers, [{ name: "a", config: { url: "https://a.dev" } }]);
  assert.deepEqual(out.skipped, [{ name: "b", missing: ["NOPE"] }]);
});

test("the committed mcp-servers.json names its secrets only as variables", () => {
  const file = JSON.parse(readFileSync(new URL("../../mcp-servers.json", import.meta.url), "utf8"));
  const out = expandServers(file, {});
  assert.deepEqual(out.servers, []);
  assert.deepEqual(
    Object.fromEntries(out.skipped.map((s) => [s.name, s.missing])),
    { slack: ["SLACK_MCP_CLIENT_ID", "SLACK_MCP_CLIENT_SECRET"], "outlook-calendar": ["OUTLOOK_MCP_TENANT_ID", "OUTLOOK_MCP_CLIENT_ID"] },
  );
});

test("rejects a file without mcpServers", () => {
  assert.throws(() => expandServers({}, {}), /mcpServers/);
});
