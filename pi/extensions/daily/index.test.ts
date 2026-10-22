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
  runStateSection,
  systemMapSection,
} from "./index.ts";

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

test("refuses a newly ticked [x] with no evidence", () => {
  const { root, diary } = sandbox();
  const verdict = tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export");
  assert.ok(verdict);
  assert.match(verdict, /refusing to tick \[x\] without evidence/);
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
  const { root, diary, runState } = sandbox();
  writeFileSync(diary, PLAN.replace("**Today**", `**Today**\n${"- [ ] filler line to make the plan block huge\n".repeat(200)}`));
  const section = runStateSection()!;
  assert.ok(section && section.length <= 6000);
  assert.match(section, /## Run state/);
  assert.match(section, /export order settled/);
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
  daily({ on: (e: string, cb: (event: unknown, ctx: unknown) => unknown) => void (handlers[e] = cb), registerTool: () => {} } as never);
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
  daily({ on: (event: string, cb: (e: unknown, c: unknown) => unknown) => (handlers[event] = cb), registerTool: () => {} } as never);
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
  assert.match(seen[0], /diary guard blocked: .*ecfx-1001/);
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
    assert.match(lines[0], /^--harness pi --source daily-guard guard diary guard blocked: .*ecfx-1001/);
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
  const pi = {
    on: (e: string, cb: (event: unknown, ctx: unknown) => unknown) => void (handlers[e] = cb),
    registerTool: (tool: { name: string }) => void (tools[tool.name] = tool as never),
    sendMessage: (m: { content: string }, o?: { triggerTurn?: boolean }) => void sent.push({ content: m.content, triggerTurn: o?.triggerTurn }),
  };
  daily(pi as never);
  handlers.session_start?.({}, { sessionManager: { getSessionId: () => "sess-1" }, ui: { notify: () => {} } });
  const run = async (action: string) => (await tools.run_day_watch.execute("t", { action })).content[0].text;
  return { tools, handlers, sent, run };
}

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
  daily({ on: (e: string, cb: (event: unknown, ctx: unknown) => unknown) => void (handlers[e] = cb), registerTool: () => {} } as never);
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
  daily({ on: (e: string, cb: (event: unknown, ctx: unknown) => unknown) => void (handlers[e] = cb), registerTool: () => {} } as never);
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
