import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { test } from "node:test";
import { CHILD_ENV, childArgs, piCommand, shellLine } from "./src/invocation.ts";

test("a tool-less run disables tools, and a lean one skips discovery", () => {
  const args = childArgs({ model: "ollama/m", task: "summarise", tools: [], lean: true });
  assert.ok(args.includes("--no-tools"));
  assert.ok(!args.includes("--tools"));
  for (const flag of ["--no-skills", "--no-context-files", "--no-extensions"]) assert.ok(args.includes(flag), flag);
});

test("a run with tools passes the allowlist and keeps discovery", () => {
  const args = childArgs({ model: "a/b", task: "t", tools: ["read", "bash"], lean: false });
  assert.equal(args[args.indexOf("--tools") + 1], "read,bash");
  assert.ok(!args.includes("--no-extensions"));
  assert.equal(args[args.indexOf("--model") + 1], "a/b");
});

test("the task cannot be mistaken for a flag or an @file", () => {
  const args = childArgs({ model: "a/b", task: "--help @secret", tools: [], lean: false });
  assert.equal(args.at(-1), "Task:\n--help @secret");
});

test("the profile prompt follows the subagent preamble", () => {
  const args = childArgs({ model: "a/b", task: "t", tools: [], lean: false, profilePrompt: "You are a reviewer." });
  const prompt = args[args.indexOf("--append-system-prompt") + 1];
  assert.match(prompt, /^You are a subagent/);
  assert.match(prompt, /\n\nYou are a reviewer\.$/);
});

test("the shell line survives quotes, newlines and $ in the task", () => {
  const nasty = `it's "quoted"\n$HOME \`whoami\` $(id) \\ end`;
  const line = shellLine(["/bin/bash", "-c", `printf '%s|%s|%s' "$${CHILD_ENV}" "$1" "$2"`, "argv0"], [nasty, "two"]);
  assert.equal(execFileSync("/bin/bash", ["-c", line], { encoding: "utf8" }), `1|${nasty}|two`);
});

test("pi is re-run with this runtime and script when the script exists", () => {
  assert.deepEqual(piCommand(["/usr/bin/node", import.meta.filename], "/usr/bin/node"), ["/usr/bin/node", import.meta.filename]);
  assert.deepEqual(piCommand(["/usr/bin/node", "/no/such/script"], "/usr/bin/node"), ["pi"]);
  assert.deepEqual(piCommand(["/opt/pi", "/no/such/script"], "/opt/pi"), ["/opt/pi"]);
});
