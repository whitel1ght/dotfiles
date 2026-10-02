import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { renderOutput, wakeMessage } from "./src/format.ts";
import { TerminalManager, type Terminal } from "./src/manager.ts";

const base = mkdtempSync(join(tmpdir(), "bg-manager-test-"));
after(() => rmSync(base, { recursive: true, force: true }));

// Every manager is shut down at the end, so a failing assertion cannot leak a
// running process and keep the test runner alive.
const managers: TerminalManager[] = [];
after(async () => {
  await Promise.all(managers.map((m) => m.shutdown()));
});

function make(opts = {}) {
  const manager = new TerminalManager({ baseDir: base, killGraceMs: 300, drainMs: 100, ...opts });
  managers.push(manager);
  return manager;
}

function exited(manager: TerminalManager): Promise<Terminal> {
  return new Promise((resolve) => manager.onExit(resolve));
}

test("captures stdout and stderr separately and reports exit 0", async () => {
  const manager = make();
  const done = exited(manager);
  manager.start({ command: "echo out; echo err >&2", cwd: base });
  const t = await done;
  assert.equal(t.status, "exited");
  assert.equal(t.exitCode, 0);
  assert.equal(t.stdout.text(), "out\n");
  assert.equal(t.stderr.text(), "err\n");
  assert.equal(readFileSync(t.stdout.path, "utf8"), "out\n");
  await manager.shutdown();
});

test("onStdout sees every stdout chunk before the exit is reported", async () => {
  const manager = make();
  const chunks: Buffer[] = [];
  const done = exited(manager);
  manager.start({ command: "echo one; echo two", cwd: base, onStdout: (chunk) => chunks.push(chunk) });
  await done;
  assert.equal(Buffer.concat(chunks).toString(), "one\ntwo\n");
  await manager.shutdown();
});

test("a nonzero exit is failed and carries the code", async () => {
  const manager = make();
  const done = exited(manager);
  manager.start({ command: "exit 3", cwd: base });
  const t = await done;
  assert.equal(t.status, "failed");
  assert.equal(t.exitCode, 3);
  await manager.shutdown();
});

test("stdin is closed, so a reader sees EOF instead of hanging", async () => {
  const manager = make();
  const done = exited(manager);
  manager.start({ command: "cat; echo eof", cwd: base });
  const t = await done;
  assert.equal(t.stdout.text(), "eof\n");
  await manager.shutdown();
});

test("stop kills the whole process group, children included", async () => {
  const manager = make();
  const t = manager.start({ command: "sleep 300 & echo $!; wait", cwd: base });
  await new Promise((resolve) => setTimeout(resolve, 300));
  const childPid = Number(t.stdout.text().trim());
  assert.ok(childPid > 0, "grandchild pid was printed");
  const stopped = await manager.stop(t.id);
  assert.equal(stopped.status, "stopped");
  await new Promise((resolve) => setTimeout(resolve, 100));
  assert.throws(() => process.kill(childPid, 0), "grandchild is gone");
  await manager.shutdown();
});

test("stop escalates to SIGKILL when SIGTERM is ignored", async () => {
  const manager = make();
  const t = manager.start({ command: "trap '' TERM; while true; do sleep 1; done", cwd: base });
  await new Promise((resolve) => setTimeout(resolve, 200));
  const started = Date.now();
  const stopped = await manager.stop(t.id);
  assert.equal(stopped.status, "stopped");
  assert.ok(Date.now() - started >= 250, "waited for the grace period");
  await manager.shutdown();
});

test("a backgrounded grandchild holding the pipes does not stall exit", async () => {
  const manager = make();
  const done = exited(manager);
  const started = Date.now();
  manager.start({ command: "sleep 30 & echo $!", cwd: base });
  const t = await done;
  assert.ok(Date.now() - started < 5000);
  assert.equal(t.status, "exited");
  // The leftover grandchild is not ours to manage; clean it up here.
  process.kill(Number(t.stdout.text().trim()));
  await manager.shutdown();
});

test("enforces the running cap and frees a slot when one finishes", async () => {
  const manager = make({ maxRunning: 1 });
  const first = manager.start({ command: "sleep 30", cwd: base });
  assert.throws(() => manager.start({ command: "true", cwd: base }), /already running/);
  await manager.stop(first.id, true);
  manager.start({ command: "true", cwd: base });
  await manager.shutdown();
});

test("rejects an empty command and a bad cwd", async () => {
  const manager = make();
  assert.throws(() => manager.start({ command: "  ", cwd: base }), /empty/);
  assert.throws(() => manager.start({ command: "true", cwd: join(base, "nope") }), /not a directory/);
  await manager.shutdown();
});

test("a missing shell is reported as an error, once", async () => {
  const manager = make({ shell: "/nonexistent/shell" });
  let exits = 0;
  manager.onExit(() => exits++);
  const done = exited(manager);
  manager.start({ command: "true", cwd: base });
  const t = await done;
  assert.equal(t.status, "error");
  assert.equal(exits, 1);
  await manager.shutdown();
});

test("prunes the oldest finished terminals past the tracking limit", async () => {
  const manager = make({ maxTracked: 2 });
  for (let i = 0; i < 3; i++) {
    const done = exited(manager);
    manager.start({ command: `echo ${i}`, cwd: base });
    await done;
  }
  assert.deepEqual(manager.list().map((t) => t.id), ["bg-2", "bg-3"]);
  await manager.shutdown();
});

test("shutdown kills running terminals, removes the spill files and is idempotent", async () => {
  const manager = make();
  const t = manager.start({ command: "sleep 300", cwd: base });
  const path = t.stdout.path;
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.ok(existsSync(path));
  await manager.shutdown();
  assert.equal(t.status, "stopped");
  assert.equal(existsSync(path), false);
  await manager.shutdown();
});

test("model-facing text names the logs and stays bounded", async () => {
  const manager = make();
  const done = exited(manager);
  manager.start({ command: "seq 1 5000", cwd: base });
  const t = await done;
  const out = renderOutput(t, "stdout", 5);
  assert.match(out, /showing the last 5 lines/);
  assert.match(out, /5000$/m);
  assert.match(out, /Full logs: .*bg-1\.stdout/);
  assert.ok(out.length < 1000);
  assert.match(wakeMessage([t]), /has finished/);
  await manager.shutdown();
});
