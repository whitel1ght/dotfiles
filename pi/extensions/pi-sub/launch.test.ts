import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readdirSync, rmSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn, spawnSync } from "node:child_process";
import test from "node:test";

import { buildArgv, extraExtensions, launch, npmRoot } from "./launch.ts";
import { readMeta } from "./state.ts";
import type { Role } from "./roles.ts";

const here = dirname(fileURLToPath(import.meta.url));
const fakePi = join(here, "test", "fake-pi.mjs");

const reader: Role = { name: "reviewer", tools: ["read", "grep", "find", "ls"], body: "be brief", writeCapable: false };
const writer: Role = { name: "worker", tools: ["read", "edit", "bash"], body: "be brief", writeCapable: true };

function sandbox(): string {
  const root = mkdtempSync(join(tmpdir(), "pi-sub-launch-"));
  process.env.PI_SUB_STATE_DIR = join(root, "state");
  process.env.PI_SUB_NPM_ROOT = join(root, "npm");
  process.env.PI_SUB_PI_BIN = fakePi;
  return root;
}

function cleanup(root: string) {
  rmSync(root, { recursive: true, force: true });
  delete process.env.PI_SUB_STATE_DIR;
  delete process.env.PI_SUB_NPM_ROOT;
  delete process.env.PI_SUB_PI_BIN;
  delete process.env.FAKE_SLEEP;
  delete process.env.FAKE_EXIT;
}

async function waitFor(what: string, ok: () => boolean, ms = 10000): Promise<void> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (ok()) return;
    await new Promise((r) => setTimeout(r, 50));
  }
  assert.ok(ok(), `timed out waiting for ${what}`);
}

/** Full lifecycle: launch, wait for exit.json, return what the wrapper wrote. */
async function runChild(opts: { task?: string } = {}) {
  const cwd = mkdtempSync(join(tmpdir(), "pi-sub-cwd-"));
  const meta = launch({
    role: reader,
    model: "prov/model",
    label: "test launch",
    task: opts.task ?? "do the thing",
    cwd,
    skills: [],
    extras: [],
    ownerSession: "sess-test",
    ownerPid: process.pid,
    maxMinutes: 5,
  });
  await waitFor(`exit.json of ${meta.id}`, () => existsSync(join(process.env.PI_SUB_STATE_DIR!, meta.id, "exit.json")));
  const dir = join(process.env.PI_SUB_STATE_DIR!, meta.id);
  const exit = JSON.parse(readFileSync(join(dir, "exit.json"), "utf8"));
  const result = existsSync(join(dir, "result.md")) ? readFileSync(join(dir, "result.md"), "utf8") : undefined;
  return { meta, dir, exit, result };
}

/**
 * Drive run.mjs directly against a hand-built agent dir, for the failure
 * modes launch() itself rejects (missing meta cwd, pre-seeded stop file).
 */
async function runWrapper(o: { cwd: string; piBin?: string; stop?: string }) {
  const dir = mkdtempSync(join(tmpdir(), "pi-sub-wrapper-"));
  writeFileSync(join(dir, "meta.json"), JSON.stringify({ argv: ["pi", "do it"], cwd: o.cwd }));
  if (o.stop !== undefined) writeFileSync(join(dir, "stop-request.json"), o.stop);
  spawn(process.execPath, [join(here, "run.mjs"), dir], {
    env: { ...process.env, PI_SUB_PI_BIN: o.piBin ?? fakePi },
    stdio: "ignore",
  });
  await waitFor(`exit.json in ${dir}`, () => existsSync(join(dir, "exit.json")));
  const exit = JSON.parse(readFileSync(join(dir, "exit.json"), "utf8"));
  const result = existsSync(join(dir, "result.md")) ? readFileSync(join(dir, "result.md"), "utf8") : undefined;
  return { dir, exit, result };
}

test("argv matches the spec order", () => {
  const argv = buildArgv({
    role: writer,
    model: "prov/sub/model",
    task: "do it",
    skills: ["/skills/a"],
    extras: ["web", "playwright"],
    promptFile: "/tmp/prompt.md",
  });
  assert.deepEqual(argv, [
    "pi",
    "--mode", "json",
    "--no-session",
    "--no-extensions",
    "--no-skills",
    "--no-context-files",
    "--no-prompt-templates",
    "--tools", "read,edit,bash",
    "--provider", "prov",
    "--model", "sub/model",
    "--append-system-prompt", "/tmp/prompt.md",
    "--skill", "/skills/a",
    "-e", join(npmRoot(), "pi-lens/dist/index.js"),
    "--no-autofix",
    "--no-autoformat",
    "--no-tests",
    "-e", join(npmRoot(), "pi-web-access/dist"),
    "--skill", join(npmRoot(), "pi-playwright/skills/playwright-browser"),
    "do it",
  ]);
});

test("model without a slash gets no --provider", () => {
  const argv = buildArgv({ role: reader, model: "local-model", task: "t", skills: [], extras: [], promptFile: "p" });
  assert.ok(!argv.includes("--provider"));
  assert.equal(argv[argv.indexOf("--model") + 1], "local-model");
});

test("task passes verbatim", () => {
  const cases = ['say "hi"\nnewline $(rm -rf /)', "-task", "plain task"];
  for (const task of cases) {
    const argv = buildArgv({ role: reader, model: "p/m", task, skills: [], extras: [], promptFile: "p" });
    assert.equal(argv[argv.length - 1], task);
  }
  // A leading-dash task is preceded by `--` so pi treats it as the message.
  const dash = buildArgv({ role: reader, model: "p/m", task: "-task", skills: [], extras: [], promptFile: "p" });
  assert.deepEqual(dash.slice(-2), ["--", "-task"]);
});

test("read-only role gets no -e", () => {
  assert.deepEqual(extraExtensions(reader, []), []);
});

test("write role gets lens flags", () => {
  assert.deepEqual(extraExtensions(writer, []), [
    "-e", join(npmRoot(), "pi-lens/dist/index.js"),
    "--no-autofix", "--no-autoformat", "--no-tests",
  ]);
});

test("web and playwright extras map to installed package paths", () => {
  assert.deepEqual(extraExtensions(reader, ["web"]), ["-e", join(npmRoot(), "pi-web-access/dist")]);
  assert.deepEqual(extraExtensions(reader, ["playwright"]), [
    "--skill", join(npmRoot(), "pi-playwright/skills/playwright-browser"),
  ]);
});

test("wrapper writes exit.json and result.md", async () => {
  const root = sandbox();
  try {
    const { meta, dir, exit, result } = await runChild();
    assert.equal(exit.how, "done");
    assert.equal(exit.code, 0);
    assert.equal(exit.signal, null);
    assert.equal(meta.pid, meta.pgid);
    assert.ok(meta.pid > 0);
    // prompt.md carries the role body; meta.json is readable back.
    assert.equal(readFileSync(join(dir, "prompt.md"), "utf8").trim(), reader.body);
    assert.equal(readMeta(meta.id).task, "do the thing");
    // fake-pi echoes its argv and the launch env as the final message.
    const echoed = JSON.parse(result!);
    assert.equal(echoed.env.PI_SUBAGENT, "1");
    assert.equal(echoed.env.PI_SUB_ID, meta.id);
    assert.deepEqual(echoed.argv, meta.argv.slice(1));
    assert.equal(echoed.argv[echoed.argv.length - 1], "do the thing");
    assert.ok(existsSync(join(dir, "events.jsonl")));
    assert.ok(existsSync(join(dir, "stderr.log")));
  } finally {
    cleanup(root);
  }
});

test("non-zero pi exit is a failure", async () => {
  const root = sandbox();
  process.env.FAKE_EXIT = "1";
  try {
    const { exit, result } = await runChild();
    assert.equal(exit.how, "failed");
    assert.equal(exit.code, 1);
    // result.md is still written, even though pi failed.
    assert.ok(result !== undefined);
  } finally {
    cleanup(root);
  }
});

test("missing pi binary still writes a failed exit.json", async () => {
  const root = sandbox();
  process.env.PI_SUB_PI_BIN = join(root, "no-such-pi");
  try {
    const { exit, result } = await runChild();
    assert.equal(exit.how, "failed");
    assert.equal(exit.code, null);
    assert.equal(exit.signal, null);
    // The spawn error is recorded, not silently swallowed.
    assert.ok(String(exit.error).includes("ENOENT"));
    // result.md (empty) is still written before exit.json.
    assert.equal(result, "");
  } finally {
    cleanup(root);
  }
});

test("missing meta cwd still writes a failed exit.json", async () => {
  const root = sandbox();
  try {
    const { exit, result } = await runWrapper({ cwd: join(root, "gone") });
    assert.equal(exit.how, "failed");
    assert.equal(exit.code, null);
    assert.equal(exit.signal, null);
    assert.ok(String(exit.error).includes("ENOENT"));
    assert.equal(result, "");
  } finally {
    cleanup(root);
  }
});

test("malformed stop-request.json yields stopped with no by", async () => {
  const root = sandbox();
  try {
    const cwd = mkdtempSync(join(tmpdir(), "pi-sub-cwd-"));
    // Pre-seeded so the child's close handler is guaranteed to see it.
    const { exit } = await runWrapper({ cwd, stop: "{not json" });
    assert.equal(exit.how, "stopped");
    assert.equal(exit.by, undefined);
    assert.equal(exit.code, 0);
  } finally {
    cleanup(root);
  }
});

test("launch rejects a cwd that does not exist", () => {
  const root = sandbox();
  try {
    const cwd = join(root, "no-such-cwd");
    assert.throws(
      () => launch({
        role: reader, model: "p/m", label: "bad cwd", task: "t", cwd,
        skills: [], extras: [], ownerSession: "s", ownerPid: process.pid, maxMinutes: 5,
      }),
      new RegExp(`pi-sub: cwd does not exist: .*no-such-cwd`),
    );
    // No half-created agent dir is left behind looking "running".
    const state = process.env.PI_SUB_STATE_DIR!;
    assert.ok(!existsSync(state) || readdirSync(state).length === 0);
  } finally {
    cleanup(root);
  }
});

test("stop-request.json wins over a zero exit code", async () => {
  const root = sandbox();
  process.env.FAKE_SLEEP = "400";
  try {
    const cwd = mkdtempSync(join(tmpdir(), "pi-sub-cwd-"));
    const meta = launch({
      role: reader, model: "p/m", label: "stop", task: "slow", cwd,
      skills: [], extras: [], ownerSession: "s", ownerPid: process.pid, maxMinutes: 5,
    });
    const dir = join(process.env.PI_SUB_STATE_DIR!, meta.id);
    await waitFor("child to start", () => existsSync(join(dir, "events.jsonl")));
    // The stop request lands while the child is still sleeping.
    writeStopRequest(dir, "user");
    await waitFor("exit.json", () => existsSync(join(dir, "exit.json")));
    const exit = JSON.parse(readFileSync(join(dir, "exit.json"), "utf8"));
    assert.equal(exit.how, "stopped");
    assert.equal(exit.by, "user");
  } finally {
    cleanup(root);
  }
});

test("wrapper stays alive through SIGTERM and writes exit.json", async () => {
  const root = sandbox();
  process.env.FAKE_SLEEP = "15000";
  try {
    const cwd = mkdtempSync(join(tmpdir(), "pi-sub-cwd-"));
    const meta = launch({
      role: reader, model: "p/m", label: "sigterm", task: "sleepy", cwd,
      skills: [], extras: [], ownerSession: "s", ownerPid: process.pid, maxMinutes: 5,
    });
    const dir = join(process.env.PI_SUB_STATE_DIR!, meta.id);
    await waitFor("child to start", () => existsSync(join(dir, "events.jsonl")));
    // One group signal stops the wrapper and the child.
    process.kill(-meta.pgid, "SIGTERM");
    await waitFor("exit.json after SIGTERM", () => existsSync(join(dir, "exit.json")));
    const exit = JSON.parse(readFileSync(join(dir, "exit.json"), "utf8"));
    assert.equal(exit.how, "failed");
    assert.equal(exit.signal, "SIGTERM");
    assert.equal(exit.code, null);
    // The wrapper itself must have exited, not just written its files.
    await waitFor("wrapper to exit", () => !isAlive(meta.pid));
  } finally {
    cleanup(root);
  }
});

test("child survives the launching process exiting", async () => {
  const root = sandbox();
  try {
    const cwd = mkdtempSync(join(tmpdir(), "pi-sub-cwd-"));
    // A short-lived parent launches, prints the id, and exits immediately.
    const script = `
import { launch } from ${JSON.stringify(pathToFileURL(join(here, "launch.ts")).href)};
const meta = launch({
  role: { name: "reader", tools: ["read"], body: "b", writeCapable: false },
  model: "prov/model", label: "orphan", task: "survive", cwd: ${JSON.stringify(cwd)},
  skills: [], extras: [], ownerSession: "sess-gone", ownerPid: 1, maxMinutes: 5,
});
console.log(meta.id);
`;
    const parent = spawnSync(process.execPath, ["--input-type=module", "-e", script], { encoding: "utf8" });
    assert.equal(parent.status, 0, parent.stderr);
    const id = parent.stdout.trim();
    assert.ok(id.length > 0);
    // The parent is gone; the detached child still finishes on its own.
    await waitFor(`exit.json of ${id}`, () => existsSync(join(process.env.PI_SUB_STATE_DIR!, id, "exit.json")));
    const exit = JSON.parse(readFileSync(join(process.env.PI_SUB_STATE_DIR!, id, "exit.json"), "utf8"));
    assert.equal(exit.how, "done");
  } finally {
    cleanup(root);
  }
});

function writeStopRequest(dir: string, by: "user" | "main" | "timeout") {
  const tmp = join(dir, "stop-request.json");
  // Not atomic, but the child only checks presence-by-existence after close.
  writeFileSync(tmp, JSON.stringify({ by, at: new Date().toISOString() }));
}

function isAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: any) {
    return err.code === "EPERM";
  }
}
