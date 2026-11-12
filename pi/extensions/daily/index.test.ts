import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import daily, {
  directionsSection,
  fitSections,
  guardVerdict,
  newlyNeedsYou,
  parseSuspendSample,
  runStateSection,
  systemMapSection,
} from "./index.ts";
import { DayWatcher } from "./watch.ts";
import type { WakeProbe } from "./watch.ts";
import { resumedBetween, WAKE_PREFIX } from "./mod/wake.ts";

const DAY = "2026-01-01";

const PLAN = [
  "# Thu Jan  1 09:00:00 +02 2026",
  "",
  "## Work",
  "",
  "<!-- start-day:start -->",
  "#### Plan",
  "",
  "**Today**",
  "- [ ] ecfx-1001 fix the export",
  "- [/] ecfx-1002 address review on backend !870",
  "<!-- start-day:end -->",
  "",
  "## Notes",
  "",
  "- my own line, never touched",
  "",
].join("\n");

const RUN_STATE = `# run-day ${DAY}
max_agents: 3
- ecfx-1001 | class=auto | agent=- | worktree=- | mr=- | retries=0 | needs_you=no | owner=main
notes:
  ecfx: export order settled
`;

function sandbox(opts: { runState?: boolean } = {}) {
  const root = mkdtempSync(join(tmpdir(), "daily-ext-"));
  const diary = join(root, "wiki", "diary", `${DAY}.md`);
  const stateDir = join(root, "state", "run-day");
  mkdirSync(join(root, "wiki", "diary"), { recursive: true });
  mkdirSync(join(stateDir, "inbox"), { recursive: true });
  writeFileSync(diary, PLAN);
  if (opts.runState !== false) writeFileSync(join(stateDir, `${DAY}.md`), RUN_STATE);
  process.env.RUN_DAY_STATE_DIR = stateDir;
  process.env.WIKI_DIR = join(root, "wiki");
  process.env.RUN_DAY_DATE = DAY;
  process.env.FRICTION_DIR = join(root, "friction"); // a real friction must never write into the user's log from a test
  return { root, diary, stateDir, runState: join(stateDir, `${DAY}.md`) };
}

function cleanup(root: string) {
  rmSync(root, { recursive: true, force: true });
  delete process.env.RUN_DAY_STATE_DIR;
  delete process.env.WIKI_DIR;
  delete process.env.RUN_DAY_DATE;
  delete process.env.FRICTION_DIR;
}

function tick(diary: string, oldText: string, newText: string, active = true) {
  return guardVerdict("edit", { path: diary, edits: [{ oldText, newText }] }, DAY, active);
}

test("new-format day: a tick needs a done entry in the agent file", () => {
  const { root, diary } = sandbox();
  const agent = join(root, "wiki", "diary", ".agent", `${DAY}.md`);
  mkdirSync(join(root, "wiki", "diary", ".agent"), { recursive: true });
  writeFileSync(agent, `# agent notes ${DAY}\n## ecfx-1001\n- 09:12 progress: working\n`);
  const refused = tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export");
  assert.ok(refused);
  assert.match(refused, /day-agent note/);
  writeFileSync(agent, `# agent notes ${DAY}\n## ecfx-1001\n- 11:40 done: merged abc1234\n`);
  assert.equal(tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export"), undefined);
  writeFileSync(agent, "");
  assert.ok(tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export"));
  cleanup(root);
});

test("refuses a newly ticked [x] with no evidence", () => {
  const { root, diary } = sandbox();
  const verdict = tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export");
  assert.ok(verdict);
  assert.match(verdict, /refusing to tick \[X\] without evidence/);
  assert.match(verdict, /ecfx-1001 fix the export/);
  cleanup(root);
});

test("accepts the same tick with an MR link, and with a note", () => {
  const { root, diary } = sandbox();
  assert.equal(
    tick(
      diary,
      "- [ ] ecfx-1001 fix the export",
      "- [x] ecfx-1001 fix the export · MR dashboard!2250  [↗][dashboard!2250]",
    ),
    undefined,
  );
  assert.equal(
    tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export · note: user confirmed"),
    undefined,
  );
  cleanup(root);
});

test("leaves an already ticked line and an in-progress change alone", () => {
  const { root, diary } = sandbox();
  assert.equal(tick(diary, "- [/] ecfx-1002", "- [x] ecfx-1002 · merged"), undefined);
  assert.equal(tick(diary, "- [ ] ecfx-1001 fix the export", "- [/] ecfx-1001 fix the export"), undefined);
  cleanup(root);
});

test("applies every edit of a multi-edit call before judging", () => {
  const { root, diary } = sandbox();
  const verdict = guardVerdict(
    "edit",
    {
      path: diary,
      edits: [
        { oldText: "- [ ] ecfx-1001 fix the export", newText: "- [x] ecfx-1001 fix the export · merged" },
        { oldText: "- [/] ecfx-1002", newText: "- [x] ecfx-1002" },
      ],
    },
    DAY,
    true,
  );
  assert.ok(verdict);
  assert.match(verdict, /ecfx-1002/);
  assert.doesNotMatch(verdict, /ecfx-1001/);
  cleanup(root);
});

test("passes through what is not its business", () => {
  const { root, diary } = sandbox();
  // oldText that does not match: the edit tool's own failure, not a tick.
  assert.equal(tick(diary, "- [ ] nope", "- [x] nope"), undefined);
  // another file, another tool, and no active run.
  assert.equal(tick(join(root, "wiki", "index.md"), "- [ ] a", "- [x] a"), undefined);
  assert.equal(guardVerdict("bash", { command: "rm -rf /" }, DAY, true), undefined);
  assert.equal(tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export", false), undefined);
  cleanup(root);
});

test("judges a whole-file write too", () => {
  const { root, diary } = sandbox();
  const bad = PLAN.replace("- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export");
  assert.ok(guardVerdict("write", { path: diary, content: bad }, DAY, true));
  cleanup(root);
});

test("injects the run state on every request, and stays silent with no run", () => {
  const { root, runState, stateDir } = sandbox();
  const section = runStateSection();
  assert.ok(section);
  assert.match(section, /A \/run-day session is active for 2026-01-01/);
  assert.match(section, /~\/\.pi\/agent\/prompts\/run-day\.md/);
  assert.match(section, /## Diary plan block/);
  assert.match(section, /ecfx-1002 address review/);
  assert.match(section, /## Run state/);
  assert.match(section, /export order settled/);
  assert.match(section, /subagents never write ~\/wiki, except ~\/wiki\/work\/system\/ and ~\/wiki\/tools\//);
  assert.ok(section && section.length <= 6000);

  writeFileSync(join(stateDir, "inbox", `20260101T080000-ECFX-1001-ab12.md`), "---\n---\n");
  writeFileSync(join(stateDir, "inbox", "notes.tmp"), "half written");
  assert.match(runStateSection()!, /1 pending inbox message\(s\)/);

  rmSync(runState);
  assert.equal(runStateSection(), null);
  cleanup(root);
});

test("trims the diary block before the run state", () => {
  const { root, diary } = sandbox();
  writeFileSync(diary, PLAN.replace("**Today**", `**Today**\n${"- [ ] filler line to make the plan block huge\n".repeat(200)}`));
  const section = runStateSection()!;
  assert.ok(section && section.length <= 6000);
  assert.match(section, /## Run state/);
  assert.match(section, /export order settled/);
  cleanup(root);
});

function writeAgent(root: string, text: string) {
  mkdirSync(join(root, "wiki", "diary", ".agent"), { recursive: true });
  writeFileSync(join(root, "wiki", "diary", ".agent", `${DAY}.md`), text);
}

test("injects the agent notes after the plan block, and nothing without an agent file", () => {
  const { root } = sandbox();
  const before = runStateSection()!;
  assert.doesNotMatch(before, /Agent notes/);
  writeAgent(root, `# agent notes ${DAY}\n## ecfx-1001\n- 09:12 progress: N1 fixed, pushed at 811e370a3\n`);
  const section = runStateSection()!;
  assert.match(section, /## Agent notes \(.*\.agent\/2026-01-01\.md\)\n# agent notes/);
  assert.match(section, /- 09:12 progress: N1 fixed/);
  assert.ok(section.indexOf("ecfx-1002 address review") < section.indexOf("## Agent notes"));
  assert.ok(section.indexOf("## Agent notes") < section.indexOf("## Run state"));
  assert.doesNotMatch(section, /agent notes truncated/);
  cleanup(root);
});

test("cuts a 10 KB agent file on a full line and keeps the plan block and run state whole", () => {
  const { root } = sandbox();
  const lines = Array.from({ length: 200 }, (_, i) => `- 10:00 note: agent entry number ${i + 1} with padding`);
  writeAgent(root, [`# agent notes ${DAY}`, ...lines].join("\n") + "\n");
  const section = runStateSection()!;
  assert.ok(section.length <= 6000);
  assert.match(section, /ecfx-1002 address review/);
  assert.match(section, /export order settled/);
  assert.match(section, /\n\[agent notes truncated: run day-agent show\]\n/);
  assert.match(section, /agent entry number 1 /);
  assert.doesNotMatch(section, /agent entry number 200/);
  const body = section.slice(section.indexOf("## Agent notes"), section.indexOf("\n\n## Run state"));
  const entries = body.split("\n").filter((l) => l.startsWith("- 10:00"));
  assert.ok(entries.every((l) => /with padding$/.test(l)));
  assert.ok(body.length <= 2200);
  cleanup(root);
});

test("multibyte characters at the agent-notes cut stay whole", () => {
  const { root } = sandbox();
  const lines = Array.from({ length: 200 }, (_, i) => `- 10:00 note: ·↗·↗·↗·↗·↗·↗ entry ${i + 1} ↗·↗·↗·↗·↗·↗·`);
  writeAgent(root, [`# agent notes ${DAY}`, ...lines].join("\n") + "\n");
  const section = runStateSection()!;
  assert.match(section, /\n\[agent notes truncated: run day-agent show\]\n/);
  const entries = section.split("\n").filter((l) => l.startsWith("- 10:00"));
  assert.ok(entries.length > 0);
  assert.ok(entries.every((l) => /^- 10:00 note: ·↗·↗·↗·↗·↗·↗ entry \d+ ↗·↗·↗·↗·↗·↗·$/.test(l)));
  assert.doesNotMatch(section, /\uFFFD/);
  cleanup(root);
});

test("agent notes get only what the budget leaves, down to the marker", () => {
  const { root, runState } = sandbox();
  const base = runStateSection()!.length;
  writeAgent(root, `# agent notes ${DAY}\n` + "- 10:00 note: x\n".repeat(100));
  writeFileSync(runState, RUN_STATE + `pad: ${"x".repeat(5950 - base)}\n`);
  const section = runStateSection()!;
  assert.ok(section.length <= 6000);
  assert.match(section, /pad: xxxxxxxxxx/);
  assert.match(section, /\n\[agent notes truncated: run day-agent show\]\n/);
  assert.doesNotMatch(section, /- 10:00 note/);
  cleanup(root);
});

test("announces needs_you once per key", () => {
  const { root } = sandbox();
  const one = RUN_STATE.replace("needs_you=no", "needs_you=yes");
  assert.deepEqual(newlyNeedsYou(one), ["ecfx-1001"]);
  assert.deepEqual(newlyNeedsYou(one), []);
  cleanup(root);
});

test("registers both handlers and blocks only on a bad tick", () => {
  const { root, diary, runState } = sandbox();
  const handlers: Record<string, (event: unknown, ctx: unknown) => unknown> = {};
  daily({
    on(event: string, callback: (event: unknown, ctx: unknown) => unknown) {
      handlers[event] = callback;
    },
    registerTool() {},
    registerCommand() {},
    registerEntryRenderer() {},
  } as never);
  assert.ok(handlers.before_agent_start);
  assert.ok(handlers.tool_call);

  const options = { sections: { rules: "Keep" } as Record<string, string> };
  handlers.before_agent_start({ systemPromptOptions: options }, { ui: undefined });
  assert.equal(options.sections.rules, "Keep");
  assert.match(options.sections.daily_run_state, /run-day session is active/);

  const blocked = handlers.tool_call(
    { toolName: "edit", input: { path: diary, edits: [{ oldText: "- [ ] ecfx-1001 fix the export", newText: "- [x] ecfx-1001 fix the export" }] } },
    {},
  ) as { block: boolean; reason: string };
  assert.equal(blocked.block, true);
  assert.match(blocked.reason, /without evidence/);

  assert.equal(handlers.tool_call({ toolName: "read", input: { path: diary } }, {}), undefined);

  // No active run: no section is set (pi diffs sections by name, so it disappears)
  // and the guard stands down.
  rmSync(runState);
  const next = { sections: {} as Record<string, string> };
  handlers.before_agent_start({ systemPromptOptions: next }, { ui: undefined });
  assert.equal(next.sections.daily_run_state, undefined);
  assert.equal(
    handlers.tool_call(
      { toolName: "edit", input: { path: diary, edits: [{ oldText: "- [/] ecfx-1002", newText: "- [x] ecfx-1002" }] } },
      {},
    ),
    undefined,
  );
  cleanup(root);
});

function directionsSandbox(script: string) {
  const root = mkdtempSync(join(tmpdir(), "daily-dir-"));
  mkdirSync(join(root, "friction"), { recursive: true });
  const file = join(root, "friction", "directions.md");
  const bin = join(root, "friction-ledger");
  const counter = join(root, "calls");
  writeFileSync(bin, script.replaceAll("$COUNTER", counter));
  chmodSync(bin, 0o755);
  process.env.FRICTION_WIKI = join(root, "friction");
  process.env.FRICTION_LEDGER_BIN = bin;
  return { root, file, bin, counter };
}

function directionsCleanup(root: string) {
  rmSync(root, { recursive: true, force: true });
  delete process.env.FRICTION_WIKI;
  delete process.env.FRICTION_LEDGER_BIN;
}

const calls = (counter: string) => (existsSync(counter) ? readFileSync(counter, "utf8").split("\n").filter(Boolean).length : 0);

test("directions: injects the rendered rules, cached until the file changes", () => {
  const { root, file, counter } = directionsSandbox('#!/bin/sh\necho x >> "$COUNTER"\ncat "$(dirname "$0")/friction/directions.md"\n');
  writeFileSync(file, "- rule one\n");
  const first = directionsSection();
  assert.match(first ?? "", /^## Standing directions\n/);
  assert.match(first ?? "", /- rule one/);
  directionsSection();
  directionsSection();
  assert.equal(calls(counter), 1, "cached across requests");
  writeFileSync(file, "- rule two\n");
  utimesSync(file, new Date(Date.now() + 5000), new Date(Date.now() + 5000));
  assert.match(directionsSection() ?? "", /- rule two/);
  assert.equal(calls(counter), 2, "re-read after the mtime changed");
  directionsCleanup(root);
});

test("directions: missing file, missing script or failing script inject nothing", () => {
  const { root, file, bin } = directionsSandbox("#!/bin/sh\necho '- r'\n");
  assert.equal(directionsSection(), null, "no directions file");
  writeFileSync(file, "x");
  rmSync(bin);
  assert.equal(directionsSection(), null, "no script");
  writeFileSync(bin, "#!/bin/sh\nexit 3\n");
  chmodSync(bin, 0o755);
  utimesSync(file, new Date(Date.now() + 9000), new Date(Date.now() + 9000));
  assert.equal(directionsSection(), null, "failing script");
  writeFileSync(bin, "#!/bin/sh\n:\n");
  utimesSync(file, new Date(Date.now() + 12000), new Date(Date.now() + 12000));
  assert.equal(directionsSection(), null, "empty render");
  directionsCleanup(root);
});

test("directions: before_agent_start sets the section, and never throws without one", () => {
  const { root, file } = directionsSandbox("#!/bin/sh\necho '- never retry with the model'\n");
  const handlers: Record<string, (event: unknown, ctx: unknown) => unknown> = {};
  daily({ on: (e: string, cb: (event: unknown, ctx: unknown) => unknown) => void (handlers[e] = cb), registerTool: () => {}, registerCommand: () => {}, registerEntryRenderer: () => {} } as never);
  writeFileSync(file, "x");
  const options = { sections: {} as Record<string, string> };
  handlers.before_agent_start({ systemPromptOptions: options }, { ui: undefined });
  assert.match(options.sections.standing_directions, /never retry with the model/);
  rmSync(file);
  const next = { sections: {} as Record<string, string> };
  assert.doesNotThrow(() => handlers.before_agent_start({ systemPromptOptions: next }, { ui: undefined }));
  assert.equal(next.sections.standing_directions, undefined);
  directionsCleanup(root);
});

/** A `friction` on PATH that records its argv, one line per call; exits `code`. */
function fakeFriction(root: string, code = 0) {
  const bin = join(root, "bin");
  const log = join(root, "friction.log");
  mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, "friction"), `#!/bin/sh\nprintf '%s\\n' "$*" >> "${log}"\nexit ${code}\n`);
  chmodSync(join(bin, "friction"), 0o755);
  return { bin, log };
}

async function waitFor(path: string) {
  for (let i = 0; i < 100 && !existsSync(path); i++) await new Promise((r) => setTimeout(r, 20));
}

function blockedTick(diary: string) {
  const handlers: Record<string, (event: unknown, ctx: unknown) => unknown> = {};
  daily({ on: (event: string, cb: (e: unknown, c: unknown) => unknown) => (handlers[event] = cb), registerTool: () => {}, registerCommand: () => {}, registerEntryRenderer: () => {} } as never);
  return handlers.tool_call(
    { toolName: "edit", input: { path: diary, edits: [{ oldText: "- [ ] ecfx-1001 fix the export", newText: "- [x] ecfx-1001 fix the export" }] } },
    {},
  ) as { block: boolean; reason: string };
}

test("guardVerdict reports a block through onBlock and stays quiet otherwise", () => {
  const { root, diary } = sandbox();
  const seen: string[] = [];
  const edit = (from: string, to: string) =>
    guardVerdict("edit", { path: diary, edits: [{ oldText: from, newText: to }] }, DAY, true, (m) => seen.push(m));
  assert.ok(edit("- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export"));
  assert.equal(seen.length, 1);
  assert.match(seen[0], /diary guard blocked \[[^\]]+\]: .*ecfx-1001/);
  assert.equal(edit("- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export · merged"), undefined);
  assert.equal(seen.length, 1);
  cleanup(root);
});

test("a blocked tick records a guard friction event for pi", async () => {
  const { root, diary } = sandbox();
  const { bin, log } = fakeFriction(root);
  const path = process.env.PATH;
  process.env.PATH = `${bin}:${path}`;
  try {
    const blocked = blockedTick(diary);
    assert.equal(blocked.block, true);
    await waitFor(log);
    const lines = readFileSync(log, "utf8").trim().split("\n");
    assert.equal(lines.length, 1);
    assert.match(lines[0], /^--harness pi --source daily-guard guard diary guard blocked \[[^\]]+\]: .*ecfx-1001/);
  } finally {
    process.env.PATH = path;
    cleanup(root);
  }
});

test("a failing or missing friction leaves the block verdict unchanged", async () => {
  const { root, diary } = sandbox();
  const expected = blockedTick(diary);
  const { bin, log } = fakeFriction(root, 1);
  const path = process.env.PATH;
  try {
    process.env.PATH = `${bin}:${path}`;
    assert.deepEqual(blockedTick(diary), expected);
    await waitFor(log);
    process.env.PATH = join(root, "nowhere");
    assert.deepEqual(blockedTick(diary), expected);
    assert.equal(expected.block, true);
  } finally {
    process.env.PATH = path;
    cleanup(root);
  }
});

/** A pi stand-in that keeps the registered tools, handlers and sent messages. */
function fakePi() {
  const tools: Record<string, { execute: (id: string, params: unknown) => Promise<{ content: { text: string }[] }> }> = {};
  const handlers: Record<string, (event: unknown, ctx: unknown) => unknown> = {};
  const sent: { content: string; triggerTurn?: boolean }[] = [];
  const commands: Record<string, { handler: (args: string, ctx: unknown) => Promise<void> }> = {};
  const userMessages: { content: string; expand?: boolean }[] = [];
  const pi = {
    on: (e: string, cb: (event: unknown, ctx: unknown) => unknown) => void (handlers[e] = cb),
    registerTool: (tool: { name: string }) => void (tools[tool.name] = tool as never),
    registerCommand: (name: string, options: never) => void (commands[name] = options),
    registerEntryRenderer: () => {},
    sendMessage: (m: { content: string }, o?: { triggerTurn?: boolean }) => void sent.push({ content: m.content, triggerTurn: o?.triggerTurn }),
    sendUserMessage: (content: string, o?: { expandPromptTemplates?: boolean }) => void userMessages.push({ content, expand: o?.expandPromptTemplates }),
  };
  daily(pi as never);
  handlers.session_start?.({}, ctxFor("sess-1"));
  const run = async (action: string) => (await tools.run_day_watch.execute("t", { action })).content[0].text;
  return { tools, handlers, sent, run, commands, userMessages };
}

const ctxFor = (session: string) => ({ sessionManager: { getSessionId: () => session }, ui: { notify: () => {} } });

/** A dotfiles checkout with the files the pi playbook print reads. */
function fakeDotfiles(root: string, playbook = "# /run-day\n") {
  const top = join(root, "dotfiles");
  mkdirSync(join(top, "pi", "prompts"), { recursive: true });
  mkdirSync(join(top, "claude", "daily", "templates"), { recursive: true });
  writeFileSync(join(top, "pi", "prompts", "run-day.md"), playbook);
  writeFileSync(join(top, "claude", "daily", "templates", "ticket-brief.md"), "brief\n");
  process.env.DOTFILES_DIR = top;
  return top;
}

test("run_day_watch start records the playbook the day runs with", async () => {
  const { root, stateDir } = sandbox();
  fakeDotfiles(root);
  const { run } = fakePi();
  await run("start");
  assert.match(readFileSync(join(stateDir, `${DAY}.pi-playbook`), "utf8"), /^[0-9a-f]{8}\n$/);
  assert.ok(!existsSync(join(stateDir, `${DAY}.playbook`)), "Claude's record is left alone: the prints differ by harness");
  await run("stop");
  delete process.env.DOTFILES_DIR;
  cleanup(root);
});

test("/daily-update reloads, and the reloaded extension resumes the day in the same session", async () => {
  const { root, stateDir } = sandbox();
  const before = fakePi();
  let reloaded = 0;
  await before.commands["daily-update"].handler("", { ...ctxFor("sess-1"), reload: async () => void reloaded++ });
  assert.equal(reloaded, 1);
  assert.ok(existsSync(join(stateDir, `${DAY}.pi-resume`)), "marker left for the reloaded extension");
  const after = fakePi();
  await after.handlers.session_start({ type: "session_start", reason: "reload" }, ctxFor("sess-1"));
  assert.deepEqual(after.userMessages, [{ content: "/run-day resume updated", expand: true }]);
  assert.ok(!existsSync(join(stateDir, `${DAY}.pi-resume`)), "marker consumed");
  await after.handlers.session_start({ type: "session_start", reason: "reload" }, ctxFor("sess-1"));
  assert.equal(after.userMessages.length, 1, "resumes once");
  cleanup(root);
});

test("no resume on a plain start, or for another session's marker", async () => {
  const { root, stateDir } = sandbox();
  writeFileSync(join(stateDir, `${DAY}.pi-resume`), "sess-1\n");
  const a = fakePi();
  await a.handlers.session_start({ type: "session_start", reason: "startup" }, ctxFor("sess-1"));
  assert.deepEqual(a.userMessages, []);
  const b = fakePi();
  await b.handlers.session_start({ type: "session_start", reason: "reload" }, ctxFor("sess-2"));
  assert.deepEqual(b.userMessages, []);
  cleanup(root);
});

test("run_day_watch: starts with a run state, holds the lock, stops and releases it", async () => {
  const { root, stateDir } = sandbox();
  const { run, handlers } = fakePi();
  const lock = join(stateDir, "watch.lock");
  assert.match(await run("start"), /watching/i);
  assert.ok(existsSync(lock), "lock written");
  assert.match(await run("status"), /watching/i);
  assert.match(await run("start"), /already watching|watching/i, "a second start in the same session is harmless");
  assert.match(await run("stop"), /stopped/i);
  assert.ok(!existsSync(lock), "lock released");
  assert.match(await run("status"), /not watching/i);
  await run("start");
  handlers.session_shutdown?.({}, {});
  assert.ok(!existsSync(lock), "shutdown releases the lock");
  cleanup(root);
});

test("run_day_watch: refuses to start without today's run state", async () => {
  const { root, stateDir } = sandbox({ runState: false });
  const { run } = fakePi();
  assert.match(await run("start"), /no run state/i);
  assert.ok(!existsSync(join(stateDir, "watch.lock")));
  cleanup(root);
});

test("run_day_watch: refuses while another live process holds the lock", async () => {
  const { root, stateDir } = sandbox();
  writeFileSync(join(stateDir, "watch.lock"), JSON.stringify({ pid: process.ppid, session: "other" }));
  const { run } = fakePi();
  assert.match(await run("start"), /other/);
  cleanup(root);
});

function mapSandbox() {
  const root = mkdtempSync(join(tmpdir(), "daily-map-"));
  const file = join(root, "map.md");
  process.env.SYSTEM_MAP = file;
  return { root, file };
}

test("system map: injected under its heading, cached until the mtime changes", () => {
  const { root, file } = mapSandbox();
  const t0 = new Date(Date.now() - 60000);
  writeFileSync(file, "- run-day: the daily plan\n");
  utimesSync(file, t0, t0);
  const first = systemMapSection();
  assert.match(first ?? "", /^## System map\n/);
  assert.match(first ?? "", /- run-day:/);
  writeFileSync(file, "- other: changed\n");
  utimesSync(file, t0, t0);
  assert.match(systemMapSection() ?? "", /- run-day:/, "cached while the mtime is unchanged");
  utimesSync(file, new Date(Date.now() + 5000), new Date(Date.now() + 5000));
  assert.match(systemMapSection() ?? "", /- other: changed/);
  rmSync(root, { recursive: true, force: true });
  delete process.env.SYSTEM_MAP;
});

test("system map: the map's own # title is dropped under the ## System map heading", () => {
  const { root, file } = mapSandbox();
  writeFileSync(file, "# System map\nPages: here\n- run-day: the daily plan\n");
  utimesSync(file, new Date(Date.now() + 15000), new Date(Date.now() + 15000));
  assert.equal(systemMapSection(), "## System map\nPages: here\n- run-day: the daily plan\n");
  writeFileSync(file, "# System map\n");
  utimesSync(file, new Date(Date.now() + 18000), new Date(Date.now() + 18000));
  assert.equal(systemMapSection(), null, "a title alone is no map");
  rmSync(root, { recursive: true, force: true });
  delete process.env.SYSTEM_MAP;
});

test("system map: missing, empty or unreadable file injects nothing; over-budget is cut", () => {
  const { root, file } = mapSandbox();
  assert.equal(systemMapSection(), null, "missing");
  writeFileSync(file, "\n");
  utimesSync(file, new Date(Date.now() + 9000), new Date(Date.now() + 9000));
  assert.equal(systemMapSection(), null, "empty");
  writeFileSync(file, Array.from({ length: 400 }, (_, i) => `- part ${i}: é description padding`).join("\n"));
  utimesSync(file, new Date(Date.now() + 12000), new Date(Date.now() + 12000));
  const text = systemMapSection() ?? "";
  const body = text.slice("## System map\n".length);
  assert.ok(Buffer.byteLength(body) <= 3072 && Buffer.byteLength(body) > 100, `cut to 3072 bytes, got ${Buffer.byteLength(body)}`);
  assert.ok(!body.includes("\uFFFD"), "no split character");
  rmSync(file);
  mkdirSync(file);
  assert.equal(systemMapSection(), null, "a directory is no map");
  rmSync(root, { recursive: true, force: true });
  delete process.env.SYSTEM_MAP;
});

test("system map: without SYSTEM_MAP, read from WIKI_DIR/work/system/map.md", () => {
  const root = mkdtempSync(join(tmpdir(), "daily-map-wiki-"));
  mkdirSync(join(root, "work", "system"), { recursive: true });
  writeFileSync(join(root, "work", "system", "map.md"), "- from-wiki-dir: the map\n");
  delete process.env.SYSTEM_MAP;
  process.env.WIKI_DIR = root;
  assert.match(systemMapSection() ?? "", /- from-wiki-dir:/);
  process.env.SYSTEM_MAP = join(root, "override.md");
  writeFileSync(process.env.SYSTEM_MAP, "- override: wins\n");
  assert.match(systemMapSection() ?? "", /- override: wins/, "SYSTEM_MAP still wins");
  delete process.env.SYSTEM_MAP;
  delete process.env.WIKI_DIR;
  rmSync(root, { recursive: true, force: true });
});

test("total cap: run state whole, then the map, then the directions, within 9000 characters", () => {
  const run = "r".repeat(6000);
  const map = `## System map\n${"m".repeat(3000)}`;
  const dirs = `## Standing directions\n${"d".repeat(7000)}`;
  const total = (s: { runState: string | null; directions: string | null; systemMap: string | null }) =>
    (s.runState ?? "").length + (s.directions ?? "").length + (s.systemMap ?? "").length;

  const all = fitSections(run, dirs, map);
  assert.equal(all.runState, run, "the run state is never cut");
  assert.ok(total(all) <= 9000, `total ${total(all)}`);
  assert.equal(all.directions, null, "the directions go first");
  assert.match(all.systemMap ?? "", /^## System map\nm+\n\(cut\)$/, "then the map is cut, and marked");

  const noRun = fitSections(null, dirs, map);
  assert.equal(noRun.systemMap, map, "without a run the map fits whole");
  assert.match(noRun.directions ?? "", /^## Standing directions\nd+\n\(cut\)$/, "and the directions are cut, marked");
  assert.ok(total(noRun) <= 9000, `total ${total(noRun)}`);

  const small = fitSections("r", "## Standing directions\nd", map);
  assert.deepEqual(small, { runState: "r", directions: "## Standing directions\nd", systemMap: map }, "small inputs pass through");
});

test("total cap: before_agent_start keeps the three sections within 9000 characters", () => {
  const { root, runState } = sandbox();
  writeFileSync(runState, RUN_STATE + "- ecfx-9 | class=auto | needs_you=no | padding padding padding\n".repeat(120));
  const map = join(root, "map.md");
  writeFileSync(map, "- part: padding padding padding padding\n".repeat(80));
  process.env.SYSTEM_MAP = map;
  const ledger = join(root, "ledger");
  writeFileSync(ledger, '#!/bin/sh\ni=1; while [ $i -le 300 ]; do echo "- direction $i: always follow this rule"; i=$((i+1)); done\n');
  chmodSync(ledger, 0o755);
  mkdirSync(join(root, "friction"), { recursive: true });
  writeFileSync(join(root, "friction", "directions.md"), "x");
  process.env.FRICTION_WIKI = join(root, "friction");
  process.env.FRICTION_LEDGER_BIN = ledger;
  const handlers: Record<string, (event: unknown, ctx: unknown) => unknown> = {};
  daily({ on: (e: string, cb: (event: unknown, ctx: unknown) => unknown) => void (handlers[e] = cb), registerTool: () => {}, registerCommand: () => {}, registerEntryRenderer: () => {} } as never);
  const options = { sections: {} as Record<string, string> };
  handlers.before_agent_start({ systemPromptOptions: options }, { ui: undefined });
  const s = options.sections;
  const total = (s.daily_run_state ?? "").length + (s.standing_directions ?? "").length + (s.system_map ?? "").length;
  assert.ok(s.daily_run_state && s.system_map, "run state and map are set");
  assert.ok(total <= 9000, `total ${total}`);
  delete process.env.SYSTEM_MAP;
  delete process.env.FRICTION_WIKI;
  delete process.env.FRICTION_LEDGER_BIN;
  cleanup(root);
});

test("system map: before_agent_start sets the section, and never throws without one", () => {
  const { root, file } = mapSandbox();
  const handlers: Record<string, (event: unknown, ctx: unknown) => unknown> = {};
  daily({ on: (e: string, cb: (event: unknown, ctx: unknown) => unknown) => void (handlers[e] = cb), registerTool: () => {}, registerCommand: () => {}, registerEntryRenderer: () => {} } as never);
  writeFileSync(file, "- run-day: the daily plan\n");
  const options = { sections: {} as Record<string, string> };
  handlers.before_agent_start({ systemPromptOptions: options }, { ui: undefined });
  assert.match(options.sections.system_map, /- run-day:/);
  rmSync(file);
  const next = { sections: {} as Record<string, string> };
  assert.doesNotThrow(() => handlers.before_agent_start({ systemPromptOptions: next }, { ui: undefined }));
  assert.equal(next.sections.system_map, undefined);
  rmSync(root, { recursive: true, force: true });
  delete process.env.SYSTEM_MAP;
});
// Sleep and wake (watch.ts checkWake): the probes are faked at the dep boundary, so nothing here
// reads /proc, sleeps, or runs ioreg. CLOCK_BOOTTIME and CLOCK_MONOTONIC are the probe's business.
const SUSPEND_MS = 95 * 60_000; // a sleep long enough for the watcher's 60 s gap
const GAP = 61_000; // a tick late enough to count as a sleep

type Probe = (needed: boolean) => Promise<WakeProbe>;

const WATCH_STATE = `# run-day ${DAY}
max_agents: 3
- ecfx-1001 | class=auto | agent=a1b2c3 | worktree=- | mr=- | retries=0 | needs_you=no | owner=main
- ecfx-1002 | class=auto | agent=- | worktree=- | mr=- | retries=0 | needs_you=no | owner=main
`;

function wakeRig(probe: Probe, opts: { state?: string; inbox?: string[] } = {}) {
  const box = sandbox();
  writeFileSync(box.runState, opts.state ?? WATCH_STATE);
  const wakes: string[] = [];
  const notes: string[] = [];
  const notifies: string[] = [];
  const watcher = new DayWatcher({
    paths: () => ({ runState: box.runState, diary: box.diary, playbook: join(box.stateDir, `${DAY}.playbook`) }),
    changes: async () => ({ code: 0, stdout: "", stderr: "" }),
    listInbox: () => opts.inbox ?? [],
    holdsLock: () => true,
    probe,
    wake: (text) => wakes.push(text),
    note: (text) => notes.push(text),
    notify: (message) => notifies.push(message),
    friction: () => {},
  });
  return { box, watcher, wakes, notes, notifies };
}

/** Linux: the verdict the sample would give, driven by the test. */
function linuxProbe(state: { resumed: boolean; sampled: boolean }): Probe {
  return async () => ({ platform: "linux", resumed: state.resumed, sampled: state.sampled, lid: "", systemstate: "" });
}

/** macOS: the raw ioreg and pmset output for a fake world, read on every probe. */
function macProbe(world: { lid: "open" | "closed" | null; graphics: boolean | null }): Probe {
  return async () => ({
    platform: "darwin",
    resumed: false,
    sampled: true,
    lid: world.lid === null ? "" : `"AppleClamshellState" = ${world.lid === "closed" ? "Yes" : "No"}`,
    systemstate: world.graphics === null ? "" : `Current System Capabilities are: ${world.graphics ? "Graphics" : "Sleep"}`,
  });
}

test("wake: a Linux resume between ticks nudges once, with the wake prefix", async () => {
  const state = { resumed: false, sampled: true };
  const rig = wakeRig(linuxProbe(state));
  assert.equal(await rig.watcher.checkWake(1_000_000), null); // the first tick has no sample to compare
  state.resumed = true;
  assert.equal(
    await rig.watcher.checkWake(1_000_000 + SUSPEND_MS),
    `${WAKE_PREFIX} woke after 95 min: run the Wake check of /run-day (section 10).`,
  );
  state.resumed = false;
  assert.equal(await rig.watcher.checkWake(1_000_000 + SUSPEND_MS + 30_000), null); // once per sleep
  assert.deepEqual(rig.notifies, []);
  assert.deepEqual(rig.wakes, []); // the nudge is returned for the caller to send, not pushed
  cleanup(rig.box.root);
});

test("wake: a Linux gap with no suspend (only CLOCK_MONOTONIC moved) does not nudge", async () => {
  const rig = wakeRig(linuxProbe({ resumed: false, sampled: true }));
  assert.equal(await rig.watcher.checkWake(0), null);
  assert.equal(await rig.watcher.checkWake(SUSPEND_MS), null);
  assert.deepEqual(rig.notifies, []);
  cleanup(rig.box.root);
});

test("wake: an unreadable Linux sample gives up after three blind probes, with one notice", async () => {
  const rig = wakeRig(linuxProbe({ resumed: false, sampled: false }));
  assert.equal(await rig.watcher.checkWake(0), null);
  let t = SUSPEND_MS;
  assert.equal(await rig.watcher.checkWake(t), null);
  assert.equal(await rig.watcher.checkWake((t += GAP)), null);
  assert.deepEqual(rig.notifies, []);
  assert.equal(await rig.watcher.checkWake((t += GAP)), null);
  assert.deepEqual(rig.notifies, ["daily wake: cannot read the suspend sample; no wake nudge for this sleep"]);
  assert.equal(await rig.watcher.checkWake((t += 1_000)), null); // no gap, no probe
  assert.equal(rig.notifies.length, 1);
  cleanup(rig.box.root);
});

test("wake: a Linux resume needs neither lid nor display and spends no blind probe", async () => {
  const state = { resumed: false, sampled: false };
  const rig = wakeRig(linuxProbe(state));
  assert.equal(await rig.watcher.checkWake(0), null);
  assert.equal(await rig.watcher.checkWake(GAP), null); // blind probe 1 of 3
  state.resumed = true;
  state.sampled = true;
  assert.match(String(await rig.watcher.checkWake(2 * GAP)), new RegExp(`^\\${WAKE_PREFIX} woke after`));
  state.resumed = false;
  state.sampled = false;
  assert.equal(await rig.watcher.checkWake(3 * GAP), null); // a fresh allowance: the resume reset it
  assert.deepEqual(rig.notifies, []);
  cleanup(rig.box.root);
});

test("wake: macOS lid closed with the display off is not a full wake, and the sleep survives", async () => {
  const world = { lid: "closed" as "open" | "closed" | null, graphics: null as boolean | null };
  const rig = wakeRig(macProbe(world));
  assert.equal(await rig.watcher.checkWake(0), null);
  assert.equal(await rig.watcher.checkWake(SUSPEND_MS), null);
  world.graphics = true; // clamshell mode: the display decides, not the lid
  // 95 min for the gap plus the 30 s tick: the sleep is recorded from the last tick before it
  assert.match(String(await rig.watcher.checkWake(SUSPEND_MS + 30_000)), /^\[daily-wake\] woke after 96 min:/);
  assert.deepEqual(rig.notifies, []);
  cleanup(rig.box.root);
});

test("wake: macOS with the lid open and the display on still nudges", async () => {
  const rig = wakeRig(macProbe({ lid: "open", graphics: true }));
  assert.equal(await rig.watcher.checkWake(0), null);
  assert.match(String(await rig.watcher.checkWake(SUSPEND_MS)), /^\[daily-wake\] woke after 95 min:/);
  cleanup(rig.box.root);
});

test("wake: macOS reading neither lid nor display gives up after three blind probes", async () => {
  const rig = wakeRig(macProbe({ lid: null, graphics: null }));
  assert.equal(await rig.watcher.checkWake(0), null);
  let t = SUSPEND_MS;
  assert.equal(await rig.watcher.checkWake(t), null);
  assert.equal(await rig.watcher.checkWake((t += GAP)), null);
  assert.equal(await rig.watcher.checkWake((t += GAP)), null);
  assert.deepEqual(rig.notifies, ["daily wake: cannot read lid or display state; no wake nudge for this sleep"]);
  cleanup(rig.box.root);
});

test("wake: a platform with no probe gives up on the sleep, with one notice", async () => {
  const rig = wakeRig(async () => ({ platform: "unsupported", resumed: false, sampled: false, lid: "", systemstate: "" }));
  assert.equal(await rig.watcher.checkWake(0), null);
  assert.equal(await rig.watcher.checkWake(SUSPEND_MS), null);
  assert.deepEqual(rig.notifies, ["daily wake: no supported wake probe; no wake nudge for this sleep"]);
  cleanup(rig.box.root);
});

test("wake: a resume nudges only with an agent outstanding or an inbox message", async () => {
  const idle = WATCH_STATE.replace("agent=a1b2c3", "agent=-");
  const quiet = { resumed: false, sampled: true };
  const noWork = wakeRig(linuxProbe(quiet), { state: idle });
  assert.equal(await noWork.watcher.checkWake(0), null);
  quiet.resumed = true;
  assert.equal(await noWork.watcher.checkWake(SUSPEND_MS), null); // nothing to wake for
  cleanup(noWork.box.root);

  const mail = { resumed: false, sampled: true };
  const withInbox = wakeRig(linuxProbe(mail), { state: idle, inbox: ["20260101T090000-ecfx-1001-abcd.md"] });
  assert.equal(await withInbox.watcher.checkWake(0), null);
  mail.resumed = true;
  assert.match(String(await withInbox.watcher.checkWake(SUSPEND_MS)), /^\[daily-wake\] woke after 95 min:/);
  cleanup(withInbox.box.root);
});

test("wake: the suspend sample is validated, and mod/wake.ts judges a resume per boot", () => {
  assert.deepEqual(parseSuspendSample('{"bootId":"b1","bootMs":1000,"monotonicMs":1000}'), { bootId: "b1", bootMs: 1000, monotonicMs: 1000 });
  assert.equal(parseSuspendSample(""), null);
  assert.equal(parseSuspendSample("not json"), null);
  assert.equal(parseSuspendSample('{"bootId":"","bootMs":1,"monotonicMs":1}'), null);
  assert.equal(parseSuspendSample('{"bootId":"b1","bootMs":"1","monotonicMs":1}'), null);
  assert.equal(parseSuspendSample('{"bootId":"b1","bootMs":null,"monotonicMs":1}'), null);

  const before = parseSuspendSample('{"bootId":"b1","bootMs":1000,"monotonicMs":1000}');
  const suspended = parseSuspendSample('{"bootId":"b1","bootMs":60000,"monotonicMs":1000}');
  const idle = parseSuspendSample('{"bootId":"b1","bootMs":2000,"monotonicMs":2000}');
  const rebooted = parseSuspendSample('{"bootId":"b2","bootMs":5000,"monotonicMs":5000}');
  assert.equal(resumedBetween(before, suspended), true); // CLOCK_BOOTTIME ran on alone
  assert.equal(resumedBetween(before, idle), false); // both clocks ran
  assert.equal(resumedBetween(before, rebooted), false); // a reboot is not a resume
  assert.equal(resumedBetween(null, suspended), false); // a missing sample fails closed
  assert.equal(resumedBetween(before, null), false);
});
