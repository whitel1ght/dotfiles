import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import piSub, { resolvePath } from "./index.ts";
import { readEvents } from "./helpers.ts";
import { deliverPending } from "./runtime.ts";
import { listAgents, readMeta, stateDir, writeMeta, type Exit, type Meta } from "./state.ts";

const here = dirname(fileURLToPath(import.meta.url));
const fakePi = join(here, "test", "fake-pi.mjs");

function sandbox(t: test.TestContext): string {
  const root = mkdtempSync(join(tmpdir(), "pi-sub-index-"));
  mkdirSync(join(root, "agents"), { recursive: true });
  writeFileSync(
    join(root, "agents", "worker.md"),
    "---\nname: worker\ndescription: A fixture role.\ntools: read, grep\n---\n\nWork.\n",
  );
  process.env.PI_SUB_STATE_DIR = join(root, "state");
  process.env.PI_SUB_NPM_ROOT = join(root, "npm");
  process.env.PI_SUB_PI_BIN = fakePi;
  process.env.PI_SUB_AGENTS_DIR = join(root, "agents");
  // The ambient process may itself be a pi-sub child (PI_SUBAGENT=1); the
  // extension under test must register as a main session regardless.
  const savedSubagent = process.env.PI_SUBAGENT;
  delete process.env.PI_SUBAGENT;
  t.after(() => {
    rmSync(root, { recursive: true, force: true });
    for (const key of ["PI_SUB_STATE_DIR", "PI_SUB_NPM_ROOT", "PI_SUB_PI_BIN", "PI_SUB_AGENTS_DIR", "FAKE_SLEEP"]) {
      delete process.env[key];
    }
    if (savedSubagent === undefined) delete process.env.PI_SUBAGENT;
    else process.env.PI_SUBAGENT = savedSubagent;
  });
  return root;
}

/** Stub `pi` that records registerTool / on / sendMessage / setActiveTools. */
function stubPi() {
  const tools: any[] = [];
  const handlers: Record<string, any> = {};
  const sent: { message: any; options: any }[] = [];
  const setActiveCalls: string[][] = [];
  const shortcuts: Record<string, any> = {};
  const commands: Record<string, any> = {};
  let active: string[] = [];
  const pi: any = {
    registerTool: (t: any) => tools.push(t),
    registerShortcut: (key: string, opts: any) => (shortcuts[key] = opts),
    registerCommand: (name: string, opts: any) => (commands[name] = opts),
    on: (event: string, handler: any) => {
      handlers[event] = handler;
    },
    sendMessage: (message: any, options: any) => sent.push({ message, options }),
    getActiveTools: () => [...active],
    setActiveTools: (names: string[]) => {
      setActiveCalls.push(names);
      active = [...names];
    },
  };
  return { pi, tools, handlers, sent, setActiveCalls, shortcuts, commands, setActive: (names: string[]) => (active = [...names]) };
}

const model = (provider: string, id: string) => ({ provider, id });

/** Stub ctx: session sess-main, scoped to p/m, with q/n available but unscoped. */
function stubCtx(cwd: string, over: Record<string, unknown> = {}): any {
  return {
    cwd,
    sessionManager: { getSessionId: () => "sess-main" },
    scopedModels: [{ model: model("p", "m") }],
    model: model("p", "m"),
    modelRegistry: { getAvailable: () => [model("p", "m"), model("q", "n")] },
    ...over,
  };
}

async function exec(tool: any, params: any, ctx: any) {
  return tool.execute("call-1", params, undefined, undefined, ctx);
}

function text(result: any): string {
  return result.content.map((c: any) => c.text).join("\n");
}

/** A pid far beyond the system limit: alive() must report it dead. */
const DEAD_PID = 4_194_304;

/** The ambient process may be a pi-sub child; tests of the main path must not see that. */
function clearSubagentEnv(t: test.TestContext): void {
  const saved = process.env.PI_SUBAGENT;
  delete process.env.PI_SUBAGENT;
  t.after(() => {
    if (saved === undefined) delete process.env.PI_SUBAGENT;
    else process.env.PI_SUBAGENT = saved;
  });
}

const exit = (how: Exit["how"], by?: Exit["by"]): Exit => ({
  code: 0,
  signal: null,
  ended_at: "2026-10-14T10:30:00Z",
  how,
  ...(by !== undefined ? { by } : {}),
});

function meta(overrides: Partial<Meta> = {}): Meta {
  return {
    id: "20261014-100000-00aa",
    role: "worker",
    model: "p/m",
    label: "fixture",
    task: "do it",
    cwd: "/tmp",
    skills: [],
    extras: [],
    pid: 1111,
    pgid: 1111,
    started_at: "2026-10-14T10:00:00Z",
    owner_session: "sess-main",
    owner_pid: 2222,
    idle_minutes: 0,
    max_minutes: 30,
    argv: ["pi", "do it"],
    ...overrides,
  };
}

function mark(id: string, files: { exit?: Exit; delivered?: boolean } = {}) {
  const dir = join(stateDir(), id);
  if (files.exit !== undefined) writeFileSync(join(dir, "exit.json"), JSON.stringify(files.exit));
  if (files.delivered) writeFileSync(join(dir, "delivered"), "");
}

async function waitFor(what: string, ok: () => boolean, ms = 10000): Promise<void> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (ok()) return;
    await new Promise((r) => setTimeout(r, 50));
  }
  assert.ok(ok(), `timed out waiting for ${what}`);
}

/** Launch tests: the detached wrapper must finish writing before t.after removes the state dir. */
async function waitForExit(id: string): Promise<void> {
  await waitFor(`exit.json of ${id}`, () => existsSync(join(stateDir(), id, "exit.json")), 5000);
}

test("registers nothing under PI_SUBAGENT", (t) => {
  const saved = process.env.PI_SUBAGENT;
  process.env.PI_SUBAGENT = "1";
  try {
    const { pi, tools, handlers } = stubPi();
    piSub(pi);
    assert.equal(tools.length, 0);
    assert.equal(Object.keys(handlers).length, 0);
  } finally {
    if (saved === undefined) delete process.env.PI_SUBAGENT;
    else process.env.PI_SUBAGENT = saved;
  }
});

test("registers the five tools and the lifecycle handlers", (t) => {
  clearSubagentEnv(t);
  const { pi, tools, handlers } = stubPi();
  piSub(pi);
  assert.deepEqual(
    tools.map((tool) => tool.name),
    ["subagent", "subagent_stop", "subagent_result", "subagent_adopt", "subagent_handoff"],
  );
  for (const event of ["session_start", "before_agent_start", "session_shutdown"]) {
    assert.equal(typeof handlers[event], "function", `${event} handler`);
  }
});

test("rejects an unlisted model without spawning", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  const ctx = stubCtx(root);
  await assert.rejects(
    exec(tools[0], { role: "worker", model: "q/n", task: "t" }, ctx),
    /model "q\/n" is not in this session's live model list.*p\/m/,
  );
  assert.equal(listAgents().length, 0);
});

test("rejects an unknown role with the available list", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  await assert.rejects(
    exec(tools[0], { role: "nope", model: "p/m", task: "t" }, stubCtx(root)),
    /unknown role "nope"; available: worker/,
  );
  assert.equal(listAgents().length, 0);
});

test("rejects an extra outside web and playwright", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  await assert.rejects(
    exec(tools[0], { role: "worker", model: "p/m", task: "t", with: ["web", "vim"] }, stubCtx(root)),
    /unknown extra "vim"/,
  );
  assert.equal(listAgents().length, 0);
});

test("skills resolve by name from pi's skills dir or as paths; unknown ones fail", async (t) => {
  const root = sandbox(t);
  const agentDir = join(root, "agent");
  mkdirSync(join(agentDir, "skills", "commit-msg"), { recursive: true });
  mkdirSync(join(root, "local-skill"));
  const saved = process.env.PI_CODING_AGENT_DIR;
  process.env.PI_CODING_AGENT_DIR = agentDir;
  t.after(() => {
    if (saved === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = saved;
  });
  const { pi, tools } = stubPi();
  piSub(pi);
  await assert.rejects(
    exec(tools[0], { role: "worker", model: "p/m", task: "t", skills: ["nope"] }, stubCtx(root)),
    /skill not found: nope/,
  );
  assert.equal(listAgents().length, 0);
  await exec(tools[0], { role: "worker", model: "p/m", task: "t", skills: ["commit-msg", "./local-skill"] }, stubCtx(root));
  const m = listAgents()[0];
  assert.deepEqual(m.skills, [join(agentDir, "skills", "commit-msg"), join(root, "local-skill")]);
  await waitForExit(m.id);
});

test("rejects a missing cwd without spawning", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  await assert.rejects(
    exec(tools[0], { role: "worker", model: "p/m", task: "t", cwd: join(root, "no-such-cwd") }, stubCtx(root)),
    /cwd does not exist/,
  );
  assert.equal(listAgents().length, 0);
});

test("launch returns the id and the agent folder", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  const result = await exec(
    tools[0],
    { role: "worker", model: "p/m", task: "do the thing", label: "mine", idle_minutes: 5, max_minutes: 9 },
    stubCtx(root),
  );
  const agents = listAgents();
  assert.equal(agents.length, 1);
  const m = agents[0];
  assert.equal(m.owner_session, "sess-main");
  assert.equal(m.idle_minutes, 5);
  assert.equal(m.max_minutes, 9);
  assert.match(text(result), new RegExp(`#1 worker \\(p/m\\) .* · mine`));
  assert.ok(text(result).includes(m.id), "id in result");
  assert.ok(text(result).includes(join(stateDir(), m.id)), "folder in result");
  assert.match(text(result), /woken when it finishes; do not poll/);
  assert.ok(existsSync(join(stateDir(), m.id, "meta.json")));
  await waitForExit(m.id);
});

test("defaults: idle flagging after 10 minutes, a 60-minute cap, cwd from the session", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  await exec(tools[0], { role: "worker", model: "p/m", task: "t" }, stubCtx(root));
  const m = listAgents()[0];
  assert.equal(m.idle_minutes, 10);
  assert.equal(m.max_minutes, 60);
  assert.equal(m.cwd, root);
  await waitForExit(m.id);
});

test("explicit 0 disables idle flagging and the hard cap", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  await exec(tools[0], { role: "worker", model: "p/m", task: "t", idle_minutes: 0, max_minutes: 0 }, stubCtx(root));
  const m = listAgents()[0];
  assert.equal(m.idle_minutes, 0);
  assert.equal(m.max_minutes, 0);
  await waitForExit(m.id);
});

test("the launch result and the wake message show the same #N", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  const ctx = stubCtx(root);
  const result = await exec(tools[0], { role: "worker", model: "p/m", task: "t", label: "mine" }, ctx);
  const m = listAgents()[0];
  assert.match(text(result), /#1 worker \(p\/m\) started/);
  // A sibling whose id sorts first but that started later: #N follows
  // started_at, so the launched agent stays #1 in the wake message too.
  writeMeta(
    meta({ id: "20261013-000000-00zz", started_at: new Date(Date.parse(m.started_at) + 60_000).toISOString(), pid: DEAD_PID }),
  );
  await waitForExit(m.id);
  const sent: string[] = [];
  deliverPending("sess-main", (msg) => sent.push(msg));
  assert.equal(sent.length, 1);
  assert.match(sent[0], /\[pi-sub\] #1 worker \(p\/m\) done .* · mine/);
});

test("readEvents skips only unparseable lines, keeping the rest", (t) => {
  const root = sandbox(t);
  const m = meta({ id: "20261014-100000-20ev", pid: DEAD_PID });
  writeMeta(m);
  const ev = (txt: string) =>
    JSON.stringify({ type: "message_end", message: { role: "assistant", content: [{ type: "text", text: txt }] } });
  // A bad line mid-file and a truncated trailing line (expected while the
  // child is mid-append): both are skipped, the good ones survive.
  writeFileSync(
    join(stateDir(), m.id, "events.jsonl"),
    [ev("first"), `{"type":"mess`, ev("second"), `{"trailing partial`].join("\n") + "\n",
  );
  const evts = readEvents(m.id) as any[];
  assert.deepEqual(
    evts.map((e) => e.message.content[0].text),
    ["first", "second"],
  );
});

test("result tails result.md when exited and activity when running", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  const ctx = stubCtx(root);

  // Running: activity lines come from events.jsonl.
  const running = meta({ id: "20261014-100000-01run", pid: DEAD_PID, started_at: "2026-10-14T10:00:00Z" });
  writeMeta(running);
  writeFileSync(
    join(stateDir(), running.id, "events.jsonl"),
    [
      JSON.stringify({ type: "message_end", message: { role: "assistant", content: [{ type: "text", text: "first update" }] } }),
      JSON.stringify({ type: "message_end", message: { role: "assistant", content: [{ type: "text", text: "still working" }] } }),
    ].join("\n") + "\n",
  );
  const live = text(await exec(tools[2], { id: running.id }, ctx));
  assert.match(live, /#1 worker \(p\/m\) running · fixture/);
  assert.match(live, /still working/);

  // Exited: the last `lines` lines of result.md.
  const done = meta({ id: "20261014-100100-02done", started_at: "2026-10-14T10:01:00Z" });
  writeMeta(done);
  mark(done.id, { exit: exit("done") });
  writeFileSync(
    join(stateDir(), done.id, "result.md"),
    [1, 2, 3, 4, 5].map((n) => `line ${n}`).join("\n") + "\n",
  );
  const doneText = text(await exec(tools[2], { id: done.id, lines: 2 }, ctx));
  assert.match(doneText, /#2 worker \(p\/m\) done · fixture/);
  assert.equal(doneText.split("\n").slice(1).join("\n"), "line 4\nline 5".trim());

  // Default lines: 40.
  writeFileSync(join(stateDir(), done.id, "result.md"), [...Array(50).keys()].map((n) => `l${n}`).join("\n") + "\n");
  const defaultLines = text(await exec(tools[2], { id: done.id }, ctx));
  assert.equal(defaultLines.split("\n").length - 1, 40);

  await assert.rejects(exec(tools[2], { id: "no-such-agent" }, ctx), /unknown agent "no-such-agent"/);
});

test("stop reports an unknown agent and stops a running one as main", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  const ctx = stubCtx(root);
  await assert.rejects(exec(tools[1], { id: "no-such-agent" }, ctx), /unknown agent "no-such-agent"/);

  process.env.FAKE_SLEEP = "8000";
  const result = await exec(tools[0], { role: "worker", model: "p/m", task: "slow" }, ctx);
  const id = listAgents()[0].id;
  const dir = join(stateDir(), id);
  await waitFor("child to start", () => existsSync(join(dir, "events.jsonl")));
  const stopResult = await exec(tools[1], { id }, ctx);
  await waitFor("exit.json after stop", () => existsSync(join(dir, "exit.json")));
  const x = JSON.parse(readFileSync(join(dir, "exit.json"), "utf8"));
  assert.equal(x.how, "stopped");
  assert.equal(x.by, "main");
  assert.match(text(stopResult), new RegExp(`^Stopped ${id}\\. The wake message follows when it exits\\.$`));
  assert.match(text(result), /do not poll/);
});

test("handoff marks running and undelivered agents only", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  const running = meta({ id: "20261014-100000-03run", started_at: "2026-10-14T10:00:00Z" });
  const undelivered = meta({ id: "20261014-100100-04und", started_at: "2026-10-14T10:01:00Z" });
  const delivered = meta({ id: "20261014-100200-05del", started_at: "2026-10-14T10:02:00Z" });
  for (const m of [running, undelivered, delivered]) writeMeta(m);
  mark(undelivered.id, { exit: exit("done") });
  mark(delivered.id, { exit: exit("done"), delivered: true });

  const result = text(await exec(tools[4], {}, stubCtx(root)));
  assert.match(result, /subagent_adopt\(\{ from: "sess-main" \}\)/);
  assert.match(result, /#1 worker \(p\/m\) · fixture/);
  assert.equal(readMeta(running.id).handoff_from, "sess-main");
  assert.equal(readMeta(undelivered.id).handoff_from, "sess-main");
  assert.equal(readMeta(delivered.id).handoff_from, undefined);
});

test("handoff with no unfinished agents says so without the adopt call", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  const result = text(await exec(tools[4], {}, stubCtx(root)));
  assert.match(result, /No agents to hand off/);
  assert.ok(!result.includes("subagent_adopt"), "nothing to hand off: no adopt call printed");
});

test("adopt by from re-owns the handed-off agents, and only those", async (t) => {
  const root = sandbox(t);
  const { pi, tools } = stubPi();
  piSub(pi);
  const ctx = stubCtx(root); // this session is sess-main
  const handed = [
    meta({ id: "20261014-100000-06a", owner_session: "sess-old", owner_pid: DEAD_PID, handoff_from: "sess-old" }),
    meta({
      id: "20261014-100100-07b",
      owner_session: "sess-old",
      owner_pid: DEAD_PID,
      handoff_from: "sess-old",
      started_at: "2026-10-14T10:01:00Z",
    }),
  ];
  const otherHandoff = meta({ id: "20261014-100200-08c", owner_session: "sess-x", handoff_from: "sess-x" });
  const noHandoff = meta({ id: "20261014-100300-09d", owner_session: "sess-old" });
  for (const m of [...handed, otherHandoff, noHandoff]) writeMeta(m);
  mark(handed[1].id, { exit: exit("done") }); // exited but undelivered: still adoptable

  const result = text(await exec(tools[3], { from: "sess-old" }, ctx));
  for (const m of handed) {
    const after = readMeta(m.id);
    assert.equal(after.owner_session, "sess-main", `${m.id} re-owned`);
    assert.equal(after.owner_pid, process.pid);
    assert.ok(result.includes(m.id), `${m.id} listed in the result`);
  }
  assert.equal(readMeta(otherHandoff.id).owner_session, "sess-x");
  assert.equal(readMeta(noHandoff.id).owner_session, "sess-old");

  // Adopting a single id re-owns it even though another live session owns it.
  const lone = meta({ id: "20261014-100400-10e", owner_session: "sess-live", owner_pid: process.pid, started_at: "2026-10-14T10:04:00Z" });
  writeMeta(lone);
  const loneResult = text(await exec(tools[3], { id: lone.id }, ctx));
  const after = readMeta(lone.id);
  assert.equal(after.owner_session, "sess-main");
  assert.match(loneResult, /- #3 worker \(p\/m\) running · fixture/);

  await assert.rejects(exec(tools[3], { id: lone.id, from: "sess-old" }, ctx), /exactly one of id or from/);
  await assert.rejects(exec(tools[3], {}, ctx), /exactly one of id or from/);
  await assert.rejects(exec(tools[3], { id: "no-such-agent" }, ctx), /unknown agent "no-such-agent"/);
});

test("before_agent_start strips the acp_delegate tools", (t) => {
  clearSubagentEnv(t);
  const { pi, handlers, setActive, setActiveCalls } = stubPi();
  piSub(pi);
  const event = { systemPromptOptions: { sections: {} } };

  setActive(["read", "acp_delegate", "acp_delegate_wait", "acp_delegate_cancel", "edit"]);
  handlers.before_agent_start(event, stubCtx("/tmp"));
  assert.deepEqual(setActiveCalls, [["read", "edit"]]);

  // Nothing to strip: no setActiveTools call, the set is left alone.
  setActiveCalls.length = 0;
  handlers.before_agent_start(event, stubCtx("/tmp"));
  assert.deepEqual(setActiveCalls, []);
});

test("session_start delivers pending runs and lists orphans", async (t) => {
  const root = sandbox(t);
  const { pi, handlers, sent } = stubPi();
  piSub(pi);

  const pending = meta({ id: "20261014-100000-11p", started_at: "2026-10-14T10:00:00Z" });
  writeMeta(pending);
  mark(pending.id, { exit: exit("done") });
  const orphan = meta({
    id: "20261014-100100-12o",
    owner_session: "sess-gone",
    owner_pid: DEAD_PID,
    label: "foundling",
  });
  writeMeta(orphan);

  try {
    handlers.session_start({}, stubCtx(root));
    assert.ok(sent.length >= 2, `at least wake + orphan, got ${sent.length}`);
    assert.match(sent[0].message.content, /\[pi-sub\] #1 worker \(p\/m\) done .* · fixture/);
    assert.equal(sent[0].message.customType, "pi-sub");
    assert.equal(sent[0].message.display, true);
    assert.deepEqual(sent[0].options, { triggerTurn: true, deliverAs: "followUp" });
    const orphanMsg = sent[sent.length - 1].message.content;
    assert.match(orphanMsg, /orphaned agent/);
    assert.ok(orphanMsg.includes(orphan.id));
    assert.match(orphanMsg, /subagent_adopt/);
    // The pending run is delivered exactly once, not again by the watcher.
    const wakes = sent.filter((s) => /done in/.test(s.message.content));
    assert.equal(wakes.length, 1);
  } finally {
    handlers.session_shutdown({});
  }
});

test("session_start is idempotent: a second start never leaks the first watcher", async (t) => {
  const root = sandbox(t);
  const { pi, handlers, sent } = stubPi();
  piSub(pi);

  const pending = meta({ id: "20261014-100000-13p", started_at: "2026-10-14T10:00:00Z" });
  writeMeta(pending);
  mark(pending.id, { exit: exit("done") });

  try {
    handlers.session_start({}, stubCtx(root));
    handlers.session_start({}, stubCtx(root));
    // Still exactly one wake for one finished run: the first watcher was
    // stopped and cleared, not orphaned alongside the second.
    const wakes = sent.filter((s) => /done in/.test(s.message.content));
    assert.equal(wakes.length, 1);
  } finally {
    handlers.session_shutdown({});
  }
});

test("session_shutdown stops the watcher and leaves children running", async (t) => {
  const root = sandbox(t);
  const { pi, tools, handlers, sent } = stubPi();
  piSub(pi);
  const ctx = stubCtx(root);

  // A real, still-running child of this session.
  process.env.FAKE_SLEEP = "8000";
  await exec(tools[0], { role: "worker", model: "p/m", task: "slow" }, ctx);
  const m = listAgents()[0];
  const dir = join(stateDir(), m.id);
  await waitFor("child to start", () => existsSync(join(dir, "events.jsonl")));

  try {
    handlers.session_start({}, ctx);
    handlers.session_shutdown({});
    assert.equal(sent.length, 0, "a healthy running agent sends nothing");
    // The wrapper was not signalled and no stop request was written.
    assert.ok(!existsSync(join(dir, "stop-request.json")));
    try {
      process.kill(m.pid, 0);
    } catch {
      assert.fail("session_shutdown must not stop the child");
    }
  } finally {
    // Clean up the detached child we started for this test.
    try {
      process.kill(-m.pgid, "SIGKILL");
    } catch {
      // already gone
    }
    await waitFor("wrapper to exit", () => {
      try {
        process.kill(m.pid, 0);
        return false;
      } catch {
        return true;
      }
    });
  }
});

const theme = { fg: (_c: string, s: string) => s, bg: (_c: string, s: string) => s, bold: (s: string) => s };

/** Stub UI ctx recording setStatus/notify and the component custom() was given. */
function uiCtx(root: string) {
  const status: (string | undefined)[] = [];
  const notes: string[] = [];
  const shown: any[] = [];
  const ctx = stubCtx(root, {
    hasUI: true,
    ui: {
      setStatus: (_k: string, v: string | undefined) => status.push(v),
      notify: (m: string) => notes.push(m),
      custom: async (factory: any, options: any) => {
        let closed = false;
        const c = factory({ requestRender() {}, terminal: { rows: 30 } }, theme, {}, () => (closed = true));
        shown.push({ c, options, closed: () => closed });
        c.handleInput("q");
        return undefined;
      },
    },
  });
  return { ctx, status, notes, shown };
}

test("registers ctrl+space and /agents", (t) => {
  clearSubagentEnv(t);
  const { pi, shortcuts, commands } = stubPi();
  piSub(pi);
  assert.equal(typeof shortcuts["ctrl+space"]?.handler, "function");
  assert.equal(typeof commands.agents?.handler, "function");
});

test("session_start sets the footer from this session's agents", (t) => {
  const root = sandbox(t);
  const { pi, handlers } = stubPi();
  piSub(pi);
  writeMeta(meta({ id: "20261014-100000-30f", pid: DEAD_PID }));
  mark("20261014-100000-30f", { exit: { ...exit("done"), ended_at: new Date().toISOString() } });
  const { ctx, status } = uiCtx(root);
  try {
    handlers.session_start({}, ctx);
    assert.match(status[status.length - 1] ?? "", /^subagents ●0 run ✓1 ✗0 ■0  ctrl\+space$/);
  } finally {
    handlers.session_shutdown({});
  }
});

test("the shortcut opens a centred overlay that q closes", async (t) => {
  const root = sandbox(t);
  const { pi, handlers, shortcuts } = stubPi();
  piSub(pi);
  const { ctx, shown } = uiCtx(root);
  try {
    handlers.session_start({}, ctx);
    await shortcuts["ctrl+space"].handler(ctx);
    assert.equal(shown.length, 1);
    assert.equal(shown[0].options.overlay, true);
    assert.equal(shown[0].options.overlayOptions.anchor, "center");
    assert.ok(shown[0].closed());
    assert.match(shown[0].c.render(100)[0], /Subagents · session sess-mai/);
  } finally {
    handlers.session_shutdown({});
  }
});

test("/agents adopt moves a handed-off session's agents here", async (t) => {
  const root = sandbox(t);
  const { pi, handlers, commands } = stubPi();
  piSub(pi);
  writeMeta(meta({ id: "20261014-100000-31h", owner_session: "sess-old", handoff_from: "sess-old" }));
  const { ctx, notes } = uiCtx(root);
  try {
    handlers.session_start({}, ctx);
    await commands.agents.handler("adopt sess-old", ctx);
    assert.match(notes.join("\n"), /Adopted 1 agent/);
    assert.equal(readMeta("20261014-100000-31h").owner_session, "sess-main");
    await commands.agents.handler("nope-id", ctx);
    assert.match(notes.join("\n"), /no agent nope-id/);
  } finally {
    handlers.session_shutdown({});
  }
});

test("resolvePath expands ~ and resolves the rest against the base", () => {
  assert.equal(resolvePath("/base", "~/wiki"), join(homedir(), "wiki"));
  assert.equal(resolvePath("/base", "~"), homedir());
  assert.equal(resolvePath("/base", "sub"), "/base/sub");
  assert.equal(resolvePath("/base", "/abs"), "/abs");
});
