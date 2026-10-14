import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

import {
  isDelivered,
  markDelivered,
  readExit,
  readMeta,
  stateDir,
  writeMeta,
  type Exit,
  type Meta,
} from "./state.ts";
import {
  checkLimits,
  deliverPending,
  flagText,
  formatDur,
  idleText,
  ownsPid,
  stop,
  wakeText,
  Watcher,
} from "./runtime.ts";

function sandbox() {
  const root = mkdtempSync(join(tmpdir(), "pi-sub-runtime-"));
  process.env.PI_SUB_STATE_DIR = join(root, "pi-sub");
  return root;
}

function cleanup(root: string) {
  rmSync(root, { recursive: true, force: true });
  delete process.env.PI_SUB_STATE_DIR;
}

function meta(overrides: Partial<Meta> = {}): Meta {
  return {
    id: "20261014-101500-00aa",
    role: "worker",
    model: "prov/model",
    label: "implement runtime",
    task: "Task 5",
    cwd: "/tmp/worktree",
    skills: [],
    extras: [],
    pid: 1111,
    pgid: 1111,
    started_at: "2026-10-14T10:00:00Z",
    owner_session: "sess-a",
    owner_pid: 2222,
    idle_minutes: 10,
    max_minutes: 60,
    argv: ["pi", "-p", "do it"],
    ...overrides,
  };
}

function writeExit(id: string, exit: Exit) {
  writeFileSync(join(stateDir(), id, "exit.json"), JSON.stringify(exit));
}

function writeStderr(id: string, text: string) {
  writeFileSync(join(stateDir(), id, "stderr.log"), text);
}

/** Append one byte so events.jsonl's mtime becomes "the last event". */
function touchEvents(id: string) {
  writeFileSync(join(stateDir(), id, "events.jsonl"), `{"type":"message_end"}\n`, { flag: "a" });
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

async function waitFor(what: string, ok: () => boolean, ms = 10000): Promise<void> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (ok()) return;
    await sleep(40);
  }
  assert.ok(ok(), `timed out waiting for ${what}`);
}

function isAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: any) {
    return err.code === "EPERM";
  }
}

/** A `node -e` sleeper in its own process group, tagged as our agent. */
function spawnSleeper(id: string, ignoreTerm = false, seconds = 60, readyFile?: string) {
  const script = ignoreTerm
    ? `process.on("SIGTERM", () => {});${readyFile ? ` require("fs").writeFileSync(${JSON.stringify(readyFile)}, "1");` : ""} setInterval(() => {}, ${seconds * 1000});`
    : `setTimeout(() => {}, ${seconds * 1000});`;
  const child = spawn(process.execPath, ["-e", script], {
    detached: true,
    stdio: "ignore",
    env: { ...process.env, PI_SUB_ID: id },
  });
  child.unref();
  return child;
}

test("formatDur renders 4m12s style durations", () => {
  assert.equal(formatDur((4 * 60 + 12) * 1000), "4m12s");
  assert.equal(formatDur(3 * 1000), "0m03s");
  assert.equal(formatDur((12 * 60 + 3) * 1000), "12m03s");
  assert.equal(formatDur(((2 * 3600 + 3 * 60 + 4)) * 1000), "2h03m04s");
  assert.equal(formatDur(0), "0m00s");
});

test("wakeText formats done, failed, and stopped", () => {
  const root = sandbox();
  try {
    const m = meta();
    const dir = join(stateDir(), m.id);
    writeMeta(m);
    assert.equal(
      wakeText(m, { code: 0, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "done" }, 1),
      `pi-sub #1 worker (prov/model) "implement runtime" finished in 4m12s. Result: ${dir}/result.md`,
    );
    writeStderr(m.id, "starting\n\nboom happened\n");
    assert.equal(
      wakeText(m, { code: 1, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "failed" }, 2),
      `pi-sub #2 worker (prov/model) "implement runtime" failed (exit 1) after 4m12s: boom happened. Result: ${dir}/result.md`,
    );
    assert.equal(
      wakeText(m, { code: null, signal: "SIGTERM", ended_at: "2026-10-14T10:04:12Z", how: "failed" }, 3),
      `pi-sub #3 worker (prov/model) "implement runtime" failed (exit SIGTERM) after 4m12s: boom happened. Result: ${dir}/result.md`,
    );
    assert.equal(
      wakeText(m, { code: 0, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "stopped", by: "user" }, 1),
      `pi-sub #1 worker (prov/model) "implement runtime" stopped by user after 4m12s.`,
    );
    // No stderr at all: the exit's own error text carries the reason.
    assert.equal(
      wakeText(m, { code: null, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "failed", error: "wrapper vanished" }, 1),
      `pi-sub #1 worker (prov/model) "implement runtime" failed (exit unknown) after 4m12s: wrapper vanished. Result: ${dir}/result.md`,
    );
    // The stderr line is capped at 200 characters.
    writeStderr(m.id, `${"x".repeat(300)}\n`);
    const failed = wakeText(m, { code: 1, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "failed" }, 1);
    assert.ok(failed.includes(`after 4m12s: ${"x".repeat(200)}. Result:`), failed);
  } finally {
    cleanup(root);
  }
});

test("flagText and idleText formats", () => {
  const root = sandbox();
  try {
    const m = meta();
    assert.equal(
      flagText(m, 3, "look at line 40"),
      `pi-sub #3 worker (prov/model) "implement runtime" flagged by user: look at line 40`,
    );
    assert.equal(
      idleText(m, 3, 10),
      `pi-sub #3 worker (prov/model) "implement runtime" has produced no events for 10 min (still running). Stop it with subagent_stop or let it continue.`,
    );
  } finally {
    cleanup(root);
  }
});

test("checkLimits: idle from last event, timeout from started_at, once per quiet spell", () => {
  const root = sandbox();
  try {
    const now = Date.parse("2026-10-14T10:15:00Z");
    const m = meta(); // idle 10 min, max 60 min, started 10:00
    const started = Date.parse(m.started_at);

    // Quiet for 11 minutes: idle, not timed out.
    assert.deepEqual(checkLimits(m, now - 11 * 60_000, now), { idle: true, timeout: false });
    // Quiet for only 5 minutes: not idle.
    assert.deepEqual(checkLimits(m, now - 5 * 60_000, now), { idle: false, timeout: false });
    // Already flagged this quiet spell (flag came after the last event): stays quiet.
    assert.equal(checkLimits(m, now - 11 * 60_000, now, now - 1 * 60_000).idle, false);
    // A new event arrived after the flag: re-armed.
    assert.equal(checkLimits(m, now - 11 * 60_000, now, now - 12 * 60_000).idle, true);

    // 61 minutes since started_at: timeout, measured from started_at.
    const over = meta({ started_at: new Date(now - 61 * 60_000).toISOString() });
    assert.deepEqual(checkLimits(over, now - 5 * 60_000, now), { idle: false, timeout: true });
    // Idle 0 / max 0 disable both checks.
    assert.deepEqual(checkLimits(meta({ idle_minutes: 0, max_minutes: 0 }), now - 24 * 60 * 60_000, now), { idle: false, timeout: false });
    void started;
  } finally {
    cleanup(root);
  }
});

test("ownsPid matches PI_SUB_ID in the ps environment", () => {
  const root = sandbox();
  try {
    const ps = (out: string) => () => out;
    const line = `node -e sleeper PI_SUB_ID=20261014-101500-00aa PI_SUBAGENT=1 PATH=/bin`;
    assert.equal(ownsPid(1111, "20261014-101500-00aa", ps(line)), true);
    assert.equal(ownsPid(1111, "20261014-101500-00bb", ps(line)), false);
    // A dead process prints nothing.
    assert.equal(ownsPid(1111, "20261014-101500-00aa", ps("")), false);
    // A similarly-named variable must not match.
    assert.equal(ownsPid(1111, "abc", ps(`sh -c FOO_PI_SUB_ID=abc XPI_SUB_ID=abc`)), false);
  } finally {
    cleanup(root);
  }
});

test("ownsPid against a real process on this machine", async () => {
  const root = sandbox();
  let child: ReturnType<typeof spawnSleeper> | undefined;
  try {
    child = spawnSleeper("20261014-101500-real1");
    await waitFor("sleeper to be alive", () => isAlive(child!.pid!));
    assert.equal(ownsPid(child.pid!, "20261014-101500-real1"), true);
    assert.equal(ownsPid(child.pid!, "20261014-101500-other"), false);
    // A plain process without the marker is never ours.
    const plain = spawn(process.execPath, ["-e", "setTimeout(() => {}, 5000)"], { stdio: "ignore" });
    await waitFor("plain sleeper to be alive", () => isAlive(plain.pid!));
    assert.equal(ownsPid(plain.pid!, "20261014-101500-real1"), false);
    plain.kill("SIGKILL");
    await waitFor("plain sleeper to die", () => !isAlive(plain.pid!));
  } finally {
    if (child?.pid) process.kill(child.pid, "SIGKILL");
    cleanup(root);
  }
});

test("deliverPending: exit recorded while owner was down, delivered once", () => {
  const root = sandbox();
  try {
    const m = meta({ id: "20261014-101500-01aa" });
    writeMeta(m);
    writeExit(m.id, { code: 0, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "done" });
    const sent: string[] = [];
    const delivered = deliverPending("sess-a", (t) => sent.push(t));
    assert.equal(sent.length, 1);
    assert.equal(delivered.length, 1);
    assert.ok(isDelivered(m.id));
    // A second run (e.g. after a crash) never re-delivers.
    deliverPending("sess-a", (t) => sent.push(t));
    assert.equal(sent.length, 1);
  } finally {
    cleanup(root);
  }
});

test("deliverPending: several exits queued in order, oldest first", () => {
  const root = sandbox();
  try {
    for (const id of ["20261014-101500-01aa", "20261014-101500-02bb", "20261014-101500-03cc"]) {
      writeMeta(meta({ id }));
      writeExit(id, { code: 0, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "done" });
    }
    const sent: string[] = [];
    deliverPending("sess-a", (t) => sent.push(t));
    assert.deepEqual(
      sent.map((t) => t.match(/#(\d)/)![1]),
      ["1", "2", "3"],
    );
    assert.deepEqual(
      sent.map((t) => t.includes("01aa")),
      [true, false, false],
    );
  } finally {
    cleanup(root);
  }
});

test("deliverPending skips other owners, running agents, and the delivered", () => {
  const root = sandbox();
  try {
    const foreign = meta({ id: "20261014-101500-01aa", owner_session: "sess-b" });
    const running = meta({ id: "20261014-101500-02bb" });
    const done = meta({ id: "20261014-101500-03cc" });
    for (const m of [foreign, running, done]) writeMeta(m);
    writeExit(foreign.id, { code: 0, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "done" });
    writeExit(done.id, { code: 0, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "done" });
    markDelivered(done.id);
    const sent: string[] = [];
    assert.deepEqual(deliverPending("sess-a", (t) => sent.push(t)), []);
    assert.equal(sent.length, 0);
  } finally {
    cleanup(root);
  }
});

test("deliverPending marks delivered immediately, so a mid-loop crash never re-sends", () => {
  const root = sandbox();
  try {
    const first = meta({ id: "20261014-101500-01aa" });
    const second = meta({ id: "20261014-101500-02bb" });
    for (const m of [first, second]) {
      writeMeta(m);
      writeExit(m.id, { code: 0, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "done" });
    }
    let calls = 0;
    assert.throws(() =>
      deliverPending("sess-a", () => {
        calls++;
        if (calls === 2) throw new Error("crash mid-loop");
      }),
    );
    assert.equal(calls, 2);
    // The first message went out and was marked delivered; the second did not.
    assert.ok(isDelivered(first.id));
    assert.ok(!isDelivered(second.id));
    // After the crash the second (and only the second) is still pending.
    const sent: string[] = [];
    deliverPending("sess-a", (t) => sent.push(t));
    assert.equal(sent.length, 1);
    assert.ok(sent[0].includes("02bb"));
  } finally {
    cleanup(root);
  }
});

test("stop refuses a pid that is not our agent", async () => {
  const root = sandbox();
  try {
    const m = meta({ pid: 4242 });
    writeMeta(m);
    await assert.rejects(
      stop(m.id, "user", { ps: () => "node -e sleeper PI_SUB_ID=not-ours" }),
      (err: Error) => {
        assert.match(err.message, /^pi-sub: pid 4242 is not agent 20261014-101500-00aa; not signalling$/);
        return true;
      },
    );
    // Refused before anything was written or signalled.
    assert.ok(!existsSync(join(stateDir(), m.id, "stop-request.json")));
  } finally {
    cleanup(root);
  }
});

test("stop signals the process group and waits for it to die", async () => {
  const root = sandbox();
  let child: ReturnType<typeof spawnSleeper> | undefined;
  try {
    const m = meta({ pid: 0, pgid: 0 });
    writeMeta(m);
    child = spawnSleeper(m.id);
    m.pid = child.pid!;
    m.pgid = child.pid!;
    writeMeta(m);
    await stop(m.id, "user", { graceMs: 1000 });
    const req = JSON.parse(readFileSync(join(stateDir(), m.id, "stop-request.json"), "utf8"));
    assert.equal(req.by, "user");
    assert.ok(typeof req.at === "string");
    await waitFor("sleeper to die", () => !isAlive(child!.pid!));
  } finally {
    if (child?.pid && isAlive(child.pid)) process.kill(-child.pid, "SIGKILL");
    cleanup(root);
  }
});

test("stop escalates to SIGKILL after the grace period", async () => {
  const root = sandbox();
  let child: ReturnType<typeof spawnSleeper> | undefined;
  try {
    const m = meta({ id: "20261014-101500-kill1", pid: 0, pgid: 0 });
    writeMeta(m);
    // Ignores SIGTERM (handler installed — we wait for its readiness file):
    // only the SIGKILL after the grace period can end it.
    const ready = join(root, "ready");
    child = spawnSleeper(m.id, true, 60, ready);
    m.pid = child.pid!;
    m.pgid = child.pid!;
    writeMeta(m);
    await waitFor("sleeper ready", () => existsSync(ready));
    const t0 = Date.now();
    await stop(m.id, "user", { graceMs: 300 });
    assert.ok(Date.now() - t0 >= 250, "stop should wait out the grace period");
    await waitFor("sleeper to die by SIGKILL", () => !isAlive(child!.pid!));
  } finally {
    if (child?.pid && isAlive(child.pid)) process.kill(-child.pid, "SIGKILL");
    cleanup(root);
  }
});

test("Watcher delivers an exit that appears while it runs", async () => {
  const root = sandbox();
  try {
    const m = meta({ pid: 4194304, pgid: 4194304 });
    writeMeta(m);
    touchEvents(m.id);
    const sent: string[] = [];
    let changes = 0;
    const watcher = new Watcher("sess-a", () => changes++, (t) => sent.push(t), {
      pollMs: 40,
      ps: () => `node -e sleeper PI_SUB_ID=${m.id}`,
      graceMs: 200,
    });
    try {
      watcher.start();
      watcher.start(); // idempotent
      await sleep(80);
      assert.equal(sent.length, 0);
      writeExit(m.id, { code: 0, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "done" });
      await waitFor("delivery", () => sent.length === 1);
      assert.match(sent[0], /finished in \d+m\d+s\. Result: /);
      assert.ok(isDelivered(m.id));
      assert.ok(changes > 0, "onChange fired");
    } finally {
      watcher.stop();
    }
    // After stop() no watcher, timer, or poller is left: nothing more arrives.
    writeMeta(meta({ id: "20261014-101500-02bb", pid: 4194304, pgid: 4194304 }));
    writeExit("20261014-101500-02bb", { code: 0, signal: null, ended_at: "2026-10-14T10:05:00Z", how: "done" });
    await sleep(150);
    assert.equal(sent.length, 1);
  } finally {
    cleanup(root);
  }
});

test("Watcher flags an idle agent once per quiet spell, re-arming on a new event", async () => {
  const root = sandbox();
  try {
    // idle_minutes is fractional here (0.01 = 0.6 s) so the test runs fast.
    const m = meta({ idle_minutes: 0.01, pid: 4194304, pgid: 4194304 });
    writeMeta(m);
    touchEvents(m.id);
    const sent: string[] = [];
    const watcher = new Watcher("sess-a", () => {}, (t) => sent.push(t), {
      pollMs: 40,
      ps: () => `node -e sleeper PI_SUB_ID=${m.id}`,
      graceMs: 200,
    });
    try {
      watcher.start();
      await waitFor("first idle flag", () => sent.length === 1);
      assert.match(sent[0], /pi-sub #1 worker \(prov\/model\) "implement runtime" has produced no events for \d+ min \(still running\)\. Stop it with subagent_stop or let it continue\./);
      // Still quiet: no second flag for the same quiet spell.
      await sleep(700);
      assert.equal(sent.length, 1);
      // A new event re-arms the flag...
      touchEvents(m.id);
      await waitFor("re-armed idle flag", () => sent.length === 2);
    } finally {
      watcher.stop();
    }
  } finally {
    cleanup(root);
  }
});

test("Watcher stops an agent that ran past max_minutes (from started_at)", async () => {
  const root = sandbox();
  try {
    // Started 10 minutes ago with a 5-minute cap: over on the first sweep.
    const m = meta({
      max_minutes: 5,
      started_at: new Date(Date.now() - 10 * 60_000).toISOString(),
      pid: 4194304,
      pgid: 4194304,
    });
    writeMeta(m);
    touchEvents(m.id);
    const watcher = new Watcher("sess-a", () => {}, () => {}, {
      pollMs: 40,
      ps: () => `node -e sleeper PI_SUB_ID=${m.id}`,
      graceMs: 200,
    });
    try {
      watcher.start();
      await waitFor("stop request", () => existsSync(join(stateDir(), m.id, "stop-request.json")));
      const req = JSON.parse(readFileSync(join(stateDir(), m.id, "stop-request.json"), "utf8"));
      assert.equal(req.by, "timeout");
    } finally {
      watcher.stop();
    }
  } finally {
    cleanup(root);
  }
});

test("Watcher treats a vanished wrapper as ended and delivers the failure", async () => {
  const root = sandbox();
  try {
    // SIGKILL'd wrapper: no exit.json and the pid is not ours any more.
    const m = meta({ pid: 4194304, pgid: 4194304 });
    writeMeta(m);
    const sent: string[] = [];
    const watcher = new Watcher("sess-a", () => {}, (t) => sent.push(t), {
      pollMs: 40,
      ps: () => "",
      graceMs: 200,
    });
    try {
      watcher.start();
      await waitFor("vanish exit", () => readExit(m.id) !== undefined);
      const exit = readExit(m.id)!;
      assert.equal(exit.how, "failed");
      assert.equal(exit.code, null);
      assert.equal(exit.signal, null);
      assert.equal(exit.error, "wrapper vanished");
      assert.ok(!Number.isNaN(Date.parse(exit.ended_at)), "ended_at is a valid timestamp");
      await waitFor("vanish delivery", () => sent.length === 1);
      assert.match(sent[0], /failed \(exit unknown\) after .*: wrapper vanished\. Result: /);
      assert.ok(isDelivered(m.id));
    } finally {
      watcher.stop();
    }
  } finally {
    cleanup(root);
  }
});

test("Watcher ignores other sessions' agents", async () => {
  const root = sandbox();
  try {
    const foreign = meta({ id: "20261014-101500-01aa", owner_session: "sess-b" });
    writeMeta(foreign);
    writeExit(foreign.id, { code: 0, signal: null, ended_at: "2026-10-14T10:04:12Z", how: "done" });
    const sent: string[] = [];
    const watcher = new Watcher("sess-a", () => {}, (t) => sent.push(t), {
      pollMs: 40,
      ps: () => "",
      graceMs: 200,
    });
    try {
      watcher.start();
      await sleep(150);
      assert.equal(sent.length, 0);
      assert.ok(!isDelivered(foreign.id));
    } finally {
      watcher.stop();
    }
  } finally {
    cleanup(root);
  }
});
